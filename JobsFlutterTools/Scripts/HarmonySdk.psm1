# HarmonySdk.psm1 | JobsFlutterTools
# Created by Jobs on 2026年10月23日，星期五.
# 项目级 OpenHarmony Flutter 缓存与 FVM 绑定；不改全局 SDK 或环境。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:HarmonyRepository = 'https://gitcode.com/CPF-Flutter/flutter_flutter.git'
$script:HarmonyManager = Import-Module (Join-Path $PSScriptRoot 'Actions/sdk-manage/Scripts/Action.psm1') -PassThru -DisableNameChecking

function Invoke-JobsHarmonyGit {
    param([string]$Git, [string[]]$Arguments, [string]$Directory, [int]$TimeoutSeconds = 120)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Git
    $quoted = & $script:HarmonyManager { param($Values) @($Values | ForEach-Object { Quote-JobsArgument $_ }) -join ' ' } $Arguments
    $start.Arguments = '-c http.lowSpeedLimit=1024 -c http.lowSpeedTime=60 ' + $quoted
    $start.WorkingDirectory = $Directory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $start.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    $start.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'
    foreach ($key in @('GIT_DIR','GIT_WORK_TREE','GIT_COMMON_DIR','GIT_INDEX_FILE','GIT_OBJECT_DIRECTORY','GIT_ALTERNATE_OBJECT_DIRECTORIES')) { $start.EnvironmentVariables.Remove($key) }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw '无法启动 Git。' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
                & (Join-Path ([Environment]::GetFolderPath('System')) 'taskkill.exe') /PID $process.Id /T /F | Out-Null
            } else { $process.Kill() }
            throw 'Git 超时，已停止本次下载；缓存现场保留。'
        }
        if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout, $stderr), 5000)) { throw 'Git 输出管道未关闭。' }
        $output = $stdout.GetAwaiter().GetResult()
        $errors = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw ('Git 失败（' + $process.ExitCode + '）：' + $errors.Trim()) }
        return $output.TrimEnd("`r", "`n")
    } finally { $process.Dispose() }
}

function ConvertFrom-JobsHarmonyTags {
    param([string]$Text)
    $tags = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    $peeled = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    foreach ($line in @($Text -split '\r?\n')) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -cnotmatch '^(?<sha>[0-9a-f]{40})\s+refs/tags/(?<tag>[^\s]+?)(?<peeled>\^\{\})?$') { throw '远端 tag 清单包含无法验证的记录。' }
        $sha = $Matches['sha']; $tag = $Matches['tag']; $isPeeled = $Matches['peeled']
        if ($tag -cnotmatch '^v?\d+\.\d+\.\d+[-+][A-Za-z0-9.+-]*ohos[A-Za-z0-9.+-]*$') { continue }
        $target = if ($isPeeled) { $peeled } else { $tags }
        if ($target.ContainsKey($tag) -and $target[$tag] -cne $sha) { throw '远端重复 tag 不一致。' }
        $target[$tag] = $sha
    }
    foreach ($tag in $tags.Keys) {
        $commit = if ($peeled.ContainsKey($tag)) { $peeled[$tag] } else { $tags[$tag] }
        $base = [version]([regex]::Match($tag, '\d+\.\d+\.\d+').Value)
        $pre = $tag -match '(?:[.+-])(?:beta|alpha|rc|pre|dev|canary)(?:[.0-9+-]|$)'
        $natural = [regex]::Replace(($tag -replace '^v',''), '\d+', { param($match) $match.Value.PadLeft(12, '0') })
        [pscustomobject]@{ Ref = $tag; Commit = $commit; Version = ('custom_jobs_ohos_' + $commit); BaseVersion = $base; Prerelease = $pre; NaturalRef = $natural; Label = ($tag + ' | ' + $commit.Substring(0,12) + ' | CPF-Flutter') }
    }
}

function Get-JobsHarmonyTagChoices {
    param([string]$Text)
    ConvertFrom-JobsHarmonyTags $Text | Sort-Object -Property @{Expression='Prerelease'; Ascending=$true}, @{Expression='BaseVersion'; Descending=$true}, @{Expression='NaturalRef'; Descending=$true}
}

function Resolve-JobsHarmonyCommit {
    param([string]$Text, [string]$Ref)
    $tag = ''; $peeled = ''; $branch = ''
    foreach ($line in @($Text -split '\r?\n')) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -cnotmatch '^(?<sha>[0-9a-f]{40})\s+(?<ref>refs/[^\s]+)$') { throw '远端 ref 记录无效。' }
        $sha = $Matches['sha']; $name = $Matches['ref']
        if ($name -ceq ('refs/tags/' + $Ref)) { if ($tag -and $tag -cne $sha) { throw '重复 tag。' }; $tag = $sha }
        elseif ($name -ceq ('refs/tags/' + $Ref + '^{}')) { if ($peeled -and $peeled -cne $sha) { throw '重复 peeled tag。' }; $peeled = $sha }
        elseif ($name -ceq ('refs/heads/' + $Ref)) { $branch = $sha }
        else { throw '远端返回了未请求的 ref。' }
    }
    if (-not $tag -or $branch) { throw '所选 tag 不存在或与同名分支冲突。' }
    if ($peeled) { return $peeled }
    return $tag
}

function Get-JobsHarmonyCache {
    $root = [Environment]::GetFolderPath('LocalApplicationData')
    if ($env:LOCALAPPDATA) { $root = $env:LOCALAPPDATA }
    if (-not [IO.Path]::IsPathRooted($root)) { throw '无法定位用户本地缓存目录。' }
    return Join-Path $root 'JobsFlutter/fvm/harmony'
}

function Assert-JobsHarmonyBindingPaths {
    param([string]$Project)
    & $script:HarmonyManager { param($Path) Assert-JobsFlutterProject $Path } $Project
    foreach ($relative in @('.fvm','.fvm/versions')) {
        $path = Join-Path $Project $relative
        if (& $script:HarmonyManager { param($Path) Test-JobsFvmPathEntry $Path } $path) {
            [void](& $script:HarmonyManager { param($Path) Assert-JobsFvmDirectory $Path } $path)
        }
    }
    foreach ($relative in @('.fvmrc','.fvm/fvm_config.json')) {
        $path = Join-Path $Project $relative
        if (& $script:HarmonyManager { param($Path) Test-JobsFvmPathEntry $Path } $path) { & $script:HarmonyManager { param($Path) Assert-JobsFvmPlainFile $Path } $path }
    }
    $link = Join-Path $Project '.fvm/flutter_sdk'
    if (& $script:HarmonyManager { param($Path) Test-JobsFvmPathEntry $Path } $link) {
        if (((Get-Item -LiteralPath $link -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { throw '.fvm/flutter_sdk 是真实目录，保留源码并停止；请先迁移到独立 SDK 缓存。' }
    }
    $versions = Join-Path $Project '.fvm/versions'
    if ([IO.Directory]::Exists($versions)) {
        foreach ($item in Get-ChildItem -LiteralPath $versions -Force) {
            if ($item.PSIsContainer -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { throw '.fvm/versions 含真实 SDK 目录，保留源码并停止。' }
        }
    }
}

function Remove-JobsHarmonyEntry {
    param([string]$Path)
    if (-not (& $script:HarmonyManager { param($Value) Test-JobsFvmPathEntry $Value } $Path)) { return }
    $entry = Get-Item -LiteralPath $Path -Force
    if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        if (($entry.Attributes -band [IO.FileAttributes]::Directory) -ne 0) { [IO.Directory]::Delete($Path) }
        else { [IO.File]::Delete($Path) }
    } elseif ($entry.PSIsContainer) {
        foreach ($child in Get-ChildItem -LiteralPath $Path -Force) { Remove-JobsHarmonyEntry $child.FullName }
        [IO.Directory]::Delete($Path)
    } else { [IO.File]::Delete($Path) }
}

function Set-JobsHarmonyConfig {
    param([string]$Project, [string]$Version, [string]$Cache)
    if ($Version -cnotmatch '^custom_jobs_ohos_[0-9a-f]{40}$' -or -not [IO.Path]::IsPathRooted($Cache)) { throw '鸿蒙 FVM 绑定参数无效。' }
    $config = & $script:HarmonyManager { param($Path) Get-JobsProjectFvmConfig $Path } $Project
    foreach ($pair in @(@('flutter', $Version), @('cachePath', $Cache), @('flutterUrl', $script:HarmonyRepository), @('updateMelosSettings', $false), @('useGitCache', $false))) {
        $config | Add-Member -NotePropertyName $pair[0] -NotePropertyValue $pair[1] -Force
    }
    [IO.File]::WriteAllText((Join-Path $Project '.fvmrc'), ($config | ConvertTo-Json -Depth 100) + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
    return $config
}

function Assert-JobsHarmonySdk {
    param([string]$Git, [string]$Sdk, [string]$Commit, [string]$Directory)
    [void](& $script:HarmonyManager { param($Path) Assert-JobsFvmDirectory $Path } $Sdk)
    if (-not [IO.Directory]::Exists((Join-Path $Sdk '.git')) -or -not [IO.File]::Exists((Join-Path $Sdk 'bin/flutter.bat'))) { throw '缓存不是完整独立 Git SDK，未覆盖。' }
    [void](& $script:HarmonyManager { param($Path) Assert-JobsFvmDirectory $Path } (Join-Path $Sdk '.git'))
    if ((Invoke-JobsHarmonyGit $Git @('-C', $Sdk, 'rev-parse', 'HEAD') $Directory) -cne $Commit -or
        (Invoke-JobsHarmonyGit $Git @('-C', $Sdk, 'remote', 'get-url', 'origin') $Directory) -cne $script:HarmonyRepository) { throw '缓存来源或 commit 不匹配，未覆盖。' }
    if (-not [string]::IsNullOrWhiteSpace((Invoke-JobsHarmonyGit $Git @('-C', $Sdk, 'status', '--porcelain', '--untracked-files=no') $Directory))) { throw 'SDK 缓存有源码改动，未覆盖或复用。' }
}

function Install-JobsHarmonySdk {
    param([string]$Git, [object]$Choice, [string]$Cache, [string]$Directory)
    $versions = Join-Path $Cache 'versions'
    [void][IO.Directory]::CreateDirectory($versions)
    [void](& $script:HarmonyManager { param($Path) Assert-JobsFvmDirectory $Path } $versions)
    $target = Join-Path $versions $Choice.Version
    if (& $script:HarmonyManager { param($Path) Test-JobsFvmPathEntry $Path } $target) {
        Assert-JobsHarmonySdk $Git $target $Choice.Commit $Directory
        return $target
    }
    $stage = Join-Path $versions ('.jobs-download-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($stage)
    $candidate = Join-Path $stage 'sdk'
    try {
        Write-Host ('下载 SDK 来源：' + $script:HarmonyRepository + '；tag：' + $Choice.Ref + '；commit：' + $Choice.Commit)
        [void](Invoke-JobsHarmonyGit $Git @('clone', '--no-checkout', $script:HarmonyRepository, $candidate) $Directory 3600)
        [void](Invoke-JobsHarmonyGit $Git @('-C', $candidate, 'checkout', '--detach', $Choice.Commit) $Directory 120)
        Assert-JobsHarmonySdk $Git $candidate $Choice.Commit $Directory
        # 同文件系统无覆盖发布；其它会话先创建目标时 Directory.Move 失败。
        [IO.Directory]::Move($candidate, $target)
        [IO.Directory]::Delete($stage)
        return $target
    } catch { Write-Warning ('SDK 下载现场保留：' + $stage); throw }
}

function Get-JobsHarmonyBindingStamp {
    param([string]$Project)
    $stamp = & $script:HarmonyManager { param($Path) Get-JobsFvmPreviewStamp $Path } $Project
    $link = Join-Path $Project '.fvm/flutter_sdk'
    $linkState = '(absent)'
    if (& $script:HarmonyManager { param($Path) Test-JobsFvmPathEntry $Path } $link) {
        $item = Get-Item -LiteralPath $link -Force
        $linkState = ([string]$item.Attributes) + ':' + (@($item.Target) | ConvertTo-Json -Compress)
    }
    return $stamp + '|' + $linkState
}

function Complete-JobsHarmonyConfigPublication {
    param([string]$Stage, [string]$Target, [bool]$Exists)
    if ($Exists) { [IO.File]::Replace($Stage, $Target, [NullString]::Value) }
    else { [IO.File]::Move($Stage, $Target) }
}

function Publish-JobsHarmonyBinding {
    param([string]$Project, [string]$Sdk, [string]$Config, [string]$Stamp)
    Assert-JobsHarmonyBindingPaths $Project
    if ((Get-JobsHarmonyBindingStamp $Project) -cne $Stamp) { throw '初始化期间项目绑定已改变，未发布 SDK。' }
    $backupRoot = & $script:HarmonyManager { Join-Path (Get-JobsInstallRoot) 'backups' }
    $backup = Join-Path $backupRoot ('openharmony-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($backup)
    $configPath = Join-Path $Project '.fvmrc'
    $hadConfig = [IO.File]::Exists($configPath)
    if ($hadConfig) { Copy-Item -LiteralPath $configPath -Destination (Join-Path $backup '.fvmrc') }
    $fvm = Join-Path $Project '.fvm'
    $hadFvm = [IO.Directory]::Exists($fvm)
    $link = Join-Path $fvm 'flutter_sdk'
    $hadLink = & $script:HarmonyManager { param($Path) Test-JobsFvmPathEntry $Path } $link
    $oldTarget = @()
    if ($hadLink) { $oldTarget = @((Get-Item -LiteralPath $link -Force).Target) }
    @{ Project=$Project; HadConfig=$hadConfig; HadFvm=$hadFvm; OldSdkTargets=$oldTarget; NewSdk=$Sdk } |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $backup 'binding.json') -Encoding UTF8
    $token = [guid]::NewGuid().ToString('N')
    $stageConfig = Join-Path $Project ('.jobs-fvmrc-' + $token)
    $stageLink = Join-Path $fvm ('.jobs-sdk-' + $token)
    $oldLink = Join-Path $fvm ('.jobs-sdk-before-' + $token)
    $configPublished = $false; $linkPublished = $false; $oldMoved = $false
    try {
        [IO.File]::WriteAllText($stageConfig, $Config, (New-Object Text.UTF8Encoding($false)))
        $expectedHash = (Get-FileHash -LiteralPath $stageConfig -Algorithm SHA256).Hash
        if ((Get-JobsHarmonyBindingStamp $Project) -cne $Stamp) { throw '发布前项目绑定已改变，未写入。' }
        [void][IO.Directory]::CreateDirectory($fvm)
        $linkType = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'Junction' } else { 'SymbolicLink' }
        # Windows PowerShell 5.1 会把 Target 当通配路径，7.x 则按字面目标处理。
        $linkTarget = $Sdk
        if ($PSVersionTable.PSVersion.Major -eq 5) { $linkTarget = [Management.Automation.WildcardPattern]::Escape($Sdk) }
        [void](New-Item -ItemType $linkType -Path $stageLink -Target $linkTarget)
        if ($hadLink) { [IO.Directory]::Move($link, $oldLink); $oldMoved = $true }
        [IO.Directory]::Move($stageLink, $link); $linkPublished = $true
        Complete-JobsHarmonyConfigPublication $stageConfig $configPath $hadConfig
        $configPublished = $true
        $actualTargets = @((Get-Item -LiteralPath $link -Force).Target)
        if ($actualTargets.Count -ne 1 -or [string]$actualTargets[0] -cne $Sdk -or
            (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash -cne $expectedHash) { throw '发布后的项目配置或 SDK 链接核验失败。' }
        if ($oldMoved) { Remove-JobsHarmonyEntry $oldLink; $oldMoved = $false }
        Write-Host ('项目绑定备份：' + $backup)
    } catch {
        $failure = $_
        try {
            if ($configPublished) {
                if (-not [IO.File]::Exists($configPath) -or
                    (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash -cne $expectedHash) { throw '项目 .fvmrc 已被其它操作改变，未覆盖。' }
                if ($hadConfig) { Copy-Item -LiteralPath (Join-Path $backup '.fvmrc') -Destination $configPath -Force }
                else { [IO.File]::Delete($configPath) }
            }
            if ($linkPublished) {
                $targets = @((Get-Item -LiteralPath $link -Force).Target)
                if ($targets.Count -ne 1 -or [string]$targets[0] -cne $Sdk) { throw '项目 SDK 链接已被其它操作改变，未覆盖。' }
                Remove-JobsHarmonyEntry $link
            }
            if ($oldMoved) { [IO.Directory]::Move($oldLink, $link); $oldMoved = $false }
            if (-not $hadFvm -and [IO.Directory]::Exists($fvm) -and @(Get-ChildItem -LiteralPath $fvm -Force).Count -eq 0) { [IO.Directory]::Delete($fvm) }
        } catch { throw ('发布失败且发现并发改动，快照与原链接保留：' + $backup + '；' + $oldLink + '；恢复错误：' + $_.Exception.Message) }
        throw $failure
    } finally {
        if ([IO.File]::Exists($stageConfig)) { [IO.File]::Delete($stageConfig) }
        if (& $script:HarmonyManager { param($Path) Test-JobsFvmPathEntry $Path } $stageLink) { Remove-JobsHarmonyEntry $stageLink }
    }
}

function Invoke-JobsHarmonySdkAction {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Target, [switch]$Check, [switch]$RequireCompletion)
    $project = & $script:HarmonyManager { param($Path) Assert-JobsFvmDirectory (Resolve-JobsTarget $Path) } $Target
    Assert-JobsHarmonyBindingPaths $project
    $cache = Get-JobsHarmonyCache
    if ($Check) {
        $config = & $script:HarmonyManager { param($Path) Get-JobsProjectFvmConfig $Path } $project
        Write-Host ('只读计划：' + $project)
        Write-Host ('来源：' + $script:HarmonyRepository + '；缓存：' + $cache)
        $pin = '(未绑定)'
        if ($config.PSObject.Properties['flutter']) {
            $candidate = [string]$config.flutter
            if ($candidate -cmatch '^(?:custom_jobs_ohos_[0-9a-f]{40}|v?\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.+-]+)?)$') { $pin = $candidate }
            else { $pin = '(其它格式，未回显)' }
        }
        $managed = Test-JobsManagedHarmonyBinding $project
        Write-Host ('当前项目版本：' + $pin + '；本工具 CPF 绑定：' + $managed)
        Write-Host '安装模式将从远端 tag 选择并锁定 commit；本次未联网、未运行 Git/FVM/Flutter、未写项目。'
        return
    }
    Write-Host ('安装/切换 Flutter@OpenHarmony SDK；项目：' + $project)
    Write-Host '选择 CPF-Flutter 的 ohos tag，锁定 commit 后安装到隔离缓存，再绑定当前项目 FVM。不会生成 ohos/、安装 DevEco 或运行构建。'
    $saved = @{}
    foreach ($key in @('PATH','FVM_CACHE_PATH','FVM_FLUTTER_URL','FVM_USE_GIT_CACHE')) { $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
    $savedTls = [Net.ServicePointManager]::SecurityProtocol
    $inspection = $null; $lock = $null
    try {
        [Net.ServicePointManager]::SecurityProtocol = $savedTls -bor [Net.SecurityProtocolType]::Tls12
        $root = & $script:HarmonyManager { Get-JobsInstallRoot }
        [void][IO.Directory]::CreateDirectory($root)
        try { $lock = [IO.File]::Open((Join-Path $root 'operation.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
        catch { throw '另一 FVM 操作正在运行，请稍后重试。' }
        $stamp = Get-JobsHarmonyBindingStamp $project
        $inspection = & $script:HarmonyManager { param($Path) New-JobsFvmInspection $Path } $project
        $chain = & $script:HarmonyManager { param($Path,$Inspection) Get-JobsFvmToolchain $Path $Inspection } $project $inspection
        $tags = Invoke-JobsHarmonyGit $chain.Git @('ls-remote', '--tags', $script:HarmonyRepository) $project
        $choices = @(Get-JobsHarmonyTagChoices $tags)
        if ($choices.Count -eq 0) { throw '来源未返回可验证的 ohos tag；未写项目。' }
        $choice = & $script:HarmonyManager { param($Fzf,$Choices,$Path) Select-JobsFlutterVersion $Fzf $Choices $Path } $chain.Fzf $choices $project
        if ($null -eq $choice) { if ($RequireCompletion) { throw '已取消鸿蒙 SDK 准备，未继续依赖操作。' }; Write-Host '已取消，项目未修改。'; return }
        $refs = Invoke-JobsHarmonyGit $chain.Git @('ls-remote', $script:HarmonyRepository, ('refs/tags/' + $choice.Ref), ('refs/tags/' + $choice.Ref + '^{}'), ('refs/heads/' + $choice.Ref)) $project
        if ((Resolve-JobsHarmonyCommit $refs $choice.Ref) -cne $choice.Commit) { throw '所选 tag 在选择期间改变，请重新选择。' }
        Write-Host ('计划：' + $choice.Ref + ' → ' + $choice.Commit + '；缓存：' + $cache)
        Write-Host 'FVM 先在影子项目初始化并核验；真实项目仅更新 .fvmrc 和 .fvm/flutter_sdk。IDE、ignore、业务源码及其它元数据保持原样。'
        if ((Read-Host '回车安装/切换；任意非空输入取消') -ne '') { if ($RequireCompletion) { throw '已取消鸿蒙 SDK 准备，未继续依赖操作。' }; Write-Host '已取消，项目未修改。'; return }
        Assert-JobsHarmonyBindingPaths $project
        if ((Get-JobsHarmonyBindingStamp $project) -cne $stamp) { throw '选版期间项目配置已改变，请重新打开。' }
        $sdk = Install-JobsHarmonySdk $chain.Git $choice $cache $project
        $pinned = Set-JobsHarmonyConfig $inspection $choice.Version $cache
        $env:FVM_CACHE_PATH = $cache; $env:FVM_FLUTTER_URL = $script:HarmonyRepository; $env:FVM_USE_GIT_CACHE = 'false'
        $use = & $script:HarmonyManager { param($Fvm,$Version,$Path) Invoke-JobsFvmTool $Fvm @('use',$Version,'--skip-setup','--skip-pub-get') $Path -Visible -TimeoutSeconds 300 } $chain.Fvm $choice.Version $inspection
        if ($use.ExitCode -ne 0) { throw 'FVM 鸿蒙 SDK 绑定失败。' }
        $after = & $script:HarmonyManager { param($Path) Get-JobsProjectFvmConfig $Path } $inspection
        foreach ($property in $pinned.PSObject.Properties) {
            if ($null -eq $after.PSObject.Properties[$property.Name]) { $after | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value }
        }
        if ($after.flutter -cne $choice.Version -or $after.cachePath -cne $cache -or $after.flutterUrl -cne $script:HarmonyRepository) { throw 'FVM 实际绑定与计划不一致。' }
        $link = Get-Item -LiteralPath (Join-Path $inspection '.fvm/flutter_sdk') -Force
        $targets = @($link.Target)
        if (($link.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -or $targets.Count -ne 1) { throw 'FVM 没有建立唯一 SDK 链接。' }
        $linkedPath = [string]$targets[0]
        if (-not [IO.Path]::IsPathRooted($linkedPath)) { $linkedPath = Join-Path (Split-Path -Parent $link.FullName) $linkedPath }
        if (-not [StringComparer]::OrdinalIgnoreCase.Equals([IO.Path]::GetFullPath($linkedPath).TrimEnd('\','/'), [IO.Path]::GetFullPath($sdk).TrimEnd('\','/'))) { throw '项目 SDK 链接未指向所选缓存。' }
        $version = & $script:HarmonyManager { param($Fvm,$Path) Invoke-JobsFvmTool $Fvm @('flutter','--version','--machine') $Path -TimeoutSeconds 300 } $chain.Fvm $inspection
        if ($version.ExitCode -ne 0) { throw '所选 SDK 初始化或版本体检失败。' }
        $actual = $version.StdOut | ConvertFrom-Json -ErrorAction Stop
        if ($actual.frameworkRevision -cne $choice.Commit) { throw '实际 Flutter commit 与锁定版本不一致。' }
        $help = & $script:HarmonyManager { param($Fvm,$Path) Invoke-JobsFvmTool $Fvm @('flutter','build','hap','--help') $Path -TimeoutSeconds 120 } $chain.Fvm $inspection
        if ($help.ExitCode -ne 0 -or ($help.StdOut + $help.StdErr) -notmatch '\bhap\b') { throw '所选 SDK 不提供 build hap；已停止。' }
        Assert-JobsHarmonySdk $chain.Git $sdk $choice.Commit $project
        Publish-JobsHarmonyBinding $project $sdk (($after | ConvertTo-Json -Depth 100) + [Environment]::NewLine) $stamp
        Write-Host ('成功：当前项目绑定 ' + $choice.Ref + ' / ' + $choice.Commit)
        Write-Host '接下来可执行鸿蒙 Flutter 环境体检；SDK 切换不代表插件、DevEco、签名或 HAP 构建已通过。'
    } finally {
        if ($inspection -and [IO.Directory]::Exists($inspection)) {
            try { Remove-JobsHarmonyEntry $inspection }
            catch { Write-Warning ('影子目录清理未完成，保留供核对：' + $inspection) }
        }
        if ($lock) { $lock.Dispose() }
        foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
        [Net.ServicePointManager]::SecurityProtocol = $savedTls
    }
}
function Test-JobsManagedHarmonyBinding {
    param([string]$Project)
    $config = & $script:HarmonyManager { param($Path) Get-JobsProjectFvmConfig $Path } $Project
    if (-not $config.PSObject.Properties['flutter'] -or -not $config.PSObject.Properties['flutterUrl'] -or -not $config.PSObject.Properties['cachePath']) { return $false }
    return [string]$config.flutter -cmatch '^custom_jobs_ohos_[0-9a-f]{40}$' -and
        [string]$config.flutterUrl -ceq $script:HarmonyRepository -and
        [StringComparer]::OrdinalIgnoreCase.Equals([string]$config.cachePath, (Get-JobsHarmonyCache))
}

function Invoke-JobsNativeSdkFromHarmony {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Target)
    $project = & $script:HarmonyManager { param($Path) Assert-JobsFvmDirectory (Resolve-JobsTarget $Path) } $Target
    Assert-JobsHarmonyBindingPaths $project
    if (-not (Test-JobsManagedHarmonyBinding $project)) { throw '不是本工具管理的 CPF OpenHarmony 绑定，未迁移未知 fork。' }
    $official = 'https://github.com/flutter/flutter.git'
    $cache = Join-Path (Split-Path -Parent (Get-JobsHarmonyCache)) 'official'
    $stamp = Get-JobsHarmonyBindingStamp $project
    Write-Host ('从 OpenHarmony 切回原生 Flutter；精确项目：' + $project)
    Write-Host ('官方 SDK 来源：' + $official + '；隔离缓存：' + $cache)
    Write-Host '先在影子项目选择并验证官方 SDK，成功后仅发布 .fvmrc 与 SDK 联接；保留 IDE、ignore、源码和其它元数据。'
    $saved = @{}
    foreach ($key in @('PATH','FVM_CACHE_PATH','FVM_FLUTTER_URL','FVM_USE_GIT_CACHE')) { $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
    $savedTls = [Net.ServicePointManager]::SecurityProtocol
    $inspection = $null; $lock = $null
    try {
        [Net.ServicePointManager]::SecurityProtocol = $savedTls -bor [Net.SecurityProtocolType]::Tls12
        $root = & $script:HarmonyManager { Get-JobsInstallRoot }
        [void][IO.Directory]::CreateDirectory($root)
        try { $lock = [IO.File]::Open((Join-Path $root 'operation.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
        catch { throw '另一 FVM 操作正在运行，请稍后重试。' }
        $inspection = & $script:HarmonyManager { param($Path) New-JobsFvmInspection $Path } $project
        $config = & $script:HarmonyManager { param($Path) Get-JobsProjectFvmConfig $Path } $inspection
        $config.PSObject.Properties.Remove('flutter')
        $config | Add-Member -NotePropertyName 'cachePath' -NotePropertyValue $cache -Force
        $config | Add-Member -NotePropertyName 'flutterUrl' -NotePropertyValue $official -Force
        $config | Add-Member -NotePropertyName 'updateMelosSettings' -NotePropertyValue $false -Force
        $config | Add-Member -NotePropertyName 'useGitCache' -NotePropertyValue $false -Force
        [IO.File]::WriteAllText((Join-Path $inspection '.fvmrc'), ($config | ConvertTo-Json -Depth 100), (New-Object Text.UTF8Encoding($false)))
        $env:FVM_CACHE_PATH = $cache; $env:FVM_FLUTTER_URL = $official; $env:FVM_USE_GIT_CACHE = 'false'
        $chain = & $script:HarmonyManager { param($Path) Get-JobsFvmToolchain $Path $Path } $inspection
        if ($chain.Context.flutterUrl -cne $official -or -not [StringComparer]::OrdinalIgnoreCase.Equals([string]$chain.Context.versionsCachePath, (Join-Path $cache 'versions'))) { throw '影子项目的官方来源或缓存未生效，未修改真实项目。' }
        $cached = @(& $script:HarmonyManager { param($Fvm,$Path) Get-JobsFvmCachedVersions $Fvm $Path } $chain.Fvm $inspection)
        $choices = @(& $script:HarmonyManager { param($Cached) Get-JobsFlutterReleaseChoices $Cached '(OpenHarmony)' } $cached)
        $choice = & $script:HarmonyManager { param($Fzf,$Choices,$Path) Select-JobsFlutterVersion $Fzf $Choices $Path } $chain.Fzf $choices $inspection
        if ($null -eq $choice) { Write-Host '已取消，OpenHarmony 绑定保持原样。'; return }
        Write-Host ('计划：OpenHarmony → 官方 Flutter ' + $choice.Version + '；来源：' + $official + '；缓存：' + $cache)
        if ((Read-Host '回车安装/切回原生 Flutter；任意非空输入取消') -ne '') { Write-Host '已取消，OpenHarmony 绑定保持原样。'; return }
        Assert-JobsHarmonyBindingPaths $project
        if ((Get-JobsHarmonyBindingStamp $project) -cne $stamp) { throw '选版期间真实项目绑定已改变，未发布。' }
        & $script:HarmonyManager { param($Path,$Version) Set-JobsProjectFvmVersion $Path $Version } $inspection $choice.Version
        $pinned = & $script:HarmonyManager { param($Path) Get-JobsProjectFvmConfig $Path } $inspection
        if (-not $choice.Ready) {
            if ($choice.Offline) { throw '离线模式下缺少就绪官方 SDK，未切换。' }
            $install = & $script:HarmonyManager { param($Fvm,$Version,$Path) Invoke-JobsFvmTool $Fvm @('install',$Version,'--skip-pub-get') $Path -Visible -TimeoutSeconds 3600 } $chain.Fvm $choice.Version $inspection
            if ($install.ExitCode -ne 0) { throw '官方 SDK 安装失败，真实项目保持 OpenHarmony 绑定。' }
        }
        $use = & $script:HarmonyManager { param($Fvm,$Version,$Path) Invoke-JobsFvmTool $Fvm @('use',$Version,'--skip-setup','--skip-pub-get') $Path -Visible -TimeoutSeconds 300 } $chain.Fvm $choice.Version $inspection
        if ($use.ExitCode -ne 0) { throw '官方 SDK 绑定失败，真实项目保持 OpenHarmony 绑定。' }
        $after = & $script:HarmonyManager { param($Path) Get-JobsProjectFvmConfig $Path } $inspection
        foreach ($property in $pinned.PSObject.Properties) {
            if ($null -eq $after.PSObject.Properties[$property.Name]) { $after | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value }
        }
        if ($after.flutter -cne $choice.Version -or $after.flutterUrl -cne $official -or $after.cachePath -cne $cache) { throw '影子项目官方绑定与所选版本不一致。' }
        $sdk = Join-Path (Join-Path $cache 'versions') $choice.Version
        [void](& $script:HarmonyManager { param($Path) Assert-JobsFvmDirectory $Path } $sdk)
        $link = Get-Item -LiteralPath (Join-Path $inspection '.fvm/flutter_sdk') -Force
        $targets = @($link.Target)
        if (($link.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -or $targets.Count -ne 1) { throw '官方 FVM SDK 联接无效。' }
        $actualPath = [string]$targets[0]
        if (-not [IO.Path]::IsPathRooted($actualPath)) { $actualPath = Join-Path (Split-Path -Parent $link.FullName) $actualPath }
        if (-not [StringComparer]::OrdinalIgnoreCase.Equals([IO.Path]::GetFullPath($actualPath).TrimEnd('\','/'), [IO.Path]::GetFullPath($sdk).TrimEnd('\','/'))) { throw '官方 SDK 联接超出所选缓存。' }
        if ((Invoke-JobsHarmonyGit $chain.Git @('-C',$sdk,'remote','get-url','origin') $inspection) -cnotin @($official,'https://github.com/flutter/flutter')) { throw 'SDK 缓存来源不是官方 Flutter，未发布。' }
        $version = & $script:HarmonyManager { param($Fvm,$Path) Invoke-JobsFvmTool $Fvm @('flutter','--version','--machine') $Path -TimeoutSeconds 300 } $chain.Fvm $inspection
        if ($version.ExitCode -ne 0 -or ($version.StdOut | ConvertFrom-Json -ErrorAction Stop).frameworkVersion -cne $choice.Version) { throw '官方 SDK 实际版本不匹配，真实项目保持原绑定。' }
        Publish-JobsHarmonyBinding $project $sdk (($after | ConvertTo-Json -Depth 100) + [Environment]::NewLine) $stamp
        Write-Host ('成功：当前项目已切回官方 Flutter ' + $choice.Version + '；OpenHarmony SDK 缓存保留，可从相邻菜单切回。')
    } finally {
        if ($inspection -and [IO.Directory]::Exists($inspection)) {
            try { Remove-JobsHarmonyEntry $inspection }
            catch { Write-Warning ('影子目录清理未完成，保留供核对：' + $inspection) }
        }
        if ($lock) { $lock.Dispose() }
        foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
        [Net.ServicePointManager]::SecurityProtocol = $savedTls
    }
}
Export-ModuleMember -Function Invoke-JobsHarmonySdkAction, Invoke-JobsNativeSdkFromHarmony, Test-JobsManagedHarmonyBinding

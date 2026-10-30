# ProjectSetup.psm1 | Flutter 项目环境与 Gradle 插件准备
# Created by Jobs on 2026年10月28日，星期三.
# 仅当前工程和当前用户缓存；系统模式不改全局 SDK、PATH 或代理。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'ProjectSetupProgress.psm1') -DisableNameChecking
. (Join-Path $PSScriptRoot 'ProjectSetupRun.ps1')
. (Join-Path $PSScriptRoot 'ProjectDependencies.ps1')
. (Join-Path $PSScriptRoot 'ProjectDependencyArchive.ps1')

# 输出脱敏来源和步骤，同时保留本次运行日志。
function Write-JobsSetupMessage {
    param([string]$Message,[switch]$AuditOnly)
    $safe = $Message -replace '(?i)(https?://)[^\s/@]+@', '$1***@'
    $safe = $safe -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]'
    $safe = $safe -replace '(?im)((?:token|password|secret|authorization)\s*[:=]\s*)\S+', '$1[已省略]'
    if (-not $AuditOnly) { Write-Host $safe }
    if (Get-Variable SetupLog -Scope Script -ErrorAction SilentlyContinue) { [IO.File]::AppendAllText($script:SetupLog, $safe + [Environment]::NewLine, (New-Object Text.UTF8Encoding($true))) }
}
# 使用参数数组执行工具；BAT 通过固定环境载体进入 CMD。
function Invoke-JobsSetupProcess {
    param([string]$File, [string[]]$Arguments = @(), [string]$Directory, [int]$TimeoutSeconds = 120)
    if ($File -match '["\x00-\x1f]') { throw '工具路径含不支持的字符。' }
    if ([IO.Path]::GetExtension($File) -in @('.bat', '.cmd')) {
        if (@($Arguments | Where-Object { $_ -match '["\x00-\x1f]' }).Count) { throw 'BAT 参数含双引号或控制字符。' }
        $cmd = Join-Path ([Environment]::GetFolderPath('System')) 'cmd.exe'
        $start = New-JobsSetupBatchStart $cmd $File $Arguments $Directory
        $result = Invoke-JobsSetupBatch $start $TimeoutSeconds
    } elseif ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        $start=New-Object Diagnostics.ProcessStartInfo
        $start.FileName=$File;$start.Arguments=(@($Arguments|ForEach-Object{Quote-JobsArgument $_})-join ' ');$start.WorkingDirectory=$Directory
        $result=Invoke-JobsSetupLiveProcess $start $TimeoutSeconds
    } else { $result = Invoke-JobsProcess -FilePath $File -Arguments $Arguments -WorkingDirectory $Directory -TimeoutSeconds $TimeoutSeconds }
    if ($result.StdOut) { Write-JobsSetupMessage $result.StdOut.TrimEnd() -AuditOnly:([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) }
    if ($result.StdErr) { Write-JobsSetupMessage $result.StdErr.TrimEnd() -AuditOnly:([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) }
    if ($result.ExitCode -ne 0) {
        $failure = New-Object System.InvalidOperationException ('工具失败：{0}，退出码 {1}' -f $File, $result.ExitCode)
        $failure.Data['NetworkFailure'] = Test-JobsSetupNetworkFailure ($result.StdOut + $result.StdErr)
        throw $failure
    }
    return $result
}
# CMD 命令行保持原生引号，不再套一层 Win32 argv 转义。
function New-JobsSetupBatchStart {
    param([string]$Cmd, [string]$File, [string[]]$Arguments, [string]$Directory)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Cmd
    $placeholders = @()
    for ($index=0; $index -lt $Arguments.Count; $index++) {
        $name = 'JOBS_SETUP_ARGUMENT_' + $index
        $start.EnvironmentVariables[$name] = $Arguments[$index]
        $placeholders += ('"%' + $name + '%"')
    }
    $start.Arguments = '/d /v:off /s /c ""%JOBS_SETUP_TOOL%" ' + ($placeholders -join ' ') + '"'
    $start.EnvironmentVariables['JOBS_SETUP_TOOL'] = $File
    $start.WorkingDirectory = $Directory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $start.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    return $start
}
# 同时排空输出；超时只停止本次 CMD/Flutter/Gradle 子树。
function Invoke-JobsSetupBatch {
    param($Start, [int]$TimeoutSeconds)
    return Invoke-JobsSetupLiveProcess $Start $TimeoutSeconds
}
# 仅短暂网络故障允许重试，认证、权限和证书错误直接保留现场。
function Test-JobsSetupNetworkFailure {
    param([string]$Text)
    return $Text -notmatch '401|403|Unauthorized|Forbidden|Authentication|PKIX|certificate|SSLHandshake|权限|证书' -and $Text -match 'timed? out|timeout|Could not GET|Could not HEAD|Connection reset|connection refused|UnknownHost|resolve host|超时'
}
# 验证目标是普通目录，避免配置/归档写入穿过链接。
function Assert-JobsSetupDirectory {
    param([string]$Path)
    if (-not [IO.Path]::IsPathRooted($Path)) { throw '必须提供绝对目录。' }
    $current = New-Object IO.DirectoryInfo ([IO.Path]::GetFullPath($Path))
    while ($null -ne $current) {
        if ($current.Exists -and ($current.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw ('目录含链接或联接：' + $current.FullName) }
        $current = $current.Parent
    }
}
# 拒绝链接配置，读取前后都保留明确边界。
function Assert-JobsSetupFile {
    param([string]$Path)
    Assert-JobsSetupDirectory (Split-Path -Parent $Path)
    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path -Force
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw ('配置必须是普通文件：' + $Path) }
    }
}
# 首个菜单前验证 fzf，不因选择系统模式强制安装 FVM。
function Get-JobsSetupFzf {
    param([string]$Project)
    $worker = Import-Module (Join-Path $PSScriptRoot 'Actions/sdk-manage/Scripts/Action.psm1') -PassThru -DisableNameChecking
    return & $worker {
        param($Project)
        $tool = Find-JobsHealthyFvmTool 'fzf.exe' @() $Project
        if (-not $tool) { Install-JobsWingetTool 'junegunn.fzf' $Project; $tool = Find-JobsHealthyFvmTool 'fzf.exe' @() $Project }
        if (-not $tool) { throw 'fzf 安装后不可用，已停止。' }
        $tool
    } $Project
}
# 单选支持真实左键回上一层，取消不会返回默认项。
function Select-JobsSetupChoice {
    param([string]$Fzf, [string]$Title, [string[]]$Choices, [switch]$Back)
    $active=Get-JobsSetupActiveNode
    if($active){Set-JobsSetupProgress $active waiting $Title}
    Set-JobsSetupProgress overall waiting $Title
    $parameters = @('--no-multi', '--height=80%', '--layout=reverse', '--border', ('--prompt=' + $Title + '> '), '--header=Enter 选择；Esc/Ctrl+C 取消；← 返回上一层')
    if ($Back) { $parameters += '--expect=left' }
    $saved = $env:FZF_DEFAULT_OPTS
    try {
        $env:FZF_DEFAULT_OPTS = ''
        $result = @($Choices | & $Fzf @parameters)
        $code = $LASTEXITCODE
        if ($code -in @(1, 130)) { throw '已取消选择，后续步骤未执行。' }
        if ($code -ne 0) { throw ('fzf 失败：' + $code) }
        if ($Back -and $result.Count -gt 0 -and $result[0] -ceq 'left') { return $null }
        $selection = @($result | Where-Object { $_ -cin $Choices })
        if ($selection.Count -ne 1) { throw 'fzf 返回未知或空选择。' }
        if($active){Set-JobsSetupProgress $active running ('已选择：'+$Title)}
        Set-JobsSetupProgress overall running ('已选择：' + $Title)
        return $selection[0]
    } finally { if ($null -eq $saved) { Remove-Item Env:FZF_DEFAULT_OPTS -ErrorAction SilentlyContinue } else { $env:FZF_DEFAULT_OPTS = $saved } }
}
# 管理器版本仅从已安装工具/官方源码读取，不为展示版本触发安装或全局初始化。
function Get-JobsSetupManagerVersion {
 param([ValidateSet('fvm','jenv')][string]$Manager,[string]$Project)
 if($Manager-ceq'fvm'){
  $tool=$null
  foreach($name in @('fvm.exe','fvm.bat','fvm.cmd')){if(-not$tool){$tool=Find-JobsExecutable $name}}
  $pointer=Join-Path (Get-JobsInstallRoot) 'tools/fvm-path.txt'
  if(-not$tool-and[IO.File]::Exists($pointer)){$candidate=[IO.File]::ReadAllText($pointer).Trim();if([IO.File]::Exists($candidate)){$tool=$candidate}}
  if($tool){try{$probe=Invoke-JobsSetupProcess $tool @('--version') $Project 30;$text=($probe.StdOut+$probe.StdErr);if($text-match'(?m)(?:FVM\s+)?v?(\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.]+)?)') {return 'FVM '+$Matches[1]}}catch{}}
  return 'FVM 版本未检测'
 }
 $cache=Join-Path (Get-JobsInstallRoot) 'toolchains/JEnv-for-Windows'
 $main=Join-Path $cache 'src/jenv.ps1';$revision='';$version='版本未检测'
 if([IO.File]::Exists($main)){$source=[IO.File]::ReadAllText($main);if($source-match'(?im)^\s*\$JENV_VERSION\s*=\s*["'']([^"'']+)["'']'){$version=$Matches[1]}}
 $git=Find-JobsExecutable 'git.exe'
 if($git-and[IO.Directory]::Exists((Join-Path $cache '.git'))){try{$probe=Invoke-JobsSetupProcess $git @('rev-parse','HEAD') $cache 30;if($probe.StdOut.Trim()-match'^[a-fA-F0-9]{40,64}$'){$revision=' @'+$probe.StdOut.Trim()}}catch{}}
 return 'jEnv Windows '+$version+$revision
}
# 检查同源 Flutter 与 Dart 实际可运行。
function Get-JobsSetupFlutter {
    param([string]$Path, [string]$Project, [string]$Mode)
    $root = Split-Path -Parent (Split-Path -Parent $Path)
    $dart = Join-Path $root 'bin/cache/dart-sdk/bin/dart.exe'
    if (-not [IO.File]::Exists($Path) -or -not [IO.File]::Exists($dart)) { throw 'Flutter SDK 不完整，缺少 Flutter 或同源 Dart。' }
    $probe=Invoke-JobsSetupProcess $Path @('--version','--machine') $Project
    $json=$probe.StdOut;$first=$json.IndexOf('{');$last=$json.LastIndexOf('}')
    if($first-lt0-or$last-le$first){throw 'Flutter --version --machine 未返回版本 JSON。'}
    $versions=$json.Substring($first,$last-$first+1)|ConvertFrom-Json
    foreach($name in @('frameworkVersion','dartSdkVersion')){if($null-eq$versions.PSObject.Properties[$name]-or$versions.$name-isnot[string]-or[string]::IsNullOrWhiteSpace($versions.$name)){throw 'Flutter 版本 JSON 缺少实际 Flutter / Dart SDK 版本。'}}
    $dartProbe=Invoke-JobsSetupProcess $dart @('--version') $Project
    if(($dartProbe.StdOut+$dartProbe.StdErr)-notmatch'Dart SDK version:\s*([^\s]+)'){throw '同源 Dart SDK 未返回实际版本。'}
    $dartVersion=$Matches[1]
    $architecture=if(($dartProbe.StdOut+$dartProbe.StdErr)-match 'on\s+["'']?(windows_[A-Za-z0-9_-]+)'){$Matches[1]}else{'unknown'}
    $manager=if($Mode-ceq'fvm'){Get-JobsSetupManagerVersion 'fvm' $Project}else{'FVM 不适用（系统模式）'}
    return [pscustomobject]@{Mode=$Mode;Flutter=$Path;Dart=$dart;Root=$root;FrameworkVersion=$versions.frameworkVersion;DartVersion=$dartVersion;Architecture=$architecture;VersionText=('Flutter '+$versions.frameworkVersion+' / Dart '+$dartVersion+' / '+$manager)}
}
# FVM 为默认首项，系统模式可选择现有 SDK 或由官方归档安装。
function Select-JobsSetupFlutter {
    param([string]$Project, [string]$Fzf, [string]$Platform)
    while ($true) {
        $mode = Select-JobsSetupChoice $Fzf 'Flutter 管理方式' @('FVM（推荐，项目隔离）','系统 Flutter（本次使用，不改全局）')
        if ($mode.StartsWith('FVM')) {
            $choice = Select-JobsSetupChoice $Fzf '项目 FVM' @('安装/切换项目 Flutter SDK','复用当前项目 FVM SDK') -Back
            if ($null -eq $choice) { continue }
            if ($choice.StartsWith('安装')) {
if ($Platform -ceq 'Ohos') {
    $manager = Import-Module (Join-Path $PSScriptRoot 'HarmonySdk.psm1') -PassThru -DisableNameChecking
    & $manager { param($p) Invoke-JobsHarmonySdkAction -Target $p -RequireCompletion } $Project
} else {
    $manager = Import-Module (Join-Path $PSScriptRoot 'Actions/sdk-manage/Scripts/Action.psm1') -PassThru -DisableNameChecking
    & $manager { param($p) Invoke-JobsFlutterVersionAction -Directory $p -RequireCompletion } $Project
}
            }
            return Get-JobsSetupFlutter (Join-Path $Project '.fvm/flutter_sdk/bin/flutter.bat') $Project 'fvm'
        }
        $options = @('手动指定现有 Flutter SDK 目录','从 Flutter 官方归档安装 SDK 到用户缓存')
        $system = Find-JobsExecutable 'flutter.bat'
        if ($system -and $system -notmatch '[\\/]\.fvm[\\/]|[\\/]fvm[\\/]default[\\/]') { $options = @('使用 PATH 中的 Flutter：' + $system) + $options }
        $choice = Select-JobsSetupChoice $Fzf '系统 Flutter' $options -Back
        if ($null -eq $choice) { continue }
        if ($choice.StartsWith('使用 PATH')) { return Get-JobsSetupFlutter $system $Project 'system' }
        if ($choice.StartsWith('手动')) {
            $sdk = (Read-Host '输入 Flutter SDK 根目录（空输入取消）').Trim().Trim('"')
            if (-not $sdk) { throw '已取消。' }
            return Get-JobsSetupFlutter (Join-Path $sdk 'bin/flutter.bat') $Project 'system'
        }
        return Install-JobsSetupFlutter $Project $Fzf
    }
}
# 网络读取有界重试，并恢复 TLS 配置；不修改代理或全局仓库。
function Receive-JobsSetupFile {
    param([string[]]$Urls, [string]$Destination, [int]$TimeoutSeconds = 600)
    $savedTls = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = $savedTls -bor [Net.SecurityProtocolType]::Tls12
        foreach ($url in $Urls) {
            if ($url -cnotmatch '^https://[^\s]+$') { throw '只接受 HTTPS 下载源。' }
            for ($attempt = 1; $attempt -le 2; $attempt++) {
                Write-JobsSetupMessage ('下载来源：{0}；目标：{1}；尝试 {2}/2' -f $url, $Destination, $attempt)
                try {
                    $curl = Find-JobsExecutable 'curl.exe'
                    if ($curl) {
                        $parameters = @('--fail','--location','--connect-timeout','15','--max-time',[string]$TimeoutSeconds,'--speed-time','30','--speed-limit','1024','--retry','1','--output', ($Destination + '.part'), $url)
                        # 每个来源独立覆盖未完成文件，防止跨源拼接不同字节。
                        [void](Invoke-JobsSetupProcess $curl $parameters (Split-Path -Parent $Destination) ($TimeoutSeconds + 30))
                    } else { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile ($Destination + '.part') -TimeoutSec $TimeoutSeconds }
                    Move-Item -LiteralPath ($Destination + '.part') -Destination $Destination -Force
                    return $url
                } catch { Write-JobsSetupMessage ('此线路失败：' + $_.Exception.Message) }
            }
        }
        throw '所有下载线路均失败；保留日志，请检查网络后重新运行。'
    } finally { [Net.ServicePointManager]::SecurityProtocol = $savedTls }
}
# 防止 ZIP 越界及链接文件写入当前用户缓存。
function Expand-JobsSetupZip {
    param([string]$Archive, [string]$Destination)
    Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName -match '(^[/\\]|(^|[/\\])\.\.([/\\]|$)|:)' -or (($entry.ExternalAttributes -shr 16) -band 61440) -eq 40960) { throw 'ZIP 含越界路径或链接。' }
        }
    } finally { $zip.Dispose() }
    Assert-JobsSetupDirectory $Destination
    [IO.Compression.ZipFile]::ExtractToDirectory($Archive, $Destination)
}
# 官方 Flutter 归档使用官方元数据摘要，独立系统安装不绑定 FVM。
function Install-JobsSetupFlutter {
    param([string]$Project, [string]$Fzf)
    $cache = Join-Path (Get-JobsInstallRoot) ('toolchains/flutter-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($cache)
    $metadata = Join-Path $cache 'releases.json'
    [void](Receive-JobsSetupFile @('https://storage.googleapis.com/flutter_infra_release/flutter/releases/releases_windows.json') $metadata 60)
    $manifest = Get-Content -LiteralPath $metadata -Raw -Encoding UTF8 | ConvertFrom-Json
    $choices = @($manifest.releases | Where-Object { $_.channel -ceq 'stable' -and $_.version -match '^\d+\.\d+\.\d+$' } | Select-Object -First 80)
    $labels = @($choices | ForEach-Object { $_.version + ' | ' + $_.archive })
    $selected = Select-JobsSetupChoice $Fzf '安装官方系统 Flutter（Stable）' $labels -Back
    if ($null -eq $selected) { return Select-JobsSetupFlutter $Project $Fzf }
    $release = $choices[[array]::IndexOf($labels, $selected)]
    if ($release.archive -cnotmatch '^stable/windows/flutter_windows_[A-Za-z0-9.+_-]+\.zip$' -or $release.sha256 -cnotmatch '^[a-fA-F0-9]{64}$') { throw '官方 Flutter 归档元数据无效。' }
    $zip = Join-Path $cache 'flutter.zip'
    [void](Receive-JobsSetupFile @(('https://storage.googleapis.com/flutter_infra_release/flutter/' + $release.archive), ('https://storage.flutter-io.cn/flutter_infra_release/flutter/' + $release.archive)) $zip 1800)
    if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ine $release.sha256) { throw 'Flutter SHA-256 校验失败，未解压。' }
    Expand-JobsSetupZip $zip (Join-Path $cache 'sdk')
    return Get-JobsSetupFlutter (Join-Path $cache 'sdk/flutter/bin/flutter.bat') $Project 'system'
}
# 读取完整 JDK 的真实主版本，不能把只有 JRE 的路径当作 SDK。
function Get-JobsSetupJava {
    param([string]$JavaHome, [string]$Project)
    $java = Join-Path $JavaHome 'bin/java.exe'
    $javac = Join-Path $JavaHome 'bin/javac.exe'
    if (-not [IO.File]::Exists($java) -or -not [IO.File]::Exists($javac)) { throw ('不是完整 JDK：' + $JavaHome) }
    $result = Invoke-JobsSetupProcess $java @('-version') $Project 30
    $text = $result.StdOut + $result.StdErr
    if ($text -notmatch 'version\s+"(?:1\.)?(\d+)') { throw '无法读取 Java 主版本。' }
    $major = [int]$Matches[1]
    $runtime=if($text-match'version\s+"([^"]+)"'){$Matches[1]}else{'未检测'}
    $build=if($text-match'(?im)^.*Runtime Environment.*$'){$Matches[0].Trim()}else{''}
    $compiler = Invoke-JobsSetupProcess $javac @('-version') $Project 30
    if (($compiler.StdOut + $compiler.StdErr) -notmatch 'javac\s+(?:1\.)?(\d+)' -or [int]$Matches[1] -ne $major) { throw 'java 与 javac 主版本不一致，不能作为完整 JDK 使用。' }
    $compilerVersion=if(($compiler.StdOut+$compiler.StdErr)-match'javac\s+([^\s]+)'){$Matches[1]}else{'未检测'}
    return [pscustomobject]@{Home=[IO.Path]::GetFullPath($JavaHome);Major=$major;Java=$java;VersionText=('Java '+$runtime+' / javac '+$compilerVersion+' / '+$build).TrimEnd(' ','/')}
}
# 从已有 JDK、手动目录或官方 Temurin 安装中选择，左键回管理方式。
function Select-JobsSetupJava {
    param([string]$Project, [string]$Fzf)
    :management while ($true) {
        $mode = Select-JobsSetupChoice $Fzf 'Java 管理方式' @('jEnv（推荐，Windows 原生实现）','系统 Java（本次使用，不改全局）')
        $roots = @()
        if ($env:JAVA_HOME) { $roots += $env:JAVA_HOME }
        $command = Find-JobsExecutable 'java.exe'
        if ($command) { $roots += Split-Path -Parent (Split-Path -Parent $command) }
        foreach ($base in @($env:ProgramFiles, $env:LOCALAPPDATA)) {
            if (-not $base) { continue }
            foreach ($relative in @('Java','Eclipse Adoptium','Microsoft','Jobs/WindowsExtension/extensions/flutter-tools/toolchains')) {
                $parent = Join-Path $base $relative
                if ([IO.Directory]::Exists($parent)) { $roots += @(Get-ChildItem -LiteralPath $parent -Directory | ForEach-Object { $_.FullName }) }
            }
            $roots += Join-Path $base 'Android/Android Studio/jbr'
        }
        $jdkRoots = @($roots | Select-Object -Unique | Where-Object { [IO.File]::Exists((Join-Path $_ 'bin/java.exe')) -and [IO.File]::Exists((Join-Path $_ 'bin/javac.exe')) })
        $labels = @($jdkRoots | ForEach-Object { '使用 JDK：' + $_ }) + @('手动指定 JDK 目录','安装官方 Temurin JDK（用户缓存）')
        while ($true) {
        $choice = Select-JobsSetupChoice $Fzf '选择 Java SDK' $labels -Back
        if ($null -eq $choice) { continue management }
        if ($choice.StartsWith('手动')) { $jdk = (Read-Host '输入 JDK 根目录（空输入取消）').Trim().Trim('"'); if (-not $jdk) { throw '已取消。' } }
        elseif ($choice.StartsWith('安装')) { $jdk = Install-JobsSetupJava $Project $Fzf; if ($null -eq $jdk) { continue } }
        else { $jdk = $choice.Substring('使用 JDK：'.Length) }
        $java = Get-JobsSetupJava $jdk $Project
        $java | Add-Member -NotePropertyName Mode -NotePropertyValue $(if ($mode.StartsWith('jEnv')) { 'jenv' } else { 'system' })
        if ($java.Mode -eq 'jenv') { Set-JobsSetupJenv $Project $java.Home }
        return $java
        }
    }
}
# Temurin ZIP 遵循所选主版本，不一律安装最高 Java。
function Install-JobsSetupJava {
    param([string]$Project, [string]$Fzf)
    $version = Select-JobsSetupChoice $Fzf 'Temurin 主版本（须兼容工程 Gradle/AGP）' @('17','21','25','27','26','11','8') -Back
    if ($null -eq $version) { return $null }
    $architecture = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { 'aarch64' } else { 'x64' }
    $cache = Join-Path (Get-JobsInstallRoot) ('toolchains/jdk-' + $version + '-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($cache)
    $metadata = Join-Path $cache 'temurin.json'
    $url = 'https://api.adoptium.net/v3/assets/latest/' + $version + '/hotspot?architecture=' + $architecture + '&image_type=jdk&os=windows&vendor=eclipse'
    [void](Receive-JobsSetupFile @($url) $metadata 60)
    $assets = Get-Content -LiteralPath $metadata -Raw -Encoding UTF8 | ConvertFrom-Json
    $selected = @($assets | Where-Object { $_.version.major -eq [int]$version -and $_.binary.os -ceq 'windows' -and $_.binary.architecture -ceq $architecture -and $_.binary.image_type -ceq 'jdk' })
    if ($selected.Count -ne 1) { throw '没有唯一匹配的官方 Temurin JDK；不自动改用其它架构或版本。' }
    $package = $selected[0].binary.package
    if ($package.link -cnotmatch '^https://github\.com/adoptium/temurin[0-9]+-binaries/releases/download/' -or $package.checksum -cnotmatch '^[a-fA-F0-9]{64}$') { throw 'Temurin 来源或 SHA-256 无效。' }
    $zip = Join-Path $cache 'jdk.zip'
    [void](Receive-JobsSetupFile @([string]$package.link) $zip 1200)
    if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ine $package.checksum) { throw 'JDK SHA-256 校验失败，未安装。' }
    Expand-JobsSetupZip $zip (Join-Path $cache 'sdk')
    $roots = @(Get-ChildItem -LiteralPath (Join-Path $cache 'sdk') -Directory)
    if ($roots.Count -ne 1) { throw 'JDK ZIP 目录不唯一。' }
    $java = Get-JobsSetupJava $roots[0].FullName $Project
    if ($java.Major -ne [int]$version) { throw 'JDK 安装后版本复检失败。' }
    return $java.Home
}
# 复用 Windows 官方 jEnv 的 add/local 模块，避开会改全局 PATH 的主初始化。
function Set-JobsSetupJenv {
    param([string]$Project, [string]$JavaHome)
    $cache = Join-Path (Get-JobsInstallRoot) 'toolchains/JEnv-for-Windows'
    $source = 'https://github.com/FelixSelter/JEnv-for-Windows.git'
    if (-not [IO.Directory]::Exists($cache)) {
        $git = Find-JobsExecutable 'git.exe'
        if (-not $git) {
            $chain=Import-Module (Join-Path $PSScriptRoot 'Actions/sdk-manage/Scripts/Action.psm1') -PassThru -DisableNameChecking
            & $chain { param($p) Install-JobsWingetTool 'Git.Git' $p } $Project
            $git=Find-JobsExecutable 'git.exe'
            if(-not $git){throw 'Git 安装后复检失败，未安装 jEnv。'}
        }
        [void](Invoke-JobsSetupProcess $git @('--version') $Project)
        Write-JobsSetupMessage ('jEnv 来源：' + $source + '；用户安装位置：' + $cache)
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $cache))
        [void](Invoke-JobsSetupProcess $git @('clone','--depth','1','--', $source, $cache) $Project 300)
    }
    $addPath = Join-Path $cache 'src/jenv-add.psm1'
    $localPath = Join-Path $cache 'src/jenv-local.psm1'
    foreach ($modulePath in @($addPath,$localPath)) { Assert-JobsSetupFile $modulePath; if (-not [IO.File]::Exists($modulePath)) { throw 'jEnv 缓存不完整，未写配置。' } }
    $git = Find-JobsExecutable 'git.exe'
    if (-not $git) { throw '复核 jEnv 官方来源需要 Git。' }
    $origin = Invoke-JobsSetupProcess $git @('remote','get-url','origin') $cache
    if ($origin.StdOut.Trim() -cne $source) { throw 'jEnv 缓存来源与官方不符。' }
    $status = Invoke-JobsSetupProcess $git @('status','--porcelain') $cache
    if (-not [string]::IsNullOrWhiteSpace($status.StdOut)) { throw 'jEnv 缓存源码存在改动，未执行。' }
    $commit = Invoke-JobsSetupProcess $git @('rev-parse','HEAD') $cache
    Write-JobsSetupMessage ('jEnv 固定源码提交：' + $commit.StdOut.Trim())
    $configPath = Join-Path $env:APPDATA 'JEnv/jenv.config.json'
    Assert-JobsSetupFile $configPath
    $before = if ([IO.File]::Exists($configPath)) { [IO.File]::ReadAllText($configPath) } else { '' }
    $config = if ($before.Trim()) { $before | ConvertFrom-Json } else { [pscustomobject]@{ jenvs = @(); locals = @(); global = '' } }
    foreach ($field in @('jenvs','locals','global')) { if ($null -eq $config.PSObject.Properties[$field]) { throw '已有 jEnv 配置缺字段，未覆盖。' } }
    $name = 'jobs-' + [guid]::NewGuid().ToString('N')
    $existing = @($config.jenvs | Where-Object { $_.path -ieq $JavaHome })
    if ($existing.Count -eq 1) { $name = $existing[0].name }
    else { $add = Import-Module $addPath -PassThru; & $add { param($c,$n,$p) Invoke-Add $c $false $n $p } $config $name $JavaHome | ForEach-Object { Write-JobsSetupMessage $_ } }
    $local = Import-Module $localPath -PassThru
    Push-Location -LiteralPath $Project
    try { & $local { param($c,$n) Invoke-Local $c $false $n } $config $name | ForEach-Object { Write-JobsSetupMessage $_ } } finally { Pop-Location }
    if (@($config.jenvs | Where-Object { $_.name -ceq $name -and $_.path -ieq $JavaHome }).Count -ne 1 -or @($config.locals | Where-Object { $_.path -ieq $Project -and $_.name -ceq $name }).Count -ne 1) { throw 'jEnv 官方模块结果复检失败，未保存配置。' }
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $configPath))
    if ([IO.File]::Exists($configPath)) { Copy-Item -LiteralPath $configPath -Destination ($configPath + '.jobs-' + [guid]::NewGuid().ToString('N') + '.bak') }
    if ([IO.File]::Exists($configPath) -and [IO.File]::ReadAllText($configPath) -cne $before) { throw 'jEnv 配置被并发修改，已停止。' }
    [IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 100), (New-Object Text.UTF8Encoding($true)))
    Write-JobsSetupMessage 'jEnv 已登记当前项目 local 映射；保留 global，未安装全局 shim 或修改系统 PATH。'
}
# 兼容矩阵只做门禁，不因 Java 选择修改项目 Gradle/AGP。
function Assert-JobsSetupCompatibility {
    param([version]$Gradle, [int]$Java, [string]$Agp)
    $minimums = @{ 8='2.0'; 9='4.3'; 10='4.7'; 11='5.0'; 12='5.4'; 13='6.0'; 14='6.3'; 15='6.7'; 16='7.0'; 17='7.3'; 18='7.5'; 19='7.6'; 20='8.3'; 21='8.5'; 22='8.8'; 23='8.10'; 24='8.14'; 25='9.1'; 26='9.4'; 27='9.8' }
    if (-not $minimums.ContainsKey($Java) -or $Gradle -lt [version]$minimums[$Java] -or ($Gradle.Major -ge 9 -and $Java -lt 17)) { throw ('Java {0} 与 Gradle {1} 运行时不兼容或尚未验证；请重新选择 JDK。' -f $Java,$Gradle) }
    if ($Agp) {
        $major = ([version]$Agp).Major
        if (($major -ge 8 -and $Java -lt 17) -or ($major -eq 7 -and $Java -lt 11)) { throw ('AGP {0} 不支持当前 Java {1}。' -f $Agp,$Java) }
    }
}
# 解析项目 Wrapper 固定版本和 AGP 声明，不跟随 latest。
function Get-JobsSetupGradleSpec {
    param([string]$Project)
    $properties = Join-Path $Project 'android/gradle/wrapper/gradle-wrapper.properties'
    Assert-JobsSetupFile $properties
    if (-not [IO.File]::Exists($properties)) { throw '缺少 Android Gradle Wrapper；不生成或升级工程。' }
    $text = [IO.File]::ReadAllText($properties)
    $urls = [regex]::Matches($text, '(?m)^\s*distributionUrl\s*=\s*(.+?)\s*$')
    if ($urls.Count -ne 1) { throw 'Wrapper distributionUrl 缺失或重复。' }
    $url = $urls[0].Groups[1].Value.Replace('\:',':').Replace('\/','/')
    $uri = $null
    if (-not [uri]::TryCreate($url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -cne 'https' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or $uri.AbsolutePath -cnotmatch '/(gradle-([0-9]+\.[0-9]+(?:\.[0-9]+)?)-(bin|all)\.zip)$') { throw '仅支持明确固定版本的 HTTPS Gradle 分发 URL。' }
    $name = $Matches[1]; $version = $Matches[2]
    $checksums = [regex]::Matches($text, '(?m)^\s*distributionSha256Sum\s*=\s*(\S+)\s*$')
    if ($checksums.Count -gt 1 -or ($checksums.Count -eq 1 -and $checksums[0].Groups[1].Value -cnotmatch '^[a-fA-F0-9]{64}$')) { throw 'Wrapper SHA-256 声明无效。' }
    $checksum = if ($checksums.Count -eq 1) { $checksums[0].Groups[1].Value } else { $null }
    $agp = $null
    foreach ($relative in @('android/settings.gradle','android/settings.gradle.kts','android/build.gradle','android/build.gradle.kts')) {
        $file = Join-Path $Project $relative
        if ([IO.File]::Exists($file)) {
            $source = [IO.File]::ReadAllText($file)
            if ($source -match 'com\.android\.tools\.build:gradle:([0-9]+\.[0-9]+(?:\.[0-9]+)?)' -or $source -match 'com\.android\.application["'']\s*\)?\s*version\s*["'']([0-9]+\.[0-9]+(?:\.[0-9]+)?)') { $agp = $Matches[1]; break }
        }
    }
    return [pscustomobject]@{ Url=$url; Name=$name; Version=[version]$version; Checksum=$checksum; Agp=$agp; Properties=$text }
}
# 与 Gradle PathAssembler 一致：原 distributionUrl 的无符号 MD5 转 base36。
function Get-JobsSetupWrapperHash {
    param([string]$Url)
    if ($Url -cmatch '[^\x21-\x7e]') { throw 'Wrapper URL 请使用 ASCII / 百分号编码形式，避免与 Java URI 缓存 hash 不一致。' }
    Add-Type -AssemblyName System.Numerics
    $md5 = [Security.Cryptography.MD5]::Create()
    try { $digest = $md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($Url)) } finally { $md5.Dispose() }
    [array]::Reverse($digest)
    $unsigned = New-Object byte[] 17
    [array]::Copy($digest,$unsigned,16)
    $number = New-Object Numerics.BigInteger (,$unsigned)
    $alphabet = '0123456789abcdefghijklmnopqrstuvwxyz'
    $hash = ''
    while ($number -gt [Numerics.BigInteger]::Zero) {
        $remainder = [Numerics.BigInteger]::Zero
        $number = [Numerics.BigInteger]::DivRem($number,[Numerics.BigInteger]36,[ref]$remainder)
        $hash = $alphabet[[int]$remainder] + $hash
    }
    return $hash
}
# 读取 Wrapper 两种 base 与相对路径，特殊/越界配置拒绝猜测。
function Get-JobsSetupWrapperZip {
    param([string]$Project,$Spec)
    $user = $env:GRADLE_USER_HOME
    if (-not $user) { $user = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.gradle' }
    if (-not [IO.Path]::IsPathRooted($user)) { throw 'GRADLE_USER_HOME 必须是绝对目录。' }
    $values = @{}
    foreach ($pair in @(@('distributionBase','GRADLE_USER_HOME'),@('zipStoreBase','GRADLE_USER_HOME'),@('distributionPath','wrapper/dists'),@('zipStorePath','wrapper/dists'))) {
        $found = [regex]::Matches($Spec.Properties,('(?m)^\s*' + $pair[0] + '\s*=\s*(.*?)\s*$'))
        if ($found.Count -gt 1) { throw ('Wrapper 配置重复：' + $pair[0]) }
        $values[$pair[0]] = if ($found.Count) { $found[0].Groups[1].Value.Replace('\/','/').Replace('\\','\') } else { $pair[1] }
    }
    foreach ($key in @('distributionBase','zipStoreBase')) { if ($values[$key] -cnotin @('GRADLE_USER_HOME','PROJECT')) { throw ('不支持的 Wrapper base：' + $key) } }
    foreach ($key in @('distributionPath','zipStorePath')) {
        if ([IO.Path]::IsPathRooted($values[$key]) -or $values[$key] -match '(^|[/\\])\.\.([/\\]|$)|:') { throw ('不安全的 Wrapper 相对目录：' + $key) }
    }
    $base = if ($values.zipStoreBase -ceq 'PROJECT') { Join-Path $Project 'android' } else { $user }
    $hash = Get-JobsSetupWrapperHash $Spec.Url
    $relative = $Spec.Name.Substring(0,$Spec.Name.Length - 4) + '/' + $hash + '/' + $Spec.Name
    $zip = Join-Path (Join-Path $base $values.zipStorePath) $relative
    Assert-JobsSetupFile $zip
    # 同时校验展开位置，避免 Wrapper 自行写入不安全目标。
    $distBase = if ($values.distributionBase -ceq 'PROJECT') { Join-Path $Project 'android' } else { $user }
    Assert-JobsSetupDirectory (Join-Path (Join-Path $distBase $values.distributionPath) ($Spec.Name.Substring(0,$Spec.Name.Length - 4) + '/' + $hash))
    return $zip
}
# 将已校验 ZIP 放入 Wrapper 真正缓存，在 Wrapper 的同一锁下原子发布。
function Publish-JobsSetupWrapperZip {
    param([string]$Project,$Spec,[string]$Archive,[string]$Checksum)
    $destination = Get-JobsSetupWrapperZip $Project $Spec
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
    $lockPath = $destination + '.lck'
    Assert-JobsSetupFile $lockPath
    $lock = $null
    try { $lock = New-Object IO.FileStream ($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) }
    catch { throw ('Wrapper 缓存正在被其它进程使用，请等构建结束重试：' + $destination) }
    $stage = $destination + '.jobs-' + [guid]::NewGuid().ToString('N')
    try {
        if ([IO.File]::Exists($destination) -and (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ieq $Checksum) { return }
        Copy-Item -LiteralPath $Archive -Destination $stage
        if ((Get-FileHash -LiteralPath $stage -Algorithm SHA256).Hash -ine $Checksum) { throw 'Wrapper 缓存复制后的 SHA-256 不符。' }
        Assert-JobsSetupFile $destination
        if ([IO.File]::Exists($destination)) { [IO.File]::Replace($stage,$destination,$null) }
        else { [IO.File]::Move($stage,$destination) }
        Write-JobsSetupMessage ('已验证 ZIP 写入标准 Wrapper 缓存：' + $destination)
    } finally {
        if ([IO.File]::Exists($stage)) { [IO.File]::Delete($stage) }
        if ($lock) { $lock.Dispose() }
    }
}
# 官方失败可切换官方备用及用户已选择的腾讯镜像，摘要始终取项目或官方。
function Install-JobsSetupGradle {
    param([string]$Project, $Java, [string]$Fzf)
    $spec = Get-JobsSetupGradleSpec $Project
    Assert-JobsSetupCompatibility $spec.Version $Java.Major $spec.Agp
    $choice = Select-JobsSetupChoice $Fzf 'Gradle 下载线路' @('官方 + 官方备用（推荐）','官方 + 官方备用 + 腾讯分发/阿里云插件镜像回退')
    $script:SetupMavenFallback = $choice -match '腾讯'
    $cache = Join-Path (Get-JobsInstallRoot) ('toolchains/gradle/' + $spec.Name.Replace('.zip',''))
    Assert-JobsSetupDirectory $cache
    [void][IO.Directory]::CreateDirectory($cache)
    $checksum = $spec.Checksum
    if (-not $checksum) {
        $sum = Join-Path $cache 'official.sha256'
        [void](Receive-JobsSetupFile @(('https://services.gradle.org/distributions/' + $spec.Name + '.sha256'), ('https://downloads.gradle.org/distributions/' + $spec.Name + '.sha256')) $sum 60)
        $checksum = [IO.File]::ReadAllText($sum).Trim()
        if ($checksum -cnotmatch '^[a-fA-F0-9]{64}$') { throw '官方 Gradle SHA-256 无效，不使用镜像自报摘要。' }
    }
    $zip = Join-Path $cache $spec.Name
    $urls = @($spec.Url, ('https://downloads.gradle.org/distributions/' + $spec.Name), ('https://services.gradle.org/distributions/' + $spec.Name)) | Select-Object -Unique
    if ($choice -match '腾讯') { $urls += 'https://mirrors.cloud.tencent.com/gradle/' + $spec.Name }
    if (-not [IO.File]::Exists($zip) -or (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ine $checksum) {
        [void](Receive-JobsSetupFile $urls $zip 900)
    }
    if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ine $checksum) { throw 'Gradle 分发 SHA-256 校验失败，未执行。' }
    $gradle = Join-Path $Project 'android/gradlew.bat'
    $jar = Join-Path $Project 'android/gradle/wrapper/gradle-wrapper.jar'
    foreach ($file in @($gradle,$jar)) { Assert-JobsSetupFile $file; if (-not [IO.File]::Exists($file)) { throw '工程 Wrapper 脚本或 JAR 缺失，未伪造生成文件。' } }
    if ([IO.File]::ReadAllText((Join-Path $Project 'android/gradle/wrapper/gradle-wrapper.properties')) -cne $spec.Properties) { throw '下载期间 Wrapper 声明已变化，请重新确认工程。' }
    Publish-JobsSetupWrapperZip $Project $spec $zip $checksum
    # 由工程自己的 Wrapper 解压、校验并创建 .ok；后续 flutter build 复用相同缓存。
    $actual = Invoke-JobsSetupProcess $gradle @('--version','--no-daemon') (Join-Path $Project 'android') 120
    if (($actual.StdOut + $actual.StdErr) -notmatch ('(?m)^Gradle ' + [regex]::Escape($spec.Version.ToString()) + '\s*$')) { throw 'Wrapper 实际 Gradle 版本与固定分发声明不符。' }
    Set-JobsSetupProgress deps.gradle done '工程 Wrapper 实际版本已复核' -Version ('Gradle '+$spec.Version.ToString())
    return $gradle
}
# 保存本工具本次选择；配置原文有备份，不删既有 FVM/jEnv 绑定。
function Save-JobsSetupProfile {
    param([string]$Project, $Flutter, $Java)
    $directory = Join-Path $Project '.jobs'
    $file = Join-Path $directory 'flutter-environment.json'
    Assert-JobsSetupFile $file
    [void][IO.Directory]::CreateDirectory($directory)
    if ([IO.File]::Exists($file)) { Copy-Item -LiteralPath $file -Destination ($file + '.' + [guid]::NewGuid().ToString('N') + '.bak') }
    $profile = [ordered]@{ Platform='Windows'; FlutterMode=$Flutter.Mode; FlutterPath=$Flutter.Flutter; JavaMode=$Java.Mode; JavaHome=$Java.Home }
    [IO.File]::WriteAllText($file, ($profile | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    Write-JobsSetupMessage ('本工程环境选择已保存：' + $file)
}
# 读取 Windows 本机配置，跨系统绝对路径不能静默沿用。
function Get-JobsSetupProfile {
    param([string]$Project)
    $file = Join-Path $Project '.jobs/flutter-environment.json'
    if (-not [IO.File]::Exists($file)) { return $null }
    Assert-JobsSetupFile $file
    $value = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $value.PSObject.Properties['Platform'] -or $value.Platform -cne 'Windows') { Write-JobsSetupMessage '工程环境选择来自其它平台，请重新选择当前电脑的 SDK。'; return $null }
    foreach ($name in @('FlutterMode','FlutterPath','JavaMode','JavaHome')) { if ($null -eq $value.PSObject.Properties[$name] -or $value.$name -isnot [string]) { throw '工程环境选择配置无效。' } }
    if ($value.FlutterMode -cnotin @('fvm','system') -or $value.JavaMode -cnotin @('jenv','system')) { throw '工程环境管理模式无效。' }
    return $value
}
# 进程级绑定 JVM 并阻断会覆盖它的 Gradle daemon criteria。
function Set-JobsSetupJavaProcess {
    param([string]$Project, $Java)
    $criteria = Join-Path $Project 'android/gradle/gradle-daemon-jvm.properties'
    if ([IO.File]::Exists($criteria)) { throw '工程存在 Gradle daemon JVM criteria，会优先于 JAVA_HOME；请先人工核对该文件，本工具不擅自覆盖。' }
    $env:JAVA_HOME = $Java.Home
    $env:PATH = (Join-Path $Java.Home 'bin') + [IO.Path]::PathSeparator + $env:PATH
    # 通过 JVM 系统属性阻止工程/用户 gradle.properties 的 org.gradle.java.home 覆盖。
    $env:GRADLE_OPTS = $env:GRADLE_OPTS + ' -Dorg.gradle.java.home="' + $Java.Home + '" -Dorg.gradle.internal.http.connectionTimeout=15000 -Dorg.gradle.internal.http.socketTimeout=30000'
}
# 可选 Maven 回退只通过本次 init script 增加，不覆盖工程或用户仓库配置。
function New-JobsSetupMirrorInit {
    param([string]$Directory)
    $path = Join-Path $Directory ('jobs-gradle-mirrors-' + [guid]::NewGuid().ToString('N') + '.gradle')
    $text = @'
// Jobs: selected per-run fallback repositories; project declarations remain intact.
if (gradle.gradleVersion.tokenize('.')[0].toInteger() >= 6) {
    gradle.beforeSettings { settings ->
        settings.pluginManagement.repositories {
            maven { url 'https://maven.aliyun.com/repository/gradle-plugin' }
            maven { url 'https://maven.aliyun.com/repository/google' }
            maven { url 'https://maven.aliyun.com/repository/public' }
            gradlePluginPortal()
            google()
            mavenCentral()
        }
    }
}
gradle.beforeProject { project ->
    project.buildscript.repositories {
        maven { url 'https://maven.aliyun.com/repository/google' }
        maven { url 'https://maven.aliyun.com/repository/public' }
        google()
        mavenCentral()
    }
}
'@
    [IO.File]::WriteAllText($path,$text,(New-Object Text.UTF8Encoding($false)))
    Write-JobsSetupMessage ('本次插件镜像：阿里云 Maven；init script：' + $path + '；退出后不再生效。插件仍遵循工程已有依赖校验规则。')
    return $path
}
# Java 独立管理也保留可复用选择，不伪装成已经更改整个系统 JAVA_HOME。
function Save-JobsSetupJavaProfile {
    param([string]$Project, $Java)
    $file = Join-Path $Project '.jobs/java-environment.json'
    Assert-JobsSetupFile $file
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $file))
    if ([IO.File]::Exists($file)) { Copy-Item -LiteralPath $file -Destination ($file + '.' + [guid]::NewGuid().ToString('N') + '.bak') }
    $data = [ordered]@{ Platform='Windows'; JavaMode=$Java.Mode; JavaHome=$Java.Home }
    [IO.File]::WriteAllText($file,($data | ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
}
# 临时只读版本探针，与插件解析在同一 Gradle 进程，取实际已应用插件版本。
function New-JobsSetupVersionInit {
 param([string]$Directory)
 $path=Join-Path $Directory ('jobs-gradle-version-'+[guid]::NewGuid().ToString('N')+'.gradle')
 $text=@'
gradle.projectsEvaluated {
    gradle.rootProject.allprojects.each { project ->
        project.plugins.each { plugin ->
            if (plugin.class.name.startsWith('com.android.')) {
                ['com.android.Version', 'com.android.builder.model.Version'].each { name ->
                    try {
                        def type = plugin.class.classLoader.loadClass(name)
                        def value = type.getField('ANDROID_GRADLE_PLUGIN_VERSION').get(null)
                        println('JOBS_TOOL_VERSION|AGP|' + value)
                    } catch (ReflectiveOperationException ignored) { }
                }
            }
        }
    }
}
'@
 [IO.File]::WriteAllText($path,$text,(New-Object Text.UTF8Encoding($false)))
 return $path
}
function Get-JobsSetupPluginVersion {
 param([string]$Text)
 $values=@([regex]::Matches($Text,'(?m)^JOBS_TOOL_VERSION\|AGP\|([^\r\n]+)')|ForEach-Object{$_.Groups[1].Value.Trim()}|Select-Object -Unique)
 if($values.Count){return 'AGP '+($values-join', ')}
 return 'AGP 实际版本未检测（未应用或插件未公开版本）'
}
# 用选定 Flutter 解析依赖，再以固定 Gradle 预热构建插件；仅网络故障允许再试一次。
function Invoke-JobsSetupDependencies {
    param([string]$Project, $Flutter, [string]$Gradle, [string]$Fzf)
    Set-JobsSetupProgress deps.pub running '解析工程 pub 依赖，复用已有凭证'
    try { [void](Invoke-JobsSetupProcess $Flutter.Flutter @('pub','get') $Project 900) } catch {
        Set-JobsSetupProgress deps.pub waiting '依赖获取失败；请在原始终端核对私库认证、VPN、网络与 SDK 约束'
        if (-not $Fzf) { throw }
        $retry = Select-JobsSetupChoice $Fzf 'pub get 未完成' @('已处理网络/认证问题，重试一次','停止本次配置')
        if ($retry.StartsWith('停止')) { throw '依赖尚未获取，已停止；已有准备结果保留。' }
        [void](Invoke-JobsSetupProcess $Flutter.Flutter @('pub','get') $Project 900)
    }
    Set-JobsSetupProgress deps.pub done 'pub get 成功'
    if (-not $Gradle) { Set-JobsSetupProgress deps.plugins skipped '所选平台不需要 Android Gradle 插件'; Write-JobsSetupMessage '本次非 Android 平台，Gradle/AGP 插件准备不适用；pub 依赖已处理。'; return }
    $local = Join-Path $Project 'android/local.properties'
    Assert-JobsSetupFile $local
    $before = if ([IO.File]::Exists($local)) { [IO.File]::ReadAllText($local) } else { '' }
    $escaped = $Flutter.Root.Replace('\','\\').Replace(':','\:').Replace(' ','\ ')
    $next = [regex]::Replace($before,'(?m)^\s*flutter\.sdk\s*=.*(?:\r?\n|$)','').TrimEnd("`r","`n") + "`r`nflutter.sdk=" + $escaped + "`r`n"
    if ($next -cne $before) {
        if ([IO.File]::Exists($local)) { Copy-Item -LiteralPath $local -Destination ($local + '.jobs-' + [guid]::NewGuid().ToString('N') + '.bak') }
        [IO.File]::WriteAllText($local,$next,(New-Object Text.UTF8Encoding($false)))
    }
    Set-JobsSetupProgress deps.plugins running '解析工程 AGP / Kotlin 插件'
    Write-JobsSetupMessage '开始解析项目原有 AGP/Kotlin/构建插件；不改仓库地址或插件版本。'
    $temporary=Join-Path ([IO.Path]::GetTempPath()) ('JobsGradleProbe-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($temporary)
    $parameters = @('help','--no-daemon','--stacktrace','--init-script',(New-JobsSetupVersionInit $temporary))
    if ((Get-Variable SetupMavenFallback -Scope Script -ErrorAction SilentlyContinue) -and $script:SetupMavenFallback) { $parameters += @('--init-script',(New-JobsSetupMirrorInit $temporary)) }
    try {
        for ($attempt = 1; $attempt -le 2; $attempt++) {
            try {
                $probe=Invoke-JobsSetupProcess $Gradle $parameters (Join-Path $Project 'android') 600
                Set-JobsSetupProgress deps.plugins done '构建插件已解析' -Version (Get-JobsSetupPluginVersion ($probe.StdOut+$probe.StdErr))
                return
            } catch {
                if ($attempt -eq 2 -or $_.Exception.Data['NetworkFailure'] -ne $true) { throw }
                Write-JobsSetupMessage 'Gradle 插件解析失败，使用已有缓存重试一次；若仍失败请检查日志中仓库与认证信息。'
            }
        }
    } finally { try{if([IO.Directory]::Exists($temporary)){[IO.Directory]::Delete($temporary,$true)}}catch{Write-JobsSetupMessage ('临时版本探针清理失败，路径：'+$temporary)} }
}
# doctor 与设备只读诊断，准备成功不等于应用已经可运行。
function Get-JobsSetupReadiness {
    param([string]$Project, $Flutter)
    $issues = New-Object 'System.Collections.Generic.List[string]'
    $platforms = @(@('android','windows','web','ohos') | Where-Object { [IO.Directory]::Exists((Join-Path $Project $_)) })
    if (-not $platforms.Count) { $issues.Add('工程没有当前 Windows 可用的 android/windows/web/ohos 平台目录。') }
    try {
        $doctor = Invoke-JobsSetupProcess $Flutter.Flutter @('doctor','-v') $Project 180
        if (($doctor.StdOut + $doctor.StdErr) -match '\[!\]|\[x\]|\[✗\]') { $issues.Add('flutter doctor 仍有缺项；按日志核对 Android SDK/许可证、Java、Visual Studio 或其它工具。') }
    } catch { $issues.Add('flutter doctor 未通过或超时，请检查日志。') }
    try {
        $devices = Invoke-JobsSetupProcess $Flutter.Flutter @('devices','--machine') $Project 90
        $parsed = $devices.StdOut | ConvertFrom-Json -ErrorAction Stop
        $usable = @($parsed | Where-Object { $_.isSupported -ne $false -and (($_.targetPlatform -like 'android*' -and 'android' -in $platforms) -or ($_.targetPlatform -like 'windows*' -and 'windows' -in $platforms) -or ($_.targetPlatform -like 'web*' -and 'web' -in $platforms) -or ($_.targetPlatform -match '^(ohos|openharmony)' -and 'ohos' -in $platforms)) })
        if (-not $usable.Count) { $issues.Add('没有与当前工程平台匹配的已连接设备/桌面/Web 目标；需要启动模拟器、连接设备或补齐目标平台。') }
    } catch { $issues.Add('设备列表读取或解析失败，未验证运行目标。') }
    if ($issues.Count) {
        Write-JobsSetupMessage '环境准备结束，运行前仍需处理：'
        foreach ($issue in $issues) { Write-JobsSetupMessage ('- ' + $issue) }
    } else { Write-JobsSetupMessage 'doctor 与匹配设备只读检查通过。' }
    Write-JobsSetupMessage '运行前另须核对项目入口 lib/main*.dart、flavor、dart-define、私库凭证及 Android applicationId；依赖准备可能已执行 debug 构建，仍未安装或启动应用；SDK 许可证必须由本人处理。'
    return [pscustomobject]@{ Ready=($issues.Count -eq 0); Issues=@($issues); Platforms=$platforms }
}
# Windows 环境键不区分大小写，.NET Framework 返回的字典却区分；按宿主语义保存存在性。
function Get-JobsSetupEnvironmentSnapshot {
    param([string[]]$Names)
    $environment = [Environment]::GetEnvironmentVariables('Process')
    $comparison = [StringComparison]::Ordinal
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { $comparison = [StringComparison]::OrdinalIgnoreCase }
    $snapshot = @{}
    foreach ($name in $Names) {
        $exists = $false
        foreach ($actualName in $environment.Keys) {
            if ([string]::Equals([string]$actualName, $name, $comparison)) { $exists = $true; break }
        }
        $snapshot[$name] = @{ Exists=$exists; Value=[Environment]::GetEnvironmentVariable($name,'Process') }
    }
    return $snapshot
}
# 区分未设置与空字符串；旧 Framework 的 .NET API 会把空值当成删除。
function Restore-JobsSetupEnvironment {
    param([hashtable]$Snapshot)
    foreach ($key in $Snapshot.Keys) {
        $item = $Snapshot[$key]
        if (-not $item.Exists) { Remove-Item ('Env:' + $key) -ErrorAction SilentlyContinue }
        elseif ($item.Value -ceq '' -and [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
            if (-not ('Jobs.SetupEnvironment' -as [type])) {
                Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; namespace Jobs { public static class SetupEnvironment { [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] public static extern bool SetEnvironmentVariable(string name, string value); } }'
            }
            if (-not [Jobs.SetupEnvironment]::SetEnvironmentVariable($key,'')) { throw ('恢复空环境变量失败：' + $key) }
        } else { Set-Item ('Env:' + $key) -Value $item.Value }
    }
}
# 无 TTY 的 CLI 不允许把 EOF 当成默认确认。
function Test-JobsSetupInteractive { return -not [Console]::IsInputRedirected }
# 独立入口负责自述、防误触、步骤停止和环境精确恢复。
function Invoke-JobsProjectSetupAction {
    param([string]$Target, [ValidateSet('project-setup','gradle-download','java-manage')][string]$Action)
    Write-Host 'Flutter 项目环境与 Gradle 插件准备' -ForegroundColor Red
    Write-Host '影响：可安装所选 Flutter/JDK/jEnv 与平台工具、绑定工程 SDK、获取依赖并实际运行；Windows C++ 安装可能请求管理员 UAC，由本人确认。保留原版本声明，不改全局 SDK/PATH、代理或持久镜像。'
    Write-Host 'FVM/jEnv 优先，可用 fzf 选择系统 SDK；Esc/Ctrl+C 取消，← 返回上一层。已完成的安装/绑定会保留，取消仅停止后续步骤。日志位于本包 logs。'
    if (-not (Test-JobsSetupInteractive)) { throw '当前无可交互控制台，请从右键仪表盘或真实终端运行。' }
    if ((Read-Host '回车继续，任意非空输入取消') -ne '') { throw '已取消，未配置环境。' }
    $project = Resolve-JobsTarget $Target
    Assert-JobsSetupDirectory $project
    $worker = Import-Module (Join-Path $PSScriptRoot 'Actions/sdk-manage/Scripts/Action.psm1') -PassThru -DisableNameChecking
    & $worker { param($p) Assert-JobsFlutterProject $p } $project
    $logs = Join-Path (Get-JobsInstallRoot) 'logs'
    [void][IO.Directory]::CreateDirectory($logs)
    $script:SetupLog = Join-Path $logs ('project-setup-' + [guid]::NewGuid().ToString('N') + '.log')
    Write-JobsSetupMessage ('工程：' + $project + '；动作：' + $Action + '；日志：' + $script:SetupLog)
    $saved = Get-JobsSetupEnvironmentSnapshot @('JAVA_HOME','PATH','GRADLE_OPTS','ANDROID_HOME','ANDROID_SDK_ROOT','TOOL_HOME','DEVECO_SDK_HOME','NO_COLOR','FORCE_COLOR','CLICOLOR','ANSI_COLORS_DISABLED','npm_config_color')
    try {
        $fzf = Get-JobsSetupFzf $project
        $platform = $null
        if ($Action -eq 'project-setup') { Set-JobsSetupProgress platform.select running '选择本工程已存在的平台'; $platform = Select-JobsSetupPlatform $project $fzf; Set-JobsSetupProgress platform.select done $platform }
        $profile = if ($Action -eq 'gradle-download') { Get-JobsSetupProfile $project } else { $null }
        if ($Action -eq 'java-manage') {
            $java = Select-JobsSetupJava $project $fzf
            Set-JobsSetupProgress sdk.java done ('Java '+$java.Major) -Version ((Get-JobsSetupDetectedVersion $java)+' / '+$(if($java.Mode-ceq'jenv'){Get-JobsSetupManagerVersion 'jenv' $project}else{'jEnv 不适用（系统模式）'}))
            Save-JobsSetupJavaProfile $project $java
            Write-JobsSetupMessage ('Java 已检查：' + $java.Home + '；模式：' + $java.Mode + '。系统模式仅本次选择；完整保存请运行一键配置。')
            return
        }
        if ($profile) {
            $flutter = Get-JobsSetupFlutter $profile.FlutterPath $project $profile.FlutterMode
            $java = Get-JobsSetupJava $profile.JavaHome $project
            $java | Add-Member -NotePropertyName Mode -NotePropertyValue $profile.JavaMode
        } else {
            Set-JobsSetupProgress sdk.flutter running '选择或安装 Flutter SDK'
            $flutter = Select-JobsSetupFlutter $project $fzf $platform
            Set-JobsSetupProgress sdk.flutter done $flutter.Mode -Version (Get-JobsSetupDetectedVersion $flutter)
            $javaFile = Join-Path $project '.jobs/java-environment.json'
            $java = $null
            if ([IO.File]::Exists($javaFile)) {
                Assert-JobsSetupFile $javaFile
                $javaSaved = Get-Content -LiteralPath $javaFile -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($javaSaved.Platform -ceq 'Windows' -and $javaSaved.JavaMode -cin @('jenv','system')) {
                    $reuse = Select-JobsSetupChoice $fzf 'Java 已保存选择' @('复用已保存的 Java SDK','重新安装/切换 Java SDK')
                    if ($reuse.StartsWith('复用')) { $java = Get-JobsSetupJava $javaSaved.JavaHome $project; $java | Add-Member -NotePropertyName Mode -NotePropertyValue $javaSaved.JavaMode }
                }
            }
            if ($null -eq $java) { Set-JobsSetupProgress sdk.java running '选择或安装 Java SDK'; $java = Select-JobsSetupJava $project $fzf }; Set-JobsSetupProgress sdk.java done ('Java ' + $java.Major)
        }
        Set-JobsSetupProgress sdk.flutter done $flutter.Mode -Version (Get-JobsSetupDetectedVersion $flutter)
        $javaVersion=Get-JobsSetupDetectedVersion $java
        $javaManager=if($java.Mode-ceq'jenv'){Get-JobsSetupManagerVersion 'jenv' $project}else{'jEnv 不适用（系统模式）'}
        Set-JobsSetupProgress sdk.java done ('Java '+$java.Major+'；'+$java.Mode) -Version ($javaVersion+' / '+$javaManager)
        if ($Action -eq 'gradle-download' -or $platform -eq 'Android') { Set-JobsSetupJavaProcess $project $java }
        if ($Action -eq 'project-setup') { Initialize-JobsSetupPlatform $project $flutter $java $fzf $platform }
        Set-JobsSetupProgress deps.gradle running '准备工程固定 Gradle 分发'
        $gradle = $null
        if ([IO.Directory]::Exists((Join-Path $project 'android')) -and ($Action -eq 'gradle-download' -or $platform -eq 'Android')) { $gradle = Install-JobsSetupGradle $project $java $fzf }
        elseif ($Action -eq 'gradle-download') { throw '当前工程没有 Android 平台，下载 Gradle 插件不适用。' }
        else { Write-JobsSetupMessage '本次未选择 Android 平台，Gradle 不适用；继续 pub 与运行前检查。' }
        Set-JobsSetupProgress deps.gradle $(if($gradle){'done'}else{'skipped'}) 'Gradle 分发阶段结束'
        Save-JobsSetupProfile $project $flutter $java
        Invoke-JobsSetupDependencies $project $flutter $gradle $fzf
        $buildArguments = $null
        if ($Action -eq 'project-setup') { $buildArguments = Invoke-JobsSetupTargetDependencies $project $flutter $java $fzf $platform $gradle }
        Write-JobsSetupMessage '所选 SDK 与 pub 依赖准备完成；存在 Android 平台时，固定 Gradle 分发和构建插件已解析。'
        Set-JobsSetupProgress run.doctor running '只读 doctor 与设备诊断'
        $readiness = Get-JobsSetupReadiness $project $flutter
        Set-JobsSetupProgress run.doctor $(if($readiness.Ready){'done'}else{'waiting'}) '诊断结果见原始终端；可继续处理所选平台运行目标'
        if ($Action -eq 'project-setup') { Invoke-JobsSetupRunVerification $project $flutter $fzf $platform $buildArguments }
        elseif (-not $readiness.Ready) { throw ('环境准备完成，但运行前诊断仍有缺项；未验证应用可运行。日志：' + $script:SetupLog) }
    } finally {
        Restore-JobsSetupEnvironment $saved
        Remove-Variable SetupLog -Scope Script -ErrorAction SilentlyContinue
    }
}
Export-ModuleMember -Function Invoke-JobsProjectSetupAction, Invoke-JobsProjectDependencyAction, Invoke-JobsProjectDependencyArchiveAction

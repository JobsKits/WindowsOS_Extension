# Action.psm1
# JobsFlutterVersionMgr
# Created by Jobs on 2026年10月19日，星期一.
# 在精确 Flutter 项目根选择并绑定 SDK；不设置 FVM 全局版本。

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking

function Write-JobsFvmMessage {
    param([string]$Message)
    $safe = $Message -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@'
    $safe = $safe -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]'
    $safe = $safe -replace '(?im)((?:token|password|secret|authorization)\s*[:=]\s*)\S+', '$1[已省略]'
    Write-Host $safe
    $logs = Join-Path (Get-JobsInstallRoot) 'logs'
    [void][IO.Directory]::CreateDirectory($logs)
    if (-not (Get-Variable -Name FvmSessionLog -Scope Script -ErrorAction SilentlyContinue)) {
        $script:FvmSessionLog = Join-Path $logs ('fvm-' + (Get-Date -Format 'yyyy-MM-dd-HH-mm-ss') + '-' + [guid]::NewGuid().ToString('N') + '.log')
    }
    [IO.File]::AppendAllText($script:FvmSessionLog, ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $safe + [Environment]::NewLine), (New-Object Text.UTF8Encoding($true)))
}

function Assert-JobsFvmDirectory {
    param([string]$Path)
    if (-not [IO.Path]::IsPathRooted($Path) -or -not [IO.Directory]::Exists($Path)) {
        throw "目标必须是存在的绝对目录：$Path"
    }
    $item = New-Object IO.DirectoryInfo ([IO.Path]::GetFullPath($Path))
    $current = $item
    while ($null -ne $current) {
        if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "不处理符号链接或目录联接：$($current.FullName)"
        }
        $current = $current.Parent
    }
    return $item.FullName
}

function Assert-JobsFvmPlainFile {
    param([string]$Path)
    $attributes = [IO.File]::GetAttributes($Path)
    if (($attributes -band [IO.FileAttributes]::Directory) -ne 0 -or ($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "配置必须是普通文件：$Path"
    }
}

function Test-JobsFvmPathEntry {
    param([string]$Path)
    # File.Exists/Test-Path 会将悬空链接当作不存在，GetAttributes 仍能识别链接本身。
    try { [void][IO.File]::GetAttributes($Path); return $true }
    catch [IO.FileNotFoundException] { return $false }
    catch [IO.DirectoryNotFoundException] { return $false }
}

function Remove-JobsYamlComment {
    param([string]$Line)
    $quote = [char]0
    for ($i = 0; $i -lt $Line.Length; $i++) {
        $character = $Line[$i]
        if ($quote -eq [char]34 -and $character -eq [char]92) { $i++; continue }
        if ($quote -eq [char]39 -and $character -eq [char]39 -and $i + 1 -lt $Line.Length -and $Line[$i + 1] -eq [char]39) { $i++; continue }
        if ($quote -ne [char]0) {
            if ($character -eq $quote) { $quote = [char]0 }
            continue
        }
        if ($character -eq [char]39 -or $character -eq [char]34) { $quote = $character; continue }
        if ($character -eq '#' -and ($i -eq 0 -or [char]::IsWhiteSpace($Line[$i - 1]))) {
            return $Line.Substring(0, $i).TrimEnd()
        }
    }
    return $Line.TrimEnd()
}

function ConvertFrom-JobsYamlAtom {
    param([string]$Value)
    $valueText = $Value.Trim()
    if ($valueText -match '^''([^'']*)''$' -or $valueText -match '^"([^"\\]*)"$') { return $Matches[1] }
    return $valueText
}

function ConvertFrom-JobsYamlFlowMap {
    param([string]$Text)
    $value = $Text.Trim()
    if (-not $value.StartsWith('{') -or -not $value.EndsWith('}')) { throw '只支持明确的 YAML 映射，不支持别名、标签或多行 flow 结构。' }
    $body = $value.Substring(1, $value.Length - 2)
    $parts = New-Object 'System.Collections.Generic.List[string]'
    $depth = 0
    $quote = [char]0
    $start = 0
    for ($i = 0; $i -lt $body.Length; $i++) {
        $character = $body[$i]
        if ($quote -eq [char]34 -and $character -eq [char]92) { $i++; continue }
        if ($quote -ne [char]0) {
            if ($character -eq $quote) { $quote = [char]0 }
            continue
        }
        if ($character -eq [char]39 -or $character -eq [char]34) { $quote = $character; continue }
        if ($character -eq '{' -or $character -eq '[') { $depth++ }
        if ($character -eq '}' -or $character -eq ']') { $depth-- }
        if ($depth -lt 0) { throw 'YAML flow 映射括号不匹配。' }
        if ($character -eq ',' -and $depth -eq 0) { $parts.Add($body.Substring($start, $i - $start)); $start = $i + 1 }
    }
    if ($quote -ne [char]0 -or $depth -ne 0) { throw 'YAML flow 映射未闭合。' }
    $parts.Add($body.Substring($start))
    $map = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    foreach ($part in $parts) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        if ($part -notmatch '^\s*(?<key>[A-Za-z_][A-Za-z0-9_-]*|''[^'']+''|"[^"\\]+")\s*:\s*(?<value>.*?)\s*$' -or
            $part -match '^\s*[A-Za-z_][A-Za-z0-9_-]*\s*:\S') { throw '无法可靠读取 YAML flow 映射；未引用键的冒号后须留空格。' }
        $key = ConvertFrom-JobsYamlAtom $Matches['key']
        $entry = $Matches['value']
        if ($map.ContainsKey($key)) { throw "YAML 存在重复键：$key" }
        $map[$key] = $entry
    }
    return $map
}

function Test-JobsFlutterPubspec {
    param([string]$Text)
    # 只解释 dependencies.flutter.sdk，不能把 description、注释或 flutter_test 当作 Flutter 项目。
    $lines = @($Text -split '\r?\n' | ForEach-Object { Remove-JobsYamlComment $_ })
    if (@($lines | Where-Object { $_ -match '^\s*\t' }).Count -gt 0) { return $false }
    $roots = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -cmatch '^(?:dependencies|''dependencies''|"dependencies")\s*:\s*(.*)$') {
            $roots += [pscustomobject]@{ Index = $i; Value = $Matches[1] }
        }
    }
    if ($roots.Count -ne 1) { return $false }
    try {
        if (-not [string]::IsNullOrWhiteSpace($roots[0].Value)) {
            $dependencies = ConvertFrom-JobsYamlFlowMap $roots[0].Value
            if (-not $dependencies.ContainsKey('flutter')) { return $false }
            $flutter = ConvertFrom-JobsYamlFlowMap $dependencies['flutter']
            return $flutter.ContainsKey('sdk') -and (ConvertFrom-JobsYamlAtom $flutter['sdk']) -ceq 'flutter'
        }
        $entries = @()
        for ($i = $roots[0].Index + 1; $i -lt $lines.Count; $i++) {
            if ([string]::IsNullOrWhiteSpace($lines[$i])) { continue }
            if ($lines[$i] -notmatch '^\s') { break }
            if ($lines[$i] -notmatch '^(?<indent> +)(?<key>[A-Za-z_][A-Za-z0-9_-]*|''[^'']+''|"[^"\\]+")\s*:\s*(?<value>.*)$') { continue }
            $entries += [pscustomobject]@{ Indent = $Matches['indent'].Length; Key = (ConvertFrom-JobsYamlAtom $Matches['key']); Value = $Matches['value']; Index = $i }
        }
        if ($entries.Count -eq 0) { return $false }
        $minimum = ($entries | Measure-Object -Property Indent -Minimum).Minimum
        $declarations = @($entries | Where-Object { $_.Indent -eq $minimum -and $_.Key -ceq 'flutter' })
        if ($declarations.Count -ne 1) { return $false }
        $declaration = $declarations[0]
        if (-not [string]::IsNullOrWhiteSpace($declaration.Value)) {
            $flutter = ConvertFrom-JobsYamlFlowMap $declaration.Value
            return $flutter.ContainsKey('sdk') -and (ConvertFrom-JobsYamlAtom $flutter['sdk']) -ceq 'flutter'
        }
        $children = @()
        foreach ($entry in $entries) {
            if ($entry.Index -le $declaration.Index) { continue }
            if ($entry.Indent -le $declaration.Indent) { break }
            $children += $entry
        }
        if ($children.Count -eq 0) { return $false }
        $childIndent = ($children | Measure-Object -Property Indent -Minimum).Minimum
        $sdk = @($children | Where-Object { $_.Indent -eq $childIndent -and $_.Key -ceq 'sdk' })
        return $sdk.Count -eq 1 -and (ConvertFrom-JobsYamlAtom $sdk[0].Value) -ceq 'flutter'
    }
    catch { return $false }
}

function Assert-JobsFlutterProject {
    param([string]$Directory)
    [void](Assert-JobsFvmDirectory $Directory)
    $pubspec = Join-Path $Directory 'pubspec.yaml'
    Assert-JobsFvmPlainFile $pubspec
    if (-not (Test-JobsFlutterPubspec (Get-Content -LiteralPath $pubspec -Raw -Encoding UTF8))) {
        throw '目标同层 pubspec.yaml 必须明确声明 dependencies.flutter.sdk: flutter；不会扫描子目录或沿用父工程。YAML 别名、标签及多行 flow 映射请先改成常见 block 写法。'
    }
}

function Invoke-JobsFvmTool {
    param([string]$File, [string[]]$Arguments = @(), [string]$Directory, [switch]$Visible, [int]$TimeoutSeconds = 30)
    if ($File -match '["\x00-\x1f]' -or @($Arguments | Where-Object { $_ -cnotmatch '^[A-Za-z0-9._@:+-]+$' }).Count -gt 0) {
        throw '工具路径或参数包含不支持的控制字符。'
    }
    $executable = $File
    $parameters = $Arguments
    $batch = [IO.Path]::GetExtension($File) -in @('.cmd', '.bat')
    if ($batch) {
        $executable = Join-Path ([Environment]::GetFolderPath('System')) 'cmd.exe'
        $parameters = @('/d', '/v:off', '/s', '/c')
    }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $executable
    if ($batch) {
        $start.EnvironmentVariables['JOBS_FVM_EXECUTABLE'] = $File
        $start.Arguments = '/d /v:off /s /c ""%JOBS_FVM_EXECUTABLE%" ' + ($Arguments -join ' ') + '"'
    }
    else { $start.Arguments = (@($parameters | ForEach-Object { Quote-JobsArgument $_ }) -join ' ') }
    $start.WorkingDirectory = $Directory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = -not $Visible
    $start.RedirectStandardOutput = -not $Visible
    $start.RedirectStandardError = -not $Visible
    if (-not $Visible) {
        $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
        $start.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    }
    $start.EnvironmentVariables['CI'] = 'true'
    $start.EnvironmentVariables['FLUTTER_SUPPRESS_ANALYTICS'] = 'true'
    $start.EnvironmentVariables['DART_SUPPRESS_ANALYTICS'] = 'true'
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw '无法启动工具。' }
        if (-not $Visible) {
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
        }
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $taskkill = Join-Path ([Environment]::GetFolderPath('System')) 'taskkill.exe'
            [void](Invoke-JobsProcess $taskkill @('/PID', [string]$process.Id, '/T', '/F') -WorkingDirectory $Directory)
            throw '操作超时；已尝试终止本次进程树，请检查终端和日志。'
        }
        $output = ''
        $errors = ''
        if (-not $Visible) {
            if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout, $stderr), 5000)) { throw '工具输出管道未按时关闭。' }
            $output = $stdout.GetAwaiter().GetResult()
            $errors = $stderr.GetAwaiter().GetResult()
        }
        return [pscustomobject]@{ ExitCode = $process.ExitCode; StdOut = $output; StdErr = $errors }
    }
    finally { $process.Dispose() }
}

function Find-JobsHealthyFvmTool {
    param([string]$Name, [string[]]$Candidates, [string]$Directory)
    $paths = @()
    foreach ($candidate in @($Name) + $Candidates) {
        $path = Find-JobsExecutable -Name $candidate -Candidates @()
        if (-not $path -or $path -in $paths) { continue }
        $paths += $path
        try {
            $result = Invoke-JobsFvmTool $path @('--version') $Directory
            if ($result.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($result.StdOut + $result.StdErr)) {
                Write-JobsFvmMessage ("健康：{0} → {1}；{2}" -f $Name, $path, ($result.StdOut + $result.StdErr).Trim())
                return $path
            }
        }
        catch { Write-JobsFvmMessage "体检失败：$path" }
    }
    return $null
}

function Update-JobsFvmSessionPath {
    # 安装器通常更新注册表 PATH；只将新增目录并入当前进程，不覆盖进程原有路径。
    $paths = @($env:PATH -split [IO.Path]::PathSeparator)
    foreach ($scope in @('User', 'Machine')) {
        $paths += @([Environment]::GetEnvironmentVariable('PATH', $scope) -split [IO.Path]::PathSeparator)
    }
    $paths += @((Join-Path $env:LOCALAPPDATA 'Microsoft/WinGet/Links'), (Join-Path $env:LOCALAPPDATA 'Programs/Git/cmd'))
    $env:PATH = (@($paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique) -join [IO.Path]::PathSeparator)
}

function Install-JobsWingetTool {
    param([string]$Id, [string]$Directory)
    $winget = Find-JobsHealthyFvmTool 'winget.exe' @() $Directory
    if (-not $winget) {
        Write-JobsFvmMessage 'WinGet 不健康或缺失。请在 Microsoft Store 安装/更新 App Installer 后重开菜单；不继续下游安装。'
        Start-Process -FilePath 'ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1'
        throw '工具链阻塞在 WinGet/App Installer。'
    }
    Write-JobsFvmMessage "安装来源：WinGet 官方 winget 源；包：$Id；范围：当前用户。安装器可能联网。"
    if ((Read-Host "缺少必需组件 $Id；回车安装，任意字符取消整个流程") -ne '') { throw '已取消必需组件安装。' }
    $result = Invoke-JobsFvmTool $winget @('install', '--id', $Id, '--exact', '--source', 'winget', '--scope', 'user', '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity') $Directory -Visible -TimeoutSeconds 1800
    if ($result.ExitCode -ne 0) { throw "WinGet 安装失败：$Id（$($result.ExitCode)）。请修复此层后重试。" }
    Update-JobsFvmSessionPath
}

function Read-JobsFvmWebJson {
    param([string]$Uri)
    Write-JobsFvmMessage "查询来源：$Uri"
    $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec 20 -Headers @{ 'User-Agent' = 'JobsFlutterVersionMgr'; 'Accept' = 'application/json' }
    return $response.Content | ConvertFrom-Json -ErrorAction Stop
}

function Install-JobsStandaloneFvm {
    param([string]$Directory)
    $architecture = $env:PROCESSOR_ARCHITEW6432
    if ([string]::IsNullOrWhiteSpace($architecture)) { $architecture = $env:PROCESSOR_ARCHITECTURE }
    switch ($architecture.ToUpperInvariant()) {
        'AMD64' { $architecture = 'x64' }
        'ARM64' { $architecture = 'arm64' }
        default { throw '官方 FVM 独立包仅支持 Windows x64 / ARM64，请使用 64 位系统。' }
    }
    $release = Read-JobsFvmWebJson 'https://api.github.com/repos/btwld/fvm/releases/latest'
    if ($release.tag_name -cnotmatch '^v?\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$') { throw 'FVM release 版本格式无效。' }
    $assets = @($release.assets | Where-Object { $_.name -match ('^fvm-.*-windows-' + $architecture + '\.zip$') })
    if ($assets.Count -ne 1) { throw '未找到唯一的官方 FVM Windows 架构包。' }
    $asset = $assets[0]
    if ($asset.browser_download_url -cnotmatch '^https://github\.com/(?:btwld|leoafarias)/fvm/releases/download/[^/]+/fvm-[^/]+\.zip$' -or
        $null -eq $asset.PSObject.Properties['digest'] -or $asset.digest -cnotmatch '^sha256:[a-f0-9]{64}$') {
        throw 'FVM 包来源或官方 SHA-256 digest 不可验证，已停止。'
    }
    Write-JobsFvmMessage ("FVM 来源：{0}；架构：{1}；SHA-256：{2}" -f $asset.browser_download_url, $architecture, $asset.digest)
    if ((Read-Host '缺少健康 FVM；回车下载官方独立包到本功能 tools，任意字符取消') -ne '') { throw '已取消 FVM 安装。' }
    $tools = Join-Path (Get-JobsInstallRoot) 'tools'
    [void][IO.Directory]::CreateDirectory($tools)
    $stage = Join-Path $tools ('fvm-stage-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($stage)
    try {
        $zip = Join-Path $stage 'fvm.zip'
        Invoke-WebRequest -Uri $asset.browser_download_url -UseBasicParsing -TimeoutSec 300 -OutFile $zip
        if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant() -cne $asset.digest.Substring(7)) { throw '官方 FVM 下载包 SHA-256 不匹配。' }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($zip)
        try {
            foreach ($entry in $archive.Entries) {
                $path = $entry.FullName.Replace('\', '/')
                if ($path.StartsWith('/') -or $path -match '(^|/)\.\.(/|$)|:') { throw 'FVM 压缩包含越界路径。' }
            }
        }
        finally { $archive.Dispose() }
        $expanded = Join-Path $stage 'expanded'
        Expand-Archive -LiteralPath $zip -DestinationPath $expanded
        $executables = @(Get-ChildItem -LiteralPath $expanded -Recurse -File -Filter 'fvm.exe')
        if ($executables.Count -ne 1) { throw '官方 FVM 压缩包未包含唯一 fvm.exe。' }
        $check = Invoke-JobsFvmTool $executables[0].FullName @('--version') $Directory
        if ($check.ExitCode -ne 0) { throw '下载的 FVM 无法执行。' }
        $destination = Join-Path $tools ('fvm-' + $release.tag_name + '-' + [guid]::NewGuid().ToString('N'))
        Move-Item -LiteralPath $expanded -Destination $destination
        $relative = $executables[0].FullName.Substring($expanded.Length).TrimStart([char]92, [char]47)
        $installed = Join-Path $destination $relative
        [IO.File]::WriteAllText((Join-Path $tools 'fvm-path.txt'), $installed, (New-Object Text.UTF8Encoding($false)))
        return $installed
    }
    finally { if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force } }
}

function Get-JobsFvmToolchain {
    param([string]$Directory, [string]$InspectionDirectory)
    $gitCandidates = @((Join-Path $env:LOCALAPPDATA 'Programs/Git/cmd/git.exe'))
    if ($env:ProgramFiles) { $gitCandidates += Join-Path $env:ProgramFiles 'Git/cmd/git.exe' }
    $git = Find-JobsHealthyFvmTool 'git.exe' $gitCandidates $Directory
    if (-not $git) { Install-JobsWingetTool 'Git.Git' $Directory; $git = Find-JobsHealthyFvmTool 'git.exe' $gitCandidates $Directory }
    if (-not $git) { throw 'Git 安装后二次体检失败，已停止。' }
    # 健康但原本不在 PATH 的 Git 必须让 FVM 子进程可见。
    $env:PATH = (Split-Path -Parent $git) + [IO.Path]::PathSeparator + $env:PATH
    $fzf = Find-JobsHealthyFvmTool 'fzf.exe' @() $Directory
    if (-not $fzf) { Install-JobsWingetTool 'junegunn.fzf' $Directory; $fzf = Find-JobsHealthyFvmTool 'fzf.exe' @() $Directory }
    if (-not $fzf) { throw 'fzf 安装后二次体检失败，已停止。' }
    $candidates = @('fvm.bat', 'fvm.cmd')
    $pointer = Join-Path (Get-JobsInstallRoot) 'tools/fvm-path.txt'
    if (Test-Path -LiteralPath $pointer -PathType Leaf) { $candidates += (Get-Content -LiteralPath $pointer -Raw -Encoding UTF8).Trim() }
    $fvm = Find-JobsHealthyFvmTool 'fvm.exe' $candidates $Directory
    if (-not $fvm) { $fvm = Install-JobsStandaloneFvm $Directory }
    $check = Invoke-JobsFvmTool $fvm @('api', 'context', '--compress') $InspectionDirectory
    if ($check.ExitCode -ne 0) { throw 'FVM 版本存在但 JSON API 不健康，请修复或升级 FVM 后重试。' }
    try { $context = ($check.StdOut | ConvertFrom-Json -ErrorAction Stop).context }
    catch { throw 'FVM api context 无法解析。' }
    if ($null -eq $context -or $null -eq $context.PSObject.Properties['flutterUrl']) { throw 'FVM 未提供有效下载来源。' }
    if ($null -eq $context.PSObject.Properties['versionsCachePath'] -or -not [IO.Path]::IsPathRooted([string]$context.versionsCachePath)) {
        throw 'FVM 有效 SDK 缓存必须是绝对路径，请检查项目、全局配置及 FVM_CACHE_PATH。'
    }
    Write-JobsFvmMessage ("FVM SDK Git 来源：{0}；缓存目录：{1}" -f $context.flutterUrl, $context.versionsCachePath)
    return [pscustomobject]@{ Git = $git; Fzf = $fzf; Fvm = $fvm; Context = $context }
}

function Test-JobsFlutterVersion {
    param([string]$Version)
    return $Version -cmatch '^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$'
}

function Get-JobsFvmCachedVersions {
    param([string]$Fvm, [string]$Directory)
    $result = Invoke-JobsFvmTool $Fvm @('api', 'list', '--compress', '--skip-size-calculation') $Directory
    if ($result.ExitCode -ne 0) { throw '无法读取 FVM 已缓存 SDK 列表。' }
    $data = $result.StdOut | ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $data.PSObject.Properties['versions']) { throw 'FVM 缓存清单缺少 versions。' }
    foreach ($version in @($data.versions)) {
        if (-not (Test-JobsFlutterVersion ([string]$version.name))) { continue }
        $ready = $null -ne $version.PSObject.Properties['isSetup'] -and $version.isSetup -eq $true
        $directoryPath = [string]$version.directory
        $ready = $ready -and [IO.File]::Exists((Join-Path $directoryPath 'bin/flutter.bat')) -and [IO.File]::Exists((Join-Path $directoryPath 'bin/cache/dart-sdk/bin/dart.exe'))
        [pscustomobject]@{ Version = [string]$version.name; Ready = $ready; Directory = $directoryPath }
    }
}

function ConvertFrom-JobsFlutterManifest {
    param($Manifest)
    if ($null -eq $Manifest.PSObject.Properties['releases'] -or $null -eq $Manifest.PSObject.Properties['current_release']) { throw 'Flutter 官方版本清单缺少必要字段。' }
    $seen = @{}
    foreach ($release in @($Manifest.releases | Sort-Object -Property release_date -Descending)) {
        $version = [string]$release.version
        if (-not (Test-JobsFlutterVersion $version) -or $release.channel -notin @('stable', 'beta', 'dev') -or $seen.ContainsKey($version)) { continue }
        $seen[$version] = $true
        $channel = [string]$release.channel
        $latest = $null -ne $Manifest.current_release.PSObject.Properties[$channel] -and $Manifest.current_release.$channel -ceq $release.hash
        [pscustomobject]@{ Version = $version; Channel = $channel; Date = ([string]$release.release_date).Split('T')[0]; Latest = $latest }
    }
    if ($seen.Count -eq 0) { throw 'Flutter 版本清单没有有效版本。' }
}

function Get-JobsFlutterReleaseChoices {
    param([object[]]$Cached, [string]$Current)
    $url = 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json'
    $offline = $false
    $releases = @()
    try { $releases = @(ConvertFrom-JobsFlutterManifest (Read-JobsFvmWebJson $url)) }
    catch {
        $offline = $true
        Write-JobsFvmMessage '官方历史/最新版本查询失败；仅提供已完成初始化的本机缓存，不能据此判断最新版本。'
    }
    $byVersion = @{}
    foreach ($entry in $Cached) { $byVersion[$entry.Version] = $entry }
    $choices = @()
    foreach ($release in $releases) {
        $cachedVersion = $byVersion[$release.Version]
        $ready = $null -ne $cachedVersion -and $cachedVersion.Ready
        $status = '需安装'
        if ($null -ne $cachedVersion) { $status = '缓存未完成初始化' }
        if ($ready) { $status = '已缓存/可切换' }
        if ($release.Latest) { $status += ' 最新' + $release.Channel }
        if ($release.Version -ceq $Current) { $status += ' 当前项目' }
        $choices += [pscustomobject]@{ Version = $release.Version; Ready = $ready; Offline = $false; Label = ($release.Version + ' | ' + $release.Channel + ' | ' + $release.Date + ' | ' + $status) }
    }
    foreach ($entry in $Cached) {
        if (-not $entry.Ready -or @($choices | Where-Object { $_.Version -ceq $entry.Version }).Count -gt 0) { continue }
        $status = '已缓存/可切换'
        if ($offline) { $status += ' 离线（最新未知）' }
        else { $status += ' 官方列表未列出' }
        if ($entry.Version -ceq $Current) { $status += ' 当前项目' }
        $choices += [pscustomobject]@{ Version = $entry.Version; Ready = $true; Offline = $offline; Label = ($entry.Version + ' | cache | - | ' + $status) }
    }
    if ($choices.Count -eq 0) { throw '没有可选择版本。请恢复网络后重新打开菜单。' }
    return $choices
}

function Select-JobsFlutterVersion {
    param([string]$Fzf, [object[]]$Choices, [string]$Directory)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Fzf
    $start.Arguments = '--no-multi --no-sort --reverse --border --prompt="Flutter SDK > " --header="输入搜索，↑↓选择，Enter确认，Esc取消；stable/beta/dev历史版本"'
    $start.WorkingDirectory = $Directory
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $start.EnvironmentVariables.Remove('FZF_DEFAULT_OPTS')
    $start.EnvironmentVariables.Remove('FZF_DEFAULT_OPTS_FILE')
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes(($Choices.Label -join "`n") + "`n")
        $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
        $process.StandardInput.BaseStream.Close()
        $output = $process.StandardOutput.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -in @(1, 130)) { return $null }
        if ($process.ExitCode -ne 0) { throw "fzf 选择失败（$($process.ExitCode)）。" }
        $selection = @($Choices | Where-Object { $_.Label -ceq $output.TrimEnd("`r", "`n") })
        if ($selection.Count -ne 1) { throw 'fzf 返回了未知选择，已停止。' }
        return $selection[0]
    }
    finally { $process.Dispose() }
}

function Get-JobsProjectFvmConfig {
    param([string]$Directory)
    $path = Join-Path $Directory '.fvmrc'
    if (-not (Test-JobsFvmPathEntry $path)) { $path = Join-Path $Directory '.fvm/fvm_config.json' }
    if (-not (Test-JobsFvmPathEntry $path)) { return [pscustomobject]@{} }
    Assert-JobsFvmPlainFile $path
    $config = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $config -or $config -is [array] -or $config -is [string] -or $config -is [ValueType]) { throw '.fvmrc 必须是 JSON 对象。' }
    # FVM 对旧键赋予更高优先级，迁移时须去掉别名以免旧版本覆盖新选择。
    if ($null -ne $config.PSObject.Properties['flutterSdkVersion']) {
        $config | Add-Member -NotePropertyName 'flutter' -NotePropertyValue $config.flutterSdkVersion -Force
        $config.PSObject.Properties.Remove('flutterSdkVersion')
    }
    return $config
}

function New-JobsFvmInspection {
    param([string]$Directory)
    $config = Get-JobsProjectFvmConfig $Directory
    if (-not [string]::IsNullOrWhiteSpace($env:FVM_CACHE_PATH) -and -not [IO.Path]::IsPathRooted($env:FVM_CACHE_PATH)) {
        throw 'FVM_CACHE_PATH 必须使用绝对路径，请先明确原缓存位置。'
    }
    if ($null -ne $config.PSObject.Properties['cachePath'] -and -not [string]::IsNullOrWhiteSpace([string]$config.cachePath) -and
        -not [IO.Path]::IsPathRooted([string]$config.cachePath)) {
        throw '项目 cachePath 必须使用绝对路径；请先明确原缓存位置，避免选版体检改变相对路径语义。'
    }
    $root = Join-Path (Get-JobsInstallRoot) ('inspection-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($root)
    try {
        # 空配置同样写入影子根，避免 API 上查目标真实目录的祖先配置。
        [IO.File]::WriteAllText((Join-Path $root '.fvmrc'), ($config | ConvertTo-Json -Depth 100 -WarningAction Stop), (New-Object Text.UTF8Encoding($false)))
        Copy-Item -LiteralPath (Join-Path $Directory 'pubspec.yaml') -Destination (Join-Path $root 'pubspec.yaml')
        return $root
    }
    catch {
        foreach ($name in @('.fvmrc', 'pubspec.yaml')) { $path = Join-Path $root $name; if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) } }
        [IO.Directory]::Delete($root)
        throw
    }
}

function Assert-JobsFvmWritePaths {
    param([string]$Directory)
    foreach ($relative in @('.fvm', '.fvm/versions', '.vscode')) {
        $path = Join-Path $Directory $relative
        if (Test-JobsFvmPathEntry $path) { [void](Assert-JobsFvmDirectory $path) }
    }
    foreach ($relative in @('.fvmrc', '.gitignore', '.vscode/settings.json', '.fvm/fvm_config.json', '.fvm/version', '.fvm/release', '.fvm/.gitignore')) {
        $path = Join-Path $Directory $relative
        if (Test-JobsFvmPathEntry $path) { Assert-JobsFvmPlainFile $path }
    }
    foreach ($workspace in Get-ChildItem -LiteralPath $Directory -Filter '*.code-workspace' -Force) {
        Assert-JobsFvmPlainFile $workspace.FullName
    }
}

function Get-JobsFvmPreviewStamp {
    param([string]$Directory)
    $entries = @()
    foreach ($relative in @('pubspec.yaml', '.fvmrc', '.fvm/fvm_config.json')) {
        $path = Join-Path $Directory $relative
        $hash = '(absent)'
        if (Test-JobsFvmPathEntry $path) { Assert-JobsFvmPlainFile $path; $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
        $entries += ($relative + ':' + $hash)
    }
    return $entries -join '|'
}

function Backup-JobsFvmProject {
    param([string]$Directory)
    $backup = Join-Path (Join-Path (Get-JobsInstallRoot) 'backups') ('project-' + (Get-Date -Format 'yyyy-MM-dd-HH-mm-ss') + '-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($backup)
    $records = New-Object 'System.Collections.Generic.List[object]'
    $queue = New-Object 'System.Collections.Generic.Queue[string]'
    foreach ($relative in @('.fvmrc', '.gitignore', '.vscode/settings.json', '.fvm')) { $queue.Enqueue($relative) }
    foreach ($workspace in Get-ChildItem -LiteralPath $Directory -Filter '*.code-workspace' -File -Force) { $queue.Enqueue($workspace.Name) }
    while ($queue.Count -gt 0) {
        $relative = $queue.Dequeue()
        $path = Join-Path $Directory $relative
        if (-not (Test-JobsFvmPathEntry $path)) { $records.Add(@{ Path = $relative; Type = 'Absent' }); continue }
        $item = Get-Item -LiteralPath $path -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            $target = ''
            if ($null -ne $item.PSObject.Properties['Target']) { $target = @($item.Target) -join ';' }
            $records.Add(@{ Path = $relative; Type = 'Link'; Target = $target })
            continue
        }
        if ($item.PSIsContainer) {
            $records.Add(@{ Path = $relative; Type = 'Directory' })
            foreach ($child in Get-ChildItem -LiteralPath $path -Force) { $queue.Enqueue(($relative + '/' + $child.Name)) }
        }
        else {
            $destination = Join-Path (Join-Path $backup 'files') $relative
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
            Copy-Item -LiteralPath $path -Destination $destination
            $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            if ($hash -cne (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash) { throw '项目备份字节校验失败。' }
            $records.Add(@{ Path = $relative; Type = 'File'; SHA256 = $hash })
        }
    }
    @{ Project = $Directory; Created = [DateTime]::Now.ToString('o'); Entries = @($records.ToArray()) } |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $backup 'snapshot.json') -Encoding UTF8
    Write-JobsFvmMessage "项目精确备份：$backup；SDK 链接仅记录目标，不复制 SDK 缓存。"
    return $backup
}

function Set-JobsProjectFvmVersion {
    param([string]$Directory, [string]$Version)
    if (-not (Test-JobsFlutterVersion $Version)) { throw '仅允许绑定具体 Flutter 版本。' }
    $config = Get-JobsProjectFvmConfig $Directory
    $config | Add-Member -NotePropertyName 'flutter' -NotePropertyValue $Version -Force
    $config | Add-Member -NotePropertyName 'updateMelosSettings' -NotePropertyValue $false -Force
    # 先在精确目标根创建配置，阻止 FVM 向父目录寻找配置并改动父级 Melos。
    [IO.File]::WriteAllText((Join-Path $Directory '.fvmrc'), ($config | ConvertTo-Json -Depth 100 -WarningAction Stop) + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
}

function Assert-JobsFvmSymlinkSupport {
    param([string]$Directory)
    if (-not ('Jobs.FvmSymlink' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Jobs {
    public static class FvmSymlink {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.I1)]
        public static extern bool CreateSymbolicLink(string link, string target, int flags);
    }
}
'@
    }
    $root = Join-Path ([IO.Path]::GetTempPath()) ('JobsFvmLink-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($root)
    try {
        $target = Join-Path $root 'target'
        [void][IO.Directory]::CreateDirectory($target)
        # PowerShell 5.1 New-Item 未必使用开发者模式的无提权标志，直接检验 FVM 所需的系统能力。
        $link = Join-Path $root 'link'
        if (-not [Jobs.FvmSymlink]::CreateSymbolicLink($link, $target, 3)) {
            if (-not [Jobs.FvmSymlink]::CreateSymbolicLink($link, $target, 1)) { throw '符号链接权限不足。' }
        }
    }
    catch { throw 'FVM 需要创建 SDK 符号链接。请在 Windows 设置中启用开发者模式后重试；本入口不自动提权或更改系统设置。' }
    finally {
        $link = Join-Path $root 'link'
        if (Test-Path -LiteralPath $link) { [IO.Directory]::Delete($link) }
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    }
}

function Invoke-JobsFlutterVersionAction {
    param([string]$Directory)
    Assert-JobsFlutterProject $Directory
    Assert-JobsFvmWritePaths $Directory
    $previewStamp = Get-JobsFvmPreviewStamp $Directory
    Write-JobsFvmMessage "Flutter SDK 安装/切换（FVM）；精确项目：$Directory"
    Write-JobsFvmMessage '流程：项目校验 → 健康工具链 → 官方历史/最新版本 → fzf → 最终确认 → 备份 → 安装/切换。工具安装会分别确认。'
    $config = Get-JobsProjectFvmConfig $Directory
    if (($config.PSObject.Properties['flutterUrl'] -and $config.flutterUrl -cnotin @('https://github.com/flutter/flutter.git','https://github.com/flutter/flutter')) -or
        ($config.PSObject.Properties['flutter'] -and [string]$config.flutter -cmatch '^custom_|/')) {
        throw '原生 Flutter 选择器只接受官方来源；本工具管理的 OpenHarmony SDK 请从统一菜单切回，其它 fork 请自行明确迁移。'
    }
    $current = '(未绑定)'
    if ($null -ne $config.PSObject.Properties['flutter']) { $current = [string]$config.flutter }
    Write-JobsFvmMessage "当前项目 .fvmrc：$current"
    $savedPath = $env:PATH
    $savedTls = [Net.ServicePointManager]::SecurityProtocol
    $lock = $null
    $inspection = $null
    try {
        [Net.ServicePointManager]::SecurityProtocol = $savedTls -bor [Net.SecurityProtocolType]::Tls12
        $root = Get-JobsInstallRoot
        [void][IO.Directory]::CreateDirectory($root)
        try { $lock = [IO.File]::Open((Join-Path $root 'operation.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
        catch { throw '另一 FVM 会话正在运行，请结束该会话后再试。' }
        $inspection = New-JobsFvmInspection $Directory
        $chain = Get-JobsFvmToolchain $Directory $inspection
        if ($chain.Context.flutterUrl -cnotin @('https://github.com/flutter/flutter.git','https://github.com/flutter/flutter')) { throw 'FVM 有效来源不是官方 Flutter 仓库；未下载或切换原生 SDK。请先检查 FVM_FLUTTER_URL 与 FVM 配置。' }
        $cached = @(Get-JobsFvmCachedVersions $chain.Fvm $inspection)
        $choices = @(Get-JobsFlutterReleaseChoices $cached $current)
        $choice = Select-JobsFlutterVersion $chain.Fzf $choices $Directory
        if ($null -eq $choice) { Write-JobsFvmMessage '已取消选择，项目未修改。'; return }
        Write-JobsFvmMessage ("计划：{0} → {1}；{2}" -f $current, $choice.Version, $choice.Label)
        Write-JobsFvmMessage '写入范围：当前根 .fvmrc（保留其它字段、关闭向父 Melos 同步）、.fvm/、可能的 .gitignore、.vscode/settings.json 和根 *.code-workspace；不获取项目 pub 依赖。未缓存版本将下载 SDK。'
        if ((Read-Host '直接回车执行当前项目的安装/切换；输入任意字符后回车取消') -ne '') { Write-JobsFvmMessage '已取消，项目未修改。'; return }
        Assert-JobsFlutterProject $Directory
        Assert-JobsFvmWritePaths $Directory
        if ((Get-JobsFvmPreviewStamp $Directory) -cne $previewStamp) { throw '选版期间 pubspec.yaml 或 .fvmrc 已被修改，请重新打开菜单确认新状态；本次未写项目。' }
        Assert-JobsFvmSymlinkSupport $Directory
        $backup = Backup-JobsFvmProject $Directory
        Set-JobsProjectFvmVersion $Directory $choice.Version
        $pinnedConfig = Get-JobsProjectFvmConfig $Directory
        $contextResult = Invoke-JobsFvmTool $chain.Fvm @('api', 'context', '--compress') $Directory
        if ($contextResult.ExitCode -ne 0) { throw "项目配置写入后的 FVM 上下文体检失败；备份：$backup" }
        $effective = ($contextResult.StdOut | ConvertFrom-Json -ErrorAction Stop).context
        if ($null -eq $effective -or $effective.versionsCachePath -cne $chain.Context.versionsCachePath -or $effective.flutterUrl -cne $chain.Context.flutterUrl) {
            throw "精确根配置建立后缓存或 SDK 来源发生变化，原选择状态不再适用。尚未安装/切换 SDK，请重新打开菜单按新上下文选版；需要恢复原配置时使用备份：$backup"
        }
        if (-not $choice.Ready) {
            if ($choice.Offline) { throw '离线模式禁止下载或初始化 SDK。' }
            Write-JobsFvmMessage ("执行：fvm install {0} --skip-pub-get；来源由以上 FVM 配置决定。" -f $choice.Version)
            $install = Invoke-JobsFvmTool $chain.Fvm @('install', $choice.Version, '--skip-pub-get') $Directory -Visible -TimeoutSeconds 3600
            if ($install.ExitCode -ne 0) { throw "SDK 安装失败（$($install.ExitCode)）；项目可能部分改动，备份：$backup" }
        }
        Write-JobsFvmMessage ("执行：fvm use {0} --skip-pub-get --skip-setup" -f $choice.Version)
        $use = Invoke-JobsFvmTool $chain.Fvm @('use', $choice.Version, '--skip-pub-get', '--skip-setup') $Directory -Visible -TimeoutSeconds 300
        if ($use.ExitCode -ne 0) { throw "FVM 切换失败（$($use.ExitCode)）；备份：$backup" }
        $after = Get-JobsProjectFvmConfig $Directory
        if ($after.flutter -cne $choice.Version -or $after.updateMelosSettings -ne $false) { throw '.fvmrc 复核与所选版本不符。' }
        # 上游模型只保留已知字段；把它省略的现有扩展字段补回，避免吞掉用户配置。
        foreach ($property in $pinnedConfig.PSObject.Properties) {
            if ($null -eq $after.PSObject.Properties[$property.Name]) { $after | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value }
        }
        [IO.File]::WriteAllText((Join-Path $Directory '.fvmrc'), ($after | ConvertTo-Json -Depth 100 -WarningAction Stop) + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
        $sdkLink = Join-Path $Directory '.fvm/flutter_sdk'
        if (-not (Test-Path -LiteralPath (Join-Path $sdkLink 'bin/flutter.bat') -PathType Leaf) -or
            ((Get-Item -LiteralPath $sdkLink -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
            throw '项目 .fvm/flutter_sdk SDK 链接不存在或不完整。'
        }
        $version = Invoke-JobsFvmTool $chain.Fvm @('flutter', '--version', '--machine') $Directory -TimeoutSeconds 120
        if ($version.ExitCode -ne 0) { throw 'Flutter SDK 切换后的执行体检失败。' }
        $actual = $version.StdOut | ConvertFrom-Json -ErrorAction Stop
        if ($actual.frameworkVersion -cne $choice.Version) { throw "实际 Flutter 版本 $($actual.frameworkVersion) 与所选版本 $($choice.Version) 不一致。" }
        Write-JobsFvmMessage ("成功：项目已绑定 Flutter {0}；实际 SDK 已复核。备份：{1}" -f $choice.Version, $backup)
        $fvmCommand = "& '" + $chain.Fvm.Replace("'", "''") + "'"
        Write-JobsFvmMessage ("后续终端命令使用 FVM：{0} flutter pub get；IDE SDK 指向项目 .fvm/flutter_sdk。请审阅 Git 差异，将 .fvmrc 纳入版本控制并忽略 .fvm/。" -f $fvmCommand)
    }
    finally {
        if ($inspection -and [IO.Directory]::Exists($inspection)) {
            try {
                foreach ($name in @('.fvmrc', 'pubspec.yaml')) { $path = Join-Path $inspection $name; if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) } }
                # 只删除本次空目录；若上游意外产生其它文件，保留现场而不递归清理。
                [IO.Directory]::Delete($inspection)
            }
            catch { Write-Warning "私有体检目录保留待查：$inspection" }
        }
        if ($null -ne $lock) { $lock.Dispose() }
        $env:PATH = $savedPath
        [Net.ServicePointManager]::SecurityProtocol = $savedTls
    }
}

function Invoke-JobsFeature {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Target)
    $directory = Assert-JobsFvmDirectory (Resolve-JobsTarget $Target)
    Invoke-JobsFlutterVersionAction $directory
}

Export-ModuleMember -Function Invoke-JobsFeature

# Action.psm1 | JobsFlutterDependencyExtractor
# Created by Jobs on 2026年10月19日，星期一.
# 仅读取精确 Flutter 项目的已解析依赖；不下载、不修改项目或工具链。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking

function Assert-JobsExtractorDirectory {
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

function Assert-JobsExtractorPlainFile {
    param([string]$Path)
    $attributes = [IO.File]::GetAttributes($Path)
    if (($attributes -band [IO.FileAttributes]::Directory) -ne 0 -or ($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "配置必须是普通文件：$Path"
    }
}

function Test-JobsExtractorPathEntry {
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
    [void](Assert-JobsExtractorDirectory $Directory)
    $pubspec = Join-Path $Directory 'pubspec.yaml'
    Assert-JobsExtractorPlainFile $pubspec
    if (-not (Test-JobsFlutterPubspec (Get-Content -LiteralPath $pubspec -Raw -Encoding UTF8))) {
        throw '目标同层 pubspec.yaml 必须明确声明 dependencies.flutter.sdk: flutter；不会扫描子目录或沿用父工程。YAML 别名、标签及多行 flow 映射请先改成常见 block 写法。'
    }
}


function ConvertTo-JobsExtractorSafeMessage {
    param([string]$Message)
    $safe = $Message -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@'
    $safe = $safe -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]'
    return $safe -replace '(?im)((?:token|password|secret|authorization)\s*[:=]\s*)\S+', '$1[已省略]'
}

function Write-JobsExtractorMessage {
    param([string]$Message)
    $safe = ConvertTo-JobsExtractorSafeMessage $Message
    Write-Host $safe
    [IO.File]::AppendAllText($script:ExtractorLog, ($safe + [Environment]::NewLine), (New-Object Text.UTF8Encoding($true)))
}

function Show-JobsExtractorIntro {
    Write-Host 'Jobs · 提取 Flutter 第三方依赖' -ForegroundColor Red
    Write-Host '1、读取所选项目的 pubspec.lock 与 .dart_tool/package_config.json，复制直接、间接和开发用第三方 Pub 源码及许可证。' -ForegroundColor Blue
    Write-Host '2、输入或拖入输出父目录，直接回车采用系统桌面；每次生成新的独立目录，不覆盖已有结果。' -ForegroundColor Blue
    Write-Host '3、只读取项目及已下载依赖；不联网、不自动 pub get、不改代理或 Flutter SDK。缺少解析记录或缓存时停止。' -ForegroundColor Blue
    Write-Host '4、不包含 Flutter/Dart SDK、原生 CocoaPods/Gradle 依赖；复制不是离线构建配置。日志在本功能安装目录的 logs 中。' -ForegroundColor Blue
    Write-Host '按 Ctrl+C 取消。'
    $answer = Read-Host '已了解用途与影响，按回车继续；任意非空输入取消'
    if ($null -eq $answer) { throw '输入已关闭，操作取消。' }
    return $answer.Length -eq 0
}

function ConvertFrom-JobsExtractorPathInput {
    param([AllowNull()][AllowEmptyString()][string]$Text, [string]$DefaultPath)
    if ([string]::IsNullOrEmpty($Text)) { return $DefaultPath }
    $value = $Text.Trim()
    # 拖入产生的外层引号只是路径表示，绝不作为 PowerShell 表达式求值。
    if ($value.StartsWith('& ')) { $value = $value.Substring(2).TrimStart() }
    if ($value.Length -ge 2 -and $value[0] -eq [char]34 -and $value[-1] -eq [char]34) {
        $value = $value.Substring(1, $value.Length - 2)
    } elseif ($value.Length -ge 2 -and $value[0] -eq [char]39 -and $value[-1] -eq [char]39) {
        $value = $value.Substring(1, $value.Length - 2).Replace("''", "'")
    }
    if ([string]::IsNullOrWhiteSpace($value) -or $value.IndexOfAny([char[]]@(0, 10, 13, 34)) -ge 0) { throw '请输入一个有效的完整文件夹路径。' }
    if (-not [IO.Path]::IsPathRooted($value)) { throw '输出目录必须是绝对路径，不能输入命令或相对路径。' }
    return [IO.Path]::GetFullPath($value)
}

function Get-JobsExtractorDesktop {
    $desktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
    if ([string]::IsNullOrWhiteSpace($desktop)) { throw '系统未提供桌面目录，请输入输出目录。' }
    return $desktop
}

function Get-JobsExtractorDartCandidates {
    param([string]$Directory)
    $candidates = New-Object 'Collections.Generic.List[string]'
    $candidates.Add((Join-Path $Directory '.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dart.exe'))
    if (-not [string]::IsNullOrEmpty($env:FLUTTER_ROOT)) {
        $candidates.Add((Join-Path $env:FLUTTER_ROOT 'bin/cache/dart-sdk/bin/dart.exe'))
    }
    foreach ($command in @(Get-Command -Name flutter.exe, flutter.bat, flutter -CommandType Application -ErrorAction SilentlyContinue)) {
        $bin = Split-Path -Parent $command.Source
        $candidates.Add((Join-Path $bin 'cache/dart-sdk/bin/dart.exe'))
    }
    # 包配置记录的 Flutter SDK 能覆盖仅 IDE 配置 SDK、PATH 未设置的场景。
    $configPath = Join-Path $Directory '.dart_tool/package_config.json'
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        try {
            $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($package in @($config.packages | Where-Object { $_.name -ceq 'flutter' })) {
                $uri = New-Object Uri ((New-Object Uri ([IO.Path]::GetFullPath($configPath))), ([string]$package.rootUri))
                if ($uri.IsFile) {
                    $sdkRoot = Split-Path -Parent (Split-Path -Parent $uri.LocalPath.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar))
                    $candidates.Add((Join-Path $sdkRoot 'bin/cache/dart-sdk/bin/dart.exe'))
                }
            }
        } catch { }
    }
    foreach ($command in @(Get-Command -Name dart.exe -CommandType Application -ErrorAction SilentlyContinue)) { $candidates.Add($command.Source) }
    return @($candidates | Select-Object -Unique)
}

function Test-JobsExtractorNativeExecutable {
    param([string]$Path)
    if (-not [IO.File]::Exists($Path) -or [IO.Path]::GetExtension($Path) -ine '.exe') { return $false }
    $stream = $null
    $reader = $null
    try {
        # 仅读 PE 签名后才体检，避免把伪装 .exe 的批处理或脚本交给系统关联执行。
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        if ($stream.Length -lt 64) { return $false }
        $reader = New-Object IO.BinaryReader ($stream)
        if ($reader.ReadUInt16() -ne 0x5A4D) { return $false }
        $stream.Position = 0x3C
        $header = $reader.ReadInt32()
        if ($header -lt 64 -or $header -gt $stream.Length - 24) { return $false }
        $stream.Position = $header
        if ($reader.ReadUInt32() -ne 0x00004550) { return $false }
        return $reader.ReadUInt16() -in @(0x014C, 0x8664, 0xAA64)
    } catch { return $false }
    finally {
        if ($null -ne $reader) { $reader.Dispose() }
        elseif ($null -ne $stream) { $stream.Dispose() }
    }
}

function Find-JobsExtractorDart {
    param([string]$Directory)
    foreach ($candidate in @(Get-JobsExtractorDartCandidates $Directory)) {
        if (-not (Test-JobsExtractorNativeExecutable $candidate)) { continue }
        try {
            $probe = Invoke-JobsProcess -FilePath $candidate -Arguments @('--version') -WorkingDirectory $Directory -TimeoutSeconds 15
            if ($probe.ExitCode -eq 0 -and ($probe.StdOut + $probe.StdErr) -match 'Dart SDK version:') { return $candidate }
        } catch { }
    }
    throw '未找到健康的 Dart SDK。请初始化项目 FVM/Flutter SDK 或将 dart.exe 加入 PATH 后重试；本工具不会自动下载。'
}

function Invoke-JobsFlutterDependencyAction {
    param([string]$Directory)
    if (-not (Show-JobsExtractorIntro)) { return }
    Assert-JobsFlutterProject $Directory
    foreach ($relative in @('pubspec.lock', '.dart_tool/package_config.json')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Directory $relative) -PathType Leaf)) {
            throw '依赖解析记录不完整，请在项目根目录手动运行 flutter pub get 成功后重试。'
        }
    }
    $logs = Join-Path (Get-JobsInstallRoot) 'logs'
    [void][IO.Directory]::CreateDirectory($logs)
    $script:ExtractorLog = Join-Path $logs ('extract-' + (Get-Date -Format 'yyyy-MM-dd-HH-mm-ss') + '-' + [guid]::NewGuid().ToString('N') + '.log')
    Write-JobsExtractorMessage ('日志：' + $script:ExtractorLog)
    $desktop = Get-JobsExtractorDesktop
    $inputPath = Read-Host ('输入或拖入输出父目录（直接回车：' + $desktop + '）')
    if ($null -eq $inputPath) { throw '输入已关闭，操作取消。' }
    $destination = ConvertFrom-JobsExtractorPathInput -Text $inputPath -DefaultPath $desktop
    $dart = Find-JobsExtractorDart $Directory
    $engine = Join-Path $PSScriptRoot 'ExtractFlutterDependencies.dart'
    Assert-JobsExtractorPlainFile $engine
    Write-JobsExtractorMessage ('来源：项目已解析的第三方 Pub 包；项目：' + $Directory)
    Write-JobsExtractorMessage ('输出父目录：' + $destination)
    Write-JobsExtractorMessage ('复用 Dart：' + $dart)
    Write-JobsExtractorMessage '正在核对锁定依赖并复制源码，请等待完成提示。'
    $result = Invoke-JobsProcess -FilePath $dart -Arguments @($engine, '--project', $Directory, '--destination', $destination) -WorkingDirectory $Directory -TimeoutSeconds 21600
    foreach ($output in @($result.StdOut, $result.StdErr)) {
        if (-not [string]::IsNullOrWhiteSpace($output)) { Write-JobsExtractorMessage $output.TrimEnd() }
    }
    if ($result.ExitCode -ne 0) { throw ('提取失败（退出码 ' + $result.ExitCode + '），请按上方说明处理；不会自动运行 flutter pub get。') }
    Write-JobsExtractorMessage '提取完成。'
}

function Invoke-JobsFeature {
    param([Parameter(Mandatory = $true)][string]$Target)
    $directory = Get-JobsDirectory -Target $Target
    Invoke-JobsFlutterDependencyAction -Directory $directory
}

Export-ModuleMember -Function Invoke-JobsFeature

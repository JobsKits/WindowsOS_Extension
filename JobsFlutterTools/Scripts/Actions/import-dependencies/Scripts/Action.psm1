# Action.psm1 | JobsFlutterTools dependency import
# Created by Jobs on 2026年10月28日，星期三.
# 校验导出依赖后预览并等待 YES；仅复制到所选项目并备份配置，不执行导入源码。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking

# 先追加目录分隔符再正规化，避免 .NET Framework 裁剪末尾合法 Unicode 空白。
function Get-JobsImporterFullDirectoryPath {
    param([string]$Path)
    if (-not [IO.Path]::IsPathRooted($Path)) { throw "依赖目录必须是绝对路径：$Path" }
    $separators = [char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $full = [IO.Path]::GetFullPath($Path.TrimEnd($separators) + [IO.Path]::DirectorySeparatorChar)
    $root = [IO.Path]::GetPathRoot($full)
    if ($full.Length -gt $root.Length) { return $full.TrimEnd($separators) }
    return $full
}

function Assert-JobsImporterDirectory {
    param([string]$Path)
    $full = Get-JobsImporterFullDirectoryPath $Path
    $separators = [char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $accessPath = $full.TrimEnd($separators) + [IO.Path]::DirectorySeparatorChar
    if (-not [IO.Directory]::Exists($accessPath)) { throw "目标必须是存在的绝对目录：$Path" }
    $current = $full
    while (-not [string]::IsNullOrEmpty($current)) {
        $accessPath = $current.TrimEnd($separators) + [IO.Path]::DirectorySeparatorChar
        if (([IO.File]::GetAttributes($accessPath) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "不处理符号链接或目录联接：$current"
        }
        $current = [IO.Path]::GetDirectoryName($current)
    }
    return $full
}

function Assert-JobsImporterPlainFile {
    param([string]$Path)
    $attributes = [IO.File]::GetAttributes($Path)
    if (($attributes -band [IO.FileAttributes]::Directory) -ne 0 -or ($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "配置必须是普通文件：$Path"
    }
}

function Test-JobsImporterPathEntry {
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
    [void](Assert-JobsImporterDirectory $Directory)
    $pubspec = Join-Path $Directory 'pubspec.yaml'
    Assert-JobsImporterPlainFile $pubspec
    if (-not (Test-JobsFlutterPubspec (Get-Content -LiteralPath $pubspec -Raw -Encoding UTF8))) {
        throw '目标同层 pubspec.yaml 必须明确声明 dependencies.flutter.sdk: flutter；不会扫描子目录或沿用父工程。YAML 别名、标签及多行 flow 映射请先改成常见 block 写法。'
    }
}


function ConvertTo-JobsImporterSafeMessage {
    param([string]$Message)
    $safe = $Message -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@'
    $safe = $safe -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]'
    return $safe -replace '(?im)((?:token|password|secret|authorization)\s*[:=]\s*)\S+', '$1[已省略]'
}

function Write-JobsImporterMessage {
    param([string]$Message)
    $safe = ConvertTo-JobsImporterSafeMessage $Message
    Write-Host $safe
    [IO.File]::AppendAllText($script:ImporterLog, ($safe + [Environment]::NewLine), (New-Object Text.UTF8Encoding($true)))
}

function ConvertFrom-JobsImporterPathInput {
    param([AllowNull()][AllowEmptyString()][string]$Text, [string]$DefaultPath)
    if ([string]::IsNullOrWhiteSpace($Text)) { throw '依赖目录不能为空，请输入或拖入本工具导出的完整目录。' }
    $value = $Text.Trim()
    # 拖入产生的外层引号只是路径表示，绝不作为 PowerShell 表达式求值。
    if ($value.StartsWith('& ')) { $value = $value.Substring(2).TrimStart() }
    if ($value.Length -ge 2 -and $value[0] -eq [char]34 -and $value[-1] -eq [char]34) {
        $value = $value.Substring(1, $value.Length - 2)
    } elseif ($value.Length -ge 2 -and $value[0] -eq [char]39 -and $value[-1] -eq [char]39) {
        $value = $value.Substring(1, $value.Length - 2).Replace("''", "'")
    }
    if ([string]::IsNullOrWhiteSpace($value) -or $value.IndexOfAny([char[]]@(0, 10, 13, 34)) -ge 0) { throw '请输入一个有效的完整文件夹路径。' }
    if (-not [IO.Path]::IsPathRooted($value)) { throw '依赖目录必须是绝对路径，不能输入命令或相对路径。' }
    return Get-JobsImporterFullDirectoryPath $value
}

function Get-JobsImporterDartCandidates {
    param([string]$Directory)
    return ,(Join-Path $Directory '.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dart.exe')
}

function Test-JobsImporterNativeExecutable {
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

function Find-JobsImporterDart {
    param([string]$Directory)
    foreach ($candidate in @(Get-JobsImporterDartCandidates $Directory)) {
        if (-not (Test-JobsImporterNativeExecutable $candidate)) { continue }
        try {
            $probe = Invoke-JobsProcess -FilePath $candidate -Arguments @('--version') -WorkingDirectory $Directory -TimeoutSeconds 15
            if ($probe.ExitCode -eq 0 -and ($probe.StdOut + $probe.StdErr) -match 'Dart SDK version:') { return $candidate }
        } catch { }
    }
    throw '未找到健康的 Dart SDK。请初始化项目 FVM/Flutter SDK 后重试；本工具不会自动下载。'
}

function Show-JobsImporterIntro {
    Write-Host 'Jobs · 导入 Flutter 第三方依赖' -ForegroundColor Red
    Write-Host '1、输入或拖入本工具导出的完整依赖目录（包含 manifest.json、pubspec.yaml、pubspec.lock、packages/）。' -ForegroundColor Blue
    Write-Host '2、先完整校验清单、包名、版本、文件与当前项目；通过后显示计划，精确输入 YES 才写入。' -ForegroundColor Blue
    Write-Host '3、源码原样复制到当前项目 vendor/flutter_dependencies/ 的独立目录，并备份、增量合并 pubspec_overrides.yaml。已有同名覆盖冲突时停止。' -ForegroundColor Blue
    Write-Host '4、不联网、不运行依赖源码、不自动 pub get、不修改全局缓存或 SDK。当前仅支持独立 Flutter 项目，Pub workspace 根和成员均暂不支持。' -ForegroundColor Blue
    Write-Host '日志在本功能安装目录的 logs/import-*.log；运行时显示精确位置。路径留空会继续询问，按 Ctrl+C 或输入结束取消。'
}

function Assert-JobsImporterSource {
    param([string]$Directory)
    [void](Assert-JobsImporterDirectory $Directory)
    foreach ($name in @('manifest.json', 'pubspec.yaml', 'pubspec.lock')) {
        Assert-JobsImporterPlainFile (Join-Path $Directory $name)
    }
    [void](Assert-JobsImporterDirectory (Join-Path $Directory 'packages'))
    $manifestPath = Join-Path $Directory 'manifest.json'
    if ((New-Object IO.FileInfo $manifestPath).Length -gt 8MB) { throw '导出清单超过 8 MiB，停止识别。' }
    $manifest = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
    if ($null -eq $manifest.PSObject.Properties['formatVersion'] -or $manifest.formatVersion -ne 1 -or
        $null -eq $manifest.PSObject.Properties['status'] -or $manifest.status -cne 'complete' -or
        $null -eq $manifest.PSObject.Properties['packages'] -or $manifest.packages -isnot [Array]) {
        throw '目录不是完整的 Flutter 依赖导出结果；要求 formatVersion=1、status=complete 及 packages 数组。'
    }
}

function Invoke-JobsImporterEngine {
    param([string]$Dart, [string]$Engine, [string]$Project, [string]$Source, [switch]$ValidateOnly, [switch]$PrivateOnly)
    $arguments = @($Engine, '--project', $Project, '--source', $Source)
    if ($PrivateOnly) { $arguments += '--private-only' }
    if ($ValidateOnly) { $arguments += '--validate-only' }
    $result = Invoke-JobsProcess -FilePath $Dart -Arguments $arguments -WorkingDirectory $Project -TimeoutSeconds 21600
    foreach ($output in @($result.StdOut, $result.StdErr)) {
        if (-not [string]::IsNullOrWhiteSpace($output)) { Write-JobsImporterMessage $output.TrimEnd() }
    }
    if ($result.ExitCode -ne 0) {
        $stage = if ($ValidateOnly) { '依赖识别/校验' } else { '导入' }
        throw ($stage + '失败（退出码 ' + $result.ExitCode + '），请按上方说明处理。')
    }
}

function Read-JobsImporterSourceInput {
    param([string]$Prompt)
    # Console.ReadLine 保留 EOF 的 null；不能把输入结束当作空行反复重问。
    Write-Host ($Prompt + '：') -NoNewline
    return [Console]::ReadLine()
}

function Invoke-JobsFlutterDependencyImport {
    param([string]$Directory, [switch]$PrivateOnly)
    if ($PrivateOnly) { Write-Host '📥 导入Flutter项目工程私库依赖：仅恢复私库源码，公共 Pub 包保留原声明。' }
    Show-JobsImporterIntro
    Assert-JobsFlutterProject $Directory
    while ($true) {
        $inputPath = Read-JobsImporterSourceInput '输入或拖入完整依赖导出目录（留空继续询问，Ctrl+C 取消）'
        if ($null -eq $inputPath) { return }
        if (-not [string]::IsNullOrWhiteSpace($inputPath)) { break }
        Write-Host '尚未输入依赖目录，请输入或拖入后按回车。'
    }
    $source = ConvertFrom-JobsImporterPathInput -Text $inputPath
    Assert-JobsImporterSource $source
    $dart = Find-JobsImporterDart $Directory
    $engine = Join-Path $PSScriptRoot 'ImportFlutterDependencies.dart'
    Assert-JobsImporterPlainFile $engine
    Assert-JobsImporterPlainFile (Join-Path $PSScriptRoot 'ExtractFlutterDependencies.dart')
    $logs = Join-Path (Get-JobsInstallRoot) 'logs'
    [void][IO.Directory]::CreateDirectory($logs)
    $script:ImporterLog = Join-Path $logs ('import-' + (Get-Date -Format 'yyyy-MM-dd-HH-mm-ss') + '-' + [guid]::NewGuid().ToString('N') + '.log')
    Write-JobsImporterMessage ('日志：' + $script:ImporterLog)
    Write-JobsImporterMessage ('来源：本地 Flutter 第三方 Pub 依赖导出；目录：' + $source)
    Write-JobsImporterMessage ('目标项目：' + $Directory)
    Write-JobsImporterMessage ('复用项目 Dart：' + $dart)
    try {
        Invoke-JobsImporterEngine -Dart $dart -Engine $engine -Project $Directory -Source $source -PrivateOnly:$PrivateOnly -ValidateOnly
        $answer = Read-Host '校验通过。核对上方来源、目标及计划，精确输入 YES 导入；其它输入取消'
        if ($null -eq $answer -or $answer -cne 'YES') {
            Write-JobsImporterMessage '已取消，项目未写入。'
            return
        }
        Invoke-JobsImporterEngine -Dart $dart -Engine $engine -Project $Directory -Source $source -PrivateOnly:$PrivateOnly
        Write-JobsImporterMessage '导入完成；请核对结果后按需手动运行 flutter pub get。'
    } catch {
        Write-JobsImporterMessage ('导入停止：' + $_.Exception.Message)
        throw
    }
}

function Invoke-JobsFeature {
    param([Parameter(Mandatory = $true)][string]$Target, [switch]$PrivateOnly)
    $directory = Get-JobsDirectory -Target $Target
    Invoke-JobsFlutterDependencyImport -Directory $directory -PrivateOnly:$PrivateOnly
}

Export-ModuleMember -Function Invoke-JobsFeature

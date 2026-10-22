# Action.psm1 | JobsFlutterDoctor
# Created by Jobs on 2026年10月22日，星期四.
# 严格校验当前根项目与同源 SDK；不自动安装或升级工具。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking

function Assert-JobsRunnerDirectory {
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

function Assert-JobsRunnerPlainFile {
    param([string]$Path)
    $attributes = [IO.File]::GetAttributes($Path)
    if (($attributes -band [IO.FileAttributes]::Directory) -ne 0 -or ($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "配置必须是普通文件：$Path"
    }
}

function Test-JobsRunnerPathEntry {
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
    for ($partIndex = 0; $partIndex -lt $parts.Count; $partIndex++) {
        $part = $parts[$partIndex]
        if ([string]::IsNullOrWhiteSpace($part)) {
            if ($partIndex -eq $parts.Count - 1 -and ($map.Count -gt 0 -or [string]::IsNullOrWhiteSpace($body))) { continue }
            throw 'YAML flow 映射存在空项。'
        }
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
    $Text = $Text.TrimStart([char]0xfeff)
    if ($Text.IndexOf([char]0) -ge 0) { return $false }
    # 只解释 dependencies.flutter.sdk，不能把 description、注释或 flutter_test 当作 Flutter 项目。
    $lines = @($Text -split '\r?\n' | ForEach-Object { Remove-JobsYamlComment $_ })
    if (@($lines | Where-Object { $_.Trim() -in @('---', '...') }).Count -gt 0) { return $false }
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
            if ($lines[$i] -notmatch '^(?<indent> +)(?<key>[A-Za-z_][A-Za-z0-9_-]*|''[^'']+''|"[^"\\]+")\s*:\s*(?<value>.*)$') { return $false }
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
    [void](Assert-JobsRunnerDirectory $Directory)
    $pubspec = Join-Path $Directory 'pubspec.yaml'
    Assert-JobsRunnerPlainFile $pubspec
    if ((Get-Item -LiteralPath $pubspec).Length -gt 1MB) { throw 'pubspec.yaml 超过 1 MiB，停止读取。' }
    if (-not (Test-JobsFlutterPubspec (Get-Content -LiteralPath $pubspec -Raw -Encoding UTF8))) {
        throw '目标同层 pubspec.yaml 必须明确声明 dependencies.flutter.sdk: flutter；不会扫描子目录或沿用父工程。YAML 别名、标签及多行 flow 映射请先改成常见 block 写法。'
    }
}

function Get-JobsRunnerFlutter {
    param([string]$Project)
    foreach ($candidate in @((Join-Path $Project '.fvm/flutter_sdk/bin/flutter.bat'), (Join-Path $Project '.fvm/flutter_sdk/bin/flutter.exe'))) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return [IO.Path]::GetFullPath($candidate) }
    }
    foreach ($binding in @('.fvmrc', '.fvm/fvm_config.json', '.fvm/flutter_sdk')) {
        if (Test-JobsRunnerPathEntry (Join-Path $Project $binding)) {
            throw '项目已绑定 FVM，但项目 Flutter SDK 缺失或不完整。请先安装 / 修复对应 FVM SDK，再运行；不会改用 PATH 的其它版本。'
        }
    }
    $flutter = Find-JobsExecutable -Name 'flutter.bat' -Candidates @('flutter.exe', 'flutter')
    if (-not $flutter) { throw '没有可用 Flutter。先安装 Flutter SDK 并加入 PATH，或用本仓 FVM 菜单绑定项目版本。' }
    return $flutter
}

function Write-JobsFlutterMessage {
    param([string]$Message)
    $safe = $Message -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@'
    $safe = $safe -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]'
    $safe = $safe -replace '(?im)((?:access[_-]?token|authorization|password|secret)\s*[:=]\s*)\S+', '$1[已省略]'
    Write-Host $safe
    Write-JobsLog $safe
}

function Get-JobsFlutterSdk {
    param([string]$Project)
    $flutter = Get-JobsRunnerFlutter $Project
    $bin = Split-Path -Parent $flutter
    $dart = Join-Path $bin 'dart.bat'
    if (-not [IO.File]::Exists($dart)) { $dart = Join-Path $bin 'dart.exe' }
    if (-not [IO.File]::Exists($dart)) { throw 'Flutter SDK 缺少同目录 Dart；请修复 SDK。不会改用其它 Dart 版本。' }
    return [pscustomobject]@{ Flutter = $flutter; Dart = $dart }
}

function New-JobsFlutterToolStartInfo {
    param([string]$Executable, [string[]]$Arguments, [string]$Project)
    if ($Executable -match '["\x00-\x1f]' -or @($Arguments | Where-Object { $_ -match '["\x00-\x1f]' }).Count -gt 0) {
        throw '工具路径或参数含引号、控制字符，停止执行。'
    }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Executable
    $start.Arguments = @($Arguments | ForEach-Object { Quote-JobsArgument $_ }) -join ' '
    if ([IO.Path]::GetExtension($Executable) -in @('.bat', '.cmd')) {
        $start.FileName = Join-Path ([Environment]::GetFolderPath('System')) 'cmd.exe'
        $start.EnvironmentVariables['JOBS_FLUTTER_TOOL'] = $Executable
        $references = @()
        for ($i = 0; $i -lt $Arguments.Count; $i++) {
            $name = 'JOBS_FLUTTER_ARG_' + $i
            $start.EnvironmentVariables[$name] = $Arguments[$i]
            $references += ('"%' + $name + '%"')
        }
        # 路径与参数经环境变量单次展开，延迟展开关闭；不将项目数据拼成可执行语句。
        $start.Arguments = '/d /v:off /s /c ""%JOBS_FLUTTER_TOOL%" ' + ($references -join ' ') + '"'
    }
    $start.WorkingDirectory = $Project
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $start.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    $start.EnvironmentVariables['CI'] = 'true'
    $start.EnvironmentVariables['FLUTTER_SUPPRESS_ANALYTICS'] = 'true'
    $start.EnvironmentVariables['DART_SUPPRESS_ANALYTICS'] = 'true'
    return $start
}

function Invoke-JobsFlutterTool {
    param([string]$Executable, [string[]]$Arguments, [string]$Project, [int]$TimeoutSeconds = 1800, [switch]$Doctor)
    Write-JobsFlutterMessage ('执行：' + $Executable + ' ' + ($Arguments -join ' '))
    $process = New-Object Diagnostics.Process
    $process.StartInfo = New-JobsFlutterToolStartInfo $Executable $Arguments $Project
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $doctorIssues = $false
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadLineAsync()
        $stderr = $process.StandardError.ReadLineAsync()
        while ($null -ne $stdout -or $null -ne $stderr) {
            if ($watch.Elapsed.TotalSeconds -gt $TimeoutSeconds) {
                if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
                    $taskkill = Join-Path ([Environment]::GetFolderPath('System')) 'taskkill.exe'
                    [void](Invoke-JobsProcess -FilePath $taskkill -Arguments @('/PID', [string]$process.Id, '/T', '/F') -TimeoutSeconds 15)
                } elseif (-not $process.HasExited) { $process.Kill() }
                throw '工具执行超时，已请求终止本次进程树。'
            }
            if ($null -ne $stdout -and $stdout.IsCompleted) {
                $line = $stdout.GetAwaiter().GetResult()
                $stdout = $null
                if ($null -ne $line) {
                    Write-JobsFlutterMessage $line
                    if ($Doctor -and $line -match '(?i)(?:^\s*\[(?:!|✗|x)\]|doctor found issues)') { $doctorIssues = $true }
                    $stdout = $process.StandardOutput.ReadLineAsync()
                }
            }
            if ($null -ne $stderr -and $stderr.IsCompleted) {
                $line = $stderr.GetAwaiter().GetResult()
                $stderr = $null
                if ($null -ne $line) {
                    Write-JobsFlutterMessage $line
                    if ($Doctor -and $line -match '(?i)(?:^\s*\[(?:!|✗|x)\]|doctor found issues)') { $doctorIssues = $true }
                    $stderr = $process.StandardError.ReadLineAsync()
                }
            }
            Start-Sleep -Milliseconds 30
        }
        $remaining = [int][Math]::Max(1, ($TimeoutSeconds - $watch.Elapsed.TotalSeconds) * 1000)
        if (-not $process.WaitForExit($remaining)) {
            if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
                $taskkill = Join-Path ([Environment]::GetFolderPath('System')) 'taskkill.exe'
                [void](Invoke-JobsProcess -FilePath $taskkill -Arguments @('/PID', [string]$process.Id, '/T', '/F') -TimeoutSeconds 15)
            } else { $process.Kill() }
            throw '工具输出关闭后仍未退出，已请求终止本次进程树。'
        }
        if ($process.ExitCode -ne 0) { throw ('工具失败（退出码 ' + $process.ExitCode + '），后续步骤已停止。') }
        if ($Doctor -and $doctorIssues) { throw 'Flutter doctor 报告尚有未通过检查；请查看上述输出。' }
    } finally { $process.Dispose() }
}
function Invoke-JobsFlutterDoctorAction {
    param([string]$Target)
    $project = Assert-JobsRunnerDirectory $Target
    Assert-JobsFlutterProject $project
    Write-JobsFlutterMessage ('Flutter 项目体检；项目：' + $project)
    Write-JobsFlutterMessage '只读项目检查：执行当前 SDK 的 --version 与 doctor -v，不获取依赖、不 clean、不安装或升级工具。Flutter 自身可能检查网络并更新 SDK 缓存。'
    $sdk = Get-JobsFlutterSdk $project
    Write-JobsFlutterMessage ('Flutter SDK：' + $sdk.Flutter)
    Write-JobsFlutterMessage ('同源 Dart：' + $sdk.Dart)
    Invoke-JobsFlutterTool $sdk.Flutter @('--version') $project 300
    Invoke-JobsFlutterTool $sdk.Flutter @('doctor', '-v') $project 600 -Doctor
    Write-JobsFlutterMessage '体检完成；doctor 提示的缺失组件请按需手动处理。'
}

function Invoke-JobsFeature {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Target)
    Invoke-JobsFlutterDoctorAction -Target (Resolve-JobsTarget $Target)
}
Export-ModuleMember -Function Invoke-JobsFeature

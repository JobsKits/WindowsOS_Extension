# Action.psm1 | JobsFlutterCodegen
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
    throw '项目 FVM SDK 缺失；不会回退全局 Flutter。'
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
    param([string]$Executable, [string[]]$Arguments, [string]$Project, [int]$TimeoutSeconds = 1800)
    Write-JobsFlutterMessage ('执行：' + $Executable + ' ' + ($Arguments -join ' '))
    $process = New-Object Diagnostics.Process
    $process.StartInfo = New-JobsFlutterToolStartInfo $Executable $Arguments $Project
    $watch = [Diagnostics.Stopwatch]::StartNew()
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
                if ($null -ne $line) { Write-JobsFlutterMessage $line; $stdout = $process.StandardOutput.ReadLineAsync() }
            }
            if ($null -ne $stderr -and $stderr.IsCompleted) {
                $line = $stderr.GetAwaiter().GetResult()
                $stderr = $null
                if ($null -ne $line) { Write-JobsFlutterMessage $line; $stderr = $process.StandardError.ReadLineAsync() }
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
    } finally { $process.Dispose() }
}
function Get-JobsYamlSection {
    # 只解释根映射及其直接成员；flow map / block map 均不执行 YAML 对象构造。
    param([string]$Text, [string]$Name)
    $lines = @($Text.TrimStart([char]0xfeff) -split '\r?\n' | ForEach-Object { Remove-JobsYamlComment $_ })
    $roots = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -cmatch '^(?<key>[A-Za-z_][A-Za-z0-9_-]*|''[^'']+''|"[^"\\]+")\s*:\s*(?<value>.*)$') {
            if ((ConvertFrom-JobsYamlAtom $Matches['key']) -ceq $Name) { $roots += [pscustomobject]@{ Index = $i; Value = $Matches['value'] } }
        }
    }
    if ($roots.Count -gt 1) { throw ('pubspec.yaml 重复根键：' + $Name) }
    if ($roots.Count -eq 0) { return $null }
    if ($roots[0].Value.Trim().Length -gt 0) { return ,(ConvertFrom-JobsYamlFlowMap $roots[0].Value) }
    $result = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    $minimum = $null
    for ($i = $roots[0].Index + 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -notmatch '^ ') { break }
        $indent = $line.Length - $line.TrimStart(' ').Length
        if ($null -eq $minimum) { $minimum = $indent }
        if ($indent -ne $minimum) { continue }
        if ($line -notmatch '^ +(?<key>[A-Za-z_][A-Za-z0-9_-]*|''[^'']+''|"[^"\\]+")\s*:\s*(?<value>.*)$') { throw ('无法可靠读取 pubspec.yaml 的 ' + $Name + ' 映射。') }
        $key = ConvertFrom-JobsYamlAtom $Matches['key']
        $value = $Matches['value']
        if ($result.ContainsKey($key)) { throw ('pubspec.yaml 重复成员：' + $Name + '.' + $key) }
        $result[$key] = $value
    }
    return ,$result
}

function Test-JobsCodegenConfigFile {
    param([string]$Project, [string]$Relative)
    $file = Join-Path $Project $Relative
    if (-not (Test-JobsRunnerPathEntry $file)) { return $false }
    [void](Assert-JobsRunnerDirectory (Split-Path -Parent $file))
    Assert-JobsRunnerPlainFile $file
    return $true
}

function Get-JobsCodegenPlan {
    param([string]$Project)
    Assert-JobsFlutterProject $Project
    $text = Get-Content -LiteralPath (Join-Path $Project 'pubspec.yaml') -Raw -Encoding UTF8
    $dependencies = Get-JobsYamlSection $text 'dependencies'
    $devDependencies = Get-JobsYamlSection $text 'dev_dependencies'
    $direct = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($map in @($dependencies, $devDependencies)) {
        if ($null -ne $map) { foreach ($key in $map.Keys) { [void]$direct.Add($key) } }
    }
    $steps = @()
    if ($direct.Contains('build_runner')) { $steps += [pscustomobject]@{ Name = 'build_runner'; Tool = 'Dart'; Arguments = @('run', 'build_runner', 'build') } }
    foreach ($name in @('flutter_launcher_icons', 'flutter_native_splash', 'ffigen')) {
        if (-not $direct.Contains($name)) { continue }
        $config = Get-JobsYamlSection $text $name
        $file = $name + '.yaml'
        $hasFile = Test-JobsCodegenConfigFile $Project $file
        if ($null -eq $config -and -not $hasFile) { Write-Host ('跳过 ' + $name + '：只有依赖，没有明确配置。'); continue }
        $arguments = @('run', $name)
        if ($name -eq 'flutter_native_splash') { $arguments = @('run', 'flutter_native_splash:create') }
        if ($hasFile) {
            if ($name -eq 'flutter_native_splash') { $arguments += ('--path=' + $file) }
            elseif ($name -eq 'flutter_launcher_icons') { $arguments += @('-f', $file) }
            else { $arguments += @('--config', $file) }
        }
        $steps += [pscustomobject]@{ Name = $name; Tool = 'Dart'; Arguments = $arguments }
    }
    $flutter = Get-JobsYamlSection $text 'flutter'
    $generate = $null -ne $flutter -and $flutter.ContainsKey('generate') -and (ConvertFrom-JobsYamlAtom $flutter['generate']) -ceq 'true'
    $hasL10nConfig = Test-JobsCodegenConfigFile $Project 'l10n.yaml'
    $arbDirectory = Join-Path $Project 'lib/l10n'
    $hasArb = $false
    if ([IO.Directory]::Exists($arbDirectory)) {
        [void](Assert-JobsRunnerDirectory $arbDirectory)
        $hasArb = @(Get-ChildItem -LiteralPath $arbDirectory -Filter '*.arb' -File).Count -gt 0
    }
    if ($generate -and ($hasL10nConfig -or $hasArb)) { $steps += [pscustomobject]@{ Name = 'l10n'; Tool = 'Flutter'; Arguments = @('gen-l10n') } }
    if ($direct.Contains('pigeon') -and (Test-JobsCodegenConfigFile $Project 'pigeons/messages.dart')) {
        $pigeon = Get-Content -LiteralPath (Join-Path $Project 'pigeons/messages.dart') -Raw -Encoding UTF8
        $pigeon = $pigeon -replace '(?s)/\*.*?\*/', '' -replace '(?m)//.*$', ''
        if ($pigeon -cmatch '(?m)^\s*@(?:[A-Za-z_]\w*\.)?ConfigurePigeon\s*\(') {
            $steps += [pscustomobject]@{ Name = 'pigeon'; Tool = 'Dart'; Arguments = @('run', 'pigeon', '--input', 'pigeons/messages.dart') }
        } else { Write-Host '跳过 pigeon：messages.dart 缺少 @ConfigurePigeon 输出配置。' }
    }
    $protoDirectory = Join-Path $Project 'protos'
    if ($direct.Contains('protobuf') -and [IO.Directory]::Exists($protoDirectory)) {
        [void](Assert-JobsRunnerDirectory $protoDirectory)
        $protos = @(Get-ChildItem -LiteralPath $protoDirectory -Filter '*.proto' -File | Sort-Object Name)
        if ($protos.Count -gt 0) {
            $arguments = @('--dart_out=lib/generated', '-Iprotos')
            if ($direct.Contains('grpc')) { $arguments[0] = '--dart_out=grpc:lib/generated' }
            foreach ($proto in $protos) { Assert-JobsRunnerPlainFile $proto.FullName; $arguments += ('protos/' + $proto.Name) }
            $steps += [pscustomobject]@{ Name = 'protobuf'; Tool = 'Protoc'; Arguments = $arguments }
        }
    }
    return $steps
}

function Read-JobsCodegenConsent {
    # ReadLine 保留 EOF 和空行差别：只有真实回车才代表执行，EOF 不构成授权。
    Write-Host '回车执行上述步骤；任意非空输入取消：' -NoNewline
    $answer = [Console]::ReadLine()
    return $null -ne $answer -and $answer.Length -eq 0
}

function ConvertFrom-JobsCodegenDeleteAnswer {
    param([AllowNull()]$Answer)
    if ($null -eq $Answer) { throw '输入已关闭；停止执行，未获取依赖或生成文件。' }
    return $Answer -ceq 'YES'
}

function Read-JobsCodegenDeleteConsent {
    Write-Host '可选：输入 YES 明确允许 build_runner 删除冲突产物；回车保留默认行为：' -NoNewline
    $answer = [Console]::ReadLine()
    return ConvertFrom-JobsCodegenDeleteAnswer $answer
}

function Invoke-JobsFlutterCodegenAction {
    param([string]$Target)
    $project = Assert-JobsRunnerDirectory $Target
    Write-JobsFlutterMessage ('Flutter 自动化生产代码；项目：' + $project)
    $plan = @(Get-JobsCodegenPlan $project)
    if ($plan.Count -eq 0) { Write-JobsFlutterMessage '没有已配置的生成器；确认后仅运行 flutter pub get。' }
    $sdk = Get-JobsFlutterSdk $project
    $protoc = $null
    if (@($plan | Where-Object Tool -eq 'Protoc').Count -gt 0) {
        $protoc = Find-JobsExecutable -Name 'protoc.exe' -Candidates @('protoc')
        $plugin = Find-JobsExecutable -Name 'protoc-gen-dart.bat' -Candidates @('protoc-gen-dart.exe', 'protoc-gen-dart')
        if (-not $protoc -or -not $plugin) { throw '已配置 protobuf，但缺少 protoc 或 protoc-gen-dart；请手动安装后重试，本工具不全局激活依赖。' }
    }
    Write-JobsFlutterMessage '将运行 flutter pub get（可能联网并修改 pubspec.lock / .dart_tool），随后按项目配置改写生成文件；生成器可运行项目自己的构建逻辑。'
    foreach ($step in $plan) { Write-JobsFlutterMessage ('计划：' + $step.Name + ' → ' + ($step.Arguments -join ' ')) }
    if (-not (Read-JobsCodegenConsent)) { Write-JobsFlutterMessage '已取消；未执行 pub get 或生成。'; return }
    $delete = $false
    if (@($plan | Where-Object Name -eq 'build_runner').Count -gt 0) { $delete = Read-JobsCodegenDeleteConsent }
    # 确认后再次校验项目，避免预览期间目录或配置文件被替换成链接。
    Assert-JobsFlutterProject $project
    Invoke-JobsFlutterTool $sdk.Flutter @('pub', 'get') $project
    foreach ($step in $plan) {
        $arguments = @($step.Arguments)
        if ($step.Name -eq 'build_runner' -and $delete) { $arguments += '--delete-conflicting-outputs' }
        $executable = $sdk.Dart
        if ($step.Tool -eq 'Flutter') { $executable = $sdk.Flutter }
        if ($step.Tool -eq 'Protoc') {
            $executable = $protoc
            $lib = Join-Path $project 'lib'
            if (Test-JobsRunnerPathEntry $lib) { [void](Assert-JobsRunnerDirectory $lib) }
            $output = Join-Path $project 'lib/generated'
            if (Test-JobsRunnerPathEntry $output) { [void](Assert-JobsRunnerDirectory $output) }
            [void][IO.Directory]::CreateDirectory($output)
        }
        Invoke-JobsFlutterTool $executable $arguments $project
    }
    Write-JobsFlutterMessage '全部生成步骤完成。请审查项目 diff 后再提交。'
}

function Invoke-JobsFeature {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Target)
    Invoke-JobsFlutterCodegenAction -Target (Resolve-JobsTarget $Target)
}
Export-ModuleMember -Function Invoke-JobsFeature

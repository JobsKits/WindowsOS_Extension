# Action.psm1
# JobsFlutterSdkInspector
# Created by Jobs on 2026年10月21日，星期二.
# 只读查询当前 Flutter 项目实际使用的 Flutter SDK 版本；FVM 管理的项目显示 FVM 版本，否则显示系统 SDK 环境。

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking

function Write-JobsSdkMessage {
    param([string]$Message)
    $safe = $Message -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@'
    $safe = $safe -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]'
    $safe = $safe -replace '(?im)((?:access[_-]?token|authorization|password|secret)\s*[:=]\s*)\S+', '$1[已省略]'
    Write-Host $safe
    Write-JobsLog $safe
}

function Assert-JobsSdkDirectory {
    param([string]$Path)
    if (-not [IO.Path]::IsPathRooted($Path) -or -not [IO.Directory]::Exists($Path)) {
        throw "目标必须是已存在的绝对目录：$Path"
    }
    $item = New-Object IO.DirectoryInfo ([IO.Path]::GetFullPath($Path))
    $current = $item
    while ($null -ne $current) {
        if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "不处理符号链接、目录联接或其它重解析目录：$($current.FullName)"
        }
        $current = $current.Parent
    }
    return $item.FullName
}

function Assert-JobsSdkPlainFile {
    param([string]$Path)
    if (-not [IO.File]::Exists($Path)) { throw "缺少文件：$Path" }
    $attributes = [IO.File]::GetAttributes($Path)
    if (($attributes -band [IO.FileAttributes]::Directory) -ne 0 -or ($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "配置必须是普通文件：$Path"
    }
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

function Get-JobsEnvironmentConstraints {
    # 读取 pubspec 根级 environment 的 sdk / flutter 约束；无法可靠解析时返回空并跳过核对。
    param([string]$Text)
    $lines = @($Text -split '\r?\n' | ForEach-Object { Remove-JobsYamlComment $_ })
    if (@($lines | Where-Object { $_ -match '^\s*\t' }).Count -gt 0) { return $null }
    $roots = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -cmatch '^environment\s*:\s*(.*)$') { $roots += [pscustomobject]@{ Index = $i; Value = $Matches[1] } }
    }
    if ($roots.Count -ne 1) { return $null }
    try {
        if (-not [string]::IsNullOrWhiteSpace($roots[0].Value)) {
            $inline = ConvertFrom-JobsYamlFlowMap $roots[0].Value
            return @{
                Sdk = if ($inline.ContainsKey('sdk')) { ConvertFrom-JobsYamlAtom $inline['sdk'] } else { '' }
                Flutter = if ($inline.ContainsKey('flutter')) { ConvertFrom-JobsYamlAtom $inline['flutter'] } else { '' }
            }
        }
        $constraints = @{ Sdk = ''; Flutter = '' }
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $minimum = $null
        for ($i = $roots[0].Index + 1; $i -lt $lines.Count; $i++) {
            if ([string]::IsNullOrWhiteSpace($lines[$i])) { continue }
            if ($lines[$i] -notmatch '^\s') { break }
            if ($lines[$i] -notmatch '^(?<indent> +)(?<key>[A-Za-z_][A-Za-z0-9_-]*|''[^'']+''|"[^"\\]+")\s*:\s*(?<value>.*)$') { continue }
            $indent = $Matches['indent'].Length
            if ($null -eq $minimum) { $minimum = $indent }
            if ($indent -ne $minimum) { continue }
            $key = ConvertFrom-JobsYamlAtom $Matches['key']
            if (-not $seen.Add($key)) { return $null }
            if ($key -ceq 'sdk') { $constraints.Sdk = ConvertFrom-JobsYamlAtom $Matches['value'] }
            if ($key -ceq 'flutter') { $constraints.Flutter = ConvertFrom-JobsYamlAtom $Matches['value'] }
        }
        return $constraints
    }
    catch { return $null }
}

function Get-JobsProjectFvmPinned {
    # 读取 FVM 配置声明的版本：新版 .fvmrc 优先，兼容旧版 .fvm/fvm_config.json。
    param([string]$Directory)
    $path = Join-Path $Directory '.fvmrc'
    if (-not [IO.File]::Exists($path)) { $path = Join-Path $Directory '.fvm\fvm_config.json' }
    if (-not [IO.File]::Exists($path)) { return $null }
    Assert-JobsSdkPlainFile $path
    $config = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $config -or $config -is [array] -or $config -is [string] -or $config -is [ValueType]) { throw '.fvmrc 必须是 JSON 对象。' }
    $pinned = ''
    if ($null -ne $config.PSObject.Properties['flutter']) { $pinned = [string]$config.flutter }
    elseif ($null -ne $config.PSObject.Properties['flutterSdkVersion']) { $pinned = [string]$config.flutterSdkVersion }
    Write-JobsSdkMessage "FVM 配置文件：$path"
    return $pinned
}

function ConvertFrom-JobsVersionAtom {
    # 仅解析纯数字三段版本；带预发布 / build 后缀的返回空并交给人工核对。
    param([string]$Text)
    $trimmed = ([string]$Text).Trim()
    if ($trimmed -cmatch '^v?(\d+)\.(\d+)\.(\d+)$') {
        try { return [version]::new([int]$Matches[1], [int]$Matches[2], [int]$Matches[3]) } catch { return $null }
    }
    return $null
}

function Test-JobsVersionConstraint {
    # 只判定常见约束写法（^、>=、<=、>、< 与空格多段）；无法可靠判定的输出未知而不是假装满足。
    param([string]$Name, [string]$Constraint, [string]$ActualText)
    $actual = ConvertFrom-JobsVersionAtom $ActualText
    if ($null -eq $actual) { return @{ Outcome = '未知'; Detail = "实际版本 $ActualText 无法解析，未做区间判定，请人工核对。" } }
    $trimmed = ([string]$Constraint).Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed -eq '*' -or $trimmed -ceq 'any') { return @{ Outcome = '无约束'; Detail = '无约束。' } }
    if ($trimmed -match '[-+]') { return @{ Outcome = '未知'; Detail = "约束 $trimmed 含预发布 / build 后缀，未做区间判定，请人工核对。" } }
    foreach ($part in ($trimmed -split '\s+')) {
        if ($part -cmatch '^\^(?<bound>\d+\.\d+\.\d+)$') {
            $bound = ConvertFrom-JobsVersionAtom $Matches['bound']
            if ($null -eq $bound) { return @{ Outcome = '未知'; Detail = "约束 $part 无法解析，请人工核对。" } }
            if ($actual -lt $bound) { return @{ Outcome = '不满足'; Detail = "不满足 ^$($Matches['bound'])（实际 $ActualText 低于下限）。" } }
            $upper = if ($bound.Major -eq 0) { [version]::new(0, $bound.Minor + 1, 0) } else { [version]::new($bound.Major + 1, 0, 0) }
            if ($actual -ge $upper) { return @{ Outcome = '不满足'; Detail = "不满足 ^$($Matches['bound'])（实际 $ActualText 已达到上界 $upper）。" } }
        }
        elseif ($part -cmatch '^>=(?<bound>\d+\.\d+\.\d+)$') {
            $bound = ConvertFrom-JobsVersionAtom $Matches['bound']
            if ($null -eq $bound -or $actual -lt $bound) { return @{ Outcome = '不满足'; Detail = "不满足 >=$($Matches['bound'])（实际 $ActualText）。" } }
        }
        elseif ($part -cmatch '^<=(?<bound>\d+\.\d+\.\d+)$') {
            $bound = ConvertFrom-JobsVersionAtom $Matches['bound']
            if ($null -eq $bound -or $actual -gt $bound) { return @{ Outcome = '不满足'; Detail = "不满足 <=$($Matches['bound'])（实际 $ActualText）。" } }
        }
        elseif ($part -cmatch '^<(?<bound>\d+\.\d+\.\d+)$') {
            $bound = ConvertFrom-JobsVersionAtom $Matches['bound']
            if ($null -eq $bound -or $actual -ge $bound) { return @{ Outcome = '不满足'; Detail = "不满足 <$($Matches['bound'])（实际 $ActualText 不低于上限）。" } }
        }
        elseif ($part -cmatch '^>(?<bound>\d+\.\d+\.\d+)$') {
            $bound = ConvertFrom-JobsVersionAtom $Matches['bound']
            if ($null -eq $bound -or $actual -le $bound) { return @{ Outcome = '不满足'; Detail = "不满足 >$($Matches['bound'])（实际 $ActualText 不高于下限）。" } }
        }
        else { return @{ Outcome = '未知'; Detail = "约束写法 $part 超过本扩展判定范围，请人工核对。" } }
    }
    return @{ Outcome = '满足'; Detail = "实际 $ActualText 满足 $trimmed。" }
}

function Invoke-JobsFlutterMachine {
    # 通过 cmd 执行 flutter.bat --version --machine；超时终止本次进程树。
    param([string]$FlutterBat, [string]$Directory, [int]$TimeoutSeconds = 300)
    if ($FlutterBat -match '["\r\n]') { throw 'Flutter 安装路径包含引号或换行。' }
    $cmd = Join-Path ([Environment]::GetFolderPath('System')) 'cmd.exe'
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $cmd
    $start.Arguments = '/d /v:off /s /c ""%JOBS_FLUTTER_EXECUTABLE%" --version --machine"'
    $start.EnvironmentVariables['JOBS_FLUTTER_EXECUTABLE'] = $FlutterBat
    $start.WorkingDirectory = $Directory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $start.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    $start.EnvironmentVariables['CI'] = 'true'
    $start.EnvironmentVariables['FLUTTER_SUPPRESS_ANALYTICS'] = 'true'
    $start.EnvironmentVariables['DART_SUPPRESS_ANALYTICS'] = 'true'
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        Write-JobsSdkMessage "执行：flutter --version --machine；SDK：$FlutterBat"
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $taskkill = Join-Path ([Environment]::GetFolderPath('System')) 'taskkill.exe'
            [void](Invoke-JobsProcess -FilePath $taskkill -Arguments @('/PID', [string]$process.Id, '/T', '/F') -WorkingDirectory $Directory)
            throw 'Flutter 版本查询超时，已终止本次进程树。'
        }
        $tasks = [Threading.Tasks.Task[]]@($stdout, $stderr)
        if (-not [Threading.Tasks.Task]::WaitAll($tasks, 5000)) { throw 'Flutter 已退出，但输出管道未能按时关闭。' }
        $output = $stdout.GetAwaiter().GetResult()
        $errors = $stderr.GetAwaiter().GetResult()
        if ($errors) { Write-JobsSdkMessage $errors.TrimEnd() }
        if ($process.ExitCode -ne 0) { throw "Flutter 版本查询失败（退出码 $($process.ExitCode)）。" }
        return $output
    }
    finally { $process.Dispose() }
}

function Get-JobsMachineField {
    # JSON 字段可能因 Flutter 版本差异而缺失；缺失时返回空串而不是触发 StrictMode 异常。
    param($Machine, [string]$Name)
    if ($null -ne $Machine -and $null -ne $Machine.PSObject.Properties[$Name]) { return [string]$Machine.$Name }
    return ''
}

function ConvertFrom-JobsFlutterMachineOutput {
    # 只采信 --version --machine 的 JSON 主体；前后杂散输出一律剥离。
    param([string]$Output)
    $first = $Output.IndexOf('{')
    $last = $Output.LastIndexOf('}')
    if ($first -lt 0 -or $last -le $first) { throw 'Flutter --version --machine 没有返回 JSON 输出。' }
    $payload = $Output.Substring($first, $last - $first + 1)
    $machine = $payload | ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $machine -or $null -eq $machine.PSObject.Properties['frameworkVersion']) { throw 'Flutter 机器可读版本输出缺少 frameworkVersion。' }
    if ([string]$machine.frameworkVersion -cnotmatch '^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$') { throw 'Flutter Framework 版本格式无效。' }
    return $machine
}

function Get-JobsFvmLinkTarget {
    # 返回 .fvm/flutter_sdk 链接指向的缓存版本目录名；解析失败时返回空。
    param([string]$LinkPath)
    try {
        $item = Get-Item -LiteralPath $LinkPath -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { return '' }
        if ($null -eq $item.PSObject.Properties['Target'] -or $null -eq $item.Target) { return '' }
        $target = [string](@($item.Target)[0])
        if ([string]::IsNullOrWhiteSpace($target)) { return '' }
        return (Split-Path -Leaf ($target.TrimEnd('\', '/')))
    }
    catch { return '' }
}

function Invoke-JobsSdkInspect {
    param([string]$Directory)
    Write-JobsSdkMessage "Flutter SDK 版本查询（只读）；目标：$Directory"
    $pubspec = Join-Path $Directory 'pubspec.yaml'
    Assert-JobsSdkPlainFile $pubspec
    $manifest = Get-Content -LiteralPath $pubspec -Raw -Encoding UTF8
    if (-not (Test-JobsFlutterPubspec $manifest)) {
        throw '目标同层 pubspec.yaml 必须明确声明 dependencies.flutter.sdk: flutter；本扩展只处理真实 Flutter 项目。'
    }
    $constraints = Get-JobsEnvironmentConstraints $manifest
    if ($null -ne $constraints) {
        if ($constraints.Sdk) { Write-JobsSdkMessage "项目 environment.sdk：$($constraints.Sdk)" }
        if ($constraints.Flutter) { Write-JobsSdkMessage "项目 environment.flutter：$($constraints.Flutter)" }
    }
    else {
        Write-JobsSdkMessage 'pubspec.yaml environment 无法可靠解析，跳过约束核对。'
    }

    $pinned = Get-JobsProjectFvmPinned $Directory
    $flutter = $null
    $sdkSource = ''
    $sdkRoot = ''
    $linkVersion = ''
    $fvmLink = Join-Path $Directory '.fvm\flutter_sdk'
    $fvmFlutter = Join-Path $fvmLink 'bin\flutter.bat'
    if ([IO.File]::Exists($fvmFlutter)) {
        $flutter = $fvmFlutter
        $sdkRoot = $fvmLink
        $linkVersion = Get-JobsFvmLinkTarget $fvmLink
        $sdkSource = 'FVM 项目 SDK（.fvm/flutter_sdk）'
        Write-JobsSdkMessage "FVM 链接已生效：flutter_sdk → $sdkRoot"
    }
    else {
        if ($null -ne $pinned) {
            if ($pinned) { Write-JobsSdkMessage ".fvmrc 已指定 $pinned，但项目 .fvm\flutter_sdk 尚未链接或不可用；本次显示系统 Flutter SDK。请执行 fvm use <版本> 后再查询。" }
            else { Write-JobsSdkMessage '存在 FVM 配置但没有指定具体版本，也没有可用的 .fvm\flutter_sdk；本次显示系统 Flutter SDK。' }
        }
        else {
            Write-JobsSdkMessage '项目不由 FVM 管理（缺少 .fvmrc / .fvm/fvm_config.json）；本次显示系统 Flutter SDK。'
        }
        $candidates = @()
        $pathFlutter = Find-JobsExecutable -Name 'flutter.bat' -Candidates @()
        if ($pathFlutter) { $candidates += $pathFlutter }
        $userFvm = Join-Path $env:USERPROFILE 'fvm\default\bin\flutter.bat'
        if ((Test-Path -LiteralPath $userFvm -PathType Leaf) -and $userFvm -notin $candidates) { $candidates += $userFvm }
        if ($candidates.Count -eq 0) { throw '未找到可执行的 Flutter SDK。请先安装 Flutter 或用 FVM 安装版本；本扩展不自动安装 SDK。' }
        $flutter = $candidates[0]
        $sdkRoot = (Split-Path -Parent (Split-Path -Parent $flutter))
        $sdkSource = '系统 Flutter SDK（PATH / 常见安装位置）'
        if ($candidates.Count -gt 1) { Write-JobsSdkMessage "发现多个系统候选，本次采信：$flutter" }
    }

    $output = Invoke-JobsFlutterMachine -FlutterBat $flutter -Directory $Directory
    $machine = ConvertFrom-JobsFlutterMachineOutput $output
    if ($null -ne $machine.PSObject.Properties['flutterRoot'] -and -not [string]::IsNullOrWhiteSpace([string]$machine.flutterRoot)) {
        $sdkRoot = [string]$machine.flutterRoot
    }
    $framework = [string]$machine.frameworkVersion
    $dart = Get-JobsMachineField $machine 'dartSdkVersion'
    $channel = Get-JobsMachineField $machine 'channel'
    $frameworkRevision = Get-JobsMachineField $machine 'frameworkRevision'
    $frameworkDate = Get-JobsMachineField $machine 'frameworkCommitDate'
    $engineRevision = Get-JobsMachineField $machine 'engineRevision'

    Write-JobsSdkMessage '━━━━━━━━━━ 查询结果 ━━━━━━━━━━'
    Write-JobsSdkMessage "项目：$Directory"
    Write-JobsSdkMessage "来源：$sdkSource"
    Write-JobsSdkMessage "Flutter 版本：$framework"
    Write-JobsSdkMessage "Dart 版本：$dart"
    if ($channel) { Write-JobsSdkMessage "发布渠道：$channel" }
    Write-JobsSdkMessage "SDK 路径：$sdkRoot"
    Write-JobsSdkMessage "SDK 可执行文件：$flutter"
    if ($frameworkRevision) { Write-JobsSdkMessage "Framework revision：$frameworkRevision" }
    if ($frameworkDate) { Write-JobsSdkMessage "Framework 提交时间：$frameworkDate" }
    if ($engineRevision) { Write-JobsSdkMessage "Engine revision：$engineRevision" }
    if ($null -ne $pinned) {
        $note = "FVM 配置版本：$pinned"
        if ($linkVersion -and $linkVersion -ceq $framework) { $note += '；链接目录与实际版本一致' }
        elseif ($linkVersion) { $note += "；链接目录 $linkVersion 与实际版本 $framework 不一致" }
        else { $note += '；项目未链接 .fvm\flutter_sdk，当前结论来自系统 SDK' }
        Write-JobsSdkMessage $note
    }
    if ($null -ne $constraints) {
        if ($constraints.Sdk) {
            $result = Test-JobsVersionConstraint -Name 'environment.sdk（Dart）' -Constraint $constraints.Sdk -ActualText $dart
            Write-JobsSdkMessage "$($result.Outcome)：environment.sdk（Dart）$($result.Detail)"
        }
        if ($constraints.Flutter) {
            $result = Test-JobsVersionConstraint -Name 'environment.flutter' -Constraint $constraints.Flutter -ActualText $framework
            Write-JobsSdkMessage "$($result.Outcome)：environment.flutter $($result.Detail)"
        }
    }
    Write-JobsSdkMessage '查询完成，未修改任何项目文件。'
}

function Invoke-JobsFeature {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Target)
    $directory = Assert-JobsSdkDirectory (Resolve-JobsTarget $Target)
    Invoke-JobsSdkInspect -Directory $directory
}

Export-ModuleMember -Function Invoke-JobsFeature

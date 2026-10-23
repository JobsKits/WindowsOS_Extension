# Action.psm1 | JobsFlutterRunner
# Created by Jobs on 2026年10月20日，星期二.
# CMD 中选择设备和连接日志；Flutter 生命周期由独立后台宿主管理。
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

function Invoke-JobsRunnerTool {
    param([string]$Flutter, [string[]]$Arguments, [string]$Project, [int]$TimeoutSeconds = 60)
    if ($Flutter -match '["\x00-\x1f]' -or @($Arguments | Where-Object { $_ -cnotmatch '^[A-Za-z0-9._:@/+=-]+$' }).Count -gt 0) {
        throw '工具参数不合法。'
    }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Flutter
    $start.Arguments = @($Arguments | ForEach-Object { Quote-JobsArgument $_ }) -join ' '
    if ([IO.Path]::GetExtension($Flutter) -in @('.bat', '.cmd')) {
        $start.FileName = Join-Path ([Environment]::GetFolderPath('System')) 'cmd.exe'
        $start.EnvironmentVariables['JOBS_FLUTTER_RUNNER_TOOL'] = $Flutter
        $start.Arguments = '/d /v:off /s /c ""%JOBS_FLUTTER_RUNNER_TOOL%" ' + ($Arguments -join ' ') + '"'
    }
    $start.WorkingDirectory = $Project
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $start.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    $start.EnvironmentVariables['FLUTTER_SUPPRESS_ANALYTICS'] = 'true'
    $start.EnvironmentVariables['DART_SUPPRESS_ANALYTICS'] = 'true'
    $process = [Diagnostics.Process]::Start($start)
    try {
        $output = $process.StandardOutput.ReadToEndAsync()
        $errors = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $taskkill = Join-Path ([Environment]::GetFolderPath('System')) 'taskkill.exe'
            [void](Invoke-JobsProcess $taskkill @('/PID', [string]$process.Id, '/T', '/F') -WorkingDirectory $Project)
            throw 'Flutter 设备查询 / 模拟器启动超时；已停止本次查询进程树。'
        }
        if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($output, $errors), 5000)) { throw 'Flutter 输出管道未按时关闭。' }
        if ($process.ExitCode -ne 0) { throw ('Flutter 命令失败：' + $errors.GetAwaiter().GetResult()) }
        return $output.GetAwaiter().GetResult()
    } finally { $process.Dispose() }
}

function ConvertFrom-JobsRunnerList {
    param([AllowEmptyString()][string]$Output)
    # 首次 SDK 启动可能在 JSON 前输出准备信息；只接受完整、合法的末尾数组。
    $text = $Output.Trim()
    for ($index = 0; $index -lt $text.Length; $index++) {
        if ($text[$index] -ne '[') { continue }
        try {
            $json = $text.Substring($index) | ConvertFrom-Json -ErrorAction Stop
            if ($null -eq $json) { return }
            foreach ($entry in @($json)) {
                if ($null -eq $entry.PSObject.Properties['id'] -or $entry.id -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.id)) {
                    throw '设备响应缺少有效 id。'
                }
            }
            foreach ($entry in @($json)) { Write-Output $entry }
            return
        } catch { }
    }
    throw 'Flutter 未返回可解析的设备 / 模拟器列表；请先运行 flutter doctor。'
}

function Get-JobsRunnerSupportedDevices {
    param([object[]]$Devices, [string]$Project)
    foreach ($device in $Devices) {
        if ($null -eq $device.PSObject.Properties['targetPlatform']) { continue }
        if ($null -ne $device.PSObject.Properties['isSupported'] -and -not $device.isSupported) { continue }
        $platform = [string]$device.targetPlatform
        if ($platform -eq 'android' -and ((Test-Path -LiteralPath (Join-Path $Project 'android') -PathType Container) -or (Test-Path -LiteralPath (Join-Path $Project '.android') -PathType Container))) { $device }
        elseif ($platform -like 'windows-*' -and (Test-Path -LiteralPath (Join-Path $Project 'windows') -PathType Container)) { $device }
        elseif ($platform -eq 'web-javascript' -and (Test-Path -LiteralPath (Join-Path $Project 'web') -PathType Container)) { $device }
    }
}

function Get-JobsRunnerAndroidEmulator {
    $roots = @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME)
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { $roots += Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
    foreach ($root in $roots) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        $candidate = Join-Path $root 'emulator/emulator.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return Find-JobsExecutable 'emulator.exe'
}

function Select-JobsRunnerDevice {
    param([string]$Flutter, [string]$Project)
    while ($true) {
        Write-Host '正在读取 Flutter 设备和 Android 模拟器……'
        $allDevices = @(ConvertFrom-JobsRunnerList (Invoke-JobsRunnerTool $Flutter @('devices', '--machine') $Project))
        $devices = @(Get-JobsRunnerSupportedDevices $allDevices $Project)
        $emulators = @()
        $androidEmulator = Get-JobsRunnerAndroidEmulator
        if ($androidEmulator -and ((Test-Path -LiteralPath (Join-Path $Project 'android') -PathType Container) -or (Test-Path -LiteralPath (Join-Path $Project '.android') -PathType Container))) {
            try { $emulators = @((Invoke-JobsRunnerTool $androidEmulator @('-list-avds') $Project) -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) }
            catch { Write-Host ('模拟器列表暂不可用：' + $_.Exception.Message) -ForegroundColor Yellow }
        }
        $choices = @()
        foreach ($device in $devices) {
            $choices += [pscustomobject]@{ Kind = 'Device'; Id = [string]$device.id; Name = [string]$device.name }
        }
        foreach ($emulator in $emulators) {
            $choices += [pscustomobject]@{ Kind = 'Emulator'; Id = [string]$emulator; Name = ('启动 Android 模拟器 · ' + $emulator) }
        }
        if ($choices.Count -eq 0) {
            Write-Host '暂无可用设备。连接手机、启动 Android 模拟器或安装对应桌面 / 浏览器工具链后重新加载。' -ForegroundColor Yellow
        }
        for ($index = 0; $index -lt $choices.Count; $index++) { Write-Host ('[' + ($index + 1) + '] ' + $choices[$index].Name + ' (' + $choices[$index].Id + ')') }
        $answer = Read-Host '[r] 重新加载  [q] 取消；输入设备序号'
        if ($null -eq $answer -or $answer -ceq 'q') { return $null }
        if ($answer -ceq 'r') { continue }
        $number = 0
        if (-not [int]::TryParse($answer, [ref]$number) -or $number -lt 1 -or $number -gt $choices.Count) { continue }
        $choice = $choices[$number - 1]
        if ($choice.Kind -eq 'Device') { return $choice.Id }
        Write-Host ('启动：' + $choice.Name)
        $start = New-Object Diagnostics.ProcessStartInfo
        $start.FileName = $androidEmulator
        $start.Arguments = '-avd ' + (Quote-JobsArgument $choice.Id)
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.WorkingDirectory = $Project
        [void][Diagnostics.Process]::Start($start)
        Write-Host '模拟器已收到启动请求。等待启动完成后按回车重新加载，再选择实际运行设备。'
        if ($null -eq (Read-Host)) { return $null }
    }
}

function Get-JobsRunnerProjectRoot {
    param([string]$Project)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Project.ToUpperInvariant()))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
    return Join-Path (Join-Path (Get-JobsInstallRoot) 'runs') $hash
}

function Get-JobsRunnerSession {
    param([string]$ProjectRoot)
    if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) { return $null }
    foreach ($directory in @(Get-ChildItem -LiteralPath $ProjectRoot -Directory | Sort-Object Name -Descending)) {
        $file = Join-Path $directory.FullName 'state.json'
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        try {
            $state = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($state.Status -notin @('Starting', 'Running')) { continue }
            $process = Get-Process -Id $state.WorkerPid -ErrorAction Stop
            $start = $process.StartTime.ToUniversalTime().Ticks
            if ($start -ne ([DateTime]$state.WorkerStartUtc).ToUniversalTime().Ticks) { continue }
            return $state
        } catch { }
    }
    return $null
}

function Send-JobsRunnerControl {
    param([string]$Session, [ValidateSet('reload', 'restart', 'stop')][string]$Command)
    $name = 'control-' + [guid]::NewGuid().ToString('N')
    $temporary = Join-Path $Session ($name + '.tmp')
    $path = Join-Path $Session ($name + '.json')
    [IO.File]::WriteAllText($temporary, (@{ Command = $Command } | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))
    [IO.File]::Move($temporary, $path)
}

function Show-JobsRunnerLog {
    param([string]$Session)
    $path = Join-Path $Session 'run.log'
    Write-Host ('日志：' + $path) -ForegroundColor Cyan
    Write-Host 'r 热重载；R 热重启；s 停止；q 退出日志。直接关闭 CMD 也会保留后台运行。' -ForegroundColor Green
    $reader = $null
    try {
        while ($null -eq $reader) {
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                $stream = New-Object IO.FileStream($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
                $reader = New-Object IO.StreamReader($stream, (New-Object Text.UTF8Encoding($false)))
            } else { Start-Sleep -Milliseconds 100 }
        }
        while ($true) {
            $text = $reader.ReadToEnd()
            if ($text.Length -gt 0) { Write-Host -NoNewline $text }
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true).KeyChar
                switch -CaseSensitive ($key) {
                    'r' { Send-JobsRunnerControl $Session reload }
                    'R' { Send-JobsRunnerControl $Session restart }
                    's' { Send-JobsRunnerControl $Session stop; Write-Host '已请求停止；最多等待 10 秒后停止本次 Flutter 进程树。' }
                    'q' { return }
                }
            }
            $statePath = Join-Path $Session 'state.json'
            try {
                $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($state.Status -in @('Stopped', 'Failed')) { Write-Host -NoNewline $reader.ReadToEnd(); return }
                $running = Get-Process -Id $state.WorkerPid -ErrorAction Stop
                if ($running.StartTime.ToUniversalTime().Ticks -ne ([DateTime]$state.WorkerStartUtc).ToUniversalTime().Ticks) { throw '进程已退出。' }
            } catch { Write-Host '后台状态不可用，请重新右键检查日志。' -ForegroundColor Yellow; return }
            Start-Sleep -Milliseconds 150
        }
    } finally { if ($reader) { $reader.Dispose() } }
}

function Start-JobsRunnerSession {
    param([string]$Project, [string]$Flutter, [string]$Device, [string]$ProjectRoot)
    $session = Join-Path $ProjectRoot ((Get-Date -Format 'yyyy.MM.dd HH-mm-ss') + '-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($session)
    $request = Join-Path $session 'request.json'
    [IO.File]::WriteAllText($request, (@{ Project = $Project; Flutter = $Flutter; Device = $Device } | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    $hostPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'bin/JobsFlutterRunnerHost.exe'
    if (-not (Test-Path -LiteralPath $hostPath -PathType Leaf)) { throw '后台宿主缺失，请重新安装本包。' }
    [void](Invoke-JobsProcess $hostPath @('start', $request) -WorkingDirectory $Project)
    $clock = [Diagnostics.Stopwatch]::StartNew()
    while ($clock.Elapsed.TotalSeconds -lt 15) {
        $failure = Join-Path $session 'startup-error.log'
        if (Test-Path -LiteralPath $failure -PathType Leaf) { throw ('后台启动失败，详见：' + $failure) }
        if (Test-Path -LiteralPath (Join-Path $session 'state.json') -PathType Leaf) { return $session }
        Start-Sleep -Milliseconds 100
    }
    throw ('后台未按时返回状态，请查看：' + $session)
}

function Invoke-JobsFlutterRunAction {
    param([string]$Target)
    Assert-JobsFlutterProject $Target
    if ($Target.StartsWith('\\')) { throw '本菜单只处理本机项目目录，不处理 UNC 共享。' }
    Write-Host 'Jobs · 运行 Flutter 项目（CMD）' -ForegroundColor Red
    Write-Host ('来源：' + $PSScriptRoot) -ForegroundColor Cyan
    Write-Host ('项目：' + $Target)
    Write-Host '设备选择后启动 flutter run --machine；运行日志进入 CMD 和本功能日志目录。'
    Write-Host '关闭 CMD 不停止项目；重新右键可重连日志，r / R 热重载 / 热重启，s 停止。'
    $projectRoot = Get-JobsRunnerProjectRoot $Target
    $existing = Get-JobsRunnerSession $projectRoot
    if ($existing) { Show-JobsRunnerLog $existing.Session; return }
    $flutter = Get-JobsRunnerFlutter $Target
    $health = Invoke-JobsRunnerTool $flutter @('--version', '--machine') $Target
    Write-Host ('Flutter：' + $flutter)
    try { $version = $health | ConvertFrom-Json; Write-Host ('版本：' + $version.frameworkVersion) } catch { throw 'Flutter SDK 体检失败，请先运行 flutter doctor。' }
    $device = Select-JobsRunnerDevice $flutter $Target
    if ($null -eq $device) { return }
    $session = Start-JobsRunnerSession $Target $flutter $device $projectRoot
    Show-JobsRunnerLog $session
}

function Invoke-JobsFeature {
    param([string]$Target)
    Invoke-JobsFlutterRunAction -Target (Resolve-JobsTarget $Target)
}

Export-ModuleMember -Function Invoke-JobsFeature


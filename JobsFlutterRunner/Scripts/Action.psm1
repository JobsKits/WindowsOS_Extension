# Action.psm1 | JobsFlutterRunner
# Created by Jobs on 2026年10月20日，星期二.
# CMD 中选择设备和连接日志；Flutter 生命周期由独立后台宿主管理。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking
. (Join-Path $PSScriptRoot 'AndroidRuntime.ps1')
$script:RunnerSelectedSdk = $null

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

function Read-JobsRunnerInput {
    param([string]$Prompt)
    Write-Host ($Prompt + '：') -NoNewline
    $answer = [Console]::ReadLine()
    if ($null -eq $answer) { throw '输入已结束，停止操作。' }
    return $answer
}

function Select-JobsRunnerChoice {
    param([string]$Title, [string[]]$Items, [switch]$Back)
    if ($Items.Count -eq 0) { throw ('没有可选择的项目：' + $Title) }
    $fzf = Find-JobsExecutable 'fzf.exe' @('fzf')
    if (-not $fzf) { throw '缺少 fzf。请先安装或修复 fzf（winget install junegunn.fzf），再重新运行。' }
    $version = Invoke-JobsProcess $fzf @('--version') -TimeoutSeconds 10
    $help = Invoke-JobsProcess $fzf @('--help') -TimeoutSeconds 10
    if ($version.ExitCode -ne 0 -or $help.ExitCode -ne 0 -or $help.StdOut -notmatch '--expect') { throw 'fzf 体检失败或不支持返回键，请修复后重试。' }
    $labels = @()
    for ($index = 0; $index -lt $Items.Count; $index++) { $labels += ('{0}  {1}' -f ($index + 1), $Items[$index]) }
    $header = '↑/↓ 选择；输入筛选；Enter 确认；Esc 取消'
    $arguments = @('--no-multi', '--height=80%', '--layout=reverse', '--border', ('--prompt=' + $Title + '> '))
    if ($Back) { $header += '；← 返回上一层'; $arguments += '--expect=left' }
    $arguments += '--header=' + $header
    $previousEncoding = $OutputEncoding
    try {
        $OutputEncoding = New-Object Text.UTF8Encoding($false)
        $result = @($labels | & $fzf @arguments)
        $code = $LASTEXITCODE
    } finally { $OutputEncoding = $previousEncoding }
    # 即使过滤结果为空（退出码 1），也先处理显式返回键。
    if ($Back -and $result.Count -gt 0 -and $result[0] -ceq 'left') { return [pscustomobject]@{ Kind = 'Back'; Index = -1 } }
    if ($code -in @(1, 130)) { return $null }
    if ($code -ne 0) { throw ('fzf 选择失败，退出码 ' + $code) }
    $selected = @($result | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($selected.Count -ne 1 -or $selected[0] -notin $labels) { throw '选择器返回未知或空选择，未执行业务。' }
    return [pscustomobject]@{ Kind = 'Selected'; Index = [Array]::IndexOf($labels, $selected[0]) }
}

function Get-JobsRunnerAvds {
    param([string]$Emulator, [string]$Project)
    foreach ($line in ((Invoke-JobsRunnerTool $Emulator @('-list-avds') $Project) -split '\r?\n')) {
        if ($line -cmatch '^[a-zA-Z0-9_.-]+$') { $line }
    }
}

function New-JobsRunnerAndroidAvd {
    param([string]$Sdk, [string]$Project, [string[]]$Existing)
    Write-Host ('Android SDK：' + $Sdk + [Environment]::NewLine + '初始化会复用健康工具；缺失 / 损坏时从 Google 官方源补齐 Command-Line Tools、Emulator / ADB，并按需从 Adoptium 下载 Java 21。系统镜像可能数 GB。' + [Environment]::NewLine + '只影响选定 SDK、用户 Java / AVD 目录；不修改全局 PATH、代理或系统虚拟化设置。') -ForegroundColor Yellow
    if ((Read-JobsRunnerInput '回车准备初始化工具；非空取消').Length -gt 0) { return $null }
    $abi = Get-JobsAndroidArchitecture
    [void][IO.Directory]::CreateDirectory($Sdk)
    $java = Get-JobsAndroidJava
    $oldJava = $env:JAVA_HOME
    try {
        $env:JAVA_HOME = Split-Path -Parent (Split-Path -Parent $java)
        $tools = Get-JobsAndroidHealthyTools -Sdk $Sdk -Java $java
        Repair-JobsAndroidComponents -Sdk $Sdk -Java $java -Tools $tools
        # Emulator 缺失时首次无法枚举；工具补齐后再次检查，避免重复创建已有 AVD。
        if ($Existing.Count -eq 0) {
            $Existing = @(Get-JobsRunnerAvds (Join-Path $Sdk 'emulator/emulator.exe') $Project | Where-Object { $_ -cmatch '^[a-zA-Z0-9_.-]+$' })
            if ($Existing.Count -gt 0) {
                $existingChoice = Select-JobsRunnerChoice '工具已就绪，选择 Android AVD' ($Existing + @('创建新的 Android 模拟器')) -Back
                if ($null -eq $existingChoice -or $existingChoice.Kind -eq 'Back') { return $null }
                if ($existingChoice.Index -lt $Existing.Count) { return $Existing[$existingChoice.Index] }
            }
        }
        $devices = @(Get-JobsAndroidDevices (Invoke-JobsAndroidTool $java $tools 'avdmanager' @('list', 'device')))
        $installed = @(Get-JobsAndroidImages (Invoke-JobsAndroidTool $java $tools 'sdkmanager' @(('--sdk_root=' + $Sdk), '--list_installed')) $abi)
        $images = $installed
        if ($images.Count -eq 0) {
            Write-Host '尚无当前宿主可用系统镜像，查询 Google 官方稳定镜像清单：https://dl.google.com/android/repository/'
            $images = @(Get-JobsAndroidImages (Invoke-JobsAndroidTool $java $tools 'sdkmanager' @(('--sdk_root=' + $Sdk), '--list', '--channel=0')) $abi)
        }
        while ($true) {
            $deviceChoice = Select-JobsRunnerChoice '选择 Android 设备型号' $devices -Back
            if ($null -eq $deviceChoice -or $deviceChoice.Kind -eq 'Back') { return $null }
            $device = $devices[$deviceChoice.Index]
            $imageChoice = Select-JobsRunnerChoice '选择 Android 系统镜像' $images -Back
            if ($null -eq $imageChoice) { return $null }
            if ($imageChoice.Kind -eq 'Back') { continue }
            $image = $images[$imageChoice.Index]
            $avdHome = Get-JobsAndroidAvdHome
            $name = New-JobsAndroidAvdName $device $image $Existing $avdHome
            Write-Host ('创建：' + $name + [Environment]::NewLine + '型号：' + $device + [Environment]::NewLine + '系统镜像：' + $image + [Environment]::NewLine + 'AVD 目标：' + $avdHome)
            if ($image -notin $installed) { Write-Host ('将从 Google 官方 SDK 源下载选定镜像到 ' + $Sdk + '，可能数 GB；许可证由本人确认。') -ForegroundColor Yellow }
            if ((Read-JobsRunnerInput '回车创建并启动；非空取消').Length -gt 0) { return $null }
            if ($image -notin $installed) {
                Invoke-JobsAndroidTool $java $tools 'sdkmanager' @(('--sdk_root=' + $Sdk), '--licenses') -Interactive
                Invoke-JobsAndroidTool $java $tools 'sdkmanager' @(('--sdk_root=' + $Sdk), '--install', $image) -Interactive
                $verified = @(Get-JobsAndroidImages (Invoke-JobsAndroidTool $java $tools 'sdkmanager' @(('--sdk_root=' + $Sdk), '--list_installed')) $abi)
                if ($image -notin $verified) { throw '镜像安装后复检失败，未创建 AVD。' }
            }
            # 不使用 --force；同名或创建失败时停止，绝不覆盖已有 AVD。
            [void](Invoke-JobsAndroidTool $java $tools 'avdmanager' @('create', 'avd', '--name', $name, '--package', $image, '--device', $device) -InputText "no`n")
            $created = @(Get-JobsRunnerAvds (Join-Path $Sdk 'emulator/emulator.exe') $Project)
            if ($name -notin $created) { throw ('创建后未找到 AVD，保留现场并停止：' + $name) }
            Write-JobsLog ('Created Android AVD ' + $name)
            return $name
        }
    } finally { $env:JAVA_HOME = $oldJava }
}

function Start-JobsRunnerAndroid {
    param([string]$Flutter, [string]$Project)
    $sdk = Get-JobsAndroidSdk
    if (-not $env:ANDROID_HOME -and -not $env:ANDROID_SDK_ROOT) {
        $configured = Get-JobsRunnerAndroidEmulator
        if ($configured) { $sdk = Split-Path -Parent (Split-Path -Parent $configured) }
    }
    $oldHome = $env:ANDROID_HOME
    $oldRoot = $env:ANDROID_SDK_ROOT
    try {
        $env:ANDROID_HOME = $sdk
        $env:ANDROID_SDK_ROOT = $sdk
        $emulator = Join-Path $sdk 'emulator/emulator.exe'
        $existing = @()
        if (Test-Path -LiteralPath $emulator -PathType Leaf) { $existing = @(Get-JobsRunnerAvds $emulator $Project) }
        $name = $null
        if ($existing.Count -gt 0) {
            $choice = Select-JobsRunnerChoice '选择 Android AVD' ($existing + @('创建新的 Android 模拟器')) -Back
            if ($null -eq $choice -or $choice.Kind -eq 'Back') { return $null }
            if ($choice.Index -lt $existing.Count) { $name = $existing[$choice.Index] }
            else { $name = New-JobsRunnerAndroidAvd $sdk $Project $existing }
        } else {
            Write-Host '尚无 Android AVD，进入内置初始化流程。'
            $name = New-JobsRunnerAndroidAvd $sdk $Project $existing
        }
        if ($null -eq $name) { return $null }
        $serial = Start-JobsAndroidAvd $sdk $name
        $device = Wait-JobsRunnerAndroidDevice $Flutter $Project $serial
        $script:RunnerSelectedSdk = $sdk
        return $device
    } finally { $env:ANDROID_HOME = $oldHome; $env:ANDROID_SDK_ROOT = $oldRoot }
}

function Wait-JobsRunnerAndroidDevice {
    param([string]$Flutter, [string]$Project, [string]$Serial)
    for ($attempt = 0; $attempt -lt 6; $attempt++) {
        try {
            $devices = @(ConvertFrom-JobsRunnerList (Invoke-JobsRunnerTool $Flutter @('devices', '--machine') $Project 30))
            $selected = @(Get-JobsRunnerSupportedDevices $devices $Project | Where-Object { $_.id -ceq $Serial })
            if ($selected.Count -eq 1) { return [string]$selected[0].id }
        } catch { Write-Host ('Flutter 设备查询暂未就绪：' + $_.Exception.Message) -ForegroundColor Yellow }
        Write-Host ('Flutter 尚未发现所选 AVD（' + $Serial + '），正在重新加载……')
        if ($attempt -lt 5) { Start-Sleep -Seconds 2 }
    }
    throw ('AVD 已启动，但 Flutter 尚未识别 ' + $Serial + '。设备已保留，请检查 flutter doctor 后重新加载。')
}

function Select-JobsRunnerDevice {
    param([string]$Flutter, [string]$Project)
    $script:RunnerSelectedSdk = $null
    while ($true) {
        Write-Host '正在读取 Flutter 运行设备……'
        $devices = @()
        try { $devices = @(Get-JobsRunnerSupportedDevices @(ConvertFrom-JobsRunnerList (Invoke-JobsRunnerTool $Flutter @('devices', '--machine') $Project)) $Project) }
        catch { Write-Host ('设备查询暂不可用，可重新加载或初始化 Android 模拟器：' + $_.Exception.Message) -ForegroundColor Yellow }
        $choices = @()
        foreach ($device in $devices) { $choices += [pscustomobject]@{ Kind = 'Device'; Id = [string]$device.id; Name = ([string]$device.name + ' · ' + [string]$device.id) } }
        if ((Test-Path -LiteralPath (Join-Path $Project 'android') -PathType Container) -or (Test-Path -LiteralPath (Join-Path $Project '.android') -PathType Container)) {
            $choices += [pscustomobject]@{ Kind = 'Android'; Id = ''; Name = 'Android 模拟器（启动已有 / 缺失时初始化）' }
        }
        $choices += [pscustomobject]@{ Kind = 'Reload'; Id = ''; Name = '重新加载设备列表' }
        if ($devices.Count -eq 0) { Write-Host '暂无可用设备；可连接手机、选择 Android 模拟器或重新加载。' -ForegroundColor Yellow }
        $selection = Select-JobsRunnerChoice '选择 Flutter 运行设备' @($choices | ForEach-Object { $_.Name })
        if ($null -eq $selection) { return $null }
        $choice = $choices[$selection.Index]
        if ($choice.Kind -eq 'Device') { return $choice.Id }
        if ($choice.Kind -eq 'Android') {
            $device = Start-JobsRunnerAndroid $Flutter $Project
            if ($null -ne $device) { return $device }
        }
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
    Write-Host 'Jobs · 从终端运行 Flutter 项目（CMD）' -ForegroundColor Red
    Write-Host ('来源：' + $PSScriptRoot) -ForegroundColor Cyan
    Write-Host ('项目：' + $Target)
    Write-Host '设备选择后启动 flutter run --machine；运行日志进入 CMD 和本功能日志目录。'
    Write-Host 'Android 模拟器可启动已有 AVD；缺失时确认后补齐工具、选择型号与系统镜像并创建启动。'
    Write-Host '设备选择使用 fzf，上下键及输入筛选，← 返回上一层，Esc 取消。'
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
    $oldHome = $env:ANDROID_HOME
    $oldRoot = $env:ANDROID_SDK_ROOT
    try {
        # 后台宿主必须继承本次所选 AVD 的 SDK，避免旧环境冲突或 PATH SDK 丢失。
        if ($script:RunnerSelectedSdk) { $env:ANDROID_HOME = $script:RunnerSelectedSdk; $env:ANDROID_SDK_ROOT = $script:RunnerSelectedSdk }
        $session = Start-JobsRunnerSession $Target $flutter $device $projectRoot
        Show-JobsRunnerLog $session
    } finally { $env:ANDROID_HOME = $oldHome; $env:ANDROID_SDK_ROOT = $oldRoot }
}

function Invoke-JobsFeature {
    param([string]$Target)
    Invoke-JobsFlutterRunAction -Target (Resolve-JobsTarget $Target)
}

Export-ModuleMember -Function Invoke-JobsFeature


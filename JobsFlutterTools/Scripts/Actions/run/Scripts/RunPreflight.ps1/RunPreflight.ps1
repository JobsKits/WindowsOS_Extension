# RunPreflight.ps1 | JobsFlutterRunner
# Created by Jobs on 2026年11月10日，星期二.
# 本地体检只读；选中未就绪鸿蒙后，独立准备阶段补齐环境并严格复检。

function New-JobsRunnerPreflightStatus {
    param([string]$Name, [string]$State, [string]$Detail)
    return [pscustomobject]@{ Name = $Name; State = $State; Detail = $Detail }
}

function Invoke-JobsRunnerPrepareHarmony {
    param([string]$Flutter,[string]$Project,[string]$DiagnosticKey,[switch]$RefreshCompatible)
    . (Join-Path $PSScriptRoot 'PrepareHarmonyRun.ps1/PrepareHarmonyRun.ps1')
    return Invoke-JobsPrepareHarmonyPipeline $Flutter $Project $DiagnosticKey -RefreshCompatible:$RefreshCompatible
}

function Get-JobsRunnerTaskEnvironmentSnapshot {
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

function Restore-JobsRunnerTaskEnvironment {
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

function Get-JobsRunnerTaskEnvironment {
    return Get-JobsRunnerTaskEnvironmentSnapshot @('PATH','JAVA_HOME','TOOL_HOME','DEVECO_STUDIO_HOME','DEVECO_SDK_HOME','OHOS_SDK_HOME')
}

function Set-JobsRunnerTaskEnvironment {
    param([hashtable]$Environment)
    foreach($key in $Environment.Keys){[Environment]::SetEnvironmentVariable($key,[string]$Environment[$key],'Process')}
}

function Start-JobsRunnerHarmonyPreparation {
    param([string]$Flutter,[string]$Project,[string]$DiagnosticKey,[switch]$RefreshCompatible)
    $prepared=Invoke-JobsRunnerPrepareHarmony $Flutter $Project $DiagnosticKey -RefreshCompatible:$RefreshCompatible
    if($null-eq$prepared-or$prepared.DiagnosticKey-cne$DiagnosticKey-or[string]::IsNullOrWhiteSpace($prepared.DeviceId)-or$prepared.DevicePlatform-notmatch'^(ohos|openharmony)(?:-|$)') { throw '鸿蒙准备结果没有确认原设备，未改跑其它目标。' }
    Set-JobsRunnerTaskEnvironment $prepared.Environment
    $script:RunnerPreparedHarmony=$prepared
    $script:RunnerSelectedPlatform=$prepared.DevicePlatform
    return $prepared.DeviceId
}

function Get-JobsRunnerHdcExecutable {
    $candidates=@()
    foreach($root in @($env:OHOS_SDK_HOME,$env:DEVECO_SDK_HOME,$env:TOOL_HOME,$env:DEVECO_STUDIO_HOME)) {
        if(-not$root){continue}
        foreach($relative in @('toolchains/hdc.exe','default/openharmony/toolchains/hdc.exe','openharmony/toolchains/hdc.exe','sdk/default/openharmony/toolchains/hdc.exe','tools/hdc/hdc.exe')){$candidates+=Join-Path $root $relative}
    }
    # HDC发现独立于完整编译SDK；部分安装或多SDK并存也不能隐藏已连接设备。
    $roots=@()
    foreach($base in @($env:ProgramFiles,${env:ProgramFiles(x86)},$env:LOCALAPPDATA)) {
        if(-not$base){continue}
        foreach($relative in @('Huawei/DevEco Studio','Huawei/DevEcoStudio','DevEco Studio','Programs/Huawei/DevEco Studio')){$roots+=Join-Path $base $relative}
    }
    if($env:LOCALAPPDATA){
        $cache=Join-Path $env:LOCALAPPDATA 'Jobs/HarmonySimulator/tools'
        if([IO.Directory]::Exists($cache)) {
            try { $roots+=@(Get-ChildItem -LiteralPath $cache -Directory -Filter 'clt-*'|ForEach-Object{$_.FullName}) }
            catch [Management.Automation.PipelineStoppedException] { throw }
            catch { Write-Host ('部分HDC工具目录不可读取：'+$_.Exception.Message) -ForegroundColor Yellow }
        }
    }
    foreach($root in $roots){foreach($relative in @('sdk/default/openharmony/toolchains/hdc.exe','sdk/openharmony/toolchains/hdc.exe','tools/hdc/hdc.exe')){$candidates+=Join-Path $root $relative}}
    foreach($path in @($candidates|Select-Object -Unique)){if([IO.File]::Exists($path)){return $path}}
    return Find-JobsExecutable 'hdc.exe' @('hdc')
}

function Get-JobsRunnerUsbInventory {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { return }
    if (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue) {
        try { return @(Get-PnpDevice -PresentOnly -ErrorAction Stop | Select-Object FriendlyName, InstanceId, Status) } catch { }
    }
    # 仅查询本机当前存在的设备，避免把历史断开的记录当作已连接手机。
    return @(Get-CimInstance -ClassName Win32_PnPEntity -Filter 'Present=True' -OperationTimeoutSec 5 -ErrorAction Stop | Select-Object Name, PNPDeviceID, Present)
}

function ConvertFrom-JobsRunnerHarmonyUsb {
    param([object[]]$Devices)
    $rows = @()
    foreach ($device in $Devices) {
        if ($null -ne $device.PSObject.Properties['Present'] -and $device.Present -eq $false) { continue }
        $id = if ($null -ne $device.PSObject.Properties['InstanceId']) { [string]$device.InstanceId } elseif ($null -ne $device.PSObject.Properties['PNPDeviceID']) { [string]$device.PNPDeviceID } else { '' }
        $name = if ($null -ne $device.PSObject.Properties['FriendlyName']) { [string]$device.FriendlyName } elseif ($null -ne $device.PSObject.Properties['Name']) { [string]$device.Name } else { '' }
        if ($id -notmatch '(?i)^USB\\') { continue }
        # HDC 接口名或华为 HDC 专用 USB 产品号才是证据；厂商名/ADB/存储外设不够。
        if ($name -notmatch '(?i)(?:^|[\s(])HDC(?:(?:\s+USB)?\s*(?:Device|Interface|Driver|设备|接口)(?:\b|$)|\s*$)' -and $id -notmatch '(?i)VID_12D1&PID_1101(?:&|\\)') { continue }
        $hardware = if ($id -match '(?i)^USB\\(VID_[A-F0-9]{4}&PID_[A-F0-9]{4})') { $Matches[1].ToUpperInvariant() } else { $id }
        $rows += [pscustomobject]@{ Id=$id; Name=$name; Serial=($id -split '\\')[-1]; Hardware=$hardware; Interface=($id -match '(?i)&MI_[A-F0-9]{2}') }
    }
    foreach ($row in $rows) {
        if ($row.Interface -and @($rows | Where-Object { -not $_.Interface -and $_.Hardware -ceq $row.Hardware }).Count) { continue }
        $row
    }
}

function Get-JobsRunnerHarmonyDiagnostics {
    param([object[]]$Devices, [string]$Project, [hashtable]$Preflight)
    $runnable = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($device in $Devices) { [void]$runnable.Add([string]$device.id) }
    $targets = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $rows = @()
    $hdc = Get-JobsRunnerHdcExecutable
    $hdcFailure = $null
    if ($hdc) {
        try {
            $output = Invoke-JobsRunnerReadOnlyTool $hdc @('list', 'targets') $Project 8
            foreach ($line in ($output -split '\r?\n')) {
                $id = $line.Trim()
                $status=''
                if($id-match'(?i)^([A-Za-z0-9][A-Za-z0-9_.:@/-]*)\s+(unauthorized|offline|notready|unauth)\b'){$id=$Matches[1];$status=$Matches[2]}
                if($line-match'(?i)unauthorized|offline|notready|unauth|\[(?:fail|error)\]'){Write-Host ('HDC 状态：'+$line.Trim()+'；请解锁设备、确认本机调试授权后重新加载。') -ForegroundColor Yellow}
                if ($id -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_.:@/-]*$' -or $id -cin @('Empty','None','OK','Success','Fail','Unauthorized','Offline','NotReady','Unauth')) { continue }
                if (-not $targets.Add($id) -or $runnable.Contains($id)) { continue }
                $rows += [pscustomobject]@{ Kind='HarmonyDiagnostic'; Id=$id; Name=('鸿蒙设备（HDC）—已连接，环境未就绪 · '+$id); Detail=('HDC 已发现目标'+$(if($status){'，状态：'+$status}else{''})+'，但当前 Flutter 没有将它列为本工程可运行设备；请核对 SDK 支持、工程鸿蒙适配和手机调试授权。') }
            }
        } catch [Management.Automation.PipelineStoppedException] { throw }
        catch { $hdcFailure = $_.Exception.Message; Write-Host ('HDC 查询未完成：'+$hdcFailure+'；可重新加载设备列表。') -ForegroundColor Yellow }
    }
    try { $usb = @(ConvertFrom-JobsRunnerHarmonyUsb @(Get-JobsRunnerUsbInventory)) }
    catch [Management.Automation.PipelineStoppedException] { throw }
    catch { $usb=@(); Write-Host ('USB 设备查询未完成，可重新加载：'+$_.Exception.Message) -ForegroundColor Yellow }
    $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($device in $usb) {
        if (-not $seen.Add($device.Id) -or $runnable.Contains($device.Serial) -or $targets.Contains($device.Serial)) { continue }
        $reason = if (-not $hdc) { '电脑已识别 HDC USB 设备，但没有找到 hdc；请先准备 DevEco / OpenHarmony 工具链。' } elseif ($hdcFailure) { '电脑已识别 HDC USB 设备，但 HDC 查询未完成：'+$hdcFailure } else { '电脑已识别 HDC USB 设备，但 HDC 尚未返回可用目标；请解锁手机并确认本机 USB 调试授权。' }
        $rows += [pscustomobject]@{ Kind='HarmonyDiagnostic'; Id=$device.Id; Name='鸿蒙USB设备—已连接，环境未就绪'; Detail=($reason+' USB 接口：'+$device.Name) }
    }
    foreach ($row in $rows) {
        if (-not [IO.Directory]::Exists((Join-Path $Project 'ohos'))) { $row.Detail += ' 当前工程没有 ohos/ 平台，需要先完成鸿蒙适配。' }
        if ($Preflight -and $Preflight.ContainsKey('ohos') -and $Preflight.ohos.State -cne 'ready') { $row.Detail += ' 体检缺项：'+$Preflight.ohos.Detail }
        $row
    }
}

function Show-JobsRunnerHarmonyDiagnostic {
    param($Device)
    Write-Host $Device.Name -ForegroundColor Yellow
    Write-Host $Device.Detail
    Write-Host '选择此设备后将在当前运行流程准备兼容 SDK、工具链与项目依赖；不改选其它设备，不绕过缺失插件或官方许可。'
}

# 直接运行已存在的同源 Dart/snapshot，避开 Flutter shim 的自举获取入口。
function Invoke-JobsRunnerReadOnlyTool {
    param([string]$Executable, [string[]]$Arguments, [string]$Project, [int]$TimeoutSeconds = 90, [int[]]$AllowedExitCodes = @(0), [hashtable]$Environment = @{})
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Executable
    $start.Arguments = @($Arguments | ForEach-Object { Quote-JobsArgument $_ }) -join ' '
    if ([IO.Path]::GetExtension($Executable) -in @('.bat', '.cmd')) {
        if ($Executable -match '["\x00-\x1f]' -or @($Arguments | Where-Object { $_ -cnotmatch '^[A-Za-z0-9._/-]+$' }).Count) { throw '体检工具参数不合法。' }
        $start.FileName = Join-Path ([Environment]::GetFolderPath('System')) 'cmd.exe'
        $start.EnvironmentVariables['JOBS_RUN_PREFLIGHT_TOOL'] = $Executable
        $start.Arguments = '/d /v:off /s /c ""%JOBS_RUN_PREFLIGHT_TOOL%" ' + ($Arguments -join ' ') + '"'
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
    foreach ($key in $Environment.Keys) { $start.EnvironmentVariables[$key] = [string]$Environment[$key] }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    $begun = $false
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $nextNotice = 10
    try {
        if (-not $process.Start()) { throw '无法启动本地体检工具。' }
        $begun = $true
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        while (-not $process.WaitForExit(100)) {
            if ($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds) { throw '本地环境体检超时；未启动 Flutter 应用。' }
            if ($clock.Elapsed.TotalSeconds -ge $nextNotice) { Write-Host '本地环境体检仍在进行，等待工具返回完整结果…'; $nextNotice += 10 }
        }
        if (-not $stdout.Wait(5000) -or -not $stderr.Wait(5000)) { throw '本地体检输出未完整结束。' }
        $result = [pscustomobject]@{ ExitCode = $process.ExitCode; StdOut = $stdout.Result; StdErr = $stderr.Result }
    } finally {
        if ($begun -and -not $process.HasExited) {
            if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
                & (Join-Path ([Environment]::GetFolderPath('System')) 'taskkill.exe') /PID $process.Id /T /F 2>&1 | Out-Null
            } else {
                $method = $process.GetType().GetMethod('Kill', [type[]]@([bool]))
                if ($method) { [void]$method.Invoke($process, [object[]]@($true)) } else { $process.Kill() }
            }
        }
        $process.Dispose()
    }
    if ($result.ExitCode -in @(130,143,-1073741510)) { throw [OperationCanceledException]::new('本地工具操作已取消。') }
    if ($result.ExitCode -notin $AllowedExitCodes) { throw ('体检命令失败：' + [IO.Path]::GetFileName($Executable) + '，退出码 ' + $result.ExitCode + '；' + $result.StdErr) }
    return ([string]$result.StdOut + [Environment]::NewLine + [string]$result.StdErr).Trim()
}

function ConvertFrom-JobsRunnerDoctorScope {
    param([string]$Output)
    $result = $Output | ConvertFrom-Json -ErrorAction Stop
    if ($result.schemaVersion -ne 1 -or $result.complete -cne $true -or $null -eq $result.PSObject.Properties['validators'] -or $result.validators -isnot [array]) { throw '本地平台体检没有完整、有效的结构化结果。' }
    $sections = @{}
    foreach ($validator in $result.validators) {
        if ($validator.type -cnotin @('success', 'partial', 'missing', 'notAvailable', 'crash') -or [string]::IsNullOrWhiteSpace([string]$validator.title)) { throw '本地平台体检状态无效。' }
        $key = if ($validator.title -match '^(?:Android toolchain|Android SDK)') { 'android' }
            elseif ($validator.title -match '^(?:HarmonyOS|OpenHarmony|OHOS|Harmony)') { 'ohos' }
            elseif ($validator.title -match '^(?:Visual Studio|Windows Version)') { 'windows' }
            elseif ($validator.title -match '^Chrome\s') { 'web' }
            else { $null }
        if (-not $key) { continue }
        $healthy = $validator.type -ceq 'success'
        $text = [string]$validator.title + '：' + [string]$validator.statusInfo
        foreach ($message in $validator.messages) {
            if ($message.type -ceq 'error') { $healthy = $false }
            if (-not [string]::IsNullOrWhiteSpace([string]$message.message)) { $text += [Environment]::NewLine + [string]$message.message }
        }
        if ($sections.ContainsKey($key)) {
            $sections[$key].Healthy = $sections[$key].Healthy -and $healthy
            $sections[$key].Text += [Environment]::NewLine + $text
        } else { $sections[$key] = [pscustomobject]@{ Healthy = $healthy; Text = $text } }
    }
    return $sections
}

function Assert-JobsRunnerDoctorSection {
    param([hashtable]$Sections, [string]$Platform)
    if (-not $Sections.ContainsKey($Platform)) { throw ('Flutter doctor 未提供 ' + $Platform + ' 检查。') }
    if (-not $Sections[$Platform].Healthy) { throw $Sections[$Platform].Text }
}

function Get-JobsRunnerPreflightAndroidPaths {
    param([string]$DoctorText)
    $detected = $null
    if ($DoctorText -match '(?m)^Android SDK at ([^\r\n]+)') { $detected = $Matches[1].Trim() }
    if (Get-Command 'Get-JobsAndroidSdk' -ErrorAction SilentlyContinue) {
        $sdk = if ($detected) { $detected } else { Get-JobsAndroidSdk }
        return [pscustomobject]@{ Sdk = $sdk; Tools = (Get-JobsAndroidTools $sdk) }
    }
    # 聚合包已有随包桌面创建器；仅调用其定位函数，不运行创建/下载业务。
    $modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'SimulatorCreators/Android/Scripts/Action.psm1'
    $module = Import-Module $modulePath -PassThru -DisableNameChecking
    return & $module { param($Detected) $sdk = if ($Detected) { $Detected } else { Get-JobsAndroidSdk }; [pscustomobject]@{ Sdk = $sdk; Tools = (Get-JobsAndroidTools $sdk) } } $detected
}

function Assert-JobsRunnerProjectPackages {
    param([string]$Project, [switch]$Harmony)
    $path = Join-Path $Project '.dart_tool/package_config.json'
    if (-not [IO.File]::Exists($path)) { throw '缺少 .dart_tool/package_config.json；请先解析工程依赖。' }
    $config = [IO.File]::ReadAllText($path) | ConvertFrom-Json -ErrorAction Stop
    if ($config.configVersion -ne 2 -or @($config.packages).Count -eq 0) { throw '工程依赖索引无效。' }
    $baseUri = [Uri]::new([IO.Path]::GetFullPath($path))
    $unsupported = @()
    foreach ($package in $config.packages) {
        $uri = [Uri]::new($baseUri, [string]$package.rootUri)
        if (-not $uri.IsFile -or -not [IO.Directory]::Exists($uri.LocalPath)) { throw ('依赖路径不可用：' + $package.name) }
        if ($Harmony) {
            $spec = Join-Path $uri.LocalPath 'pubspec.yaml'
            if (-not [IO.File]::Exists($spec)) { throw ('依赖缺少 pubspec.yaml：' + $package.name) }
            $yaml = [IO.File]::ReadAllText($spec)
            # 与既有 Harmony 环境体检一致；缺少平台声明时不能宣称原生插件可编译。
            if ($yaml -match '(?m)^\s+plugin\s*:' -and $yaml -notmatch '(?m)^\s+ohos\s*:') { $unsupported += $package.name }
        }
    }
    if ($unsupported.Count) {
        throw ('原生插件尚未声明 ohos 支持：' + [Environment]::NewLine +
            (($unsupported | ForEach-Object { '- ' + $_ }) -join [Environment]::NewLine))
    }
}

function Get-JobsRunnerHarmonyRoot {
    $configured = if ($env:DEVECO_STUDIO_HOME) { $env:DEVECO_STUDIO_HOME } else { $env:TOOL_HOME }
    if ($configured) {
        if (-not [IO.Directory]::Exists($configured)) { throw ('指定的 DevEco / CLT 不存在：' + $configured) }
        return [IO.Path]::GetFullPath($configured)
    }
    $candidates = @()
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
        if (-not $base) { continue }
        foreach ($relative in @('Huawei/DevEco Studio', 'DevEco Studio', 'Programs/Huawei/DevEco Studio')) {
            $candidate = Join-Path $base $relative
            if ([IO.Directory]::Exists($candidate)) { $candidates += $candidate }
        }
    }
    if ($env:LOCALAPPDATA) {
        $base = Join-Path $env:LOCALAPPDATA 'Jobs/HarmonySimulator/tools'
        if ([IO.Directory]::Exists($base)) { $candidates += @(Get-ChildItem -LiteralPath $base -Directory | Where-Object { $_.Name -like 'clt-*' } | ForEach-Object { $_.FullName }) }
    }
    $usable = @($candidates | Select-Object -Unique | Where-Object { [IO.Directory]::Exists((Join-Path $_ 'sdk/default/openharmony')) })
    if ($usable.Count -ne 1) { throw ('找到 ' + $usable.Count + ' 套 DevEco / CLT；请先准备工具，或用 TOOL_HOME / DEVECO_STUDIO_HOME 指定本次工具目录。') }
    return $usable[0]
}

function Assert-JobsRunnerHarmonyTools {
    param([string]$Flutter, [string]$Project, [string]$Dart, [string]$Snapshot, [hashtable]$Sections)
    $help = Invoke-JobsRunnerReadOnlyTool $Dart @($Snapshot, '--no-version-check', '--suppress-analytics', 'build', '-h') $Project 30
    if ($help -notmatch '(?m)^\s*hap\s') { throw '当前工程 FVM SDK 未提供 HAP 构建能力；普通 Flutter 无法识别纯鸿蒙设备。请先使用“安装/切换Flutter@OpenHarmony SDK”。' }
    if ($Sections.ContainsKey('ohos')) { Assert-JobsRunnerDoctorSection $Sections 'ohos' }
    $root = Get-JobsRunnerHarmonyRoot
    $sdk = if ($env:DEVECO_SDK_HOME) { $env:DEVECO_SDK_HOME } else { Join-Path $root 'sdk' }
    $ohos = if ($env:OHOS_SDK_HOME) { $env:OHOS_SDK_HOME } else { Join-Path $sdk 'default/openharmony' }
    foreach ($component in @('ets', 'native', 'toolchains')) {
        if (-not [IO.Directory]::Exists((Join-Path $ohos $component))) { throw ('Harmony SDK 缺少 ' + $component + '：' + $ohos) }
    }
    foreach ($tool in @(@('node.exe', '--version'), @('ohpm.bat', '--version'), @('hvigorw.bat', '--version'), @('hdc.exe', '-v'), @('java.exe', '-version'))) {
        $candidates = @()
        if ($tool[0] -ceq 'java.exe' -and $env:JAVA_HOME) { $candidates += Join-Path $env:JAVA_HOME 'bin/java.exe' }
        if ($tool[0] -ceq 'hdc.exe') { $candidates += Join-Path $ohos 'toolchains/hdc.exe' }
        foreach ($relative in @('', 'bin', 'node', 'node/bin', 'tools/node', 'tools/node/bin', 'ohpm/bin', 'hvigor/bin', 'tools/ohpm/bin', 'tools/hvigor/bin', 'jbr/bin')) { $candidates += Join-Path (Join-Path $root $relative) $tool[0] }
        $executable = @($candidates | Where-Object { [IO.File]::Exists($_) } | Select-Object -First 1)
        if ($executable.Count) { $executable = $executable[0] } else { $executable = Find-JobsExecutable $tool[0] }
        if (-not $executable) { throw ('缺少鸿蒙配套工具 ' + $tool[0] + '；请先通过“一键配置 Flutter 项目”准备 OpenHarmony 工具链。') }
        $output = Invoke-JobsRunnerReadOnlyTool $executable @($tool[1]) $Project 30
        if ([string]::IsNullOrWhiteSpace($output)) { throw ($tool[0] + ' 未返回有效版本。') }
    }
    foreach ($name in @('ohos/build-profile.json5', 'ohos/oh-package.json5', 'ohos/AppScope/app.json5')) {
        if (-not [IO.File]::Exists((Join-Path $Project $name))) { throw ('工程缺少 ' + $name + '；需要先适配鸿蒙，体检不会生成平台目录。') }
    }
    if (-not [IO.File]::Exists((Join-Path $Project 'ohos/hvigorfile.ts')) -and -not [IO.File]::Exists((Join-Path $Project 'ohos/hvigorfile.js'))) { throw '工程缺少 ohos/hvigorfile。' }
    Assert-JobsRunnerProjectPackages $Project -Harmony
}

function Get-JobsRunnerPreflight {
    param([string]$Flutter, [string]$Project)
    Write-Host '正在检查本地 SDK、工程依赖和各平台工具链…' -ForegroundColor Cyan
    $report = @{}
    $report.ios = New-JobsRunnerPreflightStatus 'iOS' 'not-applicable' 'Windows 不支持本地 iOS 编译运行，请在 macOS 检查。'
    $sections = @{}
    $sdk = Split-Path -Parent (Split-Path -Parent $Flutter)
    $dart = Join-Path $sdk 'bin/cache/dart-sdk/bin/dart.exe'
    $snapshot = Join-Path $sdk 'bin/cache/flutter_tools.snapshot'
    try {
        foreach ($file in @($dart, $snapshot)) { if (-not [IO.File]::Exists($file)) { throw ('SDK 公共组件未就绪：' + $file + '；请先完成 SDK 准备。') } }
        $versionText = Invoke-JobsRunnerReadOnlyTool $dart @($snapshot, '--no-version-check', '--suppress-analytics', '--version', '--machine') $Project 30
        $version = ConvertFrom-JobsSdkMachineOutput $versionText
        if ([string]::IsNullOrWhiteSpace([string]$version.frameworkVersion)) { throw '当前 SDK 未返回有效 Flutter 版本。' }
        $scope = Join-Path $PSScriptRoot 'DoctorScope.dart'
        $packages = Join-Path $sdk 'packages/flutter_tools/.dart_tool/package_config.json'
        foreach ($file in @($scope, $packages)) { if (-not [IO.File]::Exists($file)) { throw ('本地体检依赖未就绪：' + $file) } }
        # 只执行官方本地工具链 validator，联网及设备发现不是环境健康的前提。
        $environment = @{ FLUTTER_ROOT = $sdk; PATH = ((Join-Path $sdk 'bin') + [IO.Path]::PathSeparator + $env:PATH) }
        $output = Invoke-JobsRunnerReadOnlyTool $dart @('--disable-dart-dev', ('--packages=' + $packages), $scope, 'all') $Project 60 -AllowedExitCodes @(0, 1) -Environment $environment
        $sections = ConvertFrom-JobsRunnerDoctorScope $output
        $context = Get-JobsRunnerSdkContext $Flutter $Project
        if ($context.DeclaredFlutter -match '(\d+\.\d+\.\d+)') {
            $expected = $Matches[1]
            if (-not $context.FlutterVersion -or $context.FlutterVersion -notmatch ('^v?' + [regex]::Escape($expected) + '(?:$|[-+])') -or $version.frameworkVersion -notmatch ('^v?' + [regex]::Escape($expected) + '(?:$|[-+])')) { throw ('FVM 声明 ' + $context.DeclaredFlutter + '，本地 SDK 版本 ' + $context.FlutterVersion + '；请先核对绑定和实际运行版本。') }
        }
        Assert-JobsRunnerProjectPackages $Project
        $report.base = New-JobsRunnerPreflightStatus 'Flutter / 工程依赖' 'ready' ('Flutter ' + $version.frameworkVersion + '；依赖索引与本地路径有效。')
    } catch { $report.base = New-JobsRunnerPreflightStatus 'Flutter / 工程依赖' 'failed' $_.Exception.Message }
    foreach ($platform in @('android', 'ohos', 'windows', 'web')) {
        $name = @{ android = 'Android'; ohos = '鸿蒙'; windows = 'Windows'; web = 'Web' }[$platform]
        try {
            if ($report.base.State -cne 'ready') { throw '基础 SDK / 工程依赖未通过，平台检查无法判定健康。' }
            if ($platform -ceq 'ohos') { Assert-JobsRunnerHarmonyTools $Flutter $Project $dart $snapshot $sections }
            else {
                $directory = Join-Path $Project $platform
                if ($platform -ceq 'android' -and -not [IO.Directory]::Exists($directory)) { $directory = Join-Path $Project '.android' }
                if (-not [IO.Directory]::Exists($directory)) { throw ('当前工程没有 ' + $platform + ' 平台目录。') }
                Assert-JobsRunnerDoctorSection $sections $platform
                if ($platform -ceq 'android') {
                    $android = Get-JobsRunnerPreflightAndroidPaths $sections.android.Text
                    if (-not [IO.File]::Exists((Join-Path $android.Sdk 'platform-tools/adb.exe'))) { throw ('Android SDK 缺少 adb：' + $android.Sdk) }
                    if (-not $android.Tools) { throw 'Android SDK 缺少现有 Command-Line Tools。' }
                    if (-not [IO.File]::Exists((Join-Path $directory 'gradlew.bat'))) { throw '工程缺少 Android Gradle wrapper。' }
                }
            }
            $report[$platform] = New-JobsRunnerPreflightStatus $name 'ready' 'SDK、工具链和工程平台检查通过；实际构建与签名仍以运行结果为准。'
        } catch { $report[$platform] = New-JobsRunnerPreflightStatus $name 'failed' $_.Exception.Message }
    }
    return $report
}

function Write-JobsRunnerPreflight {
    param([hashtable]$Report)
    Write-Host '运行前环境体检（只检查，不安装、切换 SDK 或生成平台文件）' -ForegroundColor Cyan
    foreach ($key in @('base', 'ios', 'android', 'ohos', 'windows', 'web')) {
        $entry = $Report[$key]
        $label = if ($entry.State -ceq 'ready') { '通过' } elseif ($entry.State -ceq 'not-applicable') { '不适用' } else { '未通过' }
        $color = if ($entry.State -ceq 'ready') { 'Green' } elseif ($entry.State -ceq 'not-applicable') { 'DarkGray' } else { 'Yellow' }
        Write-Host ('[' + $label + '] ' + $entry.Name + '：' + $entry.Detail) -ForegroundColor $color
    }
}

function Assert-JobsRunnerPreflight {
    param([hashtable]$Report, [string]$Platform)
    if ($PSBoundParameters.ContainsKey('Platform') -and [string]::IsNullOrWhiteSpace($Platform)) { throw '所选设备缺少有效平台信息；未启动 Flutter 应用。' }
    $target = if ($Platform -match '^android(?:-|$)') { 'android' } elseif ($Platform -match '^(?:ohos|openharmony)(?:-|$)') { 'ohos' } elseif ($Platform -like 'windows-*') { 'windows' } elseif ($Platform -ceq 'web-javascript') { 'web' } elseif ($Platform) { throw ('无法识别所选平台：' + $Platform) } else { $null }
    $required = @('base')
    if ($target) { $required += $target }
    foreach ($key in @($required | Select-Object -Unique)) {
        if (-not $Report.ContainsKey($key) -or $Report[$key].State -cne 'ready') {
            $reason = if ($Report.ContainsKey($key)) { $Report[$key].Detail } else { '缺少有效检查结果。' }
            throw ('运行前体检未通过（' + $key + '）：' + $reason + '；未启动 Flutter 应用。')
        }
    }
}

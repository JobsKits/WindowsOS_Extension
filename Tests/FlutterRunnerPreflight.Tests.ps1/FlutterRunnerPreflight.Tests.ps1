# FlutterRunnerPreflight.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年11月10日，星期二.
# 临时 SDK / 工程与假工具；不运行用户工程、不联网、不注册扩展。
[CmdletBinding()]
param()

function Assert-Preflight {
    param([bool]$Value, [string]$Message)
    if (-not $Value) { throw ('FAIL: ' + $Message) }
    $script:checks++
}

function Invoke-PreflightTests {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ('JobsRunnerPreflight-' + [guid]::NewGuid().ToString('N'))
    $script:checks = 0
    $oldToolHome = $env:TOOL_HOME
    $oldStudioHome = $env:DEVECO_STUDIO_HOME
    $oldAndroidHome = $env:ANDROID_HOME
    $oldAndroidRoot = $env:ANDROID_SDK_ROOT
    try {
        $project = Join-Path $temporary '工程 中文 & 100%'
        $sdk = Join-Path $temporary 'sdk'
        $android = Join-Path $temporary 'android'
        $harmony = Join-Path $temporary 'deveco'
        foreach ($directory in @($project, (Join-Path $project '.dart_tool'), (Join-Path $project 'android'), (Join-Path $project 'windows'), (Join-Path $project 'web'), (Join-Path $project 'ohos/AppScope'), (Join-Path $sdk 'bin/cache/dart-sdk/bin'), (Join-Path $sdk 'packages/flutter_tools/.dart_tool'), (Join-Path $android 'platform-tools'), (Join-Path $harmony 'sdk/default/openharmony/ets'), (Join-Path $harmony 'sdk/default/openharmony/native'), (Join-Path $harmony 'sdk/default/openharmony/toolchains'))) { [void][IO.Directory]::CreateDirectory($directory) }
        foreach ($path in @((Join-Path $sdk 'bin/flutter.bat'), (Join-Path $sdk 'bin/cache/dart-sdk/bin/dart.exe'), (Join-Path $sdk 'bin/cache/flutter_tools.snapshot'), (Join-Path $sdk 'packages/flutter_tools/.dart_tool/package_config.json'), (Join-Path $project 'android/gradlew.bat'), (Join-Path $android 'platform-tools/adb.exe'), (Join-Path $project 'ohos/build-profile.json5'), (Join-Path $project 'ohos/oh-package.json5'), (Join-Path $project 'ohos/AppScope/app.json5'), (Join-Path $project 'ohos/hvigorfile.ts'))) { [IO.File]::WriteAllText($path, 'fixture') }
        [IO.File]::WriteAllText((Join-Path $project 'pubspec.yaml'), "name: fixture`ndependencies:`n  flutter:`n    sdk: flutter`n")
        [IO.File]::WriteAllText((Join-Path $project '.dart_tool/package_config.json'), '{"configVersion":2,"packages":[{"name":"fixture","rootUri":"../"}]}')
        foreach ($name in @('node.exe', 'ohpm.bat', 'hvigorw.bat', 'hdc.exe', 'java.exe')) { [IO.File]::WriteAllText((Join-Path $harmony $name), 'fixture') }
        $tools = Join-Path $android 'cmdline-tools/latest/lib'
        [void][IO.Directory]::CreateDirectory($tools)
        foreach ($name in @('sdkmanager-classpath.jar', 'avdmanager-classpath.jar')) { [IO.File]::WriteAllText((Join-Path $tools $name), 'fixture') }
        $env:ANDROID_HOME = $android
        $env:ANDROID_SDK_ROOT = $android
        $healthyDoctor = "[✓] Flutter (Channel stable, 3.47.8)`n[✓] Android toolchain - develop for Android devices`n[!] Xcode - unavailable on Windows`n[✓] Visual Studio - develop Windows apps`n[✓] Chrome - develop for web`n[!] Connected device (no devices available)"
        $healthyScope = '{"schemaVersion":1,"complete":true,"validators":[{"title":"Android toolchain - develop for Android devices","type":"success","statusInfo":"fixture","messages":[]},{"title":"Visual Studio - develop Windows apps","type":"success","statusInfo":"fixture","messages":[]},{"title":"Chrome - develop for web","type":"success","statusInfo":"fixture","messages":[]}]}'
        foreach ($relative in @('JobsFlutterRunner/Scripts/Action.psm1', 'JobsFlutterTools/Scripts/Actions/run/Scripts/Action.psm1')) {
            $module = Import-Module (Join-Path $root $relative) -Force -PassThru -DisableNameChecking
            $paths = &$module { Get-JobsRunnerPreflightAndroidPaths }
            Assert-Preflight ($paths.Sdk -ceq $android -and $paths.Tools -ceq (Split-Path -Parent $tools)) '复用现有Android定位器且不进入修复或创建流程'
            if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
                $value = &$module { param($Project) Invoke-JobsRunnerReadOnlyTool '/usr/bin/printf' @('preflight-value') $Project 3 } $project
                Assert-Preflight ($value -ceq 'preflight-value') '真实隔离子进程完整捕获输出，不依赖Flutter或下载器'
                $failed = $false
                try { &$module { param($Project) Invoke-JobsRunnerReadOnlyTool '/usr/bin/false' @() $Project 3 } $project } catch { $failed = $true }
                Assert-Preflight $failed '真实子进程失败码不能判作通过'
            }
            & $module {
                param($Doctor, $Android, $Harmony)
                $script:Doctor = $Doctor
                $script:Android = $Android
                $script:Harmony = $Harmony
                $script:HasHap = $true
                $script:PreflightCalls = [Collections.Generic.List[string]]::new()
                function script:Invoke-JobsRunnerReadOnlyTool {
                    param($Executable, $Arguments)
                    $script:PreflightCalls.Add(($Arguments -join ' '))
                    if (@($Arguments | Where-Object { $_ -match 'DoctorScope\.dart$' }).Count) { return $script:Doctor }
                    if ($Arguments -contains '--machine') { return '{"frameworkVersion":"3.47.8","dartSdkVersion":"3.13.7"}' }
                    if ($Arguments -contains 'build') { if ($script:HasHap) { return "Available subcommands:`n  hap  Build Harmony application" }; return 'Only apk and ios build commands' }
                    return 'fixture-version'
                }
                function script:Get-JobsRunnerSdkContext { return [pscustomobject]@{ DeclaredFlutter = '3.47.8'; FlutterVersion = '3.47.8' } }
                function script:Get-JobsRunnerPreflightAndroidPaths { return [pscustomobject]@{ Sdk = $script:Android; Tools = 'existing-cmdline-tools' } }
                function script:Get-JobsRunnerHarmonyRoot { return $script:Harmony }
                function script:Invoke-JobsSdkAcquireProcess { throw '检查禁止获取 SDK' }
            } $healthyScope $android $harmony
            $report = & $module { param($Flutter, $Project) Get-JobsRunnerPreflight $Flutter $Project } (Join-Path $sdk 'bin/flutter.bat') $project
            Assert-Preflight ($report.base.State -ceq 'ready' -and $report.android.State -ceq 'ready' -and $report.ohos.State -ceq 'ready') ($relative + ' 三端检查及公共环境完整通过')
            Assert-Preflight ($report.ios.State -ceq 'not-applicable') 'Windows明确显示iOS不适用'
            $failed = $false
            try { & $module { param($Output) ConvertFrom-JobsRunnerDoctorScope $Output } ('[   +2 ms] ' + $healthyScope) } catch { $failed = $true }
            Assert-Preflight $failed '结构化体检拒绝带verbose时间前缀的畸形JSON，不凭残余正文放行'
            & $module { param($Report) Assert-JobsRunnerPreflight $Report 'android' } $report
            Assert-Preflight ((@(& $module { $script:PreflightCalls.ToArray() }) -join '|') -notmatch '(?:precache|pub get|flutter run|install|create)') '只读检查未调用安装、缓存获取、生成或运行'

            [IO.File]::Move((Join-Path $harmony 'hdc.exe'), (Join-Path $harmony 'hdc.exe.saved'))
            & $module { function script:Find-JobsExecutable { return $null } }
            $missingHdc = & $module { param($Flutter, $Project) Get-JobsRunnerPreflight $Flutter $Project } (Join-Path $sdk 'bin/flutter.bat') $project
            Assert-Preflight ($missingHdc.ohos.State -ceq 'failed' -and $missingHdc.ohos.Detail -match 'hdc') '缺少HDC单独显示鸿蒙失败而非设备列表消失'
            [IO.File]::Move((Join-Path $harmony 'hdc.exe.saved'), (Join-Path $harmony 'hdc.exe'))
            [IO.File]::Move((Join-Path $project 'ohos/AppScope/app.json5'), (Join-Path $project 'ohos/AppScope/app.json5.saved'))
            $missingProject = & $module { param($Flutter, $Project) Get-JobsRunnerPreflight $Flutter $Project } (Join-Path $sdk 'bin/flutter.bat') $project
            Assert-Preflight ($missingProject.ohos.State -ceq 'failed' -and $missingProject.ohos.Detail -match 'app.json5') '缺少鸿蒙工程清单不通过且不生成平台'
            [IO.File]::Move((Join-Path $project 'ohos/AppScope/app.json5.saved'), (Join-Path $project 'ohos/AppScope/app.json5'))
            $specPath = Join-Path $project 'pubspec.yaml'
            $originalSpec = [IO.File]::ReadAllText($specPath)
            [IO.File]::WriteAllText($specPath, $originalSpec + "flutter:`n  plugin:`n    platforms:`n      android:`n        package: fixture`n")
            $missingPlugin = & $module { param($Flutter, $Project) Get-JobsRunnerPreflight $Flutter $Project } (Join-Path $sdk 'bin/flutter.bat') $project
            Assert-Preflight ($missingPlugin.ohos.State -ceq 'failed' -and $missingPlugin.ohos.Detail -match '原生插件') '原生插件没有ohos声明拒绝鸿蒙运行'
            [IO.File]::WriteAllText($specPath, $originalSpec)
            & $module { $script:HasHap = $false }
            $ordinarySdk = & $module { param($Flutter, $Project) Get-JobsRunnerPreflight $Flutter $Project } (Join-Path $sdk 'bin/flutter.bat') $project
            Assert-Preflight ($ordinarySdk.android.State -ceq 'ready' -and $ordinarySdk.ohos.State -ceq 'failed' -and $ordinarySdk.ohos.Detail -match 'HAP') '普通Flutter仍显示鸿蒙HAP能力缺失，Android保持可运行'
            & $module { $script:HasHap = $true }

            $report.ohos.State = 'failed'
            $report.ohos.Detail = '缺少 HDC / ohos 工程'
            & $module { param($Report) Assert-JobsRunnerPreflight $Report 'android' } $report
            Assert-Preflight $true '鸿蒙未就绪不阻断健康Android目标'
            $failed = $false
            try { & $module { param($Report) Assert-JobsRunnerPreflight $Report 'ohos-arm64' } $report } catch { $failed = $_.Exception.Message -match '缺少 HDC' }
            Assert-Preflight $failed '选择未健康鸿蒙目标明确阻断'
            $failed = $false
            try { & $module { param($Report) Assert-JobsRunnerPreflight $Report '' } $report } catch { $failed = $true }
            Assert-Preflight $failed '设备未声明平台时拒绝运行'

            & $module { $script:Doctor = '[!] Android toolchain - no license'; }
            $report = & $module { param($Flutter, $Project) Get-JobsRunnerPreflight $Flutter $Project } (Join-Path $sdk 'bin/flutter.bat') $project
            Assert-Preflight ($report.base.State -ceq 'failed') '畸形doctor输出无法宣称基础环境健康'
            & $module { param($Doctor) $script:Doctor = $Doctor.Replace('"type":"success"', '"type":"partial"') } $healthyScope
            $report = & $module { param($Flutter, $Project) Get-JobsRunnerPreflight $Flutter $Project } (Join-Path $sdk 'bin/flutter.bat') $project
            Assert-Preflight ($report.base.State -ceq 'ready' -and $report.android.State -ceq 'failed') 'doctor退出成功但平台警告仍失败'
            $failed = $false
            try { & $module { param($Report) Assert-JobsRunnerPreflight $Report 'android' } $report } catch { $failed = $true }
            Assert-Preflight $failed '警告平台无法进入flutter run'

            & $module { param($Doctor) $script:Doctor = $Doctor; function script:Get-JobsRunnerSdkContext { return [pscustomobject]@{ DeclaredFlutter='3.47.8'; FlutterVersion='3.41.9+ohos-1.0.2' } } } $healthyScope
            $report = & $module { param($Flutter, $Project) Get-JobsRunnerPreflight $Flutter $Project } (Join-Path $sdk 'bin/flutter.bat') $project
            Assert-Preflight ($report.base.State -ceq 'failed' -and $report.base.Detail -match 'FVM 声明') 'SDK与工程声明不匹配明确失败'
            & $module { function script:Get-JobsRunnerSdkContext { return [pscustomobject]@{ DeclaredFlutter='3.47.8'; FlutterVersion='3.47.8' } }; function script:Invoke-JobsRunnerReadOnlyTool { throw 'fixture timeout' } }
            $report = & $module { param($Flutter, $Project) Get-JobsRunnerPreflight $Flutter $Project } (Join-Path $sdk 'bin/flutter.bat') $project
            Assert-Preflight ($report.base.State -ceq 'failed' -and $report.base.Detail -match 'timeout') '命令超时或执行失败保持失败状态'
            Remove-Module $module

            # 保留真实运行编排与门禁，仅替代边界上的 SDK / 设备 / 宿主。
            foreach ($scenario in @('pass', 'base-fail', 'target-fail', 'cancel')) {
                $module = Import-Module (Join-Path $root $relative) -Force -PassThru -DisableNameChecking
                & $module {
                    param($Scenario)
                    $script:Scenario = $Scenario
                    $script:Checks = 0; $script:Starts = 0; $script:Precache = 0; $script:Selections = 0; $script:Discovery = 0
                    function script:Assert-JobsFlutterProject { }
                    function script:Get-JobsRunnerProjectRoot { return 'fixture-runs' }
                    function script:Get-JobsRunnerSession { return $null }
                    function script:Get-JobsRunnerFlutter { return 'fixture-flutter' }
                    function script:Invoke-JobsRunnerTool { return '{"frameworkVersion":"fixture"}' }
                    function script:Initialize-JobsRunnerDiscoverySdk { $script:Discovery++ }
                    function script:Get-JobsRunnerPreflight {
                        $script:Checks++
                        $base = if ($script:Scenario -ceq 'base-fail') { 'failed' } else { 'ready' }
                        $android = if ($script:Scenario -ceq 'target-fail' -and $script:Checks -gt 1) { 'failed' } else { 'ready' }
                        return @{ base = (New-JobsRunnerPreflightStatus 'Flutter' $base 'fixture'); android = (New-JobsRunnerPreflightStatus 'Android' $android 'fixture'); ohos = (New-JobsRunnerPreflightStatus '鸿蒙' 'failed' '缺少 HDC') }
                    }
                    function script:Write-JobsRunnerPreflight { }
                    function script:Select-JobsRunnerDevice { $script:Selections++; if ($script:Scenario -ceq 'cancel') { return $null }; $script:RunnerSelectedPlatform = 'android'; return 'phone-1' }
                    function script:Initialize-JobsRunnerPlatformSdk { $script:Precache++ }
                    function script:Start-JobsRunnerSession { $script:Starts++; return 'fixture-session' }
                    function script:Show-JobsRunnerLog { }
                } $scenario
                $failed = $false
                try { & $module { param($Project) Invoke-JobsFlutterRunAction $Project } $project } catch { $failed = $true }
                $counts = & $module { @($script:Starts, $script:Precache, $script:Selections, $script:Checks, $script:Discovery) }
                Assert-Preflight ($counts[4] -eq 1) '保留独立SDK准备流程'
                if ($scenario -ceq 'pass') { Assert-Preflight (-not $failed -and $counts[0] -eq 1 -and $counts[1] -eq 1 -and $counts[3] -eq 2) '健康目标检查两次，缓存准备与应用启动各一次' }
                elseif ($scenario -ceq 'base-fail') { Assert-Preflight ($failed -and $counts[0] -eq 0 -and $counts[1] -eq 0 -and $counts[2] -eq 0) '基础体检失败时不枚举选择、不准备目标、不启动应用' }
                elseif ($scenario -ceq 'target-fail') { Assert-Preflight ($failed -and $counts[0] -eq 0 -and $counts[1] -eq 0) '目标复检失败时不获取目标缓存、不启动应用' }
                else { Assert-Preflight (-not $failed -and $counts[0] -eq 0 -and $counts[1] -eq 0 -and $counts[3] -eq 1) '取消后不复检、不准备目标、不启动应用' }
                Remove-Module $module
            }
        }
        foreach ($relative in @('JobsFlutterRunner/Scripts/Action.psm1', 'JobsFlutterTools/Scripts/Actions/run/Scripts/Action.psm1')) {
            $module=Import-Module (Join-Path $root $relative) -Force -PassThru -DisableNameChecking
            $usb=@(
                [pscustomobject]@{FriendlyName='HDC Device';InstanceId='USB\VID_12D1&PID_1101\phone-ready'},
                [pscustomobject]@{FriendlyName='HDC Interface';InstanceId='USB\VID_12D1&PID_1101&MI_00\7&generated'},
                [pscustomobject]@{FriendlyName='HUAWEI Keyboard';InstanceId='USB\VID_12D1&PID_9999\keyboard'},
                [pscustomobject]@{FriendlyName='HDC Keyboard';InstanceId='USB\VID_1234&PID_9999\other-keyboard'},
                [pscustomobject]@{FriendlyName='HUAWEI ADB Interface';InstanceId='USB\VID_12D1&PID_107E\android-phone'},
                [pscustomobject]@{FriendlyName='HDC Controller';InstanceId='PCI\VID_1234&PID_1101\controller'},
                [pscustomobject]@{FriendlyName='HDC Device';InstanceId='USB\VID_12D1&PID_1101\old-phone';Present=$false}
            )
            $filtered=@(&$module {param($Usb) ConvertFrom-JobsRunnerHarmonyUsb $Usb} $usb)
            Assert-Preflight ($filtered.Count-eq1-and$filtered[0].Serial-ceq'phone-ready') 'USB识别排除普通华为外设、ADB、非USB与断开记录，并合并HDC父子接口'
            &$module {
                param($Usb)
                $script:UsbFixture=$Usb;$script:HdcFixture='fixture-hdc';$script:TargetText="phone-ready`nphone-unready`n[Empty]`nphone-unready"
                function script:Get-JobsRunnerHdcExecutable {return $script:HdcFixture}
                function script:Get-JobsRunnerUsbInventory {return $script:UsbFixture}
                function script:Invoke-JobsRunnerReadOnlyTool {return $script:TargetText}
            } $usb
            $runnable=@([pscustomobject]@{id='phone-ready';targetPlatform='ohos-arm64'})
            $rows=@(&$module {param($Devices,$Project) Get-JobsRunnerHarmonyDiagnostics $Devices $Project} $runnable $project)
            Assert-Preflight ($rows.Count-eq1-and$rows[0].Id-ceq'phone-unready'-and$rows[0].Kind-ceq'HarmonyDiagnostic') 'HDC目标去重可运行Flutter设备并排除空清单与重复ID'
            &$module {$script:TargetText='127.0.0.1:5555';$script:UsbFixture=@([pscustomobject]@{Name='HDC Device';PNPDeviceID='USB\VID_12D1&PID_1101&MI_00\7&untrusted';Present=$true})}
            $rows=@(&$module {param($Project) Get-JobsRunnerHarmonyDiagnostics -Devices @([pscustomobject]@{id='127.0.0.1:5555'}) -Project $Project} $project)
            Assert-Preflight ($rows.Count-eq1-and$rows[0].Name-ceq'鸿蒙USB设备—已连接，环境未就绪') '其它可运行HDC模拟器不能掩盖尚未映射的USB真机，兼容CIM设备字段'
            &$module {param($Usb) $script:UsbFixture=$Usb} $usb
            $noOhos=Join-Path $temporary 'no-ohos';[void][IO.Directory]::CreateDirectory($noOhos)
            &$module {$script:HdcFixture=$null}
            $rows=@(&$module {param($Project) Get-JobsRunnerHarmonyDiagnostics -Devices @() -Project $Project -Preflight @{ohos=@{State='failed';Detail='缺少HAP支持'}}} $noOhos)
            Assert-Preflight ($rows.Count-eq1-and$rows[0].Name-ceq'鸿蒙USB设备—已连接，环境未就绪') '无HDC工具时仍以原生USB证据显示已连接鸿蒙'
            Assert-Preflight ($rows[0].Detail-match'没有找到 hdc'-and$rows[0].Detail-match'没有 ohos/'-and$rows[0].Detail-match'HAP') 'USB诊断包含真实工具、工程及SDK缺项'
            &$module {$script:HdcFixture='fixture-hdc';$script:TargetText='[Empty]'}
            $rows=@(&$module {param($Project) Get-JobsRunnerHarmonyDiagnostics -Devices @() -Project $Project} $project)
            Assert-Preflight ($rows.Count-eq1-and$rows[0].Detail-match'USB 调试授权') 'HDC无目标但USB可见时提示手机授权，不假造可运行ID'
            &$module {function script:Invoke-JobsRunnerReadOnlyTool {throw 'fixture HDC timeout'}}
            $rows=@(&$module {param($Project) Get-JobsRunnerHarmonyDiagnostics -Devices @() -Project $Project} $project)
            Assert-Preflight ($rows.Count-eq1-and$rows[0].Detail-match'timeout') 'HDC超时仍保留USB诊断及失败原因'
            &$module {$script:HdcFixture=$null;$script:UsbFixture=@([pscustomobject]@{FriendlyName='HUAWEI Keyboard';InstanceId='USB\VID_12D1&PID_9999\keyboard'})}
            $rows=@(&$module {param($Project) Get-JobsRunnerHarmonyDiagnostics -Devices @() -Project $Project} $project)
            Assert-Preflight ($rows.Count-eq0) '没有HDC调试证据时不把普通华为外设冒充鸿蒙手机'
            Remove-Module $module
        }
        foreach ($scenario in @('base-fail', 'target-fail', 'cancel')) {
            $setup = New-Module -ScriptBlock {
                param($Path,$Scenario)
                . $Path
                $script:Scenario=$Scenario; $script:GateCalls=0; $script:LaunchCalls=0; $script:DeviceCalls=0
                function script:Select-JobsSetupChoice { if($script:Scenario-ceq'cancel'){return '仅完成环境准备，本次不运行应用'};return '实际编译安装并启动验证（推荐）' }
                function script:Set-JobsSetupProgress { }
                function script:Invoke-JobsSetupRunPreflight { $script:GateCalls++;if($script:Scenario-ceq'base-fail'-or$script:GateCalls-eq2){throw 'fixture preflight blocked'} }
                function script:Select-JobsSetupDevice { $script:DeviceCalls++;return 'fixture-phone' }
                function script:Get-JobsSetupRunArguments { return @('run','--machine') }
                function script:Read-JobsSetupInput { return 'RUN' }
                function script:New-JobsSetupBatchStart { $script:LaunchCalls++;throw '不应越过体检进入启动器' }
            } -ArgumentList (Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetupRun.ps1'),$scenario
            $failed=$false
            try { &$setup { param($Project) Invoke-JobsSetupRunVerification $Project ([pscustomobject]@{Flutter='fixture'}) 'fzf' 'android' } $project } catch { $failed=$true }
            $counts=&$setup { @($script:GateCalls,$script:LaunchCalls,$script:DeviceCalls) }
            Assert-Preflight ($counts[1]-eq0) '一键配置实际run不能绕过体检门禁'
            if($scenario-ceq'base-fail'){Assert-Preflight ($failed-and$counts[0]-eq1-and$counts[2]-eq0) '一键配置基础失败时不选择设备'}
            elseif($scenario-ceq'target-fail'){Assert-Preflight ($failed-and$counts[0]-eq2-and$counts[2]-eq1) 'RUN确认后目标复检失败仍不启动'}
            else{Assert-Preflight (-not$failed-and$counts[0]-eq0-and$counts[2]-eq0) '只准备模式不体检运行、不选择设备、不启动应用'}
            Remove-Module $setup
        }
        Write-Host ('PASS: ' + $script:checks + ' preflight assertions')
    } finally {
        $env:TOOL_HOME = $oldToolHome
        $env:DEVECO_STUDIO_HOME = $oldStudioHome
        $env:ANDROID_HOME = $oldAndroidHome
        $env:ANDROID_SDK_ROOT = $oldAndroidRoot
        if ([IO.Directory]::Exists($temporary)) { [IO.Directory]::Delete($temporary, $true) }
    }
}

Invoke-PreflightTests

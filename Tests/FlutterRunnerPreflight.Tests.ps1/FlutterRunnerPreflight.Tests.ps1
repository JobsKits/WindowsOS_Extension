# FlutterRunnerPreflight.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年11月10日，星期二.
# 临时 SDK / 工程与假工具；不运行用户工程、不联网、不注册扩展。
[CmdletBinding()]
param()
# 源包装与已发布 flat 布局共用路径，兼容旧收据且不跟随包装目录链接。
function Resolve-JobsScriptLayoutPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    if ([IO.Path]::GetExtension($Path) -notin @('.ps1','.cmd','.vbs')) { return $Path }
    if (Test-Path -LiteralPath $Path -PathType Container) {
        $directory = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ('脚本包装不能是链接：' + $Path) }
        return Join-Path $Path $directory.Name
    }
    return $Path
}
# 仅新源码包装压平到原发布名称；原有 SDK 资源包与 README 布局保持原意。
function Convert-JobsReleaseLayoutRelativePath {
    param([string]$Package, [string]$Relative)
    $parts = @($Relative -split '[\\/]')
    if ($parts.Count -lt 2) { return $Relative }
    $last = $parts[$parts.Count - 1]
    $parent = $parts[$parts.Count - 2]
    if ($last -ceq 'README.md' -and [IO.Path]::GetExtension($parent) -in @('.ps1','.cmd','.vbs')) {
        $sibling = Join-Path (Join-Path $Package (($parts[0..($parts.Count-2)]) -join '/')) $parent
        if ((Test-Path -LiteralPath $sibling -PathType Leaf) -and ([IO.File]::ReadAllText($sibling) -match '(?m)^(?:#|rem|\x27) JOBS_SOURCE_LAYOUT_ROOT_V1')) { return $null }
    }
    if ($last -ceq $parent -and [IO.Path]::GetExtension($last) -in @('.ps1','.cmd','.vbs')) {
        $source = Join-Path $Package $Relative
        if ((Test-Path -LiteralPath $source -PathType Leaf) -and ([IO.File]::ReadAllText($source) -match '(?m)^(?:#|rem|\x27) JOBS_SOURCE_LAYOUT_ROOT_V1')) {
            return (($parts[0..($parts.Count-2)]) -join '/')
        }
    }
    return $Relative
}


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
        foreach ($directory in @($project, (Join-Path $project '.dart_tool'), (Join-Path $project 'android'), (Join-Path $project 'windows'), (Join-Path $project 'web'), (Join-Path $project 'ohos/AppScope'), (Join-Path $sdk 'bin/cache/dart-sdk/bin'), (Join-Path $sdk 'packages/flutter_tools/.dart_tool'), (Join-Path $sdk 'packages/flutter'), (Join-Path $android 'platform-tools'), (Join-Path $harmony 'sdk/default/openharmony/ets'), (Join-Path $harmony 'sdk/default/openharmony/native'), (Join-Path $harmony 'sdk/default/openharmony/toolchains'))) { [void][IO.Directory]::CreateDirectory($directory) }
        foreach ($path in @((Join-Path $sdk 'bin/flutter.bat'), (Join-Path $sdk 'bin/cache/dart-sdk/bin/dart.exe'), (Join-Path $sdk 'bin/cache/flutter_tools.snapshot'), (Join-Path $sdk 'packages/flutter_tools/.dart_tool/package_config.json'), (Join-Path $project 'android/gradlew.bat'), (Join-Path $android 'platform-tools/adb.exe'), (Join-Path $project 'ohos/build-profile.json5'), (Join-Path $project 'ohos/oh-package.json5'), (Join-Path $project 'ohos/AppScope/app.json5'), (Join-Path $project 'ohos/hvigorfile.ts'))) { [IO.File]::WriteAllText($path, 'fixture') }
        [IO.File]::WriteAllText((Join-Path $project 'pubspec.yaml'), "name: fixture`ndependencies:`n  flutter:`n    sdk: flutter`n")
        [IO.File]::WriteAllText((Join-Path $sdk 'packages/flutter/pubspec.yaml'), 'name: flutter')
        $validPackages=@{configVersion=2;packages=@(@{name='fixture';rootUri='../'},@{name='flutter';rootUri=[Uri]::new((Join-Path $sdk 'packages/flutter/') ).AbsoluteUri})}|ConvertTo-Json -Depth 8
        [IO.File]::WriteAllText((Join-Path $project '.dart_tool/package_config.json'),$validPackages)
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
            Assert-Preflight ($report.base.State -ceq 'ready' -and $report.android.State -ceq 'ready' -and $report.ohos.State -ceq 'ready') ($relative + ' 三端检查及公共环境完整通过：' + ($report|ConvertTo-Json -Depth 6 -Compress))
            Assert-Preflight ($report.ios.State -ceq 'not-applicable') 'Windows明确显示iOS不适用'
            $failed = $false
            try { & $module { param($Output) ConvertFrom-JobsRunnerDoctorScope $Output } ('[   +2 ms] ' + $healthyScope) } catch { $failed = $true }
            Assert-Preflight $failed '结构化体检拒绝带verbose时间前缀的畸形JSON，不凭残余正文放行'
            & $module { param($Report) Assert-JobsRunnerPreflight $Report 'android' } $report
            Assert-Preflight ((@(& $module { $script:PreflightCalls.ToArray() }) -join '|') -notmatch '(?:precache|pub get|flutter run|install|create)') '只读检查未调用安装、缓存获取、生成或运行'

            $indexPath=Join-Path $project '.dart_tool/package_config.json'
            $savedIndex=[IO.File]::ReadAllText($indexPath)
            $wrongSdk=Join-Path $temporary 'Wrong SDK'
            [void][IO.Directory]::CreateDirectory((Join-Path $wrongSdk 'packages/flutter'))
            [IO.File]::WriteAllText((Join-Path $wrongSdk 'packages/flutter/pubspec.yaml'),'name: flutter')
            $wrongConfig=$savedIndex|ConvertFrom-Json
            @($wrongConfig.packages|Where-Object{$_.name-ceq'flutter'})[0].rootUri=[Uri]::new((Join-Path $wrongSdk 'packages/flutter/')).AbsoluteUri
            [IO.File]::WriteAllText($indexPath,($wrongConfig|ConvertTo-Json -Depth 8))
            $blocked=$false
            try{&$module {param($Project,$Flutter)Assert-JobsRunnerProjectPackages $Project -Flutter $Flutter} $project (Join-Path $sdk 'bin/flutter.bat')}catch{$blocked=$_.Exception.Message-match'本次所选 Flutter SDK'}
            Assert-Preflight $blocked '依赖目录存在但flutter包指向另一SDK时不能判定公共依赖健康'
            [IO.File]::WriteAllText($indexPath,$savedIndex)
            $linkSdk=Join-Path $temporary ('FvmSdkLink-'+[guid]::NewGuid().ToString('N'))
            $linked=$false
            try{[void](New-Item -ItemType SymbolicLink -Path $linkSdk -Target $sdk -ErrorAction Stop);$linked=$true}catch{}
            if($linked){
                & $module {param($Project,$Flutter)Assert-JobsRunnerProjectPackages $Project -Flutter $Flutter} $project (Join-Path $linkSdk 'bin/flutter.bat')
                Assert-Preflight $true 'FVM链接入口与真实SDK包路径经实际链接解析可判为同一SDK'
            }
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
                    function script:Repair-JobsRunnerRequiredEnvironment { param($Flutter) return $Flutter }
                    function script:Request-JobsRunnerOtherEnvironmentPreparation { }
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
                if ($scenario -ceq 'pass') { Assert-Preflight (-not $failed -and $counts[0] -eq 1 -and $counts[1] -eq 1 -and $counts[3] -eq 3) '健康目标准备后复查三次，缓存准备与应用启动各一次' }
                elseif ($scenario -ceq 'base-fail') { Assert-Preflight ($failed -and $counts[0] -eq 0 -and $counts[1] -eq 0 -and $counts[2] -eq 0) '公共依赖先修复并复检，仍失败时不选择设备或准备平台SDK' }
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
            } -ArgumentList (Resolve-JobsScriptLayoutPath (Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetupRun.ps1')),$scenario
            $failed=$false
            try { &$setup { param($Project) Invoke-JobsSetupRunVerification $Project ([pscustomobject]@{Flutter='fixture'}) 'fzf' 'android' } $project } catch { $failed=$true }
            $counts=&$setup { @($script:GateCalls,$script:LaunchCalls,$script:DeviceCalls) }
            Assert-Preflight ($counts[1]-eq0) '一键配置实际run不能绕过体检门禁'
            if($scenario-ceq'base-fail'){Assert-Preflight ($failed-and$counts[0]-eq1-and$counts[2]-eq0) '一键配置基础失败时不选择设备'}
            elseif($scenario-ceq'target-fail'){Assert-Preflight ($failed-and$counts[0]-eq2-and$counts[2]-eq1) 'RUN确认后目标复检失败仍不启动'}
            else{Assert-Preflight (-not$failed-and$counts[0]-eq0-and$counts[2]-eq0) '只准备模式不体检运行、不选择设备、不启动应用'}
            Remove-Module $setup
        }
        foreach ($relative in @('JobsFlutterRunner/Scripts/Action.psm1','JobsFlutterTools/Scripts/Actions/run/Scripts/Action.psm1')) {
            $module=Import-Module (Join-Path $root $relative) -Force -PassThru -DisableNameChecking
            & $module {
                $script:Rows=[Collections.Generic.List[object]]::new()
                function script:Write-JobsRunnerDisplayText { param($Object,$ForegroundColor) $script:Rows.Add([pscustomobject]@{Text=[string]$Object;Color=[string]$ForegroundColor}) }
                function script:Write-JobsRunnerMilestone { }
            }
            & $module { Write-JobsRunnerPreflight @{base=(New-JobsRunnerPreflightStatus 'Flutter' 'ready' '检查1；检查2');android=(New-JobsRunnerPreflightStatus 'Android' 'failed' "缺项1`n缺项2")} }
            $rows=@(& $module {$script:Rows.ToArray()})
            Assert-Preflight ($rows.Count-eq4-and$rows[0].Text.StartsWith('✅')-and$rows[1].Color-ceq'Green'-and$rows[2].Text.StartsWith('❌')-and$rows[3].Color-ceq'Red') '体检每条独立换行，通过绿勾，不满足整条红叉'
            $scopeRoot=Join-Path $temporary ('report-scope-'+[guid]::NewGuid().ToString('N'))
            $scopeProject=Join-Path $scopeRoot 'Project A';$otherProject=Join-Path $scopeRoot 'Project B'
            $scopeSdk=Join-Path $scopeRoot 'Sdk A';$otherSdk=Join-Path $scopeRoot 'Sdk B'
            foreach($directory in @($scopeProject,$otherProject,(Join-Path $scopeSdk 'bin/internal'),(Join-Path $otherSdk 'bin/internal'))){[void][IO.Directory]::CreateDirectory($directory)}
            [IO.File]::WriteAllText((Join-Path $scopeSdk 'bin/internal/engine.version'),'engine-one')
            [IO.File]::WriteAllText((Join-Path $otherSdk 'bin/internal/engine.version'),'engine-two')
            $scopeFlutter=Join-Path $scopeSdk 'bin/flutter.bat';$otherFlutter=Join-Path $otherSdk 'bin/flutter.bat'
            & $module {
                param($Flutter,$Project)
                Reset-JobsRunnerPreflightDisplay
                $script:Rows.Clear()
                $script:DisplayReport=@{base=(New-JobsRunnerPreflightStatus 'Flutter' 'ready' '基础检查通过');ohos=(New-JobsRunnerPreflightStatus '鸿蒙' 'failed' "未适配插件：`n- plugin_a`n- plugin_b")}
                Write-JobsRunnerPreflight $script:DisplayReport $Flutter $Project
            } $scopeFlutter $scopeProject
            $rows=@(&$module {$script:Rows.ToArray()})
            Assert-Preflight ($rows.Count-eq4-and($rows.Text-join'|').Contains('plugin_b')) '同轮首份体检完整展示全部状态及插件明细'
            & $module {param($Flutter,$Project)$script:Rows.Clear();Write-JobsRunnerPreflight $script:DisplayReport $Flutter $Project} $scopeFlutter $scopeProject
            Assert-Preflight ((&$module {$script:Rows.Count})-eq0) '相同scope且结果未变化时不重复完整插件清单'
            $gateFailed=$false
            try{&$module {Assert-JobsRunnerPreflight $script:DisplayReport 'ohos-arm64'}}catch{$gateFailed=$_.Exception.Message.Contains('plugin_a')}
            Assert-Preflight $gateFailed '展示未变化仍保留完整真实报告，运行门禁继续阻断失败平台'
            & $module {param($Flutter,$Project)$script:Rows.Clear();$script:DisplayReport.ohos.Detail="未适配插件：`n- plugin_a`n- plugin_b`n- plugin_c";Write-JobsRunnerPreflight $script:DisplayReport $Flutter $Project} $scopeFlutter $scopeProject
            $rows=@(&$module {$script:Rows.ToArray()})
            Assert-Preflight ($rows.Count-eq4-and($rows.Text-join'|').Contains('plugin_c')-and($rows.Text-join'|')-notmatch'Flutter') '原报告对象的插件详情变化时完整展示该项，其它平台不重复'
            & $module {param($Flutter,$Project)$script:Rows.Clear();$script:DisplayReport.ohos=New-JobsRunnerPreflightStatus '鸿蒙' 'ready' '工具链与插件检查通过';Write-JobsRunnerPreflight $script:DisplayReport $Flutter $Project} $scopeFlutter $scopeProject
            $rows=@(&$module {$script:Rows.ToArray()})
            Assert-Preflight ($rows.Count-eq1-and$rows[0].Color-ceq'Green'-and$rows[0].Text.StartsWith('✅')) '未就绪恢复通过时只展示恢复项，旧错误清单不重放'
            [IO.File]::WriteAllText((Join-Path $scopeSdk 'bin/internal/engine.version'),'engine-updated-at-same-path')
            & $module {param($Flutter,$Project)$script:Rows.Clear();Write-JobsRunnerPreflight $script:DisplayReport $Flutter $Project} $scopeFlutter $scopeProject
            Assert-Preflight ((&$module {$script:Rows.Count})-eq2) '同SDK路径的engine身份改变时重新全量展示'
            [IO.File]::WriteAllText((Join-Path $scopeProject '.fvmrc'),'{"flutter":"other-pinned-version"}')
            & $module {param($Flutter,$Project)$script:Rows.Clear();Write-JobsRunnerPreflight $script:DisplayReport $Flutter $Project} $scopeFlutter $scopeProject
            Assert-Preflight ((&$module {$script:Rows.Count})-eq2) '工程FVM声明改变时不复用旧展示快照'
            & $module {param($Flutter,$Project)$script:Rows.Clear();Write-JobsRunnerPreflight $script:DisplayReport $Flutter $Project} $scopeFlutter $otherProject
            Assert-Preflight ((&$module {$script:Rows.Count})-eq2) '切换工程时重新全量展示，不沿用另一工程快照'
            & $module {param($Flutter,$Project)$script:Rows.Clear();Write-JobsRunnerPreflight $script:DisplayReport $Flutter $Project} $otherFlutter $otherProject
            Assert-Preflight ((&$module {$script:Rows.Count})-eq2) '切换Flutter入口与SDK时重新全量展示'
            & $module {param($Flutter,$Project)$script:Rows.Clear();Reset-JobsRunnerPreflightDisplay;Write-JobsRunnerPreflight $script:DisplayReport $Flutter $Project} $otherFlutter $otherProject
            Assert-Preflight ((&$module {$script:Rows.Count})-eq2) '开始新一轮运行时显式重置，首份报告仍为全量'
            & $module {$script:Rows.Clear();Write-JobsRunnerPreflight $script:DisplayReport;Write-JobsRunnerPreflight $script:DisplayReport}
            Assert-Preflight ((&$module {$script:Rows.Count})-eq4) '未提供工程及SDK身份的独立调用保留每次全量，不误用旧快照'
            & $module { Initialize-JobsRunnerDisplay }
            $coloured=[Jobs.RunnerDisplayV1.Formatter]::Format('[错误] failed https://example.com/a(b)?x=1。',$true,$true,'37')
            Assert-Preflight ($coloured.Contains("$([char]27)[31m")-and$coloured.Contains("$([char]27)[32;4mhttps://example.com/a(b)?x=1$([char]27)[24;31m。")) '错误正文红字，URL绿下划线后恢复红字且句读不染色'
            $plain=[Jobs.RunnerDisplayV1.Formatter]::Format(([string][char]27+'[31m[会话] [依赖] [警告] [错误] https://example.com'+[string][char]27+'[0m'),$false,$false,'37')
            Assert-Preflight ($plain.Contains('💬 [会话]')-and$plain.Contains('📦 [依赖]')-and$plain.Contains('⚠️ [警告]')-and$plain.Contains('❌ [错误]')-and-not$plain.Contains([string][char]27)) '结构标签保留并补emoji，纯文本无ANSI'
            $writerTarget=New-Object IO.StringWriter
            $writer=New-Object Jobs.RunnerDisplayV1.Writer $writerTarget,$false,$false
            $writer.Write('[会');$writer.Write("话] fixture`n");$writer.Flush()
            Assert-Preflight ($writerTarget.ToString().StartsWith('💬 [会话] fixture')) 'SDK双流展示跨块标签完整渲染'
            & $module {
                $script:RepairCalls=[Collections.Generic.List[string]]::new()
                function script:Repair-JobsRunnerAndroidEnvironment { $script:RepairCalls.Add('repair:Android') }
                function script:Invoke-JobsPrepareHarmonyPipeline {param($Flutter,$Project,$DiagnosticKey,[switch]$EnvironmentOnly) if(-not$EnvironmentOnly){throw 'wrong mode'};$script:RepairCalls.Add('repair:Harmony');return [pscustomobject]@{Flutter='prepared-harmony';Environment=@{}}}
                function script:Read-JobsRunnerInput { throw '所选平台不得再次确认安装' }
            }
            $selected=&$module { Repair-JobsRunnerRequiredEnvironment 'flutter' 'project' 'android' @{base=@{State='ready'};android=@{State='failed'}} }
            Assert-Preflight ($selected-ceq'flutter'-and(@(&$module {$script:RepairCalls.ToArray()})-join'|')-ceq'repair:Android') '所选Android缺项直接准备一次，不额外询问'
            $selected=&$module { Repair-JobsRunnerRequiredEnvironment 'flutter' 'project' 'ohos-arm64' @{base=@{State='ready'};ohos=@{State='failed'}} }
            Assert-Preflight ($selected-ceq'prepared-harmony'-and(@(&$module {$script:RepairCalls.ToArray()})-join'|')-ceq'repair:Android|repair:Harmony') '所选Harmony用环境准备模式承接实际SDK，不要求虚构设备ID'
            & $module {
                $script:Answers=[Collections.Generic.Queue[string]]::new();$script:Answers.Enqueue('');$script:Answers.Enqueue(' ')
                function script:Read-JobsRunnerInput { return $script:Answers.Dequeue() }
                function script:Start-JobsRunnerBackgroundPreparation {param($Flutter,$Project,$Platform)$script:RepairCalls.Add('background:'+$Platform)}
            }
            &$module {Request-JobsRunnerOtherEnvironmentPreparation 'flutter' 'project' 'android' @{android=@{State='failed'};ohos=@{State='failed'}};Request-JobsRunnerOtherEnvironmentPreparation 'flutter' 'project' 'android' @{ohos=@{State='failed'}}}
            Assert-Preflight ((@(&$module {$script:RepairCalls.ToArray()})-join'|')-ceq'repair:Android|repair:Harmony|background:Harmony') '只询问其它缺失平台，回车后台准备，任意非空字符跳过'
            & $module {
                $script:CommonEvents=[Collections.Generic.List[string]]::new()
                $script:CommonStillFails=$false;$script:AndroidStillFails=$false
                function script:Invoke-JobsRunnerTool {param($Flutter,$Arguments)$script:CommonEvents.Add('pub:'+$Flutter+':'+($Arguments-join' '));return ''}
                function script:Get-JobsRunnerPreflight {
                    $script:CommonEvents.Add('recheck')
                    return @{base=(New-JobsRunnerPreflightStatus 'Flutter' $(if($script:CommonStillFails){'failed'}else{'ready'}) '公共依赖');android=(New-JobsRunnerPreflightStatus 'Android' $(if($script:AndroidStillFails){'failed'}else{'ready'}) '平台检查');ohos=(New-JobsRunnerPreflightStatus 'Harmony' 'failed' '不相关平台缺项')}
                }
                function script:Write-JobsRunnerPreflight { }
                function script:Repair-JobsRunnerAndroidEnvironment {$script:CommonEvents.Add('android-sdk')}
                function script:Invoke-JobsPrepareHarmonyPipeline {throw '公共依赖失败不准修复无关Harmony SDK'}
            }
            $result=&$module {Repair-JobsRunnerRequiredEnvironment 'chosen-sdk-flutter' 'project' 'android' @{base=@{State='failed'};android=@{State='failed'};ohos=@{State='failed'}}}
            Assert-Preflight ($result-ceq'chosen-sdk-flutter'-and(@(&$module {$script:CommonEvents.ToArray()})-join'|')-ceq'pub:chosen-sdk-flutter:pub get|recheck') '公共依赖先以所选SDK pub get并复检，平台随之恢复时不安装任何平台SDK'
            &$module {$script:CommonEvents.Clear();$script:AndroidStillFails=$true}
            &$module {Repair-JobsRunnerRequiredEnvironment 'chosen-sdk-flutter' 'project' 'android' @{base=@{State='failed'};android=@{State='failed'}}}|Out-Null
            Assert-Preflight ((@(&$module {$script:CommonEvents.ToArray()})-join'|')-ceq'pub:chosen-sdk-flutter:pub get|recheck|android-sdk') '只有公共依赖复检通过而所选Android仍缺项时才准备AndroidSDK'
            &$module {$script:CommonEvents.Clear();$script:CommonStillFails=$true}
            $blocked=$false
            try{&$module {Repair-JobsRunnerRequiredEnvironment 'chosen-sdk-flutter' 'project' 'android' @{base=@{State='failed'};android=@{State='failed'}}}}catch{$blocked=$_.Exception.Message-match'base'}
            Assert-Preflight ($blocked-and(@(&$module {$script:CommonEvents.ToArray()})-join'|')-ceq'pub:chosen-sdk-flutter:pub get|recheck') '公共依赖修复仍失败则停在公共门禁，不安装平台SDK'
            $original=Join-Path $temporary ('background-'+[guid]::NewGuid().ToString('N'))
            $originalProject=Join-Path $original 'Project';$originalSdk=Join-Path $original 'Sdk';$background=Join-Path $original 'Task'
            [void][IO.Directory]::CreateDirectory($originalProject);[void][IO.Directory]::CreateDirectory((Join-Path $originalSdk 'bin'));[void][IO.Directory]::CreateDirectory($background)
            [IO.File]::WriteAllText((Join-Path $originalProject 'pubspec.yaml'),'original project')
            [IO.File]::WriteAllText((Join-Path $originalSdk 'bin/flutter.exe'),'fixture SDK')
            $variables=@('LOCALAPPDATA','APPDATA','USERPROFILE','PUB_CACHE','GRADLE_USER_HOME','ANDROID_HOME','ANDROID_SDK_ROOT','ANDROID_USER_HOME','ANDROID_AVD_HOME','FVM_CACHE_PATH','FLUTTER_ROOT','TOOL_HOME','DEVECO_STUDIO_HOME','DEVECO_SDK_HOME','OHOS_SDK_HOME','JAVA_HOME','NO_COLOR','PLAIN_OUTPUT','JOBS_FLUTTER_RUNNER_FZF')
            $saved=&$module {param($Names)Get-JobsRunnerTaskEnvironmentSnapshot $Names} $variables
            try {
                &$module {
                    function script:Repair-JobsRunnerAndroidEnvironment {param($Flutter,$Project)$script:BackgroundSeen=@($Flutter,$Project,$env:ANDROID_HOME,$env:PUB_CACHE,$env:FVM_CACHE_PATH);[IO.File]::WriteAllText((Join-Path $Project 'pubspec.yaml'),'private preparation')}
                }
                &$module {param($Flutter,$Project,$Task)Invoke-JobsRunnerBackgroundPreparation $Flutter $Project Android $Task} (Join-Path $originalSdk 'bin/flutter.exe') $originalProject $background
                $seen=@(&$module {$script:BackgroundSeen})
                Assert-Preflight ($seen.Count-eq5-and@($seen|Where-Object{-not$_.StartsWith($background,[StringComparison]::Ordinal)}).Count-eq0) '后台Flutter入口、工程与Android/Pub/FVM缓存均位于本任务私有目录'
                Assert-Preflight ([IO.File]::ReadAllText((Join-Path $originalProject 'pubspec.yaml'))-ceq'original project'-and[IO.File]::ReadAllText((Join-Path $originalSdk 'bin/flutter.exe'))-ceq'fixture SDK') '后台准备不修改原工程和原SDK'
                Assert-Preflight ([IO.File]::Exists((Join-Path $background 'prepared.txt'))-and[IO.File]::ReadAllText((Join-Path $background 'state.txt')).Contains('待当前运行结束')) '后台成功只留下位置及待应用说明，不发布工程变更'
                $held=[IO.File]::Open((Join-Path $background 'task.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
                try {
                    [IO.File]::WriteAllText((Join-Path $background 'state.txt'),'active writer')
                    &$module {param($Flutter,$Project,$Task)Invoke-JobsRunnerBackgroundPreparation $Flutter $Project Android $Task} (Join-Path $originalSdk 'bin/flutter.exe') $originalProject $background
                    Assert-Preflight ([IO.File]::ReadAllText((Join-Path $background 'state.txt'))-ceq'active writer') '重复后台任务拿不到锁时不改写有效写者状态'
                }finally{$held.Dispose()}
            }finally{&$module {param($Snapshot)Restore-JobsRunnerTaskEnvironment $Snapshot} $saved}
            Remove-Module $module
        }
        # 使用真实独立PowerShell及其真实子进程，核验停止子树、锁释放与PID复用保护。
        $closure=Join-Path $temporary '后台进程 闭包'
        $scripts=Join-Path $closure 'Scripts'
        $helper=Join-Path $scripts 'RunPreflight.ps1/RepairRunEnvironment.ps1/RepairRunEnvironment.ps1'
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $helper))
        [IO.File]::Copy((Join-Path $root 'JobsFlutterRunner/Scripts/RunPreflight.ps1/RepairRunEnvironment.ps1/RepairRunEnvironment.ps1'),$helper)
        $hostPath=(Get-Process -Id $PID).Path
        $fake=@'
. (Join-Path $PSScriptRoot 'RunPreflight.ps1/RepairRunEnvironment.ps1/RepairRunEnvironment.ps1')
function Get-JobsRunnerProjectRoot { return Join-Path (Split-Path -Parent $PSScriptRoot) 'Runs' }
function Get-JobsRunnerCreatorPowerShell { return '__HOST__' }
function Write-JobsRunnerDisplayText {param($Object)Write-Host $Object}
function Repair-JobsRunnerAndroidEnvironment {
    param($Flutter,$Project)
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=Get-JobsRunnerCreatorPowerShell;$start.Arguments='-NoProfile -Command "Start-Sleep -Seconds 120"';$start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $child=[Diagnostics.Process]::Start($start)
    [IO.File]::WriteAllText((Join-Path (Get-JobsRunnerProjectRoot '') 'child.json'),(@{Pid=$child.Id;StartTicks=[string]$child.StartTime.ToUniversalTime().Ticks}|ConvertTo-Json))
    try{Start-Sleep -Seconds 120}finally{$child.Dispose()}
}
'@
        $fake=$fake.Replace('__HOST__',$hostPath.Replace("'","''"))
        $fakeModule=Join-Path $scripts 'Action.psm1'
        [IO.File]::WriteAllText($fakeModule,$fake,(New-Object Text.UTF8Encoding($false)))
        $module=Import-Module $fakeModule -PassThru -Force -DisableNameChecking
        $source=Join-Path $closure 'OriginalProject';$sdk=Join-Path $closure 'OriginalSdk'
        [void][IO.Directory]::CreateDirectory($source);[void][IO.Directory]::CreateDirectory((Join-Path $sdk 'bin'))
        [IO.File]::WriteAllText((Join-Path $source 'pubspec.yaml'),'original project')
        [IO.File]::WriteAllText((Join-Path $sdk 'bin/flutter.exe'),'fixture SDK')
        $runs=&$module {Get-JobsRunnerProjectRoot ''}
        $childRecord=Join-Path $runs 'child.json'
        try {
            $clock=[Diagnostics.Stopwatch]::StartNew()
            &$module {param($Flutter,$Project)Start-JobsRunnerBackgroundPreparation $Flutter $Project Android} (Join-Path $sdk 'bin/flutter.exe') $source
            Assert-Preflight ($clock.Elapsed.TotalSeconds-lt5) '实际后台启动立即返回，未等待环境准备完成'
            $deadline=[DateTime]::UtcNow.AddSeconds(45)
            while(-not[IO.File]::Exists($childRecord)-and[DateTime]::UtcNow-lt$deadline){Start-Sleep -Milliseconds 100}
            Assert-Preflight ([IO.File]::Exists($childRecord)) '真实独立worker进入私有准备并创建真实下载子进程夹具'
            $childIdentity=[IO.File]::ReadAllText($childRecord)|ConvertFrom-Json
            $childProcess=[Diagnostics.Process]::GetProcessById([int]$childIdentity.Pid)
            &$module {param($Runs)Stop-JobsRunnerEnvironmentPreparations $Runs} $runs
            $deadline=[DateTime]::UtcNow.AddSeconds(5)
            while(-not$childProcess.HasExited-and[DateTime]::UtcNow-lt$deadline){Start-Sleep -Milliseconds 50;$childProcess.Refresh()}
            Assert-Preflight ($childProcess.HasExited) '停止本工程后台任务时真实子进程同时退出'
            $childProcess.Dispose()
            $task=Join-Path $runs 'EnvironmentPreparation/Android'
            $released=[IO.File]::Open((Join-Path $task 'task.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);$released.Dispose()
            Assert-Preflight ([IO.File]::ReadAllText((Join-Path $task 'state.txt')).StartsWith('已停止后台准备')) 'worker结束释放文件锁并明确记录停止状态'
            Assert-Preflight ([IO.File]::ReadAllText((Join-Path $source 'pubspec.yaml'))-ceq'original project') '进程级后台与停止均保留原工程'
            [IO.File]::WriteAllText((Join-Path $task 'worker.json'),(@{Pid=$PID;StartTicks='0'}|ConvertTo-Json))
            &$module {param($Runs)Stop-JobsRunnerEnvironmentPreparations $Runs} $runs
            Assert-Preflight ([IO.File]::ReadAllText((Join-Path $task 'state.txt')).StartsWith('已停止后台准备')) 'PID相同而启动时间不符时不停止当前进程或覆盖原停止状态'
        }finally{&$module {param($Runs)Stop-JobsRunnerEnvironmentPreparations $Runs} $runs;Remove-Module $module}
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

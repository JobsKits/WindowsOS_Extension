# FlutterRunnerAndroid.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年10月29日，星期四.
# 临时 SDK 与函数夹具；不联网、不创建真实 AVD、不启动设备或注册扩展。
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$path = Join-Path $root 'JobsFlutterRunner/Scripts/Action.psm1'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('JobsRunnerAndroid-' + [guid]::NewGuid().ToString('N'))
$script:checks = 0
function Assert-AndroidRunner {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
    $script:checks++
}
function New-RunnerFixture {
    $module = Import-Module $path -Force -PassThru -DisableNameChecking
    & $module {
        $script:Calls = [Collections.Generic.List[string]]::new()
        function script:Start-Sleep { param($Seconds, $Milliseconds) }
        function script:Write-JobsLog { param($Text) $script:Calls.Add('log:' + $Text) }
    }
    return $module
}
$savedHome = $env:ANDROID_HOME
$savedRoot = $env:ANDROID_SDK_ROOT
$savedJava = $env:JAVA_HOME
try {
    [void][IO.Directory]::CreateDirectory($temporary)
    $project = Join-Path $temporary 'Project 中文 & 100%'
    [void][IO.Directory]::CreateDirectory((Join-Path $project 'android'))
    $module = New-RunnerFixture
    & $module {
        function script:Invoke-FixtureJava { $global:LASTEXITCODE = 0; return 'fixture license output' }
    }
    $licenseOutput = @(& $module { Invoke-JobsAndroidTool 'Invoke-FixtureJava' '/fixture/tools' sdkmanager @('--licenses') -Interactive })
    Assert-AndroidRunner ($licenseOutput.Count -eq 0) '许可证交互输出不混入AVD名称返回值'
    & $module {
        function script:Invoke-JobsProcess {
            param($FilePath, $Arguments)
            if ($Arguments[0] -eq 'devices') { return [pscustomobject]@{ ExitCode = 0; StdOut = "emulator-5560`tdevice"; StdErr = '' } }
            return [pscustomobject]@{ ExitCode = 0; StdOut = "Pixel_existing`nOK"; StdErr = '' }
        }
        function script:Test-JobsAndroidBoot { return $true }
    }
    Assert-AndroidRunner ((& $module { Start-JobsAndroidAvd '/fixture/sdk' 'Pixel_existing' }) -ceq 'emulator-5560') '已运行AVD直接返回匹配serial，不重复启动'
    Remove-Module $module
    $module = New-RunnerFixture
    & $module {
        function script:Find-JobsExecutable { return 'Invoke-TestFzf' }
        function script:Invoke-JobsProcess { return [pscustomobject]@{ ExitCode = 0; StdOut = '--expect'; StdErr = '' } }
        function script:Invoke-TestFzf { $global:LASTEXITCODE = $script:FakeCode; return $script:FakeOutput }
        $script:FakeCode = 1
        $script:FakeOutput = @('left')
    }
    $selection = & $module { Select-JobsRunnerChoice '镜像' @('Android 35') -Back }
    Assert-AndroidRunner ($selection.Kind -eq 'Back') '无匹配时左键仍返回上一层'
    & $module { $script:FakeCode = 130; $script:FakeOutput = @() }
    Assert-AndroidRunner ($null -eq (& $module { Select-JobsRunnerChoice '镜像' @('Android 35') -Back })) 'Esc取消不自动选择'
    & $module { $script:FakeCode = 0; $script:FakeOutput = @('', '1  Android 35') }
    Assert-AndroidRunner ((& $module { Select-JobsRunnerChoice '镜像' @('Android 35') -Back }).Index -eq 0) '回车返回明确选中项'
    Remove-Module $module

    $module = New-RunnerFixture
    & $module {
        function script:Read-JobsRunnerInput { return 'cancel' }
        function script:Get-JobsAndroidArchitecture { throw '取消后不应检查或创建 SDK' }
    }
    $cancelSdk = Join-Path $temporary 'cancelled-sdk'
    Assert-AndroidRunner ($null -eq (& $module { param($Sdk, $Project) New-JobsRunnerAndroidAvd $Sdk $Project @() } $cancelSdk $project)) '初始化准备前取消'
    Assert-AndroidRunner (-not [IO.Directory]::Exists($cancelSdk)) '取消准备不创建SDK目录'
    Remove-Module $module

    $module = New-RunnerFixture
    & $module {
        $script:Answers = [Collections.Generic.Queue[string]]::new()
        $script:Answers.Enqueue('')
        $script:Answers.Enqueue('')
        $script:Selections = [Collections.Generic.Queue[object]]::new()
        $script:Selections.Enqueue([pscustomobject]@{ Kind = 'Selected'; Index = 0 })
        $script:Selections.Enqueue([pscustomobject]@{ Kind = 'Back'; Index = -1 })
        $script:Selections.Enqueue([pscustomobject]@{ Kind = 'Selected'; Index = 0 })
        $script:Selections.Enqueue([pscustomobject]@{ Kind = 'Selected'; Index = 0 })
        $script:ImageInstalled = $true
        $script:CreatedName = ''
        function script:Read-JobsRunnerInput { param($Prompt) return $script:Answers.Dequeue() }
        function script:Get-JobsAndroidArchitecture { return 'x86_64' }
        function script:Get-JobsAndroidJava { return '/fixture/jdk/bin/java.exe' }
        function script:Get-JobsAndroidHealthyTools { return '/fixture/tools' }
        function script:Repair-JobsAndroidComponents { $script:Calls.Add('repair') }
        function script:Get-JobsAndroidAvdHome { return '/fixture/avd-home' }
        function script:Select-JobsRunnerChoice { param($Title, $Items, [switch]$Back) $script:Calls.Add('select:' + $Title); return $script:Selections.Dequeue() }
        function script:Invoke-JobsAndroidTool {
            param($Java, $Tools, $Tool, $Arguments, $InputText, [switch]$Interactive)
            $script:Calls.Add($Tool + ':' + ($Arguments -join ' '))
            if ($Arguments -contains 'create') {
                $script:CreatedName = $Arguments[[Array]::IndexOf($Arguments, '--name') + 1]
                return ''
            }
            if ($Tool -eq 'avdmanager') { return 'id: 1 or "pixel_8"' }
            if ($Arguments -contains '--list_installed') {
                if ($script:ImageInstalled) { return 'system-images;android-35;google_apis;x86_64 | 1 | Android 35' }
                return ''
            }
            if ($Arguments -contains '--list') { return 'system-images;android-35;google_apis;x86_64 | 1 | Android 35' }
            if ($Arguments -contains '--install') { $script:ImageInstalled = $true }
        }
        function script:Get-JobsRunnerAvds { return $script:CreatedName }
    }
    $env:JAVA_HOME = 'original-java'
    $name = & $module { param($Sdk, $Project) New-JobsRunnerAndroidAvd $Sdk $Project @('Jobs_existing') } (Join-Path $temporary 'sdk') $project
    $calls = @(& $module { $script:Calls.ToArray() })
    Assert-AndroidRunner ($name -match '^Jobs_pixel_8_API35_[a-f0-9]{8}$') '按所选型号镜像生成唯一AVD名称'
    Assert-AndroidRunner (@($calls | Where-Object { $_ -like 'select:选择 Android 设备型号' }).Count -eq 2) '镜像左键返回型号选择'
    Assert-AndroidRunner (@($calls | Where-Object { $_ -like '*--install*' }).Count -eq 0) '已安装镜像不重新下载'
    Assert-AndroidRunner (@($calls | Where-Object { $_ -like '*create avd*' }).Count -eq 1) '只创建一次AVD'
    Assert-AndroidRunner (@($calls | Where-Object { $_ -like '*--force*' }).Count -eq 0) '创建不覆盖既有AVD'
    Assert-AndroidRunner ($env:JAVA_HOME -ceq 'original-java') '初始化恢复Java环境'
    & $module {
        $script:Calls.Clear()
        $script:CreatedName = ''
        $script:Answers.Enqueue('')
        $script:Answers.Enqueue('cancel')
        $script:Selections.Enqueue([pscustomobject]@{ Kind = 'Selected'; Index = 0 })
        $script:Selections.Enqueue([pscustomobject]@{ Kind = 'Selected'; Index = 0 })
        $script:ImageInstalled = $false
    }
    Assert-AndroidRunner ($null -eq (& $module { param($Sdk, $Project) New-JobsRunnerAndroidAvd $Sdk $Project @() } (Join-Path $temporary 'sdk') $project)) '最终确认取消'
    $calls = @(& $module { $script:Calls.ToArray() })
    Assert-AndroidRunner (@($calls | Where-Object { $_ -like '*--list --channel=0*' }).Count -eq 1) '缺少镜像读取官方稳定通道'
    Assert-AndroidRunner (@($calls | Where-Object { $_ -like '*--install*' -or $_ -like '*create avd*' }).Count -eq 0) '取消后不下载镜像不创建AVD'
    & $module {
        $script:Calls.Clear()
        $script:CreatedName = ''
        $script:Answers.Enqueue('')
        $script:Answers.Enqueue('')
        $script:Selections.Enqueue([pscustomobject]@{ Kind = 'Selected'; Index = 0 })
        $script:Selections.Enqueue([pscustomobject]@{ Kind = 'Selected'; Index = 0 })
    }
    $name = & $module { param($Sdk, $Project) New-JobsRunnerAndroidAvd $Sdk $Project @() } (Join-Path $temporary 'sdk') $project
    $calls = @(& $module { $script:Calls.ToArray() })
    Assert-AndroidRunner (@($calls | Where-Object { $_ -like '*--install system-images;android-35;google_apis;x86_64' }).Count -eq 1) '确认后只下载所选镜像'
    Assert-AndroidRunner ($calls.IndexOf('sdkmanager:--sdk_root=' + (Join-Path $temporary 'sdk') + ' --licenses') -lt $calls.IndexOf('sdkmanager:--sdk_root=' + (Join-Path $temporary 'sdk') + ' --install system-images;android-35;google_apis;x86_64')) '镜像安装前交由官方工具确认许可证'
    Remove-Module $module

    $module = New-RunnerFixture
    & $module {
        function script:Get-JobsAndroidSdk { return $env:ANDROID_HOME }
        function script:Get-JobsRunnerAvds { return 'Pixel_existing' }
        function script:Select-JobsRunnerChoice { return [pscustomobject]@{ Kind = 'Selected'; Index = 0 } }
        function script:New-JobsRunnerAndroidAvd { throw '已有AVD不应初始化' }
        function script:Start-JobsAndroidAvd { param($Sdk, $Name) $script:Calls.Add('start:' + $Name); return 'emulator-5558' }
        function script:Wait-JobsRunnerAndroidDevice { param($Flutter, $Project, $Serial) return $Serial }
    }
    $sdk = Join-Path $temporary 'sdk'
    [void][IO.Directory]::CreateDirectory((Join-Path $sdk 'emulator'))
    [IO.File]::WriteAllText((Join-Path $sdk 'emulator/emulator.exe'), 'fixture')
    $env:ANDROID_HOME = $sdk
    $env:ANDROID_SDK_ROOT = 'original-sdk-root'
    Assert-AndroidRunner ((& $module { param($Project) Start-JobsRunnerAndroid 'flutter' $Project } $project) -ceq 'emulator-5558') '启动所选已有AVD并等待其serial'
    Assert-AndroidRunner ($env:ANDROID_HOME -ceq $sdk -and $env:ANDROID_SDK_ROOT -ceq 'original-sdk-root') '启动后恢复SDK环境'
    Assert-AndroidRunner ((& $module { $script:RunnerSelectedSdk }) -ceq $sdk) '将所选SDK交给后续Flutter运行上下文'
    Assert-AndroidRunner ((@(& $module { $script:Calls.ToArray() }) -join ',') -ceq 'start:Pixel_existing') '已有AVD不重复创建'
    & $module {
        function script:Get-JobsRunnerAvds { return }
        function script:New-JobsRunnerAndroidAvd { $script:Calls.Add('initialize'); return $null }
    }
    Assert-AndroidRunner ($null -eq (& $module { param($Project) Start-JobsRunnerAndroid 'flutter' $Project } $project)) '缺失AVD时进入初始化且取消不启动'
    Remove-Module $module

    $module = New-RunnerFixture
    & $module {
        $script:Query = 0
        function script:Invoke-JobsRunnerTool {
            $script:Query++
            if ($script:Query -eq 1) { return '[{"id":"emulator-5554","name":"Other","targetPlatform":"android"}]' }
            return '[{"id":"emulator-5554","name":"Other","targetPlatform":"android"},{"id":"emulator-5558","name":"Selected","targetPlatform":"android"}]'
        }
    }
    Assert-AndroidRunner ((& $module { param($Project) Wait-JobsRunnerAndroidDevice 'flutter' $Project 'emulator-5558' } $project) -ceq 'emulator-5558') '等待Flutter识别选定设备，不取其它已启动模拟器'
    Assert-AndroidRunner ((& $module { $script:Query }) -eq 2) '设备延迟出现时重新查询'
    Remove-Module $module

    $module = New-RunnerFixture
    & $module {
        function script:Invoke-JobsRunnerTool { return '[]' }
        function script:Select-JobsRunnerChoice { param($Title, $Items) $script:Labels = $Items; return [pscustomobject]@{ Kind = 'Selected'; Index = 0 } }
        function script:Start-JobsRunnerAndroid { return 'emulator-new' }
    }
    Assert-AndroidRunner ((& $module { param($Project) Select-JobsRunnerDevice 'flutter' $Project } $project) -ceq 'emulator-new') '无设备时仍提供Android初始化入口'
    Assert-AndroidRunner ((& $module { $script:Labels[0] }) -ceq 'Android 模拟器（启动已有 / 缺失时初始化）') '主菜单明确显示启动与初始化'
    Remove-Module $module
    $module = New-RunnerFixture
    & $module {
        function script:Assert-JobsFlutterProject { }
        function script:Get-JobsRunnerProjectRoot { return '/fixture/runs' }
        function script:Get-JobsRunnerSession { return $null }
        function script:Get-JobsRunnerFlutter { return '/fixture/flutter' }
        function script:Invoke-JobsRunnerTool { return '{"frameworkVersion":"fixture"}' }
        function script:Select-JobsRunnerDevice { $script:RunnerSelectedSdk = '/fixture/selected-sdk'; return 'emulator-5558' }
        function script:Start-JobsRunnerSession { $script:Calls.Add('sdk:' + $env:ANDROID_HOME + '|' + $env:ANDROID_SDK_ROOT); return '/fixture/session' }
        function script:Show-JobsRunnerLog { }
    }
    $env:ANDROID_HOME = 'old-home'
    $env:ANDROID_SDK_ROOT = 'old-root'
    & $module { Invoke-JobsFlutterRunAction '/fixture/project' }
    Assert-AndroidRunner ((@(& $module { $script:Calls.ToArray() }) -join ',') -ceq 'sdk:/fixture/selected-sdk|/fixture/selected-sdk') 'Flutter后台启动继承统一的所选SDK'
    Assert-AndroidRunner ($env:ANDROID_HOME -ceq 'old-home' -and $env:ANDROID_SDK_ROOT -ceq 'old-root') '后台启动后恢复调用方SDK环境'
    Remove-Module $module
    Write-Host ('PASS: FlutterRunnerAndroid.Tests.ps1 (' + $script:checks + ' assertions)')
} finally {
    $env:ANDROID_HOME = $savedHome
    $env:ANDROID_SDK_ROOT = $savedRoot
    $env:JAVA_HOME = $savedJava
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}

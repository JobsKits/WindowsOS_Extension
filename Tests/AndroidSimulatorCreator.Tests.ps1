# AndroidSimulatorCreator.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年10月22日，星期四.
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$script:assertions = 0
function Assert-Android { param([bool]$Condition, [string]$Why) $script:assertions++; if (-not $Condition) { throw ('FAIL: ' + $Why) } }
function Assert-AndroidThrows { param([scriptblock]$Action, [string]$Why) $threw = $false; try { & $Action | Out-Null } catch { $threw = $true }; Assert-Android $threw $Why }
$package = Join-Path $root 'JobsAndroidSimulatorCreator'
$module = Import-Module (Join-Path $package 'Scripts/Action.psm1') -PassThru -DisableNameChecking
$installer = Import-Module (Join-Path $package 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
$temporary = Join-Path ([IO.Path]::GetTempPath()) ("JobsAndroid 中文 & 100% ' " + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$oldArch = $env:PROCESSOR_ARCHITECTURE; $oldArch2 = $env:PROCESSOR_ARCHITEW6432
$oldAvd = $env:ANDROID_AVD_HOME; $oldJava = $env:JAVA_HOME; $oldSdk = $env:ANDROID_HOME
try {
    $manifest = Get-Content -LiteralPath (Join-Path $package 'Extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $plan = @(Get-JobsPackageRegistryPlan $manifest $temporary 'powershell.exe')
    Assert-Android ($plan.Count -eq 2) '只注册桌面背景与 CLSID'
    Assert-Android ($plan[0].Key -eq 'Software\Classes\DesktopBackground\shellex\ContextMenuHandlers\Jobs.WindowsExtension.android-simulator-create') '系统桌面专用 handler'
    Assert-Android ($plan[1].InProcServer -eq (Join-Path $temporary 'bin/JobsAndroidSimulatorCreatorContextMenu.dll')) 'DLL 在自身 release'
    Assert-Android (@($plan | Where-Object { $_.Key -match '\\Directory|\\Drive|\\\*|\\shell\\' }).Count -eq 0) '不注册普通目录、磁盘、选中项静态菜单'
    $release = Join-Path $temporary 'release'
    New-JobsPackageRelease $package $release | Out-Null
    foreach ($name in @('ContextMenu.cpp', 'ContextMenu.def', 'DesktopScope.h', 'Build.ps1', 'OpenCmd.ps1', 'CreateAndroidSimulator.ps1')) {
        Assert-Android (Test-Path -LiteralPath (Join-Path $release ('Scripts/' + $name))) ('独立 release 包含 ' + $name)
    }
    $env:PROCESSOR_ARCHITEW6432 = ''; $env:PROCESSOR_ARCHITECTURE = 'AMD64'
    Assert-Android ((& $module { Get-JobsAndroidArchitecture }) -ceq 'x86_64') 'x64 对应 x86_64 镜像'
    $env:PROCESSOR_ARCHITEW6432 = 'ARM64'
    Assert-AndroidThrows { & $module { Get-JobsAndroidArchitecture } } '真实 ARM 宿主不误用 WOW64 x64 镜像'
    $env:PROCESSOR_ARCHITEW6432 = ''; $env:PROCESSOR_ARCHITECTURE = 'x86'
    Assert-AndroidThrows { & $module { Get-JobsAndroidArchitecture } } '32 位宿主明确停止'
    $listing = @'
Installed packages:
system-images;android-35;google_apis;x86_64 | 1 | Android 35
system-images;android-36;default;x86_64 | 1 | Android 36
system-images;android-36;google_apis;x86_64 | 1 | Android 36
system-images;android-36;google_apis;x86_64 | 1 | duplicate
system-images;android-36.1;google_apis;x86_64 | 1 | stable minor
system-images;android-36-ext19;google_apis;x86_64 | 1 | stable extension
system-images;android-37-preview;google_apis;x86_64 | 1 | preview
system-images;android-99;google_apis;arm64-v8a | 1 | wrong host
system-images;android-36;android-tv;x86_64 | 1 | not phone
'@
    $images = @(& $module { param($Text) Get-JobsAndroidImages $Text x86_64 } $listing)
    Assert-Android ($images.Count -eq 5) '镜像去重且支持稳定 minor/ext，排除异构、代号预览、TV'
    Assert-Android ($images[0] -ceq 'system-images;android-36.1;google_apis;x86_64') '默认最新稳定 Google APIs'
    $devices = @(& $module { Get-JobsAndroidDevices "id: 0 or `"Nexus 5`"`nid: 1 or `"pixel_9`"`nid: 2 or `"pixel_8`"" })
    Assert-Android ($devices.Count -eq 3 -and $devices[0] -eq 'pixel_9') '保留含空格的有效硬件 id'
    $env:ANDROID_AVD_HOME = $temporary
    Assert-Android ((& $module { Get-JobsAndroidAvdHome }) -ceq $temporary) '保留用户自定义 AVD_HOME'
    $name = & $module { param($Path) New-JobsAndroidAvdName pixel_9 'system-images;android-36;google_apis;x86_64' @() $Path } $temporary
    Assert-Android ($name -match '^Jobs_pixel_9_API36_[0-9a-f]{8}$') '新名字安全且带设备/API/唯一标识'
    & $module { $script:Answer = ''; function script:Read-JobsAndroidInput { param($Prompt) return $script:Answer } }
    Assert-Android ((& $module { Read-JobsAndroidChoice '选择' @('first', 'second') }) -eq 'first') '编号回车选择首项'
    & $module { $script:Answer = '2' }
    Assert-Android ((& $module { Read-JobsAndroidChoice '选择' @('first', 'second') }) -eq 'second') '编号选择第二项'
    & $module { $script:Answer = 'q' }
    Assert-AndroidThrows { & $module { Read-JobsAndroidChoice '选择' @('first') } } 'q 停止'
    & $module { $script:Answer = '' }
    Assert-Android (-not (& $module { Confirm-JobsAndroidDownload '下载' })) '回车不下载'
    & $module { $script:Answer = 'yes' }
    Assert-Android (-not (& $module { Confirm-JobsAndroidDownload '下载' })) '小写 yes 不安装'
    & $module { $script:Answer = 'YES' }
    Assert-Android (& $module { Confirm-JobsAndroidDownload '下载' }) '精确 YES 安装'
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        $result = & $module { Invoke-JobsAndroidTool /bin/echo "SDK 中文 & 100% '" sdkmanager @('--sdk_root=SDK 中文 & 100%', '--version') }
        Assert-Android ($result -match 'toolsdir=SDK 中文 & 100% '' -classpath' -and $result -match 'SdkManagerCli --sdk_root=SDK 中文 & 100% --version') 'Java argv 保留特殊路径且参数彼此独立'
        Assert-AndroidThrows { & $module { Invoke-JobsAndroidTool /usr/bin/false tools sdkmanager @('--version') } } 'Java 非零退出传播'
    }
    & $module {
        param($Sdk)
        $script:FixtureSdk = $Sdk; $script:Calls = @(); $script:Created = $false; $script:Booted = $false; $script:FailCreate = $false; $script:Choice = 'create'; $script:ModePromptCount = 0
        function script:Test-JobsAndroidDesktop { param($Target) return $Target -eq 'desktop-fixture' }
        function script:Get-JobsAndroidArchitecture { return 'x86_64' }
        function script:Get-JobsAndroidSdk { return $script:FixtureSdk }
        function script:Get-JobsAndroidJava { return (Join-Path $script:FixtureSdk 'jbr/bin/java.exe') }
        function script:Get-JobsAndroidTools { param($Sdk) return $Sdk }
        function script:Read-JobsAndroidChoice { param($Prompt, $Items) if ($Prompt -eq '操作') { $script:ModePromptCount++ }; if ($Prompt -eq '操作' -and $script:Choice -eq 'existing') { return $Items[1] }; return $Items[0] }
        function script:Read-JobsAndroidInput { param($Prompt) return '' }
        function script:Write-JobsLog { param($Message) }
        function script:Invoke-JobsAndroidTool {
            param($Java, $Tools, $Tool, $Arguments, $InputText, [switch]$Interactive)
            $script:Calls += ($Tool + ' ' + ($Arguments -join ' '))
            if ($Arguments -contains '--list_installed') { return 'system-images;android-36;google_apis;x86_64 | 1 | Android' }
            if ($Arguments -contains 'create') {
                if ($script:FailCreate) { throw 'fixture create failed' }
                $script:Created = $true; $script:CreatedName = $Arguments[[array]::IndexOf($Arguments, '--name') + 1]
                if ($InputText -ne "no`n") { throw 'AVD prompt answer missing' }
            }
            if ($Arguments -contains 'device' -and $Arguments -notcontains '-c') { return 'id: 0 or "pixel_9"' }
            return 'healthy'
        }
        function script:Invoke-JobsProcess {
            param($FilePath, $Arguments, $TimeoutSeconds)
            $output = ''
            if ($Arguments -contains '-list-avds') { $output = 'existing'; if ($script:Created) { $output += "`n" + $script:CreatedName } }
            return [pscustomobject]@{ ExitCode = 0; StdOut = $output; StdErr = '' }
        }
        function script:Start-JobsAndroidAvd { param($Sdk, $Name) $script:Booted = $true; $script:BootName = $Name }
    } $temporary
    # Both prerequisites exist, so this branch must never ask to download.
    [void][IO.Directory]::CreateDirectory((Join-Path $temporary 'emulator'))
    [void][IO.Directory]::CreateDirectory((Join-Path $temporary 'platform-tools'))
    [IO.File]::WriteAllText((Join-Path $temporary 'emulator/emulator.exe'), 'fixture')
    [IO.File]::WriteAllText((Join-Path $temporary 'platform-tools/adb.exe'), 'fixture')
    $env:ANDROID_HOME = 'original-sdk'; $env:JAVA_HOME = 'original-java'
    & $module { Invoke-JobsAndroidSimulatorAction desktop-fixture }
    Assert-Android (& $module { $script:Created -and $script:Booted -and $script:BootName -eq $script:CreatedName }) '创建、清单复核后再启动同一个 AVD'
    Assert-Android (& $module { @($script:Calls | Where-Object { $_ -match '--force|--install|--licenses|delete' }).Count -eq 0 }) '已有 SDK/镜像不下载、不覆盖、不删除'
    Assert-Android ($env:ANDROID_HOME -eq 'original-sdk' -and $env:JAVA_HOME -eq 'original-java') '成功后恢复进程变量'
    & $module { $script:Created = $false; $script:Booted = $false; $script:FailCreate = $true }
    Assert-AndroidThrows { & $module { Invoke-JobsAndroidSimulatorAction desktop-fixture } } '创建失败原样传播'
    Assert-Android (-not (& $module { $script:Booted })) '创建失败不启动或报告成功'
    Assert-Android ($env:ANDROID_HOME -eq 'original-sdk' -and $env:JAVA_HOME -eq 'original-java') '失败后恢复进程变量'
    Assert-AndroidThrows { & $module { Invoke-JobsAndroidSimulatorAction folder-fixture } } '点击时复核普通 folder 目标'
    & $module { $script:Choice = 'existing'; $script:FailCreate = $false; $script:Calls = @() }
    & $module { Invoke-JobsAndroidSimulatorAction desktop-fixture }
    Assert-Android (& $module { $script:BootName -eq 'existing' -and @($script:Calls | Where-Object { $_ -match ' create ' }).Count -eq 0 }) '已有 AVD 分支仅启动选择项'
    & $module { $script:ModePromptCount = 0; $script:Choice = 'existing'; Invoke-JobsAndroidSimulatorAction desktop-fixture -Create }
    Assert-Android (& $module { $script:ModePromptCount -eq 0 -and $script:Created -and $script:BootName -eq $script:CreatedName }) '桌面入口直接新建，不多弹操作选择'

    $native = Get-Content -LiteralPath (Join-Path $package 'Scripts/ContextMenu.cpp') -Raw -Encoding UTF8
    Assert-Android ($native.Contains('if (selection) return S_OK;') -and $native.Contains('!IsDesktop(target)')) '原生菜单生成/点击双检且拒绝选中项'
    $source = Get-Content -LiteralPath (Join-Path $package 'Scripts/Action.psm1') -Raw -Encoding UTF8
    Assert-Android ($source.Contains('sys.boot_completed') -and $source.Contains('AddSeconds(180)')) '成功需要系统启动完成且有等待上限'
    Assert-Android (-not $source.Contains('Start-Process -FilePath $java')) 'Java 不经二次 Shell'
    Write-Host ('PASS: AndroidSimulatorCreator.Tests.ps1 (' + $script:assertions + ' assertions)')
} finally {
    $env:PROCESSOR_ARCHITECTURE = $oldArch; $env:PROCESSOR_ARCHITEW6432 = $oldArch2
    $env:ANDROID_AVD_HOME = $oldAvd; $env:JAVA_HOME = $oldJava; $env:ANDROID_HOME = $oldSdk
    Remove-Module $module; Remove-Module $installer
    Remove-Item -LiteralPath $temporary -Recurse -Force
}

# Unified Flutter menu actions. Project-local FVM only; never install or select global Flutter.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking

function Get-JobsToolsFvm {
    param([string]$Project)
    $modern = Join-Path $Project '.fvmrc'
    $legacy = Join-Path $Project '.fvm/fvm_config.json'
    if (-not [IO.File]::Exists($modern) -and -not [IO.File]::Exists($legacy)) { throw '项目尚未通过 FVM 绑定 SDK。请先使用安装/切换Flutter SDK版本；不会回退全局 Flutter。' }
    $configPath = if ([IO.File]::Exists($modern)) { $modern } else { $legacy }
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $pin = if ($config.PSObject.Properties['flutter']) { $config.flutter } elseif ($config.PSObject.Properties['flutterSdkVersion']) { $config.flutterSdkVersion } else { $null }
    if ($pin -isnot [string] -or [string]::IsNullOrWhiteSpace($pin)) { throw 'FVM 版本声明无效。' }
    $flutter = Join-Path $Project '.fvm/flutter_sdk/bin/flutter.bat'
    $dart = Join-Path $Project '.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dart.exe'
    if (-not [IO.File]::Exists($flutter) -or -not [IO.File]::Exists($dart)) { throw '项目 FVM SDK 不完整，请通过版本管理入口修复。' }
    return [pscustomobject]@{ Flutter = $flutter; Dart = $dart }
}

function Repair-JobsToolsAndroidSdk {
    param([string]$Project)
    if (-not [IO.Directory]::Exists((Join-Path $Project 'android'))) { throw '本项目没有 android/ 平台目录。' }
    Write-Host ('修复 Android SDK / platforms 缺失；项目：' + $Project)
    Write-Host '补齐官方 SDK、Java 与构建组件；许可由本人确认，只更新项目 local.properties，不修改全局 Flutter 或 PATH。'
    if ((Read-Host '回车继续，任意非空输入取消') -ne '') { return }
    $support = Import-Module (Join-Path $PSScriptRoot 'Actions/android-support/Scripts/Action.psm1') -PassThru -DisableNameChecking
    & $support {
        param($Project)
        [void](Get-JobsAndroidArchitecture)
        $sdk = Get-JobsAndroidSdk
        $localConfig = Join-Path $Project 'android/local.properties'
        if ([IO.File]::Exists($localConfig)) {
            if ((Get-Item -LiteralPath $localConfig).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'local.properties 是链接。' }
            if ([IO.File]::ReadAllText($localConfig) -match '(?m)^\s*sdk\.dir\s*=\s*(.+)$') {
                $sdk = [regex]::Replace($Matches[1].TrimEnd("`r"), '\\([\\:=#! ])', '$1')
                if (-not [IO.Path]::IsPathRooted($sdk)) { throw '项目 sdk.dir 必须是绝对路径。' }
            }
        }
        [void][IO.Directory]::CreateDirectory($sdk)
        $java = Get-JobsAndroidJava
        $tools = Get-JobsAndroidHealthyTools $sdk $java
        $listing = Invoke-JobsAndroidTool $java $tools 'sdkmanager' @(('--sdk_root=' + $sdk), '--list', '--channel=0') -TimeoutSeconds 120
        $api = $null
        foreach ($relative in @('android/app/build.gradle', 'android/app/build.gradle.kts', '.fvm/flutter_sdk/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt')) {
            $source = Join-Path $Project $relative
            if ([IO.File]::Exists($source) -and [IO.File]::ReadAllText($source) -match 'compileSdk(?:Version)?\s*(?:=\s*)?(\d+)') { $api = $Matches[1]; break }
        }
        if (-not $api) {
            $apis = @([regex]::Matches($listing, '(?m)^\s*platforms;android-(\d+)\s*\|') | ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object)
            if ($apis.Count -eq 0) { throw '无法确定稳定 Android platform。' }
            $api = [string]$apis[-1]
        }
        $builds = @([regex]::Matches($listing, '(?m)^\s*build-tools;(\d+\.\d+\.\d+)\s*\|') | ForEach-Object { [version]$_.Groups[1].Value } | Sort-Object)
        if ($builds.Count -eq 0) { throw '无法确定稳定 build-tools。' }
        $build = [string]$builds[-1]
        foreach ($relative in @('android/app/build.gradle', 'android/app/build.gradle.kts')) {
            $source = Join-Path $Project $relative
            if ([IO.File]::Exists($source) -and [IO.File]::ReadAllText($source) -match 'buildToolsVersion\s*(?:=\s*)?["''](\d+\.\d+\.\d+)') { $build = $Matches[1]; break }
        }
        $required = @{
            'platform-tools' = 'platform-tools/adb.exe'
            ('platforms;android-' + $api) = ('platforms/android-' + $api + '/android.jar')
            ('build-tools;' + $build) = ('build-tools/' + $build + '/aapt2.exe')
        }
        foreach ($package in ($required.Keys | Sort-Object)) {
            if (-not [IO.File]::Exists((Join-Path $sdk $required[$package]))) {
                Invoke-JobsAndroidTool $java $tools 'sdkmanager' @(('--sdk_root=' + $sdk), '--install', $package, '--channel=0') -Interactive
            }
            if (-not [IO.File]::Exists((Join-Path $sdk $required[$package]))) { throw ('组件安装后复检失败：' + $package) }
        }
        $config = Join-Path $Project 'android/local.properties'
        $before = ''
        if ([IO.File]::Exists($config)) {
            if ((Get-Item -LiteralPath $config).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'local.properties 是链接，未写入。' }
            $before = [IO.File]::ReadAllText($config)
        }
        $backup = Join-Path $Project ('android/.jobs-sdk-backup-' + [guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($backup)
        [IO.File]::WriteAllText((Join-Path $backup 'local.properties'), $before, (New-Object Text.UTF8Encoding($false)))
        $next = [regex]::Replace($before, '(?m)^sdk\.dir\s*=.*(?:\r?\n|$)', '')
        $escaped = $sdk.Replace('\', '\\').Replace(':', '\:').Replace(' ', '\ ')
        $next = $next.TrimEnd("`r", "`n") + "`r`nsdk.dir=" + $escaped + "`r`n"
        [IO.File]::WriteAllText($config, $next, (New-Object Text.UTF8Encoding($false)))
        Write-Host ('SDK 组件已验证，项目 sdk.dir 已修复；备份：' + $backup)
    } $Project
}

function Invoke-JobsFeature {
    param([string]$Target, [ValidateSet('run','pub-get','extract','export-private-dependencies','import-private-dependencies','import-dependencies','sdk-version','sdk-manage','ohos-sdk-manage','java-manage','android-dependencies','ohos-dependencies','native-dependencies','flutter-precache','web-dependencies','export-gradle-dependencies','import-gradle-dependencies','export-ohos-dependencies','import-ohos-dependencies','export-native-dependencies','import-native-dependencies','export-precache-dependencies','import-precache-dependencies','export-web-dependencies','import-web-dependencies','gradle-download','project-setup','package','build-harmony','codegen','native-doctor','harmony-doctor','maintenance','repair-android','repair-imports','repair-namespace')][string]$Action)
    $project = Resolve-JobsTarget $Target
    if (-not [IO.File]::Exists((Join-Path $project 'pubspec.yaml')) -or ($Action -notin @('import-dependencies','import-private-dependencies') -and -not [IO.Directory]::Exists((Join-Path $project 'lib')))) { throw '请选择 Flutter 工程根目录。' }
    if ($Action -in @('export-private-dependencies','import-private-dependencies')) {
        $workerAction = if ($Action -eq 'export-private-dependencies') { 'extract' } else { 'import-dependencies' }
        $worker = Import-Module (Join-Path $PSScriptRoot ('Actions/' + $workerAction + '/Scripts/Action.psm1')) -PassThru -DisableNameChecking
        & $worker { param($Path) Invoke-JobsFeature -Target $Path -PrivateOnly } $project
        return
    }
    if ($Action -cmatch '^(export|import)-(gradle|ohos|native|precache|web)-dependencies$') {
        $setup = Import-Module (Join-Path $PSScriptRoot 'ProjectSetup.psm1') -PassThru -DisableNameChecking
        & $setup { param($p,$a) Invoke-JobsProjectDependencyArchiveAction -Target $p -Action $a } $project $Action
        return
    }
    if ($Action -in @('pub-get','android-dependencies','ohos-dependencies','native-dependencies','flutter-precache','web-dependencies')) {
        $setup = Import-Module (Join-Path $PSScriptRoot 'ProjectSetup.psm1') -PassThru -DisableNameChecking
        & $setup { param($p,$a) Invoke-JobsProjectDependencyAction -Target $p -Action $a } $project $Action
        return
    }
    if ($Action -in @('project-setup','gradle-download','java-manage')) {
        $setup = Import-Module (Join-Path $PSScriptRoot 'ProjectSetup.psm1') -PassThru -DisableNameChecking
        & $setup { param($p,$a) Invoke-JobsProjectSetupAction -Target $p -Action $a } $project $Action
        return
    }
    if ($Action -eq 'build-harmony') {
        $packager = Import-Module (Join-Path $PSScriptRoot 'Actions/package/Scripts/Action.psm1') -PassThru -DisableNameChecking
        & $packager { param($Path) Invoke-JobsFlutterHarmonyAction -Target $Path } $project
        return
    }
    if ($Action -eq 'ohos-sdk-manage') {
        $harmony = Import-Module (Join-Path $PSScriptRoot 'HarmonySdk.psm1') -PassThru -DisableNameChecking
        & $harmony { param($Path) Invoke-JobsHarmonySdkAction -Target $Path } $project
        return
    }
    if ($Action -eq 'sdk-manage') {
        $harmony = Import-Module (Join-Path $PSScriptRoot 'HarmonySdk.psm1') -PassThru -DisableNameChecking
        if (& $harmony { param($Path) Test-JobsManagedHarmonyBinding $Path } $project) {
            & $harmony { param($Path) Invoke-JobsNativeSdkFromHarmony -Target $Path } $project
            return
        }
    }
    if ($Action -ne 'sdk-manage') { $sdk = Get-JobsToolsFvm $project }
    if ($Action -in @('native-doctor','harmony-doctor','repair-imports','repair-namespace','maintenance')) {
        & $sdk.Dart (Join-Path $PSScriptRoot 'FlutterProjectTools.dart') $Action $project
        if ($LASTEXITCODE -ne 0) { throw ('Flutter 工具返回失败：' + $LASTEXITCODE) }
        return
    }
    if ($Action -eq 'repair-android') { Repair-JobsToolsAndroidSdk $project; return }
    $modulePath = Join-Path $PSScriptRoot ('Actions/' + $Action + '/Scripts/Action.psm1')
    $worker = Import-Module $modulePath -PassThru -DisableNameChecking
    & $worker { param($Path) Invoke-JobsFeature -Target $Path } $project
}
Export-ModuleMember -Function Invoke-JobsFeature

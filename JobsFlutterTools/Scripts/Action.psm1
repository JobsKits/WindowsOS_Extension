# Unified Flutter menu actions. Project-local FVM only; never install or select global Flutter.

# Jobs enter-choice emphasis is display-only; input and business decisions stay with callers.
function Test-JobsEnterChoiceColor {
    if ((Test-Path Env:NO_COLOR) -or $env:TERM -ieq 'dumb' -or $env:PLAIN_OUTPUT -eq '1') { return $false }
    $consoleType = [Console]
    if ($null -eq $consoleType.GetProperty('IsInputRedirected') -or $null -eq $consoleType.GetProperty('IsOutputRedirected')) { return $false }
    return ($Host.Name -ceq 'ConsoleHost' -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected)
}
# Older hosts keep native colors without sending unsupported bold escape sequences.
function Test-JobsEnterChoiceBold {
    $property = $Host.UI.PSObject.Properties['SupportsVirtualTerminal']
    return ($null -ne $property -and [bool]$property.Value)
}
# Separate ordinary question text from Enter and arbitrary-input options without changing words.
function Get-JobsEnterChoiceParts {
    param([string]$Text)
    $red = '(?:(?:\u8f93\u5165)?(?:\u4efb\u610f(?:\u975e\u7a7a)?(?:\u5b57\u7b26|\u5185\u5bb9|\u6587\u5b57|\u8f93\u5165)?|\u975e\u7a7a(?:\u8f93\u5165|\u5b57\u7b26|\u5185\u5bb9)?|(?:\u5176\u5b83|\u5176\u4ed6)(?:\u975e\u7a7a)?(?:\u8f93\u5165|\u5185\u5bb9|\u5b57\u7b26)?))|(?:any\s+(?:(?:other|non[- ]empty)\s+)?(?:input|text|characters?)|non[- ]empty\s+input)'
    $green = '(?:(?:\u76f4\u63a5|\u53ea\u9700|\u4ec5(?:\u9700)?|\u6309(?:\u4e0b)?|\u7a7a)?\s*\u56de\u8f66|(?:press\s+)?\bEnter\b(?!\s+(?:YES|REPAIR|CLEAN|CONTINUE)\b))'
    $pattern = '(?is)(?<red>(?:' + $red + ')[^;\uFF1B\r\n]*?(?=[;\uFF1B\r\n]|\z))|(?<green>(?:' + $green + ')[^;\uFF1B\r\n]*?(?=(?:' + $red + ')|[;\uFF1B\r\n]|\z))'
    $offset = 0
    foreach ($match in [regex]::Matches($Text, $pattern)) {
        if ($match.Index -gt $offset) { [pscustomobject]@{ Text = $Text.Substring($offset, $match.Index - $offset); Color = '' } }
        $prefix = [regex]::Split($Text.Substring(0, $match.Index), '[;\uFF1B\r\n]')[-1]
        $typed = $prefix -match '(?i)(?:\u8f93\u5165|\u952e\u5165|type|enter)\s*(?:\u5927\u5199\s*)?(?:YES|REPAIR|CLEAN|CONTINUE)\b|\u7cbe\u786e\u8f93\u5165|\u8f93\u5165[^;\uFF1B\r\n]*[\u540e\u518d]\s*$'
        $color = if ($match.Groups['red'].Success) { 'Red' } elseif ($typed) { '' } else { 'Green' }
        [pscustomobject]@{ Text = $match.Value; Color = $color }
        $offset = $match.Index + $match.Length
    }
    if ($offset -lt $Text.Length) { [pscustomobject]@{ Text = $Text.Substring($offset); Color = '' } }
}
# Native host text remains plain in information streams and logs; bold control is console-only.
function Write-JobsEnterChoiceText {
    [CmdletBinding()]
    param([Parameter(Position=0)][AllowNull()][object]$Object, [switch]$NoNewline, [ConsoleColor]$ForegroundColor, [ConsoleColor]$BackgroundColor, [object]$Separator = ' ')
    $text = if ($Object -is [array]) { $Object -join [string]$Separator } else { [string]$Object }
    if (-not (Test-JobsEnterChoiceColor)) {
        Write-Host $Object -NoNewline:$NoNewline -Separator $Separator
        return
    }
    $normal = @{}
    if ($PSBoundParameters.ContainsKey('ForegroundColor')) { $normal.ForegroundColor = $ForegroundColor }
    if ($PSBoundParameters.ContainsKey('BackgroundColor')) { $normal.BackgroundColor = $BackgroundColor }
    foreach ($part in @(Get-JobsEnterChoiceParts $text)) {
        if (-not $part.Color) { Write-Host $part.Text -NoNewline @normal; continue }
        $bold = Test-JobsEnterChoiceBold
        if ($bold) { [Console]::Write(([string][char]27) + '[1m') }
        try { Write-Host $part.Text -ForegroundColor $part.Color -NoNewline }
        finally { if ($bold) { [Console]::Write(([string][char]27) + '[0m') } }
    }
    if (-not $NoNewline) { Write-Host }
}
# Delegate the original reader, including secure input and EOF behavior, after prompt display.
function Read-JobsEnterChoiceHost {
    [CmdletBinding()]
    param([Parameter(Position=0)][string]$Prompt, [switch]$AsSecureString, [switch]$MaskInput)
    if ($AsSecureString -or $MaskInput -or -not (Test-JobsEnterChoiceColor) -or @((Get-JobsEnterChoiceParts $Prompt) | Where-Object { $_.Color }).Count -eq 0) {
        return (Read-Host @PSBoundParameters)
    }
    Write-JobsEnterChoiceText ($Prompt + ': ') -NoNewline
    return (Read-Host)
}

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
    if ((Read-JobsEnterChoiceHost '回车继续，任意非空输入取消') -ne '') { return }
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
    param([string]$Target, [ValidateSet('run','pub-get','extract','export-private-dependencies','import-private-dependencies','export-all-dependencies','import-all-dependencies','import-dependencies','sdk-version','sdk-manage','ohos-sdk-manage','java-manage','android-dependencies','ohos-dependencies','native-dependencies','flutter-precache','web-dependencies','export-gradle-dependencies','import-gradle-dependencies','export-ohos-dependencies','import-ohos-dependencies','export-native-dependencies','import-native-dependencies','export-precache-dependencies','import-precache-dependencies','export-web-dependencies','import-web-dependencies','gradle-download','project-setup','package','build-harmony','codegen','native-doctor','harmony-doctor','maintenance','repair-android','repair-imports','repair-namespace')][string]$Action)
    $project = Resolve-JobsTarget $Target
    if (-not [IO.File]::Exists((Join-Path $project 'pubspec.yaml')) -or ($Action -notin @('import-dependencies','import-private-dependencies','export-all-dependencies','import-all-dependencies') -and -not [IO.Directory]::Exists((Join-Path $project 'lib')))) { throw '请选择 Flutter 工程根目录。' }
    if ($Action -in @('export-all-dependencies','import-all-dependencies')) {
        $migration = Import-Module (Join-Path $PSScriptRoot 'FlutterDependencyMigration.psm1/FlutterDependencyMigration.psm1') -PassThru -DisableNameChecking
        & $migration { param($p,$a) Invoke-JobsFlutterMigration -Project $p -Action $a } $project $Action
        return
    }
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

# IDEProject.Tests.ps1 | Jobs IDE menu and dispatch boundaries
# Created by Jobs on 2026年10月26日，星期一.
# Real temporary directories and stubbed launchers; no IDE or user project is opened.
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$temporaryRoot = [IO.Path]::GetTempPath()
if ([IO.Directory]::Exists('/private/tmp')) { $temporaryRoot = '/private/tmp' }
$temporary = Join-Path $temporaryRoot ('JobsIDEProjects-' + [guid]::NewGuid().ToString('N'))
$script:count = 0
function Assert { param([bool]$Value, [string]$Why); if (-not $Value) { throw ('FAIL: ' + $Why) }; $script:count++ }
function Write-File { param([string]$Path, [string]$Text); [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path)); [IO.File]::WriteAllText($Path, $Text) }
function New-Case { param([string]$Name, [hashtable]$Files); $path = Join-Path $temporary $Name; [void][IO.Directory]::CreateDirectory($path); foreach ($relative in $Files.Keys) { Write-File (Join-Path $path $relative) $Files[$relative] }; return $path }
$android = Import-Module (Join-Path $root 'JobsAndroidStudioOpener/Scripts/Action.psm1') -PassThru -DisableNameChecking
$vscode = Import-Module (Join-Path $root 'JobsVSCodeOpener/Scripts/Action.psm1') -PassThru -DisableNameChecking
function Check {
    param([string]$Path, [bool]$AndroidExpected, [bool]$VSCodeExpected, [string]$Why)
    $actualAndroid = & $android { param($Path) Test-JobsIDEProject -Directory $Path -IDE android-studio } $Path
    $actualVSCode = & $vscode { param($Path) Test-JobsIDEProject -Directory $Path -IDE vscode } $Path
    Assert ($actualAndroid -eq $AndroidExpected) ('AndroidStudio: ' + $Why)
    Assert ($actualVSCode -eq $VSCodeExpected) ('VSCode: ' + $Why)
}
try {
    [void][IO.Directory]::CreateDirectory($temporary)
    $empty = New-Case empty @{}; Check $empty $false $false 'empty folder'
    $noise = New-Case noise @{ '.DS_Store' = 'metadata'; 'Thumbs.db' = 'metadata'; 'desktop.ini' = 'metadata' }; Check $noise $false $false 'metadata-only folder'
    $plain = New-Case plain @{ 'README.md' = 'notes' }; Check $plain $false $true 'ordinary nonempty folder'
    $hidden = New-Case hidden @{}; [void][IO.Directory]::CreateDirectory((Join-Path $hidden '.git')); Check $hidden $false $true 'meaningful hidden entry counts as nonempty'
    $flutter = New-Case flutter @{ 'pubspec.yaml' = "name: sample`ndependencies:`n  flutter:`n    sdk: flutter`n" }; Check $flutter $true $true 'official Flutter root'
    Write-File (Join-Path $flutter 'ios/Runner.xcodeproj/project.pbxproj') 'SDKROOT = iphoneos;'; Check $flutter $true $true 'Flutter root containing iOS subproject'
    $harmony = New-Case harmony @{ 'pubspec.yaml' = 'dependencies: {flutter: {sdk: flutter}}'; 'ohos/build-profile.json5' = '{}' }; Check $harmony $true $true 'OpenHarmony Flutter root'
    $index = 0
    foreach ($source in @("description: 'dependencies flutter sdk flutter'`n", "dev_dependencies:`n  flutter_test:`n    sdk: flutter`n", "dependencies:`n  flutter:`n    sdk: dart`n", "dependencies: {flutter: {sdk: flutter}}`ndependencies: {}`n")) {
        $index++; Check (New-Case ('invalid-' + $index) @{ 'pubspec.yaml' = $source }) $false $true 'invalid or misleading Flutter manifest'
    }
    $native = New-Case android @{ 'settings.gradle' = "rootProject.name='fixture'"; 'build.gradle' = "plugins { id 'com.android.application' }" }; Check $native $true $true 'native Android root'
    $kotlin = New-Case kotlin @{ 'settings.gradle.kts' = 'include(":app")'; 'app/build.gradle.kts' = 'plugins { id("com.android.library") }' }; Check $kotlin $true $true 'Android module plugin under current settings root'
    $manifest = New-Case manifest @{ 'settings.gradle' = "include ':app'"; 'app/build.gradle' = 'android {}'; 'app/src/main/AndroidManifest.xml' = '<manifest />' }; Check $manifest $true $true 'Android application manifest evidence'
    Check (New-Case java @{ 'settings.gradle' = "rootProject.name='java'"; 'build.gradle' = "plugins { id 'java' }" }) $false $true 'ordinary Gradle is not Android'
    Check (New-Case comment @{ 'settings.gradle' = "rootProject.name='java'"; 'build.gradle' = "// id 'com.android.application'`n/* apply plugin: 'com.android.library' */`ndescription = 'com.android.application';" }) $false $true 'Gradle comments and plain description are not Android plugin declarations'
    Check (New-Case alias @{ 'settings.gradle' = "include ':app'"; 'app/build.gradle.kts' = 'plugins { alias(libs.plugins.android.application) }' }) $true $true 'Android version-catalog plugin alias'
    Check (New-Case noSettings @{ 'build.gradle' = "plugins { id 'com.android.application' }" }) $false $true 'only current root accepted, no settings root'
    $ios = New-Case ios @{ 'Demo.xcodeproj/project.pbxproj' = 'SDKROOT = iphoneos;' }; Check $ios $false $false 'iOS project excluded from VSCode'
    Check (New-Case simulator @{ 'Demo.xcodeproj/project.pbxproj' = 'SUPPORTED_PLATFORMS = "iphonesimulator";' }) $false $false 'iPhone simulator-only project'
    Check (New-Case mac @{ 'Demo.xcodeproj/project.pbxproj' = 'SDKROOT = macosx;' }) $false $true 'macOS Xcode project is not iOS'
    Check (New-Case swiftPackage @{ 'Package.swift' = '.iOS(.v17)' }) $false $true 'pure Swift package is not inferred as iOS Xcode project'
    Check (New-Case nested @{ 'ios/Demo.xcodeproj/project.pbxproj' = 'SDKROOT = iphoneos;' }) $false $true 'generic parent does not inherit a child project type'
    Check (New-Case workspace @{ 'Demo.xcworkspace/contents.xcworkspacedata' = '<Workspace><FileRef location="group:Child/Demo.xcodeproj" /></Workspace>'; 'Child/Demo.xcodeproj/project.pbxproj' = 'SDKROOT = iphoneos;' }) $false $false 'workspace explicit project reference'
    Check (New-Case unicode @{ 'Demo.xcworkspace/contents.xcworkspacedata' = '<FileRef location="group:中文 &amp; file/Demo.xcodeproj" />'; '中文 & file/Demo.xcodeproj/project.pbxproj' = 'SDKROOT = iphoneos;' }) $false $false 'workspace Unicode and XML entities'
    [void](New-Case siblingApp @{ 'Demo.xcodeproj/project.pbxproj' = 'SDKROOT = iphoneos;' })
    Check (New-Case siblingWorkspace @{ 'Demo.xcworkspace/contents.xcworkspacedata' = '<FileRef location="group:../siblingApp/Demo.xcodeproj" />' }) $false $false 'workspace explicit parent-relative project association'
    Check (New-Case largeIOS @{ 'Demo.xcodeproj/project.pbxproj' = (('x' * 1048577) + 'SDKROOT = iphoneos;') }) $false $false 'oversized iOS metadata is unknown rather than non-iOS'
    Check (New-Case largeWorkspace @{ 'Demo.xcworkspace/contents.xcworkspacedata' = ('x' * 1048577) }) $false $false 'oversized workspace metadata does not admit VSCode'
    Check (Join-Path $plain 'README.md') $false $false 'selected file is never mapped to its parent'
    $bundle = New-Case bundle @{ 'Tool.app/Contents/Info.plist' = 'metadata' }; Check (Join-Path $bundle 'Tool.app') $false $false 'application bundle excluded'
    foreach ($entry in @(@($android, $native, 'Get-JobsAndroidStudio', 'studio.exe'), @($vscode, $plain, 'Get-JobsVSCode', 'code.exe'))) {
        $module = $entry[0]; $path = $entry[1]
        & $module {
            $script:starts = 0
            function script:Get-JobsAndroidStudio { return 'studio.exe' }
            function script:Get-JobsVSCode { return 'code.exe' }
            function script:Start-JobsApplication { param($Executable, $Arguments, $Directory); $script:starts++; $script:opened = $Directory }
        }
        & $module { param($Path) Invoke-JobsFeature -Target $Path } $path
        Assert ((& $module { $script:starts }) -eq 1) 'eligible directory reaches only the stubbed IDE launcher'
        $rejected = $false
        try { & $module { param($Path) Invoke-JobsFeature -Target $Path } $empty } catch { $rejected = $true }
        Assert ($rejected -and (& $module { $script:starts }) -eq 1) 'empty directory rejected before IDE lookup/open'
    }
    foreach ($name in @('JobsAndroidStudioOpener', 'JobsVSCodeOpener')) {
        $package = Join-Path $root $name
        $installer = Import-Module (Join-Path $package 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
        $manifest = Get-Content -LiteralPath (Join-Path $package 'Extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $plan = @(& $installer { param($Manifest) Get-JobsPackageRegistryPlan $Manifest '/temporary/release' 'powershell.exe' } $manifest)
        Assert ($plan.Count -eq 8 -and @($plan | Where-Object Enabled).Count -eq 4) 'native directory/background/drive handler plus CLSID, four old static entries retired'
        Assert (@($plan | Where-Object { -not $_.Enabled -and $_.Key.Contains('\shell\Jobs.WindowsExtension.' + $manifest.Id) }).Count -eq 4) 'migration removes only this package legacy static scopes'
        Assert (@($plan | Where-Object { $_.Enabled -and $_.PSObject.Properties['InProcServer'] -and $_.InProcServer.EndsWith('bin/' + $name + 'ContextMenu.dll') }).Count -eq 1) 'own native binary name'
        $build = [IO.File]::ReadAllText((Join-Path $package 'Scripts/Build.ps1'))
        foreach ($source in [regex]::Matches($build, 'Join-Path \$scripts ''([^'']+\.(?:cs|cpp|def))''')) {
            Assert ([IO.File]::Exists((Join-Path $package ('Scripts/' + $source.Groups[1].Value)))) 'every declared native build source is shipped in its own package'
        }
    }
    foreach ($file in @('IDEProject.h', 'IDEProject.cs', 'ProjectEligibility.ps1', 'FlutterProject.h')) {
        Assert ((Get-FileHash -LiteralPath (Join-Path $root ('JobsAndroidStudioOpener/Scripts/' + $file))).Hash -ceq (Get-FileHash -LiteralPath (Join-Path $root ('JobsVSCodeOpener/Scripts/' + $file))).Hash) 'independent packages carry the same project policy'
    }
    Write-Host ('PASS: IDEProject (' + $script:count + ' assertions; no IDE launched)')
} finally {
    Remove-Module $android, $vscode -ErrorAction SilentlyContinue
    if ([IO.Directory]::Exists($temporary)) { [IO.Directory]::Delete($temporary, $true) }
}

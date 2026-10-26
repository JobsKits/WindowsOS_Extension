# 只在临时工程中运行实际清理逻辑，不安装菜单、不修改注册表。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$temporaryBase = [IO.Path]::GetTempPath()
if ([IO.Directory]::Exists('/private/tmp')) { $temporaryBase = '/private/tmp' }
$temporary = Join-Path $temporaryBase ('JobsClean [中文] '' & ' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$script:checks = 0
function Assert-Clean {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
    $script:checks++
}
function New-CleanFile {
    param([string]$Root, [string]$Relative, [string]$Text = 'keep')
    $path = Join-Path $Root $Relative
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
    [IO.File]::WriteAllText($path, $Text)
}
function New-CleanFlutter {
    param([string]$Root)
    New-CleanFile $Root 'pubspec.yaml' "name: demo`ndependencies:`n  flutter:`n    sdk: flutter`n"
    New-CleanFile $Root 'lib/main.dart'
}
function New-CleanAndroid {
    param([string]$Root)
    New-CleanFile $Root 'settings.gradle.kts' 'include(":app", ":feature:chat")'
    New-CleanFile $Root 'app/build.gradle.kts' 'plugins { id("com.android.application") }'
    New-CleanFile $Root 'feature/chat/build.gradle' "apply plugin: 'com.android.library'"
}
$action = $null
$outside = Join-Path $temporaryBase ('JobsCleanOutside-' + [guid]::NewGuid().ToString('N'))
try {
    # 验证独立包：只复制本包，不可回退到父仓库。
    $package = Join-Path $temporary 'JobsBuildArtifactCleaner'
    Copy-Item -LiteralPath (Join-Path $repository 'JobsBuildArtifactCleaner') -Destination $package -Recurse
    $action = Import-Module (Join-Path $package 'Scripts/Action.psm1') -PassThru -DisableNameChecking
    & $action { function script:Read-Host { param($Prompt) 'CLEAN' } }
    $flutter = Join-Path $temporary 'Flutter project'
    New-CleanFlutter $flutter
    New-CleanAndroid (Join-Path $flutter 'android')
    $outputs = @('build/windows', '.dart_tool', 'android/build', 'android/.gradle', 'android/app/build', 'android/feature/chat/build', 'windows/flutter/ephemeral')
    foreach ($path in $outputs) { New-CleanFile $flutter ($path + '/artifact') }
    $preserved = @('build/ios/keep', 'build/macos/keep', 'pubspec.lock', 'ios/build/keep', 'ios/DerivedData/keep', 'ios/Flutter/ephemeral/keep', 'ios/Pods/source', 'ios/Podfile.lock', 'macos/Flutter/ephemeral/keep', 'android/local.properties', 'unknown/build/user.txt')
    foreach ($path in $preserved) { New-CleanFile $flutter $path }
    New-CleanFile $flutter 'ios/Demo.xcodeproj/project.pbxproj' 'SDKROOT = iphoneos;'
    $plan = & $action { param($Path) Get-JobsBuildCleanPlan $Path } $flutter
    Assert-Clean ($plan.Kind -ceq 'Flutter') 'Flutter 优先于其平台子工程'
    $trailing = & $action { param($Path) Get-JobsBuildCleanPlan $Path } ($flutter + [IO.Path]::DirectorySeparatorChar)
    Assert-Clean ($trailing.Root -ceq $plan.Root -and ($trailing.Paths -join ';') -ceq ($plan.Paths -join ';')) '末尾路径分隔符归一化，不扩大或阻止清理'
    foreach ($path in $outputs) { Assert-Clean (Test-Path -LiteralPath (Join-Path $flutter ($path + '/artifact'))) '预览不删除文件' }
    & $action { param($Path) Invoke-JobsFeature $Path } $flutter
    foreach ($path in $outputs) { Assert-Clean (-not (Test-Path -LiteralPath (Join-Path $flutter $path))) ('Flutter 产物已清理：' + $path) }
    foreach ($path in $preserved) { Assert-Clean (Test-Path -LiteralPath (Join-Path $flutter $path)) ('保留源码/锁文件及 Apple 平台：' + $path) }
    Assert-Clean (Test-Path -LiteralPath (Join-Path $flutter 'lib/main.dart')) 'Flutter 源码保留'
    & $action { param($Path) Invoke-JobsFeature $Path } $flutter

    $android = Join-Path $temporary 'Android project'
    New-CleanAndroid $android
    $outputs = @('build', '.gradle', '.kotlin', 'app/build', 'feature/chat/build', 'feature/chat/.cxx', 'app/.externalNativeBuild')
    foreach ($path in $outputs) { New-CleanFile $android ($path + '/artifact') }
    New-CleanAndroid (Join-Path $android 'independent')
    New-CleanFile $android 'independent/app/build/keep'
    New-CleanFile $android 'gradle/wrapper/gradle-wrapper.properties'
    $plan = & $action { param($Path) Get-JobsBuildCleanPlan $Path } $android
    Assert-Clean ($plan.Kind -ceq 'Android') '识别 Kotlin DSL Android 多模块'
    & $action { param($Path) Invoke-JobsFeature $Path } $android
    foreach ($path in $outputs) { Assert-Clean (-not (Test-Path -LiteralPath (Join-Path $android $path))) ('Android 产物已清理：' + $path) }
    Assert-Clean (Test-Path -LiteralPath (Join-Path $android 'independent/app/build/keep')) '嵌套独立工程保留'
    Assert-Clean (Test-Path -LiteralPath (Join-Path $android 'gradle/wrapper/gradle-wrapper.properties')) 'Gradle wrapper 保留'

    $alias = Join-Path $temporary 'Alias Android'
    New-CleanFile $alias 'settings.gradle.kts'
    New-CleanFile $alias 'app/build.gradle.kts' 'plugins { alias(libs.plugins.android.application) }'
    New-CleanFile $alias 'app/src/main/AndroidManifest.xml' '<manifest/>'
    Assert-Clean ((& $action { param($Path) Get-JobsBuildCleanPlan $Path } $alias).Kind -ceq 'Android') '版本目录插件通过 Android Manifest 识别'

    foreach ($kind in @('unknown', 'java', 'ios', 'comment')) {
        $invalid = Join-Path $temporary $kind
        New-CleanFile $invalid 'build/keep'
        if ($kind -eq 'java') { New-CleanFile $invalid 'build.gradle' 'plugins { id("java") }' }
        if ($kind -eq 'ios') { New-CleanFile $invalid 'Demo.xcodeproj/project.pbxproj' 'SDKROOT = iphoneos;' }
        if ($kind -eq 'comment') { New-CleanFile $invalid 'build.gradle' '/* com.android.application */' }
        $rejected = $false
        try { & $action { param($Path) Invoke-JobsFeature $Path } $invalid } catch { $rejected = $true }
        Assert-Clean $rejected ('拒绝不支持的工程：' + $kind)
        Assert-Clean (Test-Path -LiteralPath (Join-Path $invalid 'build/keep')) '识别失败零删除'
    }
    foreach ($invalid in @($temporary, (Join-Path $flutter 'lib'))) {
        $rejected = $false
        try { & $action { param($Path) Invoke-JobsFeature $Path } $invalid } catch { $rejected = $true }
        Assert-Clean $rejected '不向上或向下寻找其它工程根目录'
    }

    $flutter = Join-Path $temporary 'Flutter link project'
    New-CleanFlutter $flutter
    New-CleanFile $flutter 'build/keep'
    & $action { function script:Read-Host { param($Prompt) 'no' } }
    & $action { param($Path) Invoke-JobsFeature $Path } $flutter
    Assert-Clean (Test-Path -LiteralPath (Join-Path $flutter 'build/keep')) '取消清理保留全部产物'
    & $action { function script:Read-Host { param($Prompt) 'CLEAN' } }
    New-CleanFile $outside 'keep'
    $linkType = 'SymbolicLink'
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { $linkType = 'Junction' }
    $linkTarget = $outside
    if ($PSVersionTable.PSVersion.Major -eq 5) { $linkTarget = [Management.Automation.WildcardPattern]::Escape($outside) }
    [void](New-Item -ItemType $linkType -Path (Join-Path $flutter '.dart_tool') -Target $linkTarget)
    $rejected = $false
    try { & $action { param($Path) Invoke-JobsFeature $Path } $flutter } catch { $rejected = $true }
    Assert-Clean $rejected '清理目标是符号链接或联接时拒绝'
    Assert-Clean (Test-Path -LiteralPath (Join-Path $flutter 'build/keep')) '先验证全部路径再删除'
    [IO.Directory]::Delete((Join-Path $flutter '.dart_tool'))
    [void](New-Item -ItemType $linkType -Path (Join-Path $flutter 'build/link') -Target $linkTarget)
    & $action { param($Path) Invoke-JobsFeature $Path } $flutter
    Assert-Clean (Test-Path -LiteralPath (Join-Path $outside 'keep')) '产物内链接只删除链接，不跟随到外部目录'
    Assert-Clean (-not (Test-Path -LiteralPath (Join-Path $flutter 'build'))) '含内部链接的产物正常移除'
    New-CleanFile $flutter 'build' 'user file'
    $rejected = $false
    try { & $action { param($Path) Invoke-JobsFeature $Path } $flutter } catch { $rejected = $true }
    Assert-Clean $rejected 'build 同名普通文件不能删除'
    Assert-Clean ([IO.File]::ReadAllText((Join-Path $flutter 'build')) -ceq 'user file') '同名文件内容保留'
    Write-Host ('PASS: BuildArtifactCleaner.Tests.ps1 (' + $script:checks + ' assertions)')
} finally {
    if ($null -ne $action) { Remove-Module $action }
    Remove-Item -LiteralPath $temporary -Recurse -Force
    if (Test-Path -LiteralPath $outside) { Remove-Item -LiteralPath $outside -Recurse -Force }
}

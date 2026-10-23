# 清理构建产物：精确识别当前 Flutter / Android 工程；Windows 没有 iOS 清理分支。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking

function Test-JobsCleanItem {
    param([string]$Path, [bool]$Directory = $false)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force
    return ($item.PSIsContainer -eq $Directory -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)
}

function Assert-JobsCleanDirectory {
    param([string]$Path)
    if (-not [IO.Path]::IsPathRooted($Path) -or -not (Test-JobsCleanItem $Path $true)) { throw '目标必须是实际文件夹。' }
    $directory = New-Object IO.DirectoryInfo ([IO.Path]::GetFullPath($Path))
    $current = $directory
    while ($null -ne $current) {
        if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ('不处理链接或目录联接：' + $current.FullName) }
        $current = $current.Parent
    }
    $normalized = $directory.FullName.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if ($null -eq $directory.Parent -or $normalized -eq [Environment]::GetFolderPath('UserProfile').TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)) { throw '不能清理磁盘或用户主目录。' }
    return $normalized
}

function Test-JobsCleanGradle {
    param([string]$Directory)
    return ((Test-JobsCleanItem (Join-Path $Directory 'build.gradle')) -or (Test-JobsCleanItem (Join-Path $Directory 'build.gradle.kts')))
}

function Test-JobsCleanSettings {
    param([string]$Directory)
    return ((Test-JobsCleanItem (Join-Path $Directory 'settings.gradle')) -or (Test-JobsCleanItem (Join-Path $Directory 'settings.gradle.kts')))
}

function Get-JobsCleanGradleModules {
    param([string]$Directory)
    if (Test-JobsCleanGradle $Directory) {
        $android = Test-JobsCleanItem (Join-Path $Directory 'src/main/AndroidManifest.xml')
        foreach ($name in @('build.gradle', 'build.gradle.kts')) {
            $file = Join-Path $Directory $name
            if (Test-JobsCleanItem $file) {
                $text = Get-Content -LiteralPath $file -Raw -Encoding UTF8
                $text = $text -replace '(?s)/\*.*?\*/', '' -replace '(?m)//.*$', ''
                if ($text -match 'com\.android\.(application|library|test|dynamic-feature|asset-pack)') { $android = $true }
            }
        }
        [pscustomobject]@{ Directory = $Directory; Android = $android }
    }
    foreach ($child in Get-ChildItem -LiteralPath $Directory -Directory -Force) {
        if ($child.Name.StartsWith('.') -or $child.Name -in @('build', 'node_modules', 'Pods', 'vendor', 'third_party', 'DerivedData') -or
            $child.Extension -in @('.xcodeproj', '.xcworkspace') -or ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        if ((Test-Path -LiteralPath (Join-Path $child.FullName '.git')) -or
            (Test-Path -LiteralPath (Join-Path $child.FullName 'pubspec.yaml')) -or (Test-JobsCleanSettings $child.FullName)) { continue }
        Get-JobsCleanGradleModules $child.FullName
    }
}

function Get-JobsCleanAndroidModules {
    param([string]$Directory)
    if (-not (Test-JobsCleanItem $Directory $true)) { return }
    if (-not (Test-JobsCleanGradle $Directory) -and -not (Test-JobsCleanSettings $Directory)) { return }
    $modules = @(Get-JobsCleanGradleModules $Directory)
    if (@($modules | Where-Object { $_.Android }).Count -gt 0) { $modules }
}

function Get-JobsCleanAndroidPaths {
    param([string]$Directory, [object[]]$Modules)
    foreach ($name in @('build', '.gradle', '.kotlin')) { Join-Path $Directory $name }
    foreach ($module in $Modules) {
        foreach ($name in @('build', '.cxx', '.externalNativeBuild')) { Join-Path $module.Directory $name }
    }
}

function Assert-JobsCleanPath {
    param([string]$Root, [string]$Path)
    $prefix = $Root.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not [IO.Path]::GetFullPath($Path).StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw ('产物路径超出工程：' + $Path) }
    $current = $Path
    while ($current -ne $Root) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ('拒绝清理链接路径：' + $current) }
            if (-not $item.PSIsContainer) { throw ('产物路径不是目录：' + $current) }
        }
        $current = Split-Path -Parent $current
    }
}

# Flutter 工程可能从 macOS 同步而来；已有 Apple 产物时只清理 build 下其它目录。
function Get-JobsCleanFlutterBuildPaths {
    param([string]$Root)
    $build = Join-Path $Root 'build'
    if (Test-JobsCleanItem $build $true) {
        $children = @(Get-ChildItem -LiteralPath $build -Force)
        if (@($children | Where-Object { $_.Name -in @('ios', 'macos') }).Count -gt 0) {
            foreach ($child in $children) {
                if ($child.PSIsContainer -and $child.Name -notin @('ios', 'macos')) { $child.FullName }
            }
            return
        }
    }
    $build
}

function Get-JobsBuildCleanPlan {
    param([string]$Target)
    $root = Assert-JobsCleanDirectory $Target
    $pubspec = Join-Path $root 'pubspec.yaml'
    $flutter = (Test-JobsCleanItem $pubspec) -and (Test-JobsCleanItem (Join-Path $root 'lib') $true)
    if ($flutter) { $flutter = (Get-Content -LiteralPath $pubspec -Raw -Encoding UTF8) -match '(?m)^[ \t]+sdk:[ \t]*flutter[ \t]*(?:#.*)?$' }
    $paths = @()
    if ($flutter) {
        $kind = 'Flutter'
        $paths += @(Get-JobsCleanFlutterBuildPaths $root)
        $paths += Join-Path $root '.dart_tool'
        $android = Join-Path $root 'android'
        $modules = @(Get-JobsCleanAndroidModules $android)
        if ($modules.Count -gt 0) { $paths += @(Get-JobsCleanAndroidPaths $android $modules) }
        foreach ($platform in @('windows', 'linux')) {
            if (Test-JobsCleanItem (Join-Path $root $platform) $true) { $paths += Join-Path $root ($platform + '/flutter/ephemeral') }
        }
    } else {
        $modules = @(Get-JobsCleanAndroidModules $root)
        if ($modules.Count -eq 0) { throw '未识别为当前层的 Flutter 或 Android 工程，未删除任何文件。Windows 不提供 iOS 工程清理。' }
        $kind = 'Android'
        $paths += @(Get-JobsCleanAndroidPaths $root $modules)
    }
    $existing = @()
    foreach ($path in @($paths | Select-Object -Unique)) {
        Assert-JobsCleanPath $root $path
        if (Test-Path -LiteralPath $path) { $existing += $path }
    }
    [pscustomobject]@{ Root = $root; Kind = $kind; Paths = $existing }
}

# 不使用 Remove-Item -Recurse 穿过联接。产物内部的重解析项只删除链接本身。
function Remove-JobsBuildTree {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        if ($item.PSIsContainer) { [IO.Directory]::Delete($item.FullName) }
        else { [IO.File]::Delete($item.FullName) }
        return
    }
    if ($item.PSIsContainer) {
        foreach ($child in Get-ChildItem -LiteralPath $Path -Force) { Remove-JobsBuildTree $child.FullName }
        [IO.Directory]::Delete($item.FullName)
    } else {
        $item.IsReadOnly = $false
        [IO.File]::Delete($item.FullName)
    }
}

function Invoke-JobsBuildCleanAction {
    param([string]$Directory)
    $plan = Get-JobsBuildCleanPlan $Directory
    Write-Host ('工程类型：' + $plan.Kind)
    Write-Host ('工程目录：' + $plan.Root)
    if ($plan.Paths.Count -eq 0) { Write-Host '没有可清理的构建产物。'; return }
    Write-Host '将删除以下工程内的构建产物（请先停止正在进行的构建）：'
    foreach ($path in $plan.Paths) { Write-Host ('  ' + $path) }
    if ((Read-Host '输入 CLEAN 确认清理，其它输入取消') -cne 'CLEAN') { Write-Host '已取消，未删除任何文件。'; return }
    # 确认后重新识别；工程或清理清单发生变化时要求重新运行。
    $fresh = Get-JobsBuildCleanPlan $plan.Root
    if ($fresh.Kind -cne $plan.Kind -or ($fresh.Paths -join "`n") -cne ($plan.Paths -join "`n")) { throw '工程或清理范围已变化，请重新运行。' }
    foreach ($path in $plan.Paths) {
        Assert-JobsCleanPath $plan.Root $path
        Remove-JobsBuildTree $path
    }
    Write-Host '构建产物清理完成。源码、锁文件、依赖与全局缓存保留。'
}

function Invoke-JobsFeature {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Target)
    Invoke-JobsBuildCleanAction -Directory (Resolve-JobsTarget $Target)
}

Export-ModuleMember -Function Invoke-JobsFeature

# Architecture.Tests.ps1 | WindowsOS@Extension 独立包架构回归
# Created by Jobs on 2026年10月18日，星期日.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'Scripts/Catalog.psm1') -Force -DisableNameChecking
$script:assertions = 0
function Assert-Architecture {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
    $script:assertions++
}
$packages = @(Get-JobsFeaturePackages -Root $root)
$parsedCatalog = Get-Content -LiteralPath (Join-Path $root 'Extensions.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$expectedCount = @($parsedCatalog).Count
Assert-Architecture ($packages.Count -eq $expectedCount) '登记的功能工程单独列出'
Assert-Architecture (@($packages.Name | Select-Object -Unique).Count -eq $expectedCount) '功能目录唯一'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('JobsStandalone-' + [guid]::NewGuid().ToString('N'))
$savedLocal = $env:LOCALAPPDATA
try {
    [void][IO.Directory]::CreateDirectory($temporary)
    $env:LOCALAPPDATA = Join-Path $temporary 'UserData'
    $roots = @()
    foreach ($package in $packages) {
        # 整个独立目录拷到一个没有父工程的临时位置，导入/打包时没有父目录可回退。
        $standalone = Join-Path $temporary $package.Name
        Copy-Item -LiteralPath $package.PackagePath -Destination $standalone -Recurse
        foreach ($name in @('Extension.json', 'Install.cmd', 'Uninstall.cmd', 'README.md', 'Scripts/Action.psm1')) {
            Assert-Architecture (Test-Path -LiteralPath (Join-Path $standalone $name) -PathType Leaf) ('独立交付文件齐全：' + $package.Id + '/' + $name)
        }
        foreach ($script in Get-ChildItem -LiteralPath (Join-Path $standalone 'Scripts') -File) {
            $source = Get-Content -LiteralPath $script.FullName -Raw
            Assert-Architecture ($source -notmatch '(?:\.\.[\\/])+(?:Scripts|Infrastructure|Jobs[A-Z])') ('包不引用父工程或其它功能：' + $script.Name)
        }
        if ($package.Id -eq 'harmony-simulator-create') {
            foreach ($name in @('Run.cmd', 'Scripts/Build.ps1', 'Scripts/ContextMenu.cpp', 'Scripts/DesktopScope.h', 'Scripts/CreateHarmonySimulator.ps1', 'Scripts/HarmonyTools.ps1')) {
                Assert-Architecture (Test-Path -LiteralPath (Join-Path $standalone $name) -PathType Leaf) ('鸿蒙独立运行与原生源码齐全：' + $name)
            }
            Assert-Architecture (@($package.InfrastructureOverrides).Count -eq 1 -and $package.InfrastructureOverrides[0] -ceq 'PackageInstaller.psm1') '鸿蒙安装器独立覆盖且保留其它基础设施模板'
        }
        $action = Import-Module (Join-Path $standalone 'Scripts/Action.psm1') -PassThru -DisableNameChecking
        Assert-Architecture ($action.ExportedCommands.ContainsKey('Invoke-JobsFeature')) ('独立业务可载入：' + $package.Id)
        $common = Import-Module (Join-Path $standalone 'Scripts/Common.psm1') -PassThru -DisableNameChecking
        $ownRoot = & $common { Get-JobsInstallRoot }
        $roots += $ownRoot
        Assert-Architecture ($ownRoot.EndsWith($package.Id, [StringComparison]::Ordinal)) ('运行状态归属于本包：' + $package.Id)
        $installer = Import-Module (Join-Path $standalone 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
        $release = Join-Path $temporary ('release-' + $package.Id)
        & $installer { param($Path, $Destination) New-JobsPackageRelease -PackagePath $Path -Destination $Destination } $standalone $release | Out-Null
        $plan = @(& $installer { param($Manifest, $Release, $PowerShell) Get-JobsPackageRegistryPlan -Manifest $Manifest -ReleasePath $Release -PowerShellPath $PowerShell -Enabled $true } $package $release (Join-Path $PSHOME 'powershell.exe'))
        $expected = 4
        if ($package.DirectoryOnly) { $expected = 3 }
        if ($package.Id -in @('flutter-run', 'flutter-package', 'flutter-doctor', 'flutter-codegen', 'git-rollback')) { $expected = 4 }
        if ($package.Id -in @('android-simulator-create', 'android-simulator-repair', 'harmony-simulator-create', 'harmony-simulator-repair')) { $expected = 2 }
        if ($package.Id -in @('run-authorize', 'run-authorization-revoke')) { $expected = 2 }
        if ($package.Id -eq 'git-proxy-configure') { $expected = 1 }
        if ($package.Id -eq 'flutter-tools') { $expected = 68 }
        Assert-Architecture ($plan.Count -eq $expected) ('本包只注册自己的上下文：' + $package.Id)
        foreach ($item in $plan) {
            if ($package.Id -eq 'flutter-tools') {
                if ($item.Enabled) {
                    Assert-Architecture ($item.Key.EndsWith('Jobs.WindowsExtension.flutter-tools') -or $item.Key.EndsWith('CLSID\{55C8C7A9-8625-4AF0-8598-DFA975064F0C}')) '统一 Flutter 只启用自己的处理器'
                } else {
                    Assert-Architecture ($item.Owner -eq 'Jobs.WindowsExtension.v1' -and $item.Key -match 'Jobs\.WindowsExtension\.flutter-(pub-get|version-manager|sdk-inspector|dependency-extract|run|package|doctor|codegen)$') '迁移只停用固定旧 Flutter 入口'
                }
                continue
            }
            if ($package.Id -in @('android-simulator-create', 'android-simulator-repair', 'harmony-simulator-create', 'harmony-simulator-repair')) {
                $clsid = '{9591D98B-3481-4E05-BE24-470FCDFD0E23}'
                if ($package.Id -eq 'android-simulator-repair') { $clsid = '{A6D8DCE0-B691-4CC9-A3C5-F02B8BC704E5}' }
                if ($package.Id -eq 'harmony-simulator-create') { $clsid = '{95E5B535-2EB8-48CA-98B5-A14D17A0A859}' }
                if ($package.Id -eq 'harmony-simulator-repair') { $clsid = '{C91A8F93-CA7B-4F28-B705-A0AC90C5F231}' }
                Assert-Architecture ($item.Key -eq ('Software\Classes\DesktopBackground\shellex\ContextMenuHandlers\Jobs.WindowsExtension.' + $package.Id) -or $item.Key -eq ('Software\Classes\CLSID\' + $clsid)) ('模拟器只注册桌面背景及本包 CLSID：' + $package.Id)
                if ($item.Key.EndsWith('CLSID\' + $clsid)) {
                    Assert-Architecture ($item.InProcServer -eq (Join-Path $release ('bin/' + $package.Name + 'ContextMenu.dll'))) ('原生 DLL 归属于本包 release：' + $package.Id)
                }
                continue
            }
            if ($package.Id -eq 'git-rollback') {
                Assert-Architecture ($item.Key.EndsWith('Jobs.WindowsExtension.git-rollback') -or $item.Key.EndsWith('CLSID\{E58D6868-A650-42EB-9629-E97338918229}')) 'Git 回退只注册自己的动态处理器和 CLSID'
                continue
            }
            if ($package.Id -in @('flutter-run', 'flutter-package', 'flutter-doctor', 'flutter-codegen')) {
                Assert-Architecture ($item.Key.EndsWith('Jobs.WindowsExtension.' + $package.Id) -or $item.Key.EndsWith('CLSID\{239D7884-83C5-4D66-AB0C-14A2667DCD61}') -or $item.Key.EndsWith('CLSID\{64A7C5BE-E031-4E89-A2D7-75C3F62B1AC9}') -or $item.Key.EndsWith('CLSID\{A41E939F-64E7-49DD-85FA-81F9B8CFD5E2}') -or $item.Key.EndsWith('CLSID\{DD71AE09-8A16-4B08-9868-5A40A9F39F63}')) '原生 COM 只注册本包处理器及 CLSID'
                continue
            }
            if ($package.Id -in @('run-authorize', 'run-authorization-revoke')) {
                $clsid = '{AE09A13F-EF17-4CE3-8BA1-F557C34280DE}'
                if ($package.Id -eq 'run-authorization-revoke') { $clsid = '{6AC50F49-6915-4130-8474-F99DA4D074D6}' }
                Assert-Architecture ($item.Key -eq ('Software\Classes\*\shellex\ContextMenuHandlers\Jobs.WindowsExtension.' + $package.Id) -or $item.Key -eq ('Software\Classes\CLSID\' + $clsid)) '权限包只注册普通文件动态处理器和自己的 CLSID'
                continue
            }
            Assert-Architecture ($item.Key.EndsWith('Jobs.WindowsExtension.' + $package.Id)) '菜单计划不包含其它功能'
            Assert-Architecture ($item.Command -notmatch '\s-Action\s' -and $item.Command -match 'Invoke\.ps1') '菜单直接启动本功能'
            Assert-Architecture ($item.Command.Contains($release)) '注册命令使用本包独立运行版本'
        }
        $copied = Get-Content -LiteralPath (Join-Path $release 'Extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-Architecture ($copied.Id -eq $package.Id) '部署只包含所选包的清单'
        $workers = if ($package.Id -eq 'flutter-tools') { 9 } else { 1 }
        Assert-Architecture (@(Get-ChildItem -LiteralPath $release -Recurse -File | Where-Object { $_.Name -eq 'Action.psm1' }).Count -eq $workers) '统一组包含自己的必要 worker，其它包只含单功能业务'
    }
    Assert-Architecture (@($roots | Select-Object -Unique).Count -eq $expectedCount) '登记的功能安装状态彼此独立'
    $single = @(Get-JobsPackageOperationPlan -Packages $packages -Selected @($packages[2].Id) -Installed @() -Mode Install)
    Assert-Architecture ($single.Count -eq 1 -and $single[0].Id -eq $packages[2].Id) '首次只选一项只部署一项'
    $configure = @(Get-JobsPackageOperationPlan -Packages $packages -Selected @($packages[2].Id) -Installed @($packages[0].Id, $packages[2].Id) -Mode Configure)
    Assert-Architecture ($configure.Count -eq 2 -and $configure[0].Mode -eq 'Uninstall' -and $configure[1].Mode -eq 'Install') '配置面板分开编排卸载和安装'
    $uninstall = @(Get-JobsPackageOperationPlan -Packages $packages -Selected @($packages[0].Id) -Installed @($packages[0].Id, $packages[2].Id) -Mode Uninstall)
    Assert-Architecture ($uninstall.Count -eq 1 -and $uninstall[0].Id -eq $packages[0].Id) '仅卸载选择的功能，保留其它已安装功能'
    $script:executed = @()
    $result = Invoke-JobsPackageOperations -Plan $single -Executor { param($Operation) $script:executed += $Operation.Id }
    Assert-Architecture ($result.Success -and $script:executed.Count -eq 1) '总入口只调用选中的独立安装器'
    $failure = Invoke-JobsPackageOperations -Plan @($single[0], $configure[0], $single[0]) -Executor {
        param($Operation)
        if ($Operation.Mode -eq 'Uninstall') { throw 'isolated package failure' }
    }
    Assert-Architecture (-not $failure.Success -and @($failure.Completed).Count -eq 1 -and $failure.Failed -eq $configure[0].Id) '失败停止并保留此前单包成功结果'
    foreach ($name in @('Worker.ps1', 'Invoke-Menu.ps1', 'Common.psm1')) {
        Assert-Architecture (-not (Test-Path -LiteralPath (Join-Path $root ('Scripts/' + $name)))) ('总入口不再承载集中业务：' + $name)
    }
    Write-Host ('PASS: Architecture.Tests.ps1 (' + $script:assertions + ' assertions)')
} finally {
    $env:LOCALAPPDATA = $savedLocal
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}

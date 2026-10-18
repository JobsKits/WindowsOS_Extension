# Architecture.Tests.ps1 | Windows@Extension 独立包架构回归
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
Assert-Architecture ($packages.Count -eq 11) '十一个功能工程单独列出'
Assert-Architecture (@($packages.Name | Select-Object -Unique).Count -eq 11) '功能目录唯一'
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
        Assert-Architecture ($plan.Count -eq $expected) ('本包只注册自己的上下文：' + $package.Id)
        foreach ($item in $plan) {
            Assert-Architecture ($item.Key.EndsWith('Jobs.WindowsExtension.' + $package.Id)) '菜单计划不包含其它功能'
            Assert-Architecture ($item.Command -notmatch '\s-Action\s' -and $item.Command -match 'Invoke\.ps1') '菜单直接启动本功能'
            Assert-Architecture ($item.Command.Contains($release)) '注册命令使用本包独立运行版本'
        }
        $copied = Get-Content -LiteralPath (Join-Path $release 'Extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-Architecture ($copied.Id -eq $package.Id) '部署只包含所选包的清单'
        Assert-Architecture (@(Get-ChildItem -LiteralPath $release -Recurse -File | Where-Object { $_.Name -eq 'Action.psm1' }).Count -eq 1) '一次安装只打包一个功能业务'
    }
    Assert-Architecture (@($roots | Select-Object -Unique).Count -eq 11) '十一个功能安装状态彼此独立'
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

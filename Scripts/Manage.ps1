<#
Manage.ps1 | WindowsOS@Extension 组合安装入口
Created by Jobs on 2026年10月18日，星期日.
读取独立包清单，显示复选框；仅编排各包自己的安装与卸载，不承载右键业务。
每包独立事务，失败停止并显示已完成项；不联网、不提权、不改变系统执行策略。
#>
[CmdletBinding()]
param(
    [ValidateSet('Install', 'Configure', 'Uninstall')][string]$Mode = 'Install',
    [switch]$Preview
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Catalog.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'Installer.psm1') -DisableNameChecking

function Main {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion -lt [version]'5.1') {
        throw '请在 Windows 使用系统 Windows PowerShell 5.1 或根目录 .cmd 入口。'
    }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw '请通过 .cmd 入口启动原生安装面板。' }
    Add-Type -AssemblyName System.Windows.Forms
    Write-Host 'Jobs Windows 独立扩展 · 组合安装面板' -ForegroundColor Red
    Write-Host ('来源：' + (Split-Path -Parent $PSScriptRoot)) -ForegroundColor Cyan
    Write-Host '范围：当前用户的 Jobs\WindowsExtension 运行目录和 HKCU\Software\Classes 菜单键。'
    Write-Host '安装仅处理勾选项；卸载另开面板。全选 / 全不选只改变选择，点击操作按钮才执行。'
    Write-Host '每包独立备份与回滚；失败停止并保留已完成项。取消或关闭窗口不执行操作。'
    if ($Preview) { Write-Host '仅预览：返回选择后退出，不部署、不写状态或注册表。' -ForegroundColor Yellow }
    $packages = @(Get-JobsFeaturePackages)
    $installed = @()
    foreach ($package in $packages) {
        $module = Import-Module (Join-Path $package.PackagePath 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
        $state = & $module { param($Path) Get-JobsPackageState -PackagePath $Path } $package.PackagePath
        if ($state.Enabled) {
            if ($package.Id -ceq 'flutter-tools') { $installed += @($state.ActionIds | ForEach-Object { 'flutter-' + $_ }) }
            else { $installed += $package.Id }
        }
    }
    $features = @(Get-JobsSelectableFeatures -Packages $packages)
    $display = $features
    $selected = $installed
    if ($Mode -eq 'Uninstall') {
        $display = @($features | Where-Object { $_.Id -in $installed })
        if ($Preview) {
            $display = $features
            $selected = @($features.Id)
        } elseif ($display.Count -eq 0) {
            [void][System.Windows.Forms.MessageBox]::Show('没有已安装的扩展。', 'Jobs Windows 独立扩展')
            return
        }
    } elseif ($Mode -eq 'Install') { $selected = @($features.Id) }
    $choice = Show-JobsFeatureSelection -Packages $display -Selected $selected -Mode $Mode -Preview:$Preview
    if ($null -eq $choice) { return }
    if ($Preview) {
        $choice | ConvertTo-Json -Depth 3
        return
    }
    if (@($choice.Features).Count -eq 0 -and $Mode -ne 'Configure') { return }
    $plan = @(Get-JobsPackageOperationPlan -Packages $packages -Selected @($choice.Features) -Installed $installed -Mode $Mode)
    $result = Invoke-JobsPackageOperations -Plan $plan
    $completed = '无变更'
    if (@($result.Completed).Count -gt 0) { $completed = $result.Completed -join "`r`n" }
    if (-not $result.Success) {
        throw ("逐包执行已停止。已完成：`r`n" + $completed + "`r`n失败功能：" + $result.Failed + "`r`n" + $result.Message)
    }
    [void][System.Windows.Forms.MessageBox]::Show(
        ("处理完成：`r`n" + $completed + "`r`n重新打开右键菜单；Windows 11 位于【显示更多选项】。"),
        'Jobs Windows 独立扩展')
}

try { Main } catch {
    $message = $_.Exception.Message
    Write-Error $message -ErrorAction Continue
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        Add-Type -AssemblyName System.Windows.Forms
        [void][System.Windows.Forms.MessageBox]::Show($message, 'Jobs Windows 独立扩展 · 停止')
    }
    exit 1
}

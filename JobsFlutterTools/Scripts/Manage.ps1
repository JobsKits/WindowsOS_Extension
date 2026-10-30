<#
Manage.ps1 | JobsFlutterTools 安装 / 卸载管理
Created by Jobs on 2026年10月27日，星期二.
本包独立面板逐项选择 Flutter 叶功能；卸载只去除所选白名单，保留其它动作。
取消、空选或预览不写状态；面板确认后直接执行；不依赖父仓或其它功能目录。
#>
[CmdletBinding()]
param(
    [ValidateSet('Manage', 'Install', 'Uninstall')][string]$Mode = 'Manage',
    [switch]$Preview
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
function Main {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion -lt [version]'5.1') { throw '请使用 Windows 系统 PowerShell 5.1 或本包 Manage.vbs。' }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw '请通过本包 Manage.vbs 或 powershell.exe -STA 启动。' }
    $package = Split-Path -Parent $PSScriptRoot
    $installer = Import-Module (Join-Path $PSScriptRoot 'PackageInstaller.psm1') -PassThru -DisableNameChecking
    $actions = Import-Module (Join-Path $PSScriptRoot 'FeatureActions.psm1') -PassThru -DisableNameChecking
    $panel = Import-Module (Join-Path $PSScriptRoot 'SelectionPanel.psm1') -PassThru -DisableNameChecking
    $state = & $installer { param($Path) Get-JobsPackageState -PackagePath $Path } $package
    $installed = @()
    if ($state.Enabled) { $installed = @($state.ActionIds) }
    $features = @(& $actions { Get-JobsFlutterActionCatalog } | ForEach-Object {
        [pscustomobject]@{ Id = $_.Id; Label = $_.Label; Group = $_.Group; Description = '仅处理本包对应子功能；未选的其它功能在卸载时保留。' }
    })
    Write-Host 'Jobs Flutter 开发辅助 · 安装 / 卸载管理面板' -ForegroundColor Red
    Write-Host ('来源：' + $package) -ForegroundColor Cyan
    Write-Host ('目标：' + $state.Root) -ForegroundColor Cyan
    Write-Host '安装合并已启用动作；卸载只移除所选动作，剩余动作保留。取消或空选不执行。'
    Write-Host '只处理当前用户菜单；安装迁移固定旧 Flutter 菜单，保留程序、工具、日志和备份。'
    $buildPlan = {
        param($Choice)
        if (@($Choice.Features).Count -eq 0) { return }
        $operation = $Choice.Mode
        $remaining = @($installed + @($Choice.Features) | Select-Object -Unique)
        if ($Choice.Mode -eq 'Uninstall') {
            $remaining = @($installed | Where-Object { $_ -cnotin @($Choice.Features) })
            if ($remaining.Count -gt 0) { $operation = 'Install' }
        }
        [pscustomobject]@{ Id = 'flutter-tools'; Label = 'Flutter 开发辅助'; PackagePath = $package; Mode = $operation
            DisplayMode = $Choice.Mode; FeatureIds = @($Choice.Features); ActionIds = $remaining }
    }.GetNewClosure()
    $choice = & $panel {
        param($Features, $Installed, $Mode, $Preview, $BuildPlan, $Worker)
        Show-JobsFeatureSelection -Packages $Features -Selected @() -Installed $Installed -Mode $Mode -Preview:$Preview -BuildPlan $BuildPlan -WorkerPath $Worker
    } $features $installed $Mode ([bool]$Preview) $buildPlan (Join-Path $PSScriptRoot 'ManagementWorker.ps1')
    if ($Preview -and $null -ne $choice) { $choice | ConvertTo-Json -Depth 3 }

}
try { Main } catch {
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        Add-Type -AssemblyName System.Windows.Forms
        [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Jobs · 管理面板启动失败')
    }
    Write-Error $_.Exception.Message -ErrorAction Continue
    exit 1
}

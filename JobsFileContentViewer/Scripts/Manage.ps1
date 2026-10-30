<#
Manage.ps1 | WindowsOS@Extension 独立功能管理
Created by Jobs on 2026年10月28日，星期三.
本包面板负责安装 / 更新或卸载；后台执行、逐项状态和实时日志均留在面板。
取消、空选和预览不部署；保留本包备份、日志及工具，不提权或改变永久执行策略。
#>
[CmdletBinding()]
param([ValidateSet('Manage', 'Install', 'Uninstall')][string]$Mode = 'Manage', [switch]$Preview)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Main {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion -lt [version]'5.1') { throw '请使用 Windows 系统 PowerShell 5.1 或本包 Manage.vbs。' }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw '请通过本包 Manage.vbs 或 powershell.exe -STA 启动。' }
    $package = Split-Path -Parent $PSScriptRoot
    $installer = Import-Module (Join-Path $PSScriptRoot 'PackageInstaller.psm1') -PassThru -DisableNameChecking
    $manifest = & $installer { param($Path) Get-JobsPackageManifest -PackagePath $Path } $package
    $state = & $installer { param($Path) Get-JobsPackageState -PackagePath $Path } $package
    $installed = @()
    if ($state.Enabled) { $installed = @($manifest.Id) }
    $features = @([pscustomobject]@{ Id = $manifest.Id; Label = $manifest.Label; Group = '本功能'; Description = $manifest.Description })
    Import-Module (Join-Path $PSScriptRoot 'SelectionPanel.psm1') -DisableNameChecking
    $buildPlan = {
        param($Choice)
        if (@($Choice.Features).Count -eq 0) { return }
        $target = $package
        $operation = [pscustomobject]@{ Id = $manifest.Id; Label = $manifest.Label; PackagePath = $target; Mode = $Choice.Mode; DisplayMode = $Choice.Mode; FeatureIds = @($Choice.Features) }
        $legacy = @{
            'flutter-run' = 'run'; 'flutter-package' = 'package'; 'flutter-doctor' = 'native-doctor'
            'flutter-codegen' = 'codegen'; 'flutter-pub-get' = 'pub-get'; 'flutter-version-manager' = 'sdk-manage'
            'flutter-sdk-inspector' = 'sdk-version'; 'flutter-dependency-extract' = 'extract'
        }
        if ($Choice.Mode -eq 'Install' -and $legacy.ContainsKey($manifest.Id)) {
            $target = Join-Path (Split-Path -Parent $package) 'JobsFlutterTools'
            $modulePath = Join-Path $target 'Scripts/PackageInstaller.psm1'
            if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) { throw '旧 Flutter 安装入口需要同级完整 JobsFlutterTools。' }
            $unified = Import-Module $modulePath -PassThru -DisableNameChecking
            $current = & $unified { param($Path) Get-JobsPackageState -PackagePath $Path } $target
            $ids = @($legacy[$manifest.Id])
            if ($current.Enabled) { $ids = @(@($current.ActionIds) + $ids | Select-Object -Unique) }
            $operation.PackagePath = $target
            $operation | Add-Member -NotePropertyName ActionIds -NotePropertyValue $ids
        }
        $operation
    }.GetNewClosure()
    Show-JobsFeatureSelection -Packages $features -Selected @() -Installed $installed -Mode $Mode -Preview:$Preview -BuildPlan $buildPlan -WorkerPath (Join-Path $PSScriptRoot 'ManagementWorker.ps1') | Out-Null
}
try { Main } catch {
    $message = $_.Exception.Message
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        Add-Type -AssemblyName System.Windows.Forms
        [void][Windows.Forms.MessageBox]::Show($message, 'Jobs · 管理面板启动失败')
    }
    Write-Error $message -ErrorAction Continue
    exit 1
}

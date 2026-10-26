# ToggleHiddenFiles.ps1 | JobsHiddenFilesToggler 独立入口
# Created by Jobs on 2026年10月26日，星期一.
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
try {
    $action = Import-Module (Join-Path $PSScriptRoot 'Action.psm1') -PassThru -DisableNameChecking
    & $action { Invoke-JobsFeature -Target ([Environment]::GetFolderPath('DesktopDirectory')) }
} catch {
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        Add-Type -AssemblyName System.Windows.Forms
        [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Jobs 隐藏文件显示')
    } else { Write-Error $_.Exception.Message -ErrorAction Continue }
    exit 1
}

# RepairAndroidSimulator.ps1 | JobsAndroidSimulatorRepairer
# Created by Jobs on 2026年10月23日，星期五.
# 用途：仅检查/修复正在运行的 Android 模拟器；内置自述、确认及本功能日志。
[CmdletBinding()]
param(
    [switch]$Check,
    [string]$Serial,
    [string]$AppId,
    [ValidateRange(1, 1048576)][int]$ThresholdMB = 800,
    [string]$TargetDataSize = '8G'
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw '本入口只支持 Windows。' }
    $module = Import-Module (Join-Path $PSScriptRoot 'Action.psm1') -PassThru -DisableNameChecking
    & $module {
        param($ReadOnly, $DeviceSerial, $PackageId, $Limit, $Size)
        Invoke-JobsAndroidRepair -Check:$ReadOnly -Serial $DeviceSerial -AppId $PackageId -ThresholdMB $Limit -TargetDataSize $Size
    } ([bool]$Check) $Serial $AppId $ThresholdMB $TargetDataSize
} catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }

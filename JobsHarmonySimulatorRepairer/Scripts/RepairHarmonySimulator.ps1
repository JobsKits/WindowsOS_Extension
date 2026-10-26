# RepairHarmonySimulator.ps1 | JobsHarmonySimulatorRepairer
# Created by Jobs on 2026年10月24日，星期六.
# 独立入口；Check 只读，普通运行先显示用途并确认。
[CmdletBinding()]
param([switch]$Check, [string]$EmulatorBin = $env:HARMONY_EMULATOR_BIN)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw '本入口只支持 x64 Windows。' }
    $module = Import-Module (Join-Path $PSScriptRoot 'Action.psm1') -PassThru -DisableNameChecking
    if ($Check) {
        & $module { param($File) Get-JobsHarmonyRepairCheck $File | Format-List | Out-Host } $EmulatorBin
    } else {
        & $module { param($File) Invoke-JobsHarmonyRepairAction -Target ([Environment]::GetFolderPath('DesktopDirectory')) -EmulatorBin $File } $EmulatorBin
    }
} catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }

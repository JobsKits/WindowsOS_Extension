# CreateHarmonySimulator.ps1 | JobsHarmonySimulatorCreator
# Created by Jobs on 2026年10月23日，星期五.
[CmdletBinding()]
param([switch]$Check, [string]$EmulatorBin = $env:HARMONY_EMULATOR_BIN, [string]$Name, [switch]$NoStart)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw '本入口只支持 x64 Windows 10 / 11。' }
    $module = Import-Module (Join-Path $PSScriptRoot 'Action.psm1') -PassThru -DisableNameChecking
    if ($Check) {
        $result = & $module { param($File) Get-JobsHarmonyCheck $File } $EmulatorBin
        Write-Host ('Emulator：' + $result.Emulator + [Environment]::NewLine + '本机已下载镜像：' + $result.Images.Count + [Environment]::NewLine + '现有实例：' + $result.Instances.Count + [Environment]::NewLine + '只读体检完成；没有创建、下载或启动模拟器。')
        exit 0
    }
    & $module { param($File, $Name, $SkipStart) Invoke-JobsHarmonySimulatorAction -Target ([Environment]::GetFolderPath('DesktopDirectory')) -EmulatorBin $File -Name $Name -NoStart:$SkipStart } $EmulatorBin $Name ([bool]$NoStart)
} catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }

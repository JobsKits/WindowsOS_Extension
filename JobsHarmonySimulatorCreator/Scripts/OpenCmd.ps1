# OpenCmd.ps1 | JobsHarmonySimulatorCreator
# Created by Jobs on 2026年10月23日，星期五.
# 路径通过进程环境传递，CMD 仅执行固定的 PowerShell 引导行。
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Target)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
try {
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = Join-Path ([Environment]::GetFolderPath('System')) 'cmd.exe'
    $start.Arguments = '/d /v:off /k ""%JOBS_HARMONY_SIMULATOR_POWERSHELL%" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%JOBS_HARMONY_SIMULATOR_INVOKE%" -Target "%JOBS_HARMONY_SIMULATOR_TARGET%""'
    $start.UseShellExecute = $false
    $start.EnvironmentVariables['JOBS_HARMONY_SIMULATOR_POWERSHELL'] = Join-Path $PSHOME 'powershell.exe'
    $start.EnvironmentVariables['JOBS_HARMONY_SIMULATOR_INVOKE'] = Join-Path $PSScriptRoot 'Invoke.ps1'
    $start.EnvironmentVariables['JOBS_HARMONY_SIMULATOR_TARGET'] = $Target
    $start.WorkingDirectory = $Target
    [void][Diagnostics.Process]::Start($start)
} catch {
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Jobs 鸿蒙 · CMD 启动失败')
    exit 1
}

# OpenCmd.ps1 | JobsFlutterTools
# Created by Jobs on 2026年10月20日，星期二.
# 路径通过进程环境传递，CMD 仅执行固定的 PowerShell 引导行。
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Target, [Parameter(Mandatory = $true)][ValidateSet('run','pub-get','extract','sdk-version','sdk-manage','ohos-sdk-manage','package','codegen','native-doctor','harmony-doctor','maintenance','repair-android','repair-imports','repair-namespace')][string]$Action)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
try {
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = Join-Path ([Environment]::GetFolderPath('System')) 'cmd.exe'
    $start.Arguments = '/d /v:off /k ""%JOBS_FLUTTER_TOOLS_POWERSHELL%" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%JOBS_FLUTTER_TOOLS_INVOKE%" -Target "%JOBS_FLUTTER_TOOLS_TARGET%" -Action "%JOBS_FLUTTER_TOOLS_ACTION%""'
    $start.UseShellExecute = $false
    $start.EnvironmentVariables['JOBS_FLUTTER_TOOLS_POWERSHELL'] = Join-Path $PSHOME 'powershell.exe'
    $start.EnvironmentVariables['JOBS_FLUTTER_TOOLS_INVOKE'] = Join-Path $PSScriptRoot 'Invoke.ps1'
    $start.EnvironmentVariables['JOBS_FLUTTER_TOOLS_TARGET'] = $Target
    $start.EnvironmentVariables['JOBS_FLUTTER_TOOLS_ACTION'] = $Action
    $start.WorkingDirectory = $Target
    [void][Diagnostics.Process]::Start($start)
} catch {
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Jobs Flutter · CMD 启动失败')
    exit 1
}

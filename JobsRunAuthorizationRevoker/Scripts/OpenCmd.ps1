# OpenCmd.ps1 | JobsRunAuthorizationRevoker
# Created by Jobs on 2026年10月24日，星期六.
# 路径通过进程环境传递，CMD 仅执行固定的 PowerShell 引导行。
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Target)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'TerminalLauncher.ps1')
    $start = New-JobsPermissionTerminalStart -Target $Target -Scripts $PSScriptRoot
    [void][Diagnostics.Process]::Start($start)
} catch {
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Jobs Windows · 终端启动失败')
    exit 1
}

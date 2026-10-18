# Action.psm1
# JobsTerminalOpener
# Created by Jobs on 2026年10月18日，星期日.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking

function Start-JobsApplication {
    param([string]$Executable, [string[]]$Arguments, [string]$Directory, [switch]$VisibleConsole)
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $Executable
    $start.Arguments = (($Arguments | ForEach-Object { Quote-JobsArgument $_ }) -join ' ')
    $start.WorkingDirectory = $Directory
    # 可交互命令通过 ShellExecute 新开可见窗口，避免继承菜单宿主的隐藏控制台。
    $start.UseShellExecute = [bool]$VisibleConsole
    if ($VisibleConsole) { $start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Normal }
    [void][System.Diagnostics.Process]::Start($start)
}

function Invoke-JobsFeature {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Target)

    $directory = Get-JobsDirectory -Target $Target
    $terminal = Find-JobsExecutable -Name 'wt.exe' -Candidates @()
    if ($terminal) {
        Start-JobsApplication $terminal @('-d', $directory) $directory
    }
    else {
        Start-JobsApplication (Join-Path $PSHOME 'powershell.exe') @('-NoLogo', '-NoExit') $directory -VisibleConsole
    }
}

Export-ModuleMember -Function Invoke-JobsFeature

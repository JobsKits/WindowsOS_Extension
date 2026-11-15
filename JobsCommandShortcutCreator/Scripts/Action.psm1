# Action.psm1 | JobsCommandShortcutCreator
# Created by Jobs on 2026年11月13日，星期五.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'SelectionPanel.psm1') -DisableNameChecking
. (Join-Path $PSScriptRoot 'CommandShortcut.ps1')

function Invoke-JobsFeature {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Target)

    Show-JobsCommandShortcutDialog -Target (Resolve-JobsTarget -Target $Target)
}

Export-ModuleMember -Function Invoke-JobsFeature

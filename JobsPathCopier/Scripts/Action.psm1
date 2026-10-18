# Action.psm1
# JobsPathCopier
# Created by Jobs on 2026年10月18日，星期日.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking

function Invoke-JobsFeature {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Target)

    Set-Clipboard -Value (Resolve-JobsTarget -Target $Target)
}

Export-ModuleMember -Function Invoke-JobsFeature

# ChangeRunPermission.ps1 | JobsRunAuthorizationRevoker
# Created by Jobs on 2026年10月24日，星期六.
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Target)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
try {
    $module = Import-Module (Join-Path $PSScriptRoot 'Action.psm1') -PassThru -DisableNameChecking
    & $module { param($Path) Invoke-JobsFeature -Target $Path } $Target
} catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }

# Action.psm1 | JobsRunAuthorizer
# Created by Jobs on 2026年10月24日，星期六.
# 单文件执行权限；业务在独立终端确认后运行。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking
. (Join-Path $PSScriptRoot 'RunPermissions.ps1')
function Invoke-JobsFeature {
    param([Parameter(Mandatory = $true)][string]$Target)
    Invoke-JobsRunPermissionAction -Target (Resolve-JobsTarget $Target) -Mode Grant
}
Export-ModuleMember -Function Invoke-JobsFeature

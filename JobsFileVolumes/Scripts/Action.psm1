# Action.psm1 | JobsFileVolumes
# Created by Jobs on 2026年10月28日，星期三.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking
. (Join-Path $PSScriptRoot 'FileVolumes.ps1')
function Invoke-JobsFeature {
    [CmdletBinding()]
    param([ValidateSet('Split', 'Merge')][string]$Mode, [string[]]$Paths)
    if ($Mode -eq 'Merge') { return Invoke-JobsFileMerge -Paths $Paths }
    if (@($Paths).Count -ne 1) { throw '拆分仅接受一个普通文件。' }
    [void](Get-JobsVolumeFile $Paths[0])
    $limit = Show-JobsVolumeLimit
    if ($limit -le 0) { Write-Host '已取消，未拆分。'; return }
    return Invoke-JobsFileSplit -Path $Paths[0] -LimitBytes $limit
}
Export-ModuleMember -Function Invoke-JobsFeature

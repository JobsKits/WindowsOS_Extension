# Action.psm1 | JobsFileContentViewer
# Created by Jobs on 2026年10月27日，星期二.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking
. (Join-Path $PSScriptRoot 'FileViewer.ps1')

function Invoke-JobsFeature {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Target)

    $previousEncoding = [Console]::OutputEncoding
    try {
        # Windows PowerShell 5.1 的默认控制台代码页可能无法表示中文。
        [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
        Invoke-JobsFileContentViewer -Target (Resolve-JobsTarget -Target $Target)
    } finally {
        [Console]::OutputEncoding = $previousEncoding
    }
}

Export-ModuleMember -Function Invoke-JobsFeature

# Invoke.ps1 | JobsPermanentDeleter
# Created by Jobs on 2026年11月18日，星期三.
# Every entry path requires the same native second-confirmation dialog.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string[]]$Target)
# JOBS_SOURCE_LAYOUT_ROOT_V1：发布 flat 副本与源码包装共用所属包目录。
$script:JobsLayoutInvokeRoot = $(if ([IO.Path]::GetFileName($PSScriptRoot) -ceq 'Invoke.ps1') { Split-Path -Parent $PSScriptRoot } else { $PSScriptRoot })
# Verify enabled package state before loading the only mutating native implementation.
function Main {
    Set-StrictMode -Version 2.0
    $ErrorActionPreference = 'Stop'
    Import-Module (Join-Path $script:JobsLayoutInvokeRoot 'Common.psm1') -DisableNameChecking
    $manifest = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $script:JobsLayoutInvokeRoot) 'Extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $settings = Get-Content -LiteralPath (Join-Path (Get-JobsInstallRoot) 'settings.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.Id -cne 'permanent-delete' -or $settings.Version -ne 2 -or $settings.Id -cne $manifest.Id -or $settings.Enabled -ne $true) { throw '本功能未安装或已卸载。' }
    $module = Import-Module (Join-Path $script:JobsLayoutInvokeRoot 'Action.psm1') -PassThru -DisableNameChecking
    & $module { param($Paths) Invoke-JobsFeature -Target $Paths } $Target
}
Main

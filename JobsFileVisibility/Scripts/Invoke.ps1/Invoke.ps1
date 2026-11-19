# Invoke.ps1 | JobsFileVisibility
# Created by Jobs on 2026年11月18日，星期三.
# Direct CLI use requires explicit state; it uses the installed package's native implementation.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string[]]$Target,
      [Parameter(Mandatory=$true)][ValidateSet('Hide','Show')][string]$State)
# JOBS_SOURCE_LAYOUT_ROOT_V1：发布 flat 副本与源码包装共用所属包目录。
$script:JobsLayoutInvokeRoot = $(if ([IO.Path]::GetFileName($PSScriptRoot) -ceq 'Invoke.ps1') { Split-Path -Parent $PSScriptRoot } else { $PSScriptRoot })
# Installed state is checked before loading any mutating business function.
function Main {
    Set-StrictMode -Version 2.0
    $ErrorActionPreference = 'Stop'
    Import-Module (Join-Path $script:JobsLayoutInvokeRoot 'Common.psm1') -DisableNameChecking
    $manifest = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $script:JobsLayoutInvokeRoot) 'Extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $settings = Get-Content -LiteralPath (Join-Path (Get-JobsInstallRoot) 'settings.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.Id -cne 'file-visibility' -or $settings.Version -ne 2 -or $settings.Id -cne $manifest.Id -or $settings.Enabled -ne $true) { throw '本功能未安装或已卸载。' }
    $module = Import-Module (Join-Path $script:JobsLayoutInvokeRoot 'Action.psm1') -PassThru -DisableNameChecking
    & $module { param($Paths,$Action) Invoke-JobsFeature -Target $Paths -State $Action } $Target $State
}
Main

# CheckHarmonySdk.ps1 | JobsFlutterTools
# Created by Jobs on 2026年10月23日，星期五.
# 只读计划；不联网、不启动工具或写入项目。
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Target)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
try {
    $module = Import-Module (Join-Path $PSScriptRoot 'HarmonySdk.psm1') -PassThru -DisableNameChecking
    & $module { param($Path) Invoke-JobsHarmonySdkAction -Target $Path -Check } $Target
} catch { Write-Error $_.Exception.Message -ErrorAction Continue; exit 1 }

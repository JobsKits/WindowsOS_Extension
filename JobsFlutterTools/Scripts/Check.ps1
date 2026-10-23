# Check.ps1 | JobsFlutterTools
# Created by Jobs on 2026年10月22日，星期四.
# 只读配置与计划；不启动 Flutter / Dart / protoc，不安装或生成。
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Target)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
try {
    $action = Import-Module (Join-Path $PSScriptRoot 'Action.psm1') -PassThru -DisableNameChecking
    & $action {
        param($Path)
        $project = Assert-JobsRunnerDirectory (Resolve-JobsTarget $Path)
        Assert-JobsFlutterProject $project
        Write-Host ('只读检查：' + $project)
        Write-Host '计划：flutter --version；flutter doctor -v。未启动 SDK。'
    } $Target
} catch { Write-Error $_.Exception.Message -ErrorAction Continue; exit 1 }

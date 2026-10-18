# Sync-PackageInfrastructure.ps1 | Windows@Extension 基础设施副本检查
# Created by Jobs on 2026年10月18日，星期日.
# 默认只验证；-Write 仅更新包内四份通用机制，不覆盖任何 Action 或功能清单。
[CmdletBinding()]
param([switch]$Write)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$parsed = Get-Content -LiteralPath (Join-Path $root 'Extensions.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$packages = @($parsed)
$different = @()
foreach ($package in $packages) {
    if ($package.Name -notmatch '^Jobs[A-Za-z0-9]+$') { throw '包名不合法。' }
    foreach ($name in @('Common.psm1', 'Invoke.ps1', 'Manage.ps1', 'PackageInstaller.psm1')) {
        $source = Join-Path $root ('Infrastructure/' + $name)
        $destination = Join-Path $root ($package.Name + '/Scripts/' + $name)
        if ($Write) { Copy-Item -LiteralPath $source -Destination $destination -Force }
        if (-not (Test-Path -LiteralPath $destination -PathType Leaf) -or
            (Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $destination).Hash) {
            $different += ($package.Name + '/' + $name)
        }
    }
}
if ($different.Count -gt 0) { throw ('基础设施副本不一致：' + ($different -join ', ')) }
Write-Host '十个独立包的基础设施副本一致；业务文件未修改。'

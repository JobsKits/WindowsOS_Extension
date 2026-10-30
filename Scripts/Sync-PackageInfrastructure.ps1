# Sync-PackageInfrastructure.ps1 | WindowsOS@Extension 基础设施副本检查
# Created by Jobs on 2026年10月18日，星期日.
# 默认只验证；-Write 更新包内六份通用机制及 GUI 转交入口，不覆盖 Action 或功能清单。
[CmdletBinding()]
param([switch]$Write)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$parsed = Get-Content -LiteralPath (Join-Path $root 'Extensions.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$packages = @($parsed)
$different = @()
$panelSource = Join-Path $root 'Scripts/Installer.psm1'
foreach ($relative in @('Scripts/SelectionPanel.psm1', 'Infrastructure/SelectionPanel.psm1')) {
    $destination = Join-Path $root $relative
    if ($Write) { Copy-Item -LiteralPath $panelSource -Destination $destination -Force }
    if (-not (Test-Path -LiteralPath $destination -PathType Leaf) -or
        (Get-FileHash -LiteralPath $panelSource).Hash -ne (Get-FileHash -LiteralPath $destination).Hash) {
        $different += $relative
    }
}
foreach ($package in $packages) {
    if ($package.Name -notmatch '^Jobs[A-Za-z0-9]+$') { throw '包名不合法。' }
    $manifest = Get-Content -LiteralPath (Join-Path $root ($package.Name + '/Extension.json')) -Raw -Encoding UTF8 | ConvertFrom-Json
    $overrides = @()
    if ($null -ne $manifest.PSObject.Properties['InfrastructureOverrides']) {
        $overrides = @($manifest.InfrastructureOverrides)
        if ($package.Id -ceq 'flutter-tools' -and $package.Name -ceq 'JobsFlutterTools') {
            if (($overrides -join ',') -cne 'PackageInstaller.psm1,Invoke.ps1,Manage.ps1') { throw '统一 Flutter 菜单的基础设施覆盖必须与固定白名单一致。' }
        } elseif ($package.Id -ceq 'hidden-files-toggle' -and $package.Name -ceq 'JobsHiddenFilesToggler') {
            if (($overrides -join ',') -cne 'PackageInstaller.psm1,Invoke.ps1') { throw '隐藏文件菜单只允许独立安装器及显式 Show/Hide 传输入口。' }
        } elseif ($package.Id -ceq 'file-volumes' -and $package.Name -ceq 'JobsFileVolumes') {
            if (($overrides -join ',') -cne 'PackageInstaller.psm1,Invoke.ps1') { throw '分卷包只覆盖原生安装器及精确选择清单入口。' }
        } elseif ($overrides.Count -ne 1 -or $overrides[0] -cne 'PackageInstaller.psm1') { throw '基础设施覆盖白名单只允许 PackageInstaller.psm1。' }
    }
    foreach ($name in @('Common.psm1', 'Invoke.ps1', 'Manage.ps1', 'PackageInstaller.psm1', 'SelectionPanel.psm1', 'ManagementWorker.ps1')) {
        # 原生 COM 包有独立生命周期；明确白名单防止同步时覆盖其注册 / 构建事务。
        if ($name -cin $overrides) { continue }
        $source = Join-Path $root ('Infrastructure/' + $name)
        $destination = Join-Path $root ($package.Name + '/Scripts/' + $name)
        if ($Write) { Copy-Item -LiteralPath $source -Destination $destination -Force }
        if (-not (Test-Path -LiteralPath $destination -PathType Leaf) -or
            (Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $destination).Hash) {
            $different += ($package.Name + '/' + $name)
        }
    }
}
# 管理脚本通过 WScript 唤起面板；旧 Flutter 目录也携带相同隐藏启动模板。
$managementFolders = @(Get-ChildItem -LiteralPath $root -Directory | Where-Object {
    $_.Name -like 'Jobs*' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'Scripts/Manage.ps1') -PathType Leaf)
})
foreach ($folder in $managementFolders) {
    # 旧 Flutter 管理目录也会独立使用面板，不让基础设施包清单漏掉它们。
    $panelDestination = Join-Path $folder.FullName 'Scripts/SelectionPanel.psm1'
    if ($Write) { Copy-Item -LiteralPath $panelSource -Destination $panelDestination -Force }
    if (-not (Test-Path -LiteralPath $panelDestination -PathType Leaf) -or
        (Get-FileHash -LiteralPath $panelSource).Hash -ne (Get-FileHash -LiteralPath $panelDestination).Hash) {
        $different += ($folder.Name + '/SelectionPanel.psm1')
    }
    foreach ($entry in @('Manage.cmd', 'Manage.vbs')) {
        $source = Join-Path $root ('Infrastructure/' + $entry)
        $destination = Join-Path $folder.FullName $entry
        if ($Write) { Copy-Item -LiteralPath $source -Destination $destination -Force }
        if (-not (Test-Path -LiteralPath $destination -PathType Leaf) -or
            (Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $destination).Hash) {
            $different += ($folder.Name + '/' + $entry)
        }
    }
}
if ($different.Count -gt 0) { throw ('基础设施副本不一致：' + ($different -join ', ')) }
Write-Host ('{0} 个独立包的共享基础设施副本一致；原生 COM 安装器按白名单独立维护，业务文件未修改。' -f $packages.Count)

# Invoke.ps1 | JobsFileVolumes
# Created by Jobs on 2026年10月28日，星期三.
# 只读取本包原生 handler 写入的精确选择清单，单次控制台处理整组。
[CmdletBinding()]
param([Parameter(Mandatory = $true)][ValidateSet('Split', 'Merge')][string]$Mode,
    [Parameter(Mandatory = $true)][string]$Request)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$exitCode = 0
$previousEncoding = [Console]::OutputEncoding
try {
    [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
    Write-Host 'Jobs · 文件分卷合并 / 拆分' -ForegroundColor Red
    Write-Host '1、只处理右键传入的精确选择，不扫描目录补齐分卷。'
    Write-Host '2、分卷采用 完整文件名@序号of总数；大小与 SHA-256 验证后发布，已有目标不覆盖。'
    Write-Host '3、只新增结果，始终保留源文件和分卷。失败候选保留，Ctrl+C 可停止。'
    Write-Host '日志：当前用户 Jobs/WindowsExtension/extensions/file-volumes/logs。'
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion -lt [version]'5.1') { throw '请在 Windows 中使用系统 PowerShell 5.1。' }
    Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking
    $root = Get-JobsInstallRoot
    $settings = Get-Content -LiteralPath (Join-Path $root 'settings.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($settings.Version -ne 2 -or $settings.Id -cne 'file-volumes' -or $settings.Enabled -ne $true) { throw '此功能已卸载，请重新打开右键菜单。' }
    . (Join-Path $PSScriptRoot 'SelectionRequest.ps1')
    $paths = @(Read-JobsVolumeRequest -Path $Request)
    $answer = Read-Host '按回车继续；Ctrl+C 取消'
    if ($null -eq $answer) { Write-Host '输入结束，已取消。'; return }
    $action = Import-Module (Join-Path $PSScriptRoot 'Action.psm1') -PassThru -DisableNameChecking
    & $action { param($Action, $Selection) Invoke-JobsFeature -Mode $Action -Paths $Selection } $Mode $paths | Out-Null
    Write-JobsLog '文件分卷操作完成或用户取消；原件保留。'
} catch {
    $exitCode = 1
    Write-Host $_.Exception.Message -ForegroundColor Red
    try { Write-JobsLog '文件分卷操作失败，原件保留。' } catch { }
} finally {
    [void](Read-Host '按回车关闭此窗口')
    [Console]::OutputEncoding = $previousEncoding
}
exit $exitCode

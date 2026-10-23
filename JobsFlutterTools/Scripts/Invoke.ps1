# Invoke.ps1 | WindowsOS@Extension 单功能运行入口
# Created by Jobs on 2026年10月18日，星期日.
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Target, [Parameter(Mandatory = $true)][ValidateSet('run','pub-get','extract','sdk-version','sdk-manage','ohos-sdk-manage','package','codegen','native-doctor','harmony-doctor','maintenance','repair-android','repair-imports','repair-namespace')][string]$Action)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$console = $false
$exitCode = 0
try {
    Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw '本扩展只支持 Windows。' }
    $manifest = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'Extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $console = [bool]$manifest.Console
    $settings = Get-Content -LiteralPath (Join-Path (Get-JobsInstallRoot) 'settings.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($settings.Version -ne 2 -or $settings.Id -cne $manifest.Id -or $settings.Enabled -ne $true) {
        throw '此功能尚未安装或已经卸载，请重新打开右键菜单。'
    }
    $path = Resolve-JobsTarget $Target
    if ($manifest.DirectoryOnly -and -not (Test-Path -LiteralPath $path -PathType Container)) {
        throw '此功能只适用于文件夹。'
    }
    # 只载入本包业务；没有 Action 分发开关，也没有其它功能的运行依赖。
    $actionModule = Import-Module (Join-Path $PSScriptRoot 'Action.psm1') -DisableNameChecking -PassThru
    & $actionModule { param($Path, $Action) Invoke-JobsFeature -Target $Path -Action $Action } $path $Action
} catch {
    $exitCode = 1
    $message = $_.Exception.Message
    $safe = $message -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@'
    $safe = $safe -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]'
    try { Write-JobsLog '本功能操作失败。' } catch { }
    if ($console) { Write-Host $safe -ForegroundColor Red }
    elseif ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        Add-Type -AssemblyName System.Windows.Forms
        [void][System.Windows.Forms.MessageBox]::Show($safe, 'Jobs Windows 右键扩展')
    } else { Write-Error $safe -ErrorAction Continue }
} finally {
    if ($console) { [void](Read-Host '按回车关闭此窗口') }
}
exit $exitCode

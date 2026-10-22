# Configure.ps1 | JobsGitProxyConfigurator
# Created by Jobs on 2026年10月22日，星期四.
[CmdletBinding()]
param([ValidateSet('Menu','Install','Check','Restore')][string]$Mode='Menu')
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$interactiveMenu=($Mode -eq 'Menu')
try {
    Write-Host 'Jobs Git 动态代理配置' -ForegroundColor Red
    Write-Host '系统代理可达优先、不可达再直连；原始 Git 业务最多一次，不改系统代理/VPN/.gitconfig/项目 remote。'
    Write-Host '仅当前用户 PATH 与专用运行态；精确备份、并发修改停止。Ctrl+C 取消；日志位于用户 LocalAppData 的 JobsGitNetworkStrategy。'
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $PSVersionTable.PSEdition -ne 'Desktop') { throw '请在 Windows PowerShell 5.1 通过本包 CMD 入口运行。' }
    if ($Mode -in @('Menu','Restore') -and [Console]::IsInputRedirected) { throw '当前没有交互终端；未修改配置。' }
    if ($Mode -eq 'Menu') {
        $choice=Read-Host '回车配置；C 检查；R 恢复；其它取消'
        switch ($choice.ToUpperInvariant()) {
            '' { $Mode='Install' }
            'C' { $Mode='Check' }
            'R' { $Mode='Restore' }
            default { exit 0 }
        }
    }
    if ($Mode -eq 'Restore' -and (Read-Host '按回车确认精确恢复；其它取消') -ne '') { exit 0 }
    Import-Module (Join-Path $PSScriptRoot 'ProxyInstaller.psm1') -DisableNameChecking
    switch ($Mode) {
        'Install' { Install-JobsGitProxy | Out-Null }
        'Check' { Test-JobsGitProxyInstallation | Out-Null }
        'Restore' { Restore-JobsGitProxy }
    }
} catch { Write-Error $_.Exception.Message -ErrorAction Continue; exit 1 }
finally {
    if ($interactiveMenu -and $env:JOBS_GIT_PROXY_MENU_HOST -ne '1' -and -not [Console]::IsInputRedirected) {
        [void](Read-Host '处理结束，按回车关闭')
    }
}

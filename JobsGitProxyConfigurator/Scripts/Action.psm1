# Action.psm1 | JobsGitProxyConfigurator
# Created by Jobs on 2026年10月22日，星期四.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking
# DesktopBackground registration is checked again before opening configuration.
function Invoke-JobsProxyConfiguratorAction {
    param([string]$Directory)
    $desktop=[Environment]::GetFolderPath('Desktop')
    if (-not $desktop -or [IO.Path]::GetFullPath($Directory).TrimEnd('\') -ine [IO.Path]::GetFullPath($desktop).TrimEnd('\')) {
        throw '此配置入口仅接受当前用户桌面空白上下文。'
    }
    $original=[Environment]::GetEnvironmentVariable('JOBS_GIT_PROXY_MENU_HOST','Process')
    try {
        $env:JOBS_GIT_PROXY_MENU_HOST='1'
        & (Join-Path $PSScriptRoot 'Configure.ps1')
    } finally { [Environment]::SetEnvironmentVariable('JOBS_GIT_PROXY_MENU_HOST',$original,'Process') }
}
function Invoke-JobsFeature {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Target)
    $directory=Get-JobsDirectory -Target $Target
    Invoke-JobsProxyConfiguratorAction $directory
}
Export-ModuleMember -Function Invoke-JobsFeature

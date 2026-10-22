# Policy.ps1 | JobsGitProxyConfigurator
# Created by Jobs on 2026年10月22日，星期四.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$EncodedArguments)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
try {
    [void][Reflection.Assembly]::LoadFrom((Join-Path $PSScriptRoot 'git.exe'))
    Import-Module (Join-Path $PSScriptRoot 'NetworkPolicy.psm1') -DisableNameChecking
    $original = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'real-git.path'), [Text.Encoding]::UTF8).Trim()
    exit (Invoke-JobsGitNetworkPolicy -Git $original -ArgumentList ([JobsGitProxy.Bridge]::Decode($EncodedArguments)))
} catch {
    [Console]::Error.WriteLine('[Jobs Git] 动态入口校验失败；请运行配置检查。')
    exit 128
}

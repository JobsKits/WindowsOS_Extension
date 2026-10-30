# ProjectSetupWorker.ps1 | GUI 的交互式控制台承接入口。
# Created by Jobs on 2026年10月28日，星期三.
param([string]$Target=$env:JOBS_SETUP_TARGET,[string]$Session=$env:JOBS_SETUP_SESSION)
$ErrorActionPreference='Stop'
$env:JOBS_SETUP_SESSION=$Session
Import-Module (Join-Path $PSScriptRoot 'ProjectSetupProgress.psm1') -DisableNameChecking
try {
 Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking
 Import-Module (Join-Path $PSScriptRoot 'FeatureActions.psm1') -DisableNameChecking
 $settings=Get-Content -LiteralPath (Join-Path (Get-JobsInstallRoot) 'settings.json') -Raw -Encoding UTF8|ConvertFrom-Json
 if($settings.Version-ne2-or$settings.Id-cne'flutter-tools'-or$settings.Enabled-ne$true-or'project-setup'-cnotin@(Get-JobsFlutterStateActionIds $settings)){throw '此一键配置菜单未安装或已停用，请通过管理入口重新选择。'}
 if(-not[string]::Equals([IO.Path]::GetFullPath($settings.ReleasePath).TrimEnd('\','/'),[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\','/'),[StringComparison]::OrdinalIgnoreCase)){throw '这是旧版菜单；请重新打开当前菜单。'}
 Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class JobsSetupConsole { [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow(); }'
 [IO.File]::WriteAllText((Join-Path $Session 'console-hwnd.txt'),[JobsSetupConsole]::GetConsoleWindow().ToInt64().ToString())
 Start-Transcript -LiteralPath (Join-Path $Session 'transcript.log') -Force | Out-Null
 Import-Module (Join-Path $PSScriptRoot 'ProjectSetup.psm1') -DisableNameChecking
 Invoke-JobsProjectSetupAction -Target $Target -Action project-setup
 Set-JobsSetupProgress overall done '本次配置与所选运行步骤完成'
} catch {
 $active=Get-JobsSetupActiveNode;if($active){Set-JobsSetupProgress $active failed $_.Exception.Message}
 Set-JobsSetupProgress overall failed $_.Exception.Message
 Write-Host $_.Exception.Message -ForegroundColor Red
} finally {
 try { Stop-Transcript | Out-Null } catch { }
 [void](Read-Host '本次任务已结束。按回车关闭终端')
}

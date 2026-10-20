@echo off
setlocal
rem Created by Jobs on 2026-10-18.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Scripts\Manage.ps1" -Mode Uninstall %*
set "jobsExitCode=%errorlevel%"
if not "%jobsExitCode%"=="0" pause
exit /b %jobsExitCode%

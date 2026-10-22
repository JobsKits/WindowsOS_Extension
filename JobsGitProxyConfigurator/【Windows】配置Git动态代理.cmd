@echo off
rem Created by Jobs on 2026-10-22. Git dynamic proxy configurator.
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Scripts\Configure.ps1" %*
set "jobsExitCode=%errorlevel%"
if not "%jobsExitCode%"=="0" pause
exit /b %jobsExitCode%

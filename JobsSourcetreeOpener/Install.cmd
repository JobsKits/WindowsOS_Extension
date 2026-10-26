@echo off
setlocal DisableDelayedExpansion
rem Created by Jobs on 2026-10-19. Independent feature package.
set "jobsPowerShell=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if defined PROCESSOR_ARCHITEW6432 set "jobsPowerShell=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%jobsPowerShell%" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Scripts\Manage.ps1" -Mode Install
set "jobsExitCode=%errorlevel%"
if not "%jobsExitCode%"=="0" pause
exit /b %jobsExitCode%

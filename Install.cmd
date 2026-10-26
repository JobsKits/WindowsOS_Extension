@echo off
setlocal DisableDelayedExpansion
rem MAINTENANCE_INDEX: Scripts\Manage.ps1 maps panel IDs, native handlers and installed releases.
rem Edit Extensions.json and each package's source manifest; never patch an installed release.
rem Created by Jobs on 2026-10-18. No elevation or permanent policy change.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Scripts\Manage.ps1" -Mode Install %*
set "jobsExitCode=%errorlevel%"
if not "%jobsExitCode%"=="0" pause
exit /b %jobsExitCode%

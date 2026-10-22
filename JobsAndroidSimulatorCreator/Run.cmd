@echo off
setlocal
rem Created by Jobs on 2026-10-22. Standalone Android AVD creator.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Scripts\CreateAndroidSimulator.ps1"
set "jobsExitCode=%errorlevel%"
pause
exit /b %jobsExitCode%

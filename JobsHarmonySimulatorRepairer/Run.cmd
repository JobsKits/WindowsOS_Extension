@echo off
setlocal DisableDelayedExpansion
rem Created by Jobs on 2026-10-23. Standalone Harmony emulator diagnosis and repair.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Scripts\RepairHarmonySimulator.ps1" %*
set "jobsExitCode=%errorlevel%"
pause
exit /b %jobsExitCode%

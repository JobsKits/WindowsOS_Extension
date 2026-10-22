@echo off
setlocal
rem Created by Jobs on 2026-10-23. Standalone HarmonyOS emulator creator.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Scripts\CreateHarmonySimulator.ps1" %*
set "jobsExitCode=%errorlevel%"
pause
exit /b %jobsExitCode%

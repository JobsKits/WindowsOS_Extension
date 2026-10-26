@echo off
setlocal DisableDelayedExpansion
rem Created by Jobs on 2026-10-26. Toggle only this user's Explorer hidden-file preference.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Scripts\ToggleHiddenFiles.ps1"
exit /b %errorlevel%

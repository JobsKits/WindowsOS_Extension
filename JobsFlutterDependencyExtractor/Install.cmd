@echo off
setlocal DisableDelayedExpansion
rem GUI startup: WScript hosts Scripts/Manage.ps1 in a hidden PowerShell process.
"%SystemRoot%\System32\wscript.exe" //nologo "%~dp0Manage.vbs" -Mode Install %*
exit /b %errorlevel%

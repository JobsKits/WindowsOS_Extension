@echo off
setlocal DisableDelayedExpansion
rem GUI startup: WScript hosts Scripts/Manage.ps1 in a hidden PowerShell process.
"%SystemRoot%\System32\wscript.exe" //nologo "%~dpn0.vbs" %*
exit /b %errorlevel%

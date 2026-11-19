@echo off
setlocal DisableDelayedExpansion
rem GUI startup: WScript hosts Scripts/Manage.ps1 in a hidden PowerShell process.
set "JOBS_LAYOUT_TARGET=%~dp0Manage.vbs"
if exist "%JOBS_LAYOUT_TARGET%\Manage.vbs" set "JOBS_LAYOUT_TARGET=%JOBS_LAYOUT_TARGET%\Manage.vbs"
"%SystemRoot%\System32\wscript.exe" //nologo "%JOBS_LAYOUT_TARGET%" %*
exit /b %errorlevel%

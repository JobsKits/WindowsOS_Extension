@echo off
setlocal DisableDelayedExpansion
rem GUI startup: WScript hosts Scripts/Manage.ps1 in a hidden PowerShell process.
rem JOBS_SOURCE_LAYOUT_ROOT_V1: original feature root, including flat release compatibility.
set "JOBS_LAYOUT_ENTRY=%~dp0"
if not exist "%JOBS_LAYOUT_ENTRY%Scripts\" if exist "%JOBS_LAYOUT_ENTRY%..\Extension.json" set "JOBS_LAYOUT_ENTRY=%~dp0..\"
set "JOBS_LAYOUT_TARGET=%JOBS_LAYOUT_ENTRY%Manage.vbs"
if exist "%JOBS_LAYOUT_TARGET%\Manage.vbs" set "JOBS_LAYOUT_TARGET=%JOBS_LAYOUT_TARGET%\Manage.vbs"
"%SystemRoot%\System32\wscript.exe" //nologo "%JOBS_LAYOUT_TARGET%" -Mode Install %*
exit /b %errorlevel%

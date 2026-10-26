@echo off
setlocal DisableDelayedExpansion
rem Standalone file execution ACL action. No target file is executed.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Scripts\ChangeRunPermission.ps1" %*
set "jobsExitCode=%errorlevel%"
pause
exit /b %jobsExitCode%

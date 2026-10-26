@echo off
setlocal DisableDelayedExpansion
rem Legacy entry delegates to the unified Flutter menu owner.
if not exist "%~dp0..\JobsFlutterTools\Install.cmd" (
  echo Please download the complete WindowsOS@Extension including JobsFlutterTools.
  exit /b 1
)
call "%~dp0..\JobsFlutterTools\Install.cmd"
exit /b %errorlevel%

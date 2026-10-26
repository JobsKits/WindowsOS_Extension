# TerminalLauncher.ps1 | Jobs file permission terminal transport
# Created by Jobs on 2026年10月24日，星期六.
# Build the fixed CMD bootstrap without interpolating file paths as commands.
function New-JobsPermissionTerminalStart {
    param([string]$Target, [string]$Scripts, [string]$SystemDirectory = [Environment]::GetFolderPath('System'), [string]$PowerShell = (Join-Path $PSHOME 'powershell.exe'))
    $file = Get-Item -LiteralPath $Target -Force -ErrorAction Stop
    if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw '只允许一个普通文件。' }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = Join-Path $SystemDirectory 'cmd.exe'
    $start.Arguments = '/d /v:off /k ""%JOBS_RUN_PERMISSION_POWERSHELL%" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%JOBS_RUN_PERMISSION_INVOKE%" -Target "%JOBS_RUN_PERMISSION_TARGET%""'
    $start.UseShellExecute = $false
    $start.EnvironmentVariables['JOBS_RUN_PERMISSION_POWERSHELL'] = $PowerShell
    $start.EnvironmentVariables['JOBS_RUN_PERMISSION_INVOKE'] = Join-Path $Scripts 'Invoke.ps1'
    $start.EnvironmentVariables['JOBS_RUN_PERMISSION_TARGET'] = $file.FullName
    $start.WorkingDirectory = $file.DirectoryName
    return $start
}

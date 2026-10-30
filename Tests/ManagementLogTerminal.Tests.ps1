# ManagementLogTerminal.Tests.ps1 | Jobs 管理器完整会话日志终端回归
# Created by Jobs on 2026年10月29日，星期四.
# 仅在临时目录验证命令数据边界，不打开桌面终端或运行安装器。
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$panel = Import-Module (Join-Path $root 'Scripts/Installer.psm1') -PassThru -Force -DisableNameChecking
$assertions = 0
function Assert-Log {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
    $script:assertions++
}
$temp = Join-Path ([IO.Path]::GetTempPath()) ('Jobs 日志终端 ' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
try {
    $path = Join-Path $temp '完整 [1] & '' $().log'
    $sentinel = Join-Path $temp 'must-not-execute'
    $content = ('完整会话日志 0123456789 abcdefghijklmnopqrstuvwxyz' + [Environment]::NewLine) * 30000
    $content += "Set-Content -LiteralPath '$sentinel' -Value executed" + [Environment]::NewLine + 'FULL-LOG-LAST-LINE'
    [IO.File]::WriteAllText($path, $content, (New-Object Text.UTF8Encoding($false)))
    $info = & $panel { param($Path) New-JobsManagementLogStartInfo -LogPath $Path } $path
    Assert-Log ($info.UseShellExecute -and $info.WindowStyle -eq 'Normal' -and $info.Arguments.Contains('-NoExit')) '以可见独立进程读取日志并保留终端'
    $encoded = ($info.Arguments -split ' ')[-1]
    $command = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded))
    Assert-Log (-not $command.Contains($path)) '特殊字符路径编码为数据，不插入命令正文'
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = (Get-Process -Id $PID).Path
    $start.Arguments = '-NoLogo -NoProfile -NonInteractive -EncodedCommand ' + $encoded
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($start)
    try {
        $output = $process.StandardOutput.ReadToEnd()
        $errorText = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        Assert-Log ($process.ExitCode -eq 0) ('日志读取进程正常结束：' + $errorText)
        Assert-Log ($output.Length -gt 1000000 -and $output.Contains('FULL-LOG-LAST-LINE')) '读取完整文件，不受面板可见区限长影响'
        Assert-Log ($output.Contains('Set-Content -LiteralPath') -and -not [IO.File]::Exists($sentinel)) '日志正文仅显示，不作为命令执行'
    } finally { $process.Dispose() }
    foreach ($invalid in @((Join-Path $temp 'missing.log'), $temp)) {
        $threw = $false
        try { & $panel { param($Path) New-JobsManagementLogStartInfo -LogPath $Path } $invalid | Out-Null } catch { $threw = $true }
        Assert-Log $threw '不存在或目录目标在启动终端前拒绝'
    }
    $lock = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $threw = $false
        try { & $panel { param($Path) New-JobsManagementLogStartInfo -LogPath $Path } $path | Out-Null } catch { $threw = $true }
        Assert-Log $threw '不可读取的会话日志在启动前报告失败'
    } finally { $lock.Dispose() }
} finally { Remove-Item -LiteralPath $temp -Recurse -Force }
Write-Host ('PASS: ManagementLogTerminal.Tests.ps1 (' + $assertions + ' assertions; no desktop launch)')

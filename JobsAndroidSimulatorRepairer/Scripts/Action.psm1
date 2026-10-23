# Action.psm1 | JobsAndroidSimulatorRepairer
# Created by Jobs on 2026年10月23日，星期五.
# 业务自包含；工具只发现不安装，每次设备写入前重新核对模拟器身份。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking

function Read-JobsRepairInput {
    param([string]$Prompt)
    Write-Host ($Prompt + '：') -NoNewline
    $answer = [Console]::ReadLine()
    if ($null -eq $answer) { throw '输入已结束，停止操作。' }
    return $answer
}
function Confirm-JobsRepairDanger {
    param([string]$Description)
    Write-Host $Description -ForegroundColor Yellow
    return (Read-JobsRepairInput '输入精确 YES 继续，其它输入取消') -ceq 'YES'
}
function Get-JobsRepairTool {
    param([ValidateSet('adb', 'emulator')][string]$Name, [switch]$Optional)
    $candidates = @()
    $explicit = $env:ANDROID_HOME
    if ([string]::IsNullOrWhiteSpace($explicit)) { $explicit = $env:ANDROID_SDK_ROOT }
    foreach ($root in @($explicit)) {
        if (-not [string]::IsNullOrWhiteSpace($root)) {
            $relative = 'platform-tools/adb.exe'
            if ($Name -eq 'emulator') { $relative = 'emulator/emulator.exe' }
            $candidates += Join-Path $root $relative
        }
    }
    if ($explicit) {
        if (-not [IO.Path]::IsPathRooted($explicit)) { throw '显式 SDK 必须为绝对路径。' }
        if (-not (Test-Path -LiteralPath $candidates[0] -PathType Leaf)) { throw ('显式 SDK 缺少 ' + $Name + '，停止；不会切换到其它 SDK。') }
        $check = Invoke-JobsProcess -FilePath $candidates[0] -Arguments @($(if ($Name -eq 'adb') { 'version' } else { '-version' })) -TimeoutSeconds 15
        if ($check.ExitCode -ne 0) { throw ('显式 SDK 的 ' + $Name + ' 体检失败，不切换 SDK。') }
        return [IO.Path]::GetFullPath($candidates[0])
    }
    $pathCommand = Find-JobsExecutable ($Name + '.exe')
    if ($pathCommand) { $candidates += $pathCommand }
    $local = $env:LOCALAPPDATA
    if (-not $local) { $local = [Environment]::GetFolderPath('LocalApplicationData') }
    if ($local) {
        $relative = 'Android/Sdk/platform-tools/adb.exe'
        if ($Name -eq 'emulator') { $relative = 'Android/Sdk/emulator/emulator.exe' }
        $candidates += Join-Path $local $relative
    }
    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $result = Invoke-JobsProcess -FilePath $candidate -Arguments @($(if ($Name -eq 'adb') { 'version' } else { '-version' })) -TimeoutSeconds 15
            if ($result.ExitCode -eq 0) { return [IO.Path]::GetFullPath($candidate) }
        }
    }
    if ($Optional) { return $null }
    throw ('没有可运行的 ' + $Name + '；请先准备已有 Android SDK / PATH。本功能不下载或安装工具。')
}
function Invoke-JobsRepairAdb {
    param([string]$Adb, [string[]]$Arguments, [int]$TimeoutSeconds = 30)
    $result = Invoke-JobsProcess -FilePath $Adb -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds
    if ($result.ExitCode -ne 0) { throw ('ADB 失败，退出码 ' + $result.ExitCode + '：' + $result.StdErr + $result.StdOut) }
    return $result.StdOut.Trim()
}
function Get-JobsRepairDevices {
    param([string]$Adb)
    $text = Invoke-JobsRepairAdb $Adb @('devices')
    foreach ($line in ($text -split '\r?\n')) {
        if ($line -cmatch '^(emulator-[0-9]+)\s+device(?:\s|$)') { Write-Output $Matches[1] }
    }
}
function Assert-JobsRepairEmulator {
    param([string]$Adb, [string]$Serial, [string]$ExpectedAvd)
    if ($Serial -cnotmatch '^emulator-[0-9]+$') { throw '拒绝真机或无法确认的设备序列号。' }
    if ((Invoke-JobsRepairAdb $Adb @('-s', $Serial, 'get-state')) -cne 'device') { throw '模拟器不在线。' }
    $qemu = Invoke-JobsRepairAdb $Adb @('-s', $Serial, 'shell', 'getprop', 'ro.kernel.qemu')
    if ($qemu -cne '1') { throw '设备未通过 QEMU 模拟器身份检查，停止。' }
    $lines = @((Invoke-JobsRepairAdb $Adb @('-s', $Serial, 'emu', 'avd', 'name')) -split '\r?\n' | Where-Object { $_ -and $_ -cne 'OK' })
    if ($lines.Count -ne 1 -or $lines[0] -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$') { throw '无法获取唯一有效的 AVD 名称，停止。' }
    if ($ExpectedAvd -and $lines[0] -cne $ExpectedAvd) { throw '模拟器端口已由其它 AVD 占用，停止。' }
    return $lines[0]
}
function Invoke-JobsRepairDeviceWrite {
    param([string]$Adb, [string]$Serial, [string]$Avd, [string[]]$Arguments, [int]$TimeoutSeconds = 60)
    [void](Assert-JobsRepairEmulator $Adb $Serial $Avd)
    return Invoke-JobsRepairAdb $Adb (@('-s', $Serial) + $Arguments) -TimeoutSeconds $TimeoutSeconds
}
function ConvertFrom-JobsRepairDf {
    param([string]$Text)
    $rows = @($Text -split '\r?\n' | Where-Object { $_ -match '^\S+\s+[0-9]+\s+[0-9]+\s+[0-9]+\s+[0-9]+%\s+/data\s*$' })
    if ($rows.Count -ne 1 -or $rows[0] -notmatch '^\S+\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)\s+[0-9]+%\s+/data\s*$') { throw '无法可靠解析 df -k /data，不把未知空间当成 0 或成功。' }
    $total = [long]::Parse($Matches[1]); $used = [long]::Parse($Matches[2]); $free = [long]::Parse($Matches[3])
    if ($total -le 0 -or $used -gt $total -or $free -gt $total) { throw 'df 返回的空间值不合理。' }
    return [pscustomobject]@{ TotalKB = $total; FreeKB = $free; FreeMB = [math]::Floor($free / 1024) }
}
function Get-JobsRepairSpace {
    param([string]$Adb, [string]$Serial)
    return ConvertFrom-JobsRepairDf (Invoke-JobsRepairAdb $Adb @('-s', $Serial, 'shell', 'df', '-k', '/data'))
}
function Get-JobsRepairLocation {
    param([string]$Adb, [string]$Serial)
    $value = Invoke-JobsRepairAdb $Adb @('-s', $Serial, 'shell', 'pm', 'get-install-location')
    if ($value -notmatch '^([012])(?:\[|\s|$)') { throw '无法可靠解析安装位置。' }
    return [int]$Matches[1]
}
function Set-JobsRepairInstallLocation {
    param([string]$Adb, [string]$Serial, [string]$Avd)
    $before = Get-JobsRepairLocation $Adb $Serial
    if ($before -ne 0) { [void](Invoke-JobsRepairDeviceWrite $Adb $Serial $Avd @('shell', 'pm', 'set-install-location', '0')) }
    if ((Get-JobsRepairLocation $Adb $Serial) -ne 0) { throw '安装位置复测未恢复自动，停止。' }
    Write-JobsLog '安装位置已复测为自动。'
    Write-Host '安装位置：0（自动），复测通过。' -ForegroundColor Green
}
function Reset-JobsRepairCompileCache {
    param([string]$Adb, [string]$Serial, [string]$Avd)
    if (-not (Confirm-JobsRepairDanger '重置所选模拟器全部应用的 ART 编译状态，后续首次启动可能变慢；不删除应用数据。')) { return }
    $output = Invoke-JobsRepairDeviceWrite $Adb $Serial $Avd @('shell', 'cmd', 'package', 'compile', '--reset', '-a') -TimeoutSeconds 180
    if ($output -match '(?i)\b(error|failure|failed|unknown command|exception)\b') { throw ('编译状态重置未通过：' + $output) }
    Write-JobsLog '编译状态重置命令完成，空间仍需复测。'
}
function Remove-JobsRepairPackage {
    param([string]$Adb, [string]$Serial, [string]$Avd, [string]$AppId)
    if ($AppId -cnotmatch '^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$') { throw '包名必须是精确 Android applicationId，禁止通配符或 Shell 字符。' }
    $existing = Invoke-JobsRepairAdb $Adb @('-s', $Serial, 'shell', 'pm', 'path', $AppId)
    if ($existing -notmatch '(?m)^package:/') { throw ('模拟器中未找到精确包名：' + $AppId) }
    if (-not (Confirm-JobsRepairDanger ('卸载所选模拟器中的 ' + $AppId + '，该应用数据会丢失。'))) { return }
    $output = Invoke-JobsRepairDeviceWrite $Adb $Serial $Avd @('uninstall', $AppId)
    if ($output -cne 'Success') { throw ('卸载未确认成功：' + $output) }
    $remaining = Invoke-JobsRepairAdb $Adb @('-s', $Serial, 'shell', 'pm', 'list', 'packages', $AppId)
    if (@($remaining -split '\r?\n' | Where-Object { $_ -ceq ('package:' + $AppId) }).Count -gt 0) { throw '卸载后精确包名仍存在。' }
    Write-JobsLog '用户指定的单一应用卸载并复测完成。'
}
function ConvertTo-JobsRepairSize {
    param([string]$Size)
    if ($Size -cnotmatch '^([1-9][0-9]{0,15})([KMGT]?)$') { throw '容量须为正整数字节或大写 K/M/G/T，例如 8G。' }
    $factor = switch ($Matches[2]) { 'K' { 1KB } 'M' { 1MB } 'G' { 1GB } 'T' { 1TB } default { 1 } }
    $bytes = [decimal]::Parse($Matches[1]) * $factor
    if ($bytes -gt [long]::MaxValue) { throw '容量超过可支持范围。' }
    return [long]$bytes
}
function Assert-JobsRepairPlainPath {
    param([string]$Path, [switch]$Directory)
    $full = [IO.Path]::GetFullPath($Path)
    $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if ($Directory -and -not $item.PSIsContainer) { throw 'AVD 路径不是目录。' }
    $current = $item
    while ($null -ne $current) {
        if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ('拒绝 AVD 链接或重解析点：' + $current.FullName) }
        if ($current -is [IO.DirectoryInfo]) { $current = $current.Parent } else { $current = $current.Directory }
    }
    return $full
}
function Get-JobsRepairAvdConfig {
    param([string]$Avd)
    if ($Avd -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$') { throw 'AVD 名称无效。' }
    $root = $env:ANDROID_AVD_HOME
    if ([string]::IsNullOrWhiteSpace($root)) {
        $userHome = $env:ANDROID_USER_HOME
        if ([string]::IsNullOrWhiteSpace($userHome)) { $userHome = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.android' }
        $root = Join-Path $userHome 'avd'
    }
    if (-not [IO.Path]::IsPathRooted($root)) { throw 'AVD 根目录必须是绝对路径。' }
    $root = Assert-JobsRepairPlainPath $root -Directory
    $locator = Join-Path $root ($Avd + '.ini')
    $directory = Join-Path $root ($Avd + '.avd')
    if (Test-Path -LiteralPath $locator -PathType Leaf) {
        [void](Assert-JobsRepairPlainPath $locator)
        $text = [IO.File]::ReadAllText($locator)
        $absolute = @([regex]::Matches($text, '(?m)^path=(.+)\r?$'))
        $relative = @([regex]::Matches($text, '(?m)^path\.rel=(.+)\r?$'))
        if ($absolute.Count -gt 1 -or $relative.Count -gt 1) { throw 'AVD 定位文件有重复路径。' }
        if ($absolute.Count -eq 1) {
            $directory = $absolute[0].Groups[1].Value.TrimEnd("`r")
            if (-not [IO.Path]::IsPathRooted($directory)) { throw 'AVD path 必须是绝对路径。' }
        } elseif ($relative.Count -eq 1) {
            $value = $relative[0].Groups[1].Value.TrimEnd("`r")
            if ([IO.Path]::IsPathRooted($value) -or $value -match '(^|[\\/])\.\.([\\/]|$)') { throw 'AVD path.rel 不允许绝对路径或越界。' }
            $directory = Join-Path (Split-Path -Parent $root) $value
        }
    }
    $directory = Assert-JobsRepairPlainPath $directory -Directory
    $config = Assert-JobsRepairPlainPath (Join-Path $directory 'config.ini')
    if ((Get-Item -LiteralPath $config).PSIsContainer) { throw 'config.ini 必须是普通文件。' }
    $ids = @([regex]::Matches([IO.File]::ReadAllText($config), '(?m)^AvdId=([^\r\n]+)\r?$'))
    if ($ids.Count -ne 1 -or $ids[0].Groups[1].Value.Trim() -cne $Avd) { throw 'config.ini 的唯一 AvdId 与目标不一致，停止自动扩容。' }
    $locatorHash = $null
    if (Test-Path -LiteralPath $locator -PathType Leaf) { $locatorHash = (Get-FileHash -LiteralPath $locator -Algorithm SHA256).Hash }
    return [pscustomobject]@{ Directory = $directory; Config = $config; Locator = $locator; Avd = $Avd; ConfigHash = (Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash; LocatorHash = $locatorHash }
}
function Assert-JobsRepairSameAvdConfig {
    param($Paths)
    $current = Get-JobsRepairAvdConfig $Paths.Avd
    foreach ($property in @('Directory', 'Config', 'Locator', 'ConfigHash', 'LocatorHash')) {
        if ($current.$property -cne $Paths.$property) { throw '确认或停机期间 AVD 路径/配置发生变化，拒绝修改或覆盖。' }
    }
}
function Assert-JobsRepairAvdStopped {
    param([string]$Adb, [string]$Serial, [string]$Directory)
    if ($Serial -cin @(Get-JobsRepairDevices $Adb)) { throw '模拟器仍在线，拒绝修改 AVD。' }
    # qemu 的命令行会随版本变化；保守要求所有本机 Emulator 进程退出，不误杀其它 AVD。
    $processes = @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop | Where-Object { $_.Name -match '^(emulator|qemu-system-[A-Za-z0-9_-]+)(\.exe)?$' })
    if ($processes.Count -gt 0) { throw '仍有 Emulator / QEMU 进程，请先正常关闭其它 AVD 后重试。' }
    $locks = @(Get-ChildItem -LiteralPath $Directory -Force -Recurse -ErrorAction Stop | Where-Object { $_.Name -match '\.lock$' })
    if ($locks.Count -gt 0) { throw 'AVD 锁仍存在；不自动删除锁，请正常退出模拟器后重试。' }
}
function Stop-JobsRepairAvd {
    param([string]$Adb, [string]$Serial, [string]$Avd, [string]$Directory, [int]$TimeoutSeconds = 45)
    [void](Invoke-JobsRepairDeviceWrite $Adb $Serial $Avd @('emu', 'kill'))
    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        try { Assert-JobsRepairAvdStopped $Adb $Serial $Directory; return } catch { $reason = $_.Exception.Message }
        Start-Sleep -Milliseconds 500
    } while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds)
    throw ('未确认模拟器安全退出，尚未备份或修改配置：' + $reason)
}
function Assert-JobsRepairDefaultStorage {
    param($Paths, [string]$Avd)
    $text = [IO.File]::ReadAllText($Paths.Config)
    if ($text -match '(?m)^\s*disk\.dataPartition\.(path|initPath)\s*=') { throw 'AVD 配置含显式数据镜像路径，不能仅备份默认目录后自动扩容，请在 Device Manager 手工处理。' }
    $processes = @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop | Where-Object { $_.Name -match '^(emulator|qemu-system-[A-Za-z0-9_-]+)(\.exe)?$' })
    $associated = @()
    foreach ($process in $processes) {
        if ([string]::IsNullOrWhiteSpace($process.CommandLine)) { throw '无法读取 Emulator 进程参数，不能确认数据目录，停止自动扩容。' }
        if ($process.CommandLine -match ('(?:^|\s)-avd\s+"?' + [regex]::Escape($Avd) + '"?(?:\s|$)')) { $associated += $process }
        if ($process.CommandLine -match '(?:^|\s)-(data|datadir)(?:\s|=)') { throw 'Emulator 使用 -data / -datadir 覆盖数据路径，停止自动扩容；只读和轻量修复仍可使用。' }
    }
    if ($associated.Count -eq 0) { throw '未能将 AVD 与本机 Emulator 启动参数唯一关联，停止自动扩容。' }
}
function Backup-JobsRepairAvd {
    param($Paths, [long]$AdditionalBytes = 0)
    Assert-JobsRepairSameAvdConfig $Paths
    $items = @(Get-ChildItem -LiteralPath $Paths.Directory -Force -Recurse -ErrorAction Stop)
    foreach ($item in $items) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'AVD 内含链接，无法保证完整备份，停止。' }
    }
    $bytes = ($items | Where-Object { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum).Sum
    $drive = New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($Paths.Directory))
    if ($drive.AvailableFreeSpace -lt ([decimal]$bytes + $AdditionalBytes + 1GB)) { throw '磁盘空间不足以完整备份 AVD、预留目标分区增长和 1 GB 余量，尚未修改配置。' }
    $backup = Join-Path (Split-Path -Parent $Paths.Directory) ('.jobs-repair-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($backup)
    $destination = Join-Path $backup 'avd'
    Copy-Item -LiteralPath $Paths.Directory -Destination $destination -Recurse -Force -ErrorAction Stop
    foreach ($item in @($items | Where-Object { -not $_.PSIsContainer })) {
        $relative = $item.FullName.Substring($Paths.Directory.Length).TrimStart([char[]]'\/')
        $copied = Join-Path $destination $relative
        if ((Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash -cne (Get-FileHash -LiteralPath $copied -Algorithm SHA256).Hash) { throw ('AVD 备份校验失败，保留现场：' + $backup) }
    }
    if (Test-Path -LiteralPath $Paths.Locator -PathType Leaf) {
        $locatorBackup = Join-Path $backup 'locator.ini'
        Copy-Item -LiteralPath $Paths.Locator -Destination $locatorBackup -Force -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $locatorBackup -Algorithm SHA256).Hash -cne $Paths.LocatorHash) { throw ('AVD 定位文件备份校验失败，保留现场：' + $backup) }
    }
    Write-Host ('完整 AVD 备份（请保留）：' + $backup) -ForegroundColor Cyan
    Write-JobsLog '完整 AVD 备份与 SHA-256 校验完成。'
    return $backup
}
function Get-JobsRepairConfiguredSize {
    param([string]$Text)
    $matches = @([regex]::Matches($Text, '(?m)^disk\.dataPartition\.size\s*=\s*([^\r\n]+)\r?$'))
    if ($matches.Count -ne 1) { throw '现有 data 分区容量缺失或重复，无法安全判断不缩容，停止。' }
    return ConvertTo-JobsRepairSize $matches[0].Groups[1].Value.Trim()
}
function Set-JobsRepairAvdSize {
    param($Paths, [string]$TargetDataSize, [string]$Adb, [string]$Serial)
    Assert-JobsRepairAvdStopped $Adb $Serial $Paths.Directory
    Assert-JobsRepairSameAvdConfig $Paths
    $bytes = [IO.File]::ReadAllBytes($Paths.Config)
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    $oldSize = Get-JobsRepairConfiguredSize $text
    $newSize = ConvertTo-JobsRepairSize $TargetDataSize
    if ($newSize -le $oldSize) { throw '目标容量必须严格大于现有配置，不允许缩容或无效扩容。' }
    foreach ($image in @(Get-ChildItem -LiteralPath $Paths.Directory -File -Force | Where-Object { $_.Name -match '^userdata.*\.img$' })) {
        if ($image.Length -gt $newSize) { throw '目标容量小于现有 userdata 镜像，不允许缩容。' }
    }
    $backup = Backup-JobsRepairAvd $Paths -AdditionalBytes $newSize
    Assert-JobsRepairAvdStopped $Adb $Serial $Paths.Directory
    Assert-JobsRepairSameAvdConfig $Paths
    # 独占 config 复核原字节后原地改写；不改其它配置，不删除 userdata/qcow2/锁。
    $stream = [IO.File]::Open($Paths.Config, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $current = New-Object byte[] $stream.Length
        if ($stream.Read($current, 0, $current.Length) -ne $current.Length -or [Convert]::ToBase64String($current) -cne [Convert]::ToBase64String($bytes)) { throw '备份期间配置发生变化，拒绝覆盖。' }
        $updated = [regex]::Replace($text, '(?m)^(disk\.dataPartition\.size\s*=\s*)[^\r\n]+', ('${1}' + $TargetDataSize))
        $output = (New-Object Text.UTF8Encoding($false)).GetBytes($updated)
        $stream.Position = 0; $stream.Write($output, 0, $output.Length); $stream.SetLength($output.Length); $stream.Flush()
    } finally { $stream.Dispose() }
    if ((Get-JobsRepairConfiguredSize ([IO.File]::ReadAllText($Paths.Config))) -ne $newSize) { throw ('配置回读失败，请保留备份：' + $backup) }
    Write-JobsLog 'AVD 目标容量配置已写入并回读；实际分区尚待冷启动复测。'
    return $backup
}
function Start-JobsRepairColdAvd {
    param([string]$Emulator, [string]$Avd, [string]$Serial)
    if ($Serial -cnotmatch '^emulator-([0-9]+)$') { throw '模拟器序列号无效。' }
    $port = [int]$Matches[1]
    if ($port -lt 5554 -or $port -gt 5682 -or $port % 2 -ne 0) { throw '模拟器控制台端口不在支持范围。' }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Emulator
    $start.Arguments = (@(@('-avd', $Avd, '-port', [string]$port, '-no-snapshot-load', '-no-snapshot-save') | ForEach-Object { Quote-JobsArgument $_ }) -join ' ')
    $start.UseShellExecute = $false
    $process = [Diagnostics.Process]::Start($start)
    if ($null -eq $process) { throw '无法冷启动模拟器。' }
    $process.Dispose()
}
function Wait-JobsRepairBoot {
    param([string]$Adb, [string]$Serial, [string]$Avd, [int]$TimeoutSeconds = 180)
    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        if ($Serial -cin @(Get-JobsRepairDevices $Adb)) {
            [void](Assert-JobsRepairEmulator $Adb $Serial $Avd)
            if ((Invoke-JobsRepairAdb $Adb @('-s', $Serial, 'shell', 'getprop', 'sys.boot_completed')) -ceq '1') { return }
        }
        Start-Sleep -Milliseconds 1000
    } while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds)
    throw '冷启动等待超时；配置和备份已保留，不报告扩容成功。'
}
function Expand-JobsRepairAvd {
    param([string]$Adb, [string]$Serial, [string]$Avd, [string]$TargetDataSize, [int]$ThresholdMB)
    $emulator = Get-JobsRepairTool 'emulator'
    $paths = Get-JobsRepairAvdConfig $Avd
    $before = Get-JobsRepairSpace $Adb $Serial
    $oldSize = Get-JobsRepairConfiguredSize ([IO.File]::ReadAllText($paths.Config))
    $targetSize = ConvertTo-JobsRepairSize $TargetDataSize
    if ($targetSize -le $oldSize -or $targetSize -le ([decimal]$before.TotalKB * 1024)) { throw '目标容量必须大于现有配置与实际 /data 总量，不允许缩容或无效扩容。' }
    Assert-JobsRepairDefaultStorage $paths $Avd
    $description = '关闭 ' + $Avd + '，完整备份 AVD 后把 disk.dataPartition.size 调为 ' + $TargetDataSize + '，随后冷启动并复测。' + [Environment]::NewLine +
        '配置：' + $paths.Config + [Environment]::NewLine + '已有 userdata 不保证随配置扩容；Emulator 可能迁移 userdata/qcow2，需保留完整备份。没有完整备份就停止；不清空数据。'
    if (-not (Confirm-JobsRepairDanger $description)) { return }
    Stop-JobsRepairAvd $Adb $Serial $Avd $paths.Directory
    $backup = Set-JobsRepairAvdSize $paths $TargetDataSize $Adb $Serial
    Start-JobsRepairColdAvd $emulator $Avd $Serial
    Wait-JobsRepairBoot $Adb $Serial $Avd
    $after = Get-JobsRepairSpace $Adb $Serial
    Write-Host ('复测 /data：总量 ' + $after.TotalKB + ' KB，可用 ' + $after.FreeMB + ' MB；备份：' + $backup)
    if ($after.TotalKB -le $before.TotalKB) { throw '配置已调整，但实际 /data 总量未增加，不能确认扩容成功。保留完整备份，不自动清空 userdata。' }
    if ($after.FreeMB -lt $ThresholdMB) { throw '实际 /data 总量增加，但可用空间仍低于阈值，尚未解决空间不足。' }
    Write-JobsLog '冷启动后实际分区总量增加且可用空间达到阈值，扩容复测通过。'
    Write-Host '实际分区容量增加且空间达到阈值，复测通过。' -ForegroundColor Green
}
function Invoke-JobsAndroidRepair {
    param([switch]$Check, [string]$Serial, [string]$AppId, [ValidateRange(1, 1048576)][int]$ThresholdMB = 800, [string]$TargetDataSize = '8G')
    [void](ConvertTo-JobsRepairSize $TargetDataSize)
    if ($AppId -and $AppId -cnotmatch '^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$') { throw 'AppId 必须是精确包名。' }
    Write-Host ('Jobs Android 模拟器检测与修复 · 来源：' + $PSScriptRoot) -ForegroundColor Cyan
    Write-Host ('用途：检查 INSTALL_FAILED_INSUFFICIENT_STORAGE；仅正在运行的本机 Android Emulator。' + [Environment]::NewLine +
        '影响：默认恢复所选模拟器安装位置为自动，并复测 /data；可选编译缓存重置、单一精确包名卸载、完整备份后调整 AVD 配置并冷启动。' + [Environment]::NewLine +
        '危险行为另需精确 YES；不操作真机、不自动卸载内置应用、不执行 wipe-data、不安装工具、不修改代理或全局环境。' + [Environment]::NewLine +
        '阈值：' + $ThresholdMB + ' MB；扩容目标：' + $TargetDataSize + '；日志：' + (Join-Path (Get-JobsInstallRoot) 'logs'))
    if (-not $Check -and (Read-JobsRepairInput '直接回车授权开始，任意非空输入取消').Length -gt 0) { throw '已取消。' }
    $adb = Get-JobsRepairTool 'adb'
    $devices = @(Get-JobsRepairDevices $adb)
    if ($Serial) {
        if ($Serial -cnotmatch '^emulator-[0-9]+$' -or $Serial -cnotin $devices) { throw '指定目标不是在线本机模拟器。' }
        $devices = @($Serial)
    }
    if ($devices.Count -eq 0) { throw '没有在线 Android Emulator；真机、离线及未授权设备均已排除。请先启动已有 AVD。' }
    if ($Check) {
        foreach ($device in $devices) {
            $avd = Assert-JobsRepairEmulator $adb $device
            $location = Get-JobsRepairLocation $adb $device
            $space = Get-JobsRepairSpace $adb $device
            Write-Host ($device + ' / ' + $avd + '：安装位置 ' + $location + '；/data 总量 ' + $space.TotalKB + ' KB，可用 ' + $space.FreeMB + ' MB。')
            try { $config = Get-JobsRepairAvdConfig $avd; Write-Host ('配置：' + $config.Config) } catch { Write-Host ('AVD 配置未定位：' + $_.Exception.Message) -ForegroundColor Yellow }
            if ($location -ne 0 -or $space.FreeMB -lt $ThresholdMB) { throw '只读检测发现安装位置或空间异常；没有执行修复、日志写入或配置变更。' }
        }
        Write-Host '只读检测通过；未执行设备写入、备份、配置修改或冷启动。' -ForegroundColor Green
        return
    }
    if ($devices.Count -eq 1) { $Serial = $devices[0] } else {
        for ($index = 0; $index -lt $devices.Count; $index++) { Write-Host ('{0}、{1}' -f ($index + 1), $devices[$index]) }
        $answer = Read-JobsRepairInput '选择模拟器编号，回车取消'
        $number = 0
        if (-not [int]::TryParse($answer, [ref]$number) -or $number -lt 1 -or $number -gt $devices.Count) { throw '未选择有效模拟器。' }
        $Serial = $devices[$number - 1]
    }
    $avd = Assert-JobsRepairEmulator $adb $Serial
    Write-Host ('目标：' + $Serial + ' / ' + $avd) -ForegroundColor Cyan
    Write-JobsLog '开始模拟器检测与修复，目标身份已核对。'
    Set-JobsRepairInstallLocation $adb $Serial $avd
    if ($AppId) { Remove-JobsRepairPackage $adb $Serial $avd $AppId }
    $space = Get-JobsRepairSpace $adb $Serial
    Write-Host ('/data 可用空间：' + $space.FreeMB + ' MB')
    if ($space.FreeMB -lt $ThresholdMB) {
        Reset-JobsRepairCompileCache $adb $Serial $avd
        $space = Get-JobsRepairSpace $adb $Serial
        Write-Host ('缓存处理后 /data 可用空间：' + $space.FreeMB + ' MB')
        if ($space.FreeMB -lt $ThresholdMB -and -not $AppId) {
            $package = Read-JobsRepairInput '可输入要卸载的精确应用包名；回车跳过（另需 YES）'
            if ($package) { Remove-JobsRepairPackage $adb $Serial $avd $package }
            $space = Get-JobsRepairSpace $adb $Serial
        }
        if ($space.FreeMB -lt $ThresholdMB) { Expand-JobsRepairAvd $adb $Serial $avd $TargetDataSize $ThresholdMB }
    }
    [void](Assert-JobsRepairEmulator $adb $Serial $avd)
    $final = Get-JobsRepairSpace $adb $Serial
    if ((Get-JobsRepairLocation $adb $Serial) -ne 0 -or $final.FreeMB -lt $ThresholdMB) {
        Write-JobsLog '最终复测未解决空间或安装位置异常。'
        throw ('最终复测仍有异常；/data 可用 ' + $final.FreeMB + ' MB，未宣称修复成功。')
    }
    Write-JobsLog '最终复测通过：安装位置自动且可用空间达到阈值。'
    Write-Host ('检测与修复复测通过：安装位置自动，/data 可用 ' + $final.FreeMB + ' MB。') -ForegroundColor Green
}
function Invoke-JobsFeature {
    param([Parameter(Mandatory = $true)][string]$Target)
    $path = Resolve-JobsTarget $Target
    $desktop = [Environment]::GetFolderPath('DesktopDirectory')
    if (-not $desktop -or [IO.Path]::GetFullPath($path).TrimEnd([char[]]'\/') -ine [IO.Path]::GetFullPath($desktop).TrimEnd([char[]]'\/')) { throw '本功能只接受系统桌面空白目标。' }
    Invoke-JobsAndroidRepair
}
Export-ModuleMember -Function Invoke-JobsFeature

# Common.psm1 | Windows@Extension 基础设施
# Created by Jobs on 2026年10月18日，星期日.
# 仅含路径、参数、进程及日志工具；每个功能包内嵌同版本副本。
Set-StrictMode -Version 2.0

function Quote-JobsArgument {
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string]$Value)

    if ($null -eq $Value) {
        $Value = ''
    }
    if ($Value.IndexOf([char]0) -ge 0) {
        throw '参数不能包含空字符。'
    }

    # Windows argv 会在双引号前折叠反斜杠，结尾反斜杠也必须成对。
    $quoted = New-Object System.Text.StringBuilder
    [void]$quoted.Append('"')
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq [char]92) {
            $slashes++
            continue
        }
        if ($character -eq [char]34) {
            [void]$quoted.Append([char]92, (2 * $slashes + 1))
            [void]$quoted.Append([char]34)
        }
        else {
            if ($slashes -gt 0) {
                [void]$quoted.Append([char]92, $slashes)
            }
            [void]$quoted.Append($character)
        }
        $slashes = 0
    }
    if ($slashes -gt 0) {
        [void]$quoted.Append([char]92, (2 * $slashes))
    }
    [void]$quoted.Append('"')
    return $quoted.ToString()
}

function Resolve-JobsTarget {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Target)

    $sentinel = '|JobsPathEnd'
    if ($Target.EndsWith($sentinel, [StringComparison]::Ordinal)) {
        $Target = $Target.Substring(0, $Target.Length - $sentinel.Length)
    }
    if ([string]::IsNullOrEmpty($Target) -or -not (Test-Path -LiteralPath $Target)) {
        throw '目标文件或文件夹不存在，请重新打开右键菜单。'
    }
    $item = Get-Item -LiteralPath $Target -Force -ErrorAction Stop
    if ($item.PSProvider.Name -ne 'FileSystem') {
        throw '右键目标必须是本地文件系统路径。'
    }
    return $item.FullName
}

function Get-JobsDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Target)

    $resolved = Resolve-JobsTarget -Target $Target
    $item = Get-Item -LiteralPath $resolved -Force -ErrorAction Stop
    if ($item.PSIsContainer) {
        return $item.FullName
    }
    return $item.Directory.FullName
}

function Find-JobsExecutable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string[]]$Candidates = @()
    )

    foreach ($candidate in @($Name) + $Candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }
        $command = Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $command) {
            return $command.Source
        }
    }
    return $null
}

function Invoke-JobsProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory,
        [ValidateRange(1, 86400)][int]$TimeoutSeconds = 30
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $quotedArguments = @($Arguments | ForEach-Object { Quote-JobsArgument -Value $_ })
    $startInfo.Arguments = $quotedArguments -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $startInfo.StandardErrorEncoding = New-Object System.Text.UTF8Encoding($false)
    if (-not [string]::IsNullOrEmpty($WorkingDirectory)) {
        $startInfo.WorkingDirectory = Get-JobsDirectory -Target $WorkingDirectory
    }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw '无法启动目标程序。'
        }
        # 两条流同时读取，避免任一缓冲区写满时进程互相等待。
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $cleanupClock = [Diagnostics.Stopwatch]::StartNew()
            $treeStopped = $false
            try {
                $killTree = $process.GetType().GetMethod('Kill', [type[]]@([bool]))
                if ($null -ne $killTree) {
                    [void]$killTree.Invoke($process, [object[]]@($true))
                    $treeStopped = $true
                }
            }
            catch {
                # 旧运行时或平台不支持整树停止时，继续下方的原生兜底。
            }
            if (-not $treeStopped -and [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
                $taskKiller = New-Object System.Diagnostics.Process
                try {
                    # Framework 5.1 没有 Kill(true)，只对本次 PID 树调用系统工具。
                    $taskKiller.StartInfo.FileName = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'taskkill.exe'
                    $taskKiller.StartInfo.Arguments = '/PID ' + $process.Id.ToString([Globalization.CultureInfo]::InvariantCulture) + ' /T /F'
                    $taskKiller.StartInfo.UseShellExecute = $false
                    $taskKiller.StartInfo.CreateNoWindow = $true
                    $taskKiller.StartInfo.RedirectStandardOutput = $true
                    $taskKiller.StartInfo.RedirectStandardError = $true
                    if (-not $process.HasExited -and $taskKiller.Start()) {
                        $killOutput = $taskKiller.StandardOutput.ReadToEndAsync()
                        $killError = $taskKiller.StandardError.ReadToEndAsync()
                        $remaining = [Math]::Max(0, 5000 - [int]$cleanupClock.ElapsedMilliseconds)
                        if ($taskKiller.WaitForExit($remaining)) {
                            $treeStopped = $taskKiller.ExitCode -eq 0
                        }
                        else {
                            $taskKiller.Kill()
                        }
                    }
                }
                catch {
                    # taskkill 失败或进程同时退出时，继续尝试精确停止父进程。
                }
                finally {
                    $taskKiller.Dispose()
                }
            }
            try {
                if (-not $treeStopped -and -not $process.HasExited) {
                    $process.Kill()
                }
                $remaining = [Math]::Max(0, 5000 - [int]$cleanupClock.ElapsedMilliseconds)
                [void]$process.WaitForExit($remaining)
            }
            catch {
                # 进程可能在超时与 Kill 之间退出；不输出原始命令或参数。
            }
            throw (New-Object System.TimeoutException('目标程序执行超时，已执行本次进程树停止流程。'))
        }
        $readTasks = [System.Threading.Tasks.Task[]]@($outputTask, $errorTask)
        if (-not [System.Threading.Tasks.Task]::WaitAll($readTasks, 5000)) {
            throw '目标程序已退出，但输出管道未能按时关闭。'
        }
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdOut = $outputTask.GetAwaiter().GetResult()
            StdErr = $errorTask.GetAwaiter().GetResult()
        }
    }
    finally {
        $process.Dispose()
    }
}

function Get-JobsInstallRoot {
    $local = [Environment]::GetEnvironmentVariable('LOCALAPPDATA')
    if ([string]::IsNullOrWhiteSpace($local)) { $local = [Environment]::GetFolderPath('LocalApplicationData') }
    if ([string]::IsNullOrWhiteSpace($local)) { throw '无法定位当前用户本地应用数据。' }
    $manifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Extension.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw '缺少本功能的 Extension.json。' }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.Id -notmatch '^[a-z][a-z0-9-]+$') { throw '本功能标识不合法。' }
    return Join-Path (Join-Path $local 'Jobs/WindowsExtension/extensions') $manifest.Id
}

function Write-JobsLog {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Message)

    $logDirectory = Join-Path (Get-JobsInstallRoot) 'logs'
    [void][IO.Directory]::CreateDirectory($logDirectory)
    # 调用方使用固定状态文案；额外清除误传的 URL/路径和换行，避免日志泄露。
    $safeMessage = $Message -replace '[\r\n\x00-\x1f]', ' '
    $safeMessage = $safeMessage -replace '(?i)[a-z][a-z0-9+.-]*://\S+', '[地址已省略]'
    $safeMessage = $safeMessage -replace '\S+@\S+:\S+', '[地址已省略]'
    $safeMessage = $safeMessage -replace '(?i)(?:[a-z]:\\|\\\\)\S+', '[路径已省略]'
    $safeMessage = $safeMessage -replace '(?<!\w)/\S+', '[路径已省略]'
    $line = [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss') + ' ' + $safeMessage + [Environment]::NewLine
    $logFile = Join-Path $logDirectory ([DateTime]::Now.ToString('yyyy-MM-dd') + '.log')
    [IO.File]::AppendAllText($logFile, $line, (New-Object System.Text.UTF8Encoding($true)))
}

Export-ModuleMember -Function Quote-JobsArgument, Resolve-JobsTarget, Get-JobsDirectory, Find-JobsExecutable, Invoke-JobsProcess, Get-JobsInstallRoot, Write-JobsLog

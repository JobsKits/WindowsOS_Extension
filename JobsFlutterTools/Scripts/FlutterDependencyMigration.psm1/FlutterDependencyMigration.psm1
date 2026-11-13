# FlutterDependencyMigration.psm1 | 一键迁移与原始缓存融合。
# 只复用本包引擎和项目 FVM Dart；默认私库，写入前预检，ZIP 校验后才可删除本次产物。

# Jobs enter-choice emphasis is display-only; input and business decisions stay with callers.
function Test-JobsEnterChoiceColor {
    if ((Test-Path Env:NO_COLOR) -or $env:TERM -ieq 'dumb' -or $env:PLAIN_OUTPUT -eq '1') { return $false }
    $consoleType = [Console]
    if ($null -eq $consoleType.GetProperty('IsInputRedirected') -or $null -eq $consoleType.GetProperty('IsOutputRedirected')) { return $false }
    return ($Host.Name -ceq 'ConsoleHost' -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected)
}
# Older hosts keep native colors without sending unsupported bold escape sequences.
function Test-JobsEnterChoiceBold {
    $property = $Host.UI.PSObject.Properties['SupportsVirtualTerminal']
    return ($null -ne $property -and [bool]$property.Value)
}
# Separate ordinary question text from Enter and arbitrary-input options without changing words.
function Get-JobsEnterChoiceParts {
    param([string]$Text)
    $red = '(?:(?:\u8f93\u5165)?(?:\u4efb\u610f(?:\u975e\u7a7a)?(?:\u5b57\u7b26|\u5185\u5bb9|\u6587\u5b57|\u8f93\u5165)?|\u975e\u7a7a(?:\u8f93\u5165|\u5b57\u7b26|\u5185\u5bb9)?|(?:\u5176\u5b83|\u5176\u4ed6)(?:\u975e\u7a7a)?(?:\u8f93\u5165|\u5185\u5bb9|\u5b57\u7b26)?))|(?:any\s+(?:(?:other|non[- ]empty)\s+)?(?:input|text|characters?)|non[- ]empty\s+input)'
    $green = '(?:(?:\u76f4\u63a5|\u53ea\u9700|\u4ec5(?:\u9700)?|\u6309(?:\u4e0b)?|\u7a7a)?\s*\u56de\u8f66|(?:press\s+)?\bEnter\b(?!\s+(?:YES|REPAIR|CLEAN|CONTINUE)\b))'
    $pattern = '(?is)(?<red>(?:' + $red + ')[^;\uFF1B\r\n]*?(?=[;\uFF1B\r\n]|\z))|(?<green>(?:' + $green + ')[^;\uFF1B\r\n]*?(?=(?:' + $red + ')|[;\uFF1B\r\n]|\z))'
    $offset = 0
    foreach ($match in [regex]::Matches($Text, $pattern)) {
        if ($match.Index -gt $offset) { [pscustomobject]@{ Text = $Text.Substring($offset, $match.Index - $offset); Color = '' } }
        $prefix = [regex]::Split($Text.Substring(0, $match.Index), '[;\uFF1B\r\n]')[-1]
        $typed = $prefix -match '(?i)(?:\u8f93\u5165|\u952e\u5165|type|enter)\s*(?:\u5927\u5199\s*)?(?:YES|REPAIR|CLEAN|CONTINUE)\b|\u7cbe\u786e\u8f93\u5165|\u8f93\u5165[^;\uFF1B\r\n]*[\u540e\u518d]\s*$'
        $color = if ($match.Groups['red'].Success) { 'Red' } elseif ($typed) { '' } else { 'Green' }
        [pscustomobject]@{ Text = $match.Value; Color = $color }
        $offset = $match.Index + $match.Length
    }
    if ($offset -lt $Text.Length) { [pscustomobject]@{ Text = $Text.Substring($offset); Color = '' } }
}
# Native host text remains plain in information streams and logs; bold control is console-only.
function Write-JobsEnterChoiceText {
    [CmdletBinding()]
    param([Parameter(Position=0)][AllowNull()][object]$Object, [switch]$NoNewline, [ConsoleColor]$ForegroundColor, [ConsoleColor]$BackgroundColor, [object]$Separator = ' ')
    $text = if ($Object -is [array]) { $Object -join [string]$Separator } else { [string]$Object }
    if (-not (Test-JobsEnterChoiceColor)) {
        Write-Host $Object -NoNewline:$NoNewline -Separator $Separator
        return
    }
    $normal = @{}
    if ($PSBoundParameters.ContainsKey('ForegroundColor')) { $normal.ForegroundColor = $ForegroundColor }
    if ($PSBoundParameters.ContainsKey('BackgroundColor')) { $normal.BackgroundColor = $BackgroundColor }
    foreach ($part in @(Get-JobsEnterChoiceParts $text)) {
        if (-not $part.Color) { Write-Host $part.Text -NoNewline @normal; continue }
        $bold = Test-JobsEnterChoiceBold
        if ($bold) { [Console]::Write(([string][char]27) + '[1m') }
        try { Write-Host $part.Text -ForegroundColor $part.Color -NoNewline }
        finally { if ($bold) { [Console]::Write(([string][char]27) + '[0m') } }
    }
    if (-not $NoNewline) { Write-Host }
}
# Delegate the original reader, including secure input and EOF behavior, after prompt display.
function Read-JobsEnterChoiceHost {
    [CmdletBinding()]
    param([Parameter(Position=0)][string]$Prompt, [switch]$AsSecureString, [switch]$MaskInput)
    if ($AsSecureString -or $MaskInput -or -not (Test-JobsEnterChoiceColor) -or @((Get-JobsEnterChoiceParts $Prompt) | Where-Object { $_.Color }).Count -eq 0) {
        return (Read-Host @PSBoundParameters)
    }
    Write-JobsEnterChoiceText ($Prompt + ': ') -NoNewline
    return (Read-Host)
}

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:MigrationScripts = Split-Path -Parent $PSScriptRoot
$script:MigrationLog = $null
Import-Module (Join-Path $script:MigrationScripts 'Common.psm1') -DisableNameChecking

function Read-JobsMigrationLine {
    param([string]$Prompt)
    if (-not [string]::IsNullOrEmpty($Prompt)) { Write-JobsEnterChoiceText ($Prompt + '：') -NoNewline }
    return [Console]::ReadLine()
}

# 只有交互控制台使用选项颜色，重定向和明确的纯文本环境保持无色。
function Test-JobsMigrationPromptColor {
    return (-not (Test-Path Env:NO_COLOR) -and $env:TERM -ine 'dumb' -and $Host.Name -ceq 'ConsoleHost' -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected)
}

# 仅给备份选项着色，读取和返回保持独立，空格及输入结束原样传回。
function Read-JobsMigrationBackupChoice {
    Write-Host '是否备份将被覆盖的当前文件？'
    if (Test-JobsMigrationPromptColor) {
        Write-JobsEnterChoiceText '回车 = 备份' -ForegroundColor Green -NoNewline
        Write-Host '；' -NoNewline
        Write-JobsEnterChoiceText '任意字符再回车 = 不备份直接覆盖：' -ForegroundColor Red -NoNewline
    } else {
        Write-JobsEnterChoiceText '回车 = 备份；任意字符再回车 = 不备份直接覆盖：' -NoNewline
    }
    return (Read-JobsMigrationLine '')
}

# 统一取得系统桌面，供导出和覆盖备份的空输入默认值使用。
function Get-JobsMigrationDesktop {
    return [Environment]::GetFolderPath('DesktopDirectory')
}

# 冲突计数必须来自本次只读计划，旧或含歧义的响应不能进入覆盖选择。
function Get-JobsMigrationConflictCount {
    param([string]$Preview)
    $counts = @([regex]::Matches($Preview, '(?m)^JOBS_MIGRATION_CONFLICTS=(0|[1-9][0-9]*)\r?$'))
    if ($counts.Count -ne 1) { throw '预检未返回唯一冲突计数，请更新完整工具包后重试；未导入。' }
    return [long]::Parse($counts[0].Groups[1].Value)
}

# fzf 默认推荐导入源；工具不可用时回退编号，取消或无结果不选择任何策略。
function Select-JobsMigrationConflictPolicy {
    $labels = @('使用导入源（推荐）— 覆盖冲突文件', '保留本机现有内容 — 跳过冲突文件')
    $fzf = Find-JobsExecutable -Name 'fzf.exe' -Candidates @('fzf')
    if ($fzf) {
        try {
            $health = Invoke-JobsProcess -FilePath $fzf -Arguments @('--version') -TimeoutSeconds 5
            if ($health.ExitCode -ne 0) { $fzf = $null }
        } catch [Management.Automation.PipelineStoppedException] { throw }
        catch { $fzf = $null }
    }
    if ($fzf) {
        $saved = @{}
        foreach ($name in @('FZF_DEFAULT_OPTS', 'FZF_DEFAULT_OPTS_FILE')) { $saved[$name] = @{ Present = (Test-Path ('Env:' + $name)); Value = [Environment]::GetEnvironmentVariable($name, 'Process') } }
        $savedEncoding = $OutputEncoding
        $savedConsoleEncoding = [Console]::OutputEncoding
        try {
            $env:FZF_DEFAULT_OPTS = ''
            $env:FZF_DEFAULT_OPTS_FILE = ''
            $OutputEncoding = New-Object Text.UTF8Encoding($false)
            [Console]::OutputEncoding = $OutputEncoding
            $global:LASTEXITCODE = -1
            $selection = @($labels | & $fzf --no-multi --no-sort --height=40% --layout=reverse --border --prompt '冲突处理 > ' --header '↑/↓ 选择；Enter 确认；Esc / Ctrl+C 取消')
            $code = $LASTEXITCODE
        } finally {
            $OutputEncoding = $savedEncoding
            [Console]::OutputEncoding = $savedConsoleEncoding
            foreach ($name in $saved.Keys) {
                if ($saved[$name].Present) { [Environment]::SetEnvironmentVariable($name, $saved[$name].Value, 'Process') }
                else { Remove-Item ('Env:' + $name) -ErrorAction SilentlyContinue }
            }
        }
        if ($code -in @(1, 130)) { return $null }
        if ($code -ne 0) { throw ('冲突选择器失败（退出码 ' + $code + '），未导入。') }
        if ($selection.Count -ne 1 -or $selection[0] -cnotin $labels) { throw '冲突选择器返回未知结果，未导入。' }
        if ($selection[0] -ceq $labels[0]) { return 'source' }
        return 'existing'
    }
    Write-JobsMigrationMessage 'fzf 不可用，改用编号选择冲突处理方式。'
    Write-Host ('1、' + $labels[0] + [Environment]::NewLine + '2、' + $labels[1])
    while ($true) {
        $answer = Read-JobsMigrationLine '直接回车或输入 1 = 使用导入源；2 = 保留本机；q / Esc / Ctrl+C 取消'
        if ($null -eq $answer -or $answer -ceq 'q' -or [string]::Equals($answer, [string][char]27, [StringComparison]::Ordinal)) { return $null }
        if ($answer.Length -eq 0 -or $answer -ceq '1') { return 'source' }
        if ($answer -ceq '2') { return 'existing' }
        Write-JobsMigrationMessage '请输入 1 或 2；q 取消。'
    }
}

function Write-JobsMigrationMessage {
    param([string]$Message)
    $safe = $Message -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@'
    $safe = $safe -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]'
    Write-Host $safe
    if ($script:MigrationLog) {
        [IO.File]::AppendAllText($script:MigrationLog, $safe + [Environment]::NewLine, (New-Object Text.UTF8Encoding($true)))
    }
}

function ConvertFrom-JobsMigrationPath {
    param([string]$Text)
    if ([IO.Directory]::Exists($Text)) { return [IO.Path]::GetFullPath($Text) }
    $value = $Text.Trim()
    if ($value.StartsWith('& ')) { $value = $value.Substring(2).TrimStart() }
    if ($value.Length -ge 2 -and $value[0] -eq [char]34 -and $value[-1] -eq [char]34) {
        $value = $value.Substring(1, $value.Length - 2)
    } elseif ($value.Length -ge 2 -and $value[0] -eq [char]39 -and $value[-1] -eq [char]39) {
        $value = $value.Substring(1, $value.Length - 2).Replace("''", "'")
    }
    if ([string]::IsNullOrWhiteSpace($value) -or -not [IO.Path]::IsPathRooted($value) -or $value.IndexOfAny([char[]]@(0,10,13,34)) -ge 0) { throw '请输入或拖入一个完整文件夹路径。' }
    return [IO.Path]::GetFullPath($value)
}

function Assert-JobsMigrationDirectory {
    param([string]$Path)
    if (-not [IO.Path]::IsPathRooted($Path) -or -not [IO.Directory]::Exists($Path)) { throw ('目录不存在：' + $Path) }
    $item = New-Object IO.DirectoryInfo ([IO.Path]::GetFullPath($Path))
    while ($null -ne $item) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw ('不处理链接或目录联接：' + $item.FullName) }
        $item = $item.Parent
    }
}

function Get-JobsMigrationFiles {
    param([string]$Directory)
    Assert-JobsMigrationDirectory $Directory
    $root = [IO.Path]::GetFullPath($Directory).TrimEnd('\','/')
    $pending = New-Object 'Collections.Generic.Stack[string]'
    $pending.Push($root)
    while ($pending.Count -gt 0) {
        foreach ($entry in (New-Object IO.DirectoryInfo ($pending.Pop())).EnumerateFileSystemInfos()) {
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw ('产物含链接，停止打包/删除：' + $entry.FullName) }
            if ($entry.Attributes -band [IO.FileAttributes]::Directory) { $pending.Push($entry.FullName); continue }
            [pscustomobject]@{ Path=$entry.FullName; Relative=$entry.FullName.Substring($root.Length+1).Replace('\','/'); Length=$entry.Length }
        }
    }
}

function Get-JobsMigrationStreamHash {
    param([IO.Stream]$Stream)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Stream)).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Assert-JobsMigrationZip {
    param([string]$Bundle,[string]$Zip)
    Add-Type -AssemblyName System.IO.Compression
    $files = @(Get-JobsMigrationFiles $Bundle)
    $prefix = [IO.Path]::GetFileName($Bundle.TrimEnd('\','/')) + '/'
    $stream = [IO.File]::OpenRead($Zip)
    $archive = $null
    try {
        $archive = New-Object IO.Compression.ZipArchive ($stream, [IO.Compression.ZipArchiveMode]::Read)
        if ($archive.Entries.Count -ne $files.Count) { throw 'ZIP 文件清单不匹配。' }
        $seen = @{}
        foreach ($file in $files) {
            $name = $prefix + $file.Relative
            $entry = $archive.GetEntry($name)
            if ($null -eq $entry -or $entry.Length -ne $file.Length -or $seen.ContainsKey($name)) { throw ('ZIP 条目缺失或重复：' + $file.Relative) }
            $seen[$name] = $true
            $source = [IO.File]::OpenRead($file.Path)
            $compressed = $entry.Open()
            try {
                if ((Get-JobsMigrationStreamHash $source) -cne (Get-JobsMigrationStreamHash $compressed)) { throw ('ZIP 校验失败或原产物已改变：' + $file.Relative) }
            } finally { $source.Dispose(); $compressed.Dispose() }
        }
        foreach ($entry in $archive.Entries) { if (-not $seen.ContainsKey($entry.FullName)) { throw 'ZIP 包含多余或重复条目。' } }
    } finally { if ($archive) { $archive.Dispose() }; $stream.Dispose() }
}

function Compress-JobsMigrationBundle {
    param([string]$Bundle)
    Add-Type -AssemblyName System.IO.Compression
    $files = @(Get-JobsMigrationFiles $Bundle)
    $prefix = [IO.Path]::GetFileName($Bundle.TrimEnd('\','/')) + '/'
    $zip = $Bundle + '.zip'
    if ([IO.File]::Exists($zip) -or [IO.Directory]::Exists($zip)) { throw '同名 ZIP 已存在；保留原产物，不覆盖。' }
    $temporary = $zip + '.partial-' + [guid]::NewGuid().ToString('N')
    $stream = $null
    $archive = $null
    try {
        $stream = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $archive = New-Object IO.Compression.ZipArchive ($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
        foreach ($file in $files) {
            $entry = $archive.CreateEntry($prefix + $file.Relative, [IO.Compression.CompressionLevel]::Optimal)
            $source = [IO.File]::OpenRead($file.Path)
            $compressed = $entry.Open()
            try { $source.CopyTo($compressed) } finally { $source.Dispose(); $compressed.Dispose() }
        }
        $archive.Dispose(); $archive = $null
        $stream.Dispose(); $stream = $null
        Assert-JobsMigrationZip $Bundle $temporary
        [IO.File]::Move($temporary, $zip)
        return $zip
    } finally {
        if ($archive) { $archive.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function Get-JobsMigrationSystemDartCandidates {
    $seen = @{}
    foreach ($command in @(Get-Command -Name dart.exe,dart,dart.bat -CommandType Application -All -ErrorAction SilentlyContinue)) {
        $file = $command.Source
        if ([string]::IsNullOrWhiteSpace($file)) { continue }
        $candidate = $null
        if ([IO.Path]::GetExtension($file) -ieq '.exe') { $candidate = $file }
        elseif ([IO.Path]::GetExtension($file) -ieq '.bat') {
            # Flutter 启动 shim 会下载或改写 SDK；只探测其旁边已经存在的原生 Dart。
            $candidate = Join-Path ([IO.Path]::GetDirectoryName($file)) 'cache/dart-sdk/bin/dart.exe'
        }
        if ($candidate -and -not $seen.ContainsKey($candidate)) { $seen[$candidate]=$true; $candidate }
    }
}

function Get-JobsMigrationDart {
    param([string]$Project)
    $worker = Import-Module (Join-Path $script:MigrationScripts 'Actions/import-dependencies/Scripts/Action.psm1') -PassThru -DisableNameChecking
    & $worker { param($p) Assert-JobsFlutterProject $p } $Project
    $preferred = & $worker { param($p) try { Find-JobsImporterDart $p } catch { return $null } } $Project
    if ($preferred) { return $preferred }
    Write-Host '项目 FVM Dart 未就绪；迁移仅处理文件，尝试复用已有原生系统 Dart，不安装或切换工程 SDK。'
    foreach ($candidate in @(Get-JobsMigrationSystemDartCandidates)) {
        if (-not (& $worker {param($p)Test-JobsImporterNativeExecutable $p} $candidate)) { continue }
        try {
            $probe = Invoke-JobsProcess -FilePath $candidate -Arguments @('--version') -WorkingDirectory $Project -TimeoutSeconds 15
            if ($probe.ExitCode -eq 0 -and ($probe.StdOut+$probe.StdErr) -match 'Dart SDK version:') {
                Write-Host ('文件迁移运行时：'+$candidate)
                return $candidate
            }
        } catch { }
    }
    throw '缺少健康的原生 Dart。请先准备已有 Dart 或 Flutter/FVM SDK，再重新运行迁移；不会调用下载 shim 或自动安装 SDK。'
}

# 小时不按天折返，长时间扫描仍显示完整累计时长。
function Format-JobsMigrationElapsed {
    param([TimeSpan]$Elapsed)
    return ('{0:00}:{1:00}:{2:00}' -f [Math]::Floor($Elapsed.TotalHours), $Elapsed.Minutes, $Elapsed.Seconds)
}
# 只在可交互控制台原位刷新；重定向、无色及纯文本模式使用低频完整行。
function Test-JobsMigrationElapsedConsole {
    return (Test-JobsMigrationPromptColor) -and $env:PLAIN_OUTPUT -ne '1'
}
# 仅终止本轮启动的进程树，兼容 PowerShell 5.1 缺少 Kill(true) 的运行时。
function Stop-JobsMigrationProcess {
    param([Diagnostics.Process]$Process)
    if ($Process.HasExited) { return }
    $treeStopped = $false
    $cleanupClock = [Diagnostics.Stopwatch]::StartNew()
    try {
        $killTree = $Process.GetType().GetMethod('Kill', [type[]]@([bool]))
        if ($null -ne $killTree) {
            [void]$killTree.Invoke($Process, [object[]]@($true))
            $treeStopped = $true
        }
    } catch { }
    if (-not $treeStopped -and [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        $taskKiller = New-Object Diagnostics.Process
        try {
            $taskKiller.StartInfo.FileName = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'taskkill.exe'
            $taskKiller.StartInfo.Arguments = '/PID ' + $Process.Id.ToString([Globalization.CultureInfo]::InvariantCulture) + ' /T /F'
            $taskKiller.StartInfo.UseShellExecute = $false
            $taskKiller.StartInfo.CreateNoWindow = $true
            $taskKiller.StartInfo.RedirectStandardOutput = $true
            $taskKiller.StartInfo.RedirectStandardError = $true
            if (-not $Process.HasExited -and $taskKiller.Start()) {
                $killOutput = $taskKiller.StandardOutput.ReadToEndAsync()
                $killError = $taskKiller.StandardError.ReadToEndAsync()
                if (-not $taskKiller.WaitForExit([Math]::Max(0, 5000 - [int]$cleanupClock.ElapsedMilliseconds))) { $taskKiller.Kill() }
                else { $treeStopped = $taskKiller.ExitCode -eq 0 }
            }
        } catch { }
        finally { $taskKiller.Dispose() }
    }
    if (-not $treeStopped -and -not $Process.HasExited) { $Process.Kill() }
    [void]$Process.WaitForExit([Math]::Max(0, 5000 - [int]$cleanupClock.ElapsedMilliseconds))
    if (-not $Process.HasExited) { throw '本轮迁移进程未能停止，请检查进程状态。' }
}
# 短轮询承接真实引擎进程，静默时持续显示耗时，退出前停止刷新并清理本轮子进程。
function Invoke-JobsMigrationProcess {
    param([string]$FilePath,[string[]]$Arguments,[string]$WorkingDirectory,[string]$Stage,[int]$TimeoutSeconds = 21600)
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = (@($Arguments | ForEach-Object { Quote-JobsArgument -Value $_ }) -join ' ')
    $startInfo.WorkingDirectory = Get-JobsDirectory -Target $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $startInfo.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $console = Test-JobsMigrationElapsedConsole
    $started = $false
    $lastSecond = 0
    $nextHeartbeatSecond = 10
    $outcome = '已停止（失败或取消）'
    Write-JobsMigrationMessage ($Stage + '｜已耗时 00:00:00；请稍候，Ctrl+C 取消。')
    try {
        if (-not $process.Start()) { throw '无法启动迁移引擎。' }
        $started = $true
        # 两条流同时读取，避免大量计划或错误输出填满管道而阻塞引擎。
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        while (-not $process.WaitForExit(200)) {
            if ($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds) { throw (New-Object TimeoutException('迁移引擎执行超时，停止本轮进程。')) }
            $second = [long][Math]::Floor($clock.Elapsed.TotalSeconds)
            if ($second -eq $lastSecond) { continue }
            $lastSecond = $second
            $status = $Stage + '｜已耗时 ' + (Format-JobsMigrationElapsed $clock.Elapsed) + '；请稍候，Ctrl+C 取消。'
            if ($console) { Write-Host ("`r" + $status) -NoNewline }
            elseif ($second -ge $nextHeartbeatSecond) {
                Write-JobsMigrationMessage $status
                $nextHeartbeatSecond = $second + 10
            }
        }
        $readTasks = [Threading.Tasks.Task[]]@($outputTask, $errorTask)
        if (-not [Threading.Tasks.Task]::WaitAll($readTasks, 5000)) { throw '迁移引擎已退出，但输出管道未能按时关闭。' }
        $outcome = if ($process.ExitCode -eq 0) { '完成' } else { '失败（退出码 ' + $process.ExitCode + '）' }
        return [pscustomobject]@{ ExitCode=$process.ExitCode; StdOut=$outputTask.GetAwaiter().GetResult(); StdErr=$errorTask.GetAwaiter().GetResult() }
    } finally {
        try {
            if ($started -and -not $process.HasExited) { Stop-JobsMigrationProcess $process }
        } finally {
            $clock.Stop()
            $process.Dispose()
            if ($console -and $lastSecond -gt 0) { Write-Host }
            Write-JobsMigrationMessage ($Stage + '｜' + $outcome + '｜总用时 ' + (Format-JobsMigrationElapsed $clock.Elapsed))
        }
    }
}
# 引擎输出保持原样解析，计时提示只写宿主和日志，不混入计划指纹。
function Invoke-JobsMigrationEngine {
    param([string]$Dart,[string[]]$Arguments,[string]$Project)
    $engine = Join-Path $script:MigrationScripts 'FlutterDependencyMigration.dart'
    if (-not [IO.File]::Exists($engine)) { throw '缺少迁移引擎，请保留完整工具包。' }
    $stage = if ($Arguments[0] -ceq 'import') {
        if ($Arguments -contains '--apply') {
            if ($Arguments -contains '--backup-directory') { '校验、备份并导入依赖' } else { '校验并导入依赖' }
        } else { '扫描并校验导入计划' }
    } else { '扫描并提取依赖' }
    $result = Invoke-JobsMigrationProcess -FilePath $Dart -Arguments (@($engine)+$Arguments) -WorkingDirectory $Project -Stage $stage
    foreach ($output in @($result.StdOut,$result.StdErr)) { if ($output) { Write-JobsMigrationMessage $output.TrimEnd() } }
    if ($result.ExitCode -ne 0) { throw ('迁移引擎失败（退出码 ' + $result.ExitCode + '）；停止本轮导入，请检查上方计划与日志。') }
    return $result.StdOut
}

function Invoke-JobsFlutterMigration {
    param([string]$Project,[ValidateSet('export-all-dependencies','import-all-dependencies')][string]$Action,[switch]$PrivateOnly)
    $script:MigrationLog = $null
    $exporting = $Action -ceq 'export-all-dependencies'
    Write-Host 'Jobs · 一键提取 / 一键导入 Flutter 依赖' -ForegroundColor Red
    Write-Host '🔐 私库是迁移重点：默认只提取可识别的私库候选；未知来源会列为缺口，Git/path/非公共源不等同于已确认私有。' -ForegroundColor Yellow
    Write-Host '只读本机已有依赖，不下载、不运行依赖源码、排除已知缓存认证配置、不安装 SDK；项目及两份缓存不代表完整离线环境。'
    Write-Host '导入先只读预检；有冲突时选择使用导入源（推荐覆盖）或保留本机（跳过）。覆盖默认先备份，可输入任意字符跳过备份，最后精确 YES 才写入。ZIP 请先解压。'
    Write-Host '日志：系统临时目录中的 JobsFlutterMigration-*.log；按 Ctrl+C 或输入结束取消。'
    $answer = Read-JobsMigrationLine '已了解用途与影响，直接回车继续；任意非空输入取消'
    if ($null -eq $answer -or $answer.Length -ne 0) { return }
    Assert-JobsMigrationDirectory $Project
    $dart = Get-JobsMigrationDart $Project
    $script:MigrationLog = Join-Path ([IO.Path]::GetTempPath()) ('JobsFlutterMigration-'+[guid]::NewGuid().ToString('N')+'.log')
    Write-JobsMigrationMessage ('日志：'+$script:MigrationLog)
    Write-JobsMigrationMessage ('目标工程：'+$Project)
    try {
        if ($exporting) {
            $all = $false
            if (-not $PrivateOnly) {
                $scope = Read-JobsMigrationLine '直接回车 = 只提取私库；输入任意字符（含空格）再回车 = 全提取'
                if ($null -eq $scope) { return }
                $all = $scope.Length -ne 0
            }
            $desktop = Get-JobsMigrationDesktop
            $inputPath = Read-JobsMigrationLine ('输入或拖入输出父目录（直接回车：'+$desktop+'）')
            if ($null -eq $inputPath) { return }
            $destination = if ($inputPath.Length -eq 0) { $desktop } else { ConvertFrom-JobsMigrationPath $inputPath }
            Assert-JobsMigrationDirectory $destination
            $before = @((New-Object IO.DirectoryInfo $destination).EnumerateFileSystemInfos() | ForEach-Object { $_.FullName })
            Write-JobsMigrationMessage ('来源：项目已解析依赖与当前机器缓存；项目：'+$Project+'；输出父目录：'+$destination)
            Write-JobsMigrationMessage ('范围：'+$(if($all){'已确认全提取'}else{'只提取私库候选'}))
            $arguments = @('export','--project',$Project,'--destination',$destination)
            if ($all) { $arguments += '--all' }
            $output = Invoke-JobsMigrationEngine $dart $arguments $Project
            $markers = @([regex]::Matches($output,'(?m)^JOBS_MIGRATION_OUTPUT=(.+)\r?$'))
            if ($markers.Count -ne 1) { throw '引擎未返回唯一完整产物；不打包、不删除。' }
            $bundle = [IO.Path]::GetFullPath($markers[0].Groups[1].Value.TrimEnd("`r"))
            Assert-JobsMigrationDirectory $bundle
            $parent = [IO.Path]::GetDirectoryName($bundle.TrimEnd('\','/'))
            if (-not [string]::Equals($parent.TrimEnd('\','/'),[IO.Path]::GetFullPath($destination).TrimEnd('\','/'),[StringComparison]::OrdinalIgnoreCase) -or $bundle -in $before) { throw '产物不是本次新建的直属目录；不打包、不删除。' }
            $zipAnswer = Read-JobsMigrationLine '直接回车 = 打包成 ZIP；输入任意字符再回车 = 不打包'
            if ($null -eq $zipAnswer -or $zipAnswer.Length -ne 0) { Write-JobsMigrationMessage ('保留提取目录：'+$bundle); return }
            $zip = Compress-JobsMigrationBundle $bundle
            Write-JobsMigrationMessage ('ZIP 已逐文件 SHA-256 校验：'+$zip)
            $deleteAnswer = Read-JobsMigrationLine '直接回车 = 不删除原始提取产物；输入任意字符再回车 = 删除'
            if ($null -ne $deleteAnswer -and $deleteAnswer.Length -ne 0) {
                Assert-JobsMigrationZip $bundle $zip
                [IO.Directory]::Delete($bundle,$true)
                Write-JobsMigrationMessage ('已删除本次提取目录；ZIP 保留：'+$zip)
            } else { Write-JobsMigrationMessage ('保留提取目录：'+$bundle) }
        } else {
            while ($true) {
                $inputPath = Read-JobsMigrationLine '输入或拖入迁移产物、原始 Pub/Gradle 缓存目录或同时包含它们的父目录（名称可改，留空继续询问）'
                if ($null -eq $inputPath) { return }
                if (-not [string]::IsNullOrWhiteSpace($inputPath)) { break }
                Write-JobsMigrationMessage '尚未输入目录，请继续输入；Ctrl+C 或输入结束取消。'
            }
            $source = ConvertFrom-JobsMigrationPath $inputPath
            Assert-JobsMigrationDirectory $source
            Write-JobsMigrationMessage ('来源：'+$source+'；目标：当前项目/本机 PUB_CACHE、GRADLE_USER_HOME 或系统默认目录')
            $arguments = @('import','--project',$Project,'--source',$source)
            $preview = Invoke-JobsMigrationEngine $dart $arguments $Project
            $conflicts = Get-JobsMigrationConflictCount $preview
            if ($conflicts -gt 0) {
                Write-JobsMigrationMessage ('本次只读计划发现 ' + $conflicts + ' 项内容冲突；选择本轮处理策略后重新生成计划。')
                $policy = Select-JobsMigrationConflictPolicy
                if ($null -eq $policy) { Write-JobsMigrationMessage '已取消，未导入。'; return }
                $arguments += @('--conflict-policy', $policy)
                if ($policy -ceq 'source') {
                    $backup = Read-JobsMigrationBackupChoice
                    if ($null -eq $backup) { Write-JobsMigrationMessage '已取消，未导入。'; return }
                    if ($backup.Length -eq 0) {
                        $desktop = Get-JobsMigrationDesktop
                        $backupPath = Read-JobsMigrationLine ('输入或拖入备份父目录（直接回车：' + $desktop + '）')
                        if ($null -eq $backupPath) { Write-JobsMigrationMessage '已取消，未导入。'; return }
                        $backupDirectory = if ($backupPath.Length -eq 0) { $desktop } else { ConvertFrom-JobsMigrationPath $backupPath }
                        if ([string]::IsNullOrWhiteSpace($backupDirectory) -or -not [IO.Path]::IsPathRooted($backupDirectory)) { throw '备份父目录无效，请输入或拖入绝对目录。' }
                        $arguments += @('--backup-directory', $backupDirectory)
                        Write-JobsMigrationMessage ('将备份到「' + $backupDirectory + '」内的新文件夹，校验通过后再覆盖。')
                    } else {
                        $arguments += '--no-backup'
                        Write-JobsMigrationMessage '本轮已选择不备份；确认后冲突文件将被导入源覆盖。'
                    }
                } else { Write-JobsMigrationMessage '本轮保留本机现有内容；跳过冲突文件，只导入可安全新增或复用的内容。' }
                $preview = Invoke-JobsMigrationEngine $dart $arguments $Project
                [void](Get-JobsMigrationConflictCount $preview)
            }
            $plans = @([regex]::Matches($preview,'(?m)^JOBS_MIGRATION_PLAN=([0-9a-f]{64})\r?$'))
            if ($plans.Count -ne 1) { throw '预检未返回唯一完整计划指纹，停止导入。' }
            $plan = $plans[0].Groups[1].Value
            while ($true) {
                $confirm = Read-JobsMigrationLine '核对上方识别结果与写入计划，精确输入大写 YES 导入；直接回车继续询问，其它非空输入取消'
                if ($null -eq $confirm) { Write-JobsMigrationMessage '输入已结束，未导入。'; return }
                if ($confirm.Length -eq 0) { Write-JobsMigrationMessage '尚未确认；请输入大写 YES 导入，或输入其它非空内容取消。'; continue }
                if (-not [string]::Equals($confirm, 'YES', [StringComparison]::Ordinal)) { Write-JobsMigrationMessage '已取消，未导入。'; return }
                break
            }
            [void](Invoke-JobsMigrationEngine $dart ($arguments+@('--apply','--expected-plan',$plan)) $Project)
            Write-JobsMigrationMessage '导入完成；请核对缺口，再用项目原有工具准备 SDK 和解析依赖。'
        }
    } finally { $script:MigrationLog = $null }
}
Export-ModuleMember -Function Invoke-JobsFlutterMigration

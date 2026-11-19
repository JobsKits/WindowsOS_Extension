# Action.psm1 | JobsGitRollback
# Created by Jobs on 2026年10月26日，星期一.
# 仅回退所选目录的最近 Git 工作树；不递归重置子仓，不联网、不推送。

# Jobs enter-choice emphasis is display-only; input and business decisions stay with callers.
# JOBS_FZF_SELECTION_CORE_V1_BEGIN
# 将选择器诊断交给当前业务日志，先剥离控制码并脱敏展示地址。
function Write-JobsFzfStatus {
    [CmdletBinding()]
    param([string]$Text)
    $plain = $Text -replace '\x1b\][^\x07]*(?:\x07|\x1b\\)', '' -replace '\x1b\[[0-?]*[ -/]*[@-~]', ''
    $plain = $plain -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@' -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]'
    foreach ($name in @('Write-JobsHarmonyMessage', 'Write-JobsPackagerMessage', 'Write-JobsFvmMessage', 'Write-JobsSetupMessage', 'Write-JobsMigrationMessage', 'Write-JobsRollbackMessage', 'Write-JobsLog', 'Write-JobsEnterChoiceText')) {
        $writer = Get-Command $name -CommandType Function -ErrorAction SilentlyContinue
        if ($writer) { & $writer $plain; return }
    }
    Write-Host $plain
}
# 复用现有 Windows argv 引号规则，不通过命令字符串求值。
function ConvertTo-JobsFzfArgument {
    param([AllowNull()][AllowEmptyString()][string]$Value)
    if ($null -eq $Value) { $Value = '' }
    if ($Value.IndexOf([char]0) -ge 0) { throw '参数不能包含空字符。' }
    $quoted = New-Object Text.StringBuilder
    [void]$quoted.Append('"')
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq [char]92) { $slashes++; continue }
        if ($character -eq [char]34) {
            [void]$quoted.Append([char]92, (2 * $slashes + 1))
            [void]$quoted.Append([char]34)
        } else {
            if ($slashes -gt 0) { [void]$quoted.Append([char]92, $slashes) }
            [void]$quoted.Append($character)
        }
        $slashes = 0
    }
    if ($slashes -gt 0) { [void]$quoted.Append([char]92, (2 * $slashes)) }
    [void]$quoted.Append('"')
    return $quoted.ToString()
}
# 仅清理本次启动的 fzf；探针有单次上限，交互沿原终端运行，不改父进程环境。
function Invoke-JobsFzfProcess {
    param([string]$Executable, [string[]]$NativeArguments, [string[]]$InputLines = @(), [switch]$Probe)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Executable
    $start.Arguments = (@($NativeArguments | ForEach-Object { ConvertTo-JobsFzfArgument $_ }) -join ' ')
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = [bool]$Probe
    $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    if ($Probe) { $start.StandardErrorEncoding = New-Object Text.UTF8Encoding($false) }
    foreach ($key in @('FZF_DEFAULT_OPTS', 'FZF_DEFAULT_OPTS_FILE', 'FZF_DEFAULT_COMMAND')) { [void]$start.EnvironmentVariables.Remove($key) }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = if ($Probe) { $process.StandardError.ReadToEndAsync() } else { $null }
        $inputWriter = New-Object IO.StreamWriter($process.StandardInput.BaseStream, (New-Object Text.UTF8Encoding($false)))
        $inputWriter.NewLine = "`n"
        try { foreach ($line in $InputLines) { $inputWriter.WriteLine($line) } } finally { $inputWriter.Dispose() }
        if ($Probe) {
            if (-not $process.WaitForExit(10000)) {
                $process.Kill(); $process.WaitForExit()
                return [pscustomobject]@{ Code = 124; Lines = @(); Error = 'fzf 健康探针超时（10 秒）。' }
            }
        } else { $process.WaitForExit() }
        $output = $outputTask.GetAwaiter().GetResult()
        $errorText = if ($errorTask) { $errorTask.GetAwaiter().GetResult() } else { '' }
        $lines = @()
        if ($output.Length -gt 0) { $lines = @($output.Replace("`r`n", "`n").TrimEnd([char]10) -split "`n") }
        return [pscustomobject]@{ Code = $process.ExitCode; Lines = $lines; Error = $errorText }
    } finally {
        try { if ($process.Id -gt 0 -and -not $process.HasExited) { $process.Kill(); $process.WaitForExit() } } catch { }
        $process.Dispose()
    }
}
# 检验真实路径、版本及实际单选/复选面板选项；不打开界面或获取依赖。
function Test-JobsFzfPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not [IO.File]::Exists($Path)) { return $false }
    try {
        $version = Invoke-JobsFzfProcess $Path @('--version') -Probe
        if ($version.Code -ne 0) { return $false }
        $marker = '__JOBS_FZF_HEALTH__'
        $probe = Invoke-JobsFzfProcess $Path @('--filter', $marker, '--no-multi', '--sync', '--layout=reverse', '--height=60%', '--border', '--delimiter', "`t", '--with-nth=2..', '--print-query', '--expect=left,space,enter', '--bind=up:up,down:down,tab:down,shift-tab:up,start:pos(1)') @("P`t$marker") -Probe
        return ($probe.Code -eq 0 -and $probe.Lines.Count -gt 0 -and $probe.Lines[-1] -ceq "P`t$marker")
    } catch [Management.Automation.PipelineStoppedException] { throw } catch { return $false }
}
# 发现当前和常见用户级安装位置，不因别名或损坏路径误判已经就绪。
function Find-JobsFzf {
    $candidates = New-Object 'Collections.Generic.List[string]'
    foreach ($name in @('fzf.exe', 'fzf')) {
        $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { $candidates.Add($command.Source) }
    }
    if ($env:LOCALAPPDATA) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA 'Microsoft/WinGet/Links/fzf.exe'))
        $packages = Join-Path $env:LOCALAPPDATA 'Microsoft/WinGet/Packages'
        if ([IO.Directory]::Exists($packages)) {
            foreach ($directory in @(Get-ChildItem -LiteralPath $packages -Directory -Filter 'junegunn.fzf*' -ErrorAction SilentlyContinue)) {
                foreach ($file in @(Get-ChildItem -LiteralPath $directory.FullName -File -Recurse -Filter 'fzf.exe' -ErrorAction SilentlyContinue)) { $candidates.Add($file.FullName) }
            }
        }
    }
    if ($env:USERPROFILE) { $candidates.Add((Join-Path $env:USERPROFILE 'scoop/shims/fzf.exe')) }
    if ($env:ChocolateyInstall) { $candidates.Add((Join-Path $env:ChocolateyInstall 'bin/fzf.exe')) }
    foreach ($candidate in @($candidates | Select-Object -Unique)) { if (Test-JobsFzfPath $candidate) { return $candidate } }
    return $null
}
# 只刷新本次进程的工具搜索路径，不改写用户或系统 PATH。
function Update-JobsProcessPath {
    param([string]$ExecutableDirectory)
    $parts = New-Object 'Collections.Generic.List[string]'
    $separator = [IO.Path]::PathSeparator
    foreach ($value in @($ExecutableDirectory, [Environment]::GetEnvironmentVariable('Path', 'User'), [Environment]::GetEnvironmentVariable('Path', 'Machine'), $env:Path)) {
        foreach ($part in @(([string]$value) -split [regex]::Escape([string]$separator))) {
            if (-not [string]::IsNullOrWhiteSpace($part) -and -not $parts.Contains($part)) { $parts.Add($part) }
        }
    }
    $env:Path = $parts -join [string]$separator
}
# 查找当前用户已就绪的原生包管理器；只读调用不注册或安装组件。
function Find-JobsWinget {
    $command = Get-Command 'winget.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $candidates = @()
    if ($command) { $candidates += $command.Source }
    if ($env:LOCALAPPDATA) { $candidates += Join-Path $env:LOCALAPPDATA 'Microsoft/WindowsApps/winget.exe' }
    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if (-not [IO.File]::Exists($candidate)) { continue }
        try { $probe = Invoke-JobsFzfProcess $candidate @('--version') -Probe; if ($probe.Code -eq 0) { return $candidate } } catch [Management.Automation.PipelineStoppedException] { throw } catch { }
    }
    return $null
}
# 必需依赖才恢复当前用户 App Installer 注册或打开一次官方安装界面，并在原流程等待就绪。
function Get-JobsRequiredWinget {
    $winget = Find-JobsWinget
    if ($winget) { return $winget }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw '当前不是 Windows，未调用 App Installer 或安装 Windows 依赖。' }
    Write-JobsFzfStatus '本次需要 Windows 原生 App Installer/winget；仅注册当前用户已有组件，不接受许可或修改系统策略。'
    $registration = Get-Command Add-AppxPackage -ErrorAction SilentlyContinue
    if ($registration -and $registration.Parameters.ContainsKey('RegisterByFamilyName')) {
        try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop } catch { Write-JobsFzfStatus ('App Installer 注册未就绪：' + $_.Exception.Message) }
        $winget = Find-JobsWinget
        if ($winget) { Update-JobsProcessPath ([IO.Path]::GetDirectoryName($winget)); return $winget }
    }
    Write-JobsFzfStatus '官方 App Installer：https://apps.microsoft.com/detail/9NBLGGH4NNS1；将打开一次官方页面。请按系统要求完成安装/许可，本入口持续复检并续行，Ctrl+C 停止等待。'
    Start-Process -FilePath 'ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1' -ErrorAction Stop | Out-Null
    while ($true) {
        Update-JobsProcessPath
        $winget = Find-JobsWinget
        if ($winget) { return $winget }
        Write-JobsFzfStatus '等待官方 App Installer 安装和当前用户注册；不会重复打开窗口，Ctrl+C 取消。'
        Start-Sleep -Seconds 3
    }
}
# 调用原生包管理器处理精确包，保留许可交互；原输出仅经脱敏展示，不用作选择结果。
function Invoke-JobsWingetPackage {
    param([string]$Winget, [string]$Package, [ValidateSet('install','upgrade','repair')][string]$Mode = 'install')
    $arguments = @($Mode, '--id', $Package, '--exact', '--source', 'winget', '--interactive')
    if ($Package -ceq 'junegunn.fzf') { $arguments += @('--scope', 'user') }
    $text = New-Object 'Collections.Generic.List[string]'
    $previous = $ErrorActionPreference
    $logFailure = $null
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        $ErrorActionPreference = 'Continue'
        $global:LASTEXITCODE = -1
        & $Winget @arguments 2>&1 | ForEach-Object { $line = [string]$_; $text.Add($line); try { Write-JobsFzfStatus $line -ErrorAction Stop } catch { $logFailure = $_.Exception; throw } }
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous }
    if ($logFailure) { throw $logFailure }
    return [pscustomobject]@{ Code = $code; Text = $text -join "`n" }
}
# 选择流程才获取必需 fzf；健康环境直接复用，只读与取消不启动安装。
function Ensure-JobsFzf {
    param([switch]$CheckOnly)
    $fzf = Find-JobsFzf
    if ($fzf) { if (-not $CheckOnly) { Update-JobsProcessPath ([IO.Path]::GetDirectoryName($fzf)) }; return $fzf }
    if ($CheckOnly) { throw 'fzf 路径、版本或所需选项尚未就绪；只读检查未安装或修复。' }
    if ([Console]::IsInputRedirected -or [Console]::IsErrorRedirected) { throw '键盘选择需要真实交互终端；未获取依赖或执行业务。' }
    Write-JobsFzfStatus '本次键盘选择需要健康 fzf；来源 https://github.com/microsoft/winget-pkgs（junegunn.fzf）。仅在缺失或损坏时获取，许可证仍由本人确认，Ctrl+C 可结束。'
    $winget = Get-JobsRequiredWinget
    $mode = 'install'
    $existing = Get-Command 'fzf.exe', 'fzf' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($existing) { $mode = 'repair' }
    $attempt = 0; $delay = 1
    while ($true) {
        $attempt++
        Write-JobsFzfStatus ("必需 fzf：$mode，第 $attempt 次；网络失败持续重试，不设总次数，Ctrl+C 结束。")
        $result = Invoke-JobsWingetPackage $winget 'junegunn.fzf' $mode
        if ($result.Code -in @(130, 1223, 1602, -1073741510, -2147023673)) { throw (New-Object OperationCanceledException('已取消 fzf 获取。')) }
        if ($result.Code -eq 0) {
            Update-JobsProcessPath
            $fzf = Find-JobsFzf
            if ($fzf) { Update-JobsProcessPath ([IO.Path]::GetDirectoryName($fzf)); Write-JobsFzfStatus ('fzf 已通过当前进程复检：' + $fzf); return $fzf }
            if ($mode -eq 'install') { $mode = 'repair'; Write-JobsFzfStatus '安装返回成功但选项复检失败，在同一流程尝试官方精确修复。'; continue }
            throw 'fzf 安装及官方修复后仍未通过实际选项复检；保留原错误，未进入业务。'
        }
        if ($result.Text -match '(?i)permission|access.denied|no.space|disk.full|hash|checksum|certificate|unauthor|license|agreement|unsupported|not.supported|unknown.command|unrecognized|no.applicable|not.found|权限|拒绝|空间不足|许可|协议|不支持|未知命令|无法找到|无适用') {
            $safeFailure = $result.Text -replace '\x1b\][^\x07]*(?:\x07|\x1b\\)', '' -replace '\x1b\[[0-?]*[ -/]*[@-~]', ''
            $safeFailure = $safeFailure -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@' -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]'
            throw ('必需 fzf 遇到确定的权限、许可、包或版本阻塞，退出码 ' + $result.Code + '；未继续业务。' + [Environment]::NewLine + $safeFailure)
        }
        Write-JobsFzfStatus ("fzf 获取失败，退出码 $($result.Code)；$delay 秒后继续本次流程。")
        Start-Sleep -Seconds $delay
        $delay = [Math]::Min(30, $delay * 2)
    }
}
# 单选与复选使用同一键盘表面；操作行独立解析，空选不回退为高亮对象。
function Select-JobsFzfItems {
    param([string]$Title, [object[]]$Items, [switch]$Multiple, [switch]$Child, [switch]$RequireConfirmation, [hashtable]$State = $null)
    if ($Items.Count -eq 0) { return [pscustomobject]@{ Action = 'empty'; Items = @() } }
    if ($Items.Count -eq 1 -and -not $Multiple -and -not $RequireConfirmation) { return [pscustomobject]@{ Action = 'selected'; Items = @($Items[0]) } }
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected -or [Console]::IsErrorRedirected) { throw '键盘菜单需要完整交互终端；未安装依赖或继续业务。' }
    $environment = [Environment]::GetEnvironmentVariables('Process')
    foreach ($key in $environment.Keys) { if ([string]$key -match '^(?i:SOURCE_?TREE)') { throw 'Sourcetree 动作进程不能等待菜单；请按已声明的终端入口或明确参数执行。' } }
    $fzf = Ensure-JobsFzf
    $selected = New-Object 'Collections.Generic.HashSet[int]'
    $query = ''; $position = 1
    if ($null -ne $State) {
        if ($State.ContainsKey('Query')) { $query = [string]$State.Query }
        if ($State.ContainsKey('Position')) { $position = [Math]::Max(1, [int]$State.Position) }
        if ($State.ContainsKey('Checked')) {
            foreach ($savedIndex in @($State.Checked)) {
                if ([int]$savedIndex -ge 0 -and [int]$savedIndex -lt $Items.Count) { [void]$selected.Add([int]$savedIndex) }
            }
        }
    }
    while ($true) {
        $rows = New-Object 'Collections.Generic.List[string]'
        $rows.Add("C`t× 取消本轮")
        if ($Child) { $rows.Add("B`t← 返回上一层") }
        if ($Multiple) {
            $rows.Add("K`t确认已勾选（$($selected.Count) 项）")
            $rows.Add("A`t全选本轮全部项目")
            $rows.Add("Z`t清空已勾选")
        }
        for ($index = 0; $index -lt $Items.Count; $index++) {
            $display = ([string]$Items[$index]) -replace '[\r\n\t]', ' '
            if ($Multiple) { $display = $(if ($selected.Contains($index)) { '[✓] ' } else { '[ ] ' }) + $display }
            $rows.Add("D$index`t$display")
        }
        $navigation = if ($Child) { '← 返回上一层' } else { '← 取消' }
        $header = if ($Multiple) { "↑/↓ 或 Tab 导航；回车勾选/取消，空格确认；$navigation；操作行回车执行；Esc / Ctrl+C 取消" } else { "↑/↓ 或 Tab 导航；回车确认；$navigation；Esc / Ctrl+C 取消" }
        $position = [Math]::Min($position, $rows.Count)
        $arguments = @('--no-multi', '--sync', '--layout=reverse', '--height=60%', '--border', '--delimiter', "`t", '--with-nth=2..', '--print-query', '--expect=left,space,enter', ('--bind=up:up,down:down,tab:down,shift-tab:up,start:pos(' + $position + ')'), ('--prompt=' + $Title + ' > '), ('--header=' + $header), ('--query=' + $query))
        if ($environment.Contains('NO_COLOR') -or $env:PLAIN_OUTPUT -eq '1' -or $env:TERM -ieq 'dumb') { $arguments += @('--color=bw', '--no-bold') }
        $result = Invoke-JobsFzfProcess $fzf $arguments @($rows)
        $lines = @($result.Lines)
        $query = if ($lines.Count -gt 0) { [string]$lines[0] } else { '' }
        $key = if ($lines.Count -gt 1) { [string]$lines[1] } else { '' }
        if ($null -ne $State) { $State.Query = $query; $State.Checked = @($selected) }
        if ($key -ceq 'left') { return [pscustomobject]@{ Action = $(if ($Child) { 'back' } else { 'cancel' }); Items = @() } }
        if ($result.Code -in @(1, 130)) { return [pscustomobject]@{ Action = 'cancel'; Items = @() } }
        if ($result.Code -ne 0) { throw ('fzf 选择失败，退出码：' + $result.Code) }
        $record = if ($lines.Count -eq 3) { [string]$lines[2] } else { '' }
        if (-not $rows.Contains($record)) { throw '选择结果不属于本轮显示清单，未执行业务。' }
        $position = $rows.IndexOf($record) + 1
        if ($null -ne $State) { $State.Position = $position }
        $tag = ($record -split "`t", 2)[0]
        if ($tag -ceq 'C') { return [pscustomobject]@{ Action = 'cancel'; Items = @() } }
        if ($tag -ceq 'B') { return [pscustomobject]@{ Action = 'back'; Items = @() } }
        if ($Multiple) {
            if ($tag -ceq 'K' -or $key -ceq 'space') {
                $chosen = @()
                for ($index = 0; $index -lt $Items.Count; $index++) { if ($selected.Contains($index)) { $chosen += $Items[$index] } }
                return [pscustomobject]@{ Action = $(if ($chosen.Count) { 'selected' } else { 'empty' }); Items = $chosen }
            }
            if ($tag -ceq 'A') { for ($index = 0; $index -lt $Items.Count; $index++) { [void]$selected.Add($index) }; if ($null -ne $State) { $State.Checked = @($selected) }; continue }
            if ($tag -ceq 'Z') { $selected.Clear(); if ($null -ne $State) { $State.Checked = @() }; continue }
        }
        if ($tag -notmatch '^D([0-9]+)$') { throw '选择器返回无效操作行。' }
        $index = [int]$Matches[1]
        if (-not $Multiple) { return [pscustomobject]@{ Action = 'selected'; Items = @($Items[$index]) } }
        if ($selected.Contains($index)) { [void]$selected.Remove($index) } else { [void]$selected.Add($index) }
        if ($null -ne $State) { $State.Checked = @($selected) }
    }
}
# JOBS_FZF_SELECTION_CORE_V1_END

# 核验真实控制台和颜色约束，重定向或SourceTree统一使用纯文本。
function Test-JobsEnterChoiceColor {
    param([Collections.IDictionary]$Capabilities = $null)
    if ($null -eq $Capabilities) {
        try {
            $environment = [Environment]::GetEnvironmentVariables('Process')
            $Capabilities = @{ HostName = $Host.Name; InputRedirected = [Console]::IsInputRedirected; OutputRedirected = [Console]::IsOutputRedirected;
                               ErrorRedirected = [Console]::IsErrorRedirected; NoColorPresent = $environment.Contains('NO_COLOR');
                               PlainOutput = $env:PLAIN_OUTPUT; Term = $env:TERM; Windows = ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT); VirtualTerminal = $false; SourceTree = ($env:IS_SOURCETREE_RUNTIME -eq '1') }
            if ($null -ne $Host.UI.PSObject.Properties['SupportsVirtualTerminal']) { $Capabilities.VirtualTerminal = $Host.UI.SupportsVirtualTerminal }
            foreach ($key in $environment.Keys) { if ([string]$key -match '^(?i:SOURCE_?TREE)') { $Capabilities.SourceTree = $true; break } }
        } catch { return $false }
    }
    return ($Capabilities.HostName -eq 'ConsoleHost' -and -not $Capabilities.InputRedirected -and -not $Capabilities.OutputRedirected -and
            -not $Capabilities.ErrorRedirected -and -not $Capabilities.NoColorPresent -and $Capabilities.PlainOutput -ne '1' -and
            $Capabilities.Term -ine 'dumb' -and (-not [string]::IsNullOrEmpty($Capabilities.Term) -or ($Capabilities.Contains('Windows') -and $Capabilities.Windows)) -and -not $Capabilities.SourceTree -and $Capabilities.VirtualTerminal)
}
# Older hosts keep native colors without sending unsupported bold escape sequences.
function Test-JobsEnterChoiceBold {
    $property = $Host.UI.PSObject.Properties['SupportsVirtualTerminal']
    return ($null -ne $property -and [bool]$property.Value)
}
# Separate ordinary question text from Enter and arbitrary-input options without changing words.
function Get-JobsEnterChoiceParts {
    param([string]$Text)
    $red = '(?:(?:\u8f93\u5165)?(?:\u4efb\u610f(?:\u975e\u7a7a)?(?:\u5b57\u7b26|\u5185\u5bb9|\u6587\u5b57|\u8f93\u5165)?|\u975e\u7a7a(?:\u8f93\u5165|\u5b57\u7b26|\u5185\u5bb9)?|(?:\u5176\u5b83|\u5176\u4ed6)(?:\u975e\u7a7a)?(?:\u8f93\u5165|\u5185\u5bb9|\u5b57\u7b26)?))|(?:any\s+(?:(?:other|non[- ]empty)\s+)?(?:input|text|characters?)|non[- ]empty\s+input)|(?:type\s+(?:anything|any\s+(?:characters?|text|input)))'
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
# 仅在真实询问中突出主体和各类操作选项。
function Get-JobsQuestionChoiceParts {
    param([string]$Text)
    $plain = [regex]::Replace($Text, '\x1b\[[0-9;]*m', '')
    $questionBody = $true
    foreach ($part in @(Get-JobsEnterChoiceParts $plain)) {
        $isOption = $part.Color -eq 'Red' -or $part.Color -eq 'Green'
        foreach ($token in [regex]::Matches($part.Text, '[^；;/|，,、？?：:=＝（）()\[\]【】\r\n]+|[；;/|，,、？?：:=＝（）()\[\]【】\r\n]')) {
            $value = $token.Value
            $separator = $value -match '^[；;/|，,、？?：:=＝（）()\[\]【】\r\n]$'
            $color = ''
            if (-not $separator -and -not [string]::IsNullOrWhiteSpace($value)) {
                if ($isOption) { $color = $part.Color }
                elseif ($questionBody) { $color = 'Cyan' }
            }
            [pscustomobject]@{ Text = $value; Color = $color }
        }
        if ($isOption) { $questionBody = $false }
    }
}
# 识别展示地址边界，保留查询、编码与配对括号。
function Get-JobsUrlRanges {
    param([string]$Text)
    $pattern = '[A-Za-z][A-Za-z0-9+.-]*://[^\s<>"''\x1b]+'
    $punctuation = '，。；：！？、（）【】《》「」『』“”‘’'
    $offset = 0
    while ($offset -lt $Text.Length) {
        $match = [regex]::Match($Text.Substring($offset), $pattern)
        if (-not $match.Success) { break }
        $start = $offset + $match.Index
        $url = $match.Value
        foreach ($mark in $punctuation.ToCharArray()) {
            $at = $url.IndexOf($mark)
            if ($at -ge 0) { $url = $url.Substring(0, $at) }
        }
        while ($url.Length) {
            $last = $url.Substring($url.Length - 1, 1)
            $unmatched = $false
            foreach ($pair in @(@('(', ')'), @('[', ']'), @('{', '}'))) {
                if ($last -eq $pair[1] -and ([regex]::Matches($url, [regex]::Escape($pair[1]))).Count -gt ([regex]::Matches($url, [regex]::Escape($pair[0]))).Count) { $unmatched = $true }
            }
            if ('. , ; : ! ?'.Split(' ') -contains $last -or $unmatched) { $url = $url.Substring(0, $url.Length - 1) }
            else { break }
        }
        [pscustomobject]@{ Start = $start; End = $start + $url.Length }
        $offset = $start + $url.Length
    }
}
# 暂时遮蔽URL，避免询问分段误识别地址内的Enter。
function Protect-JobsDisplayUrls {
    param([string]$Text)
    $builder = New-Object Text.StringBuilder
    $tokens = New-Object 'Collections.Generic.List[object]'
    $offset = 0; $number = 0
    foreach ($range in @(Get-JobsUrlRanges $Text)) {
        do { $number++; $token = [string][char]2 + 'U' + $number + [char]3 } while ($Text.Contains($token))
        [void]$builder.Append($Text.Substring($offset, $range.Start - $offset)).Append($token)
        $tokens.Add([pscustomobject]@{ Token = $token; Text = $Text.Substring($range.Start, $range.End - $range.Start) })
        $offset = $range.End
    }
    [void]$builder.Append($Text.Substring($offset))
    [pscustomobject]@{ Text = $builder.ToString(); Tokens = $tokens.ToArray() }
}
# 给可见地址标绿下划线，并恢复原SGR上下文。
function Format-JobsUrlText {
    param([AllowEmptyString()][string]$Text, [switch]$Color)
    $control = '\x1b\][^\x1b\x07]*(?:\x07|\x1b\\)|\x1b\[[0-?]*[ -/]*[@-~]'
    $sgr = '\x1b\[[0-9;:]*m'
    $value = [regex]::Replace($Text, $control, {
        param($match)
        if ($Color -and $match.Value -match ('^' + $sgr + '$')) { return $match.Value }
        return ''
    })
    if (-not $Color) { return $value }
    $styles = @{}; $visible = New-Object Text.StringBuilder; $offset = 0
    foreach ($match in [regex]::Matches($value, $sgr)) {
        [void]$visible.Append($value.Substring($offset, $match.Index - $offset))
        $index = $visible.Length
        if (-not $styles.ContainsKey($index)) { $styles[$index] = '' }
        $styles[$index] += $match.Value
        $offset = $match.Index + $match.Length
    }
    [void]$visible.Append($value.Substring($offset))
    $plain = $visible.ToString(); $starts = @{}; $ends = @{}
    foreach ($range in @(Get-JobsUrlRanges $plain)) { $starts[$range.Start] = $true; $ends[$range.End - 1] = $true }
    $escape = [string][char]27; $active = ''; $inUrl = $false; $output = New-Object Text.StringBuilder
    for ($index = 0; $index -le $plain.Length; $index++) {
        if ($styles.ContainsKey($index)) {
            $tokens = $styles[$index]; [void]$output.Append($tokens)
            foreach ($match in [regex]::Matches($tokens, $sgr)) {
                $token = $match.Value; $code = $token.Substring(2, $token.Length - 3)
                $fields = $code.Split(';'); $reset = $code -eq ''
                for ($item = 0; $item -lt $fields.Count; $item++) {
                    if ($fields[$item] -eq '0') { $reset = $true }
                    if (@('38', '48', '58') -contains $fields[$item] -and $item + 1 -lt $fields.Count) {
                        if ($fields[$item + 1] -eq '2') { $item += 4 }
                        elseif ($fields[$item + 1] -eq '5') { $item += 2 }
                    }
                }
                if ($reset) { $active = '' }
                $active += $token
            }
            if ($inUrl) { [void]$output.Append($escape + '[32;4m') }
        }
        if ($index -eq $plain.Length) { break }
        if ($starts.ContainsKey($index)) { [void]$output.Append($escape + '[32;4m'); $inUrl = $true }
        [void]$output.Append($plain[$index])
        if ($ends.ContainsKey($index)) { [void]$output.Append($escape + '[0m' + $active); $inUrl = $false }
    }
    return $output.ToString()
}
# 按现行询问规则合成展示字符串，保持输入原文。
function Format-JobsDisplayText {
    param([AllowEmptyString()][string]$Text, [switch]$Question, [switch]$Color, [string]$BaseStyle = '')
    if (-not $Color) { return (Format-JobsUrlText $Text) }
    $plain = Format-JobsUrlText $Text
    $protected = Protect-JobsDisplayUrls $plain
    $parts = if ($Question) { @(Get-JobsQuestionChoiceParts $protected.Text) } else { @(Get-JobsEnterChoiceParts $protected.Text) }
    $escape = [string][char]27
    if (-not $Question -and @($parts | Where-Object { $_.Color }).Count -eq 0) {
        $result = Format-JobsUrlText ($BaseStyle + $Text) -Color
    } else {
        $output = New-Object Text.StringBuilder
        foreach ($part in $parts) {
            $code = switch ($part.Color) { 'Red' { 31 } 'Green' { 32 } 'Cyan' { 36 } default { 0 } }
            if ($code) { [void]$output.Append($escape + '[1;' + $code + 'm' + $part.Text + $escape + '[0m' + $BaseStyle) }
            else { [void]$output.Append($BaseStyle + $part.Text) }
        }
        $formatted = $output.ToString()
        foreach ($item in $protected.Tokens) { $formatted = $formatted.Replace($item.Token, $item.Text) }
        $result = Format-JobsUrlText $formatted -Color
    }
    if ($BaseStyle) { $result += $escape + '[0m' }
    return $result
}
# 按调用者明确指定的ConsoleColor计算临时展示色。
function Get-JobsDisplayBaseStyle {
    param([Collections.IDictionary]$Parameters)
    $codes = @{ Black=30; DarkBlue=34; DarkGreen=32; DarkCyan=36; DarkRed=31; DarkMagenta=35; DarkYellow=33; Gray=37; DarkGray=90; Blue=94; Green=92; Cyan=96; Red=91; Magenta=95; Yellow=93; White=97 }
    $style = ''; $escape = [string][char]27
    if ($Parameters.ContainsKey('ForegroundColor')) { $style += $escape + '[' + $codes[[string]$Parameters.ForegroundColor] + 'm' }
    if ($Parameters.ContainsKey('BackgroundColor')) { $style += $escape + '[' + ($codes[[string]$Parameters.BackgroundColor] + 10) + 'm' }
    return $style
}
# 只在人类控制台渲染问句与URL，信息流和日志保持纯文本。
function Write-JobsEnterChoiceText {
    [CmdletBinding()]
    param([Parameter(Position=0)][AllowNull()][object]$Object, [switch]$NoNewline, [ConsoleColor]$ForegroundColor, [ConsoleColor]$BackgroundColor, [object]$Separator = ' ', [switch]$Question)
    $text = if ($Object -is [array]) { $Object -join [string]$Separator } else { [string]$Object }
    $plain = Format-JobsUrlText $text
    if (-not (Test-JobsEnterChoiceColor)) { Write-Host $plain -NoNewline:$NoNewline; return }
    $baseStyle = Get-JobsDisplayBaseStyle $PSBoundParameters
    $rendered = Format-JobsDisplayText $text -Question:$Question -Color -BaseStyle $baseStyle
    $message = New-Object Management.Automation.HostInformationMessage
    $message.Message = $plain
    $message.NoNewLine = [bool]$NoNewline
    if ($PSBoundParameters.ContainsKey('ForegroundColor')) { $message.ForegroundColor = $ForegroundColor }
    if ($PSBoundParameters.ContainsKey('BackgroundColor')) { $message.BackgroundColor = $BackgroundColor }
    Write-Information -MessageData $message -Tags 'JobsDisplay' -InformationAction SilentlyContinue
    [Console]::Write($rendered)
    if (-not $NoNewline) { [Console]::WriteLine() }
}
# Delegate the original reader, including secure input and EOF behavior, after prompt display.
function Read-JobsEnterChoiceHost {
    [CmdletBinding()]
    param([Parameter(Position=0)][string]$Prompt, [switch]$AsSecureString, [switch]$MaskInput)
    if (-not (Test-JobsEnterChoiceColor)) {
        $plainArguments = @{}
        foreach ($key in $PSBoundParameters.Keys) { $plainArguments[$key] = $PSBoundParameters[$key] }
        if ($plainArguments.ContainsKey('Prompt')) { $plainArguments.Prompt = Format-JobsUrlText $Prompt }
        return (Read-Host @plainArguments)
    }
    Write-JobsEnterChoiceText ($Prompt + ': ') -NoNewline -Question
    $readerArguments = @{}
    foreach ($key in $PSBoundParameters.Keys) {
        if ($key -ne 'Prompt') { $readerArguments[$key] = $PSBoundParameters[$key] }
    }
    return (Read-Host @readerArguments)
}

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking

# 展示与日志使用脱敏副本，不改写业务参数。
function Write-JobsRollbackMessage {
    param([string]$Message)
    $Message = $Message -replace '\x1b\][^\x07]*(?:\x07|\x1b\\)', '' -replace '\x1b\[[0-?]*[ -/]*[@-~]', ''
    $Message = $Message -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@' -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]' -replace '(?im)((?:token|password|secret|authorization)\s*[:=]\s*)\S+', '$1[已省略]'
    $safe = $Message -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@' -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]'
    Write-JobsEnterChoiceText $safe
    Write-JobsLog $safe
}
# 元数据与工作树都拒绝链接，避免回退越过用户所选边界。
function Assert-JobsRollbackPlainPath {
    param([string]$Path, [bool]$Directory)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ([bool]$item.PSIsContainer -ne $Directory) { throw '路径类型不符。' }
    $current = $item
    while ($null -ne $current) {
        if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw '不处理链接、目录联接或重解析路径。' }
        if ($current -is [IO.DirectoryInfo]) { $current = $current.Parent } else { $current = $current.Directory }
    }
    return $item.FullName
}
# 限量读取单行 UTF8 元数据，不把任意目录当成 Git。
function Read-JobsRollbackMetadata {
    param([string]$Path)
    [void](Assert-JobsRollbackPlainPath $Path $false)
    if ((Get-Item -LiteralPath $Path -Force).Length -gt 8192) { throw 'Git 元数据超过支持大小。' }
    $text = (New-Object Text.UTF8Encoding($false, $true)).GetString([IO.File]::ReadAllBytes($Path)).TrimEnd("`r", "`n")
    if (-not $text -or $text -match '[\r\n\x00]') { throw 'Git 元数据格式无效。' }
    return $text
}
# 元数据只接受确定的本地绝对路径或相对路径，拒绝 UNC 和驱动器相对写法。
function Resolve-JobsRollbackMetadataPath {
    param([string]$Base, [string]$Value)
    if (-not $Value -or $Value -match '^[\\/]{2}' -or $Value -match '^[A-Za-z]:($|[^\\/])') { throw '不支持网络或驱动器相对 Git 元数据路径。' }
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT -and $Value -match '^[\\/]') { throw 'Git 元数据必须使用明确驱动器。' }
    if (-not [IO.Path]::IsPathRooted($Value)) { $Value = Join-Path $Base $Value }
    return [IO.Path]::GetFullPath($Value)
}
# 支持普通 gitdir、子模块 gitfile 和 worktree commondir。
function Test-JobsRollbackMetadata {
    param([string]$Directory)
    try {
        [void](Assert-JobsRollbackPlainPath $Directory $true)
        $head = Read-JobsRollbackMetadata (Join-Path $Directory 'HEAD')
        if ($head -notmatch '^(ref: refs/[^\s~^:?*\[\\]+|[0-9a-fA-F]{40}|[0-9a-fA-F]{64})$' -or $head -match '\.\.|@\{' -or $head.EndsWith('/') -or $head.EndsWith('.')) { return $false }
        $common = $Directory
        $commonFile = Join-Path $Directory 'commondir'
        if (Test-Path -LiteralPath $commonFile) {
            $common = Read-JobsRollbackMetadata $commonFile
            $common = Resolve-JobsRollbackMetadataPath $Directory $common
        }
        [void](Assert-JobsRollbackPlainPath $common $true)
        [void](Assert-JobsRollbackPlainPath (Join-Path $common 'objects') $true)
        $references = Join-Path $common 'refs'
        if (-not (Test-Path -LiteralPath $references -PathType Container)) { $references = Join-Path $common 'reftable' }
        [void](Assert-JobsRollbackPlainPath $references $true)
        [void](Assert-JobsRollbackPlainPath (Join-Path $common 'config') $false)
        return $true
    } catch { return $false }
}
# 最近内层 .git 一旦出现必须有效；无效时禁止继续向上误操作父仓。
function Get-JobsRollbackBoundary {
    param([string]$Target)
    if (-not [IO.Path]::IsPathRooted($Target) -or $Target -match '^[\\/]{2}') { throw '目标必须为本地绝对目录，不支持网络共享。' }
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT -and $Target -notmatch '^[A-Za-z]:[\\/]') { throw '目标必须包含明确的本地驱动器。' }
    $directory = Assert-JobsRollbackPlainPath $Target $true
    $scan = New-Object IO.DirectoryInfo $directory
    while ($null -ne $scan) {
        if ($scan.Name -ieq '.git' -or (Test-JobsRollbackMetadata $scan.FullName)) { throw 'Git 元数据内部和裸仓不提供回退。' }
        $marker = Join-Path $scan.FullName '.git'
        if (Test-Path -LiteralPath $marker) {
            $item = Get-Item -LiteralPath $marker -Force
            if ($item.PSIsContainer) { $metadata = Assert-JobsRollbackPlainPath $marker $true }
            else {
                $text = Read-JobsRollbackMetadata $marker
                if (-not $text.StartsWith('gitdir: ', [StringComparison]::Ordinal) -or $text.Length -le 8) { throw '内层 .git 文件无效；不回退父仓。' }
                $metadata = $text.Substring(8)
                $metadata = Resolve-JobsRollbackMetadataPath $scan.FullName $metadata
            }
            if (-not (Test-JobsRollbackMetadata $metadata)) { throw '最近工作树的 Git 元数据无效；不回退父仓。' }
            return [pscustomobject]@{ Root = $scan.FullName; Metadata = $metadata }
        }
        $scan = $scan.Parent
    }
    throw '目标不在有效 Git 工作树内。'
}
# Git 只接收数组参数，仓库覆盖环境仅从本次子进程移除。
function Invoke-JobsRollbackGit {
    param([string]$Git, [string]$Directory, [string[]]$Arguments, [switch]$AllowFailure)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Git
    $all = @('--no-optional-locks', '-c', 'submodule.recurse=false', '-c', 'diff.autoRefreshIndex=false', '-C', $Directory) + $Arguments
    $start.Arguments = (@($all | ForEach-Object { Quote-JobsArgument $_ }) -join ' ')
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $start.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    foreach ($name in @('GIT_DIR','GIT_WORK_TREE','GIT_COMMON_DIR','GIT_INDEX_FILE','GIT_OBJECT_DIRECTORY','GIT_ALTERNATE_OBJECT_DIRECTORIES','GIT_NAMESPACE','GIT_CONFIG_PARAMETERS','GIT_CONFIG_COUNT','GIT_CEILING_DIRECTORIES','GIT_DISCOVERY_ACROSS_FILESYSTEM')) { $start.EnvironmentVariables.Remove($name) }
    $process = [Diagnostics.Process]::Start($start)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        # reset 写工作树时等待原始结果，不能用读取超时强杀慢盘上的写操作。
        if ($Arguments.Count -gt 0 -and $Arguments[0] -ceq 'reset') { $process.WaitForExit() }
        elseif (-not $process.WaitForExit(30000)) { $process.Kill(); throw 'Git 只读检查超时；未开始本轮回退，请保留现场检查。' }
        $result = [pscustomobject]@{ ExitCode = $process.ExitCode; StdOut = $stdout.GetAwaiter().GetResult(); StdErr = $stderr.GetAwaiter().GetResult() }
        if ($result.ExitCode -ne 0 -and -not $AllowFailure) { throw ('Git 操作失败：' + $Arguments[0] + '；' + $result.StdErr.Trim()) }
        return $result
    } finally { $process.Dispose() }
}
# 将只读 Git 输出保留原始路径字符。
function Get-JobsRollbackValue {
    param($Context, [string[]]$Arguments)
    return (Invoke-JobsRollbackGit $Context.Git $Context.Root $Arguments).StdOut.TrimEnd("`r", "`n")
}
# 游离 HEAD 记录为空身份；显式历史回退仍可用，远端模式另行拒绝。
function Get-JobsRollbackBranch {
    param($Context)
    $result = Invoke-JobsRollbackGit $Context.Git $Context.Root @('symbolic-ref','--quiet','HEAD') -AllowFailure
    if ($result.ExitCode -eq 1) { return '' }
    if ($result.ExitCode -ne 0) { throw '无法读取当前分支身份。' }
    return $result.StdOut.TrimEnd("`r", "`n")
}
# 冲突、未完成事务和索引锁必须先由用户处理。
function Assert-JobsRollbackReady {
    param($Context)
    foreach ($marker in @('MERGE_HEAD','CHERRY_PICK_HEAD','REVERT_HEAD','BISECT_LOG','BISECT_START','rebase-merge','rebase-apply','sequencer','index.lock')) {
        if (Test-Path -LiteralPath (Join-Path $Context.Metadata $marker)) { throw ('存在未完成 Git 操作或锁：' + $marker) }
    }
    if (Get-JobsRollbackValue $Context @('ls-files','--unmerged')) { throw '存在未解决冲突。' }
}
# Windows 路径按文件系统大小写规则比较，引用和提交仍用精确比较。
function Test-JobsRollbackSamePath {
    param([string]$Left, [string]$Right)
    $comparison=[StringComparison]::Ordinal
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { $comparison=[StringComparison]::OrdinalIgnoreCase }
    return [string]::Equals([IO.Path]::GetFullPath($Left),[IO.Path]::GetFullPath($Right),$comparison)
}
# 交互期间身份、分支和 HEAD 改变时停止，避免作用于新现场。
function Assert-JobsRollbackContext {
    param($Context)
    $boundary = Get-JobsRollbackBoundary $Context.Selected
    $root = Get-JobsRollbackValue $Context @('rev-parse','--show-toplevel')
    $metadata = Get-JobsRollbackValue $Context @('rev-parse','--absolute-git-dir')
    $branch = Get-JobsRollbackBranch $Context
    $head = Get-JobsRollbackValue $Context @('rev-parse','--verify','HEAD^{commit}')
    if (-not (Test-JobsRollbackSamePath $root $Context.Root) -or -not (Test-JobsRollbackSamePath $metadata $Context.Metadata) -or -not (Test-JobsRollbackSamePath $boundary.Root $Context.Root) -or $branch -cne $Context.Branch -or $head -cne $Context.Head) { throw '选择或确认期间仓库、分支或 HEAD 已变化；未执行回退。' }
    Assert-JobsRollbackReady $Context
}
# fzf 单选区分选中、返回、取消；左键在无匹配时也优先作为返回。
function Select-JobsRollbackEntry {
    param([string]$Title, [string[]]$Entries, [switch]$Back)
    if (@($Entries).Count -eq 0) { throw ('没有可选择的记录：' + $Title) }
    $selection = Select-JobsFzfItems -Title $Title -Items $Entries -Child:$Back
    if ($selection.Action -ceq 'back') { return @{ Action = 'Back'; Value = '' } }
    if ($selection.Action -cne 'selected') { return @{ Action = 'Cancel'; Value = '' } }
    return @{ Action = 'Selected'; Value = $selection.Items[0] }
}
# 单独解析选择结果，任何列表外返回都不能进入业务。
function ConvertFrom-JobsRollbackSelection {
    param([string[]]$Lines, [int]$ExitCode, [string[]]$Entries, [switch]$Back)
    if ($Back -and @($Lines).Count -gt 0 -and $Lines[0] -ceq 'left') { return @{ Action='Back'; Value='' } }
    if ($ExitCode -in @(1,130)) { return @{ Action='Cancel'; Value='' } }
    if ($ExitCode -ne 0) { throw ('fzf 选择失败，退出码：' + $ExitCode) }
    if ($Back -and @($Lines).Count -gt 0) { $Lines = @($Lines | Select-Object -Skip 1) }
    if (@($Lines).Count -eq 0 -or (@($Lines).Count -eq 1 -and -not $Lines[0])) { return @{ Action='Cancel'; Value='' } }
    if (@($Lines).Count -ne 1 -or $Lines[0] -cnotin $Entries) { throw 'fzf 返回列表外内容；未执行回退。' }
    return @{ Action='Selected'; Value=$Lines[0] }
}
# 收集当前分支各远端本地快照及真实 upstream，不联网刷新。
function Get-JobsRollbackRemoteTarget {
    param($Context)
    if (-not $Context.Branch) { throw '游离 HEAD 没有明确分支，不能回退到远端；可选择历史提交、tag 或 reflog。' }
    $branch = Get-JobsRollbackValue $Context @('symbolic-ref','--quiet','--short','HEAD')
    $refs = @()
    $upstream = Invoke-JobsRollbackGit $Context.Git $Context.Root @('rev-parse','--symbolic-full-name','@{upstream}') -AllowFailure
    if ($upstream.ExitCode -eq 0 -and $upstream.StdOut.Trim().StartsWith('refs/remotes/')) { $refs += $upstream.StdOut.Trim() }
    foreach ($remote in ((Get-JobsRollbackValue $Context @('remote')) -split '\r?\n')) {
        if ($remote) { $refs += 'refs/remotes/' + $remote + '/' + $branch }
    }
    $snapshots = @{}
    $entries = @()
    foreach ($ref in @($refs | Select-Object -Unique)) {
        $valid = Invoke-JobsRollbackGit $Context.Git $Context.Root @('show-ref','--verify','--hash',$ref) -AllowFailure
        if ($valid.ExitCode -ne 0) { continue }
        $commit = Get-JobsRollbackValue $Context @('rev-parse','--verify',($ref + '^{commit}'))
        $entry = $ref + ' [' + $commit + ']'
        $entries += $entry
        $snapshots[$entry] = @{ Ref=$ref; Commit=$commit }
    }
    if ($entries.Count -eq 0) { throw '没有当前分支可用的本地远端跟踪快照；可选择历史提交回退。' }
    if ($entries.Count -gt 1) {
        $choice = Select-JobsRollbackEntry '选择本地远端快照（不联网）' $entries -Back
        if ($choice.Action -cne 'Selected') { return $choice }
        $target = $snapshots[$choice.Value]
    } else { $target = $snapshots[$entries[0]] }
    $now = Get-JobsRollbackValue $Context @('rev-parse','--verify',($target.Ref + '^{commit}'))
    if ($now -cne $target.Commit) { throw '选择期间远端跟踪快照已变化；没有回退。' }
    return @{ Action='Selected'; Value=$target.Commit; Description=$target.Ref }
}
# 真实索引差异决定回退后提示，空提交不会虚报文件变更。
function Write-JobsRollbackStaged {
    param($Context)
    $result = Invoke-JobsRollbackGit $Context.Git $Context.Root @('diff','--cached','--quiet','--ignore-submodules=none') -AllowFailure
    if ($result.ExitCode -eq 0) { Write-JobsRollbackMessage '暂存区相对当前 HEAD 没有文件差异；空提交或内容抵消时属于正常结果。' }
    elseif ($result.ExitCode -eq 1) { Write-JobsRollbackMessage ('待提交差异：' + (Get-JobsRollbackValue $Context @('diff','--cached','--shortstat','--ignore-submodules=none'))) }
    else { throw '无法核对暂存区，请保留现场检查。' }
}
# soft 只接受起始 HEAD 的祖先，不改现有索引和工作树内容。
function Invoke-JobsRollbackSoft {
    param($Context, [string]$Commit, [string]$Description)
    Assert-JobsRollbackContext $Context
    $ancestor = Invoke-JobsRollbackGit $Context.Git $Context.Root @('merge-base','--is-ancestor',$Commit,$Context.Head) -AllowFailure
    if ($ancestor.ExitCode -ne 0) { throw '目标不是当前 HEAD 的祖先，本地可能落后或分叉；未执行回退。' }
    if ($Commit -ceq $Context.Head) { Write-JobsRollbackMessage 'HEAD 已与目标相同，本次没有撤回提交。'; Write-JobsRollbackStaged $Context; return }
    Write-JobsRollbackMessage ('soft 本地回退到 ' + $Description + ' [' + $Commit + ']；保留工作区和索引，其它远端可能已经包含这些提交。')
    Assert-JobsRollbackContext $Context
    [void](Invoke-JobsRollbackGit $Context.Git $Context.Root @('reset','--soft',$Commit))
    Write-JobsRollbackMessage 'soft 回退完成。'
    Write-JobsRollbackStaged $Context
}
# 摘要保护确认期间的索引、已跟踪变化和未跟踪状态。
function Get-JobsRollbackHardState {
    param($Context)
    $index = Get-JobsRollbackValue $Context @('rev-parse','--git-path','index')
    if (-not [IO.Path]::IsPathRooted($index)) { $index = Join-Path $Context.Root $index }
    $digest = 'missing'
    if ([IO.File]::Exists($index)) { $digest = (Get-FileHash -LiteralPath $index -Algorithm SHA256).Hash }
    $data = $digest + "`0" + (Get-JobsRollbackValue $Context @('diff','--no-ext-diff','--no-textconv','--binary','--ignore-submodules=all')) + "`0" + (Get-JobsRollbackValue $Context @('status','--porcelain=v1','-z','--untracked-files=all','--ignore-submodules=none'))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($data))) }
    finally { $sha.Dispose() }
}
# 仅精确 YES 才 reset；固定提交号并再次核对现场，不递归子模块。
function Invoke-JobsRollbackHard {
    param($Context, [string]$Commit, [string]$Description)
    Assert-JobsRollbackContext $Context
    $fixed = Get-JobsRollbackValue $Context @('rev-parse','--verify',($Commit + '^{commit}'))
    $before = Get-JobsRollbackHardState $Context
    Write-JobsRollbackMessage ('仓库：' + $Context.Root + '；hard 回退到 ' + $Description + ' [' + $fixed + ']。已跟踪修改会丢失；阻挡目标检出的未跟踪路径也可能被 Git 删除。子模块工作树不递归重置。')
    $answer = Read-JobsRollbackInput '输入 YES 执行；回车、其它输入或输入结束取消'
    if ($answer -cne 'YES') { Write-JobsRollbackMessage '已取消 hard 回退。'; return }
    Assert-JobsRollbackContext $Context
    if ((Get-JobsRollbackHardState $Context) -cne $before) { throw '确认期间索引或工作区已变化；未执行 hard 回退。' }
    Assert-JobsRollbackContext $Context
    [void](Invoke-JobsRollbackGit $Context.Git $Context.Root @('reset','--hard','--no-recurse-submodules',$fixed))
    Write-JobsRollbackMessage ('hard 回退完成：' + $fixed)
}
# 读取终端确认；不使用 eval 或脚本拼接解释用户输入。
function Read-JobsRollbackInput {
    param([string]$Prompt)
    Write-JobsEnterChoiceText ($Prompt + '：') -NoNewline
    return [Console]::ReadLine()
}
# 六种模式与目标选择组成明确的两级循环，返回重新进入真实上层。
function Invoke-JobsRollbackMenu {
    param($Context)
    $modes = @('soft 回退到 upstream','选择提交 soft 回退','hard 回退到 upstream','选择提交 hard 回退','选择 tag hard 回退','选择 reflog hard 回退')
    while ($true) {
        $mode = Select-JobsRollbackEntry '选择回退模式' $modes
        if ($mode.Action -cne 'Selected') { Write-JobsRollbackMessage '已取消回退。'; return }
        if ($mode.Value -in @('soft 回退到 upstream','hard 回退到 upstream')) { $target = Get-JobsRollbackRemoteTarget $Context }
        else {
            if ($mode.Value -eq '选择 tag hard 回退') { $records = @((Get-JobsRollbackValue $Context @('tag','--sort=-creatordate')) -split '\r?\n' | Where-Object { $_ }) }
            elseif ($mode.Value -eq '选择 reflog hard 回退') { $records = @((Get-JobsRollbackValue $Context @('reflog','--format=%H %gd %gs','--max-count=200')) -split '\r?\n' | Where-Object { $_ }) }
            else { $records = @((Get-JobsRollbackValue $Context @('log','--all','--format=%H %s','--max-count=200')) -split '\r?\n' | Where-Object { $_ }) }
            $target = Select-JobsRollbackEntry '选择回退后保留的目标' $records -Back
            if ($target.Action -ceq 'Selected') {
                $description = $target.Value
                if ($mode.Value -eq '选择 tag hard 回退') { $commit = Get-JobsRollbackValue $Context @('rev-parse','--verify',('refs/tags/' + $target.Value + '^{commit}')) }
                else { $commit = $target.Value.Split(' ')[0] }
                $target = @{ Action='Selected'; Value=$commit; Description=$description }
            }
        }
        if ($target.Action -ceq 'Back') { continue }
        if ($target.Action -cne 'Selected') { Write-JobsRollbackMessage '已取消回退。'; return }
        if ($mode.Value -in @('soft 回退到 upstream','选择提交 soft 回退')) { Invoke-JobsRollbackSoft $Context $target.Value $target.Description }
        else { Invoke-JobsRollbackHard $Context $target.Value $target.Description }
        return
    }
}
# 首屏先说明和回车；之后才写日志及进入依赖检查和回退流程。
function Invoke-JobsFeature {
    param([Parameter(Mandatory = $true)][string]$Target)
    Write-Host 'Jobs | Git 提交回退（识别子Git）' -ForegroundColor Red
    Write-Host '仅处理目标所属最近工作树，支持子模块 / 嵌套仓库 / worktree；不递归重置子仓。'
    Write-Host 'soft 保留索引与工作区；hard 丢弃已跟踪变化，需另输入 YES。只读本地快照，不 fetch、不推送。'
    Write-Host ('日志：' + (Join-Path (Get-JobsInstallRoot) 'logs') + '；Ctrl+C 随时取消。')
    if ([Console]::IsInputRedirected) { throw '需要独立交互终端，没有确认不能执行。' }
    if ($null -eq (Read-JobsRollbackInput '按回车继续，Ctrl+C 取消')) { throw '输入结束，未执行。' }
    $boundary = Get-JobsRollbackBoundary $Target
    $git = Find-JobsExecutable 'git.exe' @('git')
    if (-not $git) { throw 'Git 不可用；请先安装或修复 Git 后重试。' }
    $context = @{ Git=$git; Root=$boundary.Root; Metadata=$boundary.Metadata; Selected=[IO.Path]::GetFullPath($Target) }
    $inside = Get-JobsRollbackValue $context @('rev-parse','--is-inside-work-tree')
    if ($inside -cne 'true') { throw '目标不在 Git 工作树中。' }
    $context.Branch = Get-JobsRollbackBranch $context
    $context.Head = Get-JobsRollbackValue $context @('rev-parse','--verify','HEAD^{commit}')
    Assert-JobsRollbackContext $context
    Write-JobsRollbackMessage ('当前 Git 仓库：' + $context.Root)
    Invoke-JobsRollbackMenu $context
}
Export-ModuleMember -Function Invoke-JobsFeature

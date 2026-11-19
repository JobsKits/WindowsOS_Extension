# Action.psm1 | JobsHarmonySimulatorRepairer
# Created by Jobs on 2026年10月24日，星期六.
# 仅通过官方 Emulator 检测和启动/重启现有实例；不清除数据或重建实例。

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
function Get-JobsHarmonyToolsHome {
    if (-not $env:LOCALAPPDATA) { throw '无法定位用户级 Harmony 工具目录。' }
    return Join-Path $env:LOCALAPPDATA 'Jobs/HarmonySimulator/tools'
}
# 只接受运行时工具明确提供的诊断能力。
function Assert-JobsHarmonyCapabilities {
    param([string]$Emulator)
    $help = Invoke-JobsHarmonyQuery $Emulator @('-help')
    foreach ($flag in @('-list', '-details', '-imageList', '-start', '-stop', '-bootMode')) {
        if ($help -notmatch ('(?<![A-Za-z0-9_-])' + [regex]::Escape($flag) + '(?![A-Za-z0-9_-])')) { throw ('当前 Emulator 缺少已确认能力：' + $flag + '；请升级官方工具后重试。') }
    }
}
# 实例身份由名称、真实路径、产品类型和系统版本共同确定。
function Get-JobsHarmonyRepairFileIdentity {
    param([string]$Directory)
    $item = Get-Item -LiteralPath $Directory -Force -ErrorAction Stop
    if (-not $item.PSIsContainer) { throw '实例路径不是普通目录。' }
    $current = $item
    while ($null -ne $current) {
        if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw '实例路径不能经过链接或联接。' }
        $current = $current.Parent
    }
    $config = Join-Path $Directory 'config.ini'
    if (-not ('Jobs.HarmonyInstanceIdentity' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'HarmonyInstanceIdentity.cs') }
    return [Jobs.HarmonyInstanceIdentity]::Read($Directory, $true) + '|' + [Jobs.HarmonyInstanceIdentity]::Read($config, $false)
}
# Keep metadata plus real directory/configuration file IDs across confirmation.
function Get-JobsHarmonyRepairIdentity {
    param($Instance)
    foreach ($field in @('name', 'instancePath', 'deviceType')) {
        if ($null -eq $Instance.PSObject.Properties[$field] -or $Instance.$field -isnot [string] -or [string]::IsNullOrWhiteSpace($Instance.$field) -or $Instance.$field -match '[\x00-\x1f]') { throw ('实例详情缺少可靠字段：' + $field) }
    }
    if ($Instance.name.StartsWith('-') -or -not [IO.Path]::IsPathRooted($Instance.instancePath)) { throw '实例名称或路径无法可靠识别。' }
    $version = Get-JobsHarmonyInstanceVersion $Instance
    if (-not $version) { throw '实例详情缺少系统版本。' }
    if ($null -eq $Instance.PSObject.Properties['isRunning'] -or ($Instance.isRunning -isnot [bool] -and ($Instance.isRunning -isnot [string] -or $Instance.isRunning -cnotin @('true', 'false')))) { throw '实例详情缺少可靠 isRunning；保留只读诊断，不猜测运行状态。' }
    $running = $Instance.isRunning -is [bool] -and $Instance.isRunning
    if ($Instance.isRunning -is [string]) { $running = $Instance.isRunning -ceq 'true' }
    $uuid = ''
    if ($null -ne $Instance.PSObject.Properties['uuid']) {
        if ($Instance.uuid -isnot [string] -or $Instance.uuid -match '[\x00-\x1f]') { throw '实例 UUID 无法可靠识别。' }
        $uuid = $Instance.uuid
    }
    $fileIdentity = Get-JobsHarmonyRepairFileIdentity $Instance.instancePath
    return [pscustomobject]@{ Name = $Instance.name; Path = [IO.Path]::GetFullPath($Instance.instancePath); DeviceType = $Instance.deviceType; Version = $version; Running = $running; Uuid = $uuid; FileIdentity = $fileIdentity }
}
# 每次变更前重新读取目标身份和运行状态，避免旧菜单误操作其它实例。
function Assert-JobsHarmonyRepairTarget {
    param([string]$Emulator, $Identity, [bool]$Running)
    $matches = @(Get-JobsHarmonyInstances $Emulator | Where-Object { $_.name -ceq $Identity.Name })
    if ($matches.Count -ne 1) { throw '所选实例已经消失或名称不唯一，停止。' }
    $current = Get-JobsHarmonyRepairIdentity $matches[0]
    if ($current.Path -cne $Identity.Path -or $current.DeviceType -cne $Identity.DeviceType -or $current.Version -cne $Identity.Version -or $current.Running -ne $Running -or $current.Uuid -cne $Identity.Uuid -or $current.FileIdentity -cne $Identity.FileIdentity) { throw '所选实例身份或运行状态已变化，停止。' }
    return $current
}
# 只读体检不会创建日志、安装工具、接受协议或修改实例。
function Get-JobsHarmonyRepairCheck {
    param([string]$EmulatorBin = $env:HARMONY_EMULATOR_BIN)
    [void](Get-JobsHarmonyArchitecture)
    $emulator = Get-JobsHarmonyEmulator $EmulatorBin
    Assert-JobsHarmonyCapabilities $emulator
    $images = @(Get-JobsHarmonyImages $emulator)
    $instances = @(Get-JobsHarmonyInstances $emulator)
    return [pscustomobject]@{ Emulator = $emulator; Images = $images; Instances = $instances }
}
# 有限轮询官方状态；超时保留现场并返回失败，不自动重试启动。
function Wait-JobsHarmonyRepairState {
    param([string]$Emulator, $Identity, [bool]$Running)
    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        $matches = @(Get-JobsHarmonyInstances $Emulator | Where-Object { $_.name -ceq $Identity.Name })
        if ($matches.Count -ne 1) { throw '状态回读失去唯一实例，停止。' }
        $current = Get-JobsHarmonyRepairIdentity $matches[0]
        if ($current.Path -cne $Identity.Path -or $current.DeviceType -cne $Identity.DeviceType -or $current.Version -cne $Identity.Version -or $current.Uuid -cne $Identity.Uuid -or $current.FileIdentity -cne $Identity.FileIdentity) { throw '状态回读发现实例身份变化，停止。' }
        if ($current.Running -eq $Running) { return }
        if ($attempt -lt 9) { Start-Sleep -Milliseconds 1000 }
    }
    throw '官方实例状态尚未达到预期；保留现场，请在 DevEco Device Manager 检查，不自动再次启动。'
}
# 重启只使用官方 stop/start，不传 reset、delete 或清数据参数。
function Invoke-JobsHarmonyRepairOperation {
    param([string]$Emulator, $Identity)
    [void](Assert-JobsHarmonyRepairTarget $Emulator $Identity $Identity.Running)
    if ($Identity.Running) {
        if ((Read-JobsHarmonyInput ('将停止并冷启动 ' + $Identity.Name + '，会中断该实例中的在途任务；输入 YES 继续')) -cne 'YES') { throw '已取消，未停止实例。' }
        [void](Assert-JobsHarmonyRepairTarget $Emulator $Identity $true)
        Invoke-JobsHarmonyInteractive $Emulator @('-stop', $Identity.Name)
        Wait-JobsHarmonyRepairState $Emulator $Identity $false
    } elseif ((Select-JobsFzfItems ('确认冷启动 ' + $Identity.Name + '（默认取消）') @('冷启动以上明确实例') -RequireConfirmation).Action -cne 'selected') { throw (New-Object OperationCanceledException('已取消，未启动实例。')) }
    [void](Assert-JobsHarmonyRepairTarget $Emulator $Identity $false)
    Invoke-JobsHarmonyInteractive $Emulator @('-start', $Identity.Name, '-bootMode', 'coldboot')
    Wait-JobsHarmonyRepairState $Emulator $Identity $true
    Write-JobsHarmonyMessage ('已回读确认实例运行：' + $Identity.Name + '；系统和 hdc 连接就绪请在模拟器窗口核对。')
}
# 桌面入口先展示影响范围，随后诊断并选择现有实例。
function Invoke-JobsHarmonyRepairAction {
    param([string]$Target, [string]$EmulatorBin = $env:HARMONY_EMULATOR_BIN)
    if (-not (Test-JobsHarmonyDesktop $Target)) { throw '此入口仅适用于系统桌面空白。' }
    Remove-Variable -Name HarmonyLog -Scope Script -ErrorAction SilentlyContinue
    Write-Host 'Jobs Harmony 模拟器检测与修复' -ForegroundColor Cyan
    Write-Host '检测已有官方 DevEco Emulator、本地镜像与实例；可启动已停止实例，或输入 YES 后停止并冷启动正在运行的实例。'
    Write-Host '仅操作所选本地实例；不下载 SDK 或镜像、不接受其许可、不删应用或数据、不重建实例、不改代理或持久 PATH。键盘选择器缺失才沿本次流程准备 fzf；未知状态停止，Ctrl+C 取消。'
    if ((Read-JobsHarmonyInput '回车开始只读检测；任意非空输入取消').Length -ne 0) { throw '已取消。' }
    $logs = Join-Path (Get-JobsInstallRoot) 'logs'
    [void][IO.Directory]::CreateDirectory($logs)
    $script:HarmonyLog = Join-Path $logs ('repair-' + (Get-Date -Format 'yyyy-MM-dd-HH-mm-ss') + '-' + [guid]::NewGuid().ToString('N') + '.log')
    Write-JobsHarmonyMessage ('日志：' + $script:HarmonyLog)
    $check = Get-JobsHarmonyRepairCheck $EmulatorBin
    Write-JobsHarmonyMessage ('Emulator：' + $check.Emulator + '；已下载 Release 镜像：' + $check.Images.Count + '；实例：' + $check.Instances.Count)
    if ($check.Instances.Count -eq 0) { throw '没有现有实例可修复；请使用“新建 Harmony 模拟器”或在 DevEco Device Manager 创建后重新检测。' }
    foreach ($record in $check.Instances) { Write-JobsHarmonyMessage ($record | ConvertTo-Json -Depth 8 -Compress) }
    $name = Select-JobsHarmonyChoice '选择现有 Harmony 实例（q / Esc 取消）' @($check.Instances | ForEach-Object { $_.name })
    $selected = @($check.Instances | Where-Object { $_.name -ceq $name })
    if ($selected.Count -ne 1) { throw '实例选择无效。' }
    $identity = Get-JobsHarmonyRepairIdentity $selected[0]
    Invoke-JobsHarmonyRepairOperation $check.Emulator $identity
}
function Invoke-JobsFeature {
    param([Parameter(Mandatory = $true)][string]$Target)
    Invoke-JobsHarmonyRepairAction -Target (Resolve-JobsTarget $Target)
}
function ConvertTo-JobsHarmonyPlainText {
    param([string]$Text)
    $escape = [regex]::Escape([string][char]27)
    $plain = $Text -replace ($escape + '\][^\x07]*(?:\x07|' + $escape + '\\)'), ''
    return $plain -replace ($escape + '\[[0-?]*[ -/]*[@-~]'), ''
}
# 将鸿蒙工具诊断写入当前展示与纯文本日志，保持原颜色职责。
function Write-JobsHarmonyMessage {
    param([string]$Text)
    $Text = $Text -replace '\x1b\][^\x07]*(?:\x07|\x1b\\)', '' -replace '\x1b\[[0-?]*[ -/]*[@-~]', ''
    $Text = $Text -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@' -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]' -replace '(?im)((?:token|password|secret|authorization)\s*[:=]\s*)\S+', '$1[已省略]'
    $plain = ConvertTo-JobsHarmonyPlainText $Text
    Write-JobsEnterChoiceText $plain
    if (Get-Variable -Name HarmonyLog -Scope Script -ErrorAction SilentlyContinue) {
        [IO.File]::AppendAllText($script:HarmonyLog, $plain + [Environment]::NewLine, (New-Object Text.UTF8Encoding($true)))
    }
}
# 按原宿主输入协议显示询问并读取原文，不改变业务选择。
function Read-JobsHarmonyInput {
    param([string]$Prompt)
    Write-JobsEnterChoiceText ($Prompt + '：') -NoNewline -Question
    $answer = [Console]::ReadLine()
    if ($null -eq $answer) { throw '输入已结束，停止操作。' }
    return $answer
}
function Get-JobsHarmonyArchitecture {
    $architecture = $env:PROCESSOR_ARCHITEW6432
    if ([string]::IsNullOrWhiteSpace($architecture)) { $architecture = $env:PROCESSOR_ARCHITECTURE }
    if ($architecture -ine 'AMD64') { throw 'Harmony 本地模拟器只支持 x64 Windows 10 / 11；Windows ARM、32 位系统和虚拟机不在官方支持范围：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-requirements' }
    return 'x86_64'
}
function Test-JobsHarmonyDesktop {
    param([string]$Target)
    $desktop = [Environment]::GetFolderPath('DesktopDirectory')
    if (-not $Target -or -not $desktop -or -not [IO.Directory]::Exists($Target)) { return $false }
    return [string]::Equals([IO.Path]::GetFullPath($Target).TrimEnd('\', '/'), [IO.Path]::GetFullPath($desktop).TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)
}
function Get-JobsHarmonyEmulator {
    param([string]$EmulatorBin = $env:HARMONY_EMULATOR_BIN)
    if ($EmulatorBin) {
        if (-not [IO.Path]::IsPathRooted($EmulatorBin) -or $EmulatorBin -match '[\x00-\x1f]' -or [IO.Path]::GetExtension($EmulatorBin) -ine '.exe') { throw 'HARMONY_EMULATOR_BIN 必须是无控制字符的 Emulator.exe 绝对路径。' }
        if (-not [IO.File]::Exists($EmulatorBin)) { throw ('指定 Emulator 不存在，不会改用其它工具：' + $EmulatorBin) }
        return [IO.Path]::GetFullPath($EmulatorBin)
    }
    $toolHome = $env:DEVECO_STUDIO_HOME
    if (-not $toolHome) { $toolHome = $env:TOOL_HOME }
    if ($toolHome) {
        if (-not [IO.Path]::IsPathRooted($toolHome) -or $toolHome -match '[\x00-\x1f]') { throw 'DEVECO_STUDIO_HOME / TOOL_HOME 必须是无控制字符的绝对路径。' }
        foreach ($relative in @('tools/emulator/Emulator.exe', 'emulator/Emulator.exe')) {
            $file = Join-Path $toolHome $relative
            if ([IO.File]::Exists($file)) { return [IO.Path]::GetFullPath($file) }
        }
        throw ('指定 DevEco / Command Line Tools 中没有 Emulator.exe，不会静默切换：' + $toolHome)
    }
    $candidates = @()
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $base) { continue }
        foreach ($relative in @('Huawei/DevEco Studio/tools/emulator/Emulator.exe', 'Huawei/DevEcoStudio/tools/emulator/Emulator.exe')) {
            $file = Join-Path $base $relative
            if ([IO.File]::Exists($file)) { $candidates += [IO.Path]::GetFullPath($file) }
        }
    }
    $toolsHome = Get-JobsHarmonyToolsHome
    if ([IO.Directory]::Exists($toolsHome)) {
        foreach ($directory in @(Get-ChildItem -LiteralPath $toolsHome -Directory -Filter 'clt-*')) {
            $file = Join-Path $directory.FullName 'emulator/Emulator.exe'
            if ([IO.File]::Exists($file)) { $candidates += $file }
        }
    }
    foreach ($command in @(Get-Command -Name 'Emulator.exe', 'Emulator' -CommandType Application -All -ErrorAction SilentlyContinue)) {
        if ([IO.File]::Exists($command.Source)) { $candidates += $command.Source }
    }
    $compatible = @()
    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        try { Assert-JobsHarmonyCapabilities $candidate; $compatible += $candidate }
        catch { Write-JobsHarmonyMessage ('已排除不兼容工具：' + $candidate) }
    }
    if ($compatible.Count -gt 1) { throw '发现多份兼容 DevEco Emulator，请用 HARMONY_EMULATOR_BIN 明确选择。' }
    if ($compatible.Count -eq 1) { return $compatible[0] }

    throw '未找到兼容 DevEco Emulator。请先准备官方工具，或运行“新建 Harmony 模拟器”补齐；本检测入口不自动下载。'

}
function Invoke-JobsHarmonyQuery {
    param([string]$Emulator, [string[]]$Arguments)
    $result = Invoke-JobsProcess -FilePath $Emulator -Arguments $Arguments -TimeoutSeconds 60
    $output = ConvertTo-JobsHarmonyPlainText $result.StdOut
    if ($result.ExitCode -ne 0) { throw ('Emulator ' + ($Arguments -join ' ') + ' 失败，退出码 ' + $result.ExitCode + [Environment]::NewLine + $output + (ConvertTo-JobsHarmonyPlainText $result.StdErr)) }
    $output = $output.TrimStart([char]0xfeff).Trim()
    $errorText = (ConvertTo-JobsHarmonyPlainText $result.StdErr).Trim()
    # 6.1.1.200 实测空结果不是 JSON；仅精确匹配成功响应，不吞掉未知错误。
    if (($Arguments -join ' ') -match '^-imageList -downloaded (true|false)$' -and [string]::IsNullOrEmpty($output) -and $errorText -ceq 'No images matching the criteria were found.') { return '[]' }
    if (($Arguments -join ' ') -ceq '-list -details' -and $output -ceq '[Empty]' -and [string]::IsNullOrEmpty($errorText)) { return '[]' }
    return $output
}
function ConvertFrom-JobsHarmonyJson {
    param([string]$Text, [string]$Label)
    if ([string]::IsNullOrWhiteSpace($Text) -or $Text[0] -notin @('[', '{')) { throw ($Label + ' 未返回可识别的 JSON，停止；请核对当前官方 Emulator 输出。') }
    try { $result = $Text | ConvertFrom-Json -ErrorAction Stop }
    catch { throw ($Label + ' JSON 无法解析，停止；不会按日志文字判断成功。') }
    return $result
}
function Get-JobsHarmonyImages {
    param([string]$Emulator, [switch]$Available)
    $downloadedFilter = 'true'
    if ($Available) { $downloadedFilter = 'false' }
    $text = Invoke-JobsHarmonyQuery $Emulator @('-imageList', '-downloaded', $downloadedFilter)
    if (-not $text.StartsWith('[')) { throw '镜像清单必须为官方 JSON 数组；没有开始创建。' }
    $records = @(ConvertFrom-JobsHarmonyJson $text '镜像清单')
    $images = @()
    $seen = @{}
    foreach ($record in $records) {
        if ($null -eq $record) { continue }
        foreach ($field in @('SoftWareVersion', 'deviceType', 'osVersion', 'downloaded', 'releaseType', 'upgradable')) {
            if ($null -eq $record.PSObject.Properties[$field]) { throw ('镜像清单缺少字段：' + $field) }
        }
        foreach ($field in @('SoftWareVersion', 'deviceType', 'osVersion', 'releaseType')) {
            if ($record.$field -isnot [string] -or [string]::IsNullOrWhiteSpace($record.$field) -or $record.$field -match '[\x00-\x1f]') { throw ('镜像字段类型或内容不合法：' + $field) }
        }
        foreach ($field in @('downloaded', 'upgradable')) {
            if ($record.$field -isnot [bool] -and ($record.$field -isnot [string] -or $record.$field -cnotin @('true', 'false'))) { throw ('镜像布尔字段不合法：' + $field) }
        }
        if ($record.releaseType -ine 'Release') { continue }
        $downloaded = $record.downloaded -is [bool] -and $record.downloaded
        if ($record.downloaded -is [string]) { $downloaded = $record.downloaded -ceq 'true' }
        if ($downloaded -eq [bool]$Available) { continue }
        $type = [string]$record.deviceType
        $version = [string]$record.osVersion
        if ($type -cnotmatch '^(?:[A-Za-z][A-Za-z0-9_-]*|2in1(?: Foldable)?)$' -or [string]::IsNullOrWhiteSpace($version) -or $version.StartsWith('-') -or $version -match '[\x00-\x1f]') { throw '镜像元数据不合法，停止。' }
        $key = $type.ToLowerInvariant() + '|' + $version
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $images += [pscustomobject]@{ DeviceType = $type; OsVersion = $version; Label = $type + ' | ' + $version }
    }
    return @($images | Sort-Object @{ Expression = { if ($_.DeviceType -ieq 'phone') { 0 } else { 1 } } }, DeviceType,
        @{ Expression = { if ($_.OsVersion -match 'HarmonyOS ([0-9]+\.[0-9]+\.[0-9]+)') { [version]$Matches[1] } else { [version]'0.0.0' } }; Descending = $true },
        @{ Expression = { if ($_.OsVersion -match '\(([0-9]+)') { [int]$Matches[1] } else { 0 } }; Descending = $true })
}
function Get-JobsHarmonyInstances {
    param([string]$Emulator)
    $text = Invoke-JobsHarmonyQuery $Emulator @('-list', '-details')
    if (-not $text.StartsWith('[')) { throw '实例详情必须为官方 JSON 数组。' }
    $records = @(ConvertFrom-JobsHarmonyJson $text '实例清单')
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($record in $records) {
        if ($null -eq $record -or $null -eq $record.PSObject.Properties['name'] -or $record.name -isnot [string] -or [string]::IsNullOrWhiteSpace($record.name) -or $record.name -match '[\x00-\x1f]') { throw '实例清单必须包含无控制字符的真实字符串 name；没有按文本猜测结果。' }
        if (-not $names.Add($record.name)) { throw ('实例清单存在重复或大小写冲突名称，停止：' + $record.name) }
    }
    return $records
}
# 按当前层级保留查询状态并返回明确的选择、返回或取消结果。
function Select-JobsHarmonyChoice {
    param([string]$Title, [string[]]$Choices, [switch]$Child)
    $result = Select-JobsFzfItems $Title $Choices -Child:$Child
    if ($result.Action -ceq 'selected') { return $result.Items[0] }
    $errorValue = New-Object OperationCanceledException('选择已取消，未执行业务。')
    $errorValue.Data['JobsPickerAction'] = $result.Action
    throw $errorValue
}
function Invoke-JobsHarmonyInteractive {
    param([string]$Emulator, [string[]]$Arguments)
    Write-JobsHarmonyMessage ('执行官方工具：' + $Emulator + ' ' + ($Arguments -join ' '))
    # 保留 stdin 与官方退出码；许可仅在本人明确同意后接受，-force 仅用于确认后的镜像安装。
    $global:LASTEXITCODE = -1
    & $Emulator @Arguments | Out-Host
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw ('Emulator 操作失败，退出码 ' + $code + '；保留官方输出和已生成的现场。') }
}
# 展示随工具分发的许可原文；只有用户明确回车同意后才执行官方接受命令。
function Get-JobsHarmonyInstanceVersion {
    param($Instance)
    $flat = $null
    $nested = $null
    if ($null -ne $Instance.PSObject.Properties['os.osVersion']) { $flat = $Instance.'os.osVersion' }
    if ($null -ne $Instance.PSObject.Properties['os'] -and $null -ne $Instance.os -and $null -ne $Instance.os.PSObject.Properties['osVersion']) { $nested = $Instance.os.osVersion }
    foreach ($value in @($flat, $nested)) {
        if ($null -ne $value -and ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value) -or $value -match '[\x00-\x1f]')) { throw '实例系统版本字段类型或内容不合法。' }
    }
    if ($null -ne $flat -and $null -ne $nested -and $flat -cne $nested) { throw '实例详情的平铺 / 嵌套系统版本冲突，停止验证。' }
    if ($null -ne $flat) { return $flat }
    if ($null -ne $nested) { return $nested }
    return ''
}

Export-ModuleMember -Function Invoke-JobsFeature

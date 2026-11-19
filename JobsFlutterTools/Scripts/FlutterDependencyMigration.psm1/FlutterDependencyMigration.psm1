# FlutterDependencyMigration.psm1 | 一键迁移与原始缓存融合。
# 只复用本包引擎和项目 FVM Dart；默认私库，写入前预检，ZIP 校验后才可删除本次产物。

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
    $selection = Select-JobsFzfItems -Title '冲突处理' -Items $labels
    if ($selection.Action -cne 'selected') { return $null }
    if ($selection.Items[0] -ceq $labels[0]) { return 'source' }
    return 'existing'
}
# 将迁移诊断安全写入业务展示与纯文本日志。
function Write-JobsMigrationMessage {
    param([string]$Message)
    $Message = $Message -replace '\x1b\][^\x07]*(?:\x07|\x1b\\)', '' -replace '\x1b\[[0-?]*[ -/]*[@-~]', ''
    $Message = $Message -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@' -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]' -replace '(?im)((?:token|password|secret|authorization)\s*[:=]\s*)\S+', '$1[已省略]'
    $safe = $Message -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@'
    $safe = $safe -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]'
    Write-JobsEnterChoiceText $safe
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

# Action.psm1 | JobsFlutterRunner
# Created by Jobs on 2026年10月20日，星期二.
# CMD 中选择设备和连接日志；Flutter 生命周期由独立后台宿主管理。

# Jobs enter-choice emphasis is display-only; input and business decisions stay with callers.

# 源包装与已发布 flat 布局共用路径，兼容旧收据且不跟随包装目录链接。
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

function Resolve-JobsScriptLayoutPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    if ([IO.Path]::GetExtension($Path) -notin @('.ps1','.cmd','.vbs')) { return $Path }
    if (Test-Path -LiteralPath $Path -PathType Container) {
        $directory = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ('脚本包装不能是链接：' + $Path) }
        return Join-Path $Path $directory.Name
    }
    return $Path
}
# 仅新源码包装压平到原发布名称；原有 SDK 资源包与 README 布局保持原意。
function Convert-JobsReleaseLayoutRelativePath {
    param([string]$Package, [string]$Relative)
    $parts = @($Relative -split '[\\/]')
    if ($parts.Count -lt 2) { return $Relative }
    $last = $parts[$parts.Count - 1]
    $parent = $parts[$parts.Count - 2]
    if ($last -ceq 'README.md' -and [IO.Path]::GetExtension($parent) -in @('.ps1','.cmd','.vbs')) {
        $sibling = Join-Path (Join-Path $Package (($parts[0..($parts.Count-2)]) -join '/')) $parent
        if ((Test-Path -LiteralPath $sibling -PathType Leaf) -and ([IO.File]::ReadAllText($sibling) -match '(?m)^(?:#|rem|\x27) JOBS_SOURCE_LAYOUT_ROOT_V1')) { return $null }
    }
    if ($last -ceq $parent -and [IO.Path]::GetExtension($last) -in @('.ps1','.cmd','.vbs')) {
        $source = Join-Path $Package $Relative
        if ((Test-Path -LiteralPath $source -PathType Leaf) -and ([IO.File]::ReadAllText($source) -match '(?m)^(?:#|rem|\x27) JOBS_SOURCE_LAYOUT_ROOT_V1')) {
            return (($parts[0..($parts.Count-2)]) -join '/')
        }
    }
    return $Relative
}
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

. (Join-Path $PSScriptRoot 'RunPreflight.ps1/RunDisplay.ps1/RunDisplay.ps1')
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking
. (Resolve-JobsScriptLayoutPath (Join-Path $PSScriptRoot 'SdkDownloadOutput.ps1'))
. (Resolve-JobsScriptLayoutPath (Join-Path $PSScriptRoot 'AndroidRuntime.ps1'))
. (Join-Path $PSScriptRoot 'RunPreflight.ps1/RunPreflight.ps1')
. (Join-Path $PSScriptRoot 'RunPreflight.ps1/RepairRunEnvironment.ps1/RepairRunEnvironment.ps1')
. (Join-Path $PSScriptRoot 'RunPreflight.ps1/PrepareHarmonyRun.ps1/PrepareHarmonyRun.ps1')
. (Join-Path $PSScriptRoot 'RunPreflight.ps1/StartVirtualDevice.ps1/StartVirtualDevice.ps1')
. (Join-Path $PSScriptRoot 'RunPreflight.ps1/StartVirtualDevice.ps1/OfficialHarmonyTools.ps1/OfficialHarmonyTools.ps1')
$script:RunnerSelectedSdk = $null
$script:RunnerSelectedPlatform = $null
$script:RunnerPreflight = $null
$script:RunnerPreparedHarmony = $null

function Assert-JobsRunnerDirectory {
    param([string]$Path)
    if (-not [IO.Path]::IsPathRooted($Path) -or -not [IO.Directory]::Exists($Path)) {
        throw "目标必须是存在的绝对目录：$Path"
    }
    $item = New-Object IO.DirectoryInfo ([IO.Path]::GetFullPath($Path))
    $current = $item
    while ($null -ne $current) {
        if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "不处理符号链接或目录联接：$($current.FullName)"
        }
        $current = $current.Parent
    }
    return $item.FullName
}

function Assert-JobsRunnerPlainFile {
    param([string]$Path)
    $attributes = [IO.File]::GetAttributes($Path)
    if (($attributes -band [IO.FileAttributes]::Directory) -ne 0 -or ($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "配置必须是普通文件：$Path"
    }
}

function Test-JobsRunnerPathEntry {
    param([string]$Path)
    # File.Exists/Test-Path 会将悬空链接当作不存在，GetAttributes 仍能识别链接本身。
    try { [void][IO.File]::GetAttributes($Path); return $true }
    catch [IO.FileNotFoundException] { return $false }
    catch [IO.DirectoryNotFoundException] { return $false }
}

function Remove-JobsYamlComment {
    param([string]$Line)
    $quote = [char]0
    for ($i = 0; $i -lt $Line.Length; $i++) {
        $character = $Line[$i]
        if ($quote -eq [char]34 -and $character -eq [char]92) { $i++; continue }
        if ($quote -eq [char]39 -and $character -eq [char]39 -and $i + 1 -lt $Line.Length -and $Line[$i + 1] -eq [char]39) { $i++; continue }
        if ($quote -ne [char]0) {
            if ($character -eq $quote) { $quote = [char]0 }
            continue
        }
        if ($character -eq [char]39 -or $character -eq [char]34) { $quote = $character; continue }
        if ($character -eq '#' -and ($i -eq 0 -or [char]::IsWhiteSpace($Line[$i - 1]))) {
            return $Line.Substring(0, $i).TrimEnd()
        }
    }
    return $Line.TrimEnd()
}

function ConvertFrom-JobsYamlAtom {
    param([string]$Value)
    $valueText = $Value.Trim()
    if ($valueText -match '^''([^'']*)''$' -or $valueText -match '^"([^"\\]*)"$') { return $Matches[1] }
    return $valueText
}

function ConvertFrom-JobsYamlFlowMap {
    param([string]$Text)
    $value = $Text.Trim()
    if (-not $value.StartsWith('{') -or -not $value.EndsWith('}')) { throw '只支持明确的 YAML 映射，不支持别名、标签或多行 flow 结构。' }
    $body = $value.Substring(1, $value.Length - 2)
    $parts = New-Object 'System.Collections.Generic.List[string]'
    $depth = 0
    $quote = [char]0
    $start = 0
    for ($i = 0; $i -lt $body.Length; $i++) {
        $character = $body[$i]
        if ($quote -eq [char]34 -and $character -eq [char]92) { $i++; continue }
        if ($quote -ne [char]0) {
            if ($character -eq $quote) { $quote = [char]0 }
            continue
        }
        if ($character -eq [char]39 -or $character -eq [char]34) { $quote = $character; continue }
        if ($character -eq '{' -or $character -eq '[') { $depth++ }
        if ($character -eq '}' -or $character -eq ']') { $depth-- }
        if ($depth -lt 0) { throw 'YAML flow 映射括号不匹配。' }
        if ($character -eq ',' -and $depth -eq 0) { $parts.Add($body.Substring($start, $i - $start)); $start = $i + 1 }
    }
    if ($quote -ne [char]0 -or $depth -ne 0) { throw 'YAML flow 映射未闭合。' }
    $parts.Add($body.Substring($start))
    $map = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    for ($partIndex = 0; $partIndex -lt $parts.Count; $partIndex++) {
        $part = $parts[$partIndex]
        if ([string]::IsNullOrWhiteSpace($part)) {
            if ($partIndex -eq $parts.Count - 1 -and ($map.Count -gt 0 -or [string]::IsNullOrWhiteSpace($body))) { continue }
            throw 'YAML flow 映射存在空项。'
        }
        if ($part -notmatch '^\s*(?<key>[A-Za-z_][A-Za-z0-9_-]*|''[^'']+''|"[^"\\]+")\s*:\s*(?<value>.*?)\s*$' -or
            $part -match '^\s*[A-Za-z_][A-Za-z0-9_-]*\s*:\S') { throw '无法可靠读取 YAML flow 映射；未引用键的冒号后须留空格。' }
        $key = ConvertFrom-JobsYamlAtom $Matches['key']
        $entry = $Matches['value']
        if ($map.ContainsKey($key)) { throw "YAML 存在重复键：$key" }
        $map[$key] = $entry
    }
    return $map
}

function Test-JobsFlutterPubspec {
    param([string]$Text)
    $Text = $Text.TrimStart([char]0xfeff)
    if ($Text.IndexOf([char]0) -ge 0) { return $false }
    # 只解释 dependencies.flutter.sdk，不能把 description、注释或 flutter_test 当作 Flutter 项目。
    $lines = @($Text -split '\r?\n' | ForEach-Object { Remove-JobsYamlComment $_ })
    if (@($lines | Where-Object { $_.Trim() -in @('---', '...') }).Count -gt 0) { return $false }
    if (@($lines | Where-Object { $_ -match '^\s*\t' }).Count -gt 0) { return $false }
    $roots = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -cmatch '^(?:dependencies|''dependencies''|"dependencies")\s*:\s*(.*)$') {
            $roots += [pscustomobject]@{ Index = $i; Value = $Matches[1] }
        }
    }
    if ($roots.Count -ne 1) { return $false }
    try {
        if (-not [string]::IsNullOrWhiteSpace($roots[0].Value)) {
            $dependencies = ConvertFrom-JobsYamlFlowMap $roots[0].Value
            if (-not $dependencies.ContainsKey('flutter')) { return $false }
            $flutter = ConvertFrom-JobsYamlFlowMap $dependencies['flutter']
            return $flutter.ContainsKey('sdk') -and (ConvertFrom-JobsYamlAtom $flutter['sdk']) -ceq 'flutter'
        }
        $entries = @()
        for ($i = $roots[0].Index + 1; $i -lt $lines.Count; $i++) {
            if ([string]::IsNullOrWhiteSpace($lines[$i])) { continue }
            if ($lines[$i] -notmatch '^\s') { break }
            if ($lines[$i] -notmatch '^(?<indent> +)(?<key>[A-Za-z_][A-Za-z0-9_-]*|''[^'']+''|"[^"\\]+")\s*:\s*(?<value>.*)$') { return $false }
            $entries += [pscustomobject]@{ Indent = $Matches['indent'].Length; Key = (ConvertFrom-JobsYamlAtom $Matches['key']); Value = $Matches['value']; Index = $i }
        }
        if ($entries.Count -eq 0) { return $false }
        $minimum = ($entries | Measure-Object -Property Indent -Minimum).Minimum
        $declarations = @($entries | Where-Object { $_.Indent -eq $minimum -and $_.Key -ceq 'flutter' })
        if ($declarations.Count -ne 1) { return $false }
        $declaration = $declarations[0]
        if (-not [string]::IsNullOrWhiteSpace($declaration.Value)) {
            $flutter = ConvertFrom-JobsYamlFlowMap $declaration.Value
            return $flutter.ContainsKey('sdk') -and (ConvertFrom-JobsYamlAtom $flutter['sdk']) -ceq 'flutter'
        }
        $children = @()
        foreach ($entry in $entries) {
            if ($entry.Index -le $declaration.Index) { continue }
            if ($entry.Indent -le $declaration.Indent) { break }
            $children += $entry
        }
        if ($children.Count -eq 0) { return $false }
        $childIndent = ($children | Measure-Object -Property Indent -Minimum).Minimum
        $sdk = @($children | Where-Object { $_.Indent -eq $childIndent -and $_.Key -ceq 'sdk' })
        return $sdk.Count -eq 1 -and (ConvertFrom-JobsYamlAtom $sdk[0].Value) -ceq 'flutter'
    }
    catch { return $false }
}

function Assert-JobsFlutterProject {
    param([string]$Directory)
    [void](Assert-JobsRunnerDirectory $Directory)
    $pubspec = Join-Path $Directory 'pubspec.yaml'
    Assert-JobsRunnerPlainFile $pubspec
    if ((Get-Item -LiteralPath $pubspec).Length -gt 1MB) { throw 'pubspec.yaml 超过 1 MiB，停止读取。' }
    if (-not (Test-JobsFlutterPubspec (Get-Content -LiteralPath $pubspec -Raw -Encoding UTF8))) {
        throw '目标同层 pubspec.yaml 必须明确声明 dependencies.flutter.sdk: flutter；不会扫描子目录或沿用父工程。YAML 别名、标签及多行 flow 映射请先改成常见 block 写法。'
    }
}

function Get-JobsRunnerFlutter {
    param([string]$Project)
    foreach ($candidate in @((Join-Path $Project '.fvm/flutter_sdk/bin/flutter.bat'), (Join-Path $Project '.fvm/flutter_sdk/bin/flutter.exe'))) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return [IO.Path]::GetFullPath($candidate) }
    }
    foreach ($binding in @('.fvmrc', '.fvm/fvm_config.json', '.fvm/flutter_sdk')) {
        if (Test-JobsRunnerPathEntry (Join-Path $Project $binding)) {
            throw '项目已绑定 FVM，但项目 Flutter SDK 缺失或不完整。请先安装 / 修复对应 FVM SDK，再运行；不会改用 PATH 的其它版本。'
        }
    }
    $flutter = Find-JobsExecutable -Name 'flutter.bat' -Candidates @('flutter.exe', 'flutter')
    if (-not $flutter) { throw '没有可用 Flutter。先安装 Flutter SDK 并加入 PATH，或用本仓 FVM 菜单绑定项目版本。' }
    return $flutter
}

# 仅阅读本地 SDK 元数据；探测日志不能触发 Flutter/Dart 自举下载。
function Read-JobsRunnerSdkMetadata {
    param([string]$Path)
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if ($item.PSIsContainer -or $item.Length -gt 65536) { return '' }
        return [IO.File]::ReadAllText($item.FullName).Trim()
    } catch { return '' }
}
function Read-JobsRunnerSdkExactTag {
    param([string]$Sdk)
    if (-not (Test-Path -LiteralPath (Join-Path $Sdk '.git'))) { return '' }
    $git = Find-JobsExecutable 'git.exe' @('git')
    if (-not $git) { return '' }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName=$git
    $start.Arguments=(@('--no-optional-locks','-c','core.fsmonitor=false','-C',$Sdk,'describe','--tags','--exact-match','HEAD')|ForEach-Object{Quote-JobsArgument $_}) -join ' '
    $start.UseShellExecute=$false; $start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
    foreach($key in @('GIT_DIR','GIT_WORK_TREE','GIT_COMMON_DIR','GIT_INDEX_FILE','GIT_OBJECT_DIRECTORY','GIT_ALTERNATE_OBJECT_DIRECTORIES')){$start.EnvironmentVariables.Remove($key)}
    $start.EnvironmentVariables['GIT_NO_LAZY_FETCH']='1'
    $start.EnvironmentVariables['GIT_TERMINAL_PROMPT']='0'
    $process=New-Object Diagnostics.Process; $process.StartInfo=$start; $begun=$false
    try {
        [void]$process.Start(); $begun=$true
        $output=$process.StandardOutput.ReadToEndAsync(); $errors=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit(5000)){return ''}
        if(-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($output,$errors),1000)){return ''}
        $tag=$output.GetAwaiter().GetResult().Trim()
        if($process.ExitCode-eq0-and$tag-cmatch'^v?(\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?)$'){return $Matches[1]}
    }catch{}
    finally{if($begun-and-not$process.HasExited){$process.Kill()};$process.Dispose()}
    return ''
}
function Get-JobsRunnerSdkContext {
    param([string]$Flutter,[string]$Project)
    $declaration = ''; $declarationSource = ''
    foreach ($entry in @(@('.fvmrc','flutter'),@('.fvm/fvm_config.json','flutterSdkVersion'))) {
        $path = Join-Path $Project $entry[0]
        if (-not [IO.File]::Exists($path)) { continue }
        try {
            $config = Read-JobsRunnerSdkMetadata $path | ConvertFrom-Json -ErrorAction Stop
            if ($null -ne $config.PSObject.Properties[$entry[1]]) {
                $value = [string]$config.($entry[1])
                if ($value -cmatch '^[A-Za-z0-9][A-Za-z0-9._/@+-]{0,255}$') { $declaration=$value; $declarationSource=$entry[0] }
            }
        } catch { }
        break
    }
    $sdk = [IO.Path]::GetFullPath((Split-Path -Parent (Split-Path -Parent $Flutter)))
    $selectedSdk = $sdk
    # FVM 的 junction / symlink 解析只用于说明实际 SDK 位置，不改链接。
    for ($index=0; $index -lt 8; $index++) {
        try {
            $item = Get-Item -LiteralPath $sdk -Force -ErrorAction Stop
            if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $null -eq $item.PSObject.Properties['Target']) { break }
            $targets = @($item.Target)
            if ($targets.Count -ne 1 -or -not $targets[0]) { break }
            $next = [string]$targets[0]
            if (-not [IO.Path]::IsPathRooted($next)) { $next = Join-Path (Split-Path -Parent $sdk) $next }
            $next = [IO.Path]::GetFullPath($next)
            if ($next -ceq $sdk) { break }
            $sdk = $next
        } catch { break }
    }
    $engine = Read-JobsRunnerSdkMetadata (Join-Path $sdk 'bin/internal/engine.version')
    $engineSource = 'bin/internal/engine.version'
    if ($env:FLUTTER_PREBUILT_ENGINE_VERSION -cmatch '^[a-fA-F0-9]{40,64}$') { $engine=$env:FLUTTER_PREBUILT_ENGINE_VERSION; $engineSource='FLUTTER_PREBUILT_ENGINE_VERSION' }
    if ($engine -cnotmatch '^[a-fA-F0-9]{40,64}$') { $engine=''; $engineSource='' }
    $metadata = $null
    try { $metadata=Read-JobsRunnerSdkMetadata (Join-Path $sdk 'bin/cache/flutter.version.json') | ConvertFrom-Json -ErrorAction Stop } catch { }
    $versionPattern = '^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$'
    $flutterVersion = Read-JobsRunnerSdkExactTag $sdk
    $flutterSource = if ($flutterVersion) { 'SDK Git HEAD 的 exact tag（只读本地）' } else { '' }
    $metadataEngineMatches = $metadata -and $engine -and $null -ne $metadata.PSObject.Properties['engineRevision'] -and [string]$metadata.engineRevision -ieq $engine
    if (-not $flutterVersion -and $metadataEngineMatches -and $null -ne $metadata.PSObject.Properties['frameworkVersion'] -and [string]$metadata.frameworkVersion -cmatch $versionPattern) {
        $flutterVersion=[string]$metadata.frameworkVersion; $flutterSource='bin/cache/flutter.version.json（engine 一致）'
    }
    $dart = Read-JobsRunnerSdkMetadata (Join-Path $sdk 'bin/internal/dart-sdk.version')
    $dartSource = 'bin/internal/dart-sdk.version'
    if ($dart -cnotmatch $versionPattern) { $dart=''; $dartSource='' }
    if (-not $dart -and $metadataEngineMatches -and $null -ne $metadata.PSObject.Properties['dartSdkVersion']) {
        $candidate = [string]$metadata.dartSdkVersion
        if ($candidate -cmatch '^(\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?)(?:\s|$)') { $dart=$Matches[1]; $dartSource='bin/cache/flutter.version.json（engine 一致）' }
    }
    if (-not $dart -and $engine -and (Read-JobsRunnerSdkMetadata (Join-Path $sdk 'bin/cache/engine-dart-sdk.stamp')) -ieq $engine) {
        $candidate = Read-JobsRunnerSdkMetadata (Join-Path $sdk 'bin/cache/dart-sdk/version')
        if ($candidate -cmatch $versionPattern) { $dart=$candidate; $dartSource='bin/cache/dart-sdk/version（engine stamp 一致）' }
    }
    $architecture = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    if (-not $architecture) { try { $architecture=[Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() } catch { $architecture=if([Environment]::Is64BitOperatingSystem){'64-bit'}else{'32-bit'} } }
    $hostSystem = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'Windows' } else { [Environment]::OSVersion.Platform.ToString() }
    return [pscustomobject]@{DeclaredFlutter=$declaration;DeclaredSource=$declarationSource;FlutterVersion=$flutterVersion;FlutterSource=$flutterSource;SdkPath=$sdk;SelectedSdkPath=$selectedSdk;FlutterPath=$Flutter;DartVersion=$dart;DartSource=$dartSource;Engine=$engine;EngineSource=$engineSource;HostSystem=$hostSystem;Architecture=$architecture}
}
# 只读取官方元数据；总超时与响应上限限制展示探测，不触发SDK下载或修复。
function Invoke-JobsRunnerOfficialMetadata {
    param([string]$Url,[int]$TimeoutSeconds=4)
    if (-not ('Net.Http.HttpClient' -as [type])) { Add-Type -AssemblyName System.Net.Http }
    $client = New-Object Net.Http.HttpClient
    try {
        $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
        $client.MaxResponseContentBufferSize = 8388608
        $task=$client.GetStringAsync($Url)
        if(-not $task.Wait($TimeoutSeconds*1000)){throw '官方元数据查询超时'}
        return $task.GetAwaiter().GetResult()
    } finally { $client.Dispose() }
}
# 按官方stable指针与宿主架构解析发布记录，失败明确未知且不复用历史结果。
function Get-JobsRunnerOfficialSdkContext {
    param([string]$Architecture)
    $source='https://www.googleapis.com/storage/v1/b/flutter_infra_release/o/releases%2Freleases_windows.json?alt=media'
    $result=[ordered]@{Version='';Dart='';Engine='';ReleaseDate='';QueriedAt=[DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss UTC');Source=$source;Status='未知'}
    try {
        $manifest = Invoke-JobsRunnerOfficialMetadata $source 4 | ConvertFrom-Json -ErrorAction Stop
        if (-not $manifest -or $null -eq $manifest.PSObject.Properties['current_release'] -or $null -eq $manifest.current_release.PSObject.Properties['stable'] -or $null -eq $manifest.PSObject.Properties['releases']) { throw '官方清单缺少stable指针' }
        $current=[string]$manifest.current_release.stable
        if ($current -cnotmatch '^[a-fA-F0-9]{40}$') { throw '官方stable指针无效' }
        $arch=if($Architecture -match 'arm64'){'arm64'}else{'x64'}
        $rows=@($manifest.releases | Where-Object {
            if ($null -eq $_.PSObject.Properties['hash'] -or $null -eq $_.PSObject.Properties['channel'] -or $null -eq $_.PSObject.Properties['version']) { return $false }
            $entryArch=if($null -ne $_.PSObject.Properties['dart_sdk_arch']){[string]$_.dart_sdk_arch}else{'x64'}
            $_.hash -ceq $current -and $_.channel -ceq 'stable' -and $_.version -cmatch '^\d+\.\d+\.\d+$' -and $entryArch -ceq $arch
        })
        if ($rows.Count -eq 0) { throw '官方stable没有匹配宿主架构的记录' }
        $row=$rows[0]
        if ($null -eq $row.PSObject.Properties['dart_sdk_version'] -or $row.dart_sdk_version -cnotmatch '^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9._+-]+)?$' -or $null -eq $row.PSObject.Properties['release_date']) { throw '官方stable缺少Dart版本或发布日期' }
        $releaseTime=[DateTimeOffset]::MinValue
        if($row.release_date -is [DateTime]){$releaseTime=[DateTimeOffset]$row.release_date}
        elseif(-not [DateTimeOffset]::TryParse([string]$row.release_date,[ref]$releaseTime)){throw '官方发布日期无效'}
        foreach($entry in $rows){if($entry.version -cne $row.version -or $entry.dart_sdk_version -cne $row.dart_sdk_version){throw '官方stable记录互相冲突'}}
        $result.Version=[string]$row.version;$result.Dart=[string]$row.dart_sdk_version;$result.ReleaseDate=$releaseTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ');$result.Status='ok'
        try {
            $engine=([string](Invoke-JobsRunnerOfficialMetadata ('https://raw.githubusercontent.com/flutter/flutter/'+$current+'/bin/internal/engine.version') 3)).Trim()
            if($engine -cmatch '^[a-fA-F0-9]{40}$'){$result.Engine=$engine}
        } catch { }
    } catch {
        $result.Status='本次官方查询失败、超时或响应无法解析；不以本地缓存冒充最新'
    }
    return [pscustomobject]$result
}
# PATH发现只返回本地元数据，不调用命令入口，也不将shim目录当成SDK。
function Get-JobsRunnerPathSdkContext {
    $pathFlutter=@(Get-Command -Name @('flutter.bat','flutter.exe','flutter') -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
    if($pathFlutter.Count -ne 1){return $null}
    $root=Split-Path -Parent (Split-Path -Parent $pathFlutter[0].Source)
    if(-not [IO.File]::Exists((Join-Path $root 'bin/internal/engine.version')) -and -not [IO.File]::Exists((Join-Path $root 'packages/flutter_tools/pubspec.yaml'))){return $null}
    try{return Get-JobsRunnerSdkContext $pathFlutter[0].Source ([IO.Path]::GetTempPath())}catch{return $null}
}
# 展示官网、本机PATH与项目绑定三方环境，不执行Flutter入口获取版本。
function Write-JobsRunnerSdkContext {
    param($Context,[string[]]$Arguments)
    Write-JobsRunnerMilestone ('━━━━━━━━ SDK下载上下文（官网 / 本机 / 工程 FVM 对照）｜' + ($Arguments -join ' ') + ' ━━━━━━━━') -SdkLog
    $official=Get-JobsRunnerOfficialSdkContext $Context.Architecture
    $officialText=if($official.Version){'Flutter '+$official.Version+' / Dart '+$official.Dart+' / Engine '+$(if($official.Engine){$official.Engine}else{'未知（本次未取得该release的Engine记录）'})}else{'未知（'+$official.Status+'）'}
    Write-JobsSdkRetryMessage ('官网当前最新 stable：'+$officialText)
    Write-JobsSdkRetryMessage ('官网发布日期：'+$(if($official.ReleaseDate){$official.ReleaseDate}else{'未知'})+'；本次查询时间：'+$official.QueriedAt)
    Write-JobsSdkRetryMessage ('官网来源：https://docs.flutter.dev/install/archive / '+$official.Source)
    Write-JobsSdkRetryMessage ('本机系统：'+[Environment]::OSVersion.VersionString+' / '+$Context.Architecture)
    Write-JobsSdkRetryMessage '本机 PATH 工具发现（只读，未运行验收）：'
    foreach($tool in @('git','fvm','java','adb','hdc','node','sdkmanager')){
        $found=@(Get-Command -Name @($tool+'.exe',$tool+'.bat',$tool+'.cmd',$tool) -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
        Write-JobsSdkRetryMessage ('  '+$tool+'：'+$(if($found.Count){$found[0].Source}else{'PATH未发现'}))
    }
    $pathContext=Get-JobsRunnerPathSdkContext
    if($pathContext){
        Write-JobsSdkRetryMessage ('本机 PATH Flutter：'+$(if($pathContext.FlutterVersion){'Flutter '+$pathContext.FlutterVersion+'（'+$pathContext.FlutterSource+'）'}else{'版本未知（只读本地记录，不执行入口）'}))
        Write-JobsSdkRetryMessage ('本机 PATH SDK：'+$pathContext.SdkPath+'；Engine / Dart：'+$(if($pathContext.Engine){$pathContext.Engine}else{'未知'})+' / '+$(if($pathContext.DartVersion){$pathContext.DartVersion}else{'未知'}))
    }else{Write-JobsSdkRetryMessage '本机 PATH Flutter：未解析到SDK（未配置或命中无法静态解析的shim）'}
    if([IO.Directory]::Exists((Join-Path $Context.SdkPath 'packages/flutter_tools/lib/src/ohos')) -or ($Arguments -join ' ') -match 'ohos|harmony'){
        Write-JobsSdkRetryMessage '鸿蒙适配发行线当前最新：未知（独立发行渠道；官网stable属于Flutter主线，不能替代鸿蒙适配版本，也不会自动改绑或升级）'
    }
    $declared = if ($Context.DeclaredFlutter) { $Context.DeclaredFlutter+'（'+$Context.DeclaredSource+'）' } else { '未声明或本地声明未能解析' }
    $local = if ($Context.FlutterVersion) { $Context.FlutterVersion+'（'+$Context.FlutterSource+'）' } else { '未解析；不执行 Flutter 命令探测' }
    $dart = if ($Context.DartVersion) { $Context.DartVersion+'（'+$Context.DartSource+'）' } else { '未解析；缺少与目标 engine 对应的可信版本元数据，下载完成后确认' }
    $engine = if ($Context.Engine) { $Context.Engine+'（'+$Context.EngineSource+'）' } else { '未解析；缺少有效本地 engine 元数据' }
    Write-JobsSdkRetryMessage ('项目声明 Flutter：'+$declared)
    Write-JobsSdkRetryMessage ('SDK 本地 Flutter 版本标识：'+$local)
    Write-JobsSdkRetryMessage ('所选 SDK 位置：'+$Context.SelectedSdkPath)
    Write-JobsSdkRetryMessage ('实际 SDK 路径：'+$Context.SdkPath)
    Write-JobsSdkRetryMessage ('Flutter 入口：'+$Context.FlutterPath)
    Write-JobsSdkRetryMessage ('目标内置 Dart SDK：'+$dart)
    Write-JobsSdkRetryMessage ('目标 engine：'+$engine)
    Write-JobsSdkRetryMessage ('运行平台 / 架构：'+$Context.HostSystem+' / '+$Context.Architecture)
}

# 阶段标题仅在交互控制台标红；落盘与纯文本输出保留原始文字。
function Write-JobsRunnerMilestone {
    param([string]$Text, [switch]$SdkLog)
    $color = (Test-JobsRunnerInteractiveMenu) -and -not (Test-Path Env:NO_COLOR) -and $env:PLAIN_OUTPUT -ne '1' -and $env:TERM -ine 'dumb'
    $previous = [Console]::ForegroundColor
    try {
        if ($color) { [Console]::ForegroundColor = [ConsoleColor]::Red }
        if ($SdkLog) { Write-JobsSdkRetryMessage $Text }
        else { Write-JobsRunnerDisplayText $Text }
    } finally {
        if ($color) { [Console]::ForegroundColor = $previous }
    }
}

function Invoke-JobsRunnerTool {
    param([string]$Flutter, [string[]]$Arguments, [string]$Project, [int]$TimeoutSeconds = 60)
    if ($Flutter -match '["\x00-\x1f]' -or @($Arguments | Where-Object { $_ -cnotmatch '^[A-Za-z0-9._:@/+=-]+$' }).Count -gt 0) {
        throw '工具参数不合法。'
    }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Flutter
    $start.Arguments = @($Arguments | ForEach-Object { Quote-JobsArgument $_ }) -join ' '
    if ([IO.Path]::GetExtension($Flutter) -in @('.bat', '.cmd')) {
        $start.FileName = Join-Path ([Environment]::GetFolderPath('System')) 'cmd.exe'
        $start.EnvironmentVariables['JOBS_FLUTTER_RUNNER_TOOL'] = $Flutter
        $start.Arguments = '/d /v:off /s /c ""%JOBS_FLUTTER_RUNNER_TOOL%" ' + ($Arguments -join ' ') + '"'
    }
    $start.WorkingDirectory = $Project
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $start.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    $start.EnvironmentVariables['FLUTTER_SUPPRESS_ANALYTICS'] = 'true'
    $start.EnvironmentVariables['DART_SUPPRESS_ANALYTICS'] = 'true'
    if ($Arguments -contains '--version' -or ($Arguments.Count -gt 0 -and $Arguments[0] -ceq 'precache')) {
        $context = Get-JobsRunnerSdkContext $Flutter $Project
        Write-JobsRunnerSdkContext $context $Arguments
        $identity = if ($context.DeclaredFlutter) { $context.DeclaredFlutter } elseif ($context.FlutterVersion) { $context.FlutterVersion } else { '版本未解析' }
        $result = Invoke-JobsSdkAcquireProcess $start ([Math]::Max(120,$TimeoutSeconds)) -Label ('Flutter '+$identity+' / Dart SDK 初始化')
    }
    else { $result = Invoke-JobsSdkLiveProcess $start $TimeoutSeconds }
    if ($result.ExitCode -ne 0) { throw ('Flutter 命令失败，退出码 ' + $result.ExitCode + '；请检查上方实时输出。') }
    return $result.StdOut
}

function ConvertFrom-JobsRunnerList {
    param([AllowEmptyString()][string]$Output)
    # 首次 SDK 启动可能在 JSON 前输出准备信息；只接受完整、合法的末尾数组。
    $text = $Output.Trim()
    for ($index = 0; $index -lt $text.Length; $index++) {
        if ($text[$index] -ne '[') { continue }
        try {
            $json = $text.Substring($index) | ConvertFrom-Json -ErrorAction Stop
            if ($null -eq $json) { return }
            foreach ($entry in @($json)) {
                if ($null -eq $entry.PSObject.Properties['id'] -or $entry.id -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.id)) {
                    throw '设备响应缺少有效 id。'
                }
            }
            foreach ($entry in @($json)) { Write-Output $entry }
            return
        } catch { }
    }
    throw 'Flutter 未返回可解析的设备 / 模拟器列表；请先运行 flutter doctor。'
}

function Get-JobsRunnerSupportedDevices {
    param([object[]]$Devices, [string]$Project)
    foreach ($device in $Devices) {
        if ($null -eq $device.PSObject.Properties['targetPlatform']) { continue }
        if ($null -ne $device.PSObject.Properties['isSupported'] -and -not $device.isSupported) { continue }
        $platform = [string]$device.targetPlatform
        if ($platform -eq 'android' -and ((Test-Path -LiteralPath (Join-Path $Project 'android') -PathType Container) -or (Test-Path -LiteralPath (Join-Path $Project '.android') -PathType Container))) { $device }
        elseif ($platform -match '^(?:ohos|openharmony)(?:-|$)' -and (Test-Path -LiteralPath (Join-Path $Project 'ohos') -PathType Container)) { $device }
        elseif ($platform -like 'windows-*' -and (Test-Path -LiteralPath (Join-Path $Project 'windows') -PathType Container)) { $device }
        elseif ($platform -eq 'web-javascript' -and (Test-Path -LiteralPath (Join-Path $Project 'web') -PathType Container)) { $device }
    }
}

function Get-JobsRunnerAndroidEmulator {
    $roots = @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME)
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { $roots += Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
    foreach ($root in $roots) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        $candidate = Join-Path $root 'emulator/emulator.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return Find-JobsExecutable 'emulator.exe'
}

function Read-JobsRunnerInput {
    param([string]$Prompt)
    Write-JobsEnterChoiceText ($Prompt + '：') -NoNewline
    $answer = [Console]::ReadLine()
    if ($null -eq $answer) { throw '输入已结束，停止操作。' }
    return $answer
}

function Test-JobsRunnerInteractiveMenu {
    return ([Environment]::UserInteractive -and $Host.Name -ceq 'ConsoleHost' -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected)
}
# 保留运行器原有交互协议，选择界面只返回明确操作和目标。
function Select-JobsRunnerChoice {
    param([string]$Title, [string[]]$Items, [switch]$Back)
    if ($Items.Count -eq 0) { throw ('没有可选择的项目：' + $Title) }
    if (-not (Test-JobsRunnerInteractiveMenu)) { throw '设备选择需要交互终端或显式目标参数；未读取输入、安装依赖或启动业务。' }
    foreach ($key in [Environment]::GetEnvironmentVariables().Keys) { if ([string]$key -match '^(?i:SOURCE_?TREE)') { throw 'Sourcetree 动作不能读取设备菜单；请传入明确目标。' } }
    if ($env:JOBS_FLUTTER_RUNNER_FZF -ceq '0') { return Select-JobsRunnerTextChoice $Title $Items -Back:$Back }
    $choices = @()
    for ($index = 0; $index -lt $Items.Count; $index++) {
        $choice = [pscustomobject]@{ Index = $index; Label = $Items[$index] }
        $choice | Add-Member -MemberType ScriptMethod -Name ToString -Value { return $this.Label } -Force
        $choices += $choice
    }
    $selection = Select-JobsFzfItems -Title $Title -Items $choices -Child:$Back
    if ($selection.Action -ceq 'back') { return [pscustomobject]@{ Kind = 'Back'; Index = -1 } }
    if ($selection.Action -cne 'selected') { return $null }
    if ($selection.Items.Count -ne 1 -or $null -eq $selection.Items[0].PSObject.Properties['Index']) { throw '选择器未返回本轮有效目标。' }
    $selected = $selection.Items[0]
    $index = [int]$selected.Index
    if ($index -lt 0 -or $index -ge $choices.Count -or -not [object]::ReferenceEquals($selected, $choices[$index])) { throw '选择结果不属于本轮设备清单。' }
    return [pscustomobject]@{ Kind = 'Selected'; Index = $index }
}

function Get-JobsRunnerAvds {
    param([string]$Emulator, [string]$Project)
    foreach ($line in ((Invoke-JobsRunnerTool $Emulator @('-list-avds') $Project) -split '\r?\n')) {
        if ($line -cmatch '^[a-zA-Z0-9_.-]+$') { $line }
    }
}

function New-JobsRunnerAndroidAvd {
    param([string]$Sdk, [string]$Project, [string[]]$Existing)
    Write-JobsRunnerDisplayText ('Android SDK：' + $Sdk + [Environment]::NewLine + '初始化会复用健康工具；缺失 / 损坏时从 Google 官方源补齐 Command-Line Tools、Emulator / ADB，并按需从 Adoptium 下载 Java 21。系统镜像可能数 GB。' + [Environment]::NewLine + '只影响选定 SDK、用户 Java / AVD 目录；不修改全局 PATH、代理或系统虚拟化设置。') -ForegroundColor Yellow
    if ((Read-JobsRunnerInput '回车准备初始化工具；非空取消').Length -gt 0) { return $null }
    $abi = Get-JobsAndroidArchitecture
    [void][IO.Directory]::CreateDirectory($Sdk)
    $java = Get-JobsAndroidJava
    $oldJava = $env:JAVA_HOME
    try {
        $env:JAVA_HOME = Split-Path -Parent (Split-Path -Parent $java)
        $tools = Get-JobsAndroidHealthyTools -Sdk $Sdk -Java $java
        Repair-JobsAndroidComponents -Sdk $Sdk -Java $java -Tools $tools
        # Emulator 缺失时首次无法枚举；工具补齐后再次检查，避免重复创建已有 AVD。
        if ($Existing.Count -eq 0) {
            $Existing = @(Get-JobsRunnerAvds (Join-Path $Sdk 'emulator/emulator.exe') $Project | Where-Object { $_ -cmatch '^[a-zA-Z0-9_.-]+$' })
            if ($Existing.Count -gt 0) {
                $existingChoice = Select-JobsRunnerChoice '工具已就绪，选择 Android AVD' ($Existing + @('创建新的 Android 模拟器')) -Back
                if ($null -eq $existingChoice -or $existingChoice.Kind -eq 'Back') { return $null }
                if ($existingChoice.Index -lt $Existing.Count) { return $Existing[$existingChoice.Index] }
            }
        }
        $devices = @(Get-JobsAndroidDevices (Invoke-JobsAndroidTool $java $tools 'avdmanager' @('list', 'device')))
        $installed = @(Get-JobsAndroidImages (Invoke-JobsAndroidTool $java $tools 'sdkmanager' @(('--sdk_root=' + $Sdk), '--list_installed')) $abi)
        $images = $installed
        if ($images.Count -eq 0) {
            Write-JobsRunnerDisplayText '尚无当前宿主可用系统镜像，查询 Google 官方稳定镜像清单：https://dl.google.com/android/repository/'
            $images = @(Get-JobsAndroidImages (Invoke-JobsAndroidTool $java $tools 'sdkmanager' @(('--sdk_root=' + $Sdk), '--list', '--channel=0')) $abi)
        }
        while ($true) {
            $deviceChoice = Select-JobsRunnerChoice '选择 Android 设备型号' $devices -Back
            if ($null -eq $deviceChoice -or $deviceChoice.Kind -eq 'Back') { return $null }
            $device = $devices[$deviceChoice.Index]
            $imageChoice = Select-JobsRunnerChoice '选择 Android 系统镜像' $images -Back
            if ($null -eq $imageChoice) { return $null }
            if ($imageChoice.Kind -eq 'Back') { continue }
            $image = $images[$imageChoice.Index]
            $avdHome = Get-JobsAndroidAvdHome
            $name = New-JobsAndroidAvdName $device $image $Existing $avdHome
            Write-JobsRunnerDisplayText ('创建：' + $name + [Environment]::NewLine + '型号：' + $device + [Environment]::NewLine + '系统镜像：' + $image + [Environment]::NewLine + 'AVD 目标：' + $avdHome)
            if ($image -notin $installed) { Write-JobsRunnerDisplayText ('将从 Google 官方 SDK 源下载选定镜像到 ' + $Sdk + '，可能数 GB；许可证由本人确认。') -ForegroundColor Yellow }
            if ((Read-JobsRunnerInput '回车创建并启动；非空取消').Length -gt 0) { return $null }
            if ($image -notin $installed) {
                Invoke-JobsAndroidTool $java $tools 'sdkmanager' @(('--sdk_root=' + $Sdk), '--licenses') -Interactive
                Invoke-JobsAndroidTool $java $tools 'sdkmanager' @(('--sdk_root=' + $Sdk), '--install', $image) -Interactive
                $verified = @(Get-JobsAndroidImages (Invoke-JobsAndroidTool $java $tools 'sdkmanager' @(('--sdk_root=' + $Sdk), '--list_installed')) $abi)
                if ($image -notin $verified) { throw '镜像安装后复检失败，未创建 AVD。' }
            }
            # 不使用 --force；同名或创建失败时停止，绝不覆盖已有 AVD。
            [void](Invoke-JobsAndroidTool $java $tools 'avdmanager' @('create', 'avd', '--name', $name, '--package', $image, '--device', $device) -InputText "no`n")
            $created = @(Get-JobsRunnerAvds (Join-Path $Sdk 'emulator/emulator.exe') $Project)
            if ($name -notin $created) { throw ('创建后未找到 AVD，保留现场并停止：' + $name) }
            Write-JobsLog ('Created Android AVD ' + $name)
            return $name
        }
    } finally { $env:JAVA_HOME = $oldJava }
}

function Start-JobsRunnerAndroid {
    param([string]$Flutter, [string]$Project)
    $sdk = Get-JobsAndroidSdk
    if (-not $env:ANDROID_HOME -and -not $env:ANDROID_SDK_ROOT) {
        $configured = Get-JobsRunnerAndroidEmulator
        if ($configured) { $sdk = Split-Path -Parent (Split-Path -Parent $configured) }
    }
    $oldHome = $env:ANDROID_HOME
    $oldRoot = $env:ANDROID_SDK_ROOT
    try {
        $env:ANDROID_HOME = $sdk
        $env:ANDROID_SDK_ROOT = $sdk
        $emulator = Join-Path $sdk 'emulator/emulator.exe'
        $existing = @()
        if (Test-Path -LiteralPath $emulator -PathType Leaf) { $existing = @(Get-JobsRunnerAvds $emulator $Project) }
        $name = $null
        if ($existing.Count -gt 0) {
            $choice = Select-JobsRunnerChoice '选择 Android AVD' ($existing + @('创建新的 Android 模拟器')) -Back
            if ($null -eq $choice -or $choice.Kind -eq 'Back') { return $null }
            if ($choice.Index -lt $existing.Count) { $name = $existing[$choice.Index] }
            else { $name = New-JobsRunnerAndroidAvd $sdk $Project $existing }
        } else {
            Write-JobsRunnerDisplayText '尚无 Android AVD，进入内置初始化流程。'
            $name = New-JobsRunnerAndroidAvd $sdk $Project $existing
        }
        if ($null -eq $name) { return $null }
        $serial = Start-JobsAndroidAvd $sdk $name
        $device = Wait-JobsRunnerAndroidDevice $Flutter $Project $serial
        $script:RunnerSelectedSdk = $sdk
        return $device
    } finally { $env:ANDROID_HOME = $oldHome; $env:ANDROID_SDK_ROOT = $oldRoot }
}

function Wait-JobsRunnerAndroidDevice {
    param([string]$Flutter, [string]$Project, [string]$Serial)
    for ($attempt = 0; $attempt -lt 6; $attempt++) {
        try {
            $devices = @(ConvertFrom-JobsRunnerList (Invoke-JobsRunnerTool $Flutter @('devices', '--machine') $Project 30))
            $selected = @(Get-JobsRunnerSupportedDevices $devices $Project | Where-Object { $_.id -ceq $Serial })
            if ($selected.Count -eq 1) { return [string]$selected[0].id }
        } catch { Write-JobsRunnerDisplayText ('Flutter 设备查询暂未就绪：' + $_.Exception.Message) -ForegroundColor Yellow }
        Write-JobsRunnerDisplayText ('Flutter 尚未发现所选 AVD（' + $Serial + '），正在重新加载……')
        if ($attempt -lt 5) { Start-Sleep -Seconds 2 }
    }
    throw ('AVD 已启动，但 Flutter 尚未识别 ' + $Serial + '。设备已保留，请检查 flutter doctor 后重新加载。')
}

# 固定使用系统 Windows PowerShell，避免复用 ISE 等不能承接 -File 的宿主。
function Get-JobsRunnerCreatorPowerShell {
    $powershell = Join-Path ([Environment]::GetFolderPath('System')) 'WindowsPowerShell/v1.0/powershell.exe'
    if (-not (Test-Path -LiteralPath $powershell -PathType Leaf)) { throw '缺少 Windows PowerShell，无法调用模拟器创建入口。' }
    return $powershell
}
# 等待创建器返回的精确设备进入 Flutter；其它设备不能替代本次目标。
function Wait-JobsRunnerSelectedDevice {
    param([string]$Flutter, [string]$Project, $Target, [int]$TimeoutSeconds = 180)
    $supported = if ($Target.Platform -ceq 'Android') {
        (Test-Path -LiteralPath (Join-Path $Project 'android') -PathType Container) -or (Test-Path -LiteralPath (Join-Path $Project '.android') -PathType Container)
    } else { Test-Path -LiteralPath (Join-Path $Project 'ohos') -PathType Container }
    if (-not $supported) {
        Write-JobsRunnerDisplayText ('模拟器已保留；当前工程没有 ' + $Target.Platform + ' 平台目录，未运行应用。') -ForegroundColor Yellow
        return $null
    }
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $devices = @()
        try { $devices = @(Get-JobsRunnerSupportedDevices @(ConvertFrom-JobsRunnerList (Invoke-JobsRunnerTool $Flutter @('devices', '--machine') $Project 15)) $Project) }
        catch [Management.Automation.PipelineStoppedException] { throw }
        catch { Write-JobsRunnerDisplayText ('设备发现尚未就绪：' + $_.Exception.Message) -ForegroundColor Yellow }
        $matches = @($devices | Where-Object { $_.id -ceq $Target.Id -and (($Target.Platform -ceq 'Android' -and $_.targetPlatform -ceq 'android') -or ($Target.Platform -ceq 'Harmony' -and $_.targetPlatform -match '^(?:ohos|openharmony)(?:-|$)')) })
        if ($matches.Count -gt 1) { throw 'Flutter 返回重复目标 ID；保留模拟器，未运行应用。' }
        if ($matches.Count -eq 1) {
            $script:RunnerSelectedPlatform = [string]$matches[0].targetPlatform
            Write-JobsRunnerDisplayText ('设备已就绪，继续运行当前工程：' + $Target.Id) -ForegroundColor Green
            return [string]$matches[0].id
        }
        if ([DateTime]::UtcNow -ge $deadline) { break }
        Write-JobsRunnerDisplayText ('等待 Flutter 识别本次模拟器：' + $Target.Id + '；Ctrl+C 取消等待。')
        Start-Sleep -Seconds 2
    } while ([DateTime]::UtcNow -lt $deadline)
    throw ('等待 Flutter 识别目标超时：' + $Target.Id + '；模拟器已保留，未运行其它设备。请检查 flutter doctor 后重试。')
}
# 调用随包创建器；结果文件仅由成功创建并启动的子进程写入。
function New-JobsRunnerSimulator {
    param([ValidateSet('Android', 'Harmony')][string]$Platform)
    $creator = Join-Path $PSScriptRoot ('SimulatorCreators/' + $Platform + '/Scripts/Create' + $Platform + 'Simulator.ps1')
    if (-not (Test-Path -LiteralPath $creator -PathType Leaf)) { throw ('随包模拟器创建入口缺失，请更新本功能：' + $creator) }
    $powershell = Get-JobsRunnerCreatorPowerShell
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $creator)
    if ($Platform -ceq 'Android') { $arguments += '-Create' }
    $directory = Join-Path ([IO.Path]::GetTempPath()) ('JobsCreatedDevice-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($directory)
    $receipt = Join-Path $directory 'device.tsv'
    $hadReceipt = Test-Path Env:JOBS_FLUTTER_CREATED_DEVICE_FILE
    $savedReceipt = $env:JOBS_FLUTTER_CREATED_DEVICE_FILE
    try {
        $env:JOBS_FLUTTER_CREATED_DEVICE_FILE = $receipt
        & $powershell @arguments 2>&1 | ForEach-Object { Write-JobsRunnerDisplayText $_ }
        if ($LASTEXITCODE -ne 0) {
            Write-JobsRunnerDisplayText ('创建流程已取消或失败（退出码 ' + $LASTEXITCODE + '）；保留设备与日志，未运行应用。') -ForegroundColor Yellow
            return $null
        }
        if (-not [IO.File]::Exists($receipt)) {
            Write-JobsRunnerDisplayText '创建流程未返回已启动目标（可能取消或跳过启动）；未运行应用。' -ForegroundColor Yellow
            return $null
        }
        $text = [IO.File]::ReadAllText($receipt)
        if ($text -cnotmatch '^(Android|Harmony)\t([^\x00-\x20]+)\r?\n?$' -or $Matches[1] -cne $Platform) { throw '创建器结果无效或平台不匹配；未运行应用。' }
        $id = $Matches[2]
        if (($Platform -ceq 'Android' -and $id -cnotmatch '^emulator-[0-9]+$') -or ($Platform -ceq 'Harmony' -and $id -cnotmatch '^127\.0\.0\.1:[0-9]+$')) { throw '创建器未返回可靠设备 ID；未运行应用。' }
        return [pscustomobject]@{ Platform = $Platform; Id = $id }
    } finally {
        if ($hadReceipt) { $env:JOBS_FLUTTER_CREATED_DEVICE_FILE = $savedReceipt }
        else { Remove-Item Env:JOBS_FLUTTER_CREATED_DEVICE_FILE -ErrorAction SilentlyContinue }
        if ([IO.File]::Exists($receipt)) { [IO.File]::Delete($receipt) }
        [IO.Directory]::Delete($directory)
    }
}
# 根据 Flutter 标记和稳定设备 ID 排除模拟器；桌面与 Web 单独展示。
function Test-JobsRunnerPhysicalDevice {
    param($Device)
    if ($null -ne $Device.PSObject.Properties['emulator'] -and [bool]$Device.emulator) { return $false }
    if ($null -ne $Device.PSObject.Properties['isEmulator'] -and [bool]$Device.isEmulator) { return $false }
    return ([string]$Device.targetPlatform -match '^(?:android|ohos|openharmony)(?:-|$)' -and [string]$Device.id -notmatch '^(?:emulator-|127\.0\.0\.1:|localhost:|\[?::1\]?:)')
}
# 创建成功后只等待本轮精确目标，沿用取消、平台门禁及实例保全。
function New-JobsRunnerReadySimulator {
    param([ValidateSet('Android','Harmony')][string]$Platform, [string]$Flutter, [string]$Project, [string]$Sdk)
    $target = New-JobsRunnerSimulator $Platform
    if ($null -eq $target) { return [pscustomobject]@{ Kind='Back' } }
    $id = Wait-JobsRunnerSelectedDevice $Flutter $Project $target
    if ($null -eq $id) { return [pscustomobject]@{ Kind='Back' } }
    return [pscustomobject]@{ Kind='Ready'; Id=$id; Platform=$script:RunnerSelectedPlatform; Sdk=$Sdk; Environment=(Get-JobsRunnerVirtualEnvironment) }
}
# 根层区分真实、虚拟及桌面/Web；虚拟设备在各系统清单中复用或新建。
function Select-JobsRunnerDevice {
    param([string]$Flutter, [string]$Project)
    $script:RunnerSelectedSdk = $null
    $script:RunnerSelectedPlatform = $null
    $script:RunnerPreparedHarmony = $null
    $layer = 'Root'
    while ($true) {
        Write-JobsRunnerDisplayText '正在读取 Flutter 运行设备……'
        $devices = @()
        try { $devices = @(Get-JobsRunnerSupportedDevices @(ConvertFrom-JobsRunnerList (Invoke-JobsRunnerTool $Flutter @('devices', '--machine') $Project)) $Project) }
        catch [Management.Automation.PipelineStoppedException] { throw }
        catch [OperationCanceledException] { throw }
        catch { Write-JobsRunnerDisplayText ('设备查询暂不可用，可重新加载或选择虚拟设备：' + $_.Exception.Message) -ForegroundColor Yellow }
        if ($layer -ceq 'Root') {
            $selection = Select-JobsRunnerChoice '选择 Flutter 运行设备' @('目前已有的真实设备', '虚拟设备', '其他运行目标（桌面 / Web）', '重新加载设备列表')
            if ($null -eq $selection) { return $null }
            if ($selection.Index -eq 0) { $layer = 'Existing' }
            elseif ($selection.Index -eq 1) { $layer = 'Virtual' }
            elseif ($selection.Index -eq 2) { $layer = 'Other' }
            else { continue }
        }
        $choices = @()
        if ($layer -in @('Existing','Other')) {
            foreach ($device in $devices) {
                $included = if ($layer -ceq 'Existing') { Test-JobsRunnerPhysicalDevice $device } else { [string]$device.targetPlatform -match '^(?:windows-|web-javascript$)' }
                if ($included) { $choices += [pscustomobject]@{ Kind = 'Device'; Id = [string]$device.id; Platform = [string]$device.targetPlatform; Name = $(if ([string]::IsNullOrWhiteSpace([string]$device.name) -or [string]$device.name -ceq [string]$device.id) { '未命名设备' } else { [string]$device.name }) } }
            }
            if ($layer -ceq 'Existing') {
                $choices += @(Get-JobsRunnerHarmonyDiagnostics $devices $Project $script:RunnerPreflight | Where-Object { [string]$_.Id -notmatch '^(?:127\.0\.0\.1:|localhost:|\[?::1\]?:)' })
                $title = '目前已有的真实设备'
            } else { $title = '其他运行目标（桌面 / Web）' }
            if ($choices.Count -eq 0) { Write-JobsRunnerDisplayText '暂无可用目标，可重新加载设备列表或按 ← 返回。' -ForegroundColor Yellow }
            $choices += [pscustomobject]@{ Kind = 'Reload'; Name = '重新加载设备列表' }
        } else {
            $choices += [pscustomobject]@{ Kind='Virtual'; Platform='Android'; Name='Android 虚拟设备' }
            $choices += [pscustomobject]@{ Kind='Virtual'; Platform='Harmony'; Name='Harmony 虚拟设备' }
            $title = '虚拟设备'
        }
        $selection = Select-JobsRunnerChoice $title @($choices | ForEach-Object { $_.Name }) -Back
        if ($null -eq $selection) { return $null }
        if ($selection.Kind -eq 'Back') { $layer = 'Root'; continue }
        $selected = $choices[$selection.Index]
        switch ($selected.Kind) {
            'Device' {
                if($selected.Platform-match'^(ohos|openharmony)(?:-|$)'-and($null-eq$script:RunnerPreflight-or-not$script:RunnerPreflight.ContainsKey('ohos')-or$script:RunnerPreflight.ohos.State-cne'ready')){
                    return Start-JobsRunnerHarmonyPreparation $Flutter $Project $selected.Id
                }
                $script:RunnerSelectedPlatform = $selected.Platform
                return $selected.Id
            }
            'HarmonyDiagnostic' {
                Write-JobsRunnerDisplayText ('所选鸿蒙设备：'+$selected.Name)
                return Start-JobsRunnerHarmonyPreparation $Flutter $Project $selected.Id
            }
            'Reload' { continue }
            'Virtual' {
                $target = if ($selected.Platform -ceq 'Android') { Start-JobsRunnerExistingAndroid $Flutter $Project -AllowCreate } else { Start-JobsRunnerExistingHarmony $Flutter $Project -AllowCreate }
                if ($null -eq $target) { return $null }
                if ($target.Kind -ceq 'Ready') {
                    Set-JobsRunnerTaskEnvironment $target.Environment
                    if ($selected.Platform -ceq 'Android') { $script:RunnerSelectedSdk=$target.Sdk }
                    $script:RunnerSelectedPlatform=$target.Platform
                    return $target.Id
                }
                $layer = 'Virtual'
            }
        }
    }
}

function Resolve-JobsRunnerTarget {
    param([string]$Target)
    $resolved = Resolve-JobsTarget $Target
    if ([IO.Directory]::Exists($resolved)) {
        Assert-JobsFlutterProject $resolved
        return [pscustomobject]@{ Project = $resolved; Entry = '' }
    }
    Assert-JobsRunnerPlainFile $resolved
    if ([IO.Path]::GetExtension($resolved) -ine '.dart') { throw '请选择 Flutter 工程根目录或含 main() 的 .dart 文件。' }
    $directory = [IO.DirectoryInfo](Split-Path -Parent $resolved)
    [void](Assert-JobsRunnerDirectory $directory.FullName)
    while ($null -ne $directory) {
        $pubspec = Join-Path $directory.FullName 'pubspec.yaml'
        if (Test-JobsRunnerPathEntry $pubspec) {
            # 第一个 pubspec 就是包边界；无效或非 Flutter 时不能借外层工程运行。
            Assert-JobsFlutterProject $directory.FullName
            $lines = New-Object Collections.Generic.List[string]
            $inComment = $false
            foreach ($line in [IO.File]::ReadAllLines($resolved)) {
                $text = $line.TrimStart()
                if ($inComment) {
                    $end = $text.IndexOf('*/')
                    if ($end -lt 0) { continue }
                    $text = $text.Substring($end + 2).TrimStart()
                    $inComment = $false
                }
                while ($text.StartsWith('/*')) {
                    $end = $text.IndexOf('*/', 2)
                    if ($end -lt 0) { $inComment = $true; break }
                    $text = $text.Substring($end + 2).TrimStart()
                }
                if ($inComment -or $text.StartsWith('//')) { continue }
                $lines.Add($text)
            }
            # 只做轻量入口预检，完整 Dart 语法与入口签名仍由 Flutter 编译器判断。
            $source = $lines -join "`n"
            if ($source -match '(?m)^\s*part\s+of\b' -or $source -notmatch '(?m)^\s*(?:(?:void|Future\s*<\s*void\s*>)\s+)?main\s*\(') {
                throw ('此文件没有独立 main() 入口，请选择 Demo 实现文件：' + $resolved)
            }
            return [pscustomobject]@{ Project = $directory.FullName; Entry = $resolved }
        }
        $directory = $directory.Parent
    }
    throw ('找不到此 Dart 文件所属的 Flutter pubspec.yaml：' + $resolved)
}

function Get-JobsRunnerProjectRoot {
    param([string]$Project, [string]$Entry = '')
    $identity = $Project.ToUpperInvariant()
    if (-not [string]::IsNullOrEmpty($Entry)) { $identity += "`n" + $Entry.ToUpperInvariant() }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($identity))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
    return Join-Path (Join-Path (Get-JobsInstallRoot) 'runs') $hash
}

function Get-JobsRunnerSession {
    param([string]$ProjectRoot)
    if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) { return $null }
    foreach ($directory in @(Get-ChildItem -LiteralPath $ProjectRoot -Directory | Sort-Object Name -Descending)) {
        $file = Join-Path $directory.FullName 'state.json'
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        try {
            $state = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($state.Status -notin @('Starting', 'Running')) { continue }
            $process = Get-Process -Id $state.WorkerPid -ErrorAction Stop
            $start = $process.StartTime.ToUniversalTime().Ticks
            if ($start -ne ([DateTime]$state.WorkerStartUtc).ToUniversalTime().Ticks) { continue }
            return $state
        } catch { }
    }
    return $null
}

function Send-JobsRunnerControl {
    param([string]$Session, [ValidateSet('reload', 'restart', 'stop')][string]$Command)
    $name = 'control-' + [guid]::NewGuid().ToString('N')
    $temporary = Join-Path $Session ($name + '.tmp')
    $path = Join-Path $Session ($name + '.json')
    [IO.File]::WriteAllText($temporary, (@{ Command = $Command } | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))
    [IO.File]::Move($temporary, $path)
}

function Show-JobsRunnerLog {
    param([string]$Session, [string]$EnvironmentRoot = '')
    if ([string]::IsNullOrEmpty($EnvironmentRoot)) { $EnvironmentRoot = Split-Path -Parent $Session }
    $path = Join-Path $Session 'run.log'
    Write-JobsRunnerDisplayText ('日志：' + $path) -ForegroundColor Cyan
    Write-JobsRunnerDisplayText 'r 热重载；R 热重启；s 停止；e 停止后台环境准备；q 退出日志。直接关闭 CMD 也会保留后台运行。' -ForegroundColor Green
    $reader = $null
    try {
        while ($null -eq $reader) {
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                $stream = New-Object IO.FileStream($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
                $reader = New-Object IO.StreamReader($stream, (New-Object Text.UTF8Encoding($false)))
            } else { Start-Sleep -Milliseconds 100 }
        }
        while ($true) {
            $text = $reader.ReadToEnd()
            if ($text.Length -gt 0) { Write-JobsRunnerDisplayText -NoNewline $text }
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true).KeyChar
                switch -CaseSensitive ($key) {
                    'r' { Send-JobsRunnerControl $Session reload }
                    'R' { Send-JobsRunnerControl $Session restart }
                    's' { Send-JobsRunnerControl $Session stop; Write-JobsRunnerDisplayText '已请求停止；最多等待 10 秒后停止本次 Flutter 进程树。' }
                    'e' { Stop-JobsRunnerEnvironmentPreparations $EnvironmentRoot }
                    'q' { return }
                }
            }
            $statePath = Join-Path $Session 'state.json'
            try {
                $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($state.Status -in @('Stopped', 'Failed')) { Write-JobsRunnerDisplayText -NoNewline $reader.ReadToEnd(); return }
                $running = Get-Process -Id $state.WorkerPid -ErrorAction Stop
                if ($running.StartTime.ToUniversalTime().Ticks -ne ([DateTime]$state.WorkerStartUtc).ToUniversalTime().Ticks) { throw '进程已退出。' }
            } catch { Write-JobsRunnerDisplayText '后台状态不可用，请重新右键检查日志。' -ForegroundColor Yellow; return }
            Start-Sleep -Milliseconds 150
        }
    } finally { if ($reader) { $reader.Dispose() } }
}

function Start-JobsRunnerSession {
    param([string]$Project, [string]$Flutter, [string]$Device, [string]$ProjectRoot, [string]$Entry = '')
    $session = Join-Path $ProjectRoot ((Get-Date -Format 'yyyy.MM.dd HH-mm-ss') + '-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($session)
    $request = Join-Path $session 'request.json'
    [IO.File]::WriteAllText($request, (@{ Project = $Project; Flutter = $Flutter; Device = $Device; Target = $Entry } | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    $hostPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'bin/JobsFlutterRunnerHost.exe'
    if (-not (Test-Path -LiteralPath $hostPath -PathType Leaf)) { throw '后台宿主缺失，请重新安装本包。' }
    [void](Invoke-JobsProcess $hostPath @('start', $request) -WorkingDirectory $Project)
    $clock = [Diagnostics.Stopwatch]::StartNew()
    while ($clock.Elapsed.TotalSeconds -lt 15) {
        $failure = Join-Path $session 'startup-error.log'
        if (Test-Path -LiteralPath $failure -PathType Leaf) { throw ('后台启动失败，详见：' + $failure) }
        if (Test-Path -LiteralPath (Join-Path $session 'state.json') -PathType Leaf) { return $session }
        Start-Sleep -Milliseconds 100
    }
    throw ('后台未按时返回状态，请查看：' + $session)
}

# 设备枚举本身也需要通用制品；先准备，避免短发现超时反复打断首次下载。
function Initialize-JobsRunnerDiscoverySdk {
    param([string]$Flutter,[string]$Project)
    Write-JobsRunnerDisplayText '正在准备 Flutter 设备发现所需的通用 SDK 资源；失败自动重试，Ctrl+C 停止。'
    [void](Invoke-JobsRunnerTool $Flutter @('precache','--universal') $Project 1800)
}

# 在启动业务前补齐当前目标的引擎制品，不通过重放 flutter run 补环境。
function Initialize-JobsRunnerPlatformSdk {
    param([string]$Flutter,[string]$Project,[string]$Platform)
    $target = if ($Platform -ceq 'android') { 'android' } elseif ($Platform -like 'windows-*') { 'windows' } elseif ($Platform -ceq 'web-javascript') { 'web' } elseif ($Platform -match '^(?:ohos|openharmony)(?:-|$)') { 'ohos' } else { throw ('无法确定所选设备的平台缓存：' + $Platform) }
    if ($target -ceq 'ohos') {
        $help = Invoke-JobsRunnerTool $Flutter @('precache', '--help') $Project 30
        if ($help -notmatch '--(?:\[no-\])?ohos\b') { throw '当前 Flutter SDK 不支持 precache --ohos，请先绑定鸿蒙适配 SDK。' }
    }
    [void](Invoke-JobsRunnerTool $Flutter @('precache',('--'+$target)) $Project 120)
}

function Invoke-JobsFlutterRunAction {
    param([string]$Target)
    $runTarget = Resolve-JobsRunnerTarget $Target
    $Target = $runTarget.Project
    $entry = $runTarget.Entry
    if ($Target.StartsWith('\\')) { throw '本菜单只处理本机项目目录，不处理 UNC 共享。' }
    Write-JobsRunnerMilestone 'Jobs · 从终端运行 Flutter 项目（CMD）'
    Write-JobsRunnerDisplayText ('来源：' + $PSScriptRoot) -ForegroundColor Cyan
    Write-JobsRunnerDisplayText ('项目：' + $Target)
    if ($entry) { Write-JobsRunnerDisplayText ('Demo：' + $entry) }
    Write-JobsRunnerDisplayText '先展示 iOS / Android / 鸿蒙环境体检，仅所选平台全部通过才启动 flutter run --machine。'
    Write-JobsRunnerDisplayText '设备分为真实设备、虚拟设备及桌面 / Web；虚拟设备先选 Android / Harmony，再选择已有实例或清单末尾的新建入口，目标就绪后自动运行当前工程。'
    Write-JobsRunnerDisplayText '设备选择使用 fzf，上下键及输入筛选，← 返回上一层，Esc 取消。'
    Write-JobsRunnerDisplayText '关闭 CMD 不停止项目；重新右键可重连日志，r / R 热重载 / 热重启，s 停止，e 停止本工程后台环境准备。'
    $projectRoot = Get-JobsRunnerProjectRoot $Target $entry
    $environmentRoot = Get-JobsRunnerProjectRoot $Target
    $existing = Get-JobsRunnerSession $projectRoot
    if ($existing) { Show-JobsRunnerLog $existing.Session $environmentRoot; return }
    $flutter = Get-JobsRunnerFlutter $Target
    $health = Invoke-JobsRunnerTool $flutter @('--version', '--machine') $Target
    Write-JobsRunnerDisplayText ('Flutter：' + $flutter)
    try { $version = ConvertFrom-JobsSdkMachineOutput $health; Write-JobsRunnerDisplayText ('版本：' + $version.frameworkVersion) } catch { throw 'Flutter SDK 体检失败，请先运行 flutter doctor。' }
    Reset-JobsRunnerPreflightDisplay
    Initialize-JobsRunnerDiscoverySdk $flutter $Target
    $preflight = Get-JobsRunnerPreflight $flutter $Target
    $script:RunnerPreflight = $preflight
    Write-JobsRunnerPreflight $preflight $flutter $Target
    $preflight = Repair-JobsRunnerCommonDependencies $flutter $Target $preflight
    $script:RunnerPreflight = $preflight
    $taskEnvironment=Get-JobsRunnerTaskEnvironment
    try {
        $device = Select-JobsRunnerDevice $flutter $Target
        if ($null -eq $device) { return }
        if($script:RunnerPreparedHarmony){$flutter=$script:RunnerPreparedHarmony.Flutter}
        $oldHome = $env:ANDROID_HOME
        $oldRoot = $env:ANDROID_SDK_ROOT
        try {
            # 后台宿主必须继承本次所选 AVD 的 SDK，避免旧环境冲突或 PATH SDK 丢失。
            if ($script:RunnerSelectedSdk) { $env:ANDROID_HOME = $script:RunnerSelectedSdk; $env:ANDROID_SDK_ROOT = $script:RunnerSelectedSdk }
            # 选择或新建期间环境可能变化；使用最终目标和 SDK 重查，失败不进入运行宿主。
            $preflight = Get-JobsRunnerPreflight $flutter $Target
            $flutter = Repair-JobsRunnerRequiredEnvironment $flutter $Target $script:RunnerSelectedPlatform $preflight
            $preflight = Get-JobsRunnerPreflight $flutter $Target
            Write-JobsRunnerPreflight $preflight $flutter $Target
            Assert-JobsRunnerPreflight $preflight $script:RunnerSelectedPlatform
            Request-JobsRunnerOtherEnvironmentPreparation $flutter $Target $script:RunnerSelectedPlatform $preflight
            Initialize-JobsRunnerPlatformSdk $flutter $Target $script:RunnerSelectedPlatform
            Write-JobsRunnerMilestone '━━━━━━━━━━ Flutter 构建与运行 ━━━━━━━━━━'
            $session = Start-JobsRunnerSession $Target $flutter $device $projectRoot $entry
            Show-JobsRunnerLog $session $environmentRoot
        } finally { $env:ANDROID_HOME = $oldHome; $env:ANDROID_SDK_ROOT = $oldRoot }
    } finally { Restore-JobsRunnerTaskEnvironment $taskEnvironment }
}

function Invoke-JobsFeature {
    param([string]$Target)
    $display = Start-JobsRunnerConsoleDisplay
    try { Invoke-JobsFlutterRunAction -Target (Resolve-JobsTarget $Target) }
    finally { Restore-JobsRunnerConsoleDisplay $display }
}

Export-ModuleMember -Function Invoke-JobsFeature


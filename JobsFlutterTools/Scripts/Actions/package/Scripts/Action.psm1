# Action.psm1 | JobsFlutterPackager
# Created by Jobs on 2026年10月20日，星期二.
# CMD 内用 fzf 选择 Android / iOS / HarmonyOS；按平台检查现有 SDK 和构建工具。

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

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking
. (Resolve-JobsScriptLayoutPath (Join-Path $PSScriptRoot 'SdkDownloadOutput.ps1'))

function Assert-JobsPackagerDirectory {
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

function Assert-JobsPackagerPlainFile {
    param([string]$Path)
    $attributes = [IO.File]::GetAttributes($Path)
    if (($attributes -band [IO.FileAttributes]::Directory) -ne 0 -or ($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "配置必须是普通文件：$Path"
    }
}

function Test-JobsPackagerPathEntry {
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
    [void](Assert-JobsPackagerDirectory $Directory)
    $pubspec = Join-Path $Directory 'pubspec.yaml'
    Assert-JobsPackagerPlainFile $pubspec
    if ((Get-Item -LiteralPath $pubspec).Length -gt 1MB) { throw 'pubspec.yaml 超过 1 MiB，停止读取。' }
    if (-not (Test-JobsFlutterPubspec (Get-Content -LiteralPath $pubspec -Raw -Encoding UTF8))) {
        throw '目标同层 pubspec.yaml 必须明确声明 dependencies.flutter.sdk: flutter；不会扫描子目录或沿用父工程。YAML 别名、标签及多行 flow 映射请先改成常见 block 写法。'
    }
}

function ConvertTo-JobsPackagerPlainText {
    param([string]$Text)
    $escape = [regex]::Escape([string][char]27)
    $plain = $Text -replace ($escape + '\][^\x07]*(?:\x07|' + $escape + '\\)'), ''
    $plain = $plain -replace ($escape + '\[[0-?]*[ -/]*[@-~]'), ''
    return $plain -replace '\\(?:033|e|x1[bB])\[[0-9;]*m', ''
}
# 将打包诊断安全写入业务展示与纯文本日志。
function Write-JobsPackagerMessage {
    param([string]$Message)
    $Message = $Message -replace '\x1b\][^\x07]*(?:\x07|\x1b\\)', '' -replace '\x1b\[[0-?]*[ -/]*[@-~]', ''
    $Message = $Message -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@' -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]' -replace '(?im)((?:token|password|secret|authorization)\s*[:=]\s*)\S+', '$1[已省略]'
    $ErrorActionPreference = 'Stop'
    $safe = (ConvertTo-JobsPackagerPlainText $Message) -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@'
    $safe = $safe -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]'
    Write-JobsEnterChoiceText $safe
    if (Get-Variable -Name PackagerLog -Scope Script -ErrorAction SilentlyContinue) {
        [IO.File]::AppendAllText($script:PackagerLog, ($safe + [Environment]::NewLine), (New-Object Text.UTF8Encoding($true)))
    }
}

function Get-JobsPackagerFlutter {
    param([string]$Project, [string]$SdkRoot)
    if ($SdkRoot) { throw '此菜单仅使用项目 FVM SDK；请通过 FVM 绑定 Harmony 版本，清除本次 FLUTTER_OHOS_SDK 覆盖。' }
    foreach ($candidate in @((Join-Path $Project '.fvm/flutter_sdk/bin/flutter.bat'), (Join-Path $Project '.fvm/flutter_sdk/bin/flutter.exe'))) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return [IO.Path]::GetFullPath($candidate) }
    }
    foreach ($binding in @('.fvmrc', '.fvm/fvm_config.json', '.fvm/flutter_sdk')) {
        if (Test-JobsPackagerPathEntry (Join-Path $Project $binding)) {
            throw '项目已绑定 FVM，但项目 Flutter SDK 缺失或不完整。请先恢复对应 SDK；不会改用 PATH 的其它版本。'
        }
    }
    throw '项目 FVM SDK 缺失；不会回退全局 Flutter。'
}
# 保留打包选择层级与查询，区分产物、返回和取消结果。
function Select-JobsPackagerChoice {
    param([string]$Title, [string[]]$Choices, [switch]$Child)
    $result = Select-JobsFzfItems $Title $Choices -Child:$Child
    if ($result.Action -ceq 'selected') { return $result.Items[0] }
    if ($result.Action -ceq 'back') {
        $errorValue = New-Object OperationCanceledException('返回上一选择层。')
        $errorValue.Data['JobsPickerAction'] = 'back'
        throw $errorValue
    }
    return $null
}

function Assert-JobsPackagerWindowsPlatform {
    param([string]$Platform)
    if ($Platform -ceq 'iOS') { throw 'Windows 无法构建 iOS 安装包。请在 macOS + Xcode 上使用同名 Flutter打包 菜单；本次没有运行 pub get 或 build。' }
    if ($Platform -cnotin @('Android', 'OpenHarmony')) { throw '无效打包平台。' }
}

function Get-JobsPackagerOptions {
    param([string]$Mode = $env:BUILD_MODE, [string]$Flavor = $env:FLAVOR)
    if ([string]::IsNullOrEmpty($Mode)) { $Mode = 'release' }
    if ($Mode -cnotin @('release', 'debug', 'profile')) { throw 'BUILD_MODE / Mode 只支持 release、debug、profile。' }
    if ($Flavor -and $Flavor -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$') { throw 'FLAVOR / Flavor 只能包含英文字母、数字、下划线和连字符，并以字母开头。' }
    return [pscustomobject]@{ Mode = $Mode; Flavor = $Flavor }
}

function Assert-JobsPackagerJava17 {
    param([string]$Project)
    $java = $null
    if ($env:JAVA_HOME) {
        $java = Join-Path $env:JAVA_HOME 'bin/java.exe'
        if (-not (Test-Path -LiteralPath $java -PathType Leaf)) { throw 'JAVA_HOME 未指向完整 JDK 17；请修复后重试。' }
    } else {
        $java = Find-JobsExecutable -Name 'java.exe' -Candidates @('java')
    }
    if (-not $java) { throw '未找到 JDK 17，请安装并配置 JAVA_HOME 后重试。' }
    $result = Invoke-JobsProcess -FilePath $java -Arguments @('-version') -WorkingDirectory $Project -TimeoutSeconds 15
    $version = $result.StdOut + $result.StdErr
    if ($result.ExitCode -ne 0 -or $version -notmatch '(?:java|openjdk) version "17(?:\.|"|-)') { throw 'Android 打包沿用 JDK 17 基线；当前 Java 不是 17 或无法运行。请配置 JAVA_HOME。' }
    $javaHome = Split-Path -Parent (Split-Path -Parent $java)
    if (-not (Test-Path -LiteralPath (Join-Path $javaHome 'bin/javac.exe') -PathType Leaf)) { throw '当前 Java 缺少 javac.exe，请使用完整 JDK 17。' }
    # 仅影响本次 PowerShell 和构建子进程，结束后恢复。
    $env:JAVA_HOME = $javaHome
    $env:PATH = (Join-Path $javaHome 'bin') + [IO.Path]::PathSeparator + $env:PATH
    Write-JobsPackagerMessage ('Java 17：' + $java)
}

function Invoke-JobsPackagerTool {
    param([string]$File, [string[]]$Arguments, [string]$Project)
    if (@($Arguments | Where-Object { $_ -cnotmatch '^[A-Za-z0-9._-]+$' }).Count -gt 0) { throw '构建参数不合法。' }
    if ($Arguments -contains '--version' -or ($Arguments.Count -gt 0 -and $Arguments[0] -ceq 'precache')) {
        $bootstrap = Invoke-JobsPackagerProbe $File $Arguments $Project
        if ($bootstrap.ExitCode -ne 0) { throw 'Flutter SDK 初始化未完成。' }
        return
    }
    Write-JobsPackagerMessage ('执行：' + $File + ' ' + ($Arguments -join ' '))
    Push-Location -LiteralPath $Project
    try {
        # PowerShell 5.1 将原生 stderr 包装为 ErrorRecord；用进程退出码判断成功。
        $ErrorActionPreference = 'Continue'
        & $File @Arguments 2>&1 | ForEach-Object { Write-JobsPackagerMessage ([string]$_) }
        $code = $LASTEXITCODE
    } finally { Pop-Location }
    if ($code -ne 0) { throw ('构建命令失败，退出码 ' + $code + '：' + ($Arguments -join ' ')) }
}

function Get-JobsPackagerArtifacts {
    param([string]$Project, [string]$Type, [string]$Mode, [string]$Flavor, [datetime]$StartedUtc)
    $directory = Join-Path $Project 'build/app/outputs/flutter-apk'
    $flavorPart = ''
    if ($Flavor) { $flavorPart = $Flavor.ToLowerInvariant() + '-' }
    $expectedName = 'app-' + $flavorPart + $Mode + '.apk'
    $expectedParent = ''
    if ($Type -eq 'appbundle') {
        $directory = Join-Path $Project 'build/app/outputs/bundle'
        $expectedName = 'app-' + $flavorPart + $Mode + '.aab'
        $expectedParent = $Flavor.ToLowerInvariant() + $Mode
    }
    $found = @()
    if (Test-Path -LiteralPath $directory -PathType Container) {
        foreach ($file in Get-ChildItem -LiteralPath $directory -Recurse -File) {
            if ($file.Length -le 0) { continue }
            $nameMatches = $file.Name -ieq $expectedName
            if ($Type -eq 'appbundle') {
                if ($file.Directory.Name -ine $expectedParent) { continue }
                $nameMatches = $nameMatches -or $file.Name -ieq 'app.aab' -or $file.Name -ieq ('app-' + $Mode + '.aab')
            }
            if (-not $nameMatches) { continue }
            $found += $file.FullName
        }
    }
    if ($found.Count -eq 0) { throw ('命令结束但没有发现对应 ' + $Type + ' 非空产物（mode=' + $Mode + '，flavor=' + $Flavor + '）：' + $directory) }
    return $found
}

function Invoke-JobsPackagerBuild {
    param([string]$Project, [string]$Type, [string]$Mode = $env:BUILD_MODE, [string]$Flavor = $env:FLAVOR)
    $options = Get-JobsPackagerOptions -Mode $Mode -Flavor $Flavor
    if ($Type -cnotin @('apk', 'appbundle', 'all')) { throw '无效 Android 产物类型。' }
    $gradle = Join-Path $Project 'android/gradlew.bat'
    if (-not (Test-Path -LiteralPath $gradle -PathType Leaf)) { throw '缺少 android/gradlew.bat，目标尚未配置 Android 平台。' }
    $flutter = Get-JobsPackagerFlutter $Project
    $savedJava = $env:JAVA_HOME
    $savedPath = $env:PATH
    try {
        Assert-JobsPackagerJava17 $Project
        Invoke-JobsPackagerTool -File $flutter -Arguments @('--version') -Project $Project
        Invoke-JobsPackagerTool -File $flutter -Arguments @('precache','--android') -Project $Project
        Write-JobsPackagerMessage ('工程：' + $Project)
        Write-JobsPackagerMessage ('Flutter SDK：' + $flutter)
        Write-JobsPackagerMessage ('产物：' + $Type + '；模式：' + $options.Mode + '；Flavor：' + $options.Flavor)
        Invoke-JobsPackagerTool -File $flutter -Arguments @('pub', 'get') -Project $Project
        $targets = @($Type)
        if ($Type -eq 'all') { $targets = @('apk', 'appbundle') }
        foreach ($target in $targets) {
            $arguments = @('build', $target, ('--' + $options.Mode))
            if ($options.Flavor) { $arguments += @('--flavor', $options.Flavor) }
            $started = [DateTime]::UtcNow
            Invoke-JobsPackagerTool -File $flutter -Arguments $arguments -Project $Project
            $artifacts = @(Get-JobsPackagerArtifacts -Project $Project -Type $target -Mode $options.Mode -Flavor $options.Flavor -StartedUtc $started)
            foreach ($artifact in $artifacts) {
                $file = Get-Item -LiteralPath $artifact
                if ($file.LastWriteTimeUtc -lt $started) { Write-JobsPackagerMessage ('现存产物（构建命令成功，可能复用 Gradle 缓存，请核对）：' + $artifact) }
                else { Write-JobsPackagerMessage ('产物已验证：' + $artifact) }
            }
        }
    } finally {
        $env:JAVA_HOME = $savedJava
        $env:PATH = $savedPath
    }
}

function Get-JobsPackagerHarmonyOptions {
    param([string]$Type = $env:OHOS_BUILD_TARGET, [string]$Mode = $env:BUILD_MODE, [string]$Flavor = $env:FLAVOR)
    if ([string]::IsNullOrEmpty($Type)) { $Type = 'hap' }
    if ($Type -cnotin @('hap', 'app', 'all')) { throw 'OHOS_BUILD_TARGET / Type 只支持 hap、app、all。' }
    if ($Flavor) { throw 'OpenHarmony 暂不接受 FLAVOR / Flavor；部分适配 SDK 会将未知 flavor 静默退回 default，请先移除该参数并核对工程产品配置。' }
    $options = Get-JobsPackagerOptions -Mode $Mode -Flavor ''
    return [pscustomobject]@{ Type = $Type; Mode = $options.Mode }
}

function Initialize-JobsPackagerHarmonyEnvironment {
    $toolHome = $env:DEVECO_STUDIO_HOME
    if (-not $toolHome) { $toolHome = $env:TOOL_HOME }
    if (-not $env:DEVECO_SDK_HOME -and $env:HOS_SDK_HOME) { $env:DEVECO_SDK_HOME = $env:HOS_SDK_HOME }
    if ($toolHome) {
        if (-not [IO.Path]::IsPathRooted($toolHome) -or -not [IO.Directory]::Exists($toolHome)) { throw 'DEVECO_STUDIO_HOME / TOOL_HOME 必须指向现有 DevEco Studio 或 command-line-tools 绝对目录。' }
    } elseif (-not $env:DEVECO_SDK_HOME) {
        $candidates = @()
        foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
            if (-not $base) { continue }
            foreach ($relative in @('Huawei/DevEco Studio', 'Huawei/DevEcoStudio')) {
                $candidate = Join-Path $base $relative
                if ([IO.Directory]::Exists((Join-Path $candidate 'sdk'))) { $candidates += [IO.Path]::GetFullPath($candidate) }
            }
        }
        $candidates = @($candidates | Select-Object -Unique)
        if ($candidates.Count -gt 1) { throw '发现多个 DevEco Studio，请用 DEVECO_STUDIO_HOME 明确选择。' }
        if ($candidates.Count -eq 1) { $toolHome = $candidates[0] }
    }
    $paths = @()
    if ($toolHome) {
        $env:TOOL_HOME = $toolHome
        if (-not $env:DEVECO_SDK_HOME) { $env:DEVECO_SDK_HOME = Join-Path $toolHome 'sdk' }
        foreach ($relative in @('tools/node/bin', 'tools/node', 'tool/node/bin', 'tool/node', 'tools/ohpm/bin', 'ohpm/bin', 'tools/hvigor/bin', 'hvigor/bin')) {
            $candidate = Join-Path $toolHome $relative
            if ([IO.Directory]::Exists($candidate)) { $paths += $candidate }
        }
        if (-not $env:JAVA_HOME -and [IO.File]::Exists((Join-Path $toolHome 'jbr/bin/java.exe'))) { $env:JAVA_HOME = Join-Path $toolHome 'jbr' }
    }
    if ($env:JAVA_HOME) {
        if (-not [IO.File]::Exists((Join-Path $env:JAVA_HOME 'bin/java.exe'))) { throw 'JAVA_HOME 中没有 bin/java.exe，请修复现有 Java 配置。' }
        $paths = @((Join-Path $env:JAVA_HOME 'bin')) + $paths
    }
    if ($env:NODE_HOME) {
        $nodePath = $null
        foreach ($relative in @('bin/node.exe', 'node.exe')) {
            if ([IO.File]::Exists((Join-Path $env:NODE_HOME $relative))) { $nodePath = Split-Path -Parent (Join-Path $env:NODE_HOME $relative); break }
        }
        if (-not $nodePath) { throw 'NODE_HOME 中没有 node.exe 或 bin/node.exe，请修复现有 Node 配置。' }
        $paths = @($nodePath) + $paths
    }
    if ($paths.Count -gt 0) { $env:PATH = ($paths -join [IO.Path]::PathSeparator) + [IO.Path]::PathSeparator + $env:PATH }
    if (-not $env:DEVECO_SDK_HOME -or -not [IO.Path]::IsPathRooted($env:DEVECO_SDK_HOME) -or -not [IO.Directory]::Exists($env:DEVECO_SDK_HOME)) {
        throw '没有有效 DEVECO_SDK_HOME（兼容 HOS_SDK_HOME）。请准备 HarmonyOS SDK；不会将 OHOS_SDK_HOME 自动视为同义路径。'
    }
    $env:NO_COLOR = '1'
    $env:FORCE_COLOR = '0'
    $env:CLICOLOR = '0'
    $env:ANSI_COLORS_DISABLED = '1'
    $env:npm_config_color = 'false'
    Write-JobsPackagerMessage ('HarmonyOS SDK：' + $env:DEVECO_SDK_HOME)
}

function Invoke-JobsPackagerProbe {
    param([string]$File, [string[]]$Arguments, [string]$Project)
    if (@($Arguments | Where-Object { $_ -cnotmatch '^[A-Za-z0-9._-]+$' }).Count -gt 0) { throw '工具检查参数不合法。' }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $File
    $start.Arguments = @($Arguments | ForEach-Object { Quote-JobsArgument $_ }) -join ' '
    $start.WorkingDirectory = $Project
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT -and [IO.Path]::GetExtension($File) -in @('.bat', '.cmd')) {
        if ($File -match '["\x00-\x1f]') { throw '工具路径不合法。' }
        $start.FileName = Join-Path ([Environment]::GetFolderPath('System')) 'cmd.exe'
        $start.EnvironmentVariables['JOBS_PACKAGER_PROBE_TOOL'] = $File
        $start.Arguments = '/d /v:off /s /c ""%JOBS_PACKAGER_PROBE_TOOL%" ' + ($Arguments -join ' ') + '"'
    }
    if ([IO.Path]::GetFileName($File) -match '^flutter(\.(bat|exe|cmd))?$' -and ($Arguments -contains '--version' -or ($Arguments.Count -gt 0 -and $Arguments[0] -ceq 'precache'))) { $result = Invoke-JobsSdkAcquireProcess $start 300 -Sanitize -Label 'Flutter/Dart 首次初始化' }
    else { $result = Invoke-JobsSdkLiveProcess $start 300 -Sanitize }
    return [pscustomobject]@{ ExitCode = $result.ExitCode; Output = (ConvertTo-JobsPackagerPlainText ($result.StdOut + $result.StdErr)) }
}

function Assert-JobsPackagerHarmonyToolchain {
    param([string]$Project, [string]$Flutter, [string[]]$Targets)
    $specifications = @(
        @{ Label = 'Node.js'; Name = 'node.exe'; Candidates = @('node'); Arguments = @('--version') },
        @{ Label = 'npm'; Name = 'npm.cmd'; Candidates = @('npm.bat', 'npm'); Arguments = @('--version') },
        @{ Label = 'ohpm'; Name = 'ohpm.bat'; Candidates = @('ohpm.cmd', 'ohpm'); Arguments = @('--version') },
        @{ Label = 'Hvigor'; Name = 'hvigorw.bat'; Candidates = @('hvigorw.cmd', 'hvigorw'); Arguments = @('--version') },
        @{ Label = 'Java'; Name = 'java.exe'; Candidates = @('java'); Arguments = @('-version') }
    )
    foreach ($specification in $specifications) {
        $file = Find-JobsExecutable -Name $specification.Name -Candidates $specification.Candidates
        if (-not $file) { throw ('缺少 ' + $specification.Label + '，请检查现有 DevEco 工具目录和 PATH；不会自动安装。') }
        Write-JobsPackagerMessage ('检查 ' + $specification.Label + '：' + $file)
        $result = Invoke-JobsPackagerProbe -File $file -Arguments $specification.Arguments -Project $Project
        if ($result.Output) { Write-JobsPackagerMessage $result.Output }
        if ($result.ExitCode -ne 0) { throw ($specification.Label + ' 健康检查失败，退出码 ' + $result.ExitCode + '；没有运行 pub get 或 build。') }
    }
    $version = Invoke-JobsPackagerProbe -File $Flutter -Arguments @('--version') -Project $Project
    if ($version.Output) { Write-JobsPackagerMessage $version.Output }
    if ($version.ExitCode -ne 0) { throw ('Flutter 健康检查失败，退出码 ' + $version.ExitCode + '。') }
    foreach ($target in $Targets) {
        $result = Invoke-JobsPackagerProbe -File $Flutter -Arguments @('build', $target, '--help') -Project $Project
        if ($result.ExitCode -ne 0 -or (ConvertTo-JobsPackagerPlainText $result.Output) -cnotmatch ('flutter\s+build\s+' + $target + '\b')) {
            if ($result.Output) { Write-JobsPackagerMessage $result.Output }
            throw ('此 Flutter SDK 未确认支持 flutter build ' + $target + '，请指定匹配工程的 OpenHarmony 适配 SDK；普通 Android / iOS SDK 无法打 OpenHarmony 包。')
        }
        Write-JobsPackagerMessage ('已确认 SDK 能力：flutter build ' + $target)
    }
}

function Get-JobsPackagerHarmonyArtifacts {
    param([string]$Project, [string]$Type)
    $roots = @((Join-Path $Project 'build/ohos'), (Join-Path $Project 'ohos/build'))
    foreach ($module in Get-ChildItem -LiteralPath (Join-Path $Project 'ohos') -Directory) {
        if (($module.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { $roots += Join-Path $module.FullName 'build' }
    }
    $found = New-Object 'System.Collections.Generic.List[string]'
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($rootPath in $roots) {
        if (-not [IO.Directory]::Exists($rootPath)) { continue }
        try { [void](Assert-JobsPackagerDirectory $rootPath) } catch { continue }
        $pending = New-Object 'System.Collections.Generic.Stack[string]'
        $pending.Push($rootPath)
        while ($pending.Count -gt 0) {
            $directory = $pending.Pop()
            if (([IO.File]::GetAttributes($directory) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            foreach ($entry in Get-ChildItem -LiteralPath $directory -Force) {
                if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                if ($entry.PSIsContainer) {
                    if ($entry.Name -notin @('intermediates', '.hvigor', 'node_modules', 'oh_modules', '.git')) { $pending.Push($entry.FullName) }
                    continue
                }
                if ($entry.Extension -ine ('.' + $Type) -or $entry.Length -le 0) { continue }
                $relative = $entry.FullName.Substring($rootPath.Length).Replace('\', '/')
                if ($rootPath -ne $roots[0] -and $relative -notmatch '/outputs/') { continue }
                if ($seen.Add($entry.FullName)) { $found.Add($entry.FullName) }
            }
        }
    }
    if ($found.Count -eq 0) { throw ('命令结束但没有发现非空 .' + $Type + ' 产物；已检查 build/ohos 与 ohos 各模块的 outputs 目录。') }
    return $found.ToArray()
}

function Invoke-JobsPackagerHarmonyBuild {
    param([string]$Project, [string]$Type = $env:OHOS_BUILD_TARGET, [string]$Mode = $env:BUILD_MODE, [string]$FlutterSdk = $env:FLUTTER_OHOS_SDK, [string]$Flavor = $env:FLAVOR)
    $options = Get-JobsPackagerHarmonyOptions -Type $Type -Mode $Mode -Flavor $Flavor
    foreach ($relative in @('ohos/build-profile.json5', 'ohos/oh-package.json5')) {
        $file = Join-Path $Project $relative
        if (-not [IO.File]::Exists($file)) { throw ('工程缺少 ' + $relative + '，请先完成 ohos 平台适配；不会自动创建或修改平台。') }
        Assert-JobsPackagerPlainFile $file
    }
    $flutter = Get-JobsPackagerFlutter -Project $Project -SdkRoot $FlutterSdk
    $environment = @{}
    foreach ($name in @('PATH', 'JAVA_HOME', 'NODE_HOME', 'TOOL_HOME', 'DEVECO_SDK_HOME', 'NO_COLOR', 'FORCE_COLOR', 'CLICOLOR', 'ANSI_COLORS_DISABLED', 'npm_config_color')) {
        $environment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
    try {
        Initialize-JobsPackagerHarmonyEnvironment
        $targets = @($options.Type)
        if ($options.Type -eq 'all') { $targets = @('hap', 'app') }
        Assert-JobsPackagerHarmonyToolchain -Project $Project -Flutter $flutter -Targets $targets
        $precacheHelp = Invoke-JobsPackagerProbe $flutter @('precache','--help') $Project
        if ($precacheHelp.ExitCode -ne 0 -or $precacheHelp.Output -notmatch '--(?:\[no-\])?ohos\b') { throw '当前 Harmony Flutter SDK 未确认支持 precache --ohos，未开始构建。' }
        Invoke-JobsPackagerTool -File $flutter -Arguments @('precache','--ohos') -Project $Project
        Write-JobsPackagerMessage ('工程：' + $Project)
        Write-JobsPackagerMessage ('Flutter SDK：' + $flutter)
        Write-JobsPackagerMessage ('OpenHarmony 产物：' + $options.Type + '；模式：' + $options.Mode + '；签名沿用工程现有配置。')
        Invoke-JobsPackagerTool -File $flutter -Arguments @('pub', 'get') -Project $Project
        $validatedArtifacts = @{}
        foreach ($target in $targets) {
            $started = [DateTime]::UtcNow
            Invoke-JobsPackagerTool -File $flutter -Arguments @('build', $target, ('--' + $options.Mode)) -Project $Project
            $validatedArtifacts[$target] = @(Get-JobsPackagerHarmonyArtifacts -Project $Project -Type $target)
            foreach ($artifact in $validatedArtifacts[$target]) {
                $file = Get-Item -LiteralPath $artifact
                if ($file.Name -match '-unsigned\.') { Write-JobsPackagerMessage ('未签名 OpenHarmony 产物：' + $artifact + '；安装或上架前必须完成签名。') }
                elseif ($file.LastWriteTimeUtc -lt $started) { Write-JobsPackagerMessage ('现存 OpenHarmony 产物（构建命令成功，可能复用 Hvigor 缓存，请核对）：' + $artifact) }
                else { Write-JobsPackagerMessage ('OpenHarmony 产物已验证：' + $artifact) }
            }
        }
        # APP 构建可能重建输出树，只复核本轮已验证路径，不能换用其它旧包。
        if ($targets.Count -gt 1) {
            foreach ($target in $targets) {
                $remaining = @($validatedArtifacts[$target] | Where-Object {
                    try {
                        Assert-JobsPackagerPlainFile $_
                        [void](Assert-JobsPackagerDirectory (Split-Path -Parent $_))
                        (Get-Item -LiteralPath $_).Length -gt 0
                    } catch { $false }
                })
                if ($remaining.Count -eq 0) { throw ('最终检查失败：已验证的非空 .' + $target + ' 产物已消失或被替换，不能报告双产物完成。') }
            }
        }
    } finally {
        foreach ($name in $environment.Keys) {
            if ($null -eq $environment[$name]) { Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue }
            else { [Environment]::SetEnvironmentVariable($name, $environment[$name], 'Process') }
        }
    }
}

function Invoke-JobsFlutterHarmonyAction {
    param([string]$Target)
    Write-Host '打包鸿蒙 HAP + APP：只处理所选 Flutter 根目录，固定 release，使用项目 FVM 适配 SDK。'
    Write-Host '会运行 pub get、build hap --release、build app --release 并写入工程；签名沿用工程配置，不安装或切换 SDK。'
    Write-Host '不读取 BUILD_MODE / OHOS_BUILD_TARGET / FLAVOR；Ctrl+C 或任意非空输入取消。'
    Assert-JobsFlutterProject $Target
    try {
        [void](Assert-JobsPackagerDirectory (Join-Path $Target 'lib'))
        [void](Assert-JobsPackagerDirectory (Join-Path $Target 'ohos'))
        foreach ($relative in @('ohos/build-profile.json5', 'ohos/oh-package.json5')) {
            Assert-JobsPackagerPlainFile (Join-Path $Target $relative)
        }
    } catch {
        throw ('请先完成当前 Flutter 项目的鸿蒙平台适配：需要普通非链接的 lib/、ohos/、ohos/build-profile.json5 和 ohos/oh-package.json5。本次未启动构建。详情：' + $_.Exception.Message)
    }
    if (-not [IO.File]::Exists((Join-Path $Target '.fvm/flutter_sdk/bin/flutter.bat')) -and
        -not [IO.File]::Exists((Join-Path $Target '.fvm/flutter_sdk/bin/flutter.exe'))) {
        throw '项目 FVM SDK 缺失；快捷打包不会使用全局或临时覆盖的 Flutter。'
    }
    $confirmation = Read-JobsEnterChoiceHost '回车开始打包鸿蒙 HAP + APP，任意非空输入取消'
    if ($null -eq $confirmation -or $confirmation -ne '') { Write-Host '已取消，没有开始打包。'; return }
    $logDirectory = Join-Path (Get-JobsInstallRoot) 'logs'
    [void][IO.Directory]::CreateDirectory($logDirectory)
    $script:PackagerLog = Join-Path $logDirectory ('harmony-' + (Get-Date -Format 'yyyy-MM-dd-HH-mm-ss') + '-' + [guid]::NewGuid().ToString('N') + '.log')
    Write-JobsPackagerMessage ('日志：' + $script:PackagerLog)
    Invoke-JobsPackagerHarmonyBuild -Project $Target -Type 'all' -Mode 'release' -Flavor '' -FlutterSdk ''
    Write-JobsPackagerMessage '鸿蒙 HAP + APP 打包完成；两种产物均已检查，未签名产物需要先完成签名才能安装。'
}
# 逐级选择平台与产物，默认取消最终构建并保留返回层级状态。
function Invoke-JobsFlutterPackageAction {
    param([string]$Target)
    Write-JobsEnterChoiceText 'Flutter打包：所选工程使用键盘选择平台和产物；缺失 fzf 才在当前流程准备，许可仍由本人确认。'
    Write-JobsEnterChoiceText '构建会执行 pub get/build 并写入工程；最终默认取消。模式默认 release，BUILD_MODE 和 FLAVOR 保留。'
    Assert-JobsFlutterProject $Target
    $logDirectory = Join-Path (Get-JobsInstallRoot) 'logs'
    [void][IO.Directory]::CreateDirectory($logDirectory)
    $script:PackagerLog = Join-Path $logDirectory ('package-' + (Get-Date -Format 'yyyy-MM-dd-HH-mm-ss') + '-' + [guid]::NewGuid().ToString('N') + '.log')
    Write-JobsPackagerMessage ('日志：' + $script:PackagerLog)
    $platformState = @{}; $productState = @{}; $previousPlatform = ''; $platform = ''; $type = ''
    while ($true) {
        $platformChoice = Select-JobsFzfItems '选择打包平台' @('Android', 'iOS', 'OpenHarmony') -State $platformState
        if ($platformChoice.Action -cne 'selected') { Write-JobsPackagerMessage '已取消，没有开始打包。'; return }
        $platform = [string]$platformChoice.Items[0]
        Assert-JobsPackagerWindowsPlatform $platform
        if ($platform -cne $previousPlatform) { $productState = @{} }
        $previousPlatform = $platform
        while ($true) {
            if ($platform -ceq 'OpenHarmony') {
                $options = Get-JobsPackagerHarmonyOptions
                $labels = @{ hap = 'HAP'; app = 'APP'; all = 'HAP + APP' }
                $defaultLabel = $labels[$options.Type]
                $choices = @($defaultLabel) + @('HAP', 'APP', 'HAP + APP' | Where-Object { $_ -cne $defaultLabel })
            } else { $choices = @('APK', 'AAB', 'APK + AAB') }
            $product = Select-JobsFzfItems '选择构建产物' $choices -Child -State $productState
            if ($product.Action -ceq 'back') { break }
            if ($product.Action -cne 'selected') { Write-JobsPackagerMessage '已取消，没有开始打包。'; return }
            $choice = [string]$product.Items[0]
            $confirmation = Select-JobsFzfItems ('确认构建 ' + $choice + '（默认取消）') @('构建并写入所选工程') -Child -RequireConfirmation
            if ($confirmation.Action -ceq 'back') { continue }
            if ($confirmation.Action -cne 'selected') { Write-JobsPackagerMessage '已取消，没有开始打包。'; return }
            if ($platform -ceq 'OpenHarmony') {
                $type = switch -CaseSensitive ($choice) { 'HAP' { 'hap' } 'APP' { 'app' } 'HAP + APP' { 'all' } default { throw '无效鸿蒙产物。' } }
                Invoke-JobsPackagerHarmonyBuild -Project $Target -Type $type
                Write-JobsPackagerMessage 'Flutter HarmonyOS 打包完成；发布要求继续按工程签名配置核对。'
            } else {
                $type = switch -CaseSensitive ($choice) { 'APK' { 'apk' } 'AAB' { 'appbundle' } 'APK + AAB' { 'all' } default { throw '无效 Android 产物。' } }
                Invoke-JobsPackagerBuild -Project $Target -Type $type
                Write-JobsPackagerMessage 'Flutter Android 打包完成。'
            }
            return
        }
    }
}

function Invoke-JobsFeature {
    param([Parameter(Mandatory = $true)][string]$Target)
    $directory = Get-JobsDirectory -Target $Target
    Invoke-JobsFlutterPackageAction -Target $directory
}

Export-ModuleMember -Function Invoke-JobsFeature

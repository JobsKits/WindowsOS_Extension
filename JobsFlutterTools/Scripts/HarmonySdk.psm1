# HarmonySdk.psm1 | JobsFlutterTools
# Created by Jobs on 2026年10月23日，星期五.
# 项目级 OpenHarmony Flutter 缓存与 FVM 绑定；不改全局 SDK 或环境。

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
. (Resolve-JobsScriptLayoutPath (Join-Path $PSScriptRoot 'SdkDownloadOutput.ps1'))
$script:HarmonyRepository = 'https://gitcode.com/CPF-Flutter/flutter_flutter.git'
$script:HarmonyManager = Import-Module (Join-Path $PSScriptRoot 'Actions/sdk-manage/Scripts/Action.psm1') -PassThru -DisableNameChecking

function Invoke-JobsHarmonyGit {
    param([string]$Git, [string[]]$Arguments, [string]$Directory, [int]$TimeoutSeconds = 120, [switch]$LiveCapture)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Git
    $quoted = & $script:HarmonyManager { param($Values) @($Values | ForEach-Object { Quote-JobsArgument $_ }) -join ' ' } $Arguments
    $start.Arguments = '-c http.lowSpeedLimit=1024 -c http.lowSpeedTime=60 ' + $quoted
    $start.WorkingDirectory = $Directory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $start.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    $start.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'
    foreach ($key in @('GIT_DIR','GIT_WORK_TREE','GIT_COMMON_DIR','GIT_INDEX_FILE','GIT_OBJECT_DIRECTORY','GIT_ALTERNATE_OBJECT_DIRECTORIES')) { $start.EnvironmentVariables.Remove($key) }
    $acquire = @($Arguments | Where-Object { $_ -in @('fetch','ls-remote') }).Count -gt 0
    if ($LiveCapture -or $acquire) {
        $result = if ($acquire) { Invoke-JobsSdkAcquireProcess $start $TimeoutSeconds -Label 'OpenHarmony Flutter Git 获取' } else { Invoke-JobsSdkLiveProcess $start $TimeoutSeconds }
        if ($result.ExitCode -ne 0) { throw ('Git 失败（' + $result.ExitCode + '），请检查上方实时输出；缓存现场保留。') }
        return $result.StdOut.TrimEnd("`r", "`n")
    }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw '无法启动 Git。' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
                & (Join-Path ([Environment]::GetFolderPath('System')) 'taskkill.exe') /PID $process.Id /T /F | Out-Null
            } else { $process.Kill() }
            throw 'Git 超时，已停止本次下载；缓存现场保留。'
        }
        if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout, $stderr), 5000)) { throw 'Git 输出管道未关闭。' }
        $output = $stdout.GetAwaiter().GetResult()
        $errors = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw ('Git 失败（' + $process.ExitCode + '）：' + $errors.Trim()) }
        return $output.TrimEnd("`r", "`n")
    } finally { $process.Dispose() }
}

function ConvertFrom-JobsHarmonyTags {
    param([string]$Text)
    $tags = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    $peeled = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    foreach ($line in @($Text -split '\r?\n')) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -cnotmatch '^(?<sha>[0-9a-f]{40})\s+refs/tags/(?<tag>[^\s]+?)(?<peeled>\^\{\})?$') { throw '远端 tag 清单包含无法验证的记录。' }
        $sha = $Matches['sha']; $tag = $Matches['tag']; $isPeeled = $Matches['peeled']
        if ($tag -cnotmatch '^v?\d+\.\d+\.\d+[-+][A-Za-z0-9.+-]*ohos[A-Za-z0-9.+-]*$') { continue }
        $target = if ($isPeeled) { $peeled } else { $tags }
        if ($target.ContainsKey($tag) -and $target[$tag] -cne $sha) { throw '远端重复 tag 不一致。' }
        $target[$tag] = $sha
    }
    foreach ($tag in $tags.Keys) {
        $commit = if ($peeled.ContainsKey($tag)) { $peeled[$tag] } else { $tags[$tag] }
        $base = [version]([regex]::Match($tag, '\d+\.\d+\.\d+').Value)
        $pre = $tag -match '(?:[.+-])(?:beta|alpha|rc|pre|dev|canary)(?:[.0-9+-]|$)'
        $natural = [regex]::Replace(($tag -replace '^v',''), '\d+', { param($match) $match.Value.PadLeft(12, '0') })
        [pscustomobject]@{ Ref = $tag; Commit = $commit; Version = ('custom_jobs_ohos_' + $commit); BaseVersion = $base; Prerelease = $pre; NaturalRef = $natural; Label = ($tag + ' | ' + $commit.Substring(0,12) + ' | CPF-Flutter') }
    }
}

function Get-JobsHarmonyTagChoices {
    param([string]$Text)
    ConvertFrom-JobsHarmonyTags $Text | Sort-Object -Property @{Expression='Prerelease'; Ascending=$true}, @{Expression='BaseVersion'; Descending=$true}, @{Expression='NaturalRef'; Descending=$true}
}

function Resolve-JobsHarmonyCommit {
    param([string]$Text, [string]$Ref)
    $tag = ''; $peeled = ''; $branch = ''
    foreach ($line in @($Text -split '\r?\n')) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -cnotmatch '^(?<sha>[0-9a-f]{40})\s+(?<ref>refs/[^\s]+)$') { throw '远端 ref 记录无效。' }
        $sha = $Matches['sha']; $name = $Matches['ref']
        if ($name -ceq ('refs/tags/' + $Ref)) { if ($tag -and $tag -cne $sha) { throw '重复 tag。' }; $tag = $sha }
        elseif ($name -ceq ('refs/tags/' + $Ref + '^{}')) { if ($peeled -and $peeled -cne $sha) { throw '重复 peeled tag。' }; $peeled = $sha }
        elseif ($name -ceq ('refs/heads/' + $Ref)) { $branch = $sha }
        else { throw '远端返回了未请求的 ref。' }
    }
    if (-not $tag -or $branch) { throw '所选 tag 不存在或与同名分支冲突。' }
    if ($peeled) { return $peeled }
    return $tag
}

function Get-JobsHarmonyCache {
    $root = [Environment]::GetFolderPath('LocalApplicationData')
    if ($env:LOCALAPPDATA) { $root = $env:LOCALAPPDATA }
    if (-not [IO.Path]::IsPathRooted($root)) { throw '无法定位用户本地缓存目录。' }
    return Join-Path $root 'JobsFlutter/fvm/harmony'
}

function Assert-JobsHarmonyBindingPaths {
    param([string]$Project)
    & $script:HarmonyManager { param($Path) Assert-JobsFlutterProject $Path } $Project
    foreach ($relative in @('.fvm','.fvm/versions')) {
        $path = Join-Path $Project $relative
        if (& $script:HarmonyManager { param($Path) Test-JobsFvmPathEntry $Path } $path) {
            [void](& $script:HarmonyManager { param($Path) Assert-JobsFvmDirectory $Path } $path)
        }
    }
    foreach ($relative in @('.fvmrc','.fvm/fvm_config.json')) {
        $path = Join-Path $Project $relative
        if (& $script:HarmonyManager { param($Path) Test-JobsFvmPathEntry $Path } $path) { & $script:HarmonyManager { param($Path) Assert-JobsFvmPlainFile $Path } $path }
    }
    $link = Join-Path $Project '.fvm/flutter_sdk'
    if (& $script:HarmonyManager { param($Path) Test-JobsFvmPathEntry $Path } $link) {
        if (((Get-Item -LiteralPath $link -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { throw '.fvm/flutter_sdk 是真实目录，保留源码并停止；请先迁移到独立 SDK 缓存。' }
    }
    $versions = Join-Path $Project '.fvm/versions'
    if ([IO.Directory]::Exists($versions)) {
        foreach ($item in Get-ChildItem -LiteralPath $versions -Force) {
            if ($item.PSIsContainer -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { throw '.fvm/versions 含真实 SDK 目录，保留源码并停止。' }
        }
    }
}

function Remove-JobsHarmonyEntry {
    param([string]$Path)
    if (-not (& $script:HarmonyManager { param($Value) Test-JobsFvmPathEntry $Value } $Path)) { return }
    $entry = Get-Item -LiteralPath $Path -Force
    if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        if (($entry.Attributes -band [IO.FileAttributes]::Directory) -ne 0) { [IO.Directory]::Delete($Path) }
        else { [IO.File]::Delete($Path) }
    } elseif ($entry.PSIsContainer) {
        foreach ($child in Get-ChildItem -LiteralPath $Path -Force) { Remove-JobsHarmonyEntry $child.FullName }
        [IO.Directory]::Delete($Path)
    } else { [IO.File]::Delete($Path) }
}

function Set-JobsHarmonyConfig {
    param([string]$Project, [string]$Version, [string]$Cache)
    if ($Version -cnotmatch '^custom_jobs_ohos_[0-9a-f]{40}$' -or -not [IO.Path]::IsPathRooted($Cache)) { throw '鸿蒙 FVM 绑定参数无效。' }
    $config = & $script:HarmonyManager { param($Path) Get-JobsProjectFvmConfig $Path } $Project
    foreach ($pair in @(@('flutter', $Version), @('cachePath', $Cache), @('flutterUrl', $script:HarmonyRepository), @('updateMelosSettings', $false), @('useGitCache', $false))) {
        $config | Add-Member -NotePropertyName $pair[0] -NotePropertyValue $pair[1] -Force
    }
    [IO.File]::WriteAllText((Join-Path $Project '.fvmrc'), ($config | ConvertTo-Json -Depth 100) + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
    return $config
}

function Assert-JobsHarmonySdk {
    param([string]$Git, [string]$Sdk, [string]$Commit, [string]$Directory)
    [void](& $script:HarmonyManager { param($Path) Assert-JobsFvmDirectory $Path } $Sdk)
    if (-not [IO.Directory]::Exists((Join-Path $Sdk '.git')) -or -not [IO.File]::Exists((Join-Path $Sdk 'bin/flutter.bat'))) { throw '缓存不是完整独立 Git SDK，未覆盖。' }
    [void](& $script:HarmonyManager { param($Path) Assert-JobsFvmDirectory $Path } (Join-Path $Sdk '.git'))
    if ((Invoke-JobsHarmonyGit $Git @('-C', $Sdk, 'rev-parse', 'HEAD') $Directory) -cne $Commit -or
        (Invoke-JobsHarmonyGit $Git @('-C', $Sdk, 'remote', 'get-url', 'origin') $Directory) -cne $script:HarmonyRepository) { throw '缓存来源或 commit 不匹配，未覆盖。' }
    if (-not [string]::IsNullOrWhiteSpace((Invoke-JobsHarmonyGit $Git @('-C', $Sdk, 'status', '--porcelain', '--untracked-files=no') $Directory))) { throw 'SDK 缓存有源码改动，未覆盖或复用。' }
}

function Install-JobsHarmonySdk {
    param([string]$Git, [object]$Choice, [string]$Cache, [string]$Directory)
    $versions = Join-Path $Cache 'versions'
    [void][IO.Directory]::CreateDirectory($versions)
    [void](& $script:HarmonyManager { param($Path) Assert-JobsFvmDirectory $Path } $versions)
    $target = Join-Path $versions $Choice.Version
    if (& $script:HarmonyManager { param($Path) Test-JobsFvmPathEntry $Path } $target) {
        Assert-JobsHarmonySdk $Git $target $Choice.Commit $Directory
        return $target
    }
    $stage = Join-Path $versions ('.jobs-download-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($stage)
    $candidate = Join-Path $stage 'sdk'
    try {
        Write-Host ('下载 SDK 来源：' + $script:HarmonyRepository + '；tag：' + $Choice.Ref + '；commit：' + $Choice.Commit)
        [void](Invoke-JobsHarmonyGit $Git @('init', $candidate) $Directory)
        [void](Invoke-JobsHarmonyGit $Git @('-C',$candidate,'remote','add','origin',$script:HarmonyRepository) $Directory)
        [void](Invoke-JobsHarmonyGit $Git @('-C',$candidate,'fetch','--progress','--depth','1','origin',('refs/tags/' + $Choice.Ref)) $Directory 120 -LiveCapture)
        [void](Invoke-JobsHarmonyGit $Git @('-C', $candidate, 'checkout', '--detach', $Choice.Commit) $Directory 120 -LiveCapture)
        Assert-JobsHarmonySdk $Git $candidate $Choice.Commit $Directory
        # 同文件系统无覆盖发布；其它会话先创建目标时 Directory.Move 失败。
        [IO.Directory]::Move($candidate, $target)
        [IO.Directory]::Delete($stage)
        return $target
    } catch { Write-Warning ('SDK 下载现场保留：' + $stage); throw }
}

function Get-JobsHarmonyBindingStamp {
    param([string]$Project)
    $stamp = & $script:HarmonyManager { param($Path) Get-JobsFvmPreviewStamp $Path } $Project
    $link = Join-Path $Project '.fvm/flutter_sdk'
    $linkState = '(absent)'
    if (& $script:HarmonyManager { param($Path) Test-JobsFvmPathEntry $Path } $link) {
        $item = Get-Item -LiteralPath $link -Force
        $linkState = ([string]$item.Attributes) + ':' + (@($item.Target) | ConvertTo-Json -Compress)
    }
    return $stamp + '|' + $linkState
}

function Complete-JobsHarmonyConfigPublication {
    param([string]$Stage, [string]$Target, [bool]$Exists)
    if ($Exists) { [IO.File]::Replace($Stage, $Target, [NullString]::Value) }
    else { [IO.File]::Move($Stage, $Target) }
}

function Publish-JobsHarmonyBinding {
    param([string]$Project, [string]$Sdk, [string]$Config, [string]$Stamp)
    Assert-JobsHarmonyBindingPaths $Project
    if ((Get-JobsHarmonyBindingStamp $Project) -cne $Stamp) { throw '初始化期间项目绑定已改变，未发布 SDK。' }
    $backupRoot = & $script:HarmonyManager { Join-Path (Get-JobsInstallRoot) 'backups' }
    $backup = Join-Path $backupRoot ('openharmony-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($backup)
    $configPath = Join-Path $Project '.fvmrc'
    $hadConfig = [IO.File]::Exists($configPath)
    if ($hadConfig) { Copy-Item -LiteralPath $configPath -Destination (Join-Path $backup '.fvmrc') }
    $fvm = Join-Path $Project '.fvm'
    $hadFvm = [IO.Directory]::Exists($fvm)
    $link = Join-Path $fvm 'flutter_sdk'
    $hadLink = & $script:HarmonyManager { param($Path) Test-JobsFvmPathEntry $Path } $link
    $oldTarget = @()
    if ($hadLink) { $oldTarget = @((Get-Item -LiteralPath $link -Force).Target) }
    @{ Project=$Project; HadConfig=$hadConfig; HadFvm=$hadFvm; OldSdkTargets=$oldTarget; NewSdk=$Sdk } |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $backup 'binding.json') -Encoding UTF8
    $token = [guid]::NewGuid().ToString('N')
    $stageConfig = Join-Path $Project ('.jobs-fvmrc-' + $token)
    $stageLink = Join-Path $fvm ('.jobs-sdk-' + $token)
    $oldLink = Join-Path $fvm ('.jobs-sdk-before-' + $token)
    $configPublished = $false; $linkPublished = $false; $oldMoved = $false
    try {
        [IO.File]::WriteAllText($stageConfig, $Config, (New-Object Text.UTF8Encoding($false)))
        $expectedHash = (Get-FileHash -LiteralPath $stageConfig -Algorithm SHA256).Hash
        if ((Get-JobsHarmonyBindingStamp $Project) -cne $Stamp) { throw '发布前项目绑定已改变，未写入。' }
        [void][IO.Directory]::CreateDirectory($fvm)
        $linkType = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'Junction' } else { 'SymbolicLink' }
        # Windows PowerShell 5.1 会把 Target 当通配路径，7.x 则按字面目标处理。
        $linkTarget = $Sdk
        if ($PSVersionTable.PSVersion.Major -eq 5) { $linkTarget = [Management.Automation.WildcardPattern]::Escape($Sdk) }
        [void](New-Item -ItemType $linkType -Path $stageLink -Target $linkTarget)
        if ($hadLink) { [IO.Directory]::Move($link, $oldLink); $oldMoved = $true }
        [IO.Directory]::Move($stageLink, $link); $linkPublished = $true
        Complete-JobsHarmonyConfigPublication $stageConfig $configPath $hadConfig
        $configPublished = $true
        $actualTargets = @((Get-Item -LiteralPath $link -Force).Target)
        if ($actualTargets.Count -ne 1 -or [string]$actualTargets[0] -cne $Sdk -or
            (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash -cne $expectedHash) { throw '发布后的项目配置或 SDK 链接核验失败。' }
        if ($oldMoved) { Remove-JobsHarmonyEntry $oldLink; $oldMoved = $false }
        Write-Host ('项目绑定备份：' + $backup)
    } catch {
        $failure = $_
        try {
            if ($configPublished) {
                if (-not [IO.File]::Exists($configPath) -or
                    (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash -cne $expectedHash) { throw '项目 .fvmrc 已被其它操作改变，未覆盖。' }
                if ($hadConfig) { Copy-Item -LiteralPath (Join-Path $backup '.fvmrc') -Destination $configPath -Force }
                else { [IO.File]::Delete($configPath) }
            }
            if ($linkPublished) {
                $targets = @((Get-Item -LiteralPath $link -Force).Target)
                if ($targets.Count -ne 1 -or [string]$targets[0] -cne $Sdk) { throw '项目 SDK 链接已被其它操作改变，未覆盖。' }
                Remove-JobsHarmonyEntry $link
            }
            if ($oldMoved) { [IO.Directory]::Move($oldLink, $link); $oldMoved = $false }
            if (-not $hadFvm -and [IO.Directory]::Exists($fvm) -and @(Get-ChildItem -LiteralPath $fvm -Force).Count -eq 0) { [IO.Directory]::Delete($fvm) }
        } catch { throw ('发布失败且发现并发改动，快照与原链接保留：' + $backup + '；' + $oldLink + '；恢复错误：' + $_.Exception.Message) }
        throw $failure
    } finally {
        if ([IO.File]::Exists($stageConfig)) { [IO.File]::Delete($stageConfig) }
        if (& $script:HarmonyManager { param($Path) Test-JobsFvmPathEntry $Path } $stageLink) { Remove-JobsHarmonyEntry $stageLink }
    }
}
# 按选定SDK职责分发，只读检查和未选分支不获取工具。
function Invoke-JobsHarmonySdkAction {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Target, [switch]$Check, [switch]$RequireCompletion)
    $project = & $script:HarmonyManager { param($Path) Assert-JobsFvmDirectory (Resolve-JobsTarget $Path) } $Target
    Assert-JobsHarmonyBindingPaths $project
    $cache = Get-JobsHarmonyCache
    if ($Check) {
        $config = & $script:HarmonyManager { param($Path) Get-JobsProjectFvmConfig $Path } $project
        Write-JobsEnterChoiceText ('只读计划：' + $project)
        Write-JobsEnterChoiceText ('来源：' + $script:HarmonyRepository + '；缓存：' + $cache)
        $pin = '(未绑定)'
        if ($config.PSObject.Properties['flutter']) {
            $candidate = [string]$config.flutter
            if ($candidate -cmatch '^(?:custom_jobs_ohos_[0-9a-f]{40}|v?\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.+-]+)?)$') { $pin = $candidate }
            else { $pin = '(其它格式，未回显)' }
        }
        $managed = Test-JobsManagedHarmonyBinding $project
        Write-JobsEnterChoiceText ('当前项目版本：' + $pin + '；本工具 CPF 绑定：' + $managed)
        Write-JobsEnterChoiceText '安装模式将从远端 tag 选择并锁定 commit；本次未联网、未运行 Git/FVM/Flutter、未写项目。'
        return
    }
    Write-JobsEnterChoiceText ('安装/切换 Flutter@OpenHarmony SDK；项目：' + $project)
    Write-JobsEnterChoiceText '选择 CPF-Flutter 的 ohos tag，锁定 commit 后安装到隔离缓存，再绑定当前项目 FVM。不会生成 ohos/、安装 DevEco 或运行构建。'
    $saved = @{}
    foreach ($key in @('PATH','FVM_CACHE_PATH','FVM_FLUTTER_URL','FVM_USE_GIT_CACHE')) { $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
    $savedTls = [Net.ServicePointManager]::SecurityProtocol
    $inspection = $null; $lock = $null
    try {
        [Net.ServicePointManager]::SecurityProtocol = $savedTls -bor [Net.SecurityProtocolType]::Tls12
        $root = & $script:HarmonyManager { Get-JobsInstallRoot }
        [void][IO.Directory]::CreateDirectory($root)
        try { $lock = [IO.File]::Open((Join-Path $root 'operation.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
        catch { throw '另一 FVM 操作正在运行，请稍后重试。' }
        $stamp = Get-JobsHarmonyBindingStamp $project
        $inspection = & $script:HarmonyManager { param($Path) New-JobsFvmInspection $Path } $project
        $chain = & $script:HarmonyManager { param($Path,$Inspection) Get-JobsFvmToolchain $Path $Inspection } $project $inspection
        $tags = Invoke-JobsHarmonyGit $chain.Git @('ls-remote', '--tags', $script:HarmonyRepository) $project
        $choices = @(Get-JobsHarmonyTagChoices $tags)
        if ($choices.Count -eq 0) { throw '来源未返回可验证的 ohos tag；未写项目。' }
        $versionState = @{}
        while ($true) {
            $choice = & $script:HarmonyManager { param($Fzf,$Choices,$Path,$State) Select-JobsFlutterVersion $Fzf $Choices $Path -State $State } $chain.Fzf $choices $project $versionState
            if ($null -eq $choice) { if ($RequireCompletion) { throw '已取消鸿蒙 SDK 准备，未继续依赖操作。' }; Write-JobsEnterChoiceText '已取消，项目未修改。'; return }
            $refs = Invoke-JobsHarmonyGit $chain.Git @('ls-remote', $script:HarmonyRepository, ('refs/tags/' + $choice.Ref), ('refs/tags/' + $choice.Ref + '^{}'), ('refs/heads/' + $choice.Ref)) $project
            if ((Resolve-JobsHarmonyCommit $refs $choice.Ref) -cne $choice.Commit) { throw '所选 tag 在选择期间改变，请重新选择。' }
            Write-JobsEnterChoiceText ('计划：' + $choice.Ref + ' → ' + $choice.Commit + '；缓存：' + $cache)
            Write-JobsEnterChoiceText 'FVM 先在影子项目初始化并核验；真实项目仅更新 .fvmrc 和 .fvm/flutter_sdk。IDE、ignore、业务源码及其它元数据保持原样。'
            $confirmation = & $script:HarmonyManager { param($Child) Select-JobsFzfItems '确认安装/切换 OpenHarmony SDK（默认取消）' @('按以上精确 tag、commit 与写入范围继续') -RequireConfirmation -Child:$Child } ($choices.Count -gt 1)
            if ($confirmation.Action -ceq 'back') { continue }
            if ($confirmation.Action -cne 'selected') { if ($RequireCompletion) { throw '已取消鸿蒙 SDK 准备，未继续依赖操作。' }; Write-JobsEnterChoiceText '已取消，项目未修改。'; return }
            break
        }
        Assert-JobsHarmonyBindingPaths $project
        if ((Get-JobsHarmonyBindingStamp $project) -cne $stamp) { throw '选版期间项目配置已改变，请重新打开。' }
        $sdk = Install-JobsHarmonySdk $chain.Git $choice $cache $project
        $pinned = Set-JobsHarmonyConfig $inspection $choice.Version $cache
        $env:FVM_CACHE_PATH = $cache; $env:FVM_FLUTTER_URL = $script:HarmonyRepository; $env:FVM_USE_GIT_CACHE = 'false'
        $use = & $script:HarmonyManager { param($Fvm,$Version,$Path) Invoke-JobsFvmTool $Fvm @('use',$Version,'--skip-setup','--skip-pub-get') $Path -Visible -TimeoutSeconds 300 } $chain.Fvm $choice.Version $inspection
        if ($use.ExitCode -ne 0) { throw 'FVM 鸿蒙 SDK 绑定失败。' }
        $after = & $script:HarmonyManager { param($Path) Get-JobsProjectFvmConfig $Path } $inspection
        foreach ($property in $pinned.PSObject.Properties) {
            if ($null -eq $after.PSObject.Properties[$property.Name]) { $after | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value }
        }
        if ($after.flutter -cne $choice.Version -or $after.cachePath -cne $cache -or $after.flutterUrl -cne $script:HarmonyRepository) { throw 'FVM 实际绑定与计划不一致。' }
        $link = Get-Item -LiteralPath (Join-Path $inspection '.fvm/flutter_sdk') -Force
        $targets = @($link.Target)
        if (($link.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -or $targets.Count -ne 1) { throw 'FVM 没有建立唯一 SDK 链接。' }
        $linkedPath = [string]$targets[0]
        if (-not [IO.Path]::IsPathRooted($linkedPath)) { $linkedPath = Join-Path (Split-Path -Parent $link.FullName) $linkedPath }
        if (-not [StringComparer]::OrdinalIgnoreCase.Equals([IO.Path]::GetFullPath($linkedPath).TrimEnd('\','/'), [IO.Path]::GetFullPath($sdk).TrimEnd('\','/'))) { throw '项目 SDK 链接未指向所选缓存。' }
        $version = & $script:HarmonyManager { param($Fvm,$Path) Invoke-JobsFvmTool $Fvm @('flutter','--version','--machine') $Path -TimeoutSeconds 300 -LiveCapture } $chain.Fvm $inspection
        if ($version.ExitCode -ne 0) { throw '所选 SDK 初始化或版本体检失败。' }
        $actual = ConvertFrom-JobsSdkMachineOutput $version.StdOut
        if ($actual.frameworkRevision -cne $choice.Commit) { throw '实际 Flutter commit 与锁定版本不一致。' }
        $help = & $script:HarmonyManager { param($Fvm,$Path) Invoke-JobsFvmTool $Fvm @('flutter','build','hap','--help') $Path -TimeoutSeconds 120 } $chain.Fvm $inspection
        if ($help.ExitCode -ne 0 -or ($help.StdOut + $help.StdErr) -notmatch '\bhap\b') { throw '所选 SDK 不提供 build hap；已停止。' }
        Assert-JobsHarmonySdk $chain.Git $sdk $choice.Commit $project
        Publish-JobsHarmonyBinding $project $sdk (($after | ConvertTo-Json -Depth 100) + [Environment]::NewLine) $stamp
        Write-JobsEnterChoiceText ('成功：当前项目绑定 ' + $choice.Ref + ' / ' + $choice.Commit)
        Write-JobsEnterChoiceText '接下来可执行鸿蒙 Flutter 环境体检；SDK 切换不代表插件、DevEco、签名或 HAP 构建已通过。'
    } finally {
        if ($inspection -and [IO.Directory]::Exists($inspection)) {
            try { Remove-JobsHarmonyEntry $inspection }
            catch { Write-Warning ('影子目录清理未完成，保留供核对：' + $inspection) }
        }
        if ($lock) { $lock.Dispose() }
        foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
        [Net.ServicePointManager]::SecurityProtocol = $savedTls
    }
}
function Test-JobsManagedHarmonyBinding {
    param([string]$Project)
    $config = & $script:HarmonyManager { param($Path) Get-JobsProjectFvmConfig $Path } $Project
    if (-not $config.PSObject.Properties['flutter'] -or -not $config.PSObject.Properties['flutterUrl'] -or -not $config.PSObject.Properties['cachePath']) { return $false }
    return [string]$config.flutter -cmatch '^custom_jobs_ohos_[0-9a-f]{40}$' -and
        [string]$config.flutterUrl -ceq $script:HarmonyRepository -and
        [StringComparer]::OrdinalIgnoreCase.Equals([string]$config.cachePath, (Get-JobsHarmonyCache))
}
# 沿所选宿主SDK流程准备和执行，保持原配置与取消传播。
function Invoke-JobsNativeSdkFromHarmony {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Target)
    $project = & $script:HarmonyManager { param($Path) Assert-JobsFvmDirectory (Resolve-JobsTarget $Path) } $Target
    Assert-JobsHarmonyBindingPaths $project
    if (-not (Test-JobsManagedHarmonyBinding $project)) { throw '不是本工具管理的 CPF OpenHarmony 绑定，未迁移未知 fork。' }
    $official = 'https://github.com/flutter/flutter.git'
    $cache = Join-Path (Split-Path -Parent (Get-JobsHarmonyCache)) 'official'
    $stamp = Get-JobsHarmonyBindingStamp $project
    Write-JobsEnterChoiceText ('从 OpenHarmony 切回原生 Flutter；精确项目：' + $project)
    Write-JobsEnterChoiceText ('官方 SDK 来源：' + $official + '；隔离缓存：' + $cache)
    Write-JobsEnterChoiceText '先在影子项目选择并验证官方 SDK，成功后仅发布 .fvmrc 与 SDK 联接；保留 IDE、ignore、源码和其它元数据。'
    $saved = @{}
    foreach ($key in @('PATH','FVM_CACHE_PATH','FVM_FLUTTER_URL','FVM_USE_GIT_CACHE')) { $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
    $savedTls = [Net.ServicePointManager]::SecurityProtocol
    $inspection = $null; $lock = $null
    try {
        [Net.ServicePointManager]::SecurityProtocol = $savedTls -bor [Net.SecurityProtocolType]::Tls12
        $root = & $script:HarmonyManager { Get-JobsInstallRoot }
        [void][IO.Directory]::CreateDirectory($root)
        try { $lock = [IO.File]::Open((Join-Path $root 'operation.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
        catch { throw '另一 FVM 操作正在运行，请稍后重试。' }
        $inspection = & $script:HarmonyManager { param($Path) New-JobsFvmInspection $Path } $project
        $config = & $script:HarmonyManager { param($Path) Get-JobsProjectFvmConfig $Path } $inspection
        $config.PSObject.Properties.Remove('flutter')
        $config | Add-Member -NotePropertyName 'cachePath' -NotePropertyValue $cache -Force
        $config | Add-Member -NotePropertyName 'flutterUrl' -NotePropertyValue $official -Force
        $config | Add-Member -NotePropertyName 'updateMelosSettings' -NotePropertyValue $false -Force
        $config | Add-Member -NotePropertyName 'useGitCache' -NotePropertyValue $false -Force
        [IO.File]::WriteAllText((Join-Path $inspection '.fvmrc'), ($config | ConvertTo-Json -Depth 100), (New-Object Text.UTF8Encoding($false)))
        $env:FVM_CACHE_PATH = $cache; $env:FVM_FLUTTER_URL = $official; $env:FVM_USE_GIT_CACHE = 'false'
        $chain = & $script:HarmonyManager { param($Path) Get-JobsFvmToolchain $Path $Path } $inspection
        if ($chain.Context.flutterUrl -cne $official -or -not [StringComparer]::OrdinalIgnoreCase.Equals([string]$chain.Context.versionsCachePath, (Join-Path $cache 'versions'))) { throw '影子项目的官方来源或缓存未生效，未修改真实项目。' }
        $cached = @(& $script:HarmonyManager { param($Fvm,$Path) Get-JobsFvmCachedVersions $Fvm $Path } $chain.Fvm $inspection)
        $choices = @(& $script:HarmonyManager { param($Cached) Get-JobsFlutterReleaseChoices $Cached '(OpenHarmony)' } $cached)
        $versionState = @{}
        while ($true) {
            $choice = & $script:HarmonyManager { param($Fzf,$Choices,$Path,$State) Select-JobsFlutterVersion $Fzf $Choices $Path -State $State } $chain.Fzf $choices $inspection $versionState
            if ($null -eq $choice) { Write-JobsEnterChoiceText '已取消，OpenHarmony 绑定保持原样。'; return }
            Write-JobsEnterChoiceText ('计划：OpenHarmony → 官方 Flutter ' + $choice.Version + '；来源：' + $official + '；缓存：' + $cache)
            $confirmation = & $script:HarmonyManager { param($Child) Select-JobsFzfItems '确认切回原生 Flutter（默认取消）' @('按以上精确版本、来源与写入范围继续') -RequireConfirmation -Child:$Child } ($choices.Count -gt 1)
            if ($confirmation.Action -ceq 'back') { continue }
            if ($confirmation.Action -cne 'selected') { Write-JobsEnterChoiceText '已取消，OpenHarmony 绑定保持原样。'; return }
            break
        }
        Assert-JobsHarmonyBindingPaths $project
        if ((Get-JobsHarmonyBindingStamp $project) -cne $stamp) { throw '选版期间真实项目绑定已改变，未发布。' }
        & $script:HarmonyManager { param($Path,$Version) Set-JobsProjectFvmVersion $Path $Version } $inspection $choice.Version
        $pinned = & $script:HarmonyManager { param($Path) Get-JobsProjectFvmConfig $Path } $inspection
        if (-not $choice.Ready) {
            if ($choice.Offline) { throw '离线模式下缺少就绪官方 SDK，未切换。' }
            $install = & $script:HarmonyManager { param($Fvm,$Version,$Path) Invoke-JobsFvmTool $Fvm @('install',$Version,'--skip-pub-get') $Path -Visible -TimeoutSeconds 3600 } $chain.Fvm $choice.Version $inspection
            if ($install.ExitCode -ne 0) { throw '官方 SDK 安装失败，真实项目保持 OpenHarmony 绑定。' }
        }
        $use = & $script:HarmonyManager { param($Fvm,$Version,$Path) Invoke-JobsFvmTool $Fvm @('use',$Version,'--skip-setup','--skip-pub-get') $Path -Visible -TimeoutSeconds 300 } $chain.Fvm $choice.Version $inspection
        if ($use.ExitCode -ne 0) { throw '官方 SDK 绑定失败，真实项目保持 OpenHarmony 绑定。' }
        $after = & $script:HarmonyManager { param($Path) Get-JobsProjectFvmConfig $Path } $inspection
        foreach ($property in $pinned.PSObject.Properties) {
            if ($null -eq $after.PSObject.Properties[$property.Name]) { $after | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value }
        }
        if ($after.flutter -cne $choice.Version -or $after.flutterUrl -cne $official -or $after.cachePath -cne $cache) { throw '影子项目官方绑定与所选版本不一致。' }
        $sdk = Join-Path (Join-Path $cache 'versions') $choice.Version
        [void](& $script:HarmonyManager { param($Path) Assert-JobsFvmDirectory $Path } $sdk)
        $link = Get-Item -LiteralPath (Join-Path $inspection '.fvm/flutter_sdk') -Force
        $targets = @($link.Target)
        if (($link.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -or $targets.Count -ne 1) { throw '官方 FVM SDK 联接无效。' }
        $actualPath = [string]$targets[0]
        if (-not [IO.Path]::IsPathRooted($actualPath)) { $actualPath = Join-Path (Split-Path -Parent $link.FullName) $actualPath }
        if (-not [StringComparer]::OrdinalIgnoreCase.Equals([IO.Path]::GetFullPath($actualPath).TrimEnd('\','/'), [IO.Path]::GetFullPath($sdk).TrimEnd('\','/'))) { throw '官方 SDK 联接超出所选缓存。' }
        if ((Invoke-JobsHarmonyGit $chain.Git @('-C',$sdk,'remote','get-url','origin') $inspection) -cnotin @($official,'https://github.com/flutter/flutter')) { throw 'SDK 缓存来源不是官方 Flutter，未发布。' }
        $version = & $script:HarmonyManager { param($Fvm,$Path) Invoke-JobsFvmTool $Fvm @('flutter','--version','--machine') $Path -TimeoutSeconds 300 -LiveCapture } $chain.Fvm $inspection
        if ($version.ExitCode -ne 0 -or (ConvertFrom-JobsSdkMachineOutput $version.StdOut).frameworkVersion -cne $choice.Version) { throw '官方 SDK 实际版本不匹配，真实项目保持原绑定。' }
        Publish-JobsHarmonyBinding $project $sdk (($after | ConvertTo-Json -Depth 100) + [Environment]::NewLine) $stamp
        Write-JobsEnterChoiceText ('成功：当前项目已切回官方 Flutter ' + $choice.Version + '；OpenHarmony SDK 缓存保留，可从相邻菜单切回。')
    } finally {
        if ($inspection -and [IO.Directory]::Exists($inspection)) {
            try { Remove-JobsHarmonyEntry $inspection }
            catch { Write-Warning ('影子目录清理未完成，保留供核对：' + $inspection) }
        }
        if ($lock) { $lock.Dispose() }
        foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
        [Net.ServicePointManager]::SecurityProtocol = $savedTls
    }
}
Export-ModuleMember -Function Invoke-JobsHarmonySdkAction, Invoke-JobsNativeSdkFromHarmony, Test-JobsManagedHarmonyBinding

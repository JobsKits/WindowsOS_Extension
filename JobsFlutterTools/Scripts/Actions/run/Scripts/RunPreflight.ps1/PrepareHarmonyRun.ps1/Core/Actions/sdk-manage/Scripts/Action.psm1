# Action.psm1
# JobsFlutterVersionMgr
# Created by Jobs on 2026年10月19日，星期一.
# 在精确 Flutter 项目根选择并绑定 SDK；不设置 FVM 全局版本。


# Jobs enter-choice emphasis is display-only; input and business decisions stay with callers.

# 源包装与已发布 flat 布局共用路径，兼容旧收据且不跟随包装目录链接。
# JOBS_FZF_SELECTION_CORE_V1_BEGIN
# 将选择器诊断交给当前业务日志，先剥离控制码并脱敏展示地址。
# JOBS_WINGET_NECESSARY_NATIVE_V1_BEGIN
# 按Windows原生argv规则保留参数边界，不通过命令字符串求值。
function ConvertTo-JobsWingetNativeArgument {
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
# 隔离原生工具健康探针并限制单次时长，不改父进程环境。
function Invoke-JobsWingetNativeProbe {
    param([string]$Executable, [string[]]$NativeArguments, [string[]]$InputLines = @(), [switch]$Probe)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Executable
    $start.Arguments = (@($NativeArguments | ForEach-Object { ConvertTo-JobsWingetNativeArgument $_ }) -join ' ')
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
                return [pscustomobject]@{ Code = 124; Lines = @(); Error = '原生工具健康探针超时（10 秒）。' }
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
# 只刷新当前进程的原生工具路径，不持久化环境变更。
function Update-JobsWingetNativePath {
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
# 只读发现当前用户已注册且能够运行的WinGet。
function Find-JobsNativeWinget {
    $command = Get-Command 'winget.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $candidates = @()
    if ($command) { $candidates += $command.Source }
    if ($env:LOCALAPPDATA) { $candidates += Join-Path $env:LOCALAPPDATA 'Microsoft/WindowsApps/winget.exe' }
    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if (-not [IO.File]::Exists($candidate)) { continue }
        try { $probe = Invoke-JobsWingetNativeProbe $candidate @('--version') -Probe; if ($probe.Code -eq 0) { return $candidate } } catch [Management.Automation.PipelineStoppedException] { throw } catch { }
    }
    return $null
}
# 仅必需安装分支准备当前用户App Installer，一次打开官方界面并等待复检。
function Get-JobsNativeRequiredWinget {
    $winget = Find-JobsNativeWinget
    if ($winget) { return $winget }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw '当前不是 Windows，未调用 App Installer 或安装 Windows 依赖。' }
    Write-JobsWingetNativeStatus '本次需要 Windows 原生 App Installer/winget；仅注册当前用户已有组件，不接受许可或修改系统策略。'
    $registration = Get-Command Add-AppxPackage -ErrorAction SilentlyContinue
    if ($registration -and $registration.Parameters.ContainsKey('RegisterByFamilyName')) {
        try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop } catch { Write-JobsWingetNativeStatus ('App Installer 注册未就绪：' + $_.Exception.Message) }
        $winget = Find-JobsNativeWinget
        if ($winget) { Update-JobsWingetNativePath ([IO.Path]::GetDirectoryName($winget)); return $winget }
    }
    Write-JobsWingetNativeStatus '官方 App Installer：https://apps.microsoft.com/detail/9NBLGGH4NNS1；将打开一次官方页面。请按系统要求完成安装/许可，本入口持续复检并续行，Ctrl+C 停止等待。'
    Start-Process -FilePath 'ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1' -ErrorAction Stop | Out-Null
    while ($true) {
        Update-JobsWingetNativePath
        $winget = Find-JobsNativeWinget
        if ($winget) { return $winget }
        Write-JobsWingetNativeStatus '等待官方 App Installer 安装和当前用户注册；不会重复打开窗口，Ctrl+C 取消。'
        Start-Sleep -Seconds 3
    }
}
# 将原生包管理诊断安全送往业务展示与纯文本日志。
function Write-JobsWingetNativeStatus {
    [CmdletBinding()]
    param([string]$Text)
    $plain=$Text -replace '\x1b\][^\x07]*(?:\x07|\x1b\\)', '' -replace '\x1b\[[0-?]*[ -/]*[@-~]', ''
    $plain=$plain -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@' -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]' -replace '(?im)((?:token|password|secret|authorization)\s*[:=]\s*)\S+', '$1[已省略]'
    foreach($name in @('Write-JobsFvmMessage','Write-JobsSetupMessage','Write-JobsWorkerMessage','Write-JobsStatus','Write-JobsLog')){
        $writer=Get-Command $name -CommandType Function -ErrorAction SilentlyContinue
        if($writer){&$writer $plain;return}
    }
    Write-Host $plain
}
# 捕获展示副本但保持原生stdin与许可交互；不传accept/disable，不自动接受许可或提升权限。
function Invoke-JobsNativeWinget {
    param([string]$Winget,[string[]]$Arguments)
    $text=New-Object Collections.Generic.List[string];$saved=$ErrorActionPreference;$failure=$null;$PSNativeCommandUseErrorActionPreference=$false
    try {
        $ErrorActionPreference='Continue';$global:LASTEXITCODE=-1
        &$Winget @Arguments 2>&1|ForEach-Object {$line=[string]$_;$text.Add($line);try{Write-JobsWingetNativeStatus $line -ErrorAction Stop}catch{$failure=$_.Exception;throw}}
        $code=$LASTEXITCODE
    }finally{$ErrorActionPreference=$saved}
    if($failure){throw $failure}
    return [pscustomobject]@{Code=$code;Text=($text-join"`n")}
}
# 只对必要工具的临时获取故障持续重试，取消和确定阻塞立即停止。
function Invoke-JobsNativeWingetRetry {
    param([string]$Winget,[string[]]$Arguments)
    $delay=1
    while($true){
        $result=Invoke-JobsNativeWinget $Winget $Arguments
        if($result.Code-in@(129,130,137,143,1223,1602,-1073741510,-2147023673)){throw(New-Object OperationCanceledException('本人已取消原生包管理操作。'))}
        if($result.Code-in@(3010,1641)){throw '包管理器要求重启，请本人处理后继续；不会自动重启。'}
        if($result.Code-eq0){return $result}
        $plain=$result.Text -replace '\x1b\][^\x07]*(?:\x07|\x1b\\)', '' -replace '\x1b\[[0-?]*[ -/]*[@-~]', ''
        $plain=$plain -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@' -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]' -replace '(?im)((?:token|password|secret|authorization)\s*[:=]\s*)\S+', '$1[已省略]'
        if($plain-match'(?i)permission|access.denied|no.space|disk.full|hash|checksum|certificate|unauthor|license|agreement|unsupported|not.supported|unknown.command|unrecognized|no.applicable|no.package|no.installed.package|not.found|already.installed|no.available.upgrade|requires?.*reboot|权限|拒绝|空间不足|许可|协议|不支持|未知命令|无法找到|找不到|没有找到|不存在|无适用|已安装|需要重启') {throw ('原生包管理遇到明确阻塞，退出码 '+$result.Code+'：'+$plain)}
        Write-JobsWingetNativeStatus ('包管理网络获取失败；'+$delay+'秒后沿当前流程重试，Ctrl+C停止。')
        Start-Sleep -Seconds $delay;$delay=[Math]::Min(30,$delay*2)
    }
}
# JOBS_WINGET_NECESSARY_NATIVE_V1_END

# 将选择器诊断送往当前业务日志，剥离控制码并隐藏敏感地址。
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

# 将版本管理诊断安全写入当前展示流与纯文本日志。
function Write-JobsFvmMessage {
    param([string]$Message)
    $Message = $Message -replace '\x1b\][^\x07]*(?:\x07|\x1b\\)', '' -replace '\x1b\[[0-?]*[ -/]*[@-~]', ''
    $Message = $Message -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@' -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]' -replace '(?im)((?:token|password|secret|authorization)\s*[:=]\s*)\S+', '$1[已省略]'
    $safe = $Message -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@'
    $safe = $safe -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]'
    $safe = $safe -replace '(?im)((?:token|password|secret|authorization)\s*[:=]\s*)\S+', '$1[已省略]'
    Write-JobsEnterChoiceText $safe
    $logs = Join-Path (Get-JobsInstallRoot) 'logs'
    [void][IO.Directory]::CreateDirectory($logs)
    if (-not (Get-Variable -Name FvmSessionLog -Scope Script -ErrorAction SilentlyContinue)) {
        $script:FvmSessionLog = Join-Path $logs ('fvm-' + (Get-Date -Format 'yyyy-MM-dd-HH-mm-ss') + '-' + [guid]::NewGuid().ToString('N') + '.log')
    }
    [IO.File]::AppendAllText($script:FvmSessionLog, ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $safe + [Environment]::NewLine), (New-Object Text.UTF8Encoding($true)))
}

function Assert-JobsFvmDirectory {
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

function Assert-JobsFvmPlainFile {
    param([string]$Path)
    $attributes = [IO.File]::GetAttributes($Path)
    if (($attributes -band [IO.FileAttributes]::Directory) -ne 0 -or ($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "配置必须是普通文件：$Path"
    }
}

function Test-JobsFvmPathEntry {
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
    foreach ($part in $parts) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
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
    # 只解释 dependencies.flutter.sdk，不能把 description、注释或 flutter_test 当作 Flutter 项目。
    $lines = @($Text -split '\r?\n' | ForEach-Object { Remove-JobsYamlComment $_ })
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
            if ($lines[$i] -notmatch '^(?<indent> +)(?<key>[A-Za-z_][A-Za-z0-9_-]*|''[^'']+''|"[^"\\]+")\s*:\s*(?<value>.*)$') { continue }
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
    [void](Assert-JobsFvmDirectory $Directory)
    $pubspec = Join-Path $Directory 'pubspec.yaml'
    Assert-JobsFvmPlainFile $pubspec
    if (-not (Test-JobsFlutterPubspec (Get-Content -LiteralPath $pubspec -Raw -Encoding UTF8))) {
        throw '目标同层 pubspec.yaml 必须明确声明 dependencies.flutter.sdk: flutter；不会扫描子目录或沿用父工程。YAML 别名、标签及多行 flow 映射请先改成常见 block 写法。'
    }
}

# 安装 SDK 和首次初始化自动完成；项目切换写入及普通查询仍只执行一次。
function Invoke-JobsFvmTool {
    param([string]$File, [string[]]$Arguments = @(), [string]$Directory, [switch]$Visible, [int]$TimeoutSeconds = 30, [switch]$LiveCapture)
    $acquire = $Arguments.Count -gt 0 -and ($Arguments[0] -ceq 'install' -or ($Arguments[0] -ceq 'flutter' -and $Arguments.Count -gt 1 -and $Arguments[1] -in @('--version','precache')))
    if ($acquire -and $Arguments[0] -ceq 'install') {
        $help = Invoke-JobsFvmToolOnce $File @('install','--help') $Directory -TimeoutSeconds 30
        if ($help.ExitCode -eq 0 -and ($help.StdOut + $help.StdErr) -match '--\[no-\]setup|--no-setup' -and $Arguments -notcontains '--no-setup') {
            $Arguments += '--no-setup'
            Write-JobsFvmMessage 'FVM已确认支持--no-setup：Git SDK获取与后续Dart/engine自举分阶段预检，不改Git来源。'
        }
    }
    if ($acquire) {
        return Invoke-JobsSdkAcquire -Label ('Flutter SDK：' + ($Arguments -join ' ')) -Operation {
            $result = Invoke-JobsFvmToolOnce $File $Arguments $Directory -TimeoutSeconds ([Math]::Max(120,$TimeoutSeconds)) -LiveCapture -Acquisition
            if ($result.ExitCode -eq 0 -and $Arguments[0] -ceq 'install') {
                $probe = Invoke-JobsFvmToolOnce $File @('api','context','--compress') $Directory -TimeoutSeconds 30
                if ($probe.ExitCode -ne 0) { throw 'FVM 缓存上下文无效，SDK 管理器需要人工修复。' }
                $context = ($probe.StdOut | ConvertFrom-Json -ErrorAction Stop).context
                if (-not [IO.Path]::IsPathRooted([string]$context.versionsCachePath)) { throw 'FVM 缓存上下文无效，缺少绝对 SDK 缓存目录。' }
                $sdk = Join-Path $context.versionsCachePath $Arguments[1]
                if (-not [IO.File]::Exists((Join-Path $sdk 'bin/flutter.bat')) -and -not [IO.File]::Exists((Join-Path $sdk 'bin/flutter.exe'))) { throw ('FVM 返回成功但 SDK 的 bin/flutter 尚未获取完整：' + $sdk) }
            }
            return $result
        }
    }
    return Invoke-JobsFvmToolOnce $File $Arguments $Directory -Visible:$Visible -TimeoutSeconds $TimeoutSeconds -LiveCapture:$LiveCapture
}

function Invoke-JobsFvmToolOnce {
    param([string]$File, [string[]]$Arguments = @(), [string]$Directory, [switch]$Visible, [int]$TimeoutSeconds = 30, [switch]$LiveCapture, [switch]$Acquisition)
    if ($File -match '["\x00-\x1f]' -or @($Arguments | Where-Object { $_ -cnotmatch '^[A-Za-z0-9._@:+-]+$' }).Count -gt 0) {
        throw '工具路径或参数包含不支持的控制字符。'
    }
    $executable = $File
    $parameters = $Arguments
    $batch = [IO.Path]::GetExtension($File) -in @('.cmd', '.bat')
    if ($batch) {
        $executable = Join-Path ([Environment]::GetFolderPath('System')) 'cmd.exe'
        $parameters = @('/d', '/v:off', '/s', '/c')
    }
    if ([IO.Path]::GetFileName($File) -match '^fvm(\.(bat|cmd|ps1|exe))?$') {
        Import-JobsSdkDownloadRoute
        Initialize-JobsSdkFvmRuntime $File $Directory (Get-JobsSdkRouteEnvironment)
    }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $executable
    if ($batch) {
        $start.EnvironmentVariables['JOBS_FVM_EXECUTABLE'] = $File
        $start.Arguments = '/d /v:off /s /c ""%JOBS_FVM_EXECUTABLE%" ' + ($Arguments -join ' ') + '"'
    }
    else { $start.Arguments = (@($parameters | ForEach-Object { Quote-JobsArgument $_ }) -join ' ') }
    $start.WorkingDirectory = $Directory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = -not $Visible
    $start.RedirectStandardOutput = -not $Visible
    $start.RedirectStandardError = -not $Visible
    if (-not $Visible) {
        $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
        $start.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    }
    $start.EnvironmentVariables['CI'] = 'true'
    $start.EnvironmentVariables['FLUTTER_SUPPRESS_ANALYTICS'] = 'true'
    $start.EnvironmentVariables['DART_SUPPRESS_ANALYTICS'] = 'true'
    if ($LiveCapture) { return Invoke-JobsSdkLiveProcess $start $TimeoutSeconds -Acquisition:$Acquisition }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw '无法启动工具。' }
        if (-not $Visible) {
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
        }
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $taskkill = Join-Path ([Environment]::GetFolderPath('System')) 'taskkill.exe'
            [void](Invoke-JobsProcess $taskkill @('/PID', [string]$process.Id, '/T', '/F') -WorkingDirectory $Directory)
            throw '操作超时；已尝试终止本次进程树，请检查终端和日志。'
        }
        $output = ''
        $errors = ''
        if (-not $Visible) {
            if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout, $stderr), 5000)) { throw '工具输出管道未按时关闭。' }
            $output = $stdout.GetAwaiter().GetResult()
            $errors = $stderr.GetAwaiter().GetResult()
        }
        return [pscustomobject]@{ ExitCode = $process.ExitCode; StdOut = $output; StdErr = $errors }
    }
    finally { $process.Dispose() }
}

function Find-JobsHealthyFvmTool {
    param([string]$Name, [string[]]$Candidates, [string]$Directory)
    $paths = @()
    foreach ($candidate in @($Name) + $Candidates) {
        $path = Find-JobsExecutable -Name $candidate -Candidates @()
        if (-not $path -or $path -in $paths) { continue }
        $paths += $path
        try {
            $result = Invoke-JobsFvmTool $path @('--version') $Directory
            if ($result.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($result.StdOut + $result.StdErr)) {
                Write-JobsFvmMessage ("健康：{0} → {1}；{2}" -f $Name, $path, ($result.StdOut + $result.StdErr).Trim())
                return $path
            }
        }
        catch { Write-JobsFvmMessage "体检失败：$path" }
    }
    return $null
}

function Update-JobsFvmSessionPath {
    # 安装器通常更新注册表 PATH；只将新增目录并入当前进程，不覆盖进程原有路径。
    $paths = @($env:PATH -split [IO.Path]::PathSeparator)
    foreach ($scope in @('User', 'Machine')) {
        $paths += @([Environment]::GetEnvironmentVariable('PATH', $scope) -split [IO.Path]::PathSeparator)
    }
    $paths += @((Join-Path $env:LOCALAPPDATA 'Microsoft/WinGet/Links'), (Join-Path $env:LOCALAPPDATA 'Programs/Git/cmd'))
    $env:PATH = (@($paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique) -join [IO.Path]::PathSeparator)
}
# 保留原单次确认，只获取所需Git或Chrome并在当前流程复检。
function Install-JobsWingetTool {
    param([string]$Id,[string]$Directory)
    if($Id-notin@('Git.Git','Google.Chrome')){throw ('未声明的必需工具：'+$Id)}
    Write-JobsFvmMessage "安装来源：WinGet 官方 winget 源；包：$Id；范围：当前用户。仅本次必要分支获取，许可沿原生安装器。"
    if((Read-JobsEnterChoiceHost "缺少必需组件 $Id；回车安装，任意字符取消整个流程")-cne''){throw(New-Object OperationCanceledException('已取消必需组件安装。'))}
    $winget=Get-JobsNativeRequiredWinget
    [void](Invoke-JobsNativeWingetRetry $winget @('install','--id',$Id,'--exact','--source','winget','--scope','user','--force','--interactive'))
    Update-JobsFvmSessionPath
    Update-JobsWingetNativePath
    if($Id-ceq'Git.Git'){
        $candidates=@()
        if($env:LOCALAPPDATA){$candidates+=Join-Path $env:LOCALAPPDATA 'Programs/Git/cmd/git.exe'}
        if($env:ProgramFiles){$candidates+=Join-Path $env:ProgramFiles 'Git/cmd/git.exe'}
        if(-not(Find-JobsHealthyFvmTool 'git.exe' $candidates $Directory)){throw 'Git安装后实际版本复检失败，未继续下游。'}
    }else{
        $ready=$false
        foreach($root in @($env:LOCALAPPDATA,$env:ProgramFiles,${env:ProgramFiles(x86)})){
            if(-not$root){continue};$chrome=Join-Path $root 'Google/Chrome/Application/chrome.exe'
            if([IO.File]::Exists($chrome)-and[Diagnostics.FileVersionInfo]::GetVersionInfo($chrome).FileVersion-match'^\d+\.'){$ready=$true;break}
        }
        if(-not$ready){throw 'Chrome安装后文件版本复检失败，未继续下游。'}
    }
}

function Read-JobsFvmWebJson {
    param([string]$Uri)
    Write-JobsFvmMessage "查询来源：$Uri"
    $response = Invoke-JobsSdkAcquire -Label ('SDK 元数据：' + $Uri) -Operation { Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec 20 -Headers @{ 'User-Agent' = 'JobsFlutterVersionMgr'; 'Accept' = 'application/json' } }
    return $response.Content | ConvertFrom-Json -ErrorAction Stop
}

function Install-JobsStandaloneFvm {
    param([string]$Directory)
    $architecture = $env:PROCESSOR_ARCHITEW6432
    if ([string]::IsNullOrWhiteSpace($architecture)) { $architecture = $env:PROCESSOR_ARCHITECTURE }
    switch ($architecture.ToUpperInvariant()) {
        'AMD64' { $architecture = 'x64' }
        'ARM64' { $architecture = 'arm64' }
        default { throw '官方 FVM 独立包仅支持 Windows x64 / ARM64，请使用 64 位系统。' }
    }
    $release = Read-JobsFvmWebJson 'https://api.github.com/repos/btwld/fvm/releases/latest'
    if ($release.tag_name -cnotmatch '^v?\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$') { throw 'FVM release 版本格式无效。' }
    $assets = @($release.assets | Where-Object { $_.name -match ('^fvm-.*-windows-' + $architecture + '\.zip$') })
    if ($assets.Count -ne 1) { throw '未找到唯一的官方 FVM Windows 架构包。' }
    $asset = $assets[0]
    if ($asset.browser_download_url -cnotmatch '^https://github\.com/(?:btwld|leoafarias)/fvm/releases/download/[^/]+/fvm-[^/]+\.zip$' -or
        $null -eq $asset.PSObject.Properties['digest'] -or $asset.digest -cnotmatch '^sha256:[a-f0-9]{64}$') {
        throw 'FVM 包来源或官方 SHA-256 digest 不可验证，已停止。'
    }
    Write-JobsFvmMessage ("FVM 来源：{0}；架构：{1}；SHA-256：{2}" -f $asset.browser_download_url, $architecture, $asset.digest)
    Write-JobsFvmMessage '缺少健康 FVM，自动下载官方独立包；Ctrl+C 可停止。'
    $tools = Join-Path (Get-JobsInstallRoot) 'tools'
    [void][IO.Directory]::CreateDirectory($tools)
    $stage = Join-Path $tools ('fvm-stage-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($stage)
    $complete = $false
    try {
        $zip = Join-Path $stage 'fvm.zip'
        Receive-JobsSdkWebFile $asset.browser_download_url $zip 300 -ExpectedSha256 $asset.digest.Substring(7)
        if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant() -cne $asset.digest.Substring(7)) { throw '官方 FVM 下载包 SHA-256 不匹配。' }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($zip)
        try {
            foreach ($entry in $archive.Entries) {
                $path = $entry.FullName.Replace('\', '/')
                if ($path.StartsWith('/') -or $path -match '(^|/)\.\.(/|$)|:') { throw 'FVM 压缩包含越界路径。' }
            }
        }
        finally { $archive.Dispose() }
        $expanded = Join-Path $stage 'expanded'
        Expand-Archive -LiteralPath $zip -DestinationPath $expanded
        $executables = @(Get-ChildItem -LiteralPath $expanded -Recurse -File -Filter 'fvm.exe')
        if ($executables.Count -ne 1) { throw '官方 FVM 压缩包未包含唯一 fvm.exe。' }
        $check = Invoke-JobsFvmTool $executables[0].FullName @('--version') $Directory
        if ($check.ExitCode -ne 0) { throw '下载的 FVM 无法执行。' }
        $destination = Join-Path $tools ('fvm-' + $release.tag_name + '-' + [guid]::NewGuid().ToString('N'))
        Move-Item -LiteralPath $expanded -Destination $destination
        $relative = $executables[0].FullName.Substring($expanded.Length).TrimStart([char]92, [char]47)
        $installed = Join-Path $destination $relative
        [IO.File]::WriteAllText((Join-Path $tools 'fvm-path.txt'), $installed, (New-Object Text.UTF8Encoding($false)))
        $complete = $true
        return $installed
    }
    finally { if ($complete -and (Test-Path -LiteralPath $stage)) { Remove-Item -LiteralPath $stage -Recurse -Force } elseif (Test-Path -LiteralPath $stage) { Write-JobsFvmMessage ('未完成 FVM 下载保留：' + $stage) } }
}
# 准备当前版本操作必需工具，健康安装复用并逐项复检。
function Get-JobsFvmToolchain {
    param([string]$Directory, [string]$InspectionDirectory)
    $gitCandidates = @((Join-Path $env:LOCALAPPDATA 'Programs/Git/cmd/git.exe'))
    if ($env:ProgramFiles) { $gitCandidates += Join-Path $env:ProgramFiles 'Git/cmd/git.exe' }
    $git = Find-JobsHealthyFvmTool 'git.exe' $gitCandidates $Directory
    if (-not $git) { Install-JobsWingetTool 'Git.Git' $Directory; $git = Find-JobsHealthyFvmTool 'git.exe' $gitCandidates $Directory }
    if (-not $git) { throw 'Git 安装后二次体检失败，已停止。' }
    # 健康但原本不在 PATH 的 Git 必须让 FVM 子进程可见。
    $env:PATH = (Split-Path -Parent $git) + [IO.Path]::PathSeparator + $env:PATH
    $fzf = Ensure-JobsFzf
    $candidates = @('fvm.bat', 'fvm.cmd')
    $pointer = Join-Path (Get-JobsInstallRoot) 'tools/fvm-path.txt'
    if (Test-Path -LiteralPath $pointer -PathType Leaf) { $candidates += (Get-Content -LiteralPath $pointer -Raw -Encoding UTF8).Trim() }
    $fvm = Find-JobsHealthyFvmTool 'fvm.exe' $candidates $Directory
    if (-not $fvm) { $fvm = Install-JobsStandaloneFvm $Directory }
    $check = Invoke-JobsFvmTool $fvm @('api', 'context', '--compress') $InspectionDirectory
    if ($check.ExitCode -ne 0) { throw 'FVM 版本存在但 JSON API 不健康，请修复或升级 FVM 后重试。' }
    try { $context = ($check.StdOut | ConvertFrom-Json -ErrorAction Stop).context }
    catch { throw 'FVM api context 无法解析。' }
    if ($null -eq $context -or $null -eq $context.PSObject.Properties['flutterUrl']) { throw 'FVM 未提供有效下载来源。' }
    if ($null -eq $context.PSObject.Properties['versionsCachePath'] -or -not [IO.Path]::IsPathRooted([string]$context.versionsCachePath)) {
        throw 'FVM 有效 SDK 缓存必须是绝对路径，请检查项目、全局配置及 FVM_CACHE_PATH。'
    }
    Write-JobsFvmMessage ("FVM SDK Git 来源：{0}；缓存目录：{1}" -f $context.flutterUrl, $context.versionsCachePath)
    return [pscustomobject]@{ Git = $git; Fzf = $fzf; Fvm = $fvm; Context = $context }
}

function Test-JobsFlutterVersion {
    param([string]$Version)
    return $Version -cmatch '^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$'
}

function Get-JobsFvmCachedVersions {
    param([string]$Fvm, [string]$Directory)
    $result = Invoke-JobsFvmTool $Fvm @('api', 'list', '--compress', '--skip-size-calculation') $Directory
    if ($result.ExitCode -ne 0) { throw '无法读取 FVM 已缓存 SDK 列表。' }
    $data = $result.StdOut | ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $data.PSObject.Properties['versions']) { throw 'FVM 缓存清单缺少 versions。' }
    foreach ($version in @($data.versions)) {
        if (-not (Test-JobsFlutterVersion ([string]$version.name))) { continue }
        $ready = $null -ne $version.PSObject.Properties['isSetup'] -and $version.isSetup -eq $true
        $directoryPath = [string]$version.directory
        $ready = $ready -and [IO.File]::Exists((Join-Path $directoryPath 'bin/flutter.bat')) -and [IO.File]::Exists((Join-Path $directoryPath 'bin/cache/dart-sdk/bin/dart.exe'))
        [pscustomobject]@{ Version = [string]$version.name; Ready = $ready; Directory = $directoryPath }
    }
}

function ConvertFrom-JobsFlutterManifest {
    param($Manifest)
    if ($null -eq $Manifest.PSObject.Properties['releases'] -or $null -eq $Manifest.PSObject.Properties['current_release']) { throw 'Flutter 官方版本清单缺少必要字段。' }
    $seen = @{}
    foreach ($release in @($Manifest.releases | Sort-Object -Property release_date -Descending)) {
        $version = [string]$release.version
        if (-not (Test-JobsFlutterVersion $version) -or $release.channel -notin @('stable', 'beta', 'dev') -or $seen.ContainsKey($version)) { continue }
        $seen[$version] = $true
        $channel = [string]$release.channel
        $latest = $null -ne $Manifest.current_release.PSObject.Properties[$channel] -and $Manifest.current_release.$channel -ceq $release.hash
        [pscustomobject]@{ Version = $version; Channel = $channel; Date = ([string]$release.release_date).Split('T')[0]; Latest = $latest }
    }
    if ($seen.Count -eq 0) { throw 'Flutter 版本清单没有有效版本。' }
}

function Get-JobsFlutterReleaseChoices {
    param([object[]]$Cached, [string]$Current)
    $url = 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json'
    $offline = $false
    $releases = @()
    try { $releases = @(ConvertFrom-JobsFlutterManifest (Read-JobsFvmWebJson $url)) }
    catch {
        $offline = $true
        Write-JobsFvmMessage '官方历史/最新版本查询失败；仅提供已完成初始化的本机缓存，不能据此判断最新版本。'
    }
    $byVersion = @{}
    foreach ($entry in $Cached) { $byVersion[$entry.Version] = $entry }
    $choices = @()
    foreach ($release in $releases) {
        $cachedVersion = $byVersion[$release.Version]
        $ready = $null -ne $cachedVersion -and $cachedVersion.Ready
        $status = '需安装'
        if ($null -ne $cachedVersion) { $status = '缓存未完成初始化' }
        if ($ready) { $status = '已缓存/可切换' }
        if ($release.Latest) { $status += ' 最新' + $release.Channel }
        if ($release.Version -ceq $Current) { $status += ' 当前项目' }
        $choices += [pscustomobject]@{ Version = $release.Version; Ready = $ready; Offline = $false; Label = ($release.Version + ' | ' + $release.Channel + ' | ' + $release.Date + ' | ' + $status) }
    }
    foreach ($entry in $Cached) {
        if (-not $entry.Ready -or @($choices | Where-Object { $_.Version -ceq $entry.Version }).Count -gt 0) { continue }
        $status = '已缓存/可切换'
        if ($offline) { $status += ' 离线（最新未知）' }
        else { $status += ' 官方列表未列出' }
        if ($entry.Version -ceq $Current) { $status += ' 当前项目' }
        $choices += [pscustomobject]@{ Version = $entry.Version; Ready = $true; Offline = $offline; Label = ($entry.Version + ' | cache | - | ' + $status) }
    }
    if ($choices.Count -eq 0) { throw '没有可选择版本。请恢复网络后重新打开菜单。' }
    return $choices
}
# 保留版本查询与返回状态，默认取消并区分动作行与实际版本。
function Select-JobsFlutterVersion {
    param([string]$Fzf, [object[]]$Choices, [string]$Directory, [hashtable]$State = $null)
    $labels = @($Choices | ForEach-Object { [string]$_.Label })
    $selection = Select-JobsFzfItems -Title 'Flutter SDK' -Items $labels -State $State
    if ($selection.Action -cne 'selected') { return $null }
    $choice = @($Choices | Where-Object { $_.Label -ceq $selection.Items[0] })
    if ($choice.Count -ne 1) { throw 'fzf 返回了未知或不唯一的选择，已停止。' }
    return $choice[0]
}

function Get-JobsProjectFvmConfig {
    param([string]$Directory)
    $path = Join-Path $Directory '.fvmrc'
    if (-not (Test-JobsFvmPathEntry $path)) { $path = Join-Path $Directory '.fvm/fvm_config.json' }
    if (-not (Test-JobsFvmPathEntry $path)) { return [pscustomobject]@{} }
    Assert-JobsFvmPlainFile $path
    $config = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $config -or $config -is [array] -or $config -is [string] -or $config -is [ValueType]) { throw '.fvmrc 必须是 JSON 对象。' }
    # FVM 对旧键赋予更高优先级，迁移时须去掉别名以免旧版本覆盖新选择。
    if ($null -ne $config.PSObject.Properties['flutterSdkVersion']) {
        $config | Add-Member -NotePropertyName 'flutter' -NotePropertyValue $config.flutterSdkVersion -Force
        $config.PSObject.Properties.Remove('flutterSdkVersion')
    }
    return $config
}

function New-JobsFvmInspection {
    param([string]$Directory)
    $config = Get-JobsProjectFvmConfig $Directory
    if (-not [string]::IsNullOrWhiteSpace($env:FVM_CACHE_PATH) -and -not [IO.Path]::IsPathRooted($env:FVM_CACHE_PATH)) {
        throw 'FVM_CACHE_PATH 必须使用绝对路径，请先明确原缓存位置。'
    }
    if ($null -ne $config.PSObject.Properties['cachePath'] -and -not [string]::IsNullOrWhiteSpace([string]$config.cachePath) -and
        -not [IO.Path]::IsPathRooted([string]$config.cachePath)) {
        throw '项目 cachePath 必须使用绝对路径；请先明确原缓存位置，避免选版体检改变相对路径语义。'
    }
    $root = Join-Path (Get-JobsInstallRoot) ('inspection-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($root)
    try {
        # 空配置同样写入影子根，避免 API 上查目标真实目录的祖先配置。
        [IO.File]::WriteAllText((Join-Path $root '.fvmrc'), ($config | ConvertTo-Json -Depth 100 -WarningAction Stop), (New-Object Text.UTF8Encoding($false)))
        Copy-Item -LiteralPath (Join-Path $Directory 'pubspec.yaml') -Destination (Join-Path $root 'pubspec.yaml')
        return $root
    }
    catch {
        foreach ($name in @('.fvmrc', 'pubspec.yaml')) { $path = Join-Path $root $name; if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) } }
        [IO.Directory]::Delete($root)
        throw
    }
}

function Assert-JobsFvmWritePaths {
    param([string]$Directory)
    foreach ($relative in @('.fvm', '.fvm/versions', '.vscode')) {
        $path = Join-Path $Directory $relative
        if (Test-JobsFvmPathEntry $path) { [void](Assert-JobsFvmDirectory $path) }
    }
    foreach ($relative in @('.fvmrc', '.gitignore', '.vscode/settings.json', '.fvm/fvm_config.json', '.fvm/version', '.fvm/release', '.fvm/.gitignore')) {
        $path = Join-Path $Directory $relative
        if (Test-JobsFvmPathEntry $path) { Assert-JobsFvmPlainFile $path }
    }
    foreach ($workspace in Get-ChildItem -LiteralPath $Directory -Filter '*.code-workspace' -Force) {
        Assert-JobsFvmPlainFile $workspace.FullName
    }
}

function Get-JobsFvmPreviewStamp {
    param([string]$Directory)
    $entries = @()
    foreach ($relative in @('pubspec.yaml', '.fvmrc', '.fvm/fvm_config.json')) {
        $path = Join-Path $Directory $relative
        $hash = '(absent)'
        if (Test-JobsFvmPathEntry $path) { Assert-JobsFvmPlainFile $path; $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
        $entries += ($relative + ':' + $hash)
    }
    return $entries -join '|'
}

function Backup-JobsFvmProject {
    param([string]$Directory)
    $backup = Join-Path (Join-Path (Get-JobsInstallRoot) 'backups') ('project-' + (Get-Date -Format 'yyyy-MM-dd-HH-mm-ss') + '-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($backup)
    $records = New-Object 'System.Collections.Generic.List[object]'
    $queue = New-Object 'System.Collections.Generic.Queue[string]'
    foreach ($relative in @('.fvmrc', '.gitignore', '.vscode/settings.json', '.fvm')) { $queue.Enqueue($relative) }
    foreach ($workspace in Get-ChildItem -LiteralPath $Directory -Filter '*.code-workspace' -File -Force) { $queue.Enqueue($workspace.Name) }
    while ($queue.Count -gt 0) {
        $relative = $queue.Dequeue()
        $path = Join-Path $Directory $relative
        if (-not (Test-JobsFvmPathEntry $path)) { $records.Add(@{ Path = $relative; Type = 'Absent' }); continue }
        $item = Get-Item -LiteralPath $path -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            $target = ''
            if ($null -ne $item.PSObject.Properties['Target']) { $target = @($item.Target) -join ';' }
            $records.Add(@{ Path = $relative; Type = 'Link'; Target = $target })
            continue
        }
        if ($item.PSIsContainer) {
            $records.Add(@{ Path = $relative; Type = 'Directory' })
            foreach ($child in Get-ChildItem -LiteralPath $path -Force) { $queue.Enqueue(($relative + '/' + $child.Name)) }
        }
        else {
            $destination = Join-Path (Join-Path $backup 'files') $relative
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
            Copy-Item -LiteralPath $path -Destination $destination
            $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            if ($hash -cne (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash) { throw '项目备份字节校验失败。' }
            $records.Add(@{ Path = $relative; Type = 'File'; SHA256 = $hash })
        }
    }
    @{ Project = $Directory; Created = [DateTime]::Now.ToString('o'); Entries = @($records.ToArray()) } |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $backup 'snapshot.json') -Encoding UTF8
    Write-JobsFvmMessage "项目精确备份：$backup；SDK 链接仅记录目标，不复制 SDK 缓存。"
    return $backup
}

function Set-JobsProjectFvmVersion {
    param([string]$Directory, [string]$Version)
    if (-not (Test-JobsFlutterVersion $Version)) { throw '仅允许绑定具体 Flutter 版本。' }
    $config = Get-JobsProjectFvmConfig $Directory
    $config | Add-Member -NotePropertyName 'flutter' -NotePropertyValue $Version -Force
    $config | Add-Member -NotePropertyName 'updateMelosSettings' -NotePropertyValue $false -Force
    # 先在精确目标根创建配置，阻止 FVM 向父目录寻找配置并改动父级 Melos。
    [IO.File]::WriteAllText((Join-Path $Directory '.fvmrc'), ($config | ConvertTo-Json -Depth 100 -WarningAction Stop) + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
}

function Assert-JobsFvmSymlinkSupport {
    param([string]$Directory)
    if (-not ('Jobs.FvmSymlink' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Jobs {
    public static class FvmSymlink {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.I1)]
        public static extern bool CreateSymbolicLink(string link, string target, int flags);
    }
}
'@
    }
    $root = Join-Path ([IO.Path]::GetTempPath()) ('JobsFvmLink-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($root)
    try {
        $target = Join-Path $root 'target'
        [void][IO.Directory]::CreateDirectory($target)
        # PowerShell 5.1 New-Item 未必使用开发者模式的无提权标志，直接检验 FVM 所需的系统能力。
        $link = Join-Path $root 'link'
        if (-not [Jobs.FvmSymlink]::CreateSymbolicLink($link, $target, 3)) {
            if (-not [Jobs.FvmSymlink]::CreateSymbolicLink($link, $target, 1)) { throw '符号链接权限不足。' }
        }
    }
    catch { throw 'FVM 需要创建 SDK 符号链接。请在 Windows 设置中启用开发者模式后重试；本入口不自动提权或更改系统设置。' }
    finally {
        $link = Join-Path $root 'link'
        if (Test-Path -LiteralPath $link) { [IO.Directory]::Delete($link) }
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    }
}
# 选择版本后默认取消写入，确认后保留原SDK锁、备份和绑定事务。
function Invoke-JobsFlutterVersionAction {
    param([string]$Directory,[switch]$RequireCompletion)
    Assert-JobsFlutterProject $Directory
    Assert-JobsFvmWritePaths $Directory
    $previewStamp = Get-JobsFvmPreviewStamp $Directory
    Write-JobsFvmMessage "Flutter SDK 安装/切换（FVM）；精确项目：$Directory"
    Write-JobsFvmMessage '流程：项目校验 → 健康工具链 → 官方历史/最新版本 → fzf → 最终确认 → 备份 → 安装/切换。工具安装会分别确认。'
    $config = Get-JobsProjectFvmConfig $Directory
    if (($config.PSObject.Properties['flutterUrl'] -and $config.flutterUrl -cnotin @('https://github.com/flutter/flutter.git','https://github.com/flutter/flutter')) -or
        ($config.PSObject.Properties['flutter'] -and [string]$config.flutter -cmatch '^custom_|/')) {
        throw '原生 Flutter 选择器只接受官方来源；本工具管理的 OpenHarmony SDK 请从统一菜单切回，其它 fork 请自行明确迁移。'
    }
    $current = '(未绑定)'
    if ($null -ne $config.PSObject.Properties['flutter']) { $current = [string]$config.flutter }
    Write-JobsFvmMessage "当前项目 .fvmrc：$current"
    $savedPath = $env:PATH
    $savedTls = [Net.ServicePointManager]::SecurityProtocol
    $lock = $null
    $inspection = $null
    try {
        [Net.ServicePointManager]::SecurityProtocol = $savedTls -bor [Net.SecurityProtocolType]::Tls12
        $root = Get-JobsInstallRoot
        [void][IO.Directory]::CreateDirectory($root)
        try { $lock = [IO.File]::Open((Join-Path $root 'operation.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
        catch { throw '另一 FVM 会话正在运行，请结束该会话后再试。' }
        $inspection = New-JobsFvmInspection $Directory
        $chain = Get-JobsFvmToolchain $Directory $inspection
        if ($chain.Context.flutterUrl -cnotin @('https://github.com/flutter/flutter.git','https://github.com/flutter/flutter')) { throw 'FVM 有效来源不是官方 Flutter 仓库；未下载或切换原生 SDK。请先检查 FVM_FLUTTER_URL 与 FVM 配置。' }
        $cached = @(Get-JobsFvmCachedVersions $chain.Fvm $inspection)
        $choices = @(Get-JobsFlutterReleaseChoices $cached $current)
        $versionState = @{}
        while ($true) {
            $choice = Select-JobsFlutterVersion $chain.Fzf $choices $Directory -State $versionState
            if ($null -eq $choice) { if ($RequireCompletion) { throw '已取消 SDK 准备，未继续依赖操作。' }; Write-JobsFvmMessage '已取消选择，项目未修改。'; return }
            Write-JobsFvmMessage ("计划：{0} → {1}；{2}" -f $current, $choice.Version, $choice.Label)
            Write-JobsFvmMessage '写入范围：当前根 .fvmrc（保留其它字段、关闭向父 Melos 同步）、.fvm/、可能的 .gitignore、.vscode/settings.json 和根 *.code-workspace；不获取项目 pub 依赖。未缓存版本将下载 SDK。'
            $confirmation = Select-JobsFzfItems '确认当前项目安装/切换（默认取消）' @('应用以上准确版本与写入范围') -RequireConfirmation -Child:($choices.Count -gt 1)
            if ($confirmation.Action -ceq 'back') { continue }
            if ($confirmation.Action -cne 'selected') { if ($RequireCompletion) { throw '已取消 SDK 准备，未继续依赖操作。' }; Write-JobsFvmMessage '已取消，项目未修改。'; return }
            break
        }
        Assert-JobsFlutterProject $Directory
        Assert-JobsFvmWritePaths $Directory
        if ((Get-JobsFvmPreviewStamp $Directory) -cne $previewStamp) { throw '选版期间 pubspec.yaml 或 .fvmrc 已被修改，请重新打开菜单确认新状态；本次未写项目。' }
        Assert-JobsFvmSymlinkSupport $Directory
        $backup = Backup-JobsFvmProject $Directory
        Set-JobsProjectFvmVersion $Directory $choice.Version
        $pinnedConfig = Get-JobsProjectFvmConfig $Directory
        $contextResult = Invoke-JobsFvmTool $chain.Fvm @('api', 'context', '--compress') $Directory
        if ($contextResult.ExitCode -ne 0) { throw "项目配置写入后的 FVM 上下文体检失败；备份：$backup" }
        $effective = ($contextResult.StdOut | ConvertFrom-Json -ErrorAction Stop).context
        if ($null -eq $effective -or $effective.versionsCachePath -cne $chain.Context.versionsCachePath -or $effective.flutterUrl -cne $chain.Context.flutterUrl) {
            throw "精确根配置建立后缓存或 SDK 来源发生变化，原选择状态不再适用。尚未安装/切换 SDK，请重新打开菜单按新上下文选版；需要恢复原配置时使用备份：$backup"
        }
        if (-not $choice.Ready) {
            if ($choice.Offline) { throw '离线模式禁止下载或初始化 SDK。' }
            Write-JobsFvmMessage ("执行：fvm install {0} --skip-pub-get；来源由以上 FVM 配置决定。" -f $choice.Version)
            $install = Invoke-JobsFvmTool $chain.Fvm @('install', $choice.Version, '--skip-pub-get') $Directory -Visible -TimeoutSeconds 3600
            if ($install.ExitCode -ne 0) { throw "SDK 安装失败（$($install.ExitCode)）；项目可能部分改动，备份：$backup" }
        }
        Write-JobsFvmMessage ("执行：fvm use {0} --skip-pub-get --skip-setup" -f $choice.Version)
        $use = Invoke-JobsFvmTool $chain.Fvm @('use', $choice.Version, '--skip-pub-get', '--skip-setup') $Directory -Visible -TimeoutSeconds 300
        if ($use.ExitCode -ne 0) { throw "FVM 切换失败（$($use.ExitCode)）；备份：$backup" }
        $after = Get-JobsProjectFvmConfig $Directory
        if ($after.flutter -cne $choice.Version -or $after.updateMelosSettings -ne $false) { throw '.fvmrc 复核与所选版本不符。' }
        # 上游模型只保留已知字段；把它省略的现有扩展字段补回，避免吞掉用户配置。
        foreach ($property in $pinnedConfig.PSObject.Properties) {
            if ($null -eq $after.PSObject.Properties[$property.Name]) { $after | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value }
        }
        [IO.File]::WriteAllText((Join-Path $Directory '.fvmrc'), ($after | ConvertTo-Json -Depth 100 -WarningAction Stop) + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
        $sdkLink = Join-Path $Directory '.fvm/flutter_sdk'
        if (-not (Test-Path -LiteralPath (Join-Path $sdkLink 'bin/flutter.bat') -PathType Leaf) -or
            ((Get-Item -LiteralPath $sdkLink -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
            throw '项目 .fvm/flutter_sdk SDK 链接不存在或不完整。'
        }
        $version = Invoke-JobsFvmTool $chain.Fvm @('flutter', '--version', '--machine') $Directory -TimeoutSeconds 120 -LiveCapture
        if ($version.ExitCode -ne 0) { throw 'Flutter SDK 切换后的执行体检失败。' }
        $actual = ConvertFrom-JobsSdkMachineOutput $version.StdOut
        if ($actual.frameworkVersion -cne $choice.Version) { throw "实际 Flutter 版本 $($actual.frameworkVersion) 与所选版本 $($choice.Version) 不一致。" }
        Write-JobsFvmMessage ("成功：项目已绑定 Flutter {0}；实际 SDK 已复核。备份：{1}" -f $choice.Version, $backup)
        $fvmCommand = "& '" + $chain.Fvm.Replace("'", "''") + "'"
        Write-JobsFvmMessage ("后续终端命令使用 FVM：{0} flutter pub get；IDE SDK 指向项目 .fvm/flutter_sdk。请审阅 Git 差异，将 .fvmrc 纳入版本控制并忽略 .fvm/。" -f $fvmCommand)
    }
    finally {
        if ($inspection -and [IO.Directory]::Exists($inspection)) {
            try {
                foreach ($name in @('.fvmrc', 'pubspec.yaml')) { $path = Join-Path $inspection $name; if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) } }
                # 只删除本次空目录；若上游意外产生其它文件，保留现场而不递归清理。
                [IO.Directory]::Delete($inspection)
            }
            catch { Write-Warning "私有体检目录保留待查：$inspection" }
        }
        if ($null -ne $lock) { $lock.Dispose() }
        $env:PATH = $savedPath
        [Net.ServicePointManager]::SecurityProtocol = $savedTls
    }
}

function Invoke-JobsFeature {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Target)
    $directory = Assert-JobsFvmDirectory (Resolve-JobsTarget $Target)
    Invoke-JobsFlutterVersionAction $directory
}

Export-ModuleMember -Function Invoke-JobsFeature

# Action.psm1
# JobsCodeGraphUpdater
# Created by Jobs on 2026年10月18日，星期日.


# Jobs enter-choice emphasis is display-only; input and business decisions stay with callers.
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

function Write-JobsWorkerMessage {
    param([string]$Message)
    $safe = $Message -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@'
    $safe = $safe -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]'
    $safe = $safe -replace '(?im)(authorization\s*[:=]\s*)[^\r\n]+', '$1[已省略]'
    $safe = $safe -replace '(?im)((?:access[_-]?token|authorization|password|secret)\s*[:=]\s*)\S+', '$1[已省略]'
    Write-Host $safe
    Write-JobsLog $safe
}

function Assert-JobsOrdinaryDirectory {
    param([string]$Path)
    if (-not [IO.Path]::IsPathRooted($Path) -or -not [IO.Directory]::Exists($Path)) {
        throw "目标必须是已存在的绝对目录：$Path"
    }
    $directory = New-Object IO.DirectoryInfo ([IO.Path]::GetFullPath($Path))
    $current = $directory
    while ($null -ne $current) {
        if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "不处理符号链接、目录联接或其它重解析目录：$($current.FullName)"
        }
        $current = $current.Parent
    }
    return $directory.FullName
}

function Assert-JobsOrdinaryFile {
    param([string]$Path)
    if (-not [IO.File]::Exists($Path)) { throw "缺少文件：$Path" }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "不处理重解析文件：$Path"
    }
}

function Test-JobsSamePath {
    param([string]$First, [string]$Second)
    foreach ($path in @($First, $Second)) {
        if ([string]::IsNullOrWhiteSpace($path) -or -not [IO.Path]::IsPathRooted($path)) { return $false }
        if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT -and $path -notmatch '^(?:[A-Za-z]:[\\/]|[\\/]{2}[^\\/]+[\\/][^\\/]+(?:[\\/]|$))') { return $false }
    }
    $left = [IO.Path]::GetFullPath($First).TrimEnd('\', '/')
    $right = [IO.Path]::GetFullPath($Second).TrimEnd('\', '/')
    return [string]::Equals($left, $right, [StringComparison]::OrdinalIgnoreCase)
}

function Invoke-JobsCheckedProcess {
    param([string]$Executable, [string[]]$Arguments, [string]$Directory,
        [int]$TimeoutSeconds = 30, [switch]$Quiet)
    Write-JobsLog ("执行：{0} {1}" -f $Executable, (($Arguments | ForEach-Object { Quote-JobsArgument $_ }) -join ' '))
    $result = Invoke-JobsProcess -FilePath $Executable -Arguments $Arguments -WorkingDirectory $Directory -TimeoutSeconds $TimeoutSeconds
    if (-not $Quiet) {
        if ($result.StdOut) { Write-JobsWorkerMessage $result.StdOut.TrimEnd() }
        if ($result.StdErr) { Write-JobsWorkerMessage $result.StdErr.TrimEnd() }
    }
    if ($result.ExitCode -ne 0) {
        if ($Quiet -and $result.StdErr) { Write-JobsWorkerMessage $result.StdErr.TrimEnd() }
        throw "命令失败（退出码 $($result.ExitCode)）：$Executable"
    }
    return $result
}

function Get-JobsPackageEntry {
    param([string]$PackageDirectory, [string]$PackageName, [string]$CommandName)
    if (-not (Test-Path -LiteralPath $PackageDirectory -PathType Container)) { return $null }
    [void](Assert-JobsOrdinaryDirectory $PackageDirectory)
    $packagePath = Join-Path $PackageDirectory 'package.json'
    if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { return $null }
    Assert-JobsOrdinaryFile $packagePath
    $package = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($package.name -ne $PackageName) { return $null }
    if ($PackageName -eq '@colbymchenry/codegraph' -and $package.version -ne '1.6.2') { return $null }
    $bin = if ($package.bin -is [string]) { $package.bin } else { $package.bin.$CommandName }
    if ([string]::IsNullOrWhiteSpace($bin) -or [IO.Path]::IsPathRooted($bin)) { throw 'npm 包命令入口不合法。' }
    $root = [IO.Path]::GetFullPath($PackageDirectory).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $entry = [IO.Path]::GetFullPath((Join-Path $PackageDirectory $bin))
    if (-not $entry.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw 'npm 包命令入口越过包目录。' }
    Assert-JobsOrdinaryFile $entry
    return $entry
}

function Get-JobsCodeGraphCommand {
    param([string]$Node, [string]$Prefix)
    $packages = @((Join-Path $Prefix 'node_modules\@colbymchenry\codegraph'))
    $shim = Find-JobsExecutable -Name 'codegraph.cmd' -Candidates @((Join-Path $Prefix 'node_modules\.bin\codegraph.cmd'))
    if ($shim) {
        $shimDirectory = [IO.Path]::GetDirectoryName($shim)
        $packages += Join-Path $shimDirectory 'node_modules\@colbymchenry\codegraph'
        $packages += Join-Path ([IO.Path]::GetDirectoryName($shimDirectory)) '@colbymchenry\codegraph'
    }
    foreach ($package in $packages | Select-Object -Unique) {
        $entry = Get-JobsPackageEntry $package '@colbymchenry/codegraph' 'codegraph'
        if ($entry) {
            $platformName = 'codegraph-' + $script:CodeGraphPlatform
            $bundles = @(
                (Join-Path ([IO.Path]::GetDirectoryName($package)) $platformName),
                (Join-Path $package ('node_modules\@colbymchenry\' + $platformName))
            )
            foreach ($bundle in $bundles) {
                $metadata = Join-Path $bundle 'package.json'
                if (-not (Test-Path -LiteralPath $metadata -PathType Leaf)) { continue }
                [void](Assert-JobsOrdinaryDirectory $bundle)
                Assert-JobsOrdinaryFile $metadata
                $platform = Get-Content -LiteralPath $metadata -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($platform.name -ne ('@colbymchenry/' + $platformName) -or $platform.version -ne '1.6.2') { continue }
                $runtime = Join-Path $bundle 'node.exe'
                $cli = Join-Path $bundle 'lib\dist\bin\codegraph.js'
                Assert-JobsOrdinaryFile $runtime
                Assert-JobsOrdinaryFile $cli
                return @{ Executable = $runtime; Prefix = @('--liftoff-only', $cli); SchemaNode = $runtime }
            }
        }
    }
    if ($shim) {
        $directory = [IO.Path]::GetDirectoryName($shim)
        foreach ($bundle in @($directory, [IO.Path]::GetDirectoryName($directory))) {
            $metadata = Join-Path $bundle 'lib\package.json'
            if (-not (Test-Path -LiteralPath $metadata -PathType Leaf)) { continue }
            [void](Assert-JobsOrdinaryDirectory $bundle)
            Assert-JobsOrdinaryFile $metadata
            $package = Get-Content -LiteralPath $metadata -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($package.name -ne '@colbymchenry/codegraph' -or $package.version -ne '1.6.2') { continue }
            $runtime = Join-Path $bundle 'node.exe'
            $cli = Join-Path $bundle 'lib\dist\bin\codegraph.js'
            Assert-JobsOrdinaryFile $runtime
            Assert-JobsOrdinaryFile $cli
            return @{ Executable = $runtime; Prefix = @('--liftoff-only', $cli); SchemaNode = $runtime }
        }
    }
    return $null
}

function Assert-JobsCodeGraphVersion {
    param([hashtable]$Command, [string]$Directory)
    $result = Invoke-JobsCheckedProcess $Command.Executable ($Command.Prefix + @('--version')) $Directory
    if ($result.StdOut.Trim() -notmatch '^(?:CodeGraph\s+)?v?1\.6\.2$') {
        throw '此入口只支持已核实无隐式 hooks/agent 安装的 CodeGraph 1.6.2；未知版本不执行建图。'
    }
}

function Assert-JobsCodeGraphRuntime {
    param([hashtable]$Command, [string]$Directory)
    Assert-JobsCodeGraphVersion $Command $Directory
    $probe = 'const {DatabaseSync}=require("node:sqlite");const db=new DatabaseSync(":memory:");try{db.exec("CREATE TABLE health(value TEXT); INSERT INTO health VALUES(''ok'')");if(db.prepare("SELECT value FROM health").get().value!=="ok")throw Error("SQLite probe failed");}finally{db.close();}process.stdout.write("SQLite ok");'
    [void](Invoke-JobsCheckedProcess $Command.SchemaNode @('-e', $probe) $Directory -Quiet)
    $help = (Invoke-JobsCheckedProcess $Command.Executable ($Command.Prefix + @('--help')) $Directory -Quiet).StdOut
    foreach ($name in @('init', 'sync', 'status')) {
        if ($help -notmatch ('\b' + $name + '\b')) { throw "CodeGraph 缺少必需命令：$name" }
    }
    Write-JobsWorkerMessage "健康：CodeGraph 1.6.2、随包 Node 与 SQLite → $($Command.Executable)"
}

function Assert-JobsCodeGraphHost {
    if ($PSVersionTable.PSVersion -lt [version]'5.1' -or $PSVersionTable.PSEdition -ne 'Desktop') {
        throw '工具链阻塞在 Windows PowerShell 5.1 Desktop；请使用本包 .cmd 安装及菜单入口。'
    }
    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        $digest = [BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes('Jobs'))).Replace('-', '').ToLowerInvariant()
        if ($digest -cne '2f17a0f8d518e491c5a0c490b2c1991828dd87d173994ba40996e1da59d4e368') { throw '.NET SHA-256 不可用。' }
    } finally { $hash.Dispose() }
    $architecture = [string]$env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITEW6432) { $architecture = $env:PROCESSOR_ARCHITEW6432 }
    $script:CodeGraphPlatform = switch ($architecture.ToUpperInvariant()) {
        'AMD64' { 'win32-x64' }
        'ARM64' { 'win32-arm64' }
        default { throw 'CodeGraph 1.6.2 只提供 Windows x64/ARM64 运行包。' }
    }
    Write-JobsWorkerMessage "健康：PowerShell $($PSVersionTable.PSVersion)、.NET $([Environment]::Version)、$script:CodeGraphPlatform"
}

function Get-JobsCodeGraphNodeTools {
    param([string]$Directory)
    $candidates = @('node.exe')
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
        if ($base) { $candidates += Join-Path $base 'nodejs\node.exe'; $candidates += Join-Path $base 'Programs\nodejs\node.exe' }
    }
    $visited = @()
    foreach ($candidate in $candidates) {
        $node = Find-JobsExecutable -Name $candidate -Candidates @()
        if (-not $node -or $node -in $visited) { continue }
        $visited += $node
        try {
            $version = (Invoke-JobsCheckedProcess $node @('--version') $Directory -Quiet).StdOut.Trim()
            if ($version -notmatch '^v(\d+)\.' -or [int]$Matches[1] -lt 20 -or [int]$Matches[1] -ge 25) { throw 'CodeGraph 1.6.2 安装工具链需要 Node.js >=20 且 <25。' }
            $probe = 'if(!require("node:fs").statSync(process.execPath).isFile())throw Error("runtime missing");process.stdout.write(require("node:crypto").createHash("sha256").update("Jobs").digest("hex"));'
            $digest = (Invoke-JobsCheckedProcess $node @('-e', $probe) $Directory -Quiet).StdOut.Trim()
            if ($digest -cne '2f17a0f8d518e491c5a0c490b2c1991828dd87d173994ba40996e1da59d4e368') { throw 'Node.js 标准库体检结果不正确。' }
            $npm = Get-JobsPackageEntry (Join-Path ([IO.Path]::GetDirectoryName($node)) 'node_modules\npm') 'npm' 'npm'
            if (-not $npm) { throw '此 Node.js 安装缺少匹配的 npm JavaScript 入口。' }
            $npmVersion = (Invoke-JobsCheckedProcess $node @($npm, '--version', '--offline') $Directory -Quiet).StdOut.Trim()
            if ($npmVersion -notmatch '^\d+\.\d+\.\d+') { throw 'npm 没有返回有效版本。' }
            $npmPrefix = (Invoke-JobsCheckedProcess $node @($npm, 'config', 'get', 'prefix', '--offline') $Directory -Quiet).StdOut.Trim()
            $npmRoot = (Invoke-JobsCheckedProcess $node @($npm, 'root', '--global', '--offline') $Directory -Quiet).StdOut.Trim()
            if ([string]::IsNullOrWhiteSpace($npmPrefix) -or [string]::IsNullOrWhiteSpace($npmRoot) -or
                -not [IO.Path]::IsPathRooted($npmPrefix) -or -not [IO.Path]::IsPathRooted($npmRoot)) { throw 'npm 配置或全局包路径不可用。' }
            Write-JobsWorkerMessage "健康：Node.js $version → $node；npm $npmVersion → $npm"
            return @{ Node = $node; NpmEntry = $npm }
        } catch { Write-JobsWorkerMessage ("上游体检：{0} → {1}" -f $node, $_.Exception.Message) }
    }
    Write-JobsWorkerMessage '上游体检：Node.js/npm 缺失或损坏；已有健康的 CodeGraph 随包运行时不依赖这层。'
    return $null
}

function Get-JobsCodeGraphWinget {
    param([string]$Directory)
    $winget = Find-JobsExecutable -Name 'winget.exe' -Candidates @()
    if ($winget) {
        try {
            $version = (Invoke-JobsCheckedProcess $winget @('--version') $Directory -Quiet).StdOut.Trim()
            if ($version -notmatch '^v?\d+\.\d+') { throw 'WinGet 没有返回有效版本。' }
            [void](Invoke-JobsCheckedProcess $winget @('--info') $Directory -Quiet)
            Write-JobsWorkerMessage "健康：WinGet $version → $winget"
            return $winget
        } catch { Write-JobsWorkerMessage ("上游体检：WinGet → " + $_.Exception.Message) }
    }
    Write-JobsWorkerMessage '上游体检：WinGet 不可用；仅在缺少健康 Node.js/npm、需要安装工具链时阻塞。'
    return $null
}

function Update-JobsCodeGraphSessionPath {
    # 只合并安装器新登记的路径到本进程，不覆盖用户或系统的持久 PATH。
    $paths = @($env:PATH -split [IO.Path]::PathSeparator)
    foreach ($scope in @('User', 'Machine')) {
        $paths += @([Environment]::GetEnvironmentVariable('PATH', $scope) -split [IO.Path]::PathSeparator)
    }
    $env:PATH = (@($paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique) -join [IO.Path]::PathSeparator)
}
# 只修复实际缺失或损坏的Node工具链，复检后再恢复原索引业务。
function Repair-JobsCodeGraphNodeTools {
    param([string]$Winget,[string]$Directory)
    Write-JobsWorkerMessage '安装来源：WinGet 官方 winget 源；OpenJS.NodeJS.LTS，仅24.x最新可用补丁；当前用户范围。原生许可本人处理，Windows不使用WSL Homebrew。'
    if((Read-JobsEnterChoiceHost '按回车准备必需WinGet并安装/修复Node.js 24.x；输入任意字符取消')-cne''){throw(New-Object OperationCanceledException('已取消Node.js准备。'))}
    if(-not$Winget){$Winget=Get-JobsNativeRequiredWinget}
    $available=(Invoke-JobsNativeWingetRetry $Winget @('show','--id','OpenJS.NodeJS.LTS','--exact','--versions','--source','winget')).Text
    $versions=@([regex]::Matches($available,'(?m)^\s*(24\.\d+\.\d+)\s*$')|ForEach-Object{[version]$_.Groups[1].Value}|Sort-Object -Descending)
    if($versions.Count-eq0){throw 'WinGet官方源没有可验证的Node.js24.x，未安装其它major。'}
    $version=$versions[0].ToString()
    [void](Invoke-JobsNativeWingetRetry $Winget @('show','--id','OpenJS.NodeJS.LTS','--exact','--version',$version,'--source','winget'))
    Write-JobsWorkerMessage ('准备官方Node.js '+$version+'；安装器会处理许可并可能要求系统权限，本包不主动提权。')
    [void](Invoke-JobsNativeWingetRetry $Winget @('install','--id','OpenJS.NodeJS.LTS','--exact','--version',$version,'--source','winget','--scope','user','--force','--interactive'))
    Update-JobsCodeGraphSessionPath
    Update-JobsWingetNativePath
    $tools=Get-JobsCodeGraphNodeTools $Directory
    if(-not$tools){throw 'Node.js/npm安装返回后仍未通过实际工具复检，未继续CodeGraph。'}
    return $tools
}

function Assert-JobsGraphFiles {
    param([string]$Directory)
    $graph = Join-Path $Directory '.codegraph'
    [void](Assert-JobsOrdinaryDirectory $graph)
    foreach ($entry in Get-ChildItem -LiteralPath $graph -Force) {
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "地图中存在重解析条目：$($entry.FullName)" }
    }
    $database = Join-Path $graph 'codegraph.db'
    Assert-JobsOrdinaryFile $database
    $stream = [IO.File]::Open($database, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $header = New-Object byte[] 16
        if ($stream.Read($header, 0, 16) -ne 16 -or [Text.Encoding]::ASCII.GetString($header) -cne "SQLite format 3`0") {
            throw '当前精确地图数据库不是有效的 SQLite 文件；保留原图并停止。'
        }
    } finally { $stream.Dispose() }
    return $database
}

function Get-JobsGraphStatus {
    param([hashtable]$Command, [string]$Directory, [switch]$Complete)
    $database = Assert-JobsGraphFiles $Directory
    # 在 status 的父级回退逻辑之前，只读检查精确数据库，禁止修复或创建空 schema。
    $checkSchema = 'const {DatabaseSync}=require("node:sqlite");const db=new DatabaseSync(process.argv[1],{readOnly:true});try{if(!db.prepare("SELECT 1 FROM sqlite_master WHERE type=''table'' AND name=''nodes'' LIMIT 1").get())throw Error("missing nodes table");const r=db.prepare("PRAGMA quick_check(1)").get();if(Object.values(r)[0]!=="ok")throw Error("database integrity check failed");}finally{db.close();}'
    [void](Invoke-JobsCheckedProcess $Command.SchemaNode @('-e', $checkSchema, $database) $Directory 120 -Quiet)
    $result = Invoke-JobsCheckedProcess $Command.Executable ($Command.Prefix + @('status', '--json', $Directory)) $Directory -Quiet
    try { $status = $result.StdOut | ConvertFrom-Json }
    catch { throw 'CodeGraph 返回了无效 JSON；未继续改动地图。' }
    if ($null -eq $status -or $status.initialized -ne $true -or $status.version -ne '1.6.2' -or
        -not (Test-JobsSamePath $status.projectPath $Directory) -or
        -not (Test-JobsSamePath $status.indexPath (Join-Path $Directory '.codegraph'))) {
        throw 'CodeGraph 项目身份与精确目标不一致；拒绝回退到父目录地图。'
    }
    if ($Complete) {
        if (-not $status.lastIndexed -or $status.index.state -ne 'complete') { throw '地图未报告索引完成。' }
        foreach ($name in @('added', 'modified', 'removed')) {
            if ($null -eq $status.pendingChanges.$name -or $status.pendingChanges.$name -ne 0) { throw "地图仍有待处理变更：$name" }
        }
        if ($null -eq $status.index.pendingRefs -or $status.index.pendingRefs -ne 0) { throw '地图仍有待解析引用。' }
        foreach ($name in @('filesNeedingReindex', 'filesWithParseErrors')) {
            if ($name -in @($status.index.PSObject.Properties.Name) -and $status.index.$name -ne 0) { throw "地图仍有待处理项：$name" }
        }
    }
}

function Invoke-JobsCodeGraphAction {
    param([string]$Directory)
    Write-JobsWorkerMessage "代码地图目标：$(Join-Path $Directory '.codegraph')"
    $variables = @{ CODEGRAPH_DIR = '.codegraph'; CODEGRAPH_TELEMETRY = '0'; DO_NOT_TRACK = '1';
        CODEGRAPH_NO_DOWNLOAD = '1'; CODEGRAPH_NO_WATCH = '0'; CODEGRAPH_NO_DAEMON = '1'; NO_COLOR = '1'; FORCE_COLOR = '0';
        NODE_OPTIONS = ''; NODE_PATH = '' }
    foreach ($name in $variables.Keys) { [Environment]::SetEnvironmentVariable($name, $variables[$name], 'Process') }
    Assert-JobsCodeGraphHost
    $inspectionDirectory = Assert-JobsOrdinaryDirectory (Get-JobsInstallRoot)
    $tools = Get-JobsCodeGraphNodeTools $inspectionDirectory
    $winget = Get-JobsCodeGraphWinget $inspectionDirectory
    $prefix = Join-Path (Get-JobsInstallRoot) 'tools\codegraph'
    $command = $null
    try {
        $command = Get-JobsCodeGraphCommand '' $prefix
        if ($command) { Assert-JobsCodeGraphRuntime $command $Directory }
    } catch {
        Write-JobsWorkerMessage ("CodeGraph 体检失败：" + $_.Exception.Message)
        $command = $null
    }
    if (-not $command) {
        if (-not $tools) { $tools = Repair-JobsCodeGraphNodeTools $winget $inspectionDirectory }
        Write-JobsWorkerMessage '安装来源：https://www.npmjs.com/package/@colbymchenry/codegraph/v/1.6.2'
        Write-JobsWorkerMessage 'npm registry：https://registry.npmjs.org/'
        Write-JobsWorkerMessage "仅安装到用户目录：$prefix"
        if ((Read-JobsEnterChoiceHost '按回车安装/修复 CodeGraph；输入任意字符取消') -ne '') { throw '已取消。' }
        # 安装范围和平台由本包控制，不继承会改变 optional 包布局的 npm 进程配置。
        $npmVariables = @{ npm_config_global = 'false'; npm_config_omit = ''; npm_config_include = 'optional';
            npm_config_platform = 'win32'; npm_config_arch = $script:CodeGraphPlatform.Substring('win32-'.Length) }
        foreach ($name in $npmVariables.Keys) { [Environment]::SetEnvironmentVariable($name, $npmVariables[$name], 'Process') }
        [void](Assert-JobsOrdinaryDirectory (Get-JobsInstallRoot))
        $toolsDirectory = [IO.Path]::GetDirectoryName($prefix)
        if (Test-Path -LiteralPath $toolsDirectory) { [void](Assert-JobsOrdinaryDirectory $toolsDirectory) }
        [void][IO.Directory]::CreateDirectory($prefix)
        [void](Assert-JobsOrdinaryDirectory $prefix)
        [void](Invoke-JobsCheckedProcess $tools.Node @($tools.NpmEntry, 'ping', '--registry=https://registry.npmjs.org/', '--fetch-retries=0', '--fetch-timeout=20000') $prefix 30)
        [void](Invoke-JobsCheckedProcess $tools.Node @($tools.NpmEntry, 'install', '--global=false', '--prefix', $prefix, '--os=win32', ('--cpu=' + $npmVariables.npm_config_arch), '--registry=https://registry.npmjs.org/', '--@colbymchenry:registry=https://registry.npmjs.org/', '--include=optional', '--ignore-scripts', '--no-audit', '--no-fund', '@colbymchenry/codegraph@1.6.2') $prefix 600)
        $command = Get-JobsCodeGraphCommand $tools.Node $prefix
        if (-not $command) { throw '安装后仍找不到 CodeGraph 命令入口。' }
        Assert-JobsCodeGraphRuntime $command $Directory
    }
    [void](Assert-JobsOrdinaryDirectory $Directory)
    $graph = Join-Path $Directory '.codegraph'
    if (Test-Path -LiteralPath $graph) {
        Get-JobsGraphStatus $command $Directory
        [void](Invoke-JobsCheckedProcess $command.Executable ($command.Prefix + @('sync', $Directory)) $Directory 900)
    } else {
        [void](Invoke-JobsCheckedProcess $command.Executable ($command.Prefix + @('init', '--yes', $Directory)) $Directory 900)
    }
    Get-JobsGraphStatus $command $Directory -Complete
    Write-JobsWorkerMessage "代码地图更新完成：$graph"
}

function Invoke-JobsFeature {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Target)

    $directory = Assert-JobsOrdinaryDirectory -Path (Resolve-JobsTarget -Target $Target)
    Invoke-JobsCodeGraphAction -Directory $directory
}

Export-ModuleMember -Function Invoke-JobsFeature

# Action.psm1
# JobsFlutterPubGet
# Created by Jobs on 2026年10月18日，星期日.


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
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking
. (Join-Path $PSScriptRoot 'SdkDownloadOutput.ps1')

function Write-JobsWorkerMessage {
    param([string]$Message, [switch]$AuditOnly)
    $safe = $Message -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@'
    $safe = $safe -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]'
    $safe = $safe -replace '(?im)(authorization\s*[:=]\s*)[^\r\n]+', '$1[已省略]'
    $safe = $safe -replace '(?im)((?:access[_-]?token|authorization|password|secret)\s*[:=]\s*)\S+', '$1[已省略]'
    if (-not $AuditOnly) { Write-Host $safe }
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

function Invoke-JobsFlutterProcess {
    param([string]$Flutter, [string[]]$Arguments, [string]$Directory, [int]$TimeoutSeconds = 30)
    # cmd 只接收受控的工具路径和固定参数，项目路径始终通过 WorkingDirectory 传递。
    if ($Flutter -match '["\r\n]' -or @($Arguments | Where-Object { $_ -notin @('--version', 'pub', 'get') }).Count -gt 0) {
        throw 'Flutter 安装路径含非法控制字符或双引号，或请求了未允许的参数。'
    }
    $cmd = Join-Path ([Environment]::GetFolderPath('System')) 'cmd.exe'
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $cmd
    $start.Arguments = '/d /v:off /s /c ""%JOBS_FLUTTER_EXECUTABLE%" ' + ($Arguments -join ' ') + '"'
    $start.EnvironmentVariables['JOBS_FLUTTER_EXECUTABLE'] = $Flutter
    $start.WorkingDirectory = $Directory
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    Write-JobsWorkerMessage ("执行：Flutter {0}；目录：{1}" -f ($Arguments -join ' '), $Directory)
    if ($Arguments -contains '--version') { $result = Invoke-JobsSdkAcquireProcess $start ([Math]::Max(120,$TimeoutSeconds)) -Sanitize -Label 'Flutter/Dart 首次初始化' }
    else { $result = Invoke-JobsSdkLiveProcess $start $TimeoutSeconds -Sanitize }
    if ($result.StdOut) { Write-JobsWorkerMessage $result.StdOut.TrimEnd() -AuditOnly }
    if ($result.StdErr) { Write-JobsWorkerMessage $result.StdErr.TrimEnd() -AuditOnly }
    if ($result.ExitCode -ne 0) { throw "Flutter 操作失败（退出码 $($result.ExitCode)）。" }
}

function Invoke-JobsFlutterAction {
    param([string]$Directory)
    $pubspec = Join-Path $Directory 'pubspec.yaml'
    Assert-JobsOrdinaryFile $pubspec
    [void](Assert-JobsOrdinaryDirectory (Join-Path $Directory 'lib'))
    if ((Get-Content -LiteralPath $pubspec -Raw -Encoding UTF8) -notmatch '(?m)^\s+sdk\s*:\s*flutter\s*(?:#.*)?$') {
        throw '当前同层 pubspec.yaml 未声明 sdk: flutter。'
    }
    $fvm = Join-Path $Directory '.fvm\flutter_sdk\bin\flutter.bat'
    if (Test-Path -LiteralPath $fvm -PathType Leaf) { $flutter = $fvm }
    else { $flutter = Find-JobsExecutable -Name 'flutter.bat' -Candidates @() }
    if (-not $flutter) {
        Write-JobsWorkerMessage '缺少现成 Flutter SDK；请先按官方说明安装，扩展不会自动下载 Flutter。'
        Start-Process -FilePath 'https://docs.flutter.dev/get-started/install/windows'
        throw 'Flutter SDK 未就绪。'
    }
    Write-JobsWorkerMessage "Flutter SDK：$flutter"
    Invoke-JobsFlutterProcess $flutter @('--version') $Directory
    Write-JobsWorkerMessage "即将在此目录安装/更新 pubspec 依赖：$Directory"
    if ((Read-JobsEnterChoiceHost '按回车执行 flutter pub get；输入任意字符取消') -ne '') { throw '已取消。' }
    [void](Assert-JobsOrdinaryDirectory $Directory)
    Invoke-JobsFlutterProcess $flutter @('pub', 'get') $Directory 900
    Write-JobsWorkerMessage 'Flutter 依赖处理完成。'
}

function Invoke-JobsFeature {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Target)

    $directory = Assert-JobsOrdinaryDirectory -Path (Resolve-JobsTarget -Target $Target)
    Invoke-JobsFlutterAction -Directory $directory
}

Export-ModuleMember -Function Invoke-JobsFeature

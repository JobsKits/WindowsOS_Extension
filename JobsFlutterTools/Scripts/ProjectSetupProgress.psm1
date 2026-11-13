# ProjectSetupProgress.psm1 | 真实阶段事件，与原始终端日志分开。
# Created by Jobs on 2026年10月28日，星期三.

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
# 无会话时保持 CLI 可独立运行，不产生旁路文件。
function Set-JobsSetupProgress {
 param([string]$Node,[ValidateSet('pending','running','waiting','done','failed','skipped')][string]$State,[string]$Detail='',[string]$Version='')
 if($Node-ne'overall'-and$State-in@('running','waiting')){$script:activeNode=$Node}
 if (-not $env:JOBS_SETUP_SESSION) { return }
 $file=Join-Path $env:JOBS_SETUP_SESSION 'events.jsonl'
 $event=[ordered]@{time=(Get-Date).ToString('o');node=$Node;state=$State;detail=$Detail}
 if(-not[string]::IsNullOrWhiteSpace($Version)){$event['version']=$Version}
 [IO.File]::AppendAllText($file,($event|ConvertTo-Json -Compress)+[Environment]::NewLine,(New-Object Text.UTF8Encoding($false)))
}
# 统一绑定输入等待状态，输入只在原始控制台进行。
function Read-JobsSetupInput {
 param([string]$Prompt,[string]$Node='run.arguments')
 Set-JobsSetupProgress $Node waiting $Prompt
 $value=Read-JobsEnterChoiceHost $Prompt
 Set-JobsSetupProgress $Node running '已收到输入'
 return $value
}
# 唯一工具版本源；损坏或缺失时明确标未检测，不伪造版本。
function Get-JobsSetupVersion {
 param([string]$Path=(Join-Path $PSScriptRoot 'SetupVersion.json'))
 try {
  $value=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json
  if($value.version-cnotmatch'^\d+\.\d+\.\d+$'-or$value.build-cnotmatch'^\d{4}\.\d{2}\.\d{2}\.\d+$'){throw '工具版本格式无效'}
  return [pscustomobject]@{Version=$value.version;Build=$value.build;Label=('v'+$value.version+' build '+$value.build)}
 }catch{return [pscustomobject]@{Version=$null;Build=$null;Label='工具版本未检测'}}
}
# 兼容旧事件和未检测组件，版本展示与状态提示分开。
function Get-JobsSetupDetectedVersion {
 param($Value)
 if($null-ne$Value-and$null-ne$Value.PSObject.Properties['VersionText']-and-not[string]::IsNullOrWhiteSpace([string]$Value.VersionText)){return [string]$Value.VersionText}
 return '尚未检测'
}
# 返回当前真实子步骤，供等待/失败显示关联。
function Get-JobsSetupActiveNode { if(Get-Variable activeNode -Scope Script -ErrorAction SilentlyContinue){return $script:activeNode};return $null }
Export-ModuleMember -Function Set-JobsSetupProgress,Read-JobsSetupInput,Get-JobsSetupActiveNode,Get-JobsSetupVersion,Get-JobsSetupDetectedVersion

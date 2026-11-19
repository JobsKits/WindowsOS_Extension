# Action.psm1 | JobsFlutterCodegen
# Created by Jobs on 2026年10月22日，星期四.
# 严格校验当前根项目与同源 SDK；明确同意后仅准备本流程所需的精确SDK和生成器依赖。

# Jobs enter-choice emphasis is display-only; input and business decisions stay with callers.

# 源包装与已发布 flat 布局共用路径，兼容旧收据且不跟随包装目录链接。
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
. (Resolve-JobsScriptLayoutPath (Join-Path $PSScriptRoot 'SdkDownloadOutput.ps1'))

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

# JOBS_CODEGEN_REQUIRED_TOOLS_V1_BEGIN
# 只读探测当前项目可复用的健康FVM工具及其来源。
function Find-JobsCodegenHealthyFvmTool {
    param([string]$Name, [string[]]$Candidates, [string]$Directory)
    $paths = @()
    foreach ($candidate in @($Name) + $Candidates) {
        $path = Find-JobsExecutable -Name $candidate -Candidates @()
        if (-not $path -or $path -in $paths) { continue }
        $paths += $path
        try {
            $result = Invoke-JobsCodegenFvmTool $path @('--version') $Directory
            if ($result.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($result.StdOut + $result.StdErr)) {
                Write-JobsFlutterMessage ("健康：{0} → {1}；{2}" -f $Name, $path, ($result.StdOut + $result.StdErr).Trim())
                return $path
            }
        }
        catch { Write-JobsFlutterMessage "体检失败：$path" }
    }
    return $null
}
# 通过现有SDK下载路由读取官方FVM版本与校验信息。
function Read-JobsCodegenFvmWebJson {
    param([string]$Uri)
    Write-JobsFlutterMessage "查询来源：$Uri"
    $response = Invoke-JobsSdkAcquire -Label ('SDK 元数据：' + $Uri) -Operation { Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec 20 -Headers @{ 'User-Agent' = 'JobsFlutterVersionMgr'; 'Accept' = 'application/json' } }
    return $response.Content | ConvertFrom-Json -ErrorAction Stop
}
# 校验官方架构和SHA链后准备独立FVM，不改项目SDK绑定。
function Install-JobsCodegenStandaloneFvm {
    param([string]$Directory)
    $architecture = $env:PROCESSOR_ARCHITEW6432
    if ([string]::IsNullOrWhiteSpace($architecture)) { $architecture = $env:PROCESSOR_ARCHITECTURE }
    switch ($architecture.ToUpperInvariant()) {
        'AMD64' { $architecture = 'x64' }
        'ARM64' { $architecture = 'arm64' }
        default { throw '官方 FVM 独立包仅支持 Windows x64 / ARM64，请使用 64 位系统。' }
    }
    $release = Read-JobsCodegenFvmWebJson 'https://api.github.com/repos/btwld/fvm/releases/latest'
    if ($release.tag_name -cnotmatch '^v?\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$') { throw 'FVM release 版本格式无效。' }
    $assets = @($release.assets | Where-Object { $_.name -match ('^fvm-.*-windows-' + $architecture + '\.zip$') })
    if ($assets.Count -ne 1) { throw '未找到唯一的官方 FVM Windows 架构包。' }
    $asset = $assets[0]
    if ($asset.browser_download_url -cnotmatch '^https://github\.com/(?:btwld|leoafarias)/fvm/releases/download/[^/]+/fvm-[^/]+\.zip$' -or
        $null -eq $asset.PSObject.Properties['digest'] -or $asset.digest -cnotmatch '^sha256:[a-f0-9]{64}$') {
        throw 'FVM 包来源或官方 SHA-256 digest 不可验证，已停止。'
    }
    Write-JobsFlutterMessage ("FVM 来源：{0}；架构：{1}；SHA-256：{2}" -f $asset.browser_download_url, $architecture, $asset.digest)
    Write-JobsFlutterMessage '缺少健康 FVM，自动下载官方独立包；Ctrl+C 可停止。'
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
        $check = Invoke-JobsCodegenFvmTool $executables[0].FullName @('--version') $Directory
        if ($check.ExitCode -ne 0) { throw '下载的 FVM 无法执行。' }
        $destination = Join-Path $tools ('fvm-' + $release.tag_name + '-' + [guid]::NewGuid().ToString('N'))
        Move-Item -LiteralPath $expanded -Destination $destination
        $relative = $executables[0].FullName.Substring($expanded.Length).TrimStart([char]92, [char]47)
        $installed = Join-Path $destination $relative
        [IO.File]::WriteAllText((Join-Path $tools 'fvm-path.txt'), $installed, (New-Object Text.UTF8Encoding($false)))
        $complete = $true
        return $installed
    }
    finally { if ($complete -and (Test-Path -LiteralPath $stage)) { Remove-Item -LiteralPath $stage -Recurse -Force } elseif (Test-Path -LiteralPath $stage) { Write-JobsFlutterMessage ('未完成 FVM 下载保留：' + $stage) } }
}
# 通过既有SDK路由获取FVM工具，保持持续获取及取消语义。
function Invoke-JobsCodegenFvmTool {
    param([string]$File, [string[]]$Arguments = @(), [string]$Directory, [switch]$Visible, [int]$TimeoutSeconds = 30, [switch]$LiveCapture)
    $acquire = $Arguments.Count -gt 0 -and ($Arguments[0] -ceq 'install' -or ($Arguments[0] -ceq 'flutter' -and $Arguments.Count -gt 1 -and $Arguments[1] -in @('--version','precache')))
    if ($acquire -and $Arguments[0] -ceq 'install') {
        $help = Invoke-JobsCodegenFvmToolOnce $File @('install','--help') $Directory -TimeoutSeconds 30
        if ($help.ExitCode -eq 0 -and ($help.StdOut + $help.StdErr) -match '--\[no-\]setup|--no-setup' -and $Arguments -notcontains '--no-setup') {
            $Arguments += '--no-setup'
            Write-JobsFlutterMessage 'FVM已确认支持--no-setup：Git SDK获取与后续Dart/engine自举分阶段预检，不改Git来源。'
        }
    }
    if ($acquire) {
        return Invoke-JobsSdkAcquire -Label ('Flutter SDK：' + ($Arguments -join ' ')) -Operation {
            $result = Invoke-JobsCodegenFvmToolOnce $File $Arguments $Directory -TimeoutSeconds ([Math]::Max(120,$TimeoutSeconds)) -LiveCapture -Acquisition
            if ($result.ExitCode -eq 0 -and $Arguments[0] -ceq 'install') {
                $probe = Invoke-JobsCodegenFvmToolOnce $File @('api','context','--compress') $Directory -TimeoutSeconds 30
                if ($probe.ExitCode -ne 0) { throw 'FVM 缓存上下文无效，SDK 管理器需要人工修复。' }
                $context = ($probe.StdOut | ConvertFrom-Json -ErrorAction Stop).context
                if (-not [IO.Path]::IsPathRooted([string]$context.versionsCachePath)) { throw 'FVM 缓存上下文无效，缺少绝对 SDK 缓存目录。' }
                $sdk = Join-Path $context.versionsCachePath $Arguments[1]
                if (-not [IO.File]::Exists((Join-Path $sdk 'bin/flutter.bat')) -and -not [IO.File]::Exists((Join-Path $sdk 'bin/flutter.exe'))) { throw ('FVM 返回成功但 SDK 的 bin/flutter 尚未获取完整：' + $sdk) }
            }
            return $result
        }
    }
    return Invoke-JobsCodegenFvmToolOnce $File $Arguments $Directory -Visible:$Visible -TimeoutSeconds $TimeoutSeconds -LiveCapture:$LiveCapture
}
# 单次运行FVM工具并记录原生结果，不重放项目业务。
function Invoke-JobsCodegenFvmToolOnce {
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
# 按Windows原生argv规则转义依赖参数，不通过命令字符串求值。
function ConvertTo-JobsCodegenDependencyArgument {
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
# 运行隔离依赖子进程，保留原生交互、退出码和父进程环境。
function Invoke-JobsCodegenDependencyProcess {
    param([string]$Executable, [string[]]$NativeArguments, [string[]]$InputLines = @(), [switch]$Probe)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Executable
    $start.Arguments = (@($NativeArguments | ForEach-Object { ConvertTo-JobsCodegenDependencyArgument $_ }) -join ' ')
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
# 只刷新当前进程的工具搜索路径，不改用户或系统PATH。
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
# 只读发现当前用户已注册且能够运行的WinGet。
function Find-JobsWinget {
    $command = Get-Command 'winget.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $candidates = @()
    if ($command) { $candidates += $command.Source }
    if ($env:LOCALAPPDATA) { $candidates += Join-Path $env:LOCALAPPDATA 'Microsoft/WindowsApps/winget.exe' }
    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if (-not [IO.File]::Exists($candidate)) { continue }
        try { $probe = Invoke-JobsCodegenDependencyProcess $candidate @('--version') -Probe; if ($probe.Code -eq 0) { return $candidate } } catch [Management.Automation.PipelineStoppedException] { throw } catch { }
    }
    return $null
}
# 仅必需安装分支准备当前用户App Installer，一次打开官方界面并等待复检。
function Get-JobsRequiredWinget {
    $winget = Find-JobsWinget
    if ($winget) { return $winget }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw '当前不是 Windows，未调用 App Installer 或安装 Windows 依赖。' }
    Write-JobsCodegenDependencyStatus '本次需要 Windows 原生 App Installer/winget；仅注册当前用户已有组件，不接受许可或修改系统策略。'
    $registration = Get-Command Add-AppxPackage -ErrorAction SilentlyContinue
    if ($registration -and $registration.Parameters.ContainsKey('RegisterByFamilyName')) {
        try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop } catch { Write-JobsCodegenDependencyStatus ('App Installer 注册未就绪：' + $_.Exception.Message) }
        $winget = Find-JobsWinget
        if ($winget) { Update-JobsProcessPath ([IO.Path]::GetDirectoryName($winget)); return $winget }
    }
    Write-JobsCodegenDependencyStatus '官方 App Installer：https://apps.microsoft.com/detail/9NBLGGH4NNS1；将打开一次官方页面。请按系统要求完成安装/许可，本入口持续复检并续行，Ctrl+C 停止等待。'
    Start-Process -FilePath 'ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1' -ErrorAction Stop | Out-Null
    while ($true) {
        Update-JobsProcessPath
        $winget = Find-JobsWinget
        if ($winget) { return $winget }
        Write-JobsCodegenDependencyStatus '等待官方 App Installer 安装和当前用户注册；不会重复打开窗口，Ctrl+C 取消。'
        Start-Sleep -Seconds 3
    }
}
# 运行精确WinGet包请求并保留原生许可交互，输出经脱敏再记录。
function Invoke-JobsWingetPackage {
    param([string]$Winget, [string]$Package, [ValidateSet('install','upgrade','repair')][string]$Mode = 'install')
    $arguments = @($Mode, '--id', $Package, '--exact', '--source', 'winget', '--interactive')
    $arguments += @('--scope', 'user')
    $text = New-Object 'Collections.Generic.List[string]'
    $previous = $ErrorActionPreference
    $logFailure = $null
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        $ErrorActionPreference = 'Continue'
        $global:LASTEXITCODE = -1
        & $Winget @arguments 2>&1 | ForEach-Object { $line = [string]$_; $text.Add($line); try { Write-JobsCodegenDependencyStatus $line -ErrorAction Stop } catch { $logFailure = $_.Exception; throw } }
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous }
    if ($logFailure) { throw $logFailure }
    return [pscustomobject]@{ Code = $code; Text = $text -join "`n" }
}
# 将依赖诊断送往业务展示和日志，剥离控制码并隐藏敏感地址。
function Write-JobsCodegenDependencyStatus {
    [CmdletBinding()]
    param([string]$Text)
    Write-JobsFlutterMessage $Text
}
# 只读取本项目明确版本与来源；不沿父目录、不改配置，也不把未知 fork 换成 PATH SDK。
function Get-JobsCodegenBinding {
    param([string]$Project)
    $files = @{}; $version = ''; $source = ''; $paths = @()
    foreach ($entry in @(@{Path='.fvmrc';Key='flutter'},@{Path='.fvm/fvm_config.json';Key='flutterSdkVersion'})) {
        $path = Join-Path $Project $entry.Path
        $paths += $path
        if (-not (Test-JobsRunnerPathEntry $path)) { continue }
        Assert-JobsRunnerPlainFile $path
        if ((Get-Item -LiteralPath $path -Force).Length -gt 1MB) { throw 'FVM 配置超过 1 MiB，未准备工具。' }
        $files[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        $config = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $config.PSObject.Properties[$entry.Key]) { throw '项目 FVM 配置缺少精确版本，未推断或切换 SDK。' }
        $pin = [string]$config.($entry.Key)
        if ([string]::IsNullOrWhiteSpace($pin) -or $pin.Length -gt 200 -or $pin -match '[\x00-\x1f\x7f]') { throw '项目 FVM 版本声明无效，未准备工具。' }
        if ($version -and $version -cne $pin) { throw '当前根的两份 FVM 配置版本冲突，未准备工具。' }
        $version = $pin
        if ($null -ne $config.PSObject.Properties['flutterUrl']) {
            $url = [string]$config.flutterUrl
            if ($source -and $source -cne $url) { throw '当前根的 FVM SDK 来源冲突，未准备工具。' }
            $source = $url
        }
    }
    return [pscustomobject]@{Version=$version;Source=$source;Files=$files;Paths=$paths}
}
# 复核项目SDK声明和来源未变，阻止在准备途中改写或切换绑定。
function Assert-JobsCodegenBindingUnchanged {
    param($Binding)
    foreach ($path in @($Binding.Paths)) { if (-not $Binding.Files.ContainsKey($path) -and (Test-JobsRunnerPathEntry $path)) { throw '准备期间出现新的FVM配置，已停止生成，未覆盖配置。' } }
    foreach ($path in $Binding.Files.Keys) {
        Assert-JobsRunnerPlainFile $path
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $Binding.Files[$path]) { throw '选定项目的 FVM 配置在准备期间改变，已停止生成，未覆盖配置。' }
    }
}
# 原生工具仅在确认后的必要分支获取；scope=user、原生许可、精确包和本进程PATH保持。
function Find-JobsCodegenNativeTool {
    param([string]$Name)
    $tool = Find-JobsExecutable -Name $Name -Candidates @($Name -replace '\.exe$','')
    if (-not $tool) { return $null }
    try {
        $probe = Invoke-JobsCodegenDependencyProcess $tool @('--version') -Probe
        if ($probe.Code -eq 0 -and $probe.Lines.Count -gt 0) { return $tool }
    } catch [Management.Automation.PipelineStoppedException] { throw } catch { }
    return $null
}
# 明确同意后仅获取本项目生成计划必需的精确原生工具并复检。
function Get-JobsCodegenNativeTool {
    param([string]$Package,[string]$Name)
    $tool = Find-JobsCodegenNativeTool $Name
    if ($tool) { Update-JobsProcessPath ([IO.Path]::GetDirectoryName($tool)); return $tool }
    $winget = Get-JobsRequiredWinget
    $mode = 'install'; $delay = 1
    if (Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue) { $mode = 'repair' }
    while ($true) {
        Write-JobsCodegenDependencyStatus ('必要工具：'+$Package+'；仅当前用户'+$mode+'，原生许可由本人处理。')
        $result = Invoke-JobsWingetPackage $winget $Package $mode
        if ($result.Code -in @(130,1223,1602,-1073741510,-2147023673)) { throw (New-Object OperationCanceledException('已取消必要工具准备。')) }
        if ($result.Code -eq 0) {
            Update-JobsProcessPath
            $tool = Find-JobsCodegenNativeTool $Name
            if ($tool) { Update-JobsProcessPath ([IO.Path]::GetDirectoryName($tool)); return $tool }
            if ($mode -ceq 'install') { $mode='repair'; continue }
            throw '必要工具安装及修复后实际选项体检仍失败，未继续生成。'
        }
        $safe = $result.Text -replace '\x1b\][^\x07]*(?:\x07|\x1b\\)', '' -replace '\x1b\[[0-?]*[ -/]*[@-~]', ''
        $safe = $safe -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@' -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]'
        if ($safe -match '(?i)permission|access.denied|no.space|disk.full|hash|checksum|certificate|unauthor|license|agreement|unsupported|not.supported|unknown.command|unrecognized|no.applicable|not.found|权限|拒绝|空间不足|许可|协议|不支持|未知命令|无法找到|无适用') { throw ('必要工具遇到明确阻塞：'+$safe) }
        Write-JobsCodegenDependencyStatus ('工具获取网络失败，'+$delay+'秒后继续；Ctrl+C停止。')
        Start-Sleep -Seconds $delay; $delay=[Math]::Min(30,$delay*2)
    }
}
# 此函数只能从明确同意后的主流程调用；SDK未绑定且无健康PATH时不猜版本。
function New-JobsCodegenFvmInspection {
    param([string]$Project,$Binding,$Context)
    $root=Get-JobsInstallRoot
    [void](Assert-JobsRunnerDirectory $root)
    $inspection=Join-Path $root ('codegen-sdk-inspection-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($inspection)
    $config=[pscustomobject]@{}
    $modern=Join-Path $Project '.fvmrc'
    if ($Binding.Files.ContainsKey($modern)) { $config=Get-Content -LiteralPath $modern -Raw -Encoding UTF8|ConvertFrom-Json -ErrorAction Stop }
    $config|Add-Member -NotePropertyName flutter -NotePropertyValue $Binding.Version -Force
    $config|Add-Member -NotePropertyName flutterUrl -NotePropertyValue ([string]$Context.flutterUrl) -Force
    $config|Add-Member -NotePropertyName cachePath -NotePropertyValue (Split-Path -Parent ([string]$Context.versionsCachePath)) -Force
    $config|Add-Member -NotePropertyName updateMelosSettings -NotePropertyValue $false -Force
    [IO.File]::WriteAllText((Join-Path $inspection '.fvmrc'),($config|ConvertTo-Json -Depth 100)+[Environment]::NewLine,(New-Object Text.UTF8Encoding($false)))
    [IO.File]::Copy((Join-Path $Project 'pubspec.yaml'),(Join-Path $inspection 'pubspec.yaml'))
    return $inspection
}
# 在同意后的写流程准备项目声明的精确SDK，保持原绑定与来源。
function Get-JobsCodegenRequiredSdk {
    param([string]$Project)
    $binding = Get-JobsCodegenBinding $Project
    $sdk = $null
    try { $sdk = Get-JobsFlutterSdk $Project } catch {
        if (-not $binding.Version) { throw '当前项目没有可复用 SDK，也未声明精确 FVM 版本；请先明确本项目的 SDK 版本配置，未安装任意最新版或替换来源。' }
    }
    if ($null -eq $sdk) {
        if ($binding.Version -cnotmatch '^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$') { throw '缺失的项目 SDK 没有精确可验证的数字版本；保留未知fork/channel绑定，未猜测或替换SDK。' }
        [void](Get-JobsCodegenNativeTool 'Git.Git' 'git.exe')
        $candidates = @('fvm.bat','fvm.cmd')
        $pointer = Join-Path (Get-JobsInstallRoot) 'tools/fvm-path.txt'
        if (Test-Path -LiteralPath $pointer -PathType Leaf) { $candidates += (Get-Content -LiteralPath $pointer -Raw -Encoding UTF8).Trim() }
        $fvm = Find-JobsCodegenHealthyFvmTool 'fvm.exe' $candidates $Project
        if (-not $fvm) { $fvm = Install-JobsCodegenStandaloneFvm $Project }
        $before = Invoke-JobsCodegenFvmTool $fvm @('api','context','--compress') $Project
        if ($before.ExitCode -ne 0) { throw 'FVM 缓存上下文无效，未准备项目 SDK。' }
        $context = ($before.StdOut | ConvertFrom-Json -ErrorAction Stop).context
        if ($null -eq $context -or -not [IO.Path]::IsPathRooted([string]$context.versionsCachePath) -or [string]::IsNullOrWhiteSpace([string]$context.flutterUrl)) { throw 'FVM 缓存上下文无效，缺少绝对缓存或来源。' }
        if ($binding.Source -and $binding.Source -cne [string]$context.flutterUrl) { throw 'FVM 实际来源与项目声明不同，未下载其它来源 SDK。' }
        Write-JobsFlutterMessage ('准备本项目明确版本 '+$binding.Version+'；来源：'+$context.flutterUrl+'；缓存：'+$context.versionsCachePath+'；不执行fvm use或重写绑定。')
        # 所有FVM安装动作留在私有影子项目，真实项目绑定只读；先验证影子上下文没有改变来源或缓存。
        $inspection=New-JobsCodegenFvmInspection $Project $binding $context
        $shadow=Invoke-JobsCodegenFvmTool $fvm @('api','context','--compress') $inspection
        if ($shadow.ExitCode -ne 0) { throw ('FVM影子上下文无法验证，现场保留：'+$inspection) }
        $shadowContext=($shadow.StdOut|ConvertFrom-Json -ErrorAction Stop).context
        if ($shadowContext.versionsCachePath -cne $context.versionsCachePath -or $shadowContext.flutterUrl -cne $context.flutterUrl) { throw ('影子项目未保留原SDK来源或缓存，未下载，现场保留：'+$inspection) }
        $install = Invoke-JobsCodegenFvmTool $fvm @('install',$binding.Version,'--skip-pub-get') $inspection -TimeoutSeconds 3600
        if ($install.ExitCode -ne 0) { throw 'FVM 精确版本获取失败，未继续生成。' }
        Assert-JobsCodegenBindingUnchanged $binding
        $after = Invoke-JobsCodegenFvmTool $fvm @('api','context','--compress') $inspection
        if ($after.ExitCode -ne 0) { throw 'FVM SDK 获取后的上下文复检失败。' }
        $current = ($after.StdOut | ConvertFrom-Json -ErrorAction Stop).context
        if ($current.versionsCachePath -cne $context.versionsCachePath -or $current.flutterUrl -cne $context.flutterUrl) { throw 'FVM 缓存或 SDK 来源在准备期间改变，未继续生成。' }
        $bin = Join-Path (Join-Path $context.versionsCachePath $binding.Version) 'bin'
        $flutter = Join-Path $bin 'flutter.bat'; if (-not [IO.File]::Exists($flutter)) { $flutter=Join-Path $bin 'flutter.exe' }
        $dart = Join-Path $bin 'dart.bat'; if (-not [IO.File]::Exists($dart)) { $dart=Join-Path $bin 'dart.exe' }
        if (-not [IO.File]::Exists($flutter) -or -not [IO.File]::Exists($dart)) { throw 'FVM 返回成功但精确缓存 SDK 不完整，未继续生成。' }
        $sdk=[pscustomobject]@{Flutter=$flutter;Dart=$dart}
        Write-JobsFlutterMessage ('影子准备记录保留：'+$inspection+'；真实项目绑定未写入。')
    }
    $probe = Invoke-JobsSdkAcquireProcess (New-JobsFlutterToolStartInfo $sdk.Flutter @('--version','--machine') $Project) 300 -Sanitize -Label '选定项目 Flutter SDK 初始化'
    $actual = ConvertFrom-JobsSdkMachineOutput $probe.StdOut
    if ($binding.Version -cmatch '^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$' -and [string]$actual.frameworkVersion -cne $binding.Version) { throw '实际 SDK 版本与本项目 FVM 精确声明不同，未运行生成器。' }
    if ($binding.Version -cmatch '^custom_jobs_ohos_([0-9a-f]{40})$' -and [string]$actual.frameworkRevision -cne $Matches[1]) { throw '健康路径的实际OpenHarmony commit与项目绑定不同，未运行生成器。' }
    Invoke-JobsFlutterTool $sdk.Dart @('--version') $Project 300
    Assert-JobsCodegenBindingUnchanged $binding
    return $sdk
}
# Dart插件独立于全局PUB_CACHE，protoc显式指定插件路径，不把它添加到父进程PATH。
function Get-JobsCodegenProtobufTools {
    param($Sdk,[string]$Project)
    $protoc = Get-JobsCodegenNativeTool 'Google.Protobuf' 'protoc.exe'
    $hasher=[Security.Cryptography.SHA256]::Create()
    try { $key=([BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($Sdk.Dart))))).Replace('-','').Substring(0,16).ToLowerInvariant() } finally { $hasher.Dispose() }
    $cache=Join-Path (Join-Path (Get-JobsInstallRoot) 'tools/protoc-plugin') $key
    $existing=$cache
    while (-not [IO.Directory]::Exists($existing)) { $existing=Split-Path -Parent $existing; if (-not $existing) { throw '私有插件缓存没有可靠父目录。' } }
    [void](Assert-JobsRunnerDirectory $existing)
    [void][IO.Directory]::CreateDirectory($cache); [void](Assert-JobsRunnerDirectory $cache)
    $listStart=New-JobsFlutterToolStartInfo $Sdk.Dart @('pub','global','list') $Project; $listStart.EnvironmentVariables['PUB_CACHE']=$cache
    $list=Invoke-JobsSdkLiveProcess $listStart 120 -Sanitize
    $plugin=Join-Path $cache 'bin/protoc-gen-dart.bat'
    if ($list.ExitCode -ne 0 -or $list.StdOut -notmatch '(?m)^protoc_plugin\s+\S+\s*$' -or -not [IO.File]::Exists($plugin)) {
        $start=New-JobsFlutterToolStartInfo $Sdk.Dart @('pub','global','activate','protoc_plugin') $Project; $start.EnvironmentVariables['PUB_CACHE']=$cache
        [void](Invoke-JobsSdkAcquireProcess $start 600 -Sanitize -Label '当前Dart SDK的私有protoc_plugin')
        $list=Invoke-JobsSdkLiveProcess $listStart 120 -Sanitize
    }
    if ($list.ExitCode -ne 0 -or $list.StdOut -notmatch '(?m)^protoc_plugin\s+\S+\s*$' -or -not [IO.File]::Exists($plugin)) { throw '私有protoc_plugin准备后复检失败，未执行生成器。' }
    Assert-JobsRunnerPlainFile $plugin
    return [pscustomobject]@{Protoc=$protoc;Plugin=$plugin;PubCache=$cache}
}
# JOBS_CODEGEN_REQUIRED_TOOLS_V1_END

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
    throw '项目 FVM SDK 缺失；不会回退全局 Flutter。'
}
# 统一生成器展示与日志，清除原生控制码并隐藏敏感地址。
function Write-JobsFlutterMessage {
    param([string]$Message)
    $Message = $Message -replace '\x1b\][^\x07]*(?:\x07|\x1b\\)', '' -replace '\x1b\[[0-?]*[ -/]*[@-~]', ''
    $safe = $Message -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@'
    $safe = $safe -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]'
    $safe = $safe -replace '(?im)((?:access[_-]?token|authorization|password|secret)\s*[:=]\s*)\S+', '$1[已省略]'
    Write-JobsEnterChoiceText $safe
    Write-JobsLog $safe
}

function Get-JobsFlutterSdk {
    param([string]$Project)
    $flutter = Get-JobsRunnerFlutter $Project
    $bin = Split-Path -Parent $flutter
    $dart = Join-Path $bin 'dart.bat'
    if (-not [IO.File]::Exists($dart)) { $dart = Join-Path $bin 'dart.exe' }
    if (-not [IO.File]::Exists($dart)) { throw 'Flutter SDK 缺少同目录 Dart；请修复 SDK。不会改用其它 Dart 版本。' }
    return [pscustomobject]@{ Flutter = $flutter; Dart = $dart }
}

function New-JobsFlutterToolStartInfo {
    param([string]$Executable, [string[]]$Arguments, [string]$Project)
    if ($Executable -match '["\x00-\x1f]' -or @($Arguments | Where-Object { $_ -match '["\x00-\x1f]' }).Count -gt 0) {
        throw '工具路径或参数含引号、控制字符，停止执行。'
    }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Executable
    $start.Arguments = @($Arguments | ForEach-Object { Quote-JobsArgument $_ }) -join ' '
    if ([IO.Path]::GetExtension($Executable) -in @('.bat', '.cmd')) {
        $start.FileName = Join-Path ([Environment]::GetFolderPath('System')) 'cmd.exe'
        $start.EnvironmentVariables['JOBS_FLUTTER_TOOL'] = $Executable
        $references = @()
        for ($i = 0; $i -lt $Arguments.Count; $i++) {
            $name = 'JOBS_FLUTTER_ARG_' + $i
            $start.EnvironmentVariables[$name] = $Arguments[$i]
            $references += ('"%' + $name + '%"')
        }
        # 路径与参数经环境变量单次展开，延迟展开关闭；不将项目数据拼成可执行语句。
        $start.Arguments = '/d /v:off /s /c ""%JOBS_FLUTTER_TOOL%" ' + ($references -join ' ') + '"'
    }
    $start.WorkingDirectory = $Project
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $start.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    $start.EnvironmentVariables['CI'] = 'true'
    $start.EnvironmentVariables['FLUTTER_SUPPRESS_ANALYTICS'] = 'true'
    $start.EnvironmentVariables['DART_SUPPRESS_ANALYTICS'] = 'true'
    return $start
}
# 保留项目工具路由和退出语义，附加环境只作用于本次子进程。
function Invoke-JobsFlutterTool {
    param([string]$Executable, [string[]]$Arguments, [string]$Project, [int]$TimeoutSeconds = 1800, [hashtable]$ToolEnvironment = @{})
    Write-JobsFlutterMessage ('执行：' + $Executable + ' ' + ($Arguments -join ' '))
    if ($Arguments -contains '--version') {
        [void](Invoke-JobsSdkAcquireProcess (New-JobsFlutterToolStartInfo $Executable $Arguments $Project) $TimeoutSeconds -Sanitize -Label 'Flutter/Dart 首次初始化')
        return
    }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = New-JobsFlutterToolStartInfo $Executable $Arguments $Project
    foreach ($key in $ToolEnvironment.Keys) { $process.StartInfo.EnvironmentVariables[$key] = [string]$ToolEnvironment[$key] }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadLineAsync()
        $stderr = $process.StandardError.ReadLineAsync()
        while ($null -ne $stdout -or $null -ne $stderr) {
            if ($watch.Elapsed.TotalSeconds -gt $TimeoutSeconds) {
                if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
                    $taskkill = Join-Path ([Environment]::GetFolderPath('System')) 'taskkill.exe'
                    [void](Invoke-JobsProcess -FilePath $taskkill -Arguments @('/PID', [string]$process.Id, '/T', '/F') -TimeoutSeconds 15)
                } elseif (-not $process.HasExited) { $process.Kill() }
                throw '工具执行超时，已请求终止本次进程树。'
            }
            if ($null -ne $stdout -and $stdout.IsCompleted) {
                $line = $stdout.GetAwaiter().GetResult()
                $stdout = $null
                if ($null -ne $line) { Write-JobsFlutterMessage $line; $stdout = $process.StandardOutput.ReadLineAsync() }
            }
            if ($null -ne $stderr -and $stderr.IsCompleted) {
                $line = $stderr.GetAwaiter().GetResult()
                $stderr = $null
                if ($null -ne $line) { Write-JobsFlutterMessage $line; $stderr = $process.StandardError.ReadLineAsync() }
            }
            Start-Sleep -Milliseconds 30
        }
        $remaining = [int][Math]::Max(1, ($TimeoutSeconds - $watch.Elapsed.TotalSeconds) * 1000)
        if (-not $process.WaitForExit($remaining)) {
            if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
                $taskkill = Join-Path ([Environment]::GetFolderPath('System')) 'taskkill.exe'
                [void](Invoke-JobsProcess -FilePath $taskkill -Arguments @('/PID', [string]$process.Id, '/T', '/F') -TimeoutSeconds 15)
            } else { $process.Kill() }
            throw '工具输出关闭后仍未退出，已请求终止本次进程树。'
        }
        if ($process.ExitCode -ne 0) { throw ('工具失败（退出码 ' + $process.ExitCode + '），后续步骤已停止。') }
    } finally { $process.Dispose() }
}
function Get-JobsYamlSection {
    # 只解释根映射及其直接成员；flow map / block map 均不执行 YAML 对象构造。
    param([string]$Text, [string]$Name)
    $lines = @($Text.TrimStart([char]0xfeff) -split '\r?\n' | ForEach-Object { Remove-JobsYamlComment $_ })
    $roots = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -cmatch '^(?<key>[A-Za-z_][A-Za-z0-9_-]*|''[^'']+''|"[^"\\]+")\s*:\s*(?<value>.*)$') {
            if ((ConvertFrom-JobsYamlAtom $Matches['key']) -ceq $Name) { $roots += [pscustomobject]@{ Index = $i; Value = $Matches['value'] } }
        }
    }
    if ($roots.Count -gt 1) { throw ('pubspec.yaml 重复根键：' + $Name) }
    if ($roots.Count -eq 0) { return $null }
    if ($roots[0].Value.Trim().Length -gt 0) { return ,(ConvertFrom-JobsYamlFlowMap $roots[0].Value) }
    $result = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    $minimum = $null
    for ($i = $roots[0].Index + 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -notmatch '^ ') { break }
        $indent = $line.Length - $line.TrimStart(' ').Length
        if ($null -eq $minimum) { $minimum = $indent }
        if ($indent -ne $minimum) { continue }
        if ($line -notmatch '^ +(?<key>[A-Za-z_][A-Za-z0-9_-]*|''[^'']+''|"[^"\\]+")\s*:\s*(?<value>.*)$') { throw ('无法可靠读取 pubspec.yaml 的 ' + $Name + ' 映射。') }
        $key = ConvertFrom-JobsYamlAtom $Matches['key']
        $value = $Matches['value']
        if ($result.ContainsKey($key)) { throw ('pubspec.yaml 重复成员：' + $Name + '.' + $key) }
        $result[$key] = $value
    }
    return ,$result
}

function Test-JobsCodegenConfigFile {
    param([string]$Project, [string]$Relative)
    $file = Join-Path $Project $Relative
    if (-not (Test-JobsRunnerPathEntry $file)) { return $false }
    [void](Assert-JobsRunnerDirectory (Split-Path -Parent $file))
    Assert-JobsRunnerPlainFile $file
    return $true
}

function Get-JobsCodegenPlan {
    param([string]$Project)
    Assert-JobsFlutterProject $Project
    $text = Get-Content -LiteralPath (Join-Path $Project 'pubspec.yaml') -Raw -Encoding UTF8
    $dependencies = Get-JobsYamlSection $text 'dependencies'
    $devDependencies = Get-JobsYamlSection $text 'dev_dependencies'
    $direct = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($map in @($dependencies, $devDependencies)) {
        if ($null -ne $map) { foreach ($key in $map.Keys) { [void]$direct.Add($key) } }
    }
    $steps = @()
    if ($direct.Contains('build_runner')) { $steps += [pscustomobject]@{ Name = 'build_runner'; Tool = 'Dart'; Arguments = @('run', 'build_runner', 'build') } }
    foreach ($name in @('flutter_launcher_icons', 'flutter_native_splash', 'ffigen')) {
        if (-not $direct.Contains($name)) { continue }
        $config = Get-JobsYamlSection $text $name
        $file = $name + '.yaml'
        $hasFile = Test-JobsCodegenConfigFile $Project $file
        if ($null -eq $config -and -not $hasFile) { Write-Host ('跳过 ' + $name + '：只有依赖，没有明确配置。'); continue }
        $arguments = @('run', $name)
        if ($name -eq 'flutter_native_splash') { $arguments = @('run', 'flutter_native_splash:create') }
        if ($hasFile) {
            if ($name -eq 'flutter_native_splash') { $arguments += ('--path=' + $file) }
            elseif ($name -eq 'flutter_launcher_icons') { $arguments += @('-f', $file) }
            else { $arguments += @('--config', $file) }
        }
        $steps += [pscustomobject]@{ Name = $name; Tool = 'Dart'; Arguments = $arguments }
    }
    $flutter = Get-JobsYamlSection $text 'flutter'
    $generate = $null -ne $flutter -and $flutter.ContainsKey('generate') -and (ConvertFrom-JobsYamlAtom $flutter['generate']) -ceq 'true'
    $hasL10nConfig = Test-JobsCodegenConfigFile $Project 'l10n.yaml'
    $arbDirectory = Join-Path $Project 'lib/l10n'
    $hasArb = $false
    if ([IO.Directory]::Exists($arbDirectory)) {
        [void](Assert-JobsRunnerDirectory $arbDirectory)
        $hasArb = @(Get-ChildItem -LiteralPath $arbDirectory -Filter '*.arb' -File).Count -gt 0
    }
    if ($generate -and ($hasL10nConfig -or $hasArb)) { $steps += [pscustomobject]@{ Name = 'l10n'; Tool = 'Flutter'; Arguments = @('gen-l10n') } }
    if ($direct.Contains('pigeon') -and (Test-JobsCodegenConfigFile $Project 'pigeons/messages.dart')) {
        $pigeon = Get-Content -LiteralPath (Join-Path $Project 'pigeons/messages.dart') -Raw -Encoding UTF8
        $pigeon = $pigeon -replace '(?s)/\*.*?\*/', '' -replace '(?m)//.*$', ''
        if ($pigeon -cmatch '(?m)^\s*@(?:[A-Za-z_]\w*\.)?ConfigurePigeon\s*\(') {
            $steps += [pscustomobject]@{ Name = 'pigeon'; Tool = 'Dart'; Arguments = @('run', 'pigeon', '--input', 'pigeons/messages.dart') }
        } else { Write-Host '跳过 pigeon：messages.dart 缺少 @ConfigurePigeon 输出配置。' }
    }
    $protoDirectory = Join-Path $Project 'protos'
    if ($direct.Contains('protobuf') -and [IO.Directory]::Exists($protoDirectory)) {
        [void](Assert-JobsRunnerDirectory $protoDirectory)
        $protos = @(Get-ChildItem -LiteralPath $protoDirectory -Filter '*.proto' -File | Sort-Object Name)
        if ($protos.Count -gt 0) {
            $arguments = @('--dart_out=lib/generated', '-Iprotos')
            if ($direct.Contains('grpc')) { $arguments[0] = '--dart_out=grpc:lib/generated' }
            foreach ($proto in $protos) { Assert-JobsRunnerPlainFile $proto.FullName; $arguments += ('protos/' + $proto.Name) }
            $steps += [pscustomobject]@{ Name = 'protobuf'; Tool = 'Protoc'; Arguments = $arguments }
        }
    }
    return $steps
}
# 显示生成计划写入确认，仅接受原约定的明确同意。
function Read-JobsCodegenConsent {
    # ReadLine 保留 EOF 和空行差别：只有真实回车才代表执行，EOF 不构成授权。
    Write-JobsEnterChoiceText '回车执行上述步骤；任意非空输入取消：' -NoNewline -Question
    $answer = [Console]::ReadLine()
    return $null -ne $answer -and $answer.Length -eq 0
}

function ConvertFrom-JobsCodegenDeleteAnswer {
    param([AllowNull()]$Answer)
    if ($null -eq $Answer) { throw '输入已关闭；停止执行，未获取依赖或生成文件。' }
    return $Answer -ceq 'YES'
}
# 显示生成文件删除确认，保留原精确确认词与取消行为。
function Read-JobsCodegenDeleteConsent {
    Write-JobsEnterChoiceText '可选：输入 YES 明确允许 build_runner 删除冲突产物；回车保留默认行为：' -NoNewline -Question
    $answer = [Console]::ReadLine()
    return ConvertFrom-JobsCodegenDeleteAnswer $answer
}
# 先展示计划并确认，再准备必要工具和执行项目生成步骤。
function Invoke-JobsFlutterCodegenAction {
    param([string]$Target)
    $project = Assert-JobsRunnerDirectory $Target
    Write-JobsFlutterMessage ('Flutter 自动化生产代码；项目：' + $project)
    $plan = @(Get-JobsCodegenPlan $project)
    if ($plan.Count -eq 0) { Write-JobsFlutterMessage '没有已配置的生成器；确认后仅运行 flutter pub get。' }
    Write-JobsFlutterMessage '将运行 flutter pub get（可能联网并修改 pubspec.lock / .dart_tool），随后按项目配置改写生成文件；生成器可运行项目自己的构建逻辑。'
    Write-JobsFlutterMessage '确认后仅为本项目已声明的精确SDK准备必要Git/FVM/SDK；Protobuf计划才获取protoc及私有插件。许可和系统权限由本人处理；未知版本不猜测，取消不开始准备。'
    foreach ($step in $plan) { Write-JobsFlutterMessage ('计划：' + $step.Name + ' → ' + ($step.Arguments -join ' ')) }
    if (-not (Read-JobsCodegenConsent)) { Write-JobsFlutterMessage '已取消；未执行 pub get 或生成。'; return }
    $delete = $false
    if (@($plan | Where-Object Name -eq 'build_runner').Count -gt 0) { $delete = Read-JobsCodegenDeleteConsent }
    # 确认后再次校验项目，避免预览期间目录或配置文件被替换成链接。
    Assert-JobsFlutterProject $project
    $sdk = Get-JobsCodegenRequiredSdk $project
    $protobuf = $null
    if (@($plan | Where-Object Tool -eq 'Protoc').Count -gt 0) { $protobuf = Get-JobsCodegenProtobufTools $sdk $project }
    Invoke-JobsFlutterTool $sdk.Flutter @('--version') $project 300
    Invoke-JobsFlutterTool $sdk.Flutter @('pub', 'get') $project
    foreach ($step in $plan) {
        $arguments = @($step.Arguments)
        if ($step.Name -eq 'build_runner' -and $delete) { $arguments += '--delete-conflicting-outputs' }
        $executable = $sdk.Dart
        if ($step.Tool -eq 'Flutter') { $executable = $sdk.Flutter }
        if ($step.Tool -eq 'Protoc') {
            $executable = $protobuf.Protoc
            $arguments = @(('--plugin=protoc-gen-dart=' + $protobuf.Plugin)) + $arguments
            $lib = Join-Path $project 'lib'
            if (Test-JobsRunnerPathEntry $lib) { [void](Assert-JobsRunnerDirectory $lib) }
            $output = Join-Path $project 'lib/generated'
            if (Test-JobsRunnerPathEntry $output) { [void](Assert-JobsRunnerDirectory $output) }
            [void][IO.Directory]::CreateDirectory($output)
        }
        $environment = @{}
        if ($step.Tool -eq 'Protoc') { $environment.PUB_CACHE = $protobuf.PubCache }
        Invoke-JobsFlutterTool $executable $arguments $project -ToolEnvironment $environment
    }
    Write-JobsFlutterMessage '全部生成步骤完成。请审查项目 diff 后再提交。'
}

function Invoke-JobsFeature {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Target)
    Invoke-JobsFlutterCodegenAction -Target (Resolve-JobsTarget $Target)
}
Export-ModuleMember -Function Invoke-JobsFeature

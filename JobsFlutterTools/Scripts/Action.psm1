# Unified Flutter menu actions. Project-local FVM only; never install or select global Flutter.

# Jobs enter-choice emphasis is display-only; input and business decisions stay with callers.
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

function Get-JobsToolsFvm {
    param([string]$Project)
    $modern = Join-Path $Project '.fvmrc'
    $legacy = Join-Path $Project '.fvm/fvm_config.json'
    if (-not [IO.File]::Exists($modern) -and -not [IO.File]::Exists($legacy)) { throw '项目尚未通过 FVM 绑定 SDK。请先使用安装/切换Flutter SDK版本；不会回退全局 Flutter。' }
    $configPath = if ([IO.File]::Exists($modern)) { $modern } else { $legacy }
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $pin = if ($config.PSObject.Properties['flutter']) { $config.flutter } elseif ($config.PSObject.Properties['flutterSdkVersion']) { $config.flutterSdkVersion } else { $null }
    if ($pin -isnot [string] -or [string]::IsNullOrWhiteSpace($pin)) { throw 'FVM 版本声明无效。' }
    $flutter = Join-Path $Project '.fvm/flutter_sdk/bin/flutter.bat'
    $dart = Join-Path $Project '.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dart.exe'
    if (-not [IO.File]::Exists($flutter) -or -not [IO.File]::Exists($dart)) { throw '项目 FVM SDK 不完整，请通过版本管理入口修复。' }
    return [pscustomobject]@{ Flutter = $flutter; Dart = $dart }
}

function Repair-JobsToolsAndroidSdk {
    param([string]$Project)
    if (-not [IO.Directory]::Exists((Join-Path $Project 'android'))) { throw '本项目没有 android/ 平台目录。' }
    Write-Host ('修复 Android SDK / platforms 缺失；项目：' + $Project)
    Write-Host '补齐官方 SDK、Java 与构建组件；许可由本人确认，只更新项目 local.properties，不修改全局 Flutter 或 PATH。'
    if ((Read-JobsEnterChoiceHost '回车继续，任意非空输入取消') -ne '') { return }
    $support = Import-Module (Join-Path $PSScriptRoot 'Actions/android-support/Scripts/Action.psm1') -PassThru -DisableNameChecking
    & $support {
        param($Project)
        [void](Get-JobsAndroidArchitecture)
        $sdk = Get-JobsAndroidSdk
        $localConfig = Join-Path $Project 'android/local.properties'
        if ([IO.File]::Exists($localConfig)) {
            if ((Get-Item -LiteralPath $localConfig).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'local.properties 是链接。' }
            if ([IO.File]::ReadAllText($localConfig) -match '(?m)^\s*sdk\.dir\s*=\s*(.+)$') {
                $sdk = [regex]::Replace($Matches[1].TrimEnd("`r"), '\\([\\:=#! ])', '$1')
                if (-not [IO.Path]::IsPathRooted($sdk)) { throw '项目 sdk.dir 必须是绝对路径。' }
            }
        }
        [void][IO.Directory]::CreateDirectory($sdk)
        $java = Get-JobsAndroidJava
        $tools = Get-JobsAndroidHealthyTools $sdk $java
        $listing = Invoke-JobsAndroidTool $java $tools 'sdkmanager' @(('--sdk_root=' + $sdk), '--list', '--channel=0') -TimeoutSeconds 120
        $api = $null
        foreach ($relative in @('android/app/build.gradle', 'android/app/build.gradle.kts', '.fvm/flutter_sdk/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt')) {
            $source = Join-Path $Project $relative
            if ([IO.File]::Exists($source) -and [IO.File]::ReadAllText($source) -match 'compileSdk(?:Version)?\s*(?:=\s*)?(\d+)') { $api = $Matches[1]; break }
        }
        if (-not $api) {
            $apis = @([regex]::Matches($listing, '(?m)^\s*platforms;android-(\d+)\s*\|') | ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object)
            if ($apis.Count -eq 0) { throw '无法确定稳定 Android platform。' }
            $api = [string]$apis[-1]
        }
        $builds = @([regex]::Matches($listing, '(?m)^\s*build-tools;(\d+\.\d+\.\d+)\s*\|') | ForEach-Object { [version]$_.Groups[1].Value } | Sort-Object)
        if ($builds.Count -eq 0) { throw '无法确定稳定 build-tools。' }
        $build = [string]$builds[-1]
        foreach ($relative in @('android/app/build.gradle', 'android/app/build.gradle.kts')) {
            $source = Join-Path $Project $relative
            if ([IO.File]::Exists($source) -and [IO.File]::ReadAllText($source) -match 'buildToolsVersion\s*(?:=\s*)?["''](\d+\.\d+\.\d+)') { $build = $Matches[1]; break }
        }
        $required = @{
            'platform-tools' = 'platform-tools/adb.exe'
            ('platforms;android-' + $api) = ('platforms/android-' + $api + '/android.jar')
            ('build-tools;' + $build) = ('build-tools/' + $build + '/aapt2.exe')
        }
        foreach ($package in ($required.Keys | Sort-Object)) {
            if (-not [IO.File]::Exists((Join-Path $sdk $required[$package]))) {
                Invoke-JobsAndroidTool $java $tools 'sdkmanager' @(('--sdk_root=' + $sdk), '--install', $package, '--channel=0') -Interactive
            }
            if (-not [IO.File]::Exists((Join-Path $sdk $required[$package]))) { throw ('组件安装后复检失败：' + $package) }
        }
        $config = Join-Path $Project 'android/local.properties'
        $before = ''
        if ([IO.File]::Exists($config)) {
            if ((Get-Item -LiteralPath $config).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'local.properties 是链接，未写入。' }
            $before = [IO.File]::ReadAllText($config)
        }
        $backup = Join-Path $Project ('android/.jobs-sdk-backup-' + [guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($backup)
        [IO.File]::WriteAllText((Join-Path $backup 'local.properties'), $before, (New-Object Text.UTF8Encoding($false)))
        $next = [regex]::Replace($before, '(?m)^sdk\.dir\s*=.*(?:\r?\n|$)', '')
        $escaped = $sdk.Replace('\', '\\').Replace(':', '\:').Replace(' ', '\ ')
        $next = $next.TrimEnd("`r", "`n") + "`r`nsdk.dir=" + $escaped + "`r`n"
        [IO.File]::WriteAllText($config, $next, (New-Object Text.UTF8Encoding($false)))
        Write-Host ('SDK 组件已验证，项目 sdk.dir 已修复；备份：' + $backup)
    } $Project
}

function Invoke-JobsFeature {
    param([string]$Target, [ValidateSet('run','pub-get','extract','export-private-dependencies','import-private-dependencies','export-all-dependencies','import-all-dependencies','import-dependencies','sdk-version','sdk-manage','ohos-sdk-manage','java-manage','android-dependencies','ohos-dependencies','native-dependencies','flutter-precache','web-dependencies','export-gradle-dependencies','import-gradle-dependencies','export-ohos-dependencies','import-ohos-dependencies','export-native-dependencies','import-native-dependencies','export-precache-dependencies','import-precache-dependencies','export-web-dependencies','import-web-dependencies','gradle-download','project-setup','package','build-harmony','codegen','native-doctor','harmony-doctor','maintenance','repair-android','repair-imports','repair-namespace')][string]$Action)
    $project = Resolve-JobsTarget $Target
    if ($Action -eq 'run') {
        $runner = Import-Module (Join-Path $PSScriptRoot 'Actions/run/Scripts/Action.psm1') -PassThru -DisableNameChecking
        & $runner { param($Path) Invoke-JobsFeature -Target $Path } $project
        return
    }
    if (-not [IO.File]::Exists((Join-Path $project 'pubspec.yaml')) -or ($Action -notin @('import-dependencies','import-private-dependencies','export-all-dependencies','import-all-dependencies') -and -not [IO.Directory]::Exists((Join-Path $project 'lib')))) { throw '请选择 Flutter 工程根目录。' }
    if ($Action -in @('export-all-dependencies','import-all-dependencies')) {
        $migration = Import-Module (Join-Path $PSScriptRoot 'FlutterDependencyMigration.psm1/FlutterDependencyMigration.psm1') -PassThru -DisableNameChecking
        & $migration { param($p,$a) Invoke-JobsFlutterMigration -Project $p -Action $a } $project $Action
        return
    }
    if ($Action -in @('export-private-dependencies','import-private-dependencies')) {
        $workerAction = if ($Action -eq 'export-private-dependencies') { 'extract' } else { 'import-dependencies' }
        $worker = Import-Module (Join-Path $PSScriptRoot ('Actions/' + $workerAction + '/Scripts/Action.psm1')) -PassThru -DisableNameChecking
        & $worker { param($Path) Invoke-JobsFeature -Target $Path -PrivateOnly } $project
        return
    }
    if ($Action -cmatch '^(export|import)-(gradle|ohos|native|precache|web)-dependencies$') {
        $setup = Import-Module (Join-Path $PSScriptRoot 'ProjectSetup.psm1') -PassThru -DisableNameChecking
        & $setup { param($p,$a) Invoke-JobsProjectDependencyArchiveAction -Target $p -Action $a } $project $Action
        return
    }
    if ($Action -in @('pub-get','android-dependencies','ohos-dependencies','native-dependencies','flutter-precache','web-dependencies')) {
        $setup = Import-Module (Join-Path $PSScriptRoot 'ProjectSetup.psm1') -PassThru -DisableNameChecking
        & $setup { param($p,$a) Invoke-JobsProjectDependencyAction -Target $p -Action $a } $project $Action
        return
    }
    if ($Action -in @('project-setup','gradle-download','java-manage')) {
        $setup = Import-Module (Join-Path $PSScriptRoot 'ProjectSetup.psm1') -PassThru -DisableNameChecking
        & $setup { param($p,$a) Invoke-JobsProjectSetupAction -Target $p -Action $a } $project $Action
        return
    }
    if ($Action -eq 'build-harmony') {
        $packager = Import-Module (Join-Path $PSScriptRoot 'Actions/package/Scripts/Action.psm1') -PassThru -DisableNameChecking
        & $packager { param($Path) Invoke-JobsFlutterHarmonyAction -Target $Path } $project
        return
    }
    if ($Action -eq 'ohos-sdk-manage') {
        $harmony = Import-Module (Join-Path $PSScriptRoot 'HarmonySdk.psm1') -PassThru -DisableNameChecking
        & $harmony { param($Path) Invoke-JobsHarmonySdkAction -Target $Path } $project
        return
    }
    if ($Action -eq 'sdk-manage') {
        $harmony = Import-Module (Join-Path $PSScriptRoot 'HarmonySdk.psm1') -PassThru -DisableNameChecking
        if (& $harmony { param($Path) Test-JobsManagedHarmonyBinding $Path } $project) {
            & $harmony { param($Path) Invoke-JobsNativeSdkFromHarmony -Target $Path } $project
            return
        }
    }
    if ($Action -ne 'sdk-manage') { $sdk = Get-JobsToolsFvm $project }
    if ($Action -in @('native-doctor','harmony-doctor','repair-imports','repair-namespace','maintenance')) {
        & $sdk.Dart (Join-Path $PSScriptRoot 'FlutterProjectTools.dart') $Action $project
        if ($LASTEXITCODE -ne 0) { throw ('Flutter 工具返回失败：' + $LASTEXITCODE) }
        return
    }
    if ($Action -eq 'repair-android') { Repair-JobsToolsAndroidSdk $project; return }
    $modulePath = Join-Path $PSScriptRoot ('Actions/' + $Action + '/Scripts/Action.psm1')
    $worker = Import-Module $modulePath -PassThru -DisableNameChecking
    & $worker { param($Path) Invoke-JobsFeature -Target $Path } $project
}
Export-ModuleMember -Function Invoke-JobsFeature

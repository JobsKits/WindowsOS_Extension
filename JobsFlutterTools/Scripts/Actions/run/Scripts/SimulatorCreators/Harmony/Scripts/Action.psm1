# Action.psm1 | JobsHarmonySimulatorCreator
# Created by Jobs on 2026年10月23日，星期五.
# 通过 SDL 补齐工具，再由官方 Emulator 下载镜像；展示许可原文后由用户回车同意。

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
. (Join-Path $PSScriptRoot 'HarmonyTools.ps1')

function ConvertTo-JobsHarmonyPlainText {
    param([string]$Text)
    $escape = [regex]::Escape([string][char]27)
    $plain = $Text -replace ($escape + '\][^\x07]*(?:\x07|' + $escape + '\\)'), ''
    return $plain -replace ($escape + '\[[0-?]*[ -/]*[@-~]'), ''
}
function Write-JobsHarmonyMessage {
    param([string]$Text)
    $plain = ConvertTo-JobsHarmonyPlainText $Text
    Write-Host $plain
    if (Get-Variable -Name HarmonyLog -Scope Script -ErrorAction SilentlyContinue) {
        [IO.File]::AppendAllText($script:HarmonyLog, $plain + [Environment]::NewLine, (New-Object Text.UTF8Encoding($true)))
    }
}
function Read-JobsHarmonyInput {
    param([string]$Prompt)
    Write-JobsEnterChoiceText ($Prompt + '：') -NoNewline
    $answer = [Console]::ReadLine()
    if ($null -eq $answer) { throw '输入已结束，停止操作。' }
    return $answer
}
function Get-JobsHarmonyArchitecture {
    $architecture = $env:PROCESSOR_ARCHITEW6432
    if ([string]::IsNullOrWhiteSpace($architecture)) { $architecture = $env:PROCESSOR_ARCHITECTURE }
    if ($architecture -ine 'AMD64') { throw 'Harmony 本地模拟器只支持 x64 Windows 10 / 11；Windows ARM、32 位系统和虚拟机不在官方支持范围：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-requirements' }
    return 'x86_64'
}
function Test-JobsHarmonyDesktop {
    param([string]$Target)
    $desktop = [Environment]::GetFolderPath('DesktopDirectory')
    if (-not $Target -or -not $desktop -or -not [IO.Directory]::Exists($Target)) { return $false }
    return [string]::Equals([IO.Path]::GetFullPath($Target).TrimEnd('\', '/'), [IO.Path]::GetFullPath($desktop).TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)
}
function Get-JobsHarmonyEmulator {
    param([string]$EmulatorBin = $env:HARMONY_EMULATOR_BIN, [switch]$InstallMissing)
    if ($EmulatorBin) {
        if (-not [IO.Path]::IsPathRooted($EmulatorBin) -or $EmulatorBin -match '[\x00-\x1f]' -or [IO.Path]::GetExtension($EmulatorBin) -ine '.exe') { throw 'HARMONY_EMULATOR_BIN 必须是无控制字符的 Emulator.exe 绝对路径。' }
        if (-not [IO.File]::Exists($EmulatorBin)) { throw ('指定 Emulator 不存在，不会改用其它工具：' + $EmulatorBin) }
        return [IO.Path]::GetFullPath($EmulatorBin)
    }
    $toolHome = $env:DEVECO_STUDIO_HOME
    if (-not $toolHome) { $toolHome = $env:TOOL_HOME }
    if ($toolHome) {
        if (-not [IO.Path]::IsPathRooted($toolHome) -or $toolHome -match '[\x00-\x1f]') { throw 'DEVECO_STUDIO_HOME / TOOL_HOME 必须是无控制字符的绝对路径。' }
        foreach ($relative in @('tools/emulator/Emulator.exe', 'emulator/Emulator.exe')) {
            $file = Join-Path $toolHome $relative
            if ([IO.File]::Exists($file)) { return [IO.Path]::GetFullPath($file) }
        }
        throw ('指定 DevEco / Command Line Tools 中没有 Emulator.exe，不会静默切换：' + $toolHome)
    }
    $candidates = @()
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $base) { continue }
        foreach ($relative in @('Huawei/DevEco Studio/tools/emulator/Emulator.exe', 'Huawei/DevEcoStudio/tools/emulator/Emulator.exe')) {
            $file = Join-Path $base $relative
            if ([IO.File]::Exists($file)) { $candidates += [IO.Path]::GetFullPath($file) }
        }
    }
    $toolsHome = Get-JobsHarmonyToolsHome
    if ([IO.Directory]::Exists($toolsHome)) {
        foreach ($directory in @(Get-ChildItem -LiteralPath $toolsHome -Directory -Filter 'clt-*')) {
            $file = Join-Path $directory.FullName 'emulator/Emulator.exe'
            if ([IO.File]::Exists($file)) { $candidates += $file }
        }
    }
    foreach ($command in @(Get-Command -Name 'Emulator.exe', 'Emulator' -CommandType Application -All -ErrorAction SilentlyContinue)) {
        if ([IO.File]::Exists($command.Source)) { $candidates += $command.Source }
    }
    $compatible = @()
    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        try { Assert-JobsHarmonyCapabilities $candidate; $compatible += $candidate }
        catch { Write-JobsHarmonyMessage ('已排除不兼容工具：' + $candidate) }
    }
    if ($compatible.Count -gt 1) { throw '发现多份兼容 DevEco Emulator，请用 HARMONY_EMULATOR_BIN 明确选择。' }
    if ($compatible.Count -eq 1) { return $compatible[0] }
    if ($InstallMissing) { return Install-JobsHarmonyTools }
    throw '未找到兼容 DevEco Emulator；正常桌面菜单入口确认后会从 SDL 免登录镜像安装工具。只读 Check 不安装。'

}
function Invoke-JobsHarmonyQuery {
    param([string]$Emulator, [string[]]$Arguments)
    $result = if (($Arguments -join ' ') -ceq '-imageList -downloaded false') {
        Invoke-JobsSdkAcquire -Label 'Harmony 可下载系统镜像清单' -Operation { Invoke-JobsProcess -FilePath $Emulator -Arguments $Arguments -TimeoutSeconds 60 }
    } else { Invoke-JobsProcess -FilePath $Emulator -Arguments $Arguments -TimeoutSeconds 60 }
    $output = ConvertTo-JobsHarmonyPlainText $result.StdOut
    if ($result.ExitCode -ne 0) { throw ('Emulator ' + ($Arguments -join ' ') + ' 失败，退出码 ' + $result.ExitCode + [Environment]::NewLine + $output + (ConvertTo-JobsHarmonyPlainText $result.StdErr)) }
    $output = $output.TrimStart([char]0xfeff).Trim()
    $errorText = (ConvertTo-JobsHarmonyPlainText $result.StdErr).Trim()
    # 6.1.1.200 实测空结果不是 JSON；仅精确匹配成功响应，不吞掉未知错误。
    if (($Arguments -join ' ') -match '^-imageList -downloaded (true|false)$' -and [string]::IsNullOrEmpty($output) -and $errorText -ceq 'No images matching the criteria were found.') { return '[]' }
    if (($Arguments -join ' ') -ceq '-list -details' -and $output -ceq '[Empty]' -and [string]::IsNullOrEmpty($errorText)) { return '[]' }
    return $output
}
function Assert-JobsHarmonyCapabilities {
    param([string]$Emulator)
    $help = Invoke-JobsHarmonyQuery $Emulator @('-help')
    foreach ($flag in @('-create', '-imageList', '-list', '-start')) {
        if ($help -notmatch ('(?<![A-Za-z0-9_-])' + [regex]::Escape($flag) + '(?![A-Za-z0-9_-])')) { throw ('当前工具未确认支持 ' + $flag + '；需要具备创建功能的 DevEco Emulator 6.1+，不会使用 Android Emulator 或只启动旧实例。') }
    }
}
function ConvertFrom-JobsHarmonyJson {
    param([string]$Text, [string]$Label)
    if ([string]::IsNullOrWhiteSpace($Text) -or $Text[0] -notin @('[', '{')) { throw ($Label + ' 未返回可识别的 JSON，停止；请核对当前官方 Emulator 输出。') }
    try { $result = $Text | ConvertFrom-Json -ErrorAction Stop }
    catch { throw ($Label + ' JSON 无法解析，停止；不会按日志文字判断成功。') }
    return $result
}
function Get-JobsHarmonyImages {
    param([string]$Emulator, [switch]$Available)
    $downloadedFilter = 'true'
    if ($Available) { $downloadedFilter = 'false' }
    $text = Invoke-JobsHarmonyQuery $Emulator @('-imageList', '-downloaded', $downloadedFilter)
    if (-not $text.StartsWith('[')) { throw '镜像清单必须为官方 JSON 数组；没有开始创建。' }
    $records = @(ConvertFrom-JobsHarmonyJson $text '镜像清单')
    $images = @()
    $seen = @{}
    foreach ($record in $records) {
        if ($null -eq $record) { continue }
        foreach ($field in @('SoftWareVersion', 'deviceType', 'osVersion', 'downloaded', 'releaseType', 'upgradable')) {
            if ($null -eq $record.PSObject.Properties[$field]) { throw ('镜像清单缺少字段：' + $field) }
        }
        foreach ($field in @('SoftWareVersion', 'deviceType', 'osVersion', 'releaseType')) {
            if ($record.$field -isnot [string] -or [string]::IsNullOrWhiteSpace($record.$field) -or $record.$field -match '[\x00-\x1f]') { throw ('镜像字段类型或内容不合法：' + $field) }
        }
        foreach ($field in @('downloaded', 'upgradable')) {
            if ($record.$field -isnot [bool] -and ($record.$field -isnot [string] -or $record.$field -cnotin @('true', 'false'))) { throw ('镜像布尔字段不合法：' + $field) }
        }
        if ($record.releaseType -ine 'Release') { continue }
        $downloaded = $record.downloaded -is [bool] -and $record.downloaded
        if ($record.downloaded -is [string]) { $downloaded = $record.downloaded -ceq 'true' }
        if ($downloaded -eq [bool]$Available) { continue }
        $type = [string]$record.deviceType
        $version = [string]$record.osVersion
        if ($type -cnotmatch '^(?:[A-Za-z][A-Za-z0-9_-]*|2in1(?: Foldable)?)$' -or [string]::IsNullOrWhiteSpace($version) -or $version.StartsWith('-') -or $version -match '[\x00-\x1f]') { throw '镜像元数据不合法，停止。' }
        $key = $type.ToLowerInvariant() + '|' + $version
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $images += [pscustomobject]@{ DeviceType = $type; OsVersion = $version; Label = $type + ' | ' + $version }
    }
    return @($images | Sort-Object @{ Expression = { if ($_.DeviceType -ieq 'phone') { 0 } else { 1 } } }, DeviceType,
        @{ Expression = { if ($_.OsVersion -match 'HarmonyOS ([0-9]+\.[0-9]+\.[0-9]+)') { [version]$Matches[1] } else { [version]'0.0.0' } }; Descending = $true },
        @{ Expression = { if ($_.OsVersion -match '\(([0-9]+)') { [int]$Matches[1] } else { 0 } }; Descending = $true })
}
function Get-JobsHarmonyInstances {
    param([string]$Emulator)
    $text = Invoke-JobsHarmonyQuery $Emulator @('-list', '-details')
    $records = @(ConvertFrom-JobsHarmonyJson $text '实例清单')
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($record in $records) {
        if ($null -eq $record -or $null -eq $record.PSObject.Properties['name'] -or $record.name -isnot [string] -or [string]::IsNullOrWhiteSpace($record.name) -or $record.name -match '[\x00-\x1f]') { throw '实例清单必须包含无控制字符的真实字符串 name；没有按文本猜测结果。' }
        if (-not $names.Add($record.name)) { throw ('实例清单存在重复或大小写冲突名称，停止：' + $record.name) }
    }
    return $records
}
function Select-JobsHarmonyChoice {
    param([string]$Title, [string[]]$Choices)
    if ($Choices.Count -eq 0) { throw '没有可供选择的项目。' }
    $fzf = Find-JobsExecutable -Name 'fzf.exe' -Candidates @('fzf')
    if ($fzf) {
        $health = Invoke-JobsProcess -FilePath $fzf -Arguments @('--version') -TimeoutSeconds 10
        if ($health.ExitCode -eq 0) {
            $savedOptions = $env:FZF_DEFAULT_OPTS
            $savedOptionsFile = $env:FZF_DEFAULT_OPTS_FILE
            $savedEncoding = $OutputEncoding
            $savedConsole = [Console]::OutputEncoding
            try {
                $env:FZF_DEFAULT_OPTS = ''
                $env:FZF_DEFAULT_OPTS_FILE = ''
                $OutputEncoding = New-Object Text.UTF8Encoding($false)
                [Console]::OutputEncoding = $OutputEncoding
                $selected = @($Choices | & $fzf --height=40% --reverse --no-multi --prompt ($Title + ' > ') --header '回车确认；Esc / Ctrl+C 取消')
                $code = $LASTEXITCODE
            } finally {
                $env:FZF_DEFAULT_OPTS = $savedOptions
                $env:FZF_DEFAULT_OPTS_FILE = $savedOptionsFile
                $OutputEncoding = $savedEncoding
                [Console]::OutputEncoding = $savedConsole
            }
            if ($code -in @(1, 130)) { throw '已取消。' }
            if ($code -ne 0 -or $selected.Count -ne 1 -or $selected[0] -cnotin $Choices) { throw 'fzf 返回无效选择，停止。' }
            return $selected[0]
        }
        Write-JobsHarmonyMessage 'fzf 健康检查失败，使用编号选择。'
    }
    for ($index = 0; $index -lt $Choices.Count; $index++) { Write-Host ('  {0}、{1}' -f ($index + 1), $Choices[$index]) }
    while ($true) {
        $answer = Read-JobsHarmonyInput ($Title + '（回车第 1 项，q 取消）')
        if ($answer -ieq 'q') { throw '已取消。' }
        if ($answer.Length -eq 0) { return $Choices[0] }
        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $Choices.Count) { return $Choices[$number - 1] }
        Write-JobsHarmonyMessage '请输入列表编号。'
    }
}
function New-JobsHarmonyName {
    param([object[]]$Existing = @(), [string]$Name)
    if ($Name -and ($Name -cnotmatch '\A[A-Za-z][A-Za-z0-9_+ ]{0,63}\z' -or $Name.EndsWith(' '))) { throw '实例名须以英文字母开头，仅含英文字母、数字、空格、下划线或加号，不能以空格结尾，最多 64 字符，不支持连字符 -。' }
    $requested = -not [string]::IsNullOrEmpty($Name)
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        if (-not $requested) { $Name = 'JobsHarmony_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + [guid]::NewGuid().ToString('N').Substring(0, 6) }
        $collision = @($Existing | Where-Object { $null -ne $_ -and $_.name -ieq $Name }).Count -gt 0
        if (-not $collision) { return $Name }
        if ($requested) { throw ('已存在同名实例，拒绝覆盖：' + $Name) }
    }
    throw '无法生成唯一实例名，没有开始创建。'
}
function Invoke-JobsHarmonyInteractive {
    param([string]$Emulator, [string[]]$Arguments)
    Write-JobsHarmonyMessage ('执行官方工具：' + $Emulator + ' ' + ($Arguments -join ' '))
    # 保留 stdin 与官方退出码；许可仅在本人明确同意后接受，-force 仅用于确认后的镜像安装。
    $global:LASTEXITCODE = -1
    & $Emulator @Arguments | Out-Host
    $code = $LASTEXITCODE
    if ($code -in @(130,143,-1073741510)) { throw (New-Object Management.Automation.PipelineStoppedException) }
    if ($code -ne 0) { throw ('Emulator 操作失败，退出码 ' + $code + '；保留官方输出和已生成的现场。') }
}
# 展示随工具分发的许可原文；只有用户明确回车同意后才执行官方接受命令。
function Confirm-JobsHarmonyLicenses {
    param([string]$Emulator)
    if ($script:HarmonyLicensesConfirmed) { return }
    $directory = Join-Path (Split-Path -Parent $Emulator) 'agreement'
    $files = @('HarmonyOS_SDK_Agreement.txt', 'HarmonyOS_Software_Service_Agreement.txt') | ForEach-Object { Join-Path $directory $_ }
    foreach ($file in $files) {
        if (-not [IO.File]::Exists($file) -or (Get-Item -LiteralPath $file).Length -eq 0) { throw ('找不到可供阅读的官方许可，未接受：' + $file) }
    }
    foreach ($file in $files) {
        Write-JobsHarmonyMessage ('官方许可原文：' + $file)
        Write-Host ([IO.File]::ReadAllText($file, [Text.Encoding]::UTF8))
    }
    if ((Read-JobsHarmonyInput '阅读以上全部协议后，回车表示本人同意并继续；任意非空输入取消').Length -ne 0) { throw '已取消许可确认，未下载或启动。' }
    Invoke-JobsHarmonyInteractive $Emulator @('-license', 'accept')
    $script:HarmonyLicensesConfirmed = $true
}
function Install-JobsHarmonyImage {
    param([string]$Emulator)
    Write-JobsHarmonyMessage '没有本地 Release 镜像，正在读取官方可下载清单（最长 60 秒）…'
    $available = @(Get-JobsHarmonyImages $Emulator -Available)
    if ($available.Count -eq 0) { throw '官方没有返回可下载的 Release 镜像，请在 DevEco Device Manager 核对网络或账号要求。' }
    $selected = Select-JobsHarmonyChoice '下载系统镜像（默认最新稳定版手机；可能数 GB）' @($available | ForEach-Object { $_.Label })
    $image = @($available | Where-Object { $_.Label -ceq $selected })
    if ($image.Count -ne 1) { throw '选择器返回了无效下载镜像。' }
    Write-JobsHarmonyMessage ('官方 Emulator 下载：' + $selected + '；目录沿用 DevEco 既有配置。')
    Write-JobsHarmonyMessage '已选择镜像，自动补齐；失败持续重试，Ctrl+C 可停止。'
    Confirm-JobsHarmonyLicenses $Emulator
    # 仅对已明确确认的新镜像安装跳过重复提示；创建与启动不用 -force。
    [void](Invoke-JobsSdkAcquire -Label ('Harmony 系统镜像：' + $image[0].Label) -Operation {
    Invoke-JobsHarmonyInteractive $Emulator @('-install', '-deviceType', $image[0].DeviceType, '-osVersion', $image[0].OsVersion, '-force')
    $installed = @(Get-JobsHarmonyImages $Emulator | Where-Object { $_.DeviceType -ieq $image[0].DeviceType -and $_.OsVersion -ceq $image[0].OsVersion })
    if ($installed.Count -ne 1) { throw '所选镜像下载未完成，保留现场自动重试。' }
    })
    $installed = @(Get-JobsHarmonyImages $Emulator | Where-Object { $_.DeviceType -ieq $image[0].DeviceType -and $_.OsVersion -ceq $image[0].OsVersion })
    Write-JobsHarmonyMessage ('已验证下载镜像：' + $installed[0].Label)
    return $installed[0]
}
function Get-JobsHarmonyInstanceVersion {
    param($Instance)
    $flat = $null
    $nested = $null
    if ($null -ne $Instance.PSObject.Properties['os.osVersion']) { $flat = $Instance.'os.osVersion' }
    if ($null -ne $Instance.PSObject.Properties['os'] -and $null -ne $Instance.os -and $null -ne $Instance.os.PSObject.Properties['osVersion']) { $nested = $Instance.os.osVersion }
    foreach ($value in @($flat, $nested)) {
        if ($null -ne $value -and ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value) -or $value -match '[\x00-\x1f]')) { throw '实例系统版本字段类型或内容不合法。' }
    }
    if ($null -ne $flat -and $null -ne $nested -and $flat -cne $nested) { throw '实例详情的平铺 / 嵌套系统版本冲突，停止验证。' }
    if ($null -ne $flat) { return $flat }
    if ($null -ne $nested) { return $nested }
    return ''
}
function Get-JobsHarmonyCheck {
    param([string]$EmulatorBin = $env:HARMONY_EMULATOR_BIN, [switch]$InstallMissing)
    [void](Get-JobsHarmonyArchitecture)
    $emulator = Get-JobsHarmonyEmulator $EmulatorBin -InstallMissing:$InstallMissing
    Assert-JobsHarmonyCapabilities $emulator
    $images = @(Get-JobsHarmonyImages $emulator)
    $instances = @(Get-JobsHarmonyInstances $emulator)
    return [pscustomobject]@{ Emulator = $emulator; Images = $images; Instances = $instances }
}
# 独立 CLT 的 sdk 与 emulator 同级；只补本次已核验的新实例，保留官方已有路径。
function Set-JobsHarmonyCreatedSdk {
    param([string]$Emulator, $Instance)
    $sdk = Join-Path (Split-Path -Parent (Split-Path -Parent $Emulator)) 'sdk'
    if (-not [IO.File]::Exists((Join-Path $sdk 'default/openharmony/toolchains/hdc.exe'))) { return }
    if ($null -eq $Instance.PSObject.Properties['instancePath'] -or $Instance.instancePath -isnot [string] -or $Instance.instancePath -match '[\x00-\x1f]' -or -not [IO.Path]::IsPathRooted($Instance.instancePath)) { throw '新实例路径无效，未写入 SDK 配置。' }
    $directory = $Instance.instancePath
    $config = Join-Path $directory 'config.ini'
    if ((Split-Path -Leaf $directory) -cne $Instance.name -or -not [IO.Directory]::Exists($directory) -or -not [IO.File]::Exists($config) -or ((Get-Item -LiteralPath $directory).Attributes -band [IO.FileAttributes]::ReparsePoint) -or ((Get-Item -LiteralPath $config).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw '新实例配置不存在、名称不一致或是链接，未写入 SDK 配置。' }
    $text = [IO.File]::ReadAllText($config)
    $names = @([regex]::Matches($text, '(?m)^name=([^\r\n]*)\r?$'))
    if ($names.Count -ne 1 -or $names[0].Groups[1].Value -cne $Instance.name) { throw '新实例配置中的名称不一致，未写入 SDK 配置。' }
    if ($text -match '(?m)^(?:sdkPath|harmonyos\.sdk\.path)=[^\r\n]+') { return }
    $text = [regex]::Replace($text, '(?m)^(?:sdkPath|harmonyos\.sdk\.path)=\r?\n?', '')
    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    if (-not $text.EndsWith("`n")) { $text += $newline }
    $text += 'sdkPath=' + [IO.Path]::GetFullPath($sdk) + $newline
    $temporary = Join-Path $directory ('.jobs-sdk-' + [guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText($temporary, $text, (New-Object Text.UTF8Encoding($false)))
        [IO.File]::Replace($temporary, $config, [NullString]::Value)
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
    Write-JobsHarmonyMessage ('已为新实例配置 CLT SDK：' + $sdk)
}
# 兼容官方平铺或嵌套端口；冲突字段不能用于自动运行。
function Get-JobsHarmonyFlutterPort {
    param($Record)
    $port = ''
    if ($null -ne $Record.PSObject.Properties['hw.hdc.port']) { $port = [string]$Record.'hw.hdc.port' }
    if ($null -ne $Record.PSObject.Properties['hw'] -and $null -ne $Record.hw -and $null -ne $Record.hw.PSObject.Properties['hdc'] -and $null -ne $Record.hw.hdc -and $null -ne $Record.hw.hdc.PSObject.Properties['port']) {
        $nested = [string]$Record.hw.hdc.port
        if ($port -and $port -cne $nested) { throw '新实例 HDC 端口字段冲突；未返回 Flutter 目标。' }
        $port = $nested
    }
    if ($port -and ($port -cnotmatch '^[0-9]{1,5}$' -or [int]$port -lt 1 -or [int]$port -gt 65535)) { throw '新实例 HDC 端口无效；未返回 Flutter 目标。' }
    return $port
}
# SDK 身份只取实例详情或其自身配置，不能用其它安装的 HDC 猜测目标。
function Get-JobsHarmonyFlutterSdk {
    param($Record)
    $paths = @()
    if ($null -ne $Record.PSObject.Properties['sdkPath'] -and -not [string]::IsNullOrWhiteSpace([string]$Record.sdkPath)) { $paths += [string]$Record.sdkPath }
    if ($null -ne $Record.PSObject.Properties['instancePath'] -and [IO.Path]::IsPathRooted([string]$Record.instancePath)) {
        $config = Join-Path $Record.instancePath 'config.ini'
        if ([IO.File]::Exists($config)) {
            if (((Get-Item -LiteralPath $Record.instancePath).Attributes -band [IO.FileAttributes]::ReparsePoint) -or ((Get-Item -LiteralPath $config).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw '新实例 SDK 配置是链接；未返回 Flutter 目标。' }
            $text = [IO.File]::ReadAllText($config)
            $names = @([regex]::Matches($text, '(?m)^name=([^\r\n]*)\r?$'))
            if ($names.Count -ne 1 -or $names[0].Groups[1].Value -cne $Record.name) { throw '新实例 SDK 配置名称不一致；未返回 Flutter 目标。' }
            foreach ($match in [regex]::Matches($text, '(?m)^(?:sdkPath|harmonyos\.sdk\.path)=([^\r\n]+)\r?$')) { $paths += $match.Groups[1].Value }
        }
    }
    $normalized = @()
    foreach ($path in $paths) {
        if (-not [IO.Path]::IsPathRooted($path) -or $path -match '[\x00-\x1f]') { throw '新实例 SDK 路径无效；未返回 Flutter 目标。' }
        $normalized += [IO.Path]::GetFullPath($path).TrimEnd('\', '/')
    }
    $unique = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $normalized) { [void]$unique.Add($path) }
    if ($unique.Count -ne 1) { throw '新实例 SDK 路径缺失或冲突；未返回 Flutter 目标。' }
    return $normalized[0]
}
# 只向 Flutter 调用方返回本次实例经 HDC 实际发现的精确目标。
function Write-JobsHarmonyFlutterTarget {
    param([string]$Emulator, $Instance, [int]$TimeoutSeconds = 180)
    if (-not $env:JOBS_FLUTTER_CREATED_DEVICE_FILE) { return }
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $instances = @(Get-JobsHarmonyInstances $Emulator)
        $current = @($instances | Where-Object { $_.name -ceq $Instance.name })
        if ($current.Count -ne 1) { throw '新实例身份不唯一；保留模拟器，未返回 Flutter 目标。' }
        $record = $current[0]
        foreach ($field in @('instancePath', 'uuid')) {
            if ($null -ne $Instance.PSObject.Properties[$field] -and ($null -eq $record.PSObject.Properties[$field] -or $record.$field -cne $Instance.$field)) { throw '新实例身份已变化；未返回 Flutter 目标。' }
        }
        $port = Get-JobsHarmonyFlutterPort $record
        if ($port -and $null -ne $record.PSObject.Properties['isRunning'] -and ($record.isRunning -ceq $true -or $record.isRunning -ceq 'true')) {
            foreach ($peer in $instances) {
                if ($peer.name -cne $record.name -and $null -ne $peer.PSObject.Properties['isRunning'] -and ($peer.isRunning -ceq $true -or $peer.isRunning -ceq 'true') -and (Get-JobsHarmonyFlutterPort $peer) -ceq $port) { throw '多个运行实例使用同一 HDC 端口；未返回 Flutter 目标。' }
            }
            $sdk = Get-JobsHarmonyFlutterSdk $record
            foreach ($relative in @('default/openharmony/toolchains/hdc.exe', 'openharmony/toolchains/hdc.exe', 'toolchains/hdc.exe')) {
                $hdc = Join-Path $sdk $relative
                if (-not [IO.File]::Exists($hdc)) { continue }
                $result = Invoke-JobsProcess -FilePath $hdc -Arguments @('list', 'targets') -TimeoutSeconds 10
                $id = '127.0.0.1:' + $port
                if ($result.ExitCode -eq 0 -and $id -cin @($result.StdOut -split '\r?\n' | ForEach-Object { $_.Trim() })) {
                    [IO.File]::WriteAllText($env:JOBS_FLUTTER_CREATED_DEVICE_FILE, "Harmony`t$id`n", (New-Object Text.UTF8Encoding($false)))
                    Write-JobsHarmonyMessage ('已确认本次实例 HDC 目标：' + $id + '；继续等待 Flutter 识别。')
                    return
                }
            }
        }
        if ([DateTime]::UtcNow -ge $deadline) { break }
        Write-JobsHarmonyMessage ('等待新实例 HDC 就绪：' + $Instance.name + '；Ctrl+C 取消。')
        Start-Sleep -Seconds 2
    } while ([DateTime]::UtcNow -lt $deadline)
    throw '新实例已保留，但未确认唯一 HDC 目标；未自动运行 Flutter，请在 DevEco Device Manager 检查。'
}
function Invoke-JobsHarmonySimulatorAction {
    param([string]$Target, [string]$EmulatorBin = $env:HARMONY_EMULATOR_BIN, [string]$Name, [switch]$NoStart)
    if (-not (Test-JobsHarmonyDesktop $Target)) { throw '此入口仅适用于系统桌面空白。' }
    Remove-Variable -Name HarmonyLog -Scope Script -ErrorAction SilentlyContinue
    $script:HarmonyLicensesConfirmed = $false
    Write-Host ('Jobs 新建 Harmony 模拟器 · 来源：' + $PSScriptRoot) -ForegroundColor Cyan
    Write-Host '仅支持 x64 Windows 10 / 11 物理机；缺少兼容工具时从 SDL 镜像免登录下载 CLT 6.1.1.280（约 2.60 GB）。'
    Write-JobsEnterChoiceText '回车授权校验并安装缺失工具依赖到独立目录；健康工具不升级。缺镜像时读取官方清单，回车下载最新稳定版手机镜像，再创建唯一实例并启动。'
    Write-JobsEnterChoiceText '华为官网下载工具需登录；SDL 是工具包的替代下载源，不含系统镜像。下载或启动前展示随附许可原文，回车表示本人同意；非空输入取消。不覆盖旧实例、不改代理或 PATH。'
    Write-Host '手机等模拟器受官方中国大陆使用区域限制；需要账号授权的镜像请在 DevEco Studio 操作，不绕过限制。'
    if ((Read-JobsHarmonyInput '直接回车检查并选择，任意非空输入取消').Length -gt 0) { throw '已取消。' }
    $logDirectory = Join-Path (Get-JobsInstallRoot) 'logs'
    [void][IO.Directory]::CreateDirectory($logDirectory)
    $script:HarmonyLog = Join-Path $logDirectory ('create-' + (Get-Date -Format 'yyyy-MM-dd-HH-mm-ss') + '-' + [guid]::NewGuid().ToString('N') + '.log')
    Write-JobsHarmonyMessage ('日志：' + $script:HarmonyLog)
    $check = Get-JobsHarmonyCheck $EmulatorBin -InstallMissing
    if ($check.Images.Count -eq 0) {
        $check.Images = @(Install-JobsHarmonyImage $check.Emulator)
        $selected = $check.Images[0].Label
    } else {
        $selected = Select-JobsHarmonyChoice '选择已下载的 Harmony 镜像' @($check.Images | ForEach-Object { $_.Label })
    }
    $image = @($check.Images | Where-Object { $_.Label -ceq $selected })
    if ($image.Count -ne 1) { throw '镜像选择不唯一，停止。' }
    $nameValue = New-JobsHarmonyName -Existing $check.Instances -Name $Name
    $arguments = @('-create', $nameValue, '-deviceType', $image[0].DeviceType, '-osVersion', $image[0].OsVersion)
    Write-JobsHarmonyMessage ('即将创建：' + $nameValue + '；镜像：' + $selected)
    Write-JobsHarmonyMessage '实例与镜像路径沿用 DevEco 既有配置；机型使用官方最新默认模板。'
    if ((Read-JobsHarmonyInput '直接回车创建，任意非空输入取消').Length -gt 0) { throw '已取消。' }
    $latest = @(Get-JobsHarmonyInstances $check.Emulator)
    [void](New-JobsHarmonyName -Existing $latest -Name $nameValue)
    Invoke-JobsHarmonyInteractive $check.Emulator $arguments
    try { $created = @((Get-JobsHarmonyInstances $check.Emulator) | Where-Object { $_.name -ceq $nameValue }) }
    catch { throw ('创建命令已返回，但详情回读失败；请保留现场去 Device Manager 核对，不自动重试。' + [Environment]::NewLine + $_.Exception.Message) }
    if ($created.Count -ne 1 -or $null -eq $created[0].PSObject.Properties['deviceType'] -or $created[0].deviceType -ine $image[0].DeviceType -or (Get-JobsHarmonyInstanceVersion $created[0]) -cne $image[0].OsVersion) { throw '创建命令已返回，但回读没有验证唯一且匹配的实例；请保留现场在 DevEco Device Manager 核对，不要当作创建成功或自动重试。' }
    Set-JobsHarmonyCreatedSdk -Emulator $check.Emulator -Instance $created[0]
    Write-JobsHarmonyMessage ('已验证新实例：' + $nameValue)
    if (-not $NoStart -and (Read-JobsHarmonyInput '直接回车启动，任意非空输入保留实例并跳过启动').Length -eq 0) {
        Confirm-JobsHarmonyLicenses $check.Emulator
        $startArguments = @('-start', $nameValue)
        Invoke-JobsHarmonyInteractive $check.Emulator $startArguments
        Write-JobsHarmonyMessage '启动命令已成功执行；设备启动就绪情况请查看模拟器窗口。'
        Write-JobsHarmonyFlutterTarget $check.Emulator $created[0]
    }
}
function Invoke-JobsFeature {
    param([Parameter(Mandatory = $true)][string]$Target)
    Invoke-JobsHarmonySimulatorAction -Target (Resolve-JobsTarget $Target)
}
Export-ModuleMember -Function Invoke-JobsFeature

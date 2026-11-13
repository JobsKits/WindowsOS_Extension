# HarmonyToolsCore.psm1 | Jobs Flutter Harmony run preparation
# Created by Jobs on 2026年11月10日，星期二.
# Jobs 自有工具获取/许可函数快照；不含模拟器创建、镜像安装或启动入口。
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking
. (Join-Path $PSScriptRoot 'SdkDownloadOutput.ps1')
. (Join-Path $PSScriptRoot 'HarmonyTools.ps1')
$script:HarmonyLicensesConfirmed=$false
function Test-JobsEnterChoiceColor {
    if ((Test-Path Env:NO_COLOR) -or $env:TERM -ieq 'dumb' -or $env:PLAIN_OUTPUT -eq '1') { return $false }
    $consoleType = [Console]
    if ($null -eq $consoleType.GetProperty('IsInputRedirected') -or $null -eq $consoleType.GetProperty('IsOutputRedirected')) { return $false }
    return ($Host.Name -ceq 'ConsoleHost' -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected)
}

function Test-JobsEnterChoiceBold {
    $property = $Host.UI.PSObject.Properties['SupportsVirtualTerminal']
    return ($null -ne $property -and [bool]$property.Value)
}

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

function Read-JobsEnterChoiceHost {
    [CmdletBinding()]
    param([Parameter(Position=0)][string]$Prompt, [switch]$AsSecureString, [switch]$MaskInput)
    if ($AsSecureString -or $MaskInput -or -not (Test-JobsEnterChoiceColor) -or @((Get-JobsEnterChoiceParts $Prompt) | Where-Object { $_.Color }).Count -eq 0) {
        return (Read-Host @PSBoundParameters)
    }
    Write-JobsEnterChoiceText ($Prompt + ': ') -NoNewline
    return (Read-Host)
}

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

function New-JobsSetupBatchStart {
    param([string]$Cmd, [string]$File, [string[]]$Arguments, [string]$Directory)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Cmd
    $placeholders = @()
    for ($index=0; $index -lt $Arguments.Count; $index++) {
        $name = 'JOBS_SETUP_ARGUMENT_' + $index
        $start.EnvironmentVariables[$name] = $Arguments[$index]
        $placeholders += ('"%' + $name + '%"')
    }
    $start.Arguments = '/d /v:off /s /c ""%JOBS_SETUP_TOOL%" ' + ($placeholders -join ' ') + '"'
    $start.EnvironmentVariables['JOBS_SETUP_TOOL'] = $File
    $start.WorkingDirectory = $Directory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $start.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    return $start
}

function Assert-JobsSetupDirectory {
    param([string]$Path)
    if (-not [IO.Path]::IsPathRooted($Path)) { throw '必须提供绝对目录。' }
    $current = New-Object IO.DirectoryInfo ([IO.Path]::GetFullPath($Path))
    while ($null -ne $current) {
        if ($current.Exists -and ($current.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw ('目录含链接或联接：' + $current.FullName) }
        $current = $current.Parent
    }
}

function Expand-JobsSetupZip {
    param([string]$Archive, [string]$Destination)
    Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName -match '(^[/\\]|(^|[/\\])\.\.([/\\]|$)|:)' -or (($entry.ExternalAttributes -shr 16) -band 61440) -eq 40960) { throw 'ZIP 含越界路径或链接。' }
        }
    } finally { $zip.Dispose() }
    Assert-JobsSetupDirectory $Destination
    [IO.Compression.ZipFile]::ExtractToDirectory($Archive, $Destination)
}
Export-ModuleMember -Function @()

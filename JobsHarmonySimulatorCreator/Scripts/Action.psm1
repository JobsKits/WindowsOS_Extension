# Action.psm1 | JobsHarmonySimulatorCreator
# Created by Jobs on 2026年10月23日，星期五.
# 只调用官方 Emulator 的本地镜像、创建和可选启动接口；不安装工具或接受许可。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking

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
    Write-Host ($Prompt + '：') -NoNewline
    $answer = [Console]::ReadLine()
    if ($null -eq $answer) { throw '输入已结束，停止操作。' }
    return $answer
}
function Get-JobsHarmonyArchitecture {
    $architecture = $env:PROCESSOR_ARCHITEW6432
    if ([string]::IsNullOrWhiteSpace($architecture)) { $architecture = $env:PROCESSOR_ARCHITECTURE }
    if ($architecture -ine 'AMD64') { throw '鸿蒙本地模拟器只支持 x64 Windows 10 / 11；Windows ARM、32 位系统和虚拟机不在官方支持范围：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-requirements' }
    return 'x86_64'
}
function Test-JobsHarmonyDesktop {
    param([string]$Target)
    $desktop = [Environment]::GetFolderPath('DesktopDirectory')
    if (-not $Target -or -not $desktop -or -not [IO.Directory]::Exists($Target)) { return $false }
    return [string]::Equals([IO.Path]::GetFullPath($Target).TrimEnd('\', '/'), [IO.Path]::GetFullPath($desktop).TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)
}
function Get-JobsHarmonyEmulator {
    param([string]$EmulatorBin = $env:HARMONY_EMULATOR_BIN)
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
    $candidates = @($candidates | Select-Object -Unique)
    if ($candidates.Count -gt 1) { throw '发现多份 DevEco Emulator，请用 HARMONY_EMULATOR_BIN 明确选择。' }
    if ($candidates.Count -eq 1) { return $candidates[0] }
    $file = Find-JobsExecutable -Name 'Emulator.exe' -Candidates @('Emulator')
    if ($file) { return $file }
    throw '未找到官方 DevEco Emulator。请先准备 DevEco Studio 6.1+ 或带 Emulator 的 Command Line Tools，或设置 HARMONY_EMULATOR_BIN；本入口不自动安装：https://developer.huawei.com/consumer/cn/deveco-studio/'
}
function Invoke-JobsHarmonyQuery {
    param([string]$Emulator, [string[]]$Arguments)
    $result = Invoke-JobsProcess -FilePath $Emulator -Arguments $Arguments -TimeoutSeconds 60
    $output = ConvertTo-JobsHarmonyPlainText $result.StdOut
    if ($result.ExitCode -ne 0) { throw ('Emulator ' + ($Arguments -join ' ') + ' 失败，退出码 ' + $result.ExitCode + [Environment]::NewLine + $output + (ConvertTo-JobsHarmonyPlainText $result.StdErr)) }
    return $output.TrimStart([char]0xfeff).Trim()
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
    param([string]$Emulator)
    $text = Invoke-JobsHarmonyQuery $Emulator @('-imageList', '-downloaded', 'true')
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
        if (-not $downloaded) { continue }
        $type = [string]$record.deviceType
        $version = [string]$record.osVersion
        if ($type -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$' -or [string]::IsNullOrWhiteSpace($version) -or $version -match '[\x00-\x1f]') { throw '已下载镜像元数据不合法，停止。' }
        $key = $type.ToLowerInvariant() + '|' + $version
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $images += [pscustomobject]@{ DeviceType = $type; OsVersion = $version; Label = $type + ' | ' + $version }
    }
    return $images
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
    param([object[]]$Existing, [string]$Name)
    if ($Name -and $Name -cnotmatch '^[A-Za-z][A-Za-z0-9_-]{0,63}$') { throw '实例名只能以英文字母开头，使用字母、数字、下划线或连字符，最多 64 字符。' }
    $requested = -not [string]::IsNullOrEmpty($Name)
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        if (-not $requested) { $Name = 'JobsHarmony_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + [guid]::NewGuid().ToString('N').Substring(0, 6) }
        $collision = @($Existing | Where-Object { $_.name -ieq $Name }).Count -gt 0
        if (-not $collision) { return $Name }
        if ($requested) { throw ('已存在同名实例，拒绝覆盖：' + $Name) }
    }
    throw '无法生成唯一实例名，没有开始创建。'
}
function Invoke-JobsHarmonyInteractive {
    param([string]$Emulator, [string[]]$Arguments)
    Write-JobsHarmonyMessage ('执行官方工具：' + $Emulator + ' ' + ($Arguments -join ' '))
    # 不重定向 stdin、不回答许可、不传 -force；用户保留官方 y/n 交互。
    $global:LASTEXITCODE = -1
    & $Emulator @Arguments
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw ('Emulator 操作失败，退出码 ' + $code + '；保留官方输出和已生成的现场。') }
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
    param([string]$EmulatorBin = $env:HARMONY_EMULATOR_BIN)
    [void](Get-JobsHarmonyArchitecture)
    $emulator = Get-JobsHarmonyEmulator $EmulatorBin
    Assert-JobsHarmonyCapabilities $emulator
    $images = @(Get-JobsHarmonyImages $emulator)
    $instances = @(Get-JobsHarmonyInstances $emulator)
    return [pscustomobject]@{ Emulator = $emulator; Images = $images; Instances = $instances }
}
function Invoke-JobsHarmonySimulatorAction {
    param([string]$Target, [string]$EmulatorBin = $env:HARMONY_EMULATOR_BIN, [string]$Name, [switch]$NoStart)
    if (-not (Test-JobsHarmonyDesktop $Target)) { throw '此入口仅适用于系统桌面空白。' }
    Remove-Variable -Name HarmonyLog -Scope Script -ErrorAction SilentlyContinue
    Write-Host ('Jobs 新建鸿蒙模拟器 · 来源：' + $PSScriptRoot) -ForegroundColor Cyan
    Write-Host '仅支持 x64 Windows 10 / 11 物理机；需要现有 DevEco Emulator 6.1+ 与已下载镜像。'
    Write-Host '将选择本机镜像、创建唯一新实例并回读验证，可选启动；不安装工具、不下载镜像、不覆盖旧实例、不自动接受许可或改系统配置。'
    Write-Host '手机等模拟器受官方中国大陆使用区域限制；需要账号授权的镜像请在 DevEco Studio 操作，不绕过限制。'
    if ((Read-JobsHarmonyInput '直接回车检查并选择，任意非空输入取消').Length -gt 0) { throw '已取消。' }
    $check = Get-JobsHarmonyCheck $EmulatorBin
    if ($check.Images.Count -eq 0) { throw '没有本机已下载的 HarmonyOS 镜像。请在 DevEco Studio > Tools > Device Manager 下载支持本机架构的镜像并本人确认许可后重试；本入口不会自动下载。' }
    $selected = Select-JobsHarmonyChoice '选择已下载的鸿蒙镜像' @($check.Images | ForEach-Object { $_.Label })
    $image = @($check.Images | Where-Object { $_.Label -ceq $selected })
    if ($image.Count -ne 1) { throw '镜像选择不唯一，停止。' }
    $nameValue = New-JobsHarmonyName -Existing $check.Instances -Name $Name
    $arguments = @('-create', $nameValue, '-deviceType', $image[0].DeviceType, '-osVersion', $image[0].OsVersion)
    Write-JobsHarmonyMessage ('即将创建：' + $nameValue + '；镜像：' + $selected)
    Write-JobsHarmonyMessage '实例与镜像路径沿用 DevEco 既有配置；机型使用官方最新默认模板。'
    if ((Read-JobsHarmonyInput '直接回车创建，任意非空输入取消').Length -gt 0) { throw '已取消。' }
    $latest = @(Get-JobsHarmonyInstances $check.Emulator)
    [void](New-JobsHarmonyName -Existing $latest -Name $nameValue)
    $logDirectory = Join-Path (Get-JobsInstallRoot) 'logs'
    [void][IO.Directory]::CreateDirectory($logDirectory)
    $script:HarmonyLog = Join-Path $logDirectory ('create-' + (Get-Date -Format 'yyyy-MM-dd-HH-mm-ss') + '-' + [guid]::NewGuid().ToString('N') + '.log')
    Write-JobsHarmonyMessage ('日志：' + $script:HarmonyLog)
    Invoke-JobsHarmonyInteractive $check.Emulator $arguments
    try { $created = @((Get-JobsHarmonyInstances $check.Emulator) | Where-Object { $_.name -ceq $nameValue }) }
    catch { throw ('创建命令已返回，但详情回读失败；请保留现场去 Device Manager 核对，不自动重试。' + [Environment]::NewLine + $_.Exception.Message) }
    if ($created.Count -ne 1 -or $null -eq $created[0].PSObject.Properties['deviceType'] -or $created[0].deviceType -ine $image[0].DeviceType -or (Get-JobsHarmonyInstanceVersion $created[0]) -cne $image[0].OsVersion) { throw '创建命令已返回，但回读没有验证唯一且匹配的实例；请保留现场在 DevEco Device Manager 核对，不要当作创建成功或自动重试。' }
    Write-JobsHarmonyMessage ('已验证新实例：' + $nameValue)
    if (-not $NoStart -and (Read-JobsHarmonyInput '直接回车启动，任意非空输入保留实例并跳过启动').Length -eq 0) {
        $startArguments = @('-start', $nameValue)
        Invoke-JobsHarmonyInteractive $check.Emulator $startArguments
        Write-JobsHarmonyMessage '启动命令已成功执行；设备启动就绪情况请查看模拟器窗口。'
    }
}
function Invoke-JobsFeature {
    param([Parameter(Mandatory = $true)][string]$Target)
    Invoke-JobsHarmonySimulatorAction -Target (Resolve-JobsTarget $Target)
}
Export-ModuleMember -Function Invoke-JobsFeature

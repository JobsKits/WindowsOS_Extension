# Action.psm1 | JobsHarmonySimulatorRepairer
# Created by Jobs on 2026年10月24日，星期六.
# 仅通过官方 Emulator 检测和启动/重启现有实例；不清除数据或重建实例。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking
function Get-JobsHarmonyToolsHome {
    if (-not $env:LOCALAPPDATA) { throw '无法定位用户级 Harmony 工具目录。' }
    return Join-Path $env:LOCALAPPDATA 'Jobs/HarmonySimulator/tools'
}
# 只接受运行时工具明确提供的诊断能力。
function Assert-JobsHarmonyCapabilities {
    param([string]$Emulator)
    $help = Invoke-JobsHarmonyQuery $Emulator @('-help')
    foreach ($flag in @('-list', '-details', '-imageList', '-start', '-stop', '-bootMode')) {
        if ($help -notmatch ('(?<![A-Za-z0-9_-])' + [regex]::Escape($flag) + '(?![A-Za-z0-9_-])')) { throw ('当前 Emulator 缺少已确认能力：' + $flag + '；请升级官方工具后重试。') }
    }
}
# 实例身份由名称、真实路径、产品类型和系统版本共同确定。
function Get-JobsHarmonyRepairFileIdentity {
    param([string]$Directory)
    $item = Get-Item -LiteralPath $Directory -Force -ErrorAction Stop
    if (-not $item.PSIsContainer) { throw '实例路径不是普通目录。' }
    $current = $item
    while ($null -ne $current) {
        if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw '实例路径不能经过链接或联接。' }
        $current = $current.Parent
    }
    $config = Join-Path $Directory 'config.ini'
    if (-not ('Jobs.HarmonyInstanceIdentity' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'HarmonyInstanceIdentity.cs') }
    return [Jobs.HarmonyInstanceIdentity]::Read($Directory, $true) + '|' + [Jobs.HarmonyInstanceIdentity]::Read($config, $false)
}
# Keep metadata plus real directory/configuration file IDs across confirmation.
function Get-JobsHarmonyRepairIdentity {
    param($Instance)
    foreach ($field in @('name', 'instancePath', 'deviceType')) {
        if ($null -eq $Instance.PSObject.Properties[$field] -or $Instance.$field -isnot [string] -or [string]::IsNullOrWhiteSpace($Instance.$field) -or $Instance.$field -match '[\x00-\x1f]') { throw ('实例详情缺少可靠字段：' + $field) }
    }
    if ($Instance.name.StartsWith('-') -or -not [IO.Path]::IsPathRooted($Instance.instancePath)) { throw '实例名称或路径无法可靠识别。' }
    $version = Get-JobsHarmonyInstanceVersion $Instance
    if (-not $version) { throw '实例详情缺少系统版本。' }
    if ($null -eq $Instance.PSObject.Properties['isRunning'] -or ($Instance.isRunning -isnot [bool] -and ($Instance.isRunning -isnot [string] -or $Instance.isRunning -cnotin @('true', 'false')))) { throw '实例详情缺少可靠 isRunning；保留只读诊断，不猜测运行状态。' }
    $running = $Instance.isRunning -is [bool] -and $Instance.isRunning
    if ($Instance.isRunning -is [string]) { $running = $Instance.isRunning -ceq 'true' }
    $uuid = ''
    if ($null -ne $Instance.PSObject.Properties['uuid']) {
        if ($Instance.uuid -isnot [string] -or $Instance.uuid -match '[\x00-\x1f]') { throw '实例 UUID 无法可靠识别。' }
        $uuid = $Instance.uuid
    }
    $fileIdentity = Get-JobsHarmonyRepairFileIdentity $Instance.instancePath
    return [pscustomobject]@{ Name = $Instance.name; Path = [IO.Path]::GetFullPath($Instance.instancePath); DeviceType = $Instance.deviceType; Version = $version; Running = $running; Uuid = $uuid; FileIdentity = $fileIdentity }
}
# 每次变更前重新读取目标身份和运行状态，避免旧菜单误操作其它实例。
function Assert-JobsHarmonyRepairTarget {
    param([string]$Emulator, $Identity, [bool]$Running)
    $matches = @(Get-JobsHarmonyInstances $Emulator | Where-Object { $_.name -ceq $Identity.Name })
    if ($matches.Count -ne 1) { throw '所选实例已经消失或名称不唯一，停止。' }
    $current = Get-JobsHarmonyRepairIdentity $matches[0]
    if ($current.Path -cne $Identity.Path -or $current.DeviceType -cne $Identity.DeviceType -or $current.Version -cne $Identity.Version -or $current.Running -ne $Running -or $current.Uuid -cne $Identity.Uuid -or $current.FileIdentity -cne $Identity.FileIdentity) { throw '所选实例身份或运行状态已变化，停止。' }
    return $current
}
# 只读体检不会创建日志、安装工具、接受协议或修改实例。
function Get-JobsHarmonyRepairCheck {
    param([string]$EmulatorBin = $env:HARMONY_EMULATOR_BIN)
    [void](Get-JobsHarmonyArchitecture)
    $emulator = Get-JobsHarmonyEmulator $EmulatorBin
    Assert-JobsHarmonyCapabilities $emulator
    $images = @(Get-JobsHarmonyImages $emulator)
    $instances = @(Get-JobsHarmonyInstances $emulator)
    return [pscustomobject]@{ Emulator = $emulator; Images = $images; Instances = $instances }
}
# 有限轮询官方状态；超时保留现场并返回失败，不自动重试启动。
function Wait-JobsHarmonyRepairState {
    param([string]$Emulator, $Identity, [bool]$Running)
    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        $matches = @(Get-JobsHarmonyInstances $Emulator | Where-Object { $_.name -ceq $Identity.Name })
        if ($matches.Count -ne 1) { throw '状态回读失去唯一实例，停止。' }
        $current = Get-JobsHarmonyRepairIdentity $matches[0]
        if ($current.Path -cne $Identity.Path -or $current.DeviceType -cne $Identity.DeviceType -or $current.Version -cne $Identity.Version -or $current.Uuid -cne $Identity.Uuid -or $current.FileIdentity -cne $Identity.FileIdentity) { throw '状态回读发现实例身份变化，停止。' }
        if ($current.Running -eq $Running) { return }
        if ($attempt -lt 9) { Start-Sleep -Milliseconds 1000 }
    }
    throw '官方实例状态尚未达到预期；保留现场，请在 DevEco Device Manager 检查，不自动再次启动。'
}
# 重启只使用官方 stop/start，不传 reset、delete 或清数据参数。
function Invoke-JobsHarmonyRepairOperation {
    param([string]$Emulator, $Identity)
    [void](Assert-JobsHarmonyRepairTarget $Emulator $Identity $Identity.Running)
    if ($Identity.Running) {
        if ((Read-JobsHarmonyInput ('将停止并冷启动 ' + $Identity.Name + '，会中断该实例中的在途任务；输入 YES 继续')) -cne 'YES') { throw '已取消，未停止实例。' }
        [void](Assert-JobsHarmonyRepairTarget $Emulator $Identity $true)
        Invoke-JobsHarmonyInteractive $Emulator @('-stop', $Identity.Name)
        Wait-JobsHarmonyRepairState $Emulator $Identity $false
    } elseif ((Read-JobsHarmonyInput ('回车冷启动 ' + $Identity.Name + '；任意非空输入取消')).Length -ne 0) { throw '已取消，未启动实例。' }
    [void](Assert-JobsHarmonyRepairTarget $Emulator $Identity $false)
    Invoke-JobsHarmonyInteractive $Emulator @('-start', $Identity.Name, '-bootMode', 'coldboot')
    Wait-JobsHarmonyRepairState $Emulator $Identity $true
    Write-JobsHarmonyMessage ('已回读确认实例运行：' + $Identity.Name + '；系统和 hdc 连接就绪请在模拟器窗口核对。')
}
# 桌面入口先展示影响范围，随后诊断并选择现有实例。
function Invoke-JobsHarmonyRepairAction {
    param([string]$Target, [string]$EmulatorBin = $env:HARMONY_EMULATOR_BIN)
    if (-not (Test-JobsHarmonyDesktop $Target)) { throw '此入口仅适用于系统桌面空白。' }
    Remove-Variable -Name HarmonyLog -Scope Script -ErrorAction SilentlyContinue
    Write-Host 'Jobs Harmony 模拟器检测与修复' -ForegroundColor Cyan
    Write-Host '检测已有官方 DevEco Emulator、本地镜像与实例；可启动已停止实例，或输入 YES 后停止并冷启动正在运行的实例。'
    Write-Host '仅操作所选本地实例；不下载、不接受许可、不删应用或数据、不重建实例、不改代理与 PATH。未知状态停止。Ctrl+C 取消。'
    if ((Read-JobsHarmonyInput '回车开始只读检测；任意非空输入取消').Length -ne 0) { throw '已取消。' }
    $logs = Join-Path (Get-JobsInstallRoot) 'logs'
    [void][IO.Directory]::CreateDirectory($logs)
    $script:HarmonyLog = Join-Path $logs ('repair-' + (Get-Date -Format 'yyyy-MM-dd-HH-mm-ss') + '-' + [guid]::NewGuid().ToString('N') + '.log')
    Write-JobsHarmonyMessage ('日志：' + $script:HarmonyLog)
    $check = Get-JobsHarmonyRepairCheck $EmulatorBin
    Write-JobsHarmonyMessage ('Emulator：' + $check.Emulator + '；已下载 Release 镜像：' + $check.Images.Count + '；实例：' + $check.Instances.Count)
    if ($check.Instances.Count -eq 0) { throw '没有现有实例可修复；请使用“新建 Harmony 模拟器”或在 DevEco Device Manager 创建后重新检测。' }
    foreach ($record in $check.Instances) { Write-JobsHarmonyMessage ($record | ConvertTo-Json -Depth 8 -Compress) }
    $name = Select-JobsHarmonyChoice '选择现有 Harmony 实例（q / Esc 取消）' @($check.Instances | ForEach-Object { $_.name })
    $selected = @($check.Instances | Where-Object { $_.name -ceq $name })
    if ($selected.Count -ne 1) { throw '实例选择无效。' }
    $identity = Get-JobsHarmonyRepairIdentity $selected[0]
    Invoke-JobsHarmonyRepairOperation $check.Emulator $identity
}
function Invoke-JobsFeature {
    param([Parameter(Mandatory = $true)][string]$Target)
    Invoke-JobsHarmonyRepairAction -Target (Resolve-JobsTarget $Target)
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
    Write-Host ($Prompt + '：') -NoNewline
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

    throw '未找到兼容 DevEco Emulator。请先准备官方工具，或运行“新建 Harmony 模拟器”补齐；本检测入口不自动下载。'

}
function Invoke-JobsHarmonyQuery {
    param([string]$Emulator, [string[]]$Arguments)
    $result = Invoke-JobsProcess -FilePath $Emulator -Arguments $Arguments -TimeoutSeconds 60
    $output = ConvertTo-JobsHarmonyPlainText $result.StdOut
    if ($result.ExitCode -ne 0) { throw ('Emulator ' + ($Arguments -join ' ') + ' 失败，退出码 ' + $result.ExitCode + [Environment]::NewLine + $output + (ConvertTo-JobsHarmonyPlainText $result.StdErr)) }
    $output = $output.TrimStart([char]0xfeff).Trim()
    $errorText = (ConvertTo-JobsHarmonyPlainText $result.StdErr).Trim()
    # 6.1.1.200 实测空结果不是 JSON；仅精确匹配成功响应，不吞掉未知错误。
    if (($Arguments -join ' ') -match '^-imageList -downloaded (true|false)$' -and [string]::IsNullOrEmpty($output) -and $errorText -ceq 'No images matching the criteria were found.') { return '[]' }
    if (($Arguments -join ' ') -ceq '-list -details' -and $output -ceq '[Empty]' -and [string]::IsNullOrEmpty($errorText)) { return '[]' }
    return $output
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
    if (-not $text.StartsWith('[')) { throw '实例详情必须为官方 JSON 数组。' }
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
function Invoke-JobsHarmonyInteractive {
    param([string]$Emulator, [string[]]$Arguments)
    Write-JobsHarmonyMessage ('执行官方工具：' + $Emulator + ' ' + ($Arguments -join ' '))
    # 保留 stdin 与官方退出码；许可仅在本人明确同意后接受，-force 仅用于确认后的镜像安装。
    $global:LASTEXITCODE = -1
    & $Emulator @Arguments | Out-Host
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw ('Emulator 操作失败，退出码 ' + $code + '；保留官方输出和已生成的现场。') }
}
# 展示随工具分发的许可原文；只有用户明确回车同意后才执行官方接受命令。
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

Export-ModuleMember -Function Invoke-JobsFeature

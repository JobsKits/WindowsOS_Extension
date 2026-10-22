# Action.psm1 | JobsAndroidSimulatorCreator
# Created by Jobs on 2026年10月22日，星期四.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking

function Read-JobsAndroidChoice {
    param([string]$Prompt, [object[]]$Items)
    if ($Items.Count -eq 0) { throw '没有可供选择的项目。' }
    for ($index = 0; $index -lt $Items.Count; $index++) { Write-Host ('  {0}. {1}' -f ($index + 1), $Items[$index]) }
    while ($true) {
        $answer = Read-JobsAndroidInput ($Prompt + '（回车第 1 项，q 取消）')
        if ($answer -eq 'q') { throw '已取消。' }
        if ($answer.Length -eq 0) { return $Items[0] }
        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $Items.Count) { return $Items[$number - 1] }
        Write-Host '请输入列表编号。' -ForegroundColor Yellow
    }
}
function Read-JobsAndroidInput {
    param([string]$Prompt)
    # Console.ReadLine 能区分 EOF 与真正回车，重定向 / 无交互时不执行默认动作。
    Write-Host ($Prompt + '：') -NoNewline
    $answer = [Console]::ReadLine()
    if ($null -eq $answer) { throw '输入已结束，停止操作。' }
    return $answer
}
function Confirm-JobsAndroidDownload {
    param([string]$Description)
    Write-Host $Description -ForegroundColor Yellow
    return (Read-JobsAndroidInput '输入 YES 下载 / 安装，直接回车取消') -ceq 'YES'
}
function Get-JobsAndroidArchitecture {
    $architecture = $env:PROCESSOR_ARCHITEW6432
    if ([string]::IsNullOrWhiteSpace($architecture)) { $architecture = $env:PROCESSOR_ARCHITECTURE }
    if ($architecture -ine 'AMD64') {
        throw '当前 Android Emulator 官方不支持 Windows ARM / 32 位宿主。请使用 x64 Windows 10 / 11：https://developer.android.com/studio/install#windows'
    }
    return 'x86_64'
}
function Get-JobsAndroidSdk {
    $candidates = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT)
    if ($env:LOCALAPPDATA) { $candidates += Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            # 显式配置优先；不能悄悄把损坏的指定 SDK 切到另一份。
            return [IO.Path]::GetFullPath($candidate)
        }
    }
    throw '无法定位 SDK，请设置 ANDROID_HOME 或当前用户 LOCALAPPDATA。'
}
function Get-JobsAndroidJava {
    $candidates = @()
    if ($env:JAVA_HOME) { $candidates += Join-Path $env:JAVA_HOME 'bin/java.exe' }
    foreach ($base in @($env:ProgramFiles, $env:LOCALAPPDATA)) {
        if ($base) { $candidates += Join-Path $base 'Android/Android Studio/jbr/bin/java.exe' }
    }
    $pathJava = Find-JobsExecutable 'java.exe'
    if ($pathJava) { $candidates += $pathJava }
    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $result = Invoke-JobsProcess -FilePath $candidate -Arguments @('-version') -TimeoutSeconds 15
        if ($result.ExitCode -eq 0) { return $candidate }
    }
    throw '没有健康 Java。请安装 Android Studio（附带 JBR）或受支持的 JDK，并设置 JAVA_HOME 后重试：https://developer.android.com/studio/install'
}
function Get-JobsAndroidTools {
    param([string]$Sdk)
    $directory = Join-Path $Sdk 'cmdline-tools'
    $roots = @()
    if (Test-Path -LiteralPath $directory -PathType Container) {
        $roots = @(Get-ChildItem -LiteralPath $directory -Directory | Sort-Object @{ Expression = { $_.Name -eq 'latest' }; Descending = $true }, LastWriteTime -Descending)
    }
    foreach ($root in $roots) {
        if ((Test-Path -LiteralPath (Join-Path $root.FullName 'lib/sdkmanager-classpath.jar') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $root.FullName 'lib/avdmanager-classpath.jar') -PathType Leaf)) { return $root.FullName }
    }
    return $null
}
function Invoke-JobsAndroidTool {
    param([string]$Java, [string]$Tools, [ValidateSet('sdkmanager', 'avdmanager')][string]$Tool, [string[]]$Arguments, [string]$InputText, [switch]$Interactive, [int]$TimeoutSeconds = 90)
    $mainClass = 'com.android.sdklib.tool.sdkmanager.SdkManagerCli'
    if ($Tool -eq 'avdmanager') { $mainClass = 'com.android.sdklib.tool.AvdManagerCli' }
    # 直接 Java argv 避开 .bat / CMD 对 SDK 路径内 &、%、单引号的二次解释。
    $argumentsList = @(('-Dcom.android.sdklib.toolsdir=' + $Tools), '-classpath', (Join-Path $Tools ('lib/' + $Tool + '-classpath.jar')), $mainClass) + $Arguments
    if ($Interactive) {
        & $Java @argumentsList
        if ($LASTEXITCODE -ne 0) { throw ($Tool + ' 执行失败，退出码 ' + $LASTEXITCODE) }
        return
    }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Java
    $start.Arguments = (@($argumentsList | ForEach-Object { Quote-JobsArgument $_ }) -join ' ')
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.RedirectStandardInput = $true
    $process = [Diagnostics.Process]::Start($start)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if ($InputText) { $process.StandardInput.Write($InputText) }
        $process.StandardInput.Close()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) { $process.Kill(); throw ($Tool + ' 超时，已停止本次 Java 进程。') }
        $output = $stdout.GetAwaiter().GetResult()
        $errorText = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw ($Tool + ' 执行失败：' + $errorText + $output) }
        if ($errorText) { Write-Host $errorText -ForegroundColor DarkYellow }
        return $output
    } finally { $process.Dispose() }
}
function Install-JobsAndroidCommandTools {
    param([string]$Sdk, [string]$Reason = '缺少 SDK Command-Line Tools。')
    if (-not (Confirm-JobsAndroidDownload ($Reason + '来源：https://dl.google.com/android/repository/；目标：' + $Sdk + '。下载代表接受 SDK 条款 https://developer.android.com/studio/terms 。不覆盖已有目录。'))) { throw '未安装 Command-Line Tools，停止。' }
    $previousProtocol = [Net.ServicePointManager]::SecurityProtocol
    # 下载、解压与最终重命名都放在 SDK 卷内，兼容系统临时目录与 SDK 分属 C: / D:。
    $parent = Join-Path $Sdk 'cmdline-tools'
    [void][IO.Directory]::CreateDirectory($parent)
    $temporary = Join-Path $parent ('.jobs-stage-' + [guid]::NewGuid().ToString('N'))
    try {
        [Net.ServicePointManager]::SecurityProtocol = $previousProtocol -bor [Net.SecurityProtocolType]::Tls12
        [void][IO.Directory]::CreateDirectory($temporary)
        $xmlPath = Join-Path $temporary 'repository.xml'
        Invoke-WebRequest -UseBasicParsing -Uri 'https://dl.google.com/android/repository/repository2-3.xml' -OutFile $xmlPath -TimeoutSec 60
        $settings = New-Object Xml.XmlReaderSettings
        $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
        $reader = [Xml.XmlReader]::Create($xmlPath, $settings)
        $document = New-Object Xml.XmlDocument
        try { $document.Load($reader) } finally { $reader.Dispose() }
        $archive = $document.SelectSingleNode("//*[local-name()='remotePackage' and @path='cmdline-tools;latest']/*[local-name()='archives']/*[local-name()='archive'][*[local-name()='host-os']='windows']/*[local-name()='complete']")
        if ($null -eq $archive) { throw '官方仓库未返回 Windows 命令行工具，停止。' }
        $relative = $archive.SelectSingleNode("*[local-name()='url']").InnerText
        if ($relative -cnotmatch '^commandlinetools-win-[0-9]+_latest\.zip$') { throw '官方归档地址不符合预期，停止。' }
        $checksum = $archive.SelectSingleNode("*[local-name()='checksum']")
        $algorithm = $checksum.GetAttribute('type').ToUpperInvariant().Replace('-', '')
        if ($algorithm -notin @('SHA1', 'SHA256')) { throw '无法识别官方归档校验算法。' }
        $zip = Join-Path $temporary 'tools.zip'
        Write-Host ('下载来源：https://dl.google.com/android/repository/' + $relative)
        Invoke-WebRequest -UseBasicParsing -Uri ('https://dl.google.com/android/repository/' + $relative) -OutFile $zip -TimeoutSec 600
        if ((Get-FileHash -LiteralPath $zip -Algorithm $algorithm).Hash -ine $checksum.InnerText.Trim()) { throw '官方归档校验失败，未安装。' }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archiveFile = [IO.Compression.ZipFile]::OpenRead($zip)
        try {
            foreach ($entry in $archiveFile.Entries) {
                if ($entry.FullName -match '(^[/\\]|(^|[/\\])\.\.([/\\]|$)|:)') { throw '压缩包含越界路径，停止。' }
            }
        } finally { $archiveFile.Dispose() }
        $expanded = Join-Path $temporary 'expanded'
        [IO.Compression.ZipFile]::ExtractToDirectory($zip, $expanded)
        $source = Join-Path $expanded 'cmdline-tools'
        foreach ($name in @('sdkmanager', 'avdmanager')) {
            if (-not (Test-Path -LiteralPath (Join-Path $source ('lib/' + $name + '-classpath.jar')) -PathType Leaf)) { throw '下载工具目录结构不完整。' }
        }
        $destination = Join-Path $parent ('jobs-' + (Get-Date -Format 'yyyyMMddHHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        [IO.Directory]::Move($source, $destination)
        return $destination
    } finally {
        [Net.ServicePointManager]::SecurityProtocol = $previousProtocol
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
    }
}
function Assert-JobsAndroidCommandTools {
    param([string]$Java, [string]$Tools)
    [void](Invoke-JobsAndroidTool $Java $Tools 'sdkmanager' @('--version'))
    [void](Invoke-JobsAndroidTool $Java $Tools 'avdmanager' @('list', 'device', '-c'))
}
function Get-JobsAndroidHealthyTools {
    param([string]$Sdk, [string]$Java, [switch]$ReadOnly)
    $tools = Get-JobsAndroidTools $Sdk
    $reason = '缺少 SDK Command-Line Tools。'
    if ($tools) {
        try { Assert-JobsAndroidCommandTools $Java $tools; return $tools }
        catch { $reason = '现有 Command-Line Tools 体检失败：' + $_.Exception.Message + [Environment]::NewLine }
    }
    if ($ReadOnly) { throw ($reason + '只读体检不会修复或下载。') }
    # 每次业务只允许安装一个独立版本；新版本再次失败时不循环安装。
    $repaired = Install-JobsAndroidCommandTools -Sdk $Sdk -Reason $reason
    try { Assert-JobsAndroidCommandTools $Java $repaired }
    catch { throw ('Command-Line Tools 安装 / 修复后仍不可用，停止：' + $_.Exception.Message) }
    return $repaired
}
function Get-JobsAndroidUnhealthyComponents {
    param([string]$Sdk)
    foreach ($component in @(@('emulator', 'emulator/emulator.exe', '-version'), @('platform-tools', 'platform-tools/adb.exe', 'version'))) {
        $failure = $null
        $path = Join-Path $Sdk $component[1]
        try {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw '执行文件不存在。' }
            $result = Invoke-JobsProcess -FilePath $path -Arguments @($component[2]) -TimeoutSeconds 20
            if ($result.ExitCode -ne 0) { throw ('退出码 ' + $result.ExitCode + '；' + $result.StdErr + $result.StdOut) }
        } catch { $failure = $_.Exception.Message }
        if ($failure) {
            [pscustomobject]@{ Id = $component[0]; Error = $failure; HasDirectory = (Test-Path -LiteralPath (Join-Path $Sdk $component[0]) -PathType Container) }
        }
    }
}
function Repair-JobsAndroidComponents {
    param([string]$Sdk, [string]$Java, [string]$Tools, [switch]$ReadOnly)
    $unhealthy = @(Get-JobsAndroidUnhealthyComponents $Sdk)
    if ($unhealthy.Count -eq 0) { return }
    $details = @($unhealthy | ForEach-Object { $_.Id + '：' + $_.Error }) -join [Environment]::NewLine
    if ($ReadOnly) { throw ('SDK 工具体检失败；只读模式不会修复：' + [Environment]::NewLine + $details) }
    $description = 'SDK 工具缺失或损坏：' + [Environment]::NewLine + $details + [Environment]::NewLine +
        '从 Google 官方源修复一次到 ' + $Sdk + '。损坏的已有工具包会先卸载再安装；下载失败时可能暂时缺失该工具。AVD、系统镜像及其它工具包保留。'
    if (-not (Confirm-JobsAndroidDownload $description)) { throw '未修复必要 SDK 工具，停止。' }
    Invoke-JobsAndroidTool $Java $Tools 'sdkmanager' @(('--sdk_root=' + $Sdk), '--licenses') -Interactive
    foreach ($component in $unhealthy) {
        if ($component.HasDirectory) {
            Invoke-JobsAndroidTool $Java $Tools 'sdkmanager' @(('--sdk_root=' + $Sdk), '--uninstall', $component.Id) -Interactive
        }
    }
    $identifiers = @($unhealthy | ForEach-Object { $_.Id })
    Invoke-JobsAndroidTool $Java $Tools 'sdkmanager' (@(('--sdk_root=' + $Sdk), '--install') + $identifiers) -Interactive
    $remaining = @(Get-JobsAndroidUnhealthyComponents $Sdk)
    if ($remaining.Count -gt 0) {
        throw ('SDK 工具修复后仍不可用，停止：' + (@($remaining | ForEach-Object { $_.Id + '：' + $_.Error }) -join '；'))
    }
}
function Get-JobsAndroidImages {
    param([string]$Listing, [string]$Abi)
    $seen = @{}
    foreach ($line in ($Listing -split '\r?\n')) {
        if ($line -match '^\s*(system-images;android-(\d+(?:\.\d+)?(?:-ext\d+)?);(?:google_apis_playstore|google_apis|default);(x86_64|arm64-v8a))\s*\|') {
            if ($Matches[3] -ceq $Abi -and -not $seen.ContainsKey($Matches[1])) {
                $identifier = $Matches[1]
                $api = $Matches[2]
                $extension = 0
                if ($api -match '-ext(\d+)$') { $extension = [int]$Matches[1] }
                $apiVersion = $api -replace '-ext\d+$', ''
                if ($apiVersion -notmatch '\.') { $apiVersion += '.0' }
                $seen[$identifier] = [pscustomobject]@{ Version = [version]$apiVersion; Extension = $extension }
            }
        }
    }
    return @($seen.Keys | Sort-Object @{ Expression = { $seen[$_].Version }; Descending = $true }, @{ Expression = { $seen[$_].Extension }; Descending = $true }, @{ Expression = { if ($_ -like '*;google_apis;*') { 0 } elseif ($_ -like '*;google_apis_playstore;*') { 1 } else { 2 } } }, @{ Expression = { $_ } })
}
function Get-JobsAndroidDevices {
    param([string]$Listing)
    $items = @()
    foreach ($line in ($Listing -split '\r?\n')) {
        if ($line -match '^\s*id:\s+\d+\s+or\s+"([^"\r\n]+)"') { $items += $Matches[1] }
    }
    return @($items | Select-Object -Unique | Sort-Object @{ Expression = { $_ -notmatch '^pixel' } }, @{ Expression = { $_ }; Descending = $true })
}
function Get-JobsAndroidAvdHome {
    if ($env:ANDROID_AVD_HOME) { return [IO.Path]::GetFullPath($env:ANDROID_AVD_HOME) }
    if ($env:ANDROID_EMULATOR_HOME) { return Join-Path $env:ANDROID_EMULATOR_HOME 'avd' }
    if ($env:ANDROID_USER_HOME) { return Join-Path $env:ANDROID_USER_HOME 'avd' }
    return Join-Path ([Environment]::GetFolderPath('UserProfile')) '.android/avd'
}
function New-JobsAndroidAvdName {
    param([string]$Device, [string]$Image, [string[]]$Existing, [string]$AvdHome)
    $api = 'API'
    if ($Image -match ';android-(\d+(?:\.\d+)?(?:-ext\d+)?);') { $api = 'API' + $Matches[1] }
    for ($attempt = 0; $attempt -lt 8; $attempt++) {
        $name = 'Jobs_' + ($Device -replace '[^a-zA-Z0-9_.-]', '_') + '_' + $api + '_' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        if ($name -notin $Existing -and -not (Test-Path -LiteralPath (Join-Path $AvdHome ($name + '.ini'))) -and -not (Test-Path -LiteralPath (Join-Path $AvdHome ($name + '.avd')))) { return $name }
    }
    throw '无法生成未占用的 AVD 名称。'
}
function Test-JobsAndroidBoot {
    param([string]$Adb, [string]$Serial, [string]$ExpectedName)
    $result = Invoke-JobsProcess -FilePath $Adb -Arguments @('-s', $Serial, 'shell', 'getprop', 'sys.boot_completed') -TimeoutSeconds 10
    if ($result.ExitCode -ne 0 -or $result.StdOut.Trim() -cne '1') { return $false }
    $nameResult = Invoke-JobsProcess -FilePath $Adb -Arguments @('-s', $Serial, 'emu', 'avd', 'name') -TimeoutSeconds 10
    return $nameResult.ExitCode -eq 0 -and @($nameResult.StdOut -split '\r?\n')[0].Trim() -ceq $ExpectedName
}
function Start-JobsAndroidAvd {
    param([string]$Sdk, [string]$Name)
    $emulator = Join-Path $Sdk 'emulator/emulator.exe'
    $adb = Join-Path $Sdk 'platform-tools/adb.exe'
    $devices = Invoke-JobsProcess -FilePath $adb -Arguments @('devices') -TimeoutSeconds 20
    if ($devices.ExitCode -ne 0) { throw ('adb 设备检查失败：' + $devices.StdErr) }
    foreach ($line in ($devices.StdOut -split '\r?\n')) {
        if ($line -match '^(emulator-\d+)\s+device\s*$') {
            $serial = $Matches[1]
            $avd = Invoke-JobsProcess -FilePath $adb -Arguments @('-s', $serial, 'emu', 'avd', 'name') -TimeoutSeconds 15
            if ($avd.ExitCode -eq 0 -and @($avd.StdOut -split '\r?\n')[0].Trim() -ceq $Name) {
                if (Test-JobsAndroidBoot $adb $serial $Name) { Write-Host ('模拟器已运行：' + $Name); return }
                throw ('该 AVD 已在启动中，请稍后检查：' + $Name)
            }
        }
    }
    $port = 0
    for ($candidate = 5554; $candidate -le 5682; $candidate += 2) {
        $listeners = @()
        try {
            foreach ($value in @($candidate, ($candidate + 1))) { $listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, $value); $listener.Start(); $listeners += $listener }
            $port = $candidate
        } catch { } finally { foreach ($listener in $listeners) { $listener.Stop() } }
        if ($port) { break }
    }
    if (-not $port) { throw '没有空闲模拟器端口。' }
    $logs = Join-Path (Get-JobsInstallRoot) 'logs'
    [void][IO.Directory]::CreateDirectory($logs)
    $prefix = Join-Path $logs ($Name + '-' + (Get-Date -Format 'yyyyMMddHHmmss'))
    $process = Start-Process -FilePath $emulator -ArgumentList @('-avd', (Quote-JobsArgument $Name), '-port', $port, '-no-boot-anim') -RedirectStandardOutput ($prefix + '.stdout.log') -RedirectStandardError ($prefix + '.stderr.log') -PassThru
    Write-Host ('等待 Android 完成启动；日志：' + $prefix + '.stderr.log')
    $deadline = [DateTime]::UtcNow.AddSeconds(180)
    try {
        while ([DateTime]::UtcNow -lt $deadline) {
            if ($process.HasExited) { throw ('模拟器退出，退出码 ' + $process.ExitCode + '；日志：' + $prefix + '.stderr.log') }
            if (Test-JobsAndroidBoot $adb ('emulator-' + $port) $Name) { Write-Host ('Android 模拟器已就绪：' + $Name) -ForegroundColor Green; return }
            Start-Sleep -Seconds 2
        }
        throw ('等待启动超时；保留 AVD / 进程，请查看日志：' + $prefix + '.stderr.log')
    } finally { $process.Dispose() }
}
function Test-JobsAndroidDesktop {
    param([string]$Target)
    $desktop = [Environment]::GetFolderPath('DesktopDirectory')
    if ([string]::IsNullOrWhiteSpace($desktop)) { return $false }
    return [string]::Equals([IO.Path]::GetFullPath($Target).TrimEnd('\', '/'), [IO.Path]::GetFullPath($desktop).TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)
}
function Invoke-JobsAndroidSimulatorAction {
    param([string]$Target, [switch]$Create)
    if (-not (Test-JobsAndroidDesktop $Target)) { throw '此入口仅适用于系统桌面空白。' }
    $abi = Get-JobsAndroidArchitecture
    $sdk = Get-JobsAndroidSdk
    $java = Get-JobsAndroidJava
    $oldAndroidHome = $env:ANDROID_HOME
    $oldJavaHome = $env:JAVA_HOME
    try {
        $env:ANDROID_HOME = $sdk
        $env:JAVA_HOME = Split-Path -Parent (Split-Path -Parent $java)
        Write-Host ('SDK 来源：' + $sdk + [Environment]::NewLine + 'Java 来源：' + $java)
        $tools = Get-JobsAndroidHealthyTools -Sdk $sdk -Java $java
        Repair-JobsAndroidComponents -Sdk $sdk -Java $java -Tools $tools
        $emulator = Join-Path $sdk 'emulator/emulator.exe'
        $acceleration = Invoke-JobsProcess -FilePath $emulator -Arguments @('-accel-check') -TimeoutSeconds 20
        if ($acceleration.ExitCode -ne 0) { throw ('硬件加速不可用，请按官方说明启用 WHPX / BIOS 虚拟化；不会自动修改系统：https://developer.android.com/studio/run/emulator-acceleration' + [Environment]::NewLine + $acceleration.StdOut + $acceleration.StdErr) }
        $list = Invoke-JobsProcess -FilePath $emulator -Arguments @('-list-avds') -TimeoutSeconds 20
        if ($list.ExitCode -ne 0) { throw '现有 AVD 清单读取失败。' }
        $existing = @($list.StdOut -split '\r?\n' | Where-Object { $_ -cmatch '^[a-zA-Z0-9_.-]+$' })
        $mode = '新建 Android 模拟器'
        if (-not $Create) { $mode = Read-JobsAndroidChoice '操作' @('新建 Android 模拟器', '启动已有 Android 模拟器') }
        if ($mode -eq '启动已有 Android 模拟器') {
            $name = Read-JobsAndroidChoice '选择已有 AVD' $existing
        } else {
            $listing = Invoke-JobsAndroidTool $java $tools 'sdkmanager' @(('--sdk_root=' + $sdk), '--list_installed')
            $images = @(Get-JobsAndroidImages $listing $abi)
            if ($images.Count -eq 0) {
                if (-not (Confirm-JobsAndroidDownload ('没有本机 ' + $abi + ' 系统镜像。是否查询 Google 官方可用镜像？后续选定后再确认安装。'))) { throw '没有系统镜像，停止。' }
                $listing = Invoke-JobsAndroidTool $java $tools 'sdkmanager' @(('--sdk_root=' + $sdk), '--list', '--channel=0')
                $images = @(Get-JobsAndroidImages $listing $abi)
                $image = Read-JobsAndroidChoice '选择待安装稳定系统镜像' $images
                if (-not (Confirm-JobsAndroidDownload ('安装 ' + $image + ' 到 ' + $sdk + '，可能下载数 GB；SDK 许可交互由官方工具显示。'))) { throw '已取消镜像安装。' }
                Invoke-JobsAndroidTool $java $tools 'sdkmanager' @(('--sdk_root=' + $sdk), '--licenses') -Interactive
                Invoke-JobsAndroidTool $java $tools 'sdkmanager' @(('--sdk_root=' + $sdk), '--install', $image) -Interactive
                $installed = Invoke-JobsAndroidTool $java $tools 'sdkmanager' @(('--sdk_root=' + $sdk), '--list_installed')
                if ($image -notin @(Get-JobsAndroidImages $installed $abi)) { throw '镜像安装后复检失败，停止。' }
            } else { $image = Read-JobsAndroidChoice '选择已安装系统镜像' $images }
            $devices = @(Get-JobsAndroidDevices (Invoke-JobsAndroidTool $java $tools 'avdmanager' @('list', 'device')))
            $device = Read-JobsAndroidChoice '选择设备型号' $devices
            $avdHome = Get-JobsAndroidAvdHome
            $name = New-JobsAndroidAvdName $device $image $existing $avdHome
            Write-Host ('即将创建：' + $name + [Environment]::NewLine + '机型：' + $device + [Environment]::NewLine + '系统：' + $image + [Environment]::NewLine + 'AVD 目录：' + $avdHome)
            if ((Read-JobsAndroidInput '直接回车创建并启动，任意非空输入取消').Length -gt 0) { throw '已取消。' }
            # 无 --force，不覆盖已有 AVD；失败保留本次目录便于查日志。
            [void](Invoke-JobsAndroidTool $java $tools 'avdmanager' @('create', 'avd', '--name', $name, '--package', $image, '--device', $device) -InputText "no`n")
            $created = Invoke-JobsProcess -FilePath $emulator -Arguments @('-list-avds') -TimeoutSeconds 20
            if ($created.ExitCode -ne 0 -or $name -notin @($created.StdOut -split '\r?\n')) { throw ('创建后未在 AVD 清单找到 ' + $name + '，停止。') }
            Write-JobsLog ('Created Android AVD ' + $name)
        }
        Start-JobsAndroidAvd $sdk $name
    } finally { $env:ANDROID_HOME = $oldAndroidHome; $env:JAVA_HOME = $oldJavaHome }
}
function Invoke-JobsFeature {
    param([Parameter(Mandatory = $true)][string]$Target)
    Invoke-JobsAndroidSimulatorAction -Target (Resolve-JobsTarget $Target) -Create
}
Export-ModuleMember -Function Invoke-JobsFeature

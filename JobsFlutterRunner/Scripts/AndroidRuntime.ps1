# AndroidRuntime.ps1 | JobsFlutterRunner
# Created by Jobs on 2026年10月29日，星期四.
# 复用 JobsAndroidSimulatorCreator 的工具链自检与 AVD 实现；仅定义函数，由本包运行器调用。
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
    $local = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($local)) { $local = [Environment]::GetFolderPath('LocalApplicationData') }
    if (-not [string]::IsNullOrWhiteSpace($local)) { $candidates += Join-Path $local 'Android/Sdk' }
    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            # 显式配置优先；不能悄悄把损坏的指定 SDK 切到另一份。
            if (-not [IO.Path]::IsPathRooted($candidate) -or ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT -and $candidate -notmatch '^[a-zA-Z]:[\\/]')) { throw ('SDK 必须使用本机绝对路径：' + $candidate) }
            $path = [IO.Path]::GetFullPath($candidate)
            if (Test-Path -LiteralPath $path) {
                $item = Get-Item -LiteralPath $path -Force
                if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ('SDK 目标不是普通目录：' + $path) }
            }
            return $path
        }
    }
    throw '无法定位 SDK，请设置 ANDROID_HOME 或当前用户 LOCALAPPDATA。'
}
function Get-JobsAndroidJavaRoot {
    $local = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($local)) { $local = [Environment]::GetFolderPath('LocalApplicationData') }
    if ([string]::IsNullOrWhiteSpace($local)) { throw '无法定位当前用户 Java 安装目录。' }
    return Join-Path $local 'Jobs/AndroidToolchain/java'
}
function Test-JobsAndroidJava {
    param([string]$Path)
    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
        $result = Invoke-JobsProcess -FilePath $Path -Arguments @('-version') -TimeoutSeconds 15
        $version = $result.StdErr + [Environment]::NewLine + $result.StdOut
        return $result.ExitCode -eq 0 -and $version -match '(?:openjdk|java) version "(\d+)' -and [int]$Matches[1] -ge 21
    } catch { return $false }
}
function Expand-JobsAndroidArchive {
    param([string]$Archive, [string]$Destination)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archiveFile = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        foreach ($entry in $archiveFile.Entries) {
            if ($entry.FullName -match '(^[/\\]|(^|[/\\])\.\.([/\\]|$)|:)') { throw '压缩包含越界路径，停止。' }
        }
    } finally { $archiveFile.Dispose() }
    [IO.Compression.ZipFile]::ExtractToDirectory($Archive, $Destination)
}
function Install-JobsAndroidJava {
    $parent = Get-JobsAndroidJavaRoot
    [void][IO.Directory]::CreateDirectory($parent)
    $stage = Join-Path $parent ('.jobs-stage-' + [guid]::NewGuid().ToString('N'))
    $previousProtocol = [Net.ServicePointManager]::SecurityProtocol
    try {
        [void][IO.Directory]::CreateDirectory($stage)
        [Net.ServicePointManager]::SecurityProtocol = $previousProtocol -bor [Net.SecurityProtocolType]::Tls12
        $metadata = Join-Path $stage 'temurin.json'
        $metadataUrl = 'https://api.adoptium.net/v3/assets/latest/21/hotspot?architecture=x64&image_type=jdk&os=windows&vendor=eclipse'
        Write-Host ('自动补齐 Java 21；元数据来源：' + $metadataUrl + [Environment]::NewLine + '安装目标：' + $parent)
        Invoke-WebRequest -UseBasicParsing -Uri $metadataUrl -OutFile $metadata -TimeoutSec 60
        $parsed = Get-Content -LiteralPath $metadata -Raw -Encoding UTF8 | ConvertFrom-Json
        $assets = @($parsed)
        $asset = @($assets | Where-Object { $_.version.major -eq 21 -and $_.binary.os -ceq 'windows' -and $_.binary.architecture -ceq 'x64' -and $_.binary.image_type -ceq 'jdk' -and $_.vendor -ceq 'eclipse' })
        if ($asset.Count -ne 1) { throw '官方 API 未返回唯一 Windows x64 Temurin 21 JDK。' }
        $package = $asset[0].binary.package
        $link = [string]$package.link
        if ($link -cnotmatch '^https://github\.com/adoptium/temurin21-binaries/releases/download/[^/]+/OpenJDK21U-jdk_x64_windows_hotspot_[^/]+\.zip$' -or
            [string]$package.checksum -cnotmatch '^[a-fA-F0-9]{64}$') { throw 'Java 官方下载地址或 SHA-256 不符合预期，停止。' }
        $zip = Join-Path $stage 'temurin.zip'
        Write-Host ('Java 归档来源：' + $link)
        Invoke-WebRequest -UseBasicParsing -Uri $link -OutFile $zip -TimeoutSec 600
        if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ine [string]$package.checksum) { throw 'Java 归档 SHA-256 校验失败，未安装。' }
        $expanded = Join-Path $stage 'expanded'
        Expand-JobsAndroidArchive -Archive $zip -Destination $expanded
        $roots = @(Get-ChildItem -LiteralPath $expanded -Directory)
        if ($roots.Count -ne 1 -or -not (Test-JobsAndroidJava (Join-Path $roots[0].FullName 'bin/java.exe'))) { throw '下载的 Java 目录结构或版本体检失败。' }
        $destination = Join-Path $parent ('temurin-21-' + [guid]::NewGuid().ToString('N'))
        [IO.Directory]::Move($roots[0].FullName, $destination)
        $java = Join-Path $destination 'bin/java.exe'
        if (-not (Test-JobsAndroidJava $java)) { throw ('Java 安装后复检失败，停止：' + $destination) }
        return $java
    } finally {
        [Net.ServicePointManager]::SecurityProtocol = $previousProtocol
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    }
}
function Get-JobsAndroidJava {
    param([switch]$ReadOnly)
    $candidates = @()
    if ($env:JAVA_HOME) { $candidates += Join-Path $env:JAVA_HOME 'bin/java.exe' }
    foreach ($base in @($env:ProgramFiles, $env:LOCALAPPDATA)) {
        if ($base) { $candidates += Join-Path $base 'Android/Android Studio/jbr/bin/java.exe' }
    }
    $pathJava = Find-JobsExecutable 'java.exe'
    if ($pathJava) { $candidates += $pathJava }
    $parent = Get-JobsAndroidJavaRoot
    if (Test-Path -LiteralPath $parent -PathType Container) {
        foreach ($directory in @(Get-ChildItem -LiteralPath $parent -Directory | Where-Object { $_.Name -like 'temurin-21-*' } | Sort-Object LastWriteTime -Descending)) {
            $candidates += Join-Path $directory.FullName 'bin/java.exe'
        }
    }
    foreach ($candidate in $candidates) { if (Test-JobsAndroidJava $candidate) { return $candidate } }
    if ($ReadOnly) { throw '没有健康 Java 21+；只读体检不会下载或修复。' }
    # 用户目录 ZIP 安装，不运行 MSI、不写全局 JAVA_HOME / PATH；新版本失败不循环安装。
    return Install-JobsAndroidJava
}
function Get-JobsAndroidTools {
    param([string]$Sdk, [switch]$All)
    $directory = Join-Path $Sdk 'cmdline-tools'
    $roots = @()
    if (Test-Path -LiteralPath $directory -PathType Container) {
        $roots = @(Get-ChildItem -LiteralPath $directory -Directory | Sort-Object @{ Expression = { $_.Name -eq 'latest' }; Descending = $true }, LastWriteTime -Descending)
    }
    foreach ($root in $roots) {
        if ((Test-Path -LiteralPath (Join-Path $root.FullName 'lib/sdkmanager-classpath.jar') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $root.FullName 'lib/avdmanager-classpath.jar') -PathType Leaf)) {
            if ($All) { Write-Output $root.FullName } else { return $root.FullName }
        }
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
        # 交互输出只写终端，不能混入调用方返回的 AVD 名称 / serial。
        & $Java @argumentsList | Out-Host
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
    Write-Host ($Reason + '自动补齐 Command-Line Tools。来源：https://dl.google.com/android/repository/；目标：' + $Sdk + '。SDK 条款：https://developer.android.com/studio/terms 。不覆盖已有目录。')
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
        $expanded = Join-Path $temporary 'expanded'
        Expand-JobsAndroidArchive -Archive $zip -Destination $expanded
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
    $reason = '缺少 SDK Command-Line Tools。'
    foreach ($tools in @(Get-JobsAndroidTools $Sdk -All)) {
        if ([string]::IsNullOrWhiteSpace($tools)) { continue }
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
    Write-Host $description -ForegroundColor Yellow
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
                $deadline = [DateTime]::UtcNow.AddSeconds(180)
                while ([DateTime]::UtcNow -lt $deadline) {
                    if (Test-JobsAndroidBoot $adb $serial $Name) { Write-Host ('模拟器已运行：' + $Name); return $serial }
                    Start-Sleep -Seconds 2
                }
                throw ('该 AVD 未在 180 秒内完成启动，已保留设备：' + $Name)
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
            if (Test-JobsAndroidBoot $adb ('emulator-' + $port) $Name) { Write-Host ('Android 模拟器已就绪：' + $Name) -ForegroundColor Green; return ('emulator-' + $port) }
            Start-Sleep -Seconds 2
        }
        throw ('等待启动超时；保留 AVD / 进程，请查看日志：' + $prefix + '.stderr.log')
    } finally { $process.Dispose() }
}

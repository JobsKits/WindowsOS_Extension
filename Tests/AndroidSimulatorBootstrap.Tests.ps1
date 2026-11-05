# AndroidSimulatorBootstrap.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年10月23日，星期五.
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$script:assertions = 0
function Assert-Bootstrap { param([bool]$Condition, [string]$Why) $script:assertions++; if (-not $Condition) { throw ('FAIL: ' + $Why) } }
function Assert-BootstrapThrows { param([scriptblock]$Action, [string]$Why) $threw = $false; try { & $Action | Out-Null } catch { $threw = $true }; Assert-Bootstrap $threw $Why }
$path = Join-Path $root 'JobsAndroidSimulatorCreator/Scripts/Action.psm1'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ("JobsAndroidBootstrap 中文 & 100% ' " + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$oldJavaHome = $env:JAVA_HOME; $oldAndroidHome = $env:ANDROID_HOME; $oldSdkRoot = $env:ANDROID_SDK_ROOT
$module = $null
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $payload = Join-Path $temporary 'payload'
    [void][IO.Directory]::CreateDirectory((Join-Path $payload 'jdk-21-fixture/bin'))
    [IO.File]::WriteAllText((Join-Path $payload 'jdk-21-fixture/bin/java.exe'), 'fixture executable')
    $zip = Join-Path $temporary 'java.zip'
    [IO.Compression.ZipFile]::CreateFromDirectory($payload, $zip)
    $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    $metadata = @([ordered]@{ vendor = 'eclipse'; version = @{ major = 21 }; binary = @{ architecture = 'x64'; os = 'windows'; image_type = 'jdk'; package = @{ link = 'https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21-fixture/OpenJDK21U-jdk_x64_windows_hotspot_21-fixture.zip'; checksum = $hash } } }) | ConvertTo-Json -Depth 6
    $javaRoot = Join-Path $temporary 'user-java-on-SDK-independent-volume'
    [void][IO.Directory]::CreateDirectory((Join-Path $javaRoot 'old-jdk'))
    [IO.File]::WriteAllText((Join-Path $javaRoot 'old-jdk/keep.txt'), 'existing JDK stays')
    $module = Import-Module $path -PassThru -DisableNameChecking -Force
    & $module {
        param($Parent, $Archive, $Metadata)
        $script:Parent = $Parent; $script:Archive = $Archive; $script:Metadata = $Metadata; $script:Downloads = @(); $script:JavaFails = $false; $script:CorruptDownloads = 0
        function script:Get-JobsAndroidJavaRoot { return $script:Parent }
        function script:Receive-JobsSdkWebFile {
            param($Uri, $Destination, $TimeoutSeconds)
            $OutFile = $Destination
            $script:Downloads += @{ Uri = $Uri; OutFile = $OutFile }
            if ($Uri -like 'https://api.adoptium.net/*') { [IO.File]::WriteAllText($OutFile, $script:Metadata) }
            elseif ($script:CorruptDownloads -gt 0) { $script:CorruptDownloads--; [IO.File]::WriteAllText($OutFile, 'incomplete fixture transfer') }
            else { Copy-Item -LiteralPath $script:Archive -Destination $OutFile }
        }
        function script:Start-Sleep { param($Seconds) }
        function script:Invoke-JobsProcess {
            param($FilePath, $Arguments, $TimeoutSeconds)
            if ($script:JavaFails) { return [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = 'broken Java' } }
            return [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = 'openjdk version "21.0.9" 2025-10-21 LTS' }
        }
    } $javaRoot $zip $metadata
    $java = & $module { Install-JobsAndroidJava }
    Assert-Bootstrap (Test-Path -LiteralPath $java -PathType Leaf) 'SHA-256 验证后的用户目录 Java ZIP 安装成功'
    Assert-Bootstrap ((Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $java))) -eq $javaRoot) 'Java 安装仅位于当前用户工具目录'
    $downloads = @(& $module { $script:Downloads })
    Assert-Bootstrap ($downloads.Count -eq 2 -and $downloads[0].Uri -like 'https://api.adoptium.net/v3/assets/latest/21/*') '仅查询官方 Temurin 21 元数据和选定归档'
    foreach ($download in $downloads) {
        Assert-Bootstrap ((Split-Path -Parent (Split-Path -Parent $download.OutFile)) -eq $javaRoot) 'Java 下载/解压stage与最终JDK同卷'
    }
    Assert-Bootstrap (@(Get-ChildItem -LiteralPath $javaRoot -Force | Where-Object { $_.Name -like '.jobs-stage-*' }).Count -eq 0) 'Java 成功后清理本次 stage'
    Assert-Bootstrap ([IO.File]::ReadAllText((Join-Path $javaRoot 'old-jdk/keep.txt')) -eq 'existing JDK stays') '已有 Java 完整保留'
    Assert-Bootstrap ($env:JAVA_HOME -eq $oldJavaHome) '用户目录 Java 安装不修改 JAVA_HOME'
    & $module { $script:Metadata = $script:Metadata.Replace('https://github.com/adoptium/', 'https://untrusted.example/adoptium/') }
    Assert-BootstrapThrows { & $module { Install-JobsAndroidJava } } '非官方归档地址在下载前拒绝'
    Assert-Bootstrap (Test-Path -LiteralPath $java) '失败不影响上一次健康Java'
    $verifiedArchive = Join-Path $temporary 'verified-after-corrupt-transfer.zip'
    $downloadsBefore = & $module { $script:CorruptDownloads = 1; $script:Downloads.Count }
    & $module { param($Destination, $Hash) Receive-JobsAndroidVerifiedArchive -Uri 'https://fixture.invalid/sdk.zip' -Destination $Destination -Algorithm SHA256 -Checksum $Hash } $verifiedArchive $hash
    Assert-Bootstrap ((Get-FileHash -LiteralPath $verifiedArchive -Algorithm SHA256).Hash -eq $hash) '损坏归档持续重取并校验成功'
    Assert-Bootstrap ((& $module { $script:Downloads.Count }) -eq $downloadsBefore + 2) '摘要失败仅重取归档，未重放安装'
    Assert-Bootstrap (@(Get-ChildItem -LiteralPath $javaRoot -Force | Where-Object { $_.Name -like '.jobs-stage-*' }).Count -gt 0) '失败暂存保留供排查和续传'
    & $module { param($Metadata) $script:Metadata = $Metadata; $script:JavaFails = $true } $metadata
    Assert-BootstrapThrows { & $module { Install-JobsAndroidJava } } '下载后Java仍不能运行立即停止'
    Assert-Bootstrap (@(Get-ChildItem -LiteralPath $javaRoot -Directory | Where-Object { $_.Name -like 'temurin-21-*' }).Count -eq 1) '不提交未经健康检查的新JDK目录'
    Remove-Module $module
    $module = Import-Module $path -PassThru -DisableNameChecking -Force
    & $module {
        $script:InstallCount = 0
        function script:Find-JobsExecutable { param($Name) return $null }
        function script:Get-JobsAndroidJavaRoot { return 'missing-java-root-fixture' }
        function script:Test-JobsAndroidJava { param($Path) return $false }
        function script:Install-JobsAndroidJava { $script:InstallCount++; return 'installed-java-fixture' }
    }
    Assert-BootstrapThrows { & $module { Get-JobsAndroidJava -ReadOnly } } 'Check 无健康Java时报告错误'
    Assert-Bootstrap (& $module { $script:InstallCount -eq 0 }) 'Check Java 零下载/安装'
    Assert-Bootstrap ((& $module { Get-JobsAndroidJava }) -eq 'installed-java-fixture') '运行模式缺Java自动补齐'
    Assert-Bootstrap (& $module { $script:InstallCount -eq 1 }) 'Java只补齐一次'
    Remove-Module $module
    $module = Import-Module $path -PassThru -DisableNameChecking -Force
    & $module {
        $script:JavaMajor = 8; $script:ThrowNative = $false
        function script:Invoke-JobsProcess {
            param($FilePath, $Arguments, $TimeoutSeconds)
            if ($script:ThrowNative) { throw 'fixture invalid executable' }
            return [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = ('openjdk version "' + $script:JavaMajor + '.0.1"') }
        }
    }
    Assert-Bootstrap (-not (& $module { param($Java) Test-JobsAndroidJava $Java } $java)) 'Java8退出0仍不当作健康依赖'
    & $module { $script:JavaMajor = 21 }
    Assert-Bootstrap (& $module { param($Java) Test-JobsAndroidJava $Java } $java) 'Java21解析与运行均正常才复用'
    & $module { $script:ThrowNative = $true }
    Assert-Bootstrap (-not (& $module { param($Java) Test-JobsAndroidJava $Java } $java)) '坏候选原生异常作为不健康继续检查'
    $env:ANDROID_HOME = 'relative-sdk-fixture'
    Assert-BootstrapThrows { & $module { Get-JobsAndroidSdk } } '显式相对SDK路径在任何目录创建前拒绝'
    $collision = Join-Path $temporary 'SDK-is-file'
    [IO.File]::WriteAllText($collision, 'leave file unchanged')
    $env:ANDROID_HOME = $collision
    Assert-BootstrapThrows { & $module { Get-JobsAndroidSdk } } 'SDK文件碰撞停止'
    $uncreated = Join-Path $temporary 'cancel-before-ensure-sdk'
    & $module {
        param($Sdk)
        $script:IntroSdk = $Sdk; $script:InstallCount = 0
        function script:Test-JobsAndroidDesktop { param($Target) return $true }
        function script:Get-JobsAndroidArchitecture { return 'x86_64' }
        function script:Get-JobsAndroidSdk { return $script:IntroSdk }
        function script:Read-JobsAndroidInput { param($Prompt) return 'cancel' }
        function script:Get-JobsAndroidJavaRoot { return 'user-java-fixture' }
        function script:Get-JobsAndroidJava { $script:InstallCount++; throw 'must not install' }
    } $uncreated
    Assert-BootstrapThrows { & $module { Invoke-JobsAndroidSimulatorAction desktop-fixture -Create } } '入口首屏可取消自动补齐'
    Assert-Bootstrap (-not (Test-Path -LiteralPath $uncreated)) '首屏取消不创建SDK根'
    Assert-Bootstrap (& $module { $script:InstallCount -eq 0 }) '首屏取消不进入Java和下游工具安装'
    $retrySdk = Join-Path $temporary 'sdk-retry-fixture'
    & $module {
        param($Sdk)
        $script:RetrySdk = $Sdk
        $script:SdkAttempts = 0
        function script:Start-Sleep { param($Seconds) }
        function script:Invoke-JobsSdkLiveProcess {
            param($Start, $TimeoutSeconds, [switch]$Sanitize, [switch]$Acquisition)
            if (-not $Acquisition) { throw 'SDK 获取必须启用停滞超时模式' }
            $script:SdkAttempts++
            if ($script:SdkAttempts -le 4) { return [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = 'connection reset fixture' } }
            if ($script:SdkAttempts -ge 6) {
                [void][IO.Directory]::CreateDirectory((Join-Path $script:RetrySdk 'platform-tools'))
                foreach ($name in @('package.xml', 'adb.exe')) { [IO.File]::WriteAllText((Join-Path $script:RetrySdk ('platform-tools/' + $name)), 'fixture') }
            }
            return [pscustomobject]@{ ExitCode = 0; StdOut = 'sdk fixture installed'; StdErr = '' }
        }
    } $retrySdk
    $installOutput = @(& $module { Invoke-JobsAndroidTool 'fixture-java' 'fixture-tools' sdkmanager @(('--sdk_root=' + $script:RetrySdk), '--install', 'platform-tools') -Interactive })
    Assert-Bootstrap ((& $module { $script:SdkAttempts }) -eq 6) 'SDK安装失败四次及退出0但缺文件后，自动第六次成功'
    Assert-Bootstrap ($installOutput.Count -eq 0) '安装进度不污染调用方返回值'
    $listing = & $module { Invoke-JobsAndroidTool 'fixture-java' 'fixture-tools' sdkmanager @('--list', '--channel=0') }
    Assert-Bootstrap ($listing -eq 'sdk fixture installed') 'SDK远程清单在重试后返回原始机器输出'
    foreach ($component in @(@('platform-tools','adb.exe'), @('platforms;android-35','android.jar'), @('build-tools;35.0.0','aapt2.exe'), @('ndk;27.0.1','ndk-build.cmd'), @('cmake;3.22.1','bin/cmake.exe'))) {
        $attempts = & $module {
            param($Sdk, $Identifier, $Required)
            $script:SdkAttempts = 0; $script:RetrySdk = $Sdk; $script:RetryPackage = $Identifier; $script:RetryRequired = $Required
            function script:Invoke-JobsSdkLiveProcess {
                param($Start, $TimeoutSeconds, [switch]$Sanitize, [switch]$Acquisition)
                $script:SdkAttempts++
                $directory = Join-Path $script:RetrySdk ($script:RetryPackage.Replace(';', [IO.Path]::DirectorySeparatorChar))
                [void][IO.Directory]::CreateDirectory($directory)
                [IO.File]::WriteAllText((Join-Path $directory 'package.xml'), 'fixture metadata only')
                if ($script:SdkAttempts -ge 2) {
                    $binary = Join-Path $directory $script:RetryRequired
                    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $binary))
                    [IO.File]::WriteAllText($binary, 'fixture binary')
                }
                return [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = '' }
            }
            Invoke-JobsAndroidTool 'fixture-java' 'fixture-tools' sdkmanager @(('--sdk_root=' + $Sdk), '--install', $Identifier) -Interactive
            return $script:SdkAttempts
        } (Join-Path $temporary ('metadata-only-' + $component[0].Replace(';','-'))) $component[0] $component[1]
        Assert-Bootstrap ($attempts -eq 2) ($component[0] + ' 仅元数据不算成功，关键文件就绪才结束获取')
    }
    Write-Host ('PASS: AndroidSimulatorBootstrap.Tests.ps1 (' + $script:assertions + ' assertions)')
} finally {
    if ($module) { Remove-Module $module -ErrorAction SilentlyContinue }
    $env:JAVA_HOME = $oldJavaHome; $env:ANDROID_HOME = $oldAndroidHome; $env:ANDROID_SDK_ROOT = $oldSdkRoot
    Remove-Item -LiteralPath $temporary -Recurse -Force
}

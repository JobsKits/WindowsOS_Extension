# FlutterProjectSetup.Tests.ps1 | 隔离准备、校验、取消和下载门禁
# Created by Jobs on 2026年10月28日，星期三.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$count = 0
function Assert($Value, [string]$Message) { $script:count++; if (-not $Value) { throw $Message } }
function Assert-Throws([scriptblock]$Body, [string]$Message) { $failed=$false; try { & $Body | Out-Null } catch { $failed=$true }; Assert $failed $Message }
$tempBase = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { [IO.Path]::GetTempPath() } else { '/private/tmp' }
$temp = Join-Path $tempBase ('jobs-flutter-setup-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$module = Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetup.psm1') -PassThru -DisableNameChecking
try {
    $caseName = 'Jobs_Setup_Env_' + [guid]::NewGuid().ToString('N')
    [Environment]::SetEnvironmentVariable($caseName, 'original', 'Process')
    try {
        $upperName = $caseName.ToUpperInvariant()
        $caseSnapshot = & $module { param($n) Get-JobsSetupEnvironmentSnapshot @($n) } $upperName
        Assert ($caseSnapshot[$upperName].Exists -eq ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT)) '环境键存在性按宿主大小写语义识别'
        $exactSnapshot = & $module { param($n) Get-JobsSetupEnvironmentSnapshot @($n) } $caseName
        [Environment]::SetEnvironmentVariable($caseName, 'changed', 'Process')
        & $module { param($s) Restore-JobsSetupEnvironment $s } $exactSnapshot
        Assert ([Environment]::GetEnvironmentVariable($caseName, 'Process') -ceq 'original') '快照恢复原值而不删除已存在变量'
        $absentName = $caseName + '_Absent'
        $absentSnapshot = & $module { param($n) Get-JobsSetupEnvironmentSnapshot @($n) } $absentName
        [Environment]::SetEnvironmentVariable($absentName, 'temporary', 'Process')
        & $module { param($s) Restore-JobsSetupEnvironment $s } $absentSnapshot
        Assert ($null -eq [Environment]::GetEnvironmentVariable($absentName, 'Process')) '原本未设置的变量恢复为未设置'
    } finally { [Environment]::SetEnvironmentVariable($caseName, $null, 'Process') }
    $project = Join-Path $temp '工程 with spaces'
    [void][IO.Directory]::CreateDirectory((Join-Path $project 'android/gradle/wrapper'))
    [void][IO.Directory]::CreateDirectory((Join-Path $project 'lib'))
    $props = Join-Path $project 'android/gradle/wrapper/gradle-wrapper.properties'
    [IO.File]::WriteAllText($props,"distributionUrl=https\://services.gradle.org/distributions/gradle-8.14-all.zip`n")
    [IO.File]::WriteAllText((Join-Path $project 'android/settings.gradle.kts'),'plugins { id("com.android.application") version "8.12.1" apply false }')
    $spec = & $module { param($p) Get-JobsSetupGradleSpec $p } $project
    Assert ($spec.Name -ceq 'gradle-8.14-all.zip' -and $spec.Version -eq [version]'8.14' -and $spec.Agp -ceq '8.12.1') 'Wrapper 与 Kotlin AGP 精确解析'
    foreach ($row in @(@('7.3',17),@('8.5',21),@('8.14',24),@('9.1',25))) {
        & $module { param($g,$j) Assert-JobsSetupCompatibility ([version]$g) $j $null } $row[0] $row[1]
        Assert $true ('Java 兼容边界通过：' + $row[0])
    }
    foreach ($row in @(@('7.2',17),@('8.4',21),@('9.0',11),@('8.13',24),@('9.0',25),@('9.1',28))) {
        Assert-Throws { & $module { param($g,$j) Assert-JobsSetupCompatibility ([version]$g) $j $null } $row[0] $row[1] } '不兼容/未验证 Java 阻断'
    }
    Assert-Throws { & $module { Assert-JobsSetupCompatibility ([version]'7.5') 11 '8.0' } } 'AGP8 要求 Java17'
    foreach ($url in @('http://services.gradle.org/distributions/gradle-8.14-all.zip','https://user:secret@example.com/gradle-8.14-bin.zip','https://example.com/gradle-latest-bin.zip','https://example.com/gradle-8.14-bin.zip?token=x')) {
        [IO.File]::WriteAllText($props,('distributionUrl=' + $url))
        Assert-Throws { & $module { param($p) Get-JobsSetupGradleSpec $p } $project } '拒绝不固定/明文/凭据 URL'
    }
    [IO.File]::WriteAllText($props,"distributionUrl=https://example.com/gradle-8.14-bin.zip`ndistributionSha256Sum=bad`n")
    Assert-Throws { & $module { param($p) Get-JobsSetupGradleSpec $p } $project } '拒绝坏摘要'
    [IO.File]::WriteAllText($props,"distributionUrl=https://example.com/gradle-8.14-bin.zip`ndistributionUrl=https://example.com/gradle-8.5-bin.zip`n")
    Assert-Throws { & $module { param($p) Get-JobsSetupGradleSpec $p } $project } '重复 Wrapper URL 拒绝'
    Assert (& $module { Test-JobsSetupNetworkFailure 'Could not GET Connection reset' }) '临时网络故障允许重试'
    foreach ($errorText in @('Could not GET 401 Unauthorized','Could not GET 403 Forbidden','Could not GET PKIX certificate','Could not GET Authentication failed','Compilation failed')) {
        Assert (-not (& $module { param($t) Test-JobsSetupNetworkFailure $t } $errorText)) '认证/证书/代码失败不重试'
    }
    $start = & $module { New-JobsSetupBatchStart 'cmd.exe' 'C:\SDK 百分%\flutter.bat' @('pub','get') 'C:\工程 空格' }
    Assert ($start.Arguments -ceq '/d /v:off /s /c ""%JOBS_SETUP_TOOL%" "%JOBS_SETUP_ARGUMENT_0%" "%JOBS_SETUP_ARGUMENT_1%""') 'BAT 原生双层引号保持，无 Win32 反斜杠污染'
    Assert ($start.EnvironmentVariables['JOBS_SETUP_TOOL'] -ceq 'C:\SDK 百分%\flutter.bat' -and $start.WorkingDirectory -ceq 'C:\工程 空格' -and $start.EnvironmentVariables['JOBS_SETUP_ARGUMENT_0'] -ceq 'pub') '特殊工具/工程路径不拼接进命令'
    $flutter = [pscustomobject]@{ Mode='system'; Flutter='C:\Flutter\bin\flutter.bat'; Root='C:\Flutter' }
    $java = [pscustomobject]@{ Mode='system'; Home='C:\Java17'; Major=17 }
    & $module { param($p,$f,$j) Save-JobsSetupProfile $p $f $j } $project $flutter $java
    $profile = & $module { param($p) Get-JobsSetupProfile $p } $project
    Assert ($profile.FlutterMode -ceq 'system' -and $profile.JavaMode -ceq 'system' -and $profile.Platform -ceq 'Windows') '两种系统模式可持久复用'
    & $module { param($p,$f,$j) Save-JobsSetupProfile $p $f $j } $project $flutter $java
    Assert (@(Get-ChildItem -LiteralPath (Join-Path $project '.jobs') -Filter '*.bak').Count -eq 1) '已有环境选择先备份'
    [IO.File]::WriteAllText((Join-Path $project '.jobs/flutter-environment.json'),'{"Platform":"MacOS"}')
    Assert ($null -eq (& $module { param($p) Get-JobsSetupProfile $p } $project)) '跨系统路径不复用'
    [IO.File]::WriteAllText((Join-Path $project '.jobs/flutter-environment.json'),'{"Platform":"Windows"}')
    Assert-Throws { & $module { param($p) Get-JobsSetupProfile $p } $project } '损坏选择拒绝'
    $criteria = Join-Path $project 'android/gradle/gradle-daemon-jvm.properties'
    [IO.File]::WriteAllText($criteria,'toolchainVersion=21')
    Assert-Throws { & $module { param($p,$j) Set-JobsSetupJavaProcess $p $j } $project $java } 'daemon JVM criteria 明确阻断'
    [IO.File]::Delete($criteria)
    Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
    $badZip = Join-Path $temp 'bad.zip'
    $archive = [IO.Compression.ZipFile]::Open($badZip,[IO.Compression.ZipArchiveMode]::Create)
    [void]$archive.CreateEntry('../escape.txt'); $archive.Dispose()
    Assert-Throws { & $module { param($z,$d) Expand-JobsSetupZip $z $d } $badZip (Join-Path $temp 'expanded') } 'ZIP 路径穿越拒绝'
    Assert (-not [IO.File]::Exists((Join-Path $temp 'escape.txt'))) '拒绝后无越界产物'
    # 官方 API 的顶层数组含同版本其它系统；只允许匹配的 Windows 归档进入校验和复检。
    $jdkFixtureRoot = Join-Path $temp 'temurin-selection'
    [void][IO.Directory]::CreateDirectory($jdkFixtureRoot)
    $jdkFixtureZip = Join-Path $jdkFixtureRoot 'fixture.zip'
    $jdkFixtureBytes = [byte[]]@(10, 20, 30, 40, 50)
    [IO.File]::WriteAllBytes($jdkFixtureZip, $jdkFixtureBytes)
    $jdkFixtureHash = (Get-FileHash -LiteralPath $jdkFixtureZip -Algorithm SHA256).Hash
    $jdkArchitecture = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { 'aarch64' } else { 'x64' }
    $jdkWindowsUrl = 'https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17-fixture/windows-jdk.zip'
    $jdkLinuxUrl = 'https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17-fixture/linux-jdk.zip'
    $jdkMetadata = ConvertTo-Json -Depth 8 -InputObject @(
        @{ version = @{ major = 17 }; binary = @{ os = 'linux'; architecture = $jdkArchitecture; image_type = 'jdk'; package = @{ link = $jdkLinuxUrl; checksum = $jdkFixtureHash } } },
        @{ version = @{ major = 17 }; binary = @{ os = 'windows'; architecture = $jdkArchitecture; image_type = 'jdk'; package = @{ link = $jdkWindowsUrl; checksum = $jdkFixtureHash } } }
    )
    $jdkOriginalFunctions = & $module {
        @{
            'Get-JobsInstallRoot' = ${function:Get-JobsInstallRoot}
            'Select-JobsSetupChoice' = ${function:Select-JobsSetupChoice}
            'Receive-JobsSetupFile' = ${function:Receive-JobsSetupFile}
            'Expand-JobsSetupZip' = ${function:Expand-JobsSetupZip}
            'Get-JobsSetupJava' = ${function:Get-JobsSetupJava}
        }
    }
    try {
        & $module {
            param($Root, $Metadata, $Archive, $WindowsUrl)
            $script:jdkFixtureRoot = $Root; $script:jdkFixtureMetadata = $Metadata
            $script:jdkFixtureArchive = $Archive; $script:jdkFixtureWindowsUrl = $WindowsUrl
            $script:jdkFixtureRequests = New-Object 'System.Collections.Generic.List[string]'
            $script:jdkFixtureExpansions = 0; $script:jdkFixtureProbes = 0
            function script:Get-JobsInstallRoot { $script:jdkFixtureRoot }
            function script:Select-JobsSetupChoice { param($Fzf, $Title, $Choices, [switch]$Back) '17' }
            function script:Receive-JobsSetupFile {
                param([string[]]$Urls, [string]$Destination, [int]$TimeoutSeconds)
                if ($Urls.Count -ne 1) { throw 'JDK 夹具不接受混合下载地址。' }
                $script:jdkFixtureRequests.Add($Urls[0])
                if ([IO.Path]::GetFileName($Destination) -ceq 'temurin.json') {
                    [IO.File]::WriteAllText($Destination, $script:jdkFixtureMetadata, (New-Object Text.UTF8Encoding($false)))
                } elseif ($Urls[0] -ceq $script:jdkFixtureWindowsUrl) {
                    [IO.File]::Copy($script:jdkFixtureArchive, $Destination)
                } else { throw ('不应下载其它系统的 JDK：' + $Urls[0]) }
                return $Urls[0]
            }
            function script:Expand-JobsSetupZip {
                param($Zip, $Destination)
                $script:jdkFixtureExpansions++
                [void][IO.Directory]::CreateDirectory((Join-Path $Destination 'jdk-17-fixture/bin'))
                [IO.File]::WriteAllText((Join-Path $Destination 'jdk-17-fixture/bin/java.exe'), 'fixture, never executed')
                [IO.File]::WriteAllText((Join-Path $Destination 'jdk-17-fixture/bin/javac.exe'), 'fixture, never executed')
            }
            function script:Get-JobsSetupJava {
                param($JavaHome, $Project)
                $script:jdkFixtureProbes++
                if (-not [IO.File]::Exists((Join-Path $JavaHome 'bin/java.exe')) -or -not [IO.File]::Exists((Join-Path $JavaHome 'bin/javac.exe'))) { throw 'JDK 夹具缺少完整工具。' }
                [pscustomobject]@{ Home = $JavaHome; Major = 17 }
            }
        } $jdkFixtureRoot $jdkMetadata $jdkFixtureZip $jdkWindowsUrl
        $jdkHome = & $module { param($p) Install-JobsSetupJava $p 'fixture-fzf' } $project
        $jdkRequests = @(& $module { $script:jdkFixtureRequests.ToArray() })
        Assert ($jdkRequests.Count -eq 2 -and $jdkRequests[0] -ceq ('https://api.adoptium.net/v3/assets/latest/17/hotspot?architecture=' + $jdkArchitecture + '&image_type=jdk&os=windows&vendor=eclipse')) 'JDK 元数据请求保留本人所选主版、Windows 和宿主架构'
        Assert ($jdkRequests[1] -ceq $jdkWindowsUrl -and $jdkRequests -cnotcontains $jdkLinuxUrl) '同版本 Linux 项不混入 Windows 下载地址'
        Assert ((& $module { $script:jdkFixtureExpansions -eq 1 -and $script:jdkFixtureProbes -eq 1 }) -and [IO.File]::Exists((Join-Path $jdkHome 'bin/javac.exe'))) '真实归档字节通过 SHA256 后才解压，并复检完整 JDK'
        Assert ((Get-FileHash -LiteralPath (Join-Path (Split-Path -Parent (Split-Path -Parent $jdkHome)) 'jdk.zip') -Algorithm SHA256).Hash -ceq $jdkFixtureHash) '所选 Windows 归档落盘字节与官方摘要匹配'
    } finally {
        & $module {
            param($OriginalFunctions)
            foreach ($name in $OriginalFunctions.Keys) { Set-Item -LiteralPath ('Function:script:' + $name) -Value $OriginalFunctions[$name] }
            Remove-Variable -Scope Script -Name jdkFixtureRoot,jdkFixtureMetadata,jdkFixtureArchive,jdkFixtureWindowsUrl,jdkFixtureRequests,jdkFixtureExpansions,jdkFixtureProbes -ErrorAction SilentlyContinue
        } $jdkOriginalFunctions
    }
    $init = & $module { param($d) New-JobsSetupMirrorInit $d } $temp
    Assert ([IO.File]::ReadAllText($init).Contains('beforeSettings') -and [IO.File]::ReadAllText($init).Contains('maven.aliyun.com')) '可选插件镜像仅产生本次 init script'
    $hash = & $module { Get-JobsSetupWrapperHash 'https://services.gradle.org/distributions/gradle-8.14-all.zip' }
    Assert ($hash -ceq 'c2qonpi39x1mddn7hk5gh9iqj') 'Gradle PathAssembler MD5 unsigned base36 兼容固定向量'
    $savedUserHome = [Environment]::GetEnvironmentVariable('GRADLE_USER_HOME','Process')
    $env:GRADLE_USER_HOME = Join-Path $temp 'gradle-user-home'
    try {
        [IO.File]::WriteAllText($props,"distributionUrl=https://services.gradle.org/distributions/gradle-8.14-all.zip`n")
        $spec = & $module { param($p) Get-JobsSetupGradleSpec $p } $project
        $zipPath = & $module { param($p,$s) Get-JobsSetupWrapperZip $p $s } $project $spec
        Assert ($zipPath -ceq (Join-Path $env:GRADLE_USER_HOME 'wrapper/dists/gradle-8.14-all/c2qonpi39x1mddn7hk5gh9iqj/gradle-8.14-all.zip')) '标准 Wrapper zipStore 与原 URL hash 缓存定位'
        $archive = Join-Path $temp 'verified-dist.zip'
        [IO.File]::WriteAllText($archive,'fake-gradle-distribution')
        $checksum = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
        & $module { param($p,$s,$z,$h) Publish-JobsSetupWrapperZip $p $s $z $h } $project $spec $archive $checksum
        Assert ((Get-FileHash -LiteralPath $zipPath).Hash -ceq $checksum) '已验 ZIP 复制到后续 flutter build 真正使用的 Wrapper 缓存'
        Assert (-not [IO.File]::Exists($zipPath + '.ok')) '不伪造 Wrapper 完成标记'
        $lock = New-Object IO.FileStream (($zipPath + '.lck'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        try { Assert-Throws { & $module { param($p,$s,$z,$h) Publish-JobsSetupWrapperZip $p $s $z $h } $project $spec $archive $checksum } '并行 Wrapper 锁阻止覆盖缓存' } finally { $lock.Dispose() }
        $spec.Properties += "zipStoreBase=PROJECT`nzipStorePath=custom/zips`ndistributionBase=PROJECT`ndistributionPath=custom/dists`n"
        $path = & $module { param($p,$s) Get-JobsSetupWrapperZip $p $s } $project $spec
        Assert ($path.StartsWith((Join-Path $project 'android/custom/zips/'))) 'PROJECT zipStore 以 android 为根'
        $spec.Properties += "zipStorePath=../escape`n"
        Assert-Throws { & $module { param($p,$s) Get-JobsSetupWrapperZip $p $s } $project $spec } '重复或越界 Wrapper 缓存路径拒绝'
        [IO.File]::WriteAllText($props,"distributionUrl=https://services.gradle.org/distributions/gradle-8.14-all.zip`ndistributionSha256Sum=$checksum`n")
        [IO.File]::WriteAllText((Join-Path $project 'android/gradlew.bat'),'fixture')
        [IO.File]::WriteAllText((Join-Path $project 'android/gradle/wrapper/gradle-wrapper.jar'),'fixture')
        & $module {
            param($base,$archive)
            $script:fakeRoot=$base; $script:fakeArchive=$archive; $script:downloads=0
            function script:Get-JobsInstallRoot { $script:fakeRoot }
            function script:Select-JobsSetupChoice { param($f,$t,$c) $c[0] }
            function script:Receive-JobsSetupFile {
                param([string[]]$Urls,[string]$Destination,[int]$TimeoutSeconds)
                $script:downloadUrls=$Urls; $script:downloads++
                Copy-Item -LiteralPath $script:fakeArchive -Destination $Destination
                $Urls[0]
            }
            function script:Invoke-JobsSetupProcess { param($f,$a,$d,$t) [pscustomobject]@{ExitCode=0;StdOut="Gradle 8.14`n";StdErr=''} }
        } $temp $archive
        $selectedGradle = & $module { param($p) Install-JobsSetupGradle $p ([pscustomobject]@{Major=17}) 'fake-fzf' } $project
        Assert ($selectedGradle -ceq (Join-Path $project 'android/gradlew.bat')) '最终执行工程 Wrapper，不依赖临时私有分发'
        Assert ((& $module { @($script:downloadUrls).Count }) -eq 2) '官方 URL 与官方备用是独立数组项，避免 PowerShell +/逗号优先级拼接'
        Assert ((& $module { $script:downloads }) -eq 1) '首次请求一次下载，SHA通过才发布'
        & $module { param($p) Install-JobsSetupGradle $p ([pscustomobject]@{Major=17}) 'fake-fzf' } $project | Out-Null
        Assert ((& $module { $script:downloads }) -eq 1) '重复准备复用已验归档'
        [IO.File]::WriteAllText((Join-Path $temp 'toolchains/gradle/gradle-8.14-all/gradle-8.14-all.zip'),'bad')
        & $module { function script:Receive-JobsSetupFile { param([string[]]$Urls,[string]$Destination,[int]$TimeoutSeconds) [IO.File]::WriteAllText($Destination,'still-bad'); $Urls[0] } }
        Assert-Throws { & $module { param($p) Install-JobsSetupGradle $p ([pscustomobject]@{Major=17}) 'fake-fzf' } $project } '错误摘要下载不执行 Wrapper'
    } finally {
        if ($null -eq $savedUserHome) { Remove-Item Env:GRADLE_USER_HOME -ErrorAction SilentlyContinue } else { $env:GRADLE_USER_HOME=$savedUserHome }
    }
    # 只替换模块内外部边界，验证全流程顺序、收尾和环境恢复。
    & $module {
        param($base)
        $script:events = New-Object 'System.Collections.Generic.List[string]'
        $script:fakeRoot = $base
        function script:Test-JobsSetupInteractive { $true }
        function script:Read-Host { param($Prompt) '' }
        function script:Get-JobsInstallRoot { $script:fakeRoot }
        function script:Select-JobsSetupPlatform { param($p,$f) 'Android' }
        function script:Initialize-JobsSetupPlatform { param($p,$f,$j,$z,$t) }
        function script:Invoke-JobsSetupRunVerification { param($p,$f,$z,$t) }
        function script:Get-JobsSetupFzf { param($p) 'fake-fzf' }
        function script:Select-JobsSetupFlutter { param($p,$f) $script:events.Add('flutter'); [pscustomobject]@{Mode='fvm';Flutter='fixture';Root='fixture'} }
        function script:Select-JobsSetupJava { param($p,$f) $script:events.Add('java'); [pscustomobject]@{Mode='jenv';Home='fixture';Major=17} }
        function script:Set-JobsSetupJavaProcess { param($p,$j) $script:events.Add('bind-java'); $env:JAVA_HOME='changed-for-test';$env:GRADLE_OPTS='changed-for-test' }
        function script:Install-JobsSetupGradle { param($p,$j,$f) $script:events.Add('gradle'); 'fake-gradle' }
        function script:Save-JobsSetupProfile { param($p,$f,$j) $script:events.Add('profile') }
        function script:Invoke-JobsSetupDependencies { param($p,$f,$g) $script:events.Add('pub-and-plugins'); if ($script:failDependencies) { throw 'fixture-pub-failed' } }
        function script:Invoke-JobsSetupTargetDependencies { param($p,$f,$j,$z,$t,$g) $script:events.Add('target-dependencies'); return ,@('build','apk','--debug','--target','lib/main.dart') }
        function script:Get-JobsSetupReadiness { param($p,$f) $script:events.Add('readiness'); [pscustomobject]@{Ready=$true} }
        $script:failDependencies=$false
    } $temp
    [IO.File]::WriteAllText((Join-Path $project 'pubspec.yaml'),"name: fixture`ndependencies:`n  flutter:`n    sdk: flutter`n")
    $savedJava=[Environment]::GetEnvironmentVariable('JAVA_HOME','Process'); $savedOpts=[Environment]::GetEnvironmentVariable('GRADLE_OPTS','Process')
    & $module { param($p) Invoke-JobsProjectSetupAction -Target $p -Action project-setup } $project
    $events = & $module { $script:events -join ',' }
    Assert ($events -ceq 'flutter,java,bind-java,gradle,profile,pub-and-plugins,target-dependencies,readiness') '完整流程先选择 SDK 与 JVM，再固定分发、pub/插件、只读运行检查'
    Assert ([Environment]::GetEnvironmentVariable('JAVA_HOME','Process') -ceq $savedJava -and [Environment]::GetEnvironmentVariable('GRADLE_OPTS','Process') -ceq $savedOpts) '成功后进程环境精确恢复'
    & $module { $script:events.Clear(); $script:failDependencies=$true }
    Assert-Throws { & $module { param($p) Invoke-JobsProjectSetupAction -Target $p -Action project-setup } $project } '依赖失败传播'
    Assert ((& $module { $script:events -join ',' }) -notmatch 'readiness') '依赖失败不继续运行检查/报成功'
    Assert ([Environment]::GetEnvironmentVariable('JAVA_HOME','Process') -ceq $savedJava -and [Environment]::GetEnvironmentVariable('GRADLE_OPTS','Process') -ceq $savedOpts) '失败后环境精确恢复'
    & $module { function script:Read-Host { param($Prompt) 'cancel' }; $script:events.Clear() }
    Assert-Throws { & $module { param($p) Invoke-JobsProjectSetupAction -Target $p -Action project-setup } $project } '初始取消阻断'
    Assert ((& $module { $script:events.Count }) -eq 0) '取消不进入 SDK/下载/写配置'
    Write-Host ('PASS: FlutterProjectSetup.Tests.ps1 (' + $count + ' assertions; no SDK installation, network, registry, or real project writes)')
} finally {
    Remove-Module $module
    Remove-Item -LiteralPath $temp -Recurse -Force
}

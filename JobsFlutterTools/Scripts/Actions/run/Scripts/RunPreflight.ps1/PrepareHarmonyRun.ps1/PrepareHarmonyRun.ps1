# PrepareHarmonyRun.ps1 | JobsFlutterRunner
# Created by Jobs on 2026年11月10日，星期二.
# 当前运行流程准备所选鸿蒙设备；下载可重试，项目发布与业务命令不整体重放。

# 单独加载准备库时保留原生输出，运行器内复用统一展示层。
function Write-JobsPrepareDisplay {
    param([Parameter(Position=0)]$Object,[ConsoleColor]$ForegroundColor)
    if(Get-Command Write-JobsRunnerDisplayText -CommandType Function -ErrorAction SilentlyContinue){Write-JobsRunnerDisplayText @PSBoundParameters}
    else{Write-Host @PSBoundParameters}
}

function Get-JobsPrepareEnvironmentSnapshot {
    return Get-JobsRunnerTaskEnvironmentSnapshot @('PATH','JAVA_HOME','FLUTTER_ROOT','TOOL_HOME','DEVECO_STUDIO_HOME','DEVECO_SDK_HOME','OHOS_SDK_HOME','FVM_CACHE_PATH','FVM_FLUTTER_URL','FVM_USE_GIT_CACHE')
}

function Restore-JobsPrepareEnvironment {
    param([hashtable]$Snapshot)
    Restore-JobsRunnerTaskEnvironment $Snapshot
}

function Import-JobsPrepareCore {
    $base = Join-Path $PSScriptRoot 'Core'
    return [pscustomobject]@{
        Harmony=(Import-Module (Join-Path $base 'HarmonySdk.psm1') -PassThru -DisableNameChecking)
        Tools=(Import-Module (Join-Path $base 'HarmonyToolsCore.psm1') -PassThru -DisableNameChecking)
    }
}

# SDK 自举沿用原运行器；其它准备命令使用同仓库的 BAT 参数占位与双流处理。
function Invoke-JobsPrepareProcess {
    param([string]$File,[string[]]$Arguments,[string]$Directory,[int]$TimeoutSeconds=900)
    if ($File -match '["\x00-\x1f]' -or @($Arguments | Where-Object { $_ -match '["\x00-\x1f]' }).Count) { throw '环境准备工具参数包含不支持的字符。' }
    if ([IO.Path]::GetExtension($File) -in @('.bat','.cmd')) {
        $start = & $script:JobsPrepareCore.Tools { param($File,$Arguments,$Directory) New-JobsSetupBatchStart (Join-Path ([Environment]::GetFolderPath('System')) 'cmd.exe') $File $Arguments $Directory } $File $Arguments $Directory
    } else {
        $start=New-Object Diagnostics.ProcessStartInfo
        $start.FileName=$File; $start.Arguments=(@($Arguments | ForEach-Object {Quote-JobsArgument $_})-join' '); $start.WorkingDirectory=$Directory
    }
    $result=Invoke-JobsSdkLiveProcess $start $TimeoutSeconds -Sanitize
    if ($result.ExitCode -ne 0) { throw ('鸿蒙环境准备命令失败，退出码 '+$result.ExitCode+'；保留工具原始输出与已完成的准备结果。') }
    return $result
}

function Test-JobsPrepareCompatibility {
    param([string]$Flutter,[string]$Project,[string]$Framework,[string]$DartVersion='',[string]$Mode='sdk')
    $sdk=Split-Path -Parent (Split-Path -Parent $Flutter)
    $dart=Join-Path $sdk 'bin/cache/dart-sdk/bin/dart.exe'
    $packages=Join-Path $sdk 'packages/flutter_tools/.dart_tool/package_config.json'
    if (-not [IO.File]::Exists($dart) -or -not [IO.File]::Exists($packages)) { throw '当前 SDK 缺少约束解析所需的同源 Dart / 包索引，未选择不明版本。' }
    $output=Invoke-JobsRunnerReadOnlyTool $dart @('--disable-dart-dev',('--packages='+$packages),(Join-Path $PSScriptRoot 'SdkCompatibility.dart'),$Project,$Mode,$Framework,$DartVersion) $Project 30 -AllowedExitCodes @(0,1)
    $result=$output|ConvertFrom-Json -ErrorAction Stop
    if ($result.schemaVersion-ne1-or$result.compatible-isnot[bool]) { throw 'SDK 兼容性检查未返回有效结果。' }
    return $result
}

function Initialize-JobsPrepareSdk {
    param([string]$Flutter,[string]$Project,[switch]$RefreshCompatible)
    $version=ConvertFrom-JobsSdkMachineOutput (Invoke-JobsRunnerTool $Flutter @('--version','--machine') $Project)
    $compat=Test-JobsPrepareCompatibility $Flutter $Project $version.frameworkVersion $version.dartSdkVersion
    $help=Invoke-JobsRunnerReadOnlyTool (Join-Path (Split-Path -Parent (Split-Path -Parent $Flutter)) 'bin/cache/dart-sdk/bin/dart.exe') @((Join-Path (Split-Path -Parent (Split-Path -Parent $Flutter)) 'bin/cache/flutter_tools.snapshot'),'--no-version-check','--suppress-analytics','build','-h') $Project 30
    if (-not$RefreshCompatible-and$compat.compatible-and$help-match'(?m)^\s*hap\s') { return [pscustomobject]@{Flutter=$Flutter;ProjectName=$compat.projectName} }
    $module=$script:JobsPrepareCore.Harmony
    $git=Find-JobsExecutable 'git.exe' @('git')
    if (-not $git) { throw '当前环境缺少 Git，无法验证正式 SDK 来源；本轮停止，未切换全局 SDK。' }
    return & $module {
        param($Git,$CurrentFlutter,$Project,$Compatibility,$CurrentReady,$CurrentRevision,$Display)
        Assert-JobsHarmonyBindingPaths $Project
        $cache=Get-JobsHarmonyCache
        $root=&$script:HarmonyManager {Get-JobsInstallRoot}
        [void][IO.Directory]::CreateDirectory($root)
        $lock=$null
        try {
            try {$lock=[IO.File]::Open((Join-Path $root 'operation.lock'),'OpenOrCreate','ReadWrite','None')}catch{throw '另一项目 SDK 操作仍在进行，未并发写入缓存或项目。'}
            $stamp=Get-JobsHarmonyBindingStamp $Project
            $tags=Invoke-JobsHarmonyGit $Git @('ls-remote','--tags',$script:HarmonyRepository) $Project
            $choices=@(Get-JobsHarmonyTagChoices $tags|Where-Object{-not$_.Prerelease})
            foreach($choice in $choices){
                $base=&$Compatibility $CurrentFlutter $Project ([string]$choice.BaseVersion) '' 'flutter'
                if(-not$base.compatible){continue}
                $refs=Invoke-JobsHarmonyGit $Git @('ls-remote',$script:HarmonyRepository,('refs/tags/'+$choice.Ref),('refs/tags/'+$choice.Ref+'^{}'),('refs/heads/'+$choice.Ref)) $Project
                if((Resolve-JobsHarmonyCommit $refs $choice.Ref)-cne$choice.Commit){throw '正式 tag 在准备期间变化，未发布 SDK。'}
                & $Display ('自动选择兼容正式候选：'+$choice.Ref+'；来源：'+$script:HarmonyRepository+'；commit：'+$choice.Commit)
                & $Display '目标 Dart 将在对应 engine 自举后核验；此时尚不宣称版本兼容。'
                if($CurrentReady-and$choice.Commit-ceq$CurrentRevision){return [pscustomobject]@{Flutter=$CurrentFlutter;ProjectName=$base.projectName}}
                $sdk=Install-JobsHarmonySdk $Git $choice $cache $Project
                $candidate=Join-Path $sdk 'bin/flutter.bat'
                # 在调用方作用域执行可见 SDK 自举，不重放项目发布或业务构建。
                $actual=&$Compatibility $candidate $Project '' '' 'bootstrap'
                if($actual.frameworkRevision-cne$choice.Commit){throw 'SDK 实际版本提交与锁定 tag 不一致，未发布项目绑定。'}
                $ok=&$Compatibility $CurrentFlutter $Project $actual.frameworkVersion $actual.dartSdkVersion 'sdk'
                if(-not$ok.compatible){& $Display ('候选与工程约束不符，缓存保留：'+$ok.reason);continue}
                Assert-JobsHarmonySdk $Git $sdk $choice.Commit $Project
                $config=&$script:HarmonyManager {param($Path)Get-JobsProjectFvmConfig $Path} $Project
                foreach($pair in @(@('flutter',$choice.Version),@('cachePath',$cache),@('flutterUrl',$script:HarmonyRepository),@('updateMelosSettings',$false),@('useGitCache',$false))){$config|Add-Member -NotePropertyName $pair[0] -NotePropertyValue $pair[1] -Force}
                Publish-JobsHarmonyBinding $Project $sdk (($config|ConvertTo-Json -Depth 100)+[Environment]::NewLine) $stamp
                return [pscustomobject]@{Flutter=$candidate;ProjectName=$ok.projectName}
            }
            throw '没有满足工程 Flutter / Dart 约束的正式鸿蒙 SDK；未绑定预览版或修改全局版本。'
        }finally{if($lock){$lock.Dispose()}}
    } $git $Flutter $Project ${function:Invoke-JobsPrepareCompatibilityBridge} ($compat.compatible-and$help-match'(?m)^\s*hap\s') $version.frameworkRevision ${function:Write-JobsPrepareDisplay}
}

function Invoke-JobsPrepareCompatibilityBridge {
    param($Flutter,$Project,$Framework,$DartVersion,$Mode)
    if($Mode-ceq'bootstrap'){
        $actual=ConvertFrom-JobsSdkMachineOutput (Invoke-JobsRunnerTool $Flutter @('--version','--machine') $Project)
        $help=Invoke-JobsRunnerTool $Flutter @('build','hap','--help') $Project 60
        if($help-notmatch'\bhap\b'){throw '候选 SDK 没有 HAP 构建能力。'}
        return $actual
    }
    return Test-JobsPrepareCompatibility $Flutter $Project $Framework $DartVersion $Mode
}

function New-JobsPrepareOhosPlatform {
    param([string]$Flutter,[string]$Project,[string]$Name)
    $target=Join-Path $Project 'ohos'
    if(Test-Path -LiteralPath $target){
        $item=Get-Item -LiteralPath $target -Force
        if(-not$item.PSIsContainer-or($item.Attributes-band[IO.FileAttributes]::ReparsePoint)){throw '现有 ohos 不是普通目录，保留原对象并停止。'}
        return
    }
    if($Name-cnotmatch'^[a-z_][a-z0-9_]*$'){throw '工程包名不是合法 Flutter 项目名，未猜测替代名称。'}
    $stage=Join-Path $Project ('.jobs-harmony-stage-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($stage)
    try{
        [void](Invoke-JobsPrepareProcess $Flutter @('create','--platforms=ohos','--no-pub','--project-name',$Name,'.') $stage 300)
        foreach($file in @('build-profile.json5','oh-package.json5','AppScope/app.json5')){if(-not[IO.File]::Exists((Join-Path $stage ('ohos/'+$file)))){throw '临时生成结果缺少鸿蒙清单，未发布目录。'}}
        if(Test-Path -LiteralPath $target){throw '准备期间已有 ohos 出现，未覆盖并发变更。'}
        [IO.Directory]::Move((Join-Path $stage 'ohos'),$target)
        [IO.Directory]::Delete($stage,$true)
    }catch{Write-JobsPrepareDisplay ('鸿蒙生成现场保留：'+$stage);throw}
}

function Install-JobsPrepareJava17 {
    param([string]$Project)
    $root=Join-Path $env:LOCALAPPDATA 'Jobs/HarmonySimulator/java'
    [void][IO.Directory]::CreateDirectory($root)
    $stage=Join-Path $root ('temurin17-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($stage)
    $metadata=Join-Path $stage 'assets.json'
    $url='https://api.adoptium.net/v3/assets/latest/17/hotspot?architecture=x64&image_type=jdk&os=windows&vendor=eclipse'
    Write-JobsPrepareDisplay ('当前流程获取 JDK 17；来源：'+$url+'；安装到独立用户缓存，不改全局 Java。')
    Receive-JobsSdkWebFile $url $metadata 60
    $assets=Get-Content -LiteralPath $metadata -Raw -Encoding UTF8|ConvertFrom-Json
    $selected=@($assets|Where-Object{$_.version.major-eq17-and$_.binary.os-ceq'windows'-and$_.binary.architecture-ceq'x64'-and$_.binary.image_type-ceq'jdk'})
    if($selected.Count-ne1){throw '官方接口未返回唯一 Windows x64 JDK 17。'}
    $package=$selected[0].binary.package
    if($package.link-cnotmatch'^https://github\.com/adoptium/temurin17-binaries/releases/download/'-or$package.checksum-cnotmatch'^[a-fA-F0-9]{64}$'){throw 'JDK 官方来源或摘要无效，未安装。'}
    $zip=Join-Path $stage 'jdk.zip'
    Receive-JobsSdkWebFile ([string]$package.link) $zip 1200 -ExpectedSha256 ([string]$package.checksum)
    if((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash-ine$package.checksum){throw 'JDK 归档摘要不符，现场保留。'}
    &$script:JobsPrepareCore.Tools {param($Zip,$Target)Expand-JobsSetupZip $Zip $Target} $zip (Join-Path $stage 'sdk')
    $roots=@(Get-ChildItem -LiteralPath (Join-Path $stage 'sdk') -Directory)
    if($roots.Count-ne1){throw 'JDK 解压根不唯一，现场保留。'}
    return $roots[0].FullName
}

function Initialize-JobsPrepareTools {
    param([string]$Project)
    $root=$null
    try{$root=Get-JobsRunnerHarmonyRoot}catch{}
    $emulator=$null
    if(-not(Test-JobsPrepareToolFiles $root)){
        if($root){Write-JobsPrepareDisplay '现有鸿蒙工具缺少组件；保留原安装，自动获取完整 CLT 到独立用户缓存。'}
        $emulator=&$script:JobsPrepareCore.Tools {Install-JobsHarmonyTools}
        $root=Split-Path -Parent (Split-Path -Parent $emulator)
    }
    if(-not$emulator){foreach($relative in @('emulator/Emulator.exe','tools/emulator/Emulator.exe')){$path=Join-Path $root $relative;if([IO.File]::Exists($path)){$emulator=$path;break}}}
    if($emulator){&$script:JobsPrepareCore.Tools {param($Tool)Confirm-JobsHarmonyLicenses $Tool} $emulator}
    $sdk=Join-Path $root 'sdk'
    $ohos=Join-Path $sdk 'default/openharmony'
    foreach($part in @('ets','native','toolchains')){if(-not[IO.Directory]::Exists((Join-Path $ohos $part))){throw ('CLT 缺少 '+$part+'；未进入应用运行。')}}
    $paths=@($root)
    foreach($relative in @('node','node/bin','tools/node','tools/node/bin','ohpm/bin','tools/ohpm/bin','hvigor/bin','tools/hvigor/bin','sdk/default/openharmony/toolchains')){$paths+=Join-Path $root $relative}
    $env:PATH=(@($paths|Where-Object{[IO.Directory]::Exists($_)})+@($env:PATH))-join[IO.Path]::PathSeparator
    $env:TOOL_HOME=$root;$env:DEVECO_STUDIO_HOME=$root;$env:DEVECO_SDK_HOME=$sdk;$env:OHOS_SDK_HOME=$ohos
    $java=$null
    $candidates=@($env:JAVA_HOME,(Join-Path $root 'jbr'),(Join-Path $root 'jre'))
    $cache=Join-Path $env:LOCALAPPDATA 'Jobs/HarmonySimulator/java'
    if([IO.Directory]::Exists($cache)){foreach($directory in Get-ChildItem -LiteralPath $cache -Directory){$nested=Join-Path $directory.FullName 'sdk';if([IO.Directory]::Exists($nested)){$candidates+=@(Get-ChildItem -LiteralPath $nested -Directory|ForEach-Object{$_.FullName})}}}
    foreach($candidate in $candidates){if(-not$candidate){continue};try{
        $runtime=Invoke-JobsRunnerReadOnlyTool (Join-Path $candidate 'bin/java.exe') @('-version') $Project 30
        $compiler=Invoke-JobsRunnerReadOnlyTool (Join-Path $candidate 'bin/javac.exe') @('-version') $Project 30
        if($runtime-match'version "17(?:\.|\")'-and$compiler-match'javac 17(?:\.|$)'){$java=$candidate;break}
    }catch [Management.Automation.PipelineStoppedException] {throw}
    catch [OperationCanceledException] {throw}
    catch {if($_.Exception.Message-match'(?i)取消|cancel|退出码\s*(?:130|143|-1073741510)'){throw}}}
    if(-not$java){$java=Install-JobsPrepareJava17 $Project}
    $runtime=Invoke-JobsRunnerReadOnlyTool (Join-Path $java 'bin/java.exe') @('-version') $Project 30
    $compiler=Invoke-JobsRunnerReadOnlyTool (Join-Path $java 'bin/javac.exe') @('-version') $Project 30
    if($runtime-notmatch'version "17(?:\.|\")'-or$compiler-notmatch'javac 17(?:\.|$)'){throw 'JDK 获取后运行时或编译器仍不是 17，未继续依赖解析。'}
    $env:JAVA_HOME=$java;$env:PATH=(Join-Path $java 'bin')+[IO.Path]::PathSeparator+$env:PATH
    foreach($tool in @('node.exe','ohpm.bat','hdc.exe','java.exe','javac.exe')){if(-not(Find-JobsExecutable $tool)){throw ('工具获取后缺少 '+$tool+'；本轮未运行应用。')}}
    return [pscustomobject]@{Root=$root;Ohpm=(Find-JobsExecutable 'ohpm.bat')}
}

function Test-JobsPrepareToolFiles {
    param([string]$Root)
    if(-not$Root-or-not[IO.Directory]::Exists($Root)){return $false}
    foreach($part in @('ets','native','toolchains')){if(-not[IO.Directory]::Exists((Join-Path $Root ('sdk/default/openharmony/'+$part)))){return $false}}
    foreach($tool in @(@('node/node.exe','node/bin/node.exe','tools/node/node.exe','tools/node/bin/node.exe'),@('ohpm/bin/ohpm.bat','tools/ohpm/bin/ohpm.bat'),@('sdk/default/openharmony/toolchains/hdc.exe'))){
        if(@($tool|Where-Object{[IO.File]::Exists((Join-Path $Root $_))}).Count-eq0){return $false}
    }
    return $true
}

function Get-JobsPrepareOriginalIdentity {
    param([string]$DiagnosticKey,[switch]$AllowUnknown)
    if([string]::IsNullOrWhiteSpace($DiagnosticKey)-or$DiagnosticKey-match'[\x00-\x1f]'){throw '原设备诊断标识无效。'}
    if($DiagnosticKey-notmatch'(?i)^USB\\'){return $DiagnosticKey}
    $current=$DiagnosticKey
    for($step=0;$step-lt5;$step++){
        $serial=($current-split'\\')[-1]
        if($current-match'(?i)^USB\\'-and$serial-cmatch'^[A-Za-z0-9][A-Za-z0-9_.-]*$'){return $serial}
        if(-not(Get-Command Get-PnpDeviceProperty -ErrorAction SilentlyContinue)){break}
        try{$property=Get-PnpDeviceProperty -InstanceId $current -KeyName 'DEVPKEY_Device_Parent' -ErrorAction Stop;$parent=[string]$property.Data}catch{break}
        if(-not$parent-or$parent-ceq$current){break};$current=$parent
    }
    if($AllowUnknown){return $null}
    throw '已确认原 USB 调试接口，但无法取得它的精确设备序列号；未改选其它 HDC 目标。'
}

function Wait-JobsPreparedHarmonyDevice {
    param([string]$Flutter,[string]$Project,[string]$Identity,[int]$TimeoutSeconds=120)
    $clock=[Diagnostics.Stopwatch]::StartNew()
    while($clock.Elapsed.TotalSeconds-lt$TimeoutSeconds){
        $hdc=Get-JobsRunnerHdcExecutable
        if(-not$hdc){throw '准备后仍找不到 HDC，未启动应用。'}
        $targets=@((Invoke-JobsRunnerReadOnlyTool $hdc @('list','targets') $Project 8)-split'\r?\n'|ForEach-Object{$_.Trim()})
        if($Identity-cin$targets){
            $devices=@(Get-JobsRunnerSupportedDevices @(ConvertFrom-JobsRunnerList (Invoke-JobsRunnerTool $Flutter @('devices','--machine') $Project 20)) $Project|Where-Object{$_.id-ceq$Identity-and$_.targetPlatform-match'^(ohos|openharmony)(?:-|$)'})
            if($devices.Count-gt1){throw 'Flutter 返回重复原设备标识，未运行其它设备。'}
            if($devices.Count-eq1){return $devices[0]}
        }
        Write-JobsPrepareDisplay ('等待原鸿蒙设备就绪与本机调试授权：'+$Identity+'；Ctrl+C 可取消。')
        Start-Sleep -Seconds 2
    }
    throw ('环境已准备，但未确认原设备 '+$Identity+' 可运行；未改跑其它设备。')
}

function Invoke-JobsPrepareHarmonyPipeline {
    param([string]$Flutter,[string]$Project,[string]$DiagnosticKey,[switch]$RefreshCompatible,[switch]$EnvironmentOnly)
    $snapshot=Get-JobsPrepareEnvironmentSnapshot
    try{
        Write-JobsPrepareDisplay '正在当前运行流程准备鸿蒙环境：隔离正式 SDK、CLT 工具、项目平台与依赖；不下载模拟器镜像，不修改已有业务源码。' -ForegroundColor Cyan
        $identity=$null
        if(-not$EnvironmentOnly){$identity=Get-JobsPrepareOriginalIdentity $DiagnosticKey -AllowUnknown}
        $script:JobsPrepareCore=Import-JobsPrepareCore
        $selected=Initialize-JobsPrepareSdk $Flutter $Project -RefreshCompatible:$RefreshCompatible
        $flutter=$selected.Flutter
        [void](Invoke-JobsRunnerTool $flutter @('precache','--universal') $Project 1800)
        $tools=Initialize-JobsPrepareTools $Project
        New-JobsPrepareOhosPlatform $flutter $Project $selected.ProjectName
        [void](Invoke-JobsRunnerTool $flutter @('precache','--ohos') $Project 1800)
        [void](Invoke-JobsPrepareProcess $flutter @('pub','get') $Project 900)
        Assert-JobsRunnerProjectPackages $Project -Harmony -Flutter $flutter
        $directory=Join-Path $Project 'ohos'
        $wrapper=$null
        foreach($name in @('hvigorw.bat','hvigorw.cmd')){$path=Join-Path $directory $name;if([IO.File]::Exists($path)){$wrapper=$path;break}}
        if(-not$wrapper){throw '鸿蒙工程缺少自己的 Hvigor wrapper，未用其它工程的配置代替。'}
        [void](Invoke-JobsPrepareProcess $tools.Ohpm @('install') $directory 1800)
        [void](Invoke-JobsPrepareProcess $wrapper @('--sync') $directory 1800)
        $report=Get-JobsRunnerPreflight $flutter $Project
        Write-JobsRunnerPreflight $report $flutter $Project
        Assert-JobsRunnerPreflight $report 'ohos-arm64'
        if($EnvironmentOnly){
            $environment=@{}
            foreach($key in @('PATH','JAVA_HOME','TOOL_HOME','DEVECO_STUDIO_HOME','DEVECO_SDK_HOME','OHOS_SDK_HOME')){$environment[$key]=[Environment]::GetEnvironmentVariable($key,'Process')}
            return [pscustomobject]@{Flutter=$flutter;Environment=$environment;DeviceId='';DevicePlatform='ohos-arm64'}
        }
        if(-not$identity){$identity=Get-JobsPrepareOriginalIdentity $DiagnosticKey}
        $device=Wait-JobsPreparedHarmonyDevice $flutter $Project $identity
        if([string]$device.id-cne$identity-or[string]$device.targetPlatform-notmatch'(?i)^(?:ohos|openharmony)(?:-|$)'){throw '准备结果没有精确匹配原鸿蒙设备，未启动应用。'}
        $environment=@{}
        foreach($key in @('PATH','JAVA_HOME','TOOL_HOME','DEVECO_STUDIO_HOME','DEVECO_SDK_HOME','OHOS_SDK_HOME')){$environment[$key]=[Environment]::GetEnvironmentVariable($key,'Process')}
        return [pscustomobject]@{Flutter=$flutter;DiagnosticKey=$DiagnosticKey;Environment=$environment;DeviceId=[string]$device.id;DevicePlatform=[string]$device.targetPlatform}
    }finally{Restore-JobsPrepareEnvironment $snapshot}
}

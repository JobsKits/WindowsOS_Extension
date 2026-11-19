# RepairRunEnvironment.ps1 | Flutter 运行所需环境与隔离后台准备。
# Created by Jobs on 2026年11月15日，星期日.
# 由运行器加载；后台只修改本轮私有副本与私有缓存，不发布当前工程配置。

# 将设备平台转换为本机可准备的移动工具链。
function Get-JobsRunnerRepairPlatform {
    param([string]$Platform)
    if ($Platform -match '^android(?:-|$)') { return 'Android' }
    if ($Platform -match '^(?:ohos|openharmony)(?:-|$)') { return 'Harmony' }
    return ''
}
# 自动准备当前 Android 工程所需组件，沿用已有下载、许可与备份边界。
function Repair-JobsRunnerAndroidEnvironment {
    param([string]$Flutter,[string]$Project)
    $sdk=Get-JobsAndroidSdk
    $directory=if([IO.Directory]::Exists((Join-Path $Project 'android'))){Join-Path $Project 'android'}else{Join-Path $Project '.android'}
    if(-not[IO.Directory]::Exists($directory)){throw '当前工程缺少 Android 平台目录；不以其它工程模板覆盖。'}
    $local=Join-Path $directory 'local.properties'
    $before=''
    if([IO.File]::Exists($local)){
        Assert-JobsRunnerPlainFile $local
        $before=[IO.File]::ReadAllText($local)
        if($before-match'(?m)^\s*sdk\.dir\s*=\s*(.+)$'){$sdk=[regex]::Replace($Matches[1].TrimEnd("`r"),'\\([\\:=#! ])','$1')}
    }
    if(-not[IO.Path]::IsPathRooted($sdk)){throw 'Android sdk.dir 必须是绝对路径，未写入未知目录。'}
    [void][IO.Directory]::CreateDirectory($sdk)
    $lock=$null
    try{
        try{$lock=[IO.File]::Open((Join-Path $sdk '.jobs-runner-prepare.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch{throw '同一 Android SDK 已有准备任务；请待该任务完成后重试，不并发修改共享 SDK。'}
        $java=Get-JobsAndroidJava
        $tools=Get-JobsAndroidHealthyTools $sdk $java
        $env:ANDROID_HOME=$sdk;$env:ANDROID_SDK_ROOT=$sdk
        $env:JAVA_HOME=Split-Path -Parent (Split-Path -Parent $java)
        $env:PATH=(Split-Path -Parent $java)+[IO.Path]::PathSeparator+$env:PATH
        $listing=Invoke-JobsAndroidTool $java $tools 'sdkmanager' @(('--sdk_root='+$sdk),'--list','--channel=0') -TimeoutSeconds 120
        $source=''
        foreach($relative in @('app/build.gradle','app/build.gradle.kts')){$path=Join-Path $directory $relative;if([IO.File]::Exists($path)){$source += [IO.File]::ReadAllText($path)+"`n"}}
        $defaults=Join-Path (Split-Path -Parent (Split-Path -Parent $Flutter)) 'packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt'
        if([IO.File]::Exists($defaults)){$source += [IO.File]::ReadAllText($defaults)}
        if($source-match'compileSdk(?:Version)?\s*(?::\s*Int\s*)?=?\s*(\d+)'){$api=$Matches[1]}else{throw '无法从当前工程及绑定 Flutter 确定 compileSdk，保留现场；不擅自升级工程要求。'}
        if($source-match'buildToolsVersion\s*=?\s*["''](\d+\.\d+\.\d+)["'']'){$build=$Matches[1]}else{
            $versions=@([regex]::Matches($listing,'(?m)^\s*build-tools;(\d+\.\d+\.\d+)\s*\|')|ForEach-Object{[version]$_.Groups[1].Value}|Sort-Object -Descending)
            if(-not$versions.Count){throw '官方稳定 Build Tools 清单不可解析，未选择未知组件。'}
            $build=[string]$versions[0]
        }
        $required=@{'platform-tools'='platform-tools/adb.exe';('platforms;android-'+$api)=('platforms/android-'+$api+'/android.jar');('build-tools;'+$build)=('build-tools/'+$build+'/aapt2.exe')}
        if($source-match'ndkVersion\s*(?::\s*String\s*)?=?\s*["'']([0-9.]+)["'']'){$required['ndk;'+$Matches[1]]='ndk/'+$Matches[1]+'/ndk-build.cmd'}
        if($source-match'(?s)cmake\s*\{[^}]*version\s*=?\s*["'']([0-9.]+)["'']'){$required['cmake;'+$Matches[1]]='cmake/'+$Matches[1]+'/bin/cmake.exe'}
        foreach($package in @($required.Keys|Sort-Object)){
            if(-not[IO.File]::Exists((Join-Path $sdk $required[$package]))){Invoke-JobsAndroidTool $java $tools 'sdkmanager' @(('--sdk_root='+$sdk),'--install',$package,'--channel=0') -Interactive}
            if(-not[IO.File]::Exists((Join-Path $sdk $required[$package]))){throw ('Android 组件准备后复检失败：'+$package)}
        }
        if([IO.File]::Exists($local)-and[IO.File]::ReadAllText($local)-cne$before){throw '准备期间 local.properties 已被修改，未覆盖。'}
        if([IO.File]::Exists($local)){[IO.File]::Copy($local,($local+'.jobs-backup-'+[guid]::NewGuid().ToString('N')))}
        $escaped=$sdk.Replace('\','\\').Replace(':','\:').Replace(' ','\ ')
        $next=([regex]::Replace($before,'(?m)^sdk\.dir\s*=.*(?:\r?\n|$)','')).TrimEnd("`r","`n")+"`r`nsdk.dir="+$escaped+"`r`n"
        [IO.File]::WriteAllText($local,$next,(New-Object Text.UTF8Encoding($false)))
        [void](Invoke-JobsRunnerTool $Flutter @('pub','get') $Project 900)
        [void](Invoke-JobsRunnerTool $Flutter @('precache','--android') $Project 1800)
    }finally{if($lock){$lock.Dispose()}}
}
# 设备选择前先修本工程公共依赖，避免公共失败被误判成每个平台都缺SDK。
function Repair-JobsRunnerCommonDependencies {
    param([string]$Flutter,[string]$Project,[hashtable]$Report)
    if(-not$Report.ContainsKey('base')-or$Report.base.State-cne'ready'){
        Write-JobsRunnerMilestone '先使用本次所选 Flutter SDK 修复工程公共依赖索引'
        [void](Invoke-JobsRunnerTool $Flutter @('pub','get') $Project 900)
        $Report=Get-JobsRunnerPreflight $Flutter $Project
        Write-JobsRunnerPreflight $Report $Flutter $Project
        Assert-JobsRunnerPreflight $Report
    }
    return $Report
}
# 先修公共依赖并复检，再按所选平台的真实结果准备工具链。
function Repair-JobsRunnerRequiredEnvironment {
    param([string]$Flutter,[string]$Project,[string]$Platform,[hashtable]$Report)
    $Report=Repair-JobsRunnerCommonDependencies $Flutter $Project $Report
    $kind=Get-JobsRunnerRepairPlatform $Platform
    $key=if($kind-ceq'Android'){'android'}elseif($kind-ceq'Harmony'){'ohos'}else{''}
    if($key-and($Report.ContainsKey($key)-and$Report[$key].State-cne'ready')){
        Write-JobsRunnerMilestone ('正在直接补齐本次运行所需的 '+$kind+' 环境')
        if($kind-ceq'Android'){Repair-JobsRunnerAndroidEnvironment $Flutter $Project}
        else{
            $result=Invoke-JobsPrepareHarmonyPipeline $Flutter $Project '' -EnvironmentOnly
            Set-JobsRunnerTaskEnvironment $result.Environment
            $Flutter=$result.Flutter
            $script:RunnerPreparedHarmony=$result
        }
    }
    return $Flutter
}
# 私有快照拒绝链接，不跟随外部工程、SDK 或供应商目录。
function Copy-JobsRunnerPreparationTree {
    param([string]$Source,[string]$Destination,[switch]$Sdk)
    [void][IO.Directory]::CreateDirectory($Destination)
    foreach($item in @(Get-ChildItem -LiteralPath $Source -Force)){
        if($item.Name-in@('node_modules','Pods','.dart_tool','build','DerivedData','work','.fvm')-or(-not$Sdk-and$item.Name-ceq'.git')){continue}
        if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw ('后台快照遇到外部链接，未访问或修改目标：'+$item.FullName)}
        $target=Join-Path $Destination $item.Name
        if($item.PSIsContainer){Copy-JobsRunnerPreparationTree $item.FullName $target -Sdk:$Sdk}
        else{[IO.File]::Copy($item.FullName,$target,$false)}
    }
}
# Windows worker持有自己的Job，终止worker时自动回收本轮全部下载子进程。
function New-JobsRunnerPreparationJob {
    if([Environment]::OSVersion.Platform-ne[PlatformID]::Win32NT){return $null}
    if(-not('Jobs.PreparationJobV1.Lifetime'-as[type])){
        Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
namespace Jobs.PreparationJobV1 {
    public sealed class Lifetime : IDisposable {
        [StructLayout(LayoutKind.Sequential)] struct Basic {public long PerProcessUserTimeLimit,PerJobUserTimeLimit;public uint LimitFlags;public UIntPtr MinimumWorkingSetSize,MaximumWorkingSetSize;public uint ActiveProcessLimit;public UIntPtr Affinity;public uint PriorityClass,SchedulingClass;}
        [StructLayout(LayoutKind.Sequential)] struct Io {public ulong ReadOperationCount,WriteOperationCount,OtherOperationCount,ReadTransferCount,WriteTransferCount,OtherTransferCount;}
        [StructLayout(LayoutKind.Sequential)] struct Extended {public Basic BasicLimitInformation;public Io IoInfo;public UIntPtr ProcessMemoryLimit,JobMemoryLimit,PeakProcessMemoryUsed,PeakJobMemoryUsed;}
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr attributes,string name);
        [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job,int kind,IntPtr data,uint length);
        [DllImport("kernel32.dll",SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job,IntPtr process);
        [DllImport("kernel32.dll",SetLastError=true)] static extern bool QueryInformationJobObject(IntPtr job,int kind,IntPtr data,uint length,out uint returned);
        [DllImport("kernel32.dll",SetLastError=true)] static extern bool IsProcessInJob(IntPtr process,IntPtr job,out bool result);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
        IntPtr handle;
        public Lifetime() {
            handle=CreateJobObject(IntPtr.Zero,null);
            if(handle==IntPtr.Zero)throw new System.ComponentModel.Win32Exception();
            Extended value=new Extended();value.BasicLimitInformation.LimitFlags=0x2000;
            int length=Marshal.SizeOf(typeof(Extended));IntPtr data=Marshal.AllocHGlobal(length);
            try {
                Marshal.StructureToPtr(value,data,false);
                if(!SetInformationJobObject(handle,9,data,(uint)length)||!AssignProcessToJobObject(handle,Process.GetCurrentProcess().Handle))throw new System.ComponentModel.Win32Exception();
            }catch{CloseHandle(handle);handle=IntPtr.Zero;throw;}
            finally{Marshal.FreeHGlobal(data);}
        }
        public void Complete(){
            // 同一Job的守护子进程也须退出；按已打开句柄核验归属，防PID复用误伤。
            IntPtr list=Marshal.AllocHGlobal(65536);Stopwatch clock=Stopwatch.StartNew();
            try{
                while(true){
                    uint returned;if(!QueryInformationJobObject(handle,3,list,65536,out returned))throw new System.ComponentModel.Win32Exception();
                    int count=Marshal.ReadInt32(list,4),children=0;
                    for(int index=0;index<count;index++){
                        long id=IntPtr.Size==8?Marshal.ReadInt64(list,8+index*8):Marshal.ReadInt32(list,8+index*4);
                        if(id==Process.GetCurrentProcess().Id)continue;children++;
                        if(id<=0||id>Int32.MaxValue)continue;
                        try{using(Process process=Process.GetProcessById((int)id)){bool owned;if(!IsProcessInJob(process.Handle,handle,out owned))throw new System.ComponentModel.Win32Exception();if(owned&&!process.HasExited){process.Kill();process.WaitForExit(1000);}}}catch(ArgumentException){}
                    }
                    if(children==0)break;
                    if(clock.ElapsedMilliseconds>5000)throw new InvalidOperationException("Preparation descendants did not exit; retaining failure state.");
                    System.Threading.Thread.Sleep(25);
                }
            }finally{Marshal.FreeHGlobal(list);}
            Extended value=new Extended();int length=Marshal.SizeOf(typeof(Extended));IntPtr data=Marshal.AllocHGlobal(length);
            try{Marshal.StructureToPtr(value,data,false);if(!SetInformationJobObject(handle,9,data,(uint)length))throw new System.ComponentModel.Win32Exception();}
            finally{Marshal.FreeHGlobal(data);}
        }
        public void Dispose(){if(handle!=IntPtr.Zero){CloseHandle(handle);handle=IntPtr.Zero;}}
    }
}
'@
    }
    return New-Object Jobs.PreparationJobV1.Lifetime
}
# 只停止已核验PID及启动时间的本工程worker，保留缓存、日志和当前Flutter会话。
function Stop-JobsRunnerEnvironmentPreparations {
    param([string]$ProjectRoot)
    foreach($platform in @('Android','Harmony')){
        $directory=Join-Path $ProjectRoot ('EnvironmentPreparation/'+$platform)
        $receipt=Join-Path $directory 'worker.json'
        if(-not[IO.File]::Exists($receipt)){continue}
        try{
            $identity=[IO.File]::ReadAllText($receipt)|ConvertFrom-Json
            $process=[Diagnostics.Process]::GetProcessById([int]$identity.Pid)
            try{
                if($process.StartTime.ToUniversalTime().Ticks-cne[long]$identity.StartTicks){throw 'PID已复用，未停止其它进程。'}
                if([Environment]::OSVersion.Platform-eq[PlatformID]::Win32NT){$process.Kill()}
                else{
                    $method=$process.GetType().GetMethod('Kill',[type[]]@([bool]))
                    if($null-eq$method){throw '当前宿主无法核验完整子树回收能力，未停止未知子进程。'}
                    $process.Kill($true)
                }
                if(-not$process.WaitForExit(5000)){throw 'worker未在停止期限内退出，请核对任务日志。'}
                [IO.File]::WriteAllText((Join-Path $directory 'state.txt'),'已停止后台准备；私有缓存与日志保留，当前Flutter运行不受影响。')
                Write-JobsRunnerDisplayText ('已停止 '+$platform+' 后台环境准备，当前 Flutter 运行保留。')
            }finally{$process.Dispose()}
        }catch [ArgumentException]{Write-JobsRunnerDisplayText ($platform+' 后台准备已结束。')}
        catch{Write-JobsRunnerDisplayText ('❌ [错误] 未能安全停止 '+$platform+' 后台准备：'+$_.Exception.Message) -ForegroundColor Red}
    }
}
# 在私有 SDK / 工程 / 用户缓存完成后台准备；完成后只留下待应用说明，不发布当前工程。
function Invoke-JobsRunnerBackgroundPreparation {
    param([string]$Flutter,[string]$Project,[ValidateSet('Android','Harmony')][string]$Platform,[string]$Directory)
    $lock=$null;$job=$null
    $state=Join-Path $Directory 'state.txt'
    try{
        $lock=[IO.File]::Open((Join-Path $Directory 'task.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        $job=New-JobsRunnerPreparationJob
        $current=[Diagnostics.Process]::GetCurrentProcess()
        [IO.File]::WriteAllText((Join-Path $Directory 'worker.json'),(@{Pid=$PID;StartTicks=[string]$current.StartTime.ToUniversalTime().Ticks}|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText($state,'正在建立隔离副本')
        $scope=Join-Path $Directory ([guid]::NewGuid().ToString('N'))
        $copy=Join-Path $scope 'Project';$sdk=Join-Path $scope 'FlutterSdk';$profile=Join-Path $scope 'User'
        Copy-JobsRunnerPreparationTree $Project $copy
        $originalSdk=Split-Path -Parent (Split-Path -Parent $Flutter)
        if([IO.File]::Exists((Join-Path $originalSdk '.git'))-or[IO.File]::Exists((Join-Path $originalSdk '.git/commondir'))){throw '原 SDK 使用外部 Git 工作树元数据，不能安全复制；未接触原 SDK。'}
        Copy-JobsRunnerPreparationTree $originalSdk $sdk -Sdk
        $privateFlutter=Join-Path $sdk ('bin/'+[IO.Path]::GetFileName($Flutter))
        $env:LOCALAPPDATA=Join-Path $profile 'AppData/Local';$env:APPDATA=Join-Path $profile 'AppData/Roaming';$env:USERPROFILE=$profile
        $env:PUB_CACHE=Join-Path $profile 'PubCache';$env:GRADLE_USER_HOME=Join-Path $profile 'Gradle';$env:ANDROID_HOME=Join-Path $profile 'AndroidSdk';$env:ANDROID_SDK_ROOT=$env:ANDROID_HOME
        $env:ANDROID_USER_HOME=Join-Path $profile 'Android';$env:ANDROID_AVD_HOME=Join-Path $profile 'Avd';$env:FVM_CACHE_PATH=Join-Path $profile 'Fvm';$env:FLUTTER_ROOT=$sdk
        foreach($path in @($env:LOCALAPPDATA,$env:APPDATA,$profile,$env:PUB_CACHE,$env:GRADLE_USER_HOME,$env:ANDROID_HOME)) {[void][IO.Directory]::CreateDirectory($path)}
        foreach($name in @('TOOL_HOME','DEVECO_STUDIO_HOME','DEVECO_SDK_HOME','OHOS_SDK_HOME','JAVA_HOME')){[Environment]::SetEnvironmentVariable($name,$null,'Process')}
        $env:NO_COLOR='1';$env:PLAIN_OUTPUT='1';$env:JOBS_FLUTTER_RUNNER_FZF='0'
        if($Platform-ceq'Android'){
            # 快照中的旧 sdk.dir 不得把后台准备带回前台共享 SDK。
            foreach($relative in @('android/local.properties','.android/local.properties')){$local=Join-Path $copy $relative;if([IO.File]::Exists($local)){[IO.File]::WriteAllText($local,([regex]::Replace([IO.File]::ReadAllText($local),'(?m)^\s*sdk\.dir\s*=.*(?:\r?\n|$)','')))}}
            Repair-JobsRunnerAndroidEnvironment $privateFlutter $copy
        }else{
            [void](Invoke-JobsPrepareHarmonyPipeline $privateFlutter $copy '' -EnvironmentOnly -RefreshCompatible)
        }
        [IO.File]::WriteAllText((Join-Path $Directory 'prepared.txt'),('隔离工程：'+$copy+[Environment]::NewLine+'隔离 SDK：'+$sdk+[Environment]::NewLine+'当前工程未改动。FVM、平台文件与依赖索引均只在隔离目录；当前运行结束后从本工程重新发起对应平台运行，前台流程核验后再应用，不自动覆盖。'))
        [IO.File]::WriteAllText($state,'已完成隔离准备；工程变更待当前运行结束后核验应用')
        if($job){$job.Complete()}
    }catch{
        if($lock){[IO.File]::WriteAllText($state,('未完成：'+$_.Exception.Message+'；保留隔离目录与日志，当前运行不受影响。'))}
        Write-JobsRunnerDisplayText ('❌ [错误] 后台准备未完成：'+$_.Exception.Message) -ForegroundColor Red
    }finally{if($lock){$lock.Dispose()};if($job){$job.Dispose()}}
}
# 以无窗口独立 PowerShell 执行私有后台任务，父流程不等待下载完成。
function Start-JobsRunnerBackgroundPreparation {
    param([string]$Flutter,[string]$Project,[string]$Platform)
    $directory=Join-Path (Get-JobsRunnerProjectRoot $Project) ('EnvironmentPreparation/'+$Platform)
    [void][IO.Directory]::CreateDirectory($directory)
    try{$probe=[IO.File]::Open((Join-Path $directory 'task.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);$probe.Dispose()}catch{Write-JobsRunnerDisplayText ('已有同项目 '+$Platform+' 后台准备任务，日志：'+$directory);return}
    $module=Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Action.psm1'
    $runId=[guid]::NewGuid().ToString('N')
    $log=Join-Path $directory ('prepare-'+$runId+'.log')
    $request=Join-Path $directory ('request-'+$runId+'.json')
    [IO.File]::WriteAllText($request,(@{Flutter=$Flutter;Project=$Project;Platform=$Platform;Directory=$directory;Module=$module;Log=$log}|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
    $command='$r=Get-Content -LiteralPath '+("'"+$request.Replace("'","''")+"'")+' -Raw -Encoding UTF8|ConvertFrom-Json;$m=Import-Module $r.Module -PassThru -DisableNameChecking;& $m {param($r) Invoke-JobsRunnerBackgroundPreparation $r.Flutter $r.Project $r.Platform $r.Directory} $r *> $r.Log'
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=Get-JobsRunnerCreatorPowerShell
    $start.Arguments='-NoProfile -ExecutionPolicy Bypass -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardInput=$true
    $process=New-Object Diagnostics.Process;$process.StartInfo=$start
    try{[void]$process.Start();$process.StandardInput.Close();Write-JobsRunnerDisplayText ('后台准备 '+$Platform+' 已启动；不会阻塞当前运行。日志：'+$log)}finally{$process.Dispose()}
}
# 仅询问未选择且缺失的移动平台，回车后台准备，任意非空输入跳过。
function Request-JobsRunnerOtherEnvironmentPreparation {
    param([string]$Flutter,[string]$Project,[string]$Selected,[hashtable]$Report)
    $active=Get-JobsRunnerRepairPlatform $Selected
    foreach($pair in @(@('Android','android'),@('Harmony','ohos'))){
        if($pair[0]-ceq$active-or-not$Report.ContainsKey($pair[1])-or$Report[$pair[1]].State-ceq'ready'){continue}
        Write-JobsRunnerDisplayText ($pair[0]+' 环境未就绪；后台在独立工程和私有缓存准备，完成前不会改动本次运行工程。')
        try{$answer=Read-JobsRunnerInput ('回车后台补齐 '+$pair[0]+'；任意字符+回车不补')}
        catch [Management.Automation.PipelineStoppedException]{throw}
        catch [OperationCanceledException]{throw}
        catch{Write-JobsRunnerDisplayText ('未取得可选后台确认，跳过 '+$pair[0]+'；继续当前运行。');continue}
        if($answer.Length-eq0){try{Start-JobsRunnerBackgroundPreparation $Flutter $Project $pair[0]}catch{Write-JobsRunnerDisplayText ('❌ [错误] 后台任务未启动：'+$_.Exception.Message+'；继续当前运行。') -ForegroundColor Red}}
    }
}

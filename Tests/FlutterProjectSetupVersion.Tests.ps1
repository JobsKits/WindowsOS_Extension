# FlutterProjectSetupVersion.Tests.ps1 | 真实版本字段与工具单源回归。
# Created by Jobs on 2026年10月29日，星期四.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$count=0
function Assert($Value,[string]$Message){$script:count++;if(-not$Value){throw $Message}}
$tempBase=if([Environment]::OSVersion.Platform-eq[PlatformID]::Win32NT){[IO.Path]::GetTempPath()}else{'/private/tmp'}
$temp=Join-Path $tempBase ('jobs-setup-version-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$oldSession=$env:JOBS_SETUP_SESSION;$env:JOBS_SETUP_SESSION=$temp
$module=Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetup.psm1') -PassThru -DisableNameChecking
$progress=Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetupProgress.psm1') -PassThru -DisableNameChecking
try{
 $tool=Get-JobsSetupVersion
 $metadata=Get-Content -LiteralPath (Join-Path $root 'JobsFlutterTools/Scripts/SetupVersion.json') -Raw|ConvertFrom-Json
 Assert ($tool.Version-ceq$metadata.version-and$tool.Build-ceq$metadata.build) '工具版号只有 SetupVersion.json 一个源'
 Assert ($tool.Label-ceq('v'+$metadata.version+' build '+$metadata.build)) '窗口同时显示语义版本与 build'
 Assert ((Get-JobsSetupVersion (Join-Path $temp 'missing.json')).Label-ceq'工具版本未检测') '缺失版本文件不伪造默认值'
 $bad=Join-Path $temp 'bad.json';[IO.File]::WriteAllText($bad,'{"version":"fake","build":"2026"}')
 Assert ((Get-JobsSetupVersion $bad).Label-ceq'工具版本未检测') '无效元数据明确未检测'
 Set-JobsSetupProgress sdk.flutter done '真实探测' -Version 'Flutter 3.38.2 / Dart 3.10.0 / FVM 4.0.1'
 Set-JobsSetupProgress run.device done '已选择'
 $events=@([IO.File]::ReadAllLines((Join-Path $temp 'events.jsonl'))|ForEach-Object{$_|ConvertFrom-Json})
 Assert ($events[0].version-ceq'Flutter 3.38.2 / Dart 3.10.0 / FVM 4.0.1') '事件独立传递完整版本'
 Assert ($events[1].PSObject.Properties.Name-notcontains'version') '旧事件与非版本步骤兼容'
 Assert ((Get-JobsSetupDetectedVersion ([pscustomobject]@{Mode='system'}))-ceq'尚未检测') '旧对象缺字段时明确未检测'
 $sdk=Join-Path $temp 'flutter';$jdk=Join-Path $temp 'jdk'
 foreach($file in @((Join-Path $sdk 'bin/flutter.bat'),(Join-Path $sdk 'bin/cache/dart-sdk/bin/dart.exe'),(Join-Path $jdk 'bin/java.exe'),(Join-Path $jdk 'bin/javac.exe'))){[void][IO.Directory]::CreateDirectory((Split-Path -Parent $file));[IO.File]::WriteAllText($file,'fixture, never executed')}
 &$module{
  param($base)
  $script:versionRoot=$base
  function script:Get-JobsInstallRoot{$script:versionRoot}
  function script:Find-JobsExecutable{param($Name)if($Name-ceq'fvm.exe'){return (Join-Path $script:versionRoot 'fvm.exe')}}
  function script:Invoke-JobsSetupProcess{
   param($File,$Arguments,$Directory,$TimeoutSeconds)
   $name=[IO.Path]::GetFileName($File)
   $out='';$err=''
   switch($name){
    'flutter.bat'{$out='Bootstrap preamble'+"`n"+'{"frameworkVersion":"3.38.2","dartSdkVersion":"3.10.0"}';if(($Arguments-join',')-cne'--version,--machine'){throw 'Flutter 必须查询 machine 版本'}}
    'dart.exe'{$err='Dart SDK version: 3.10.0 (stable)'}
    'fvm.exe'{$out='FVM 4.0.1'}
    'java.exe'{$err='openjdk version "17.0.16" 2025-07-15'+"`n"+'OpenJDK Runtime Environment Temurin-17.0.16+8 (build 17.0.16+8)'}
    'javac.exe'{$out='javac 17.0.16'}
    default{throw ('未知夹具工具 '+$name)}
   }
   [pscustomobject]@{ExitCode=0;StdOut=$out;StdErr=$err}
  }
 }$temp
 $flutter=&$module{param($p,$base)Get-JobsSetupFlutter $p $base 'fvm'}(Join-Path $sdk 'bin/flutter.bat') $temp
 Assert ($flutter.VersionText-ceq'Flutter 3.38.2 / Dart 3.10.0 / FVM 4.0.1') 'Flutter/Dart/FVM 分别读取实际工具输出'
 $flutter=&$module{param($p,$base)Get-JobsSetupFlutter $p $base 'system'}(Join-Path $sdk 'bin/flutter.bat') $temp
 Assert ($flutter.VersionText.Contains('FVM 不适用')) '系统模式不声称使用了 FVM'
 $java=&$module{param($p,$base)Get-JobsSetupJava $p $base}$jdk $temp
 Assert ($java.Major-eq17-and$java.VersionText.Contains('Java 17.0.16 / javac 17.0.16')) 'Java 与 javac 完整补丁版本同时保留'
 Assert ($java.VersionText.Contains('Temurin-17.0.16+8')) 'Java 厂商与构建号不被主版本替代'
 $jenv=Join-Path $temp 'toolchains/JEnv-for-Windows/src/jenv.ps1';[void][IO.Directory]::CreateDirectory((Split-Path -Parent $jenv));[IO.File]::WriteAllText($jenv,'$JENV_VERSION = "v2.2.1"; throw "never import manager initialization"')
 $version=&$module{param($p)Get-JobsSetupManagerVersion 'jenv' $p}$temp
 Assert ($version-ceq'jEnv Windows v2.2.1') 'jEnv 从已装官方源码读取版本，不执行全局初始化'
 $properties=Join-Path $temp 'source.properties';[IO.File]::WriteAllText($properties,"Pkg.Revision= 29.0.14033849`nAndroidVersion.ApiLevel=36`n")
 Assert ((&$module{param($p)Get-JobsSetupPropertyValue $p 'Pkg.Revision'}$properties)-ceq'29.0.14033849') 'Android 组件实际 source.properties 版本可读取'
 Assert ((&$module{param($p)Get-JobsSetupPropertyValue $p 'Absent.Key'}$properties)-ceq'未检测') 'Android 缺失版本不采用期望安装值'
 Assert ((&$module{Get-JobsSetupPluginVersion "JOBS_TOOL_VERSION|AGP|8.12.2`nJOBS_TOOL_VERSION|AGP|8.12.2"})-ceq'AGP 8.12.2') 'AGP 显示同进程插件类加载器实际版本并去重'
 Assert ((&$module{Get-JobsSetupPluginVersion 'build successful'}).Contains('实际版本未检测')) '解析成功不等于知道 AGP 版本'
 $init=&$module{param($p)New-JobsSetupVersionInit $p}$temp;$initText=[IO.File]::ReadAllText($init)
 Assert ($initText.Contains('plugin.class.classLoader.loadClass')-and$initText.Contains('ANDROID_GRADLE_PLUGIN_VERSION')) '版本探针读取实际已加载 AGP'
 Assert (-not$initText.Contains('repositories')-and-not$initText.Contains('setProperty')) '版本探针不修改插件仓库或工程配置'
 # 完整依赖调用只替换外部进程边界，核对实际 AGP 事件与临时探针回收。
 [void][IO.Directory]::CreateDirectory((Join-Path $temp 'android'))
 &$module{
  $script:versionCommands=New-Object 'System.Collections.Generic.List[string]'
  function script:Invoke-JobsSetupProcess{
   param($File,$Arguments,$Directory,$TimeoutSeconds)
   $script:versionCommands.Add($Arguments[0])
   if($Arguments[0]-ceq'help'){
    $index=[array]::IndexOf($Arguments,'--init-script');if($index-lt0){throw '缺少实际 AGP 版本探针'}
    $script:versionProbe=$Arguments[$index+1];if(-not[IO.File]::Exists($script:versionProbe)){throw '探针未落盘'}
    return [pscustomobject]@{ExitCode=0;StdOut='JOBS_TOOL_VERSION|AGP|8.12.2';StdErr=''}
   }
   return [pscustomobject]@{ExitCode=0;StdOut='pub get fixture';StdErr=''}
  }
 }
 &$module{param($p,$f)Invoke-JobsSetupDependencies $p $f (Join-Path $p 'android/gradlew.bat') 'fixture-fzf'}$temp $flutter
 $last=@([IO.File]::ReadAllLines((Join-Path $temp 'events.jsonl'))|ForEach-Object{$_|ConvertFrom-Json}|Where-Object{$_.node-ceq'deps.plugins'})[-1]
 Assert ($last.state-ceq'done'-and$last.version-ceq'AGP 8.12.2') '插件阶段真正传递实际解析版本'
 Assert ((&$module{$script:versionCommands-join','})-ceq'pub,help') 'pub get 先于构建插件配置解析'
 Assert (-not[IO.File]::Exists((&$module{$script:versionProbe}))) 'Gradle 完成后清理临时版本探针，不污染项目目录'
 $dashboard=[IO.File]::ReadAllText((Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetupDashboard.ps1'))
 Assert ($dashboard.Contains("`$arrow.Text='>>>>>'")-and$dashboard.Contains("Drawing.Font('Consolas',9")) '里程碑 ASCII >>>>> 使用独立等宽连接符'
 Assert ($dashboard.Contains('Get-JobsSetupVersion')-and$dashboard.Contains('$toolVersion.Label')) '窗口版本只读取单文件版本源'
 Assert ($dashboard.Contains("版本：尚未检测")-and$dashboard.Contains('$toolTips.SetToolTip($versionLabel')) '版本独立小字显示且完整 tooltip 可访问'
 $run=[IO.File]::ReadAllText((Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetupRun.ps1'))
 Assert ($run.Contains("'installationVersion'")-and$run.Contains('VC/Tools/MSVC')-and$run.Contains('Windows Kits/10/Include')) 'Windows C++ 版本取本机 VS/MSVC/SDK 清单'
 Assert ($run.Contains('FileVersionInfo')-and$run.Contains('Get-JobsSetupBrowserVersion')) '浏览器读取已安装二进制版本，不启动浏览器冒充探测'
 Assert ($dashboard.Contains('Windows.Forms.SplitContainer')-and$dashboard.Contains('Orientation]::Horizontal')-and$dashboard.Contains('$split.IsSplitterFixed=$false')) '上下区域使用真实可拖动水平分隔'
 Assert ($dashboard.Contains('$split.Panel1MinSize=265')-and$dashboard.Contains('$split.Panel2MinSize=180')-and$dashboard.Contains('$split.Add_SplitterMoved($resize)')) '分区最小尺寸与原生控制台 resize 同步'
 $process=[IO.File]::ReadAllText((Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetupProcess.cs'))
 Assert (-not$process.Contains('WaitHandle.WaitAll')-and$process.Contains('outDone.WaitOne(timeout)')-and$process.Contains('errDone.WaitOne(remaining)')) 'Framework STA 排空不使用多句柄 WaitAll，沿用单一超时预算'
 Assert (-not$process.Contains('Kill(true)')-and-not$process.Contains('ArgumentList')) '日志采集没有 .NET Core 专用进程 API'
 Write-Host ('PASS: FlutterProjectSetupVersion.Tests.ps1 ('+$count+' assertions; fixture-only, no SDK installation or native GUI)')
}finally{
 if($null-eq$oldSession){Remove-Item Env:JOBS_SETUP_SESSION -ErrorAction SilentlyContinue}else{$env:JOBS_SETUP_SESSION=$oldSession}
 Remove-Item -LiteralPath $temp -Recurse -Force
 Remove-Module $module,$progress -ErrorAction SilentlyContinue
}

# ProjectSetupRun.ps1 | 随 ProjectSetup 模块加载的平台准备与真实启动验收。
# Created by Jobs on 2026年10月28日，星期三.
# 复用 JobsCommand@Flutter/WindowsOS 原生 setup、Android 与设备内核思路；本包独立运行。
# 当前进程专用原始输出采集器，不过滤终端日志。
function New-JobsSetupLiveProcess {
 param($Start,[switch]$InputEnabled)
 if(-not('Jobs.SetupProcess'-as[type])){Add-Type -Path (Join-Path $PSScriptRoot 'ProjectSetupProcess.cs')}
 $raw=if($env:JOBS_SETUP_SESSION){Join-Path $env:JOBS_SETUP_SESSION 'raw.log'}elseif(Get-Variable SetupLog -Scope Script -ErrorAction SilentlyContinue){$script:SetupLog+'.raw.log'}else{''}
 return New-Object Jobs.SetupProcess($Start,$raw,[bool]$InputEnabled)
}
# 仅停止本次启动的进程树；不按程序名杀其它会话。
function Stop-JobsSetupProcessTree {
 param([int]$ProcessId)
 $result=Invoke-JobsProcess -FilePath (Join-Path ([Environment]::GetFolderPath('System')) 'taskkill.exe') -Arguments @('/PID',[string]$ProcessId,'/T','/F') -TimeoutSeconds 10
 if($result.ExitCode-ne0){throw('无法停止本次进程树 PID '+$ProcessId)}
}
# 实时工具输出保留到独立 raw.log，超时/取消停止本次子树。
function Invoke-JobsSetupLiveProcess {
 param($Start,[int]$TimeoutSeconds)
 $runner=New-JobsSetupLiveProcess $Start
 $clock=[Diagnostics.Stopwatch]::StartNew();$begun=$false
 try{
  $runner.Start();$begun=$true
  while(-not$runner.HasExited){
   if($clock.Elapsed.TotalSeconds-ge$TimeoutSeconds){Stop-JobsSetupProcessTree $runner.Id;throw '工具超时，已停止本次进程树。'}
   Start-Sleep -Milliseconds 50
  }
  if(-not$runner.Drain(5000)){throw '工具输出管道未及时关闭，原始日志保留。'}
  if($runner.OutputFailure){throw('原始日志保存失败：'+$runner.OutputFailure)}
  return [pscustomobject]@{ExitCode=$runner.ExitCode;StdOut=$runner.StdOut;StdErr=$runner.StdErr}
 }finally{if($begun-and-not$runner.HasExited){Stop-JobsSetupProcessTree $runner.Id};$runner.Dispose()}
}
# 只列工程已有且 Windows 支持的原生平台，不能假装支持 iOS。
function Select-JobsSetupPlatform {
 param([string]$Project,[string]$Fzf)
 $items=@(@('Android','Web','Windows','Ohos')|Where-Object{[IO.Directory]::Exists((Join-Path $Project $_.ToLowerInvariant()))})
 if(-not$items.Count){throw '本工程没有 Android、Web、Windows 或 Ohos 平台；Apple/Linux 需要对应宿主。'}
 return Select-JobsSetupChoice $Fzf '选择本次准备与验收的平台' $items
}
# 增量更新一个 local.properties 字段并保留原文备份。
function Set-JobsSetupLocalProperty {
 param([string]$Project,[string]$Key,[string]$Value)
 $path=Join-Path $Project 'android/local.properties';Assert-JobsSetupFile $path
 $before=if([IO.File]::Exists($path)){[IO.File]::ReadAllText($path)}else{''}
 $escaped=$Value.Replace('\','\\').Replace(':','\:').Replace(' ','\ ')
 $next=[regex]::Replace($before,('(?m)^\s*'+[regex]::Escape($Key)+'\s*=.*(?:\r?\n|$)'),'').TrimEnd("`r","`n")+"`r`n"+$Key+'='+$escaped+"`r`n"
 if($next-cne$before){if([IO.File]::Exists($path)){Copy-Item -LiteralPath $path -Destination ($path+'.jobs-'+[guid]::NewGuid().ToString('N')+'.bak')};[IO.File]::WriteAllText($path,$next,(New-Object Text.UTF8Encoding($false)))}
}
# source.properties / 文件版本读取均来自本机已安装文件，不把期望值当检测值。
function Get-JobsSetupPropertyValue {
 param([string]$File,[string]$Name)
 if([IO.File]::Exists($File)){$text=[IO.File]::ReadAllText($File);if($text-match('(?m)^\s*'+[regex]::Escape($Name)+'\s*=\s*([^\r\n]+)')){return $Matches[1].Trim()}}
 return '未检测'
}
function Get-JobsSetupBrowserVersion {
 foreach($base in @($env:ProgramFiles,${env:ProgramFiles(x86)},$env:LOCALAPPDATA)){
  if(-not$base){continue}
  foreach($relative in @('Google/Chrome/Application/chrome.exe','Microsoft/Edge/Application/msedge.exe')){
   $file=Join-Path $base $relative
   if([IO.File]::Exists($file)){$info=[Diagnostics.FileVersionInfo]::GetVersionInfo($file);$name=if($relative.StartsWith('Google')){'Chrome'}else{'Edge'};$version=if($info.ProductVersion){$info.ProductVersion}else{'版本未检测'};return ($name+' '+$version)}
  }
 }
 return '浏览器未检测'
}
# 官方 Android 工具内核补齐平台、build-tools、NDK/CMake；许可交给本人确认。
function Initialize-JobsSetupAndroid {
 param([string]$Project,$Flutter,$Java,[string]$Fzf)
 $support=Import-Module (Join-Path $PSScriptRoot 'Actions/android-support/Scripts/Action.psm1') -PassThru -DisableNameChecking
 $sdk=&$support{Get-JobsAndroidSdk}
 $local=Join-Path $Project 'android/local.properties'
 if([IO.File]::Exists($local)-and[IO.File]::ReadAllText($local)-match'(?m)^\s*sdk\.dir\s*=\s*(.+)$'){$sdk=[regex]::Replace($Matches[1].TrimEnd("`r"),'\\([\\:=#! ])','$1')}
 Assert-JobsSetupDirectory $sdk;[void][IO.Directory]::CreateDirectory($sdk)
 $env:ANDROID_HOME=$sdk;$env:ANDROID_SDK_ROOT=$sdk
 $toolJava=$Java.Java
 if($Java.Major-lt21){Write-JobsSetupMessage 'Android 命令行工具需要独立 Java21+；Gradle 仍使用所选项目 JDK。';$toolJava=&$support{Get-JobsAndroidJava}}
 $tools=&$support{param($s,$j)Get-JobsAndroidHealthyTools $s $j}$sdk $toolJava
 $listing=&$support{param($s,$j,$t)Invoke-JobsAndroidTool $j $t 'sdkmanager' @(('--sdk_root='+$s),'--list','--channel=0') -TimeoutSeconds 120}$sdk $toolJava $tools
 $source=''
 foreach($relative in @('android/app/build.gradle','android/app/build.gradle.kts')){$path=Join-Path $Project $relative;if([IO.File]::Exists($path)){$source += [IO.File]::ReadAllText($path)+"`n"}}
 $flutterDefaults=Join-Path $Flutter.Root 'packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt'
 if([IO.File]::Exists($flutterDefaults)){$source += [IO.File]::ReadAllText($flutterDefaults)}
 $apis=@([regex]::Matches($listing,'(?m)^\s*platforms;android-(\d+)\s*\|')|ForEach-Object{$_.Groups[1].Value}|Select-Object -Unique|Sort-Object{[int]$_}-Descending)
 $builds=@([regex]::Matches($listing,'(?m)^\s*build-tools;(\d+\.\d+\.\d+)\s*\|')|ForEach-Object{$_.Groups[1].Value}|Select-Object -Unique|Sort-Object{[version]$_}-Descending)
 if($source-match'compileSdk(?:Version)?\s*(?::\s*Int\s*)?=?\s*(\d+)'){$api=$Matches[1]}else{$api=Select-JobsSetupChoice $Fzf '无法静态确定 compileSdk，请选择工程所需 API' $apis}
 if($source-match'buildToolsVersion\s*=?\s*["''](\d+\.\d+\.\d+)["'']'){$build=$Matches[1]}else{$build=Select-JobsSetupChoice $Fzf '选择 Android Build Tools' $builds}
 $packages=@('platform-tools',('platforms;android-'+$api),('build-tools;'+$build))
 if($source-match'ndkVersion\s*(?::\s*String\s*)?=?\s*["'']([0-9.]+)["'']'){$packages+=('ndk;'+$Matches[1])}
 if($source-match'(?s)cmake\s*\{[^}]*version\s*=?\s*["'']([0-9.]+)["'']'){$packages+=('cmake;'+$Matches[1])}
 Set-JobsSetupProgress platform.licenses waiting '请在下方原始终端逐项阅读 Android SDK 许可；不自动回答 yes'
 &$support{param($s,$j,$t)Invoke-JobsAndroidTool $j $t 'sdkmanager' @(('--sdk_root='+$s),'--licenses') -Interactive}$sdk $toolJava $tools
 Set-JobsSetupProgress platform.licenses done '许可工具已返回；组件安装会复核许可'
 &$support{param($s,$j,$t,$p)Invoke-JobsAndroidTool $j $t 'sdkmanager' (@(('--sdk_root='+$s),'--install')+$p) -Interactive}$sdk $toolJava $tools $packages
 foreach($path in @('platform-tools/adb.exe',('platforms/android-'+$api+'/android.jar'),('build-tools/'+$build+'/aapt2.exe'))){if(-not[IO.File]::Exists((Join-Path $sdk $path))){throw('Android 组件复检失败：'+$path)}}
 foreach($package in $packages){if($package.StartsWith('ndk;')){$required=Join-Path $sdk ('ndk/'+$package.Substring(4)+'/ndk-build.cmd')}elseif($package.StartsWith('cmake;')){$required=Join-Path $sdk ('cmake/'+$package.Substring(6)+'/bin/cmake.exe')}else{continue};if(-not[IO.File]::Exists($required)){throw('Android 原生组件复检失败：'+$package)}}
 Set-JobsSetupLocalProperty $Project 'sdk.dir' $sdk
 Write-JobsSetupMessage ('Android SDK 已准备：'+$sdk+'；组件：'+($packages-join', '))
 $versions=@(('Android API '+(Get-JobsSetupPropertyValue (Join-Path $sdk ('platforms/android-'+$api+'/source.properties')) 'AndroidVersion.ApiLevel')),('Build Tools '+(Get-JobsSetupPropertyValue (Join-Path $sdk ('build-tools/'+$build+'/source.properties')) 'Pkg.Revision')),('platform-tools '+(Get-JobsSetupPropertyValue (Join-Path $sdk 'platform-tools/source.properties') 'Pkg.Revision')))
 foreach($package in $packages){if($package.StartsWith('ndk;')){$versions+=('NDK '+(Get-JobsSetupPropertyValue (Join-Path $sdk ('ndk/'+$package.Substring(4)+'/source.properties')) 'Pkg.Revision'))}elseif($package.StartsWith('cmake;')){$cmake=Invoke-JobsSetupProcess (Join-Path $sdk ('cmake/'+$package.Substring(6)+'/bin/cmake.exe')) @('--version') $Project 30;$value=if(($cmake.StdOut+$cmake.StdErr)-match'cmake version\s+([^\s]+)'){$Matches[1]}else{'未检测'};$versions+=('CMake '+$value)}}
 if(-not@($packages|Where-Object{$_.StartsWith('ndk;')}).Count){$versions+='NDK 工程未声明'}
 if(-not@($packages|Where-Object{$_.StartsWith('cmake;')}).Count){$versions+='CMake 工程未声明'}
 $toolVersion=&$support{param($s,$j,$t)Invoke-JobsAndroidTool $j $t 'sdkmanager' @(('--sdk_root='+$s),'--version') -TimeoutSeconds 30}$sdk $toolJava $tools
 $toolText=if([string]$toolVersion-match'(?m)^\s*(\d+(?:\.\d+)+)\s*$'){$Matches[1]}else{'未检测'};$versions+=('cmdline-tools '+$toolText)
 Set-JobsSetupProgress platform.tools done 'Android 已安装组件版本已读取' -Version ($versions-join' / ')
}
# Windows 桌面缺少 C++ 工作负载时，按用户选择安装官方 Build Tools 后复检。
function Initialize-JobsSetupWindowsDesktop {
 param([string]$Project,[string]$Fzf)
 $vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
 $component=if($env:PROCESSOR_ARCHITECTURE-eq'ARM64'){'Microsoft.VisualStudio.Component.VC.Tools.ARM64'}else{'Microsoft.VisualStudio.Component.VC.Tools.x86.x64'}
 $healthy=$false
 if([IO.File]::Exists($vswhere)){try{$probe=Invoke-JobsSetupProcess $vswhere @('-latest','-products','*','-requires',$component,'-property','installationPath') $Project;$healthy=-not[string]::IsNullOrWhiteSpace($probe.StdOut)}catch{}}
 if(-not$healthy){
  $choice=Select-JobsSetupChoice $Fzf 'Windows C++ 工具缺失' @('安装 Visual Studio Build Tools C++ 工作负载','已手动安装，重新检查')
  if($choice.StartsWith('安装')){
   $winget=Find-JobsExecutable 'winget.exe';if(-not$winget){throw '缺少 WinGet，请先从 Microsoft Store 安装 App Installer，再重新执行。'}
   Set-JobsSetupProgress platform.tools waiting '官方 Build Tools 安装可能请求管理员 UAC，由本人确认'
   [void](Invoke-JobsSetupProcess $winget @('install','--id','Microsoft.VisualStudio.2022.BuildTools','--exact','--source','winget','--scope','machine','--accept-source-agreements','--override',('--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --add '+$component+' --includeRecommended')) $Project 3600)
  }
  if(-not[IO.File]::Exists($vswhere)){throw 'Visual Studio Installer 未就绪，请完成安装后重试。'}
  $probe=Invoke-JobsSetupProcess $vswhere @('-latest','-products','*','-requires',$component,'-property','installationPath') $Project
  if([string]::IsNullOrWhiteSpace($probe.StdOut)){throw 'C++ 工具安装后复检失败。'}
 }
 $path=$probe.StdOut.Trim()
 $reported=Invoke-JobsSetupProcess $vswhere @('-latest','-products','*','-requires',$component,'-property','installationVersion') $Project 30
 $vsVersion=if($reported.StdOut.Trim()){$reported.StdOut.Trim()}else{'未检测'}
 $vc=Join-Path $path 'VC/Tools/MSVC';$msvc=@()
 if([IO.Directory]::Exists($vc)){$msvc=@(Get-ChildItem -LiteralPath $vc -Directory|Where-Object{$_.Name-match'^\d+\.\d+\.\d+$'}|ForEach-Object{$_.Name}|Sort-Object{[version]$_}-Descending)}
 $sdkRoot=Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/Include';$sdks=@()
 if([IO.Directory]::Exists($sdkRoot)){$sdks=@(Get-ChildItem -LiteralPath $sdkRoot -Directory|Where-Object{$_.Name-match'^\d+\.\d+\.\d+\.\d+$'}|ForEach-Object{$_.Name}|Sort-Object{[version]$_}-Descending)}
 Set-JobsSetupProgress platform.tools done '已读取 Visual Studio 工具清单' -Version ('VS '+$vsVersion+' / MSVC '+$(if($msvc.Count){$msvc-join', '}else{'未检测'})+' / Windows SDK '+$(if($sdks.Count){$sdks-join', '}else{'未检测'}))
}
# 按所选平台准备工具及 Flutter precache，不生成用户未选择的平台。
function Initialize-JobsSetupPlatform {
 param([string]$Project,$Flutter,$Java,[string]$Fzf,[string]$Platform)
 Set-JobsSetupProgress platform.tools running ('准备 '+$Platform+' 工具链')
 switch($Platform){
  Android{Initialize-JobsSetupAndroid $Project $Flutter $Java $Fzf}
  Windows{Initialize-JobsSetupWindowsDesktop $Project $Fzf;Set-JobsSetupProgress platform.licenses skipped '微软安装器许可由本人处理'}
  Web{
   $browser=$false
   foreach($base in @($env:ProgramFiles,${env:ProgramFiles(x86)},$env:LOCALAPPDATA)){if($base){foreach($relative in @('Google/Chrome/Application/chrome.exe','Microsoft/Edge/Application/msedge.exe')){if([IO.File]::Exists((Join-Path $base $relative))){$browser=$true}}}}
   if(-not$browser){$choice=Select-JobsSetupChoice $Fzf 'Web 浏览器缺失' @('安装 Google Chrome','已自行安装，重新运行时检查');if($choice.StartsWith('安装')){$worker=Import-Module (Join-Path $PSScriptRoot 'Actions/sdk-manage/Scripts/Action.psm1') -PassThru -DisableNameChecking;&$worker{param($p)Install-JobsWingetTool 'Google.Chrome' $p}$Project}}
   Set-JobsSetupProgress platform.tools done '浏览器本地文件版本已读取' -Version (Get-JobsSetupBrowserVersion)
   Set-JobsSetupProgress platform.licenses skipped '浏览器许可沿官方安装器'
  }
  Ohos{Set-JobsSetupProgress platform.licenses skipped '鸿蒙许可沿现有 DevEco 工具链，本人处理'}
  default{throw '未选择受支持的平台。'}
 }
 Invoke-JobsDependencyPrecache $Project $Flutter $Platform
 Set-JobsSetupProgress platform.tools done ($Platform+' 工具链与 Flutter 平台缓存已准备')
}
# 复用同包 Android 核心，镜像→机型子层可真实返回，不覆盖既有 AVD。
function New-JobsSetupAvd {
 param([string]$Project,[string]$Fzf,$Support)
 $abi=&$Support{Get-JobsAndroidArchitecture}
 $sdk=&$Support{Get-JobsAndroidSdk};$java=&$Support{Get-JobsAndroidJava}
 $tools=&$Support{param($s,$j)Get-JobsAndroidHealthyTools $s $j}$sdk $java
 &$Support{param($s,$j,$t)Repair-JobsAndroidComponents $s $j $t}$sdk $java $tools
 $emulator=Join-Path $sdk 'emulator/emulator.exe'
 [void](Invoke-JobsSetupProcess $emulator @('-accel-check') $Project 30)
 $existing=Invoke-JobsSetupProcess $emulator @('-list-avds') $Project 30
 $names=@($existing.StdOut-split'\r?\n'|Where-Object{$_-match'^[A-Za-z0-9_.-]+$'})
 $listing=&$Support{param($s,$j,$t)Invoke-JobsAndroidTool $j $t 'sdkmanager' @(('--sdk_root='+$s),'--list','--channel=0') -TimeoutSeconds 120}$sdk $java $tools
 $images=@(&$Support{param($l,$a)Get-JobsAndroidImages $l $a}$listing $abi)
 if(-not$images.Count){throw '官方清单没有本机可用的稳定 Android 模拟器镜像。'}
 $listing=&$Support{param($j,$t)Invoke-JobsAndroidTool $j $t 'avdmanager' @('list','device')}$java $tools
 $devices=@(&$Support{param($l)Get-JobsAndroidDevices $l}$listing)
 while($true){
  $image=Select-JobsSetupChoice $Fzf '选择 Android 镜像（可能下载数GB）' $images -Back
  if($null-eq$image){return}
  $device=Select-JobsSetupChoice $Fzf '选择 Android 机型' $devices -Back
  if($null-eq$device){continue}
  Set-JobsSetupProgress run.device waiting '请本人阅读镜像 SDK 许可；不自动回答 yes'
  &$Support{param($s,$j,$t)Invoke-JobsAndroidTool $j $t 'sdkmanager' @(('--sdk_root='+$s),'--licenses') -Interactive}$sdk $java $tools
  &$Support{param($s,$j,$t,$i)Invoke-JobsAndroidTool $j $t 'sdkmanager' @(('--sdk_root='+$s),'--install',$i) -Interactive}$sdk $java $tools $image
  $avdHome=&$Support{Get-JobsAndroidAvdHome}
  $name=&$Support{param($d,$i,$n,$h)New-JobsAndroidAvdName $d $i $n $h}$device $image $names $avdHome
  if((Read-JobsSetupInput ('回车创建并启动新 AVD '+$name+'；其它输入取消') run.device)-ne''){throw '已取消创建；已下载组件保留。'}
  &$Support{param($j,$t,$n,$i,$d)[void](Invoke-JobsAndroidTool $j $t 'avdmanager' @('create','avd','--name',$n,'--package',$i,'--device',$d) -InputText "no`n")}$java $tools $name $image $device
  &$Support{param($s,$n)Start-JobsAndroidAvd $s $n}$sdk $name
  return
 }
}
# 设备空态始终有重新加载、启动/创建 AVD 或等待授权入口。
function Select-JobsSetupDevice {
 param([string]$Project,$Flutter,[string]$Fzf,[string]$Platform)
 while($true){
  Set-JobsSetupProgress run.device running '读取真实设备列表'
  $probe=Invoke-JobsSetupProcess $Flutter.Flutter @('devices','--machine') $Project 90
  $parsedDevices=$probe.StdOut|ConvertFrom-Json
  $devices=@($parsedDevices|Where-Object{$_.isSupported-ne$false-and($(if($Platform -ceq 'Ohos'){([string]$_.targetPlatform)-match'^(ohos|openharmony)'}else{([string]$_.targetPlatform).ToLowerInvariant().StartsWith($Platform.ToLowerInvariant())}))})
  $rows=@($devices|ForEach-Object{$_.id+' | '+$_.name})
  $options=$rows+@('重新加载设备列表','等待连接设备 / 处理设备授权')
  if($Platform-eq'Android'){$options+=@('启动已有 Android AVD','创建并启动 Android AVD')}
  $choice=Select-JobsSetupChoice $Fzf '选择运行设备（无设备时可重新加载）' $options
  if($choice-cin$rows){$device=$devices[[array]::IndexOf($rows,$choice)];Set-JobsSetupProgress run.device done $device.name;return [string]$device.id}
  if($choice-eq'重新加载设备列表'){continue}
  if($choice.StartsWith('等待')){[void](Read-JobsSetupInput '连接设备、处理 adb unauthorized / 浏览器 / 桌面权限后回车重新加载' run.device);continue}
  $support=Import-Module (Join-Path $PSScriptRoot 'Actions/android-support/Scripts/Action.psm1') -PassThru -DisableNameChecking
  if($choice.StartsWith('创建')){
   New-JobsSetupAvd $Project $Fzf $support
  }else{
   $sdk=&$support{Get-JobsAndroidSdk};$emulator=Join-Path $sdk 'emulator/emulator.exe'
   if(-not[IO.File]::Exists($emulator)){throw '未安装 Android Emulator，请选择创建入口准备模拟器，或连接真机。'}
   $listing=Invoke-JobsSetupProcess $emulator @('-list-avds') $Project 30
   $avds=@($listing.StdOut-split'\r?\n'|Where-Object{$_-match'^[A-Za-z0-9_.-]+$'})
   $name=Select-JobsSetupChoice $Fzf '启动已有 AVD' $avds
   &$support{param($s,$n)Start-JobsAndroidAvd $s $n}$sdk $name
  }
  [void](Read-JobsSetupInput '模拟器准备后回车重新加载实际设备列表' run.device)
 }
}
# 从真实入口与 Android flavor 声明建立参数，不接受拼接 Shell 命令。
function Get-JobsSetupRunArguments {
 param([string]$Project,[string]$Fzf,[string]$Device,[string]$Platform,[switch]$ForBuild)
 Set-JobsSetupProgress run.arguments running '选择启动入口与配置'
 $entries=@(Get-ChildItem -LiteralPath (Join-Path $Project 'lib') -Filter 'main*.dart' -File|Where-Object{-not($_.Attributes-band[IO.FileAttributes]::ReparsePoint)}|ForEach-Object{'lib/'+$_.Name})

 $entry=Select-JobsSetupChoice $Fzf '选择 Dart 入口' ($entries+@('手动指定工程内 Dart 入口'))
 if($entry-eq'手动指定工程内 Dart 入口'){$entry=Read-JobsSetupInput '输入工程内 Dart 入口相对路径';$absolute=[IO.Path]::GetFullPath((Join-Path $Project $entry));if(-not$absolute.StartsWith($Project.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)-or[IO.Path]::GetExtension($absolute)-cne'.dart'){throw '入口必须位于当前工程内且为 .dart 文件。'};Assert-JobsSetupFile $absolute;if(-not[IO.File]::Exists($absolute)){throw 'Dart 入口不存在。'}}
 $mode=if($ForBuild){'debug'}else{Select-JobsSetupChoice $Fzf '运行模式' @('debug','profile','release')}
 if($ForBuild){
 $target=switch($Platform){Android{'apk'} Windows{'windows'} Web{'web'} Ohos{'hap'} default{throw '本宿主不支持所选构建目标。'}}
 $argsList=@('build',$target,'--debug','--target',$entry)
 }else{$argsList=@('run','--machine',('--'+$mode),'-d',$Device,'--target',$entry)}
 if($Platform-eq'Android'){
  $source='';foreach($rel in @('android/app/build.gradle','android/app/build.gradle.kts')){$file=Join-Path $Project $rel;if([IO.File]::Exists($file)){$source += [IO.File]::ReadAllText($file)}}
  $flavorSource='';if($source-match'(?s)productFlavors\s*\{(.*?)(?=\n\s*(?:buildTypes|signingConfigs|compileOptions|kotlinOptions|sourceSets)\b|\z)'){$flavorSource=$Matches[1]};$flavors=@([regex]::Matches($flavorSource,'(?:create|maybeCreate|register)\s*\(\s*["'']([A-Za-z0-9_-]+)["'']\s*\)')|ForEach-Object{$_.Groups[1].Value}|Select-Object -Unique)
  $choice=Select-JobsSetupChoice $Fzf 'Flavor' (@('不传 flavor','手动输入 flavor')+$flavors)
  if($choice-eq'手动输入 flavor'){$choice=Read-JobsSetupInput '输入 flavor 名称（空输入取消）';if(-not$choice){throw '已取消 flavor 输入。'}}
  if($choice-ne'不传 flavor'){if($choice-notmatch'^[A-Za-z0-9_-]+$'){throw 'Flavor 名称无效。'};$argsList+=@('--flavor',$choice)}
 }
 $defines=Read-JobsSetupInput '可选 dart-define JSON 配置文件路径（空回车不传；不要在终端输入密码）'
 if($defines){$defines=$defines.Trim().Trim('"');if(-not[IO.Path]::IsPathRooted($defines)){$defines=Join-Path $Project $defines};Assert-JobsSetupFile $defines;if(-not[IO.File]::Exists($defines)){throw 'dart-define 配置文件不存在。'};$defineData=[IO.File]::ReadAllText($defines)|ConvertFrom-Json;if($defineData-isnot[pscustomobject]){throw 'dart-define 文件必须是 JSON 对象。'};$argsList+=('--dart-define-from-file='+$defines)}
 Set-JobsSetupProgress run.arguments done ('入口 '+$entry+'；设备 '+$Device+'；参数已选择，不记录 define 值')
 return ,$argsList
}
# 把机器协议中的真实启动事件关联到本次 appId，日志文字不能冒充成功。
function Get-JobsSetupMachineEvent {
 param([string]$Line)
 # 外层对象保留 JSON 数组层级，兼容 5.1 的顶层数组输出且拒绝嵌套伪事件。
 try{$parsed=('{"Items":'+$Line+'}')|ConvertFrom-Json -ErrorAction Stop;$items=@($parsed.Items)}catch{return @()}
 return @($items|Where-Object{$_-is[pscustomobject]-and$null-ne$_.PSObject.Properties['event']-and$_.event-is[string]-and$null-ne$_.PSObject.Properties['params']-and$_.params-is[pscustomobject]})
}
# 只有协议事件且 appId 与本次 app.start 一致，才能通过启动门禁。
function Test-JobsSetupAppStarted {
 param([string]$AppId,$Event)
 return (-not[string]::IsNullOrWhiteSpace($AppId)-and$Event-is[pscustomobject]-and$null-ne$Event.PSObject.Properties['event']-and$Event.event-ceq'app.started'-and$null-ne$Event.PSObject.Properties['params']-and$Event.params-is[pscustomobject]-and$null-ne$Event.params.PSObject.Properties['appId']-and$Event.params.appId-is[string]-and$Event.params.appId-ceq$AppId)
}
# 真实启动验证后保留运行与 r/R/q 控制；未见 app.started 绝不标为成功。
function Invoke-JobsSetupRunVerification {
 param([string]$Project,$Flutter,[string]$Fzf,[string]$Platform,[string[]]$PreparedBuildArguments)
 $choice=Select-JobsSetupChoice $Fzf '最终运行阶段' @('实际编译安装并启动验证（推荐）','仅完成环境准备，本次不运行应用')
 if($choice.StartsWith('仅完成')){Set-JobsSetupProgress run.launch skipped '用户选择只准备';Set-JobsSetupProgress run.started skipped '未运行应用，不能宣称已可运行';return}
 $device=Select-JobsSetupDevice $Project $Flutter $Fzf $Platform
 if($PreparedBuildArguments){$arguments=@('run','--machine','-d',$device)+@($PreparedBuildArguments | Select-Object -Skip 2)}else{$arguments=Get-JobsSetupRunArguments $Project $Fzf $device $Platform}
 Set-JobsSetupProgress run.launch waiting '即将编译并安装到所选目标，需本人确认'
 if((Read-JobsSetupInput '输入 RUN 才开始实际编译、安装和启动；其它输入停止' run.launch)-cne'RUN'){throw '已取消实际运行；环境准备结果保留。'}
 $start=New-JobsSetupBatchStart (Join-Path ([Environment]::GetFolderPath('System')) 'cmd.exe') $Flutter.Flutter $arguments $Project
 $runner=New-JobsSetupLiveProcess $start -InputEnabled
 $clock=[Diagnostics.Stopwatch]::StartNew();$appId=$null;$started=$false;$quit=$false;$request=0;$begun=$false
 try{
  $runner.Start();$begun=$true;Set-JobsSetupProgress run.launch running 'Flutter 正在编译、安装与启动；完整输出在下方'
  while($true){
   if($runner.HasExited){if(-not$runner.Drain(5000)){throw '运行输出管道未及时结束。'}}
   foreach($line in $runner.TakeLines()){
    foreach($event in @(Get-JobsSetupMachineEvent $line)){
     if($event.event-ceq'app.start'-and$null-ne$event.params.PSObject.Properties['appId']-and$event.params.appId-is[string]){$appId=$event.params.appId}
     if(Test-JobsSetupAppStarted $appId $event){$started=$true;Set-JobsSetupProgress run.launch done '构建安装与启动阶段完成';Set-JobsSetupProgress run.started done ('已收到本次 app.started；设备 '+$device);Write-JobsSetupMessage '本次应用已启动验证。终端 r 热重载，R 热重启，q 停止本次应用。'}
    }
   }
   if($runner.HasExited){break}
   if(-not$started-and$clock.Elapsed.TotalSeconds-gt900){throw '15 分钟内没有收到本次 app.started；运行验收未通过。'}
   if([Console]::KeyAvailable){
    $key=[Console]::ReadKey($true).KeyChar
    if($key-in@('r','R')-and$appId){$request++;$runner.Send((ConvertTo-Json -InputObject @(@{id=$request;method='app.restart';params=@{appId=$appId;fullRestart=($key-ceq'R');pause=$false}}) -Compress -Depth 10))}
    elseif($key-eq'q'){$quit=$true;if($appId){$request++;$runner.Send((ConvertTo-Json -InputObject @(@{id=$request;method='app.stop';params=@{appId=$appId}}) -Compress -Depth 10))};$request++;$runner.Send((ConvertTo-Json -InputObject @(@{id=$request;method='daemon.shutdown'}) -Compress));break}
   }
   Start-Sleep -Milliseconds 50
  }
  if($quit-and-not$runner.HasExited){$stopClock=[Diagnostics.Stopwatch]::StartNew();while(-not$runner.HasExited-and$stopClock.Elapsed.TotalSeconds-lt10){Start-Sleep -Milliseconds 50}}
  if(-not$started){throw 'Flutter 进程结束但没有收到本次 app.started；不能认定项目已运行。'}
  if(-not$quit-and$runner.ExitCode-ne0){throw('应用启动后 Flutter 异常退出：'+$runner.ExitCode)}
 }finally{if($begun-and-not$runner.HasExited){Stop-JobsSetupProcessTree $runner.Id};$runner.Dispose()}
}

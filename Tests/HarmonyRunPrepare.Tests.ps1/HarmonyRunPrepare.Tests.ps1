# HarmonyRunPrepare.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年11月10日，星期二.
# 临时工程与假命令验证真实阶段编排；不联网、不安装、不切用户 SDK 或运行应用。
[CmdletBinding()]
param([string]$Dart,[string]$Packages)

function Assert-Prepare {
    param([bool]$Value,[string]$Message)
    if(-not$Value){throw ('FAIL: '+$Message)}
    $script:Checks++
}

function Invoke-PrepareTests {
    $script:Checks=0
    $root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $temporary=Join-Path ([IO.Path]::GetTempPath()) ('JobsHarmonyRunPrepare-'+[guid]::NewGuid().ToString('N'))
    $project=Join-Path $temporary '工程 中文 & 100%'
    [void][IO.Directory]::CreateDirectory((Join-Path $project 'ohos'))
    [void][IO.Directory]::CreateDirectory((Join-Path $project 'lib'))
    [IO.File]::WriteAllText((Join-Path $project 'lib/main.dart'),'existing business source')
    [IO.File]::WriteAllText((Join-Path $project 'pubspec.yaml'),"name: fixture`nenvironment:`n  sdk: '>=3.10.0 <4.0.0'`n  flutter: '>=3.38.0'`ndependencies:`n  flutter:`n    sdk: flutter`n")
    [IO.File]::WriteAllText((Join-Path $project 'ohos/hvigorw.bat'),'fixture')
    try{
        foreach($relative in @('JobsFlutterRunner/Scripts','JobsFlutterTools/Scripts/Actions/run/Scripts')){
            $scripts=Join-Path $root $relative
            $entry=Join-Path $scripts 'RunPreflight.ps1/PrepareHarmonyRun.ps1/PrepareHarmonyRun.ps1'
            $core=Import-Module (Join-Path (Split-Path -Parent $entry) 'Core/HarmonySdk.psm1') -PassThru -DisableNameChecking
            $choices=@(&$core {Get-JobsHarmonyTagChoices ((('a'*40)+"`trefs/tags/3.41.9+ohos-1.0.2`n")+(('b'*40)+"`trefs/tags/3.47.7+ohos-0.0.1-pre`n"))})
            Assert-Prepare ($choices[0].Ref-ceq'3.41.9+ohos-1.0.2'-and-not$choices[0].Prerelease-and$choices[1].Prerelease) '随包管理器将正式鸿蒙tag排在预览版前'
            Remove-Module $core
            foreach($revisionChanged in @($false,$true)){
                $module=New-Module -ScriptBlock {
                    param($Helper,$Entry,$Root,$RevisionChanged)
                    . $Helper
                    . $Entry
                    $script:RevisionChanged=$RevisionChanged
                    $manager=New-Module -ScriptBlock {
                        param($Root)
                        $script:Root=$Root
                        function Get-JobsInstallRoot {return $script:Root}
                        function Get-JobsProjectFvmConfig {return [pscustomobject]@{flutter='old-version';UserSetting='keep'}}
                    } -ArgumentList $Root
                    $harmony=New-Module -ScriptBlock {
                        param($Root,$Manager)
                        $script:Root=$Root;$script:HarmonyManager=$Manager;$script:HarmonyRepository='https://gitcode.com/CPF-Flutter/flutter_flutter.git';$script:Published=$null
                        function Assert-JobsHarmonyBindingPaths {}
                        function Get-JobsHarmonyCache {return $script:Root}
                        function Get-JobsHarmonyBindingStamp {return 'stamp'}
                        function Invoke-JobsHarmonyGit {return 'fixture refs'}
                        function Get-JobsHarmonyTagChoices {return [pscustomobject]@{Ref='3.41.9+ohos-1.0.2';Commit=('a'*40);Version=('custom_jobs_ohos_'+('a'*40));BaseVersion=[version]'3.41.9';Prerelease=$false}}
                        function Resolve-JobsHarmonyCommit {return ('a'*40)}
                        function Install-JobsHarmonySdk {return (Join-Path $script:Root 'candidate')}
                        function Assert-JobsHarmonySdk {}
                        function Publish-JobsHarmonyBinding {param($Project,$Sdk,$Config,$Stamp)$script:Published=$Config|ConvertFrom-Json}
                    } -ArgumentList $Root,$manager
                    $script:JobsPrepareCore=[pscustomobject]@{Harmony=$harmony;Tools='fixture'}
                    function script:Find-JobsExecutable {return 'git.exe'}
                    function script:ConvertFrom-JobsSdkMachineOutput {param($Text)return $Text|ConvertFrom-Json}
                    function script:Invoke-JobsRunnerTool {param($Flutter,$Arguments)
                        if($Arguments[0]-ceq'build'){return 'hap build help'}
                        $revision=if($script:RevisionChanged){'c'*40}else{'a'*40}
                        return @{frameworkVersion='3.41.9';dartSdkVersion='3.11.0';frameworkRevision=$revision}|ConvertTo-Json -Compress
                    }
                    function script:Invoke-JobsRunnerReadOnlyTool {return 'apk only'}
                    function script:Test-JobsPrepareCompatibility {return [pscustomobject]@{compatible=$true;projectName='fixture';reason=''}}
                } -ArgumentList (Join-Path $scripts 'RunPreflight.ps1/RunPreflight.ps1'),$entry,(Join-Path $temporary ([guid]::NewGuid().ToString('N'))),$revisionChanged
                $failed=$false;$selected=$null
                try{$selected=&$module {param($Project)Initialize-JobsPrepareSdk '/fixture/bin/flutter.bat' $Project} $project}catch{$failed=$true;if(-not$revisionChanged){Write-Host $_.Exception.Message;Write-Host $_.ScriptStackTrace}}
                $published=&$module {&$script:JobsPrepareCore.Harmony {$script:Published}}
                if($revisionChanged){Assert-Prepare ($failed-and$null-eq$published) 'SDK实际commit改变时不发布项目绑定'}
                else{
                    Assert-Prepare (-not$failed-and$selected.Flutter-like'*/candidate/bin/flutter.bat') '真实自动选版函数通过闭包复用SDK管理器，无交互总入口'
                    Assert-Prepare ($published.UserSetting-ceq'keep'-and$published.flutter-ceq('custom_jobs_ohos_'+('a'*40))) '自动绑定仍保留用户已有FVM配置字段'
                    &$module {
                        function script:Invoke-JobsRunnerReadOnlyTool {return 'hap help'}
                        &$script:JobsPrepareCore.Harmony {$script:Published=$null;function script:Install-JobsHarmonySdk {throw 'same commit must not install'}}
                    }
                    $reused=&$module {param($Project)Initialize-JobsPrepareSdk '/fixture/bin/flutter.bat' $Project -RefreshCompatible} $project
                    Assert-Prepare ($reused.Flutter-ceq'/fixture/bin/flutter.bat') '启动前刷新正式候选后可复用已核验同commit的当前兼容SDK'
                    Assert-Prepare ($null-eq(&$module {&$script:JobsPrepareCore.Harmony {$script:Published}})) '同commit不重装缓存、不重复发布项目绑定或生成备份'

                }
                &$module {Remove-Module $script:JobsPrepareCore.Harmony}
                Remove-Module $module
            }
            foreach($scenario in @('success','openharmony','plugins','license','identity','impostor','health')){
                $module=New-Module -ScriptBlock {
                    param($Helper,$Entry,$Scenario)
                    Set-StrictMode -Version 2.0
                    . $Helper
                    . $Entry
                    $script:Scenario=$Scenario
                    $script:Calls=[Collections.Generic.List[string]]::new()
                    function script:Import-JobsPrepareCore {$script:Calls.Add('core');return [pscustomobject]@{Harmony='fixture';Tools='fixture'}}
                    function script:Initialize-JobsPrepareSdk {$script:Calls.Add('sdk');return [pscustomobject]@{Flutter='prepared-flutter';ProjectName='fixture'}}
                    function script:Invoke-JobsRunnerTool {param($Flutter,$Arguments)$script:Calls.Add(($Arguments-join' '));return ''}
                    function script:Initialize-JobsPrepareTools { $script:Calls.Add('tools');$env:TOOL_HOME='prepared-tools';$env:JAVA_HOME='prepared-java';if($script:Scenario-ceq'license'){throw [OperationCanceledException]::new('license cancelled')};return [pscustomobject]@{Ohpm='fixture-ohpm'} }
                    function script:New-JobsPrepareOhosPlatform {$script:Calls.Add('platform')}
                    function script:Invoke-JobsPrepareProcess {param($File,$Arguments)$script:Calls.Add(($Arguments-join' '));return [pscustomobject]@{ExitCode=0;StdOut='';StdErr=''}}
                    function script:Assert-JobsRunnerProjectPackages {$script:Calls.Add('plugins');if($script:Scenario-ceq'plugins'){throw "原生插件尚未声明 ohos 支持：`n- company_plugin`n- vendor_plugin"}}
                    function script:Get-JobsRunnerPreflight {$script:Calls.Add('health');return @{base=@{State='ready'};ohos=@{State='ready'}}}
                    function script:Write-JobsRunnerPreflight {}
                    function script:Assert-JobsRunnerPreflight {if($script:Scenario-ceq'health'){throw 'fixture health failed'}}
                    function script:Wait-JobsPreparedHarmonyDevice {param($Flutter,$Project,$Identity)$script:Calls.Add('wait:'+$Identity);if($script:Scenario-ceq'identity'){throw '原设备不在清单'};$id=if($script:Scenario-ceq'impostor'){'other-phone'}else{$Identity};$platform=if($script:Scenario-ceq'openharmony'){'openharmony-arm64'}else{'ohos-arm64'};return [pscustomobject]@{id=$id;targetPlatform=$platform}}
                } -ArgumentList (Join-Path $scripts 'RunPreflight.ps1/RunPreflight.ps1'),$entry,$scenario
                $beforeHome=[Environment]::GetEnvironmentVariable('TOOL_HOME','Process')
                $beforeJava=[Environment]::GetEnvironmentVariable('JAVA_HOME','Process')
                $failed=$false;$result=$null
                try{$result=&$module {param($Project)Invoke-JobsPrepareHarmonyPipeline 'original-flutter' $Project 'USB\VID_12D1&PID_1101\original-phone'} $project}catch{$failed=$true}
                $calls=@(&$module {$script:Calls.ToArray()})
                Assert-Prepare ([Environment]::GetEnvironmentVariable('TOOL_HOME','Process')-ceq$beforeHome-and[Environment]::GetEnvironmentVariable('JAVA_HOME','Process')-ceq$beforeJava) '成功、失败和许可取消均精确恢复父进程环境'
                Assert-Prepare (@($calls|Where-Object{$_-ceq'sdk'}).Count-eq1) '准备失败不会整体重放SDK或项目发布阶段'
                Assert-Prepare (($calls-join'|')-notmatch'(^|\|)(run|.*imageList|.*create.*avd|.*-start)(\||$)') '环境准备不启动应用、创建模拟器或下载镜像'
                if($scenario-in@('success','openharmony')){
                    Assert-Prepare (-not$failed-and$result.DeviceId-ceq'original-phone'-and$result.DiagnosticKey-ceq'USB\VID_12D1&PID_1101\original-phone'-and$result.Flutter-ceq'prepared-flutter') '成功返回新SDK及原设备，不改选其它HDC目标'
                    Assert-Prepare ($result.Environment.TOOL_HOME-ceq'prepared-tools'-and$result.Environment.JAVA_HOME-ceq'prepared-java') '返回环境只用于后续当前运行子进程'
                    Assert-Prepare (($calls-join'|')-ceq'core|sdk|precache --universal|tools|platform|precache --ohos|pub get|plugins|install|--sync|health|wait:original-phone') 'SDK、CLT、平台、Flutter/原生依赖和复检按依赖顺序仅执行一次'
                }else{
                    Assert-Prepare $failed '永久缺项或取消不能返回准备成功'
                    if($scenario-ceq'plugins'){Assert-Prepare (($calls-join'|')-notmatch'\|install|\|--sync|\|wait:') '公司/供应商插件缺实现时停止，不运行或伪造适配'}
                    if($scenario-ceq'license'){Assert-Prepare (($calls-join'|')-notmatch'platform|pub get|plugins|wait:') '许可取消后不生成平台、不拉依赖、不运行'}
                    if($scenario-ceq'health'){Assert-Prepare (($calls-join'|')-notmatch'wait:') '准备后体检未通过时不进入设备运行等待'}
                }
                Remove-Module $module
            }
            # 使用真实原子目录发布函数，只替换临时工程生成命令。
            $module=New-Module -ScriptBlock {
                param($Entry)
                . $Entry
                $script:Calls=0
                function script:Invoke-JobsPrepareProcess {
                    param($File,$Arguments,$Directory)
                    $script:Calls++
                    [void][IO.Directory]::CreateDirectory((Join-Path $Directory 'ohos/AppScope'))
                    [void][IO.Directory]::CreateDirectory((Join-Path $Directory 'lib'))
                    foreach($file in @('build-profile.json5','oh-package.json5','AppScope/app.json5')){[IO.File]::WriteAllText((Join-Path $Directory ('ohos/'+$file)),'generated')}
                    [IO.File]::WriteAllText((Join-Path $Directory 'lib/main.dart'),'generated default source')
                }
            } -ArgumentList $entry
            $fresh=Join-Path $temporary ([guid]::NewGuid().ToString('N'))
            [void][IO.Directory]::CreateDirectory((Join-Path $fresh 'lib'))
            [IO.File]::WriteAllText((Join-Path $fresh 'lib/main.dart'),'original business')
            &$module {param($Project)New-JobsPrepareOhosPlatform 'fixture-flutter' $Project 'fixture'} $fresh
            Assert-Prepare ([IO.File]::ReadAllText((Join-Path $fresh 'lib/main.dart'))-ceq'original business'-and[IO.File]::Exists((Join-Path $fresh 'ohos/AppScope/app.json5'))) '临时生成只原子发布ohos，业务lib保持逐字不变'
            &$module {param($Project)New-JobsPrepareOhosPlatform 'fixture-flutter' $Project 'fixture'} $fresh
            Assert-Prepare ((&$module {$script:Calls})-eq1) '已有ohos保留，不重复生成或覆盖'
            Remove-Module $module
            # HDC与Flutter必须共同确认精确原ID；清单中的其它设备不能替代。
            $module=New-Module -ScriptBlock {
                param($Entry)
                . $Entry
                function script:Get-JobsRunnerHdcExecutable {return 'hdc'}
                function script:Invoke-JobsRunnerReadOnlyTool {return "other-phone`noriginal-phone"}
                function script:Invoke-JobsRunnerTool {return 'fixture'}
                function script:ConvertFrom-JobsRunnerList {return @([pscustomobject]@{id='other-phone';targetPlatform='ohos-arm64'},[pscustomobject]@{id='original-phone';targetPlatform='ohos-arm64'})}
                function script:Get-JobsRunnerSupportedDevices {param($Devices,$Project)return $Devices}
            } -ArgumentList $entry
            $device=&$module {param($Project)Wait-JobsPreparedHarmonyDevice 'flutter' $Project 'original-phone' 1} $project
            Assert-Prepare ($device.id-ceq'original-phone') '多个可用设备中仍精确匹配最初选择的设备'
            $failed=$false
            try{&$module {param($Project)Wait-JobsPreparedHarmonyDevice 'flutter' $Project 'absent-phone' 0} $project}catch{$failed=$true}
            Assert-Prepare $failed '原设备缺失不回退到其它手机'
            Remove-Module $module
        }
        if($Dart-and$Packages){
            $checker=Join-Path $root 'JobsFlutterRunner/Scripts/RunPreflight.ps1/PrepareHarmonyRun.ps1/SdkCompatibility.dart'
            $output=&$Dart '--disable-dart-dev' ('--packages='+$Packages) $checker $project sdk '3.41.9' '3.11.0'
            Assert-Prepare ($LASTEXITCODE-eq0-and($output|ConvertFrom-Json).compatible) '真实pub_semver/YAML接受兼容正式版本'
            $output=&$Dart '--disable-dart-dev' ('--packages='+$Packages) $checker $project sdk '3.35.7' '3.9.0'
            Assert-Prepare ($LASTEXITCODE-eq1-and-not($output|ConvertFrom-Json).compatible) '真实pub_semver/YAML拒绝过旧Flutter/Dart版本'
        }
        Write-Host ('PASS: HarmonyRunPrepare ('+$script:Checks+' assertions; no real downloads, binding or app run)')
    }finally{if([IO.Directory]::Exists($temporary)){[IO.Directory]::Delete($temporary,$true)}}
}

Invoke-PrepareTests

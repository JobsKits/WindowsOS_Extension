# FlutterRunnerVirtualStart.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年11月12日，星期四.
# 真实菜单/启动编排配临时实例与假外部边界；不联网、不安装、不启动真实模拟器或App。
[CmdletBinding()]
param([switch]$BoundaryOnly)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('JobsVirtualStart-'+[guid]::NewGuid().ToString('N'))
if($temporary.StartsWith('/var/')-and[IO.Directory]::Exists('/private/var')){$temporary='/private'+$temporary}
$script:Checks=0
function Assert-Virtual {param([bool]$Value,[string]$Message)if(-not$Value){throw ('FAIL: '+$Message)};$script:Checks++}
function New-VirtualSdkListing {
    param([switch]$TargetUpdates,[switch]$OtherUpdates,[switch]$UpdatedTargets)
    $emulator=if($UpdatedTargets){'36.2.0'}else{'35.1.0'}
    $platform=if($UpdatedTargets){'36.0.0'}else{'35.0.0'}
    $emulatorRemote=if($TargetUpdates-or$UpdatedTargets){'36.2.0'}else{$emulator}
    $platformRemote=if($TargetUpdates-or$UpdatedTargets){'36.0.0'}else{$platform}
    $otherRemote=if($OtherUpdates){'2'}else{'1'}
    $listing=@(
        'Installed packages:', 'Path | Version | Description | Location', '------- | ------- | ------- | -------',
        ('emulator | '+$emulator+' | Android Emulator | emulator'), ('platform-tools | '+$platform+' | Android SDK Platform-Tools | platform-tools'),
        'platforms;android-36 | 1 | Android SDK Platform 36 | platforms/android-36', 'ndk;28.0 | 1 | NDK | ndk/28.0',
        'Available Packages:', 'Path | Version | Description', '------- | ------- | -------',
        ('emulator | '+$emulatorRemote+' | Android Emulator'), ('platform-tools | '+$platformRemote+' | Android SDK Platform-Tools'),
        ('platforms;android-36 | '+$otherRemote+' | Android SDK Platform 36'), ('ndk;28.0 | '+$otherRemote+' | NDK')
    )
    if($TargetUpdates-or$OtherUpdates){
        $listing+=@('Available Updates:','ID | Installed | Available','------- | ------- | -------')
        if($TargetUpdates){$listing+=@(('emulator | '+$emulator+' | '+$emulatorRemote),('platform-tools | '+$platform+' | '+$platformRemote))}
        if($OtherUpdates){$listing+=@('platforms;android-36 | 1 | 2','ndk;28.0 | 1 | 2')}
    }
    return ($listing-join"`n")+"`n"
}

function Test-VirtualMetadataAndMenuBoundaries {
    param([string]$Path)
    $public=[pscustomobject]@{code=0;value=[pscustomobject]@{status=4;content=[pscustomobject]@{content='<h4>DevEco Studio 6.1.1 Release (6.1.1.300)</h4><table><caption>Command line tools</caption><tr><td>Command Line</td><td>6.1.1.300</td></tr><tr><td>Emulator</td><td>6.1.1.350</td></tr></table>'}}}
    foreach($scenario in @('timeout','task-timeout','dns','408','429','503','401','403','permanent','auth','html','schema','cancel-request','cancel-backoff')) {
        $module=Import-Module $Path -Force -PassThru -DisableNameChecking
        try {
            $failure=$null
            if($scenario-eq'timeout'-or$scenario-eq'cancel-backoff'){$failure=New-Object TimeoutException('HTTP attempt timed out')}
            elseif($scenario-eq'task-timeout'){$failure=New-Object Threading.Tasks.TaskCanceledException('HTTP request canceled by HttpClient.Timeout',(New-Object TimeoutException('HTTP timeout')))}
            elseif($scenario-eq'dns'){$failure=New-Object Net.WebException('DNS fixture',$null,[Net.WebExceptionStatus]::NameResolutionFailure,$null)}
            elseif($scenario-match'^\d+$'){$failure=New-Object Exception('HTTP fixture');$failure|Add-Member NoteProperty Response ([pscustomobject]@{StatusCode=[int]$scenario;Headers=@{'Retry-After'='4'}})}
            elseif($scenario-eq'permanent'){$failure=New-Object ArgumentException('invalid native HTTP argument')}
            elseif($scenario-eq'cancel-request'){$failure=New-Object OperationCanceledException('本人取消')}
            &$module {
                param($Failure,$Scenario,$Public)
                $script:MetadataFailure=$Failure;$script:MetadataScenario=$Scenario;$script:MetadataPublic=$Public
                $script:MetadataCalls=0;$script:MetadataSleeps=0;$script:MetadataTimeouts=@();$script:MetadataHeaders=@()
                function script:Invoke-RestMethod {
                    param($Uri,$Method,$ContentType,$Body,$Headers,$TimeoutSec)
                    $script:MetadataCalls++;$script:MetadataTimeouts+=,$TimeoutSec
                    if($Headers){$script:MetadataHeaders+=,$Headers}
                    if($script:MetadataCalls-eq1-and$null-ne$script:MetadataFailure){throw $script:MetadataFailure}
                    if($script:MetadataScenario-eq'auth'){return [pscustomobject]@{returnCode='90910011'}}
                    if($script:MetadataScenario-eq'html'){return '<html>official login required</html>'}
                    if($script:MetadataScenario-eq'schema'){return [pscustomobject]@{unknown='schema'}}
                    if($Uri-like'*getCenterDocument'){return $script:MetadataPublic}
                    return [pscustomobject]@{code='00000';value=[pscustomobject]@{downloadUrl='https://example.invalid/unused'}}
                }
                function script:Start-Sleep {
                    param($Seconds)
                    if($Seconds-ne1){throw 'backoff must remain cancellable in one-second chunks'}
                    $script:MetadataSleeps++
                    if($script:MetadataScenario-eq'cancel-backoff'){throw (New-Object OperationCanceledException('本人取消等待'))}
                }
            } $failure $scenario $public
            $failed=$false;$canceled=$false;$answer=$null
            try {
                if($scenario-in@('timeout','task-timeout','schema')){$answer=&$module {Get-JobsRunnerHarmonyPublicRelease}}
                elseif($scenario-in@('auth','html')){$answer=&$module {Get-JobsRunnerHarmonyOfficialUpdate}}
                elseif($scenario-eq'dns'){$answer=&$module {Invoke-JobsRunnerHarmonyOfficialService 'getToolVersionList' @{toolAlias='command-line-tools-for-hmos';language='cn'}}}
                else{$answer=&$module {Invoke-JobsRunnerHarmonyOfficialService 'getToolVersionDownloadUrl' @{versionId='fixture';sdkId='fixture';packageId='fixture'}}}
            }catch [OperationCanceledException]{$failed=$true;$canceled=$true}catch{$failed=$true}
            $state=&$module {[pscustomobject]@{Calls=$script:MetadataCalls;Sleeps=$script:MetadataSleeps;Timeouts=$script:MetadataTimeouts;Headers=$script:MetadataHeaders}}
            if($scenario-in@('timeout','task-timeout','dns','408','429','503')) {
                Assert-Virtual (-not$failed-and$state.Calls-eq2-and$state.Sleeps-ge2) ($scenario+'瞬时原生HTTP失败自动重入后成功，不要求手动重试')
                Assert-Virtual (@($state.Timeouts|Where-Object{$_-ne20}).Count-eq0) '每次原生HTTP请求均20秒有界，不重放业务安装或启动'
                if($scenario-in@('timeout','task-timeout')){Assert-Virtual ($answer.Version-ceq'6.1.1.300') 'PS7 timeout后仍经真实Release正文解析，忽略Emulator版本'}
                if($scenario-eq'429'){Assert-Virtual ($state.Sleeps-eq4) 'HTTP429按Retry-After分片等待并可取消'}
                if($scenario-eq'dns'){Assert-Virtual ($state.Headers.Count-eq2-and$state.Headers[0]['X-HD-SERIALNO']-cne$state.Headers[1]['X-HD-SERIALNO']) '目录/URL原生重试重新生成官方请求头'}
            }elseif($scenario-in@('auth','html')) {
                Assert-Virtual (-not$failed-and$answer.State-ceq'Blocked'-and$state.Calls-eq1-and$state.Sleeps-eq0) ($scenario+'授权/HTML响应立即未就绪，不网络重试')
            }elseif($scenario-in@('cancel-request','cancel-backoff')) {
                Assert-Virtual ($failed-and$canceled-and$state.Calls-eq1) ($scenario+'本人取消立即透传，不再次请求/安装/启动')
                Assert-Virtual ($state.Sleeps-eq$(if($scenario-eq'cancel-backoff'){1}else{0})) '取消不被错误归类为网络故障'
            }else {
                Assert-Virtual ($failed-and$state.Calls-eq1-and$state.Sleeps-eq0) ($scenario+'HTTP授权/本地参数/正文schema错误立即失败')
            }
        }finally{Remove-Module $module}
    }

    $module=Import-Module $Path -Force -PassThru -DisableNameChecking
    $savedMode=$env:JOBS_FLUTTER_RUNNER_FZF
    try {
        $env:JOBS_FLUTTER_RUNNER_FZF=$null
        &$module {
            $script:MenuInteractive=$true;$script:MenuFzf=$null;$script:MenuHealthy=$true;$script:TextReads=0
            function script:Test-JobsRunnerInteractiveMenu {return $script:MenuInteractive}
            function script:Find-JobsExecutable {return $script:MenuFzf}
            function script:Invoke-JobsProcess {return [pscustomobject]@{ExitCode=$(if($script:MenuHealthy){0}else{1});StdOut='--bind --expect'}}
            function script:Read-JobsRunnerInput {$script:TextReads++;return 'b'}
            function script:Invoke-VirtualFzf {$script:FzfArguments=@($args);$global:LASTEXITCODE=130;return 'left'}
        }
        $failed=$false;try{&$module {Select-JobsRunnerChoice 'missing' @('Original') -Back}|Out-Null}catch{$failed=$_.Exception.Message-like'*fzf*'}
        Assert-Virtual ($failed-and(&$module {$script:TextReads})-eq0) '正常交互fzf缺失明确失败，不静默转数字菜单'
        &$module {$script:MenuFzf='Invoke-VirtualFzf';$script:MenuHealthy=$false}
        $failed=$false;try{&$module {Select-JobsRunnerChoice 'broken' @('Original') -Back}|Out-Null}catch{$failed=$_.Exception.Message-like'*fzf*'}
        Assert-Virtual ($failed-and(&$module {$script:TextReads})-eq0) '正常交互fzf损坏明确失败，不静默转数字菜单'
        $env:JOBS_FLUTTER_RUNNER_FZF='0'
        Assert-Virtual ((&$module {Select-JobsRunnerChoice 'explicit text' @('Original') -Back}).Kind-ceq'Back') '本人显式关闭fzf时文本菜单可返回'
        $env:JOBS_FLUTTER_RUNNER_FZF=$null
        &$module {$script:MenuInteractive=$false}
        Assert-Virtual ((&$module {Select-JobsRunnerChoice 'redirected text' @('Original') -Back}).Kind-ceq'Back') '非交互/输入重定向的文本菜单可返回'
        &$module {$script:MenuInteractive=$true;$script:MenuHealthy=$true}
        Assert-Virtual ((&$module {Select-JobsRunnerChoice 'keys' @('Original') -Back}).Kind-ceq'Back') 'fzf空匹配/退出130前处理显式左键返回'
        $arguments=&$module {$script:FzfArguments-join' '}
        Assert-Virtual ($arguments-match'up:up,down:down,left:accept'-and$arguments-match'--expect=left') '明确绑定上下选择和左键返回'
    }finally{$env:JOBS_FLUTTER_RUNNER_FZF=$savedMode;Remove-Module $module}
}

[void][IO.Directory]::CreateDirectory($temporary)
try {
    foreach($relative in @('JobsFlutterRunner/Scripts/Action.psm1','JobsFlutterTools/Scripts/Actions/run/Scripts/Action.psm1')) {
        $path=Join-Path $root $relative
        Test-VirtualMetadataAndMenuBoundaries $path
        if($BoundaryOnly){continue}
        $module=Import-Module $path -Force -PassThru -DisableNameChecking
        Assert-Virtual ((&$module {(Get-Command Get-JobsAndroidSdk).ScriptBlock.File})-like'*AndroidRuntime.ps1') '两份运行器均随包携带真实Android启动工具能力，不能依赖测试mock或兄弟目录'
        $complete=New-VirtualSdkListing
        $updatesReport=New-VirtualSdkListing -TargetUpdates -OtherUpdates
        $afterReport=New-VirtualSdkListing -UpdatedTargets -OtherUpdates
        $invalidReports=@('', 'not-a-catalog', '<html>login</html>', "Installed packages:`nAvailable Packages:`n", ($complete+"Warning: Failed to fetch repository`n"),
            ($complete.Replace('Installed packages:','Available Packages:')), ($complete+"Available Packages:`n"),
            ($complete.Replace('Path | Version | Description | Location','Path | Version')), ($complete.Replace('------- | ------- | ------- | -------','broken')),
            ($complete.Replace('emulator | 35.1.0','Emulator | 35.1.0')), ($complete.Replace('35.1.0','35.1.0-rc1')),
            ($updatesReport -replace '(?s)Available Updates:.*$',''), ($updatesReport.Replace('emulator | 35.1.0 | 36.2.0','emulator | 35.1.0 | 36.2.0 | injected')),
            ($updatesReport.Replace('platforms;android-36 | 1 | 2','platforms;android-36 | broken')), ($complete+"Available Updates:`nID | Installed | Available`n--- | --- | ---`n"),
            ($updatesReport.Replace('emulator | 35.1.0 | 36.2.0','emulator | 35.1.0 | 35.1.0')), ($complete+"Still waiting for package manifests...`n"))
        foreach($invalid in $invalidReports) {
            $failed=$false
            try { &$module {param($Listing) @(Get-JobsRunnerAndroidStableUpdates $Listing)} $invalid | Out-Null } catch { $failed=$true }
            Assert-Virtual $failed '空/截断/错序/缺表/预览或版本矛盾目录不能冒充无更新'
        }
        Assert-Virtual ((@(&$module {param($Listing) Get-JobsRunnerAndroidStableUpdates $Listing} $complete)).Count-eq0) '真实完整正式表格没有Updates节可确认无更新'
        Assert-Virtual ((@(&$module {param($Listing) Get-JobsRunnerAndroidStableUpdates $Listing} $updatesReport)-join'|')-ceq'emulator|platform-tools') '交叉核对三表版本后只返回启动组件'
        & $module {
            param($BeforeReport,$AfterReport)
            $script:Calls=[Collections.Generic.List[string]]::new();$script:Updated=$false;$script:BeforeReport=$BeforeReport;$script:AfterReport=$AfterReport
            function script:Get-JobsAndroidArchitecture {return 'x64'}
            function script:Get-JobsAndroidSdk {return '/fixture/sdk'}
            function script:Get-JobsAndroidJava {return '/fixture/java/bin/java.exe'}
            function script:Get-JobsAndroidHealthyTools {return '/fixture/tools'}
            function script:Repair-JobsAndroidComponents {$script:Calls.Add('repair')}
            function script:Get-JobsAndroidUnhealthyComponents {return @()}
            function script:Invoke-JobsRunnerReadOnlyTool {param($File,$Arguments)$script:Calls.Add(($Arguments-join' '));return 'healthy'}
            function script:Invoke-JobsAndroidTool {
                param($Java,$Tools,$Tool,$Arguments,[switch]$IncludeStandardError)
                $script:Calls.Add(($Arguments-join' '))
                if($Arguments-contains'--install'){$script:Updated=$true}
                if($Arguments-contains'--list'){
                    if(-not$IncludeStandardError){throw 'metadata stderr was discarded'}
                    if($script:Updated){return $script:AfterReport};return $script:BeforeReport
                }
            }
        } $updatesReport $afterReport
        $snapshot=&$module {Get-JobsRunnerTaskEnvironmentSnapshot @('PATH','JAVA_HOME','ANDROID_HOME','ANDROID_SDK_ROOT')}
        try { $sdk=&$module {Initialize-JobsRunnerVirtualAndroid '/fixture/project'} }
        finally { &$module {param($Snapshot)Restore-JobsRunnerTaskEnvironment $Snapshot} $snapshot }
        $calls=@(&$module {$script:Calls.ToArray()})
        Assert-Virtual ($sdk-ceq'/fixture/sdk'-and($calls-join'|')-match'--install --channel=0 --sdk_root=/fixture/sdk emulator platform-tools') '只更新当前SDK的正式emulator/ADB组件'
        Assert-Virtual (($calls-join'|')-notmatch'--update|--install.*platforms;|--install.*ndk;|-create') '不全局升级、不改项目平台或创建实例'
        Assert-Virtual (($calls-join'|')-match'--licenses'-and($calls-join'|')-match'-accel-check') '保留本人许可与启动前硬件加速体检'
        Remove-Module $module

        $module=Import-Module $path -Force -PassThru -DisableNameChecking
        try {
            &$module {
                param($Report)
                $script:Report=$Report;$script:LiveCalls=0
                function script:Invoke-JobsSdkAcquire {param($Label,$Operation) return &$Operation}
                function script:Invoke-JobsSdkLiveProcess {$script:LiveCalls++;return [pscustomobject]@{ExitCode=0;StdOut=$script:Report;StdErr='Warning: Errors during XML parse: repository is invalid'}}
            } $complete
            $output=&$module {Invoke-JobsAndroidTool 'java.exe' '/fixture/tools' 'sdkmanager' @('--list') -IncludeStandardError}
            $failed=$false;try{&$module {param($Report)Get-JobsRunnerAndroidStableUpdates $Report} $output|Out-Null}catch{$failed=$true}
            Assert-Virtual ($failed-and$output.Contains('Errors during XML parse')) '真实Runtime的exit0错误stderr仍进入正式目录门禁'
            $legacy=&$module {Invoke-JobsAndroidTool 'java.exe' '/fixture/tools' 'sdkmanager' @('--list')}
            Assert-Virtual ($legacy-ceq$complete) '未请求stderr时旧工具调用的StdOut返回语义保持'
            $nativeSource=&$module {(${function:Get-JobsRunnerFileIdentity}).Ast.FindAll({param($node)$node-is[Management.Automation.Language.StringConstantExpressionAst]-and$node.Value.StartsWith('using System;')},$true)|Select-Object -First 1}
            if(-not('JobsRunnerNative.FileIdentity'-as[type])){Add-Type -TypeDefinition $nativeSource.Value}
            Assert-Virtual ($null-ne('JobsRunnerNative.FileIdentity'-as[type]).GetMethod('Read')) '原生卷号/FileIdInfo提供器在当前CLR完成C#语法编译，未调用Windows DLL'
        } finally {Remove-Module $module}

        foreach($failureKind in @('xml','headers-only','invalid-option')) {
            $module=Import-Module $path -Force -PassThru -DisableNameChecking
            try {
                &$module {
                    param($Report,$FailureKind)
                    $script:Report=$Report;$script:FailureKind=$FailureKind;$script:LiveCalls=0
                    function script:Write-JobsSdkRetryMessage {}
                    function script:Start-Sleep {throw 'deterministic metadata failure retried'}
                    function script:Invoke-JobsSdkLiveProcess {
                        $script:LiveCalls++
                        if($script:FailureKind-ceq'invalid-option'){return [pscustomobject]@{ExitCode=1;StdOut='';StdErr='Error: invalid option --unsupported'}}
                        if($script:FailureKind-ceq'headers-only'){return [pscustomobject]@{ExitCode=0;StdOut="Installed packages:`nAvailable Packages:`n";StdErr=''}}
                        return [pscustomobject]@{ExitCode=0;StdOut=$script:Report;StdErr='Warning: Errors during XML parse: invalid repository'}
                    }
                } $complete $failureKind
                $failed=$false
                try {
                    &$module {
                        $report=Invoke-JobsAndroidTool 'java.exe' '/fixture/tools' 'sdkmanager' @('--list') -IncludeStandardError
                        Get-JobsRunnerAndroidStableUpdates $report
                    } | Out-Null
                } catch { $failed=$true }
                Assert-Virtual ($failed-and(&$module {$script:LiveCalls})-eq1) '真实获取重试核心遇确定目录/参数错误只查询一次并停止'
            } finally {Remove-Module $module}
        }

        foreach($scenario in @('success','cancel','back','missing','wait-failed','identity','selection-identity','selection-object','wait-identity','wait-id','wait-portreuse','boot-dynamic')) {

            $FixtureRoot=Join-Path $temporary ([guid]::NewGuid().ToString('N'))
            $avd=Join-Path $FixtureRoot 'Original.avd';[void][IO.Directory]::CreateDirectory($avd)
            $sdk=Join-Path $FixtureRoot 'sdk';$image=Join-Path $sdk 'system-images/android-35/google_apis/x86_64';[void][IO.Directory]::CreateDirectory($image)
            [IO.File]::WriteAllText((Join-Path $FixtureRoot 'Original.ini'),'path='+$avd+"`n")
            [IO.File]::WriteAllText((Join-Path $avd 'config.ini'),"AvdId=Original`nimage.sysdir.1=system-images/android-35/google_apis/x86_64/`n")
            [IO.File]::WriteAllText((Join-Path $image 'package.xml'),'fixture');[IO.File]::WriteAllText((Join-Path $image 'system.img'),'fixture')
            $module=Import-Module $path -Force -PassThru -DisableNameChecking
            & $module {
                param($Scenario,$FixtureRoot,$Sdk)
                $script:Scenario=$Scenario;$script:FixtureRoot=$FixtureRoot;$script:Sdk=$Sdk;$script:Starts=0;$script:Created=0;$script:IdentityReads=0;$script:ObjectGeneration=1
                function script:Initialize-JobsRunnerVirtualAndroid {$env:JAVA_HOME='temporary-java';return $script:Sdk}
                function script:Get-JobsAndroidAvdHome {return $script:FixtureRoot}
                function script:Get-JobsRunnerFileIdentity {param($Path)return ($Path+'|file-object-'+$script:ObjectGeneration)}
                function script:Get-JobsRunnerAvds {if($script:Scenario-ceq'missing'){return @()};return @('Original','Other')}
                function script:Select-JobsRunnerChoice {
                    if($script:Scenario-ceq'cancel'){return $null}
                    if($script:Scenario-ceq'back'){return [pscustomobject]@{Kind='Back';Index=-1}}
                    if($script:Scenario-ceq'selection-identity'){
                        $replacement=Join-Path $script:FixtureRoot 'Replacement.avd'
                        [void][IO.Directory]::CreateDirectory($replacement)
                        [IO.File]::Copy((Join-Path $script:FixtureRoot 'Original.avd/config.ini'),(Join-Path $replacement 'config.ini'))
                        [IO.File]::WriteAllText((Join-Path $script:FixtureRoot 'Original.ini'),('path='+$replacement+"`n"))
                    }
                    if($script:Scenario-ceq'selection-object'){
                        $configPath=Join-Path $script:FixtureRoot 'Original.avd/config.ini';$iniPath=Join-Path $script:FixtureRoot 'Original.ini'
                        $configBytes=[IO.File]::ReadAllBytes($configPath);$iniBytes=[IO.File]::ReadAllBytes($iniPath)
                        [IO.Directory]::Delete((Split-Path -Parent $configPath),$true);[IO.File]::Delete($iniPath)
                        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $configPath))
                        [IO.File]::WriteAllBytes($configPath,$configBytes);[IO.File]::WriteAllBytes($iniPath,$iniBytes)
                        $script:ObjectGeneration=2
                    }
                    return [pscustomobject]@{Kind='Selected';Index=0}
                }
                function script:Start-JobsAndroidAvd {param($Sdk,$Name)if($Name-cne'Original'){throw 'wrong AVD'};$script:Starts++;return 'emulator-5568'}
                function script:Test-JobsAndroidBoot {param($Adb,$Serial,$Name)if($Serial-cne'emulator-5568'-or$Name-cne'Original'){throw 'wrong final instance'};return $script:Scenario-cne'wait-portreuse'}
                function script:New-JobsRunnerSimulator {$script:Created++;throw 'never create'}
                function script:Wait-JobsRunnerSelectedDevice {
                    param($Flutter,$Project,$Target)
                    if($script:Scenario-ceq'wait-failed'){throw 'not visible'}
                    if($script:Scenario-ceq'wait-identity'){$script:ObjectGeneration=2}
                    if($script:Scenario-ceq'wait-id'){return 'emulator-replacement'}
                    if($script:Scenario-ceq'boot-dynamic'){[IO.File]::AppendAllText((Join-Path $script:FixtureRoot 'Original.avd/config.ini'),"fastboot.chosenSnapshotFile=runtime`n")}
                    return $Target.Id
                }
                if($Scenario-ceq'identity'){
                    $script:RealIdentity=${function:Get-JobsRunnerAndroidAvdIdentity}
                    function script:Get-JobsRunnerAndroidAvdIdentity {param($Name)$result=&$script:RealIdentity $Name;$script:IdentityReads++;if($script:IdentityReads-gt1){$result.ConfigHash='changed'};return $result}
                }
            } $scenario $FixtureRoot $sdk
            $savedJava=$env:JAVA_HOME;$failed=$false;$result=$null
            try{$result=&$module {Start-JobsRunnerExistingAndroid 'flutter' '/fixture/project'}}catch{$failed=$true;if($scenario-in@('success','running')){Write-Host $_.Exception.Message;Write-Host $_.ScriptStackTrace}}
            Assert-Virtual ($env:JAVA_HOME-ceq$savedJava) 'Android成功、失败、返回与取消均恢复父进程环境'
            Assert-Virtual ((&$module {$script:Created})-eq0) '启动已有AVD不转入创建入口'
            if($scenario-in@('success','boot-dynamic')){Assert-Virtual (-not$failed-and$result.Kind-ceq'Ready'-and$result.Id-ceq'emulator-5568'-and$result.Environment.JAVA_HOME-ceq'temporary-java'-and(&$module {$script:Starts})-eq1) '原AVD精确serial承接本次运行并仅启动一次'}
            elseif($scenario-in@('wait-failed','wait-identity','wait-id','wait-portreuse')){Assert-Virtual ($failed-and(&$module {$script:Starts})-eq1) '启动后发现失败不重放启动或误选其它设备'}
            elseif($scenario-in@('identity','selection-identity','selection-object')){Assert-Virtual ($failed-and(&$module {$script:Starts})-eq0) '选择期间同名AVD被替换或原配置改变时阻止启动'}
            else{Assert-Virtual (-not$failed-and(&$module {$script:Starts})-eq0-and($scenario-ceq'cancel'-or$result.Kind-ceq'Back')) '空列表返回、左键返回与取消均无启动'}
            Remove-Module $module
        }

        foreach($scenario in @('success','running','boot-dynamic','cancel','back','missing','license','identity','selection-config','app-gate','post-identity','post-config','post-port','post-missing')) {
            $FixtureRoot=Join-Path $temporary ([guid]::NewGuid().ToString('N'));$instance=Join-Path $FixtureRoot 'Original Phone';[void][IO.Directory]::CreateDirectory($instance)
            $sdk=Join-Path $FixtureRoot 'sdk';[void][IO.Directory]::CreateDirectory((Join-Path $sdk 'default/openharmony/toolchains'));[IO.File]::WriteAllText((Join-Path $sdk 'default/openharmony/toolchains/hdc.exe'),'fixture')
            $config=Join-Path $instance 'config.ini';$original="name=Original Phone`ncustom=preserved`n";if($scenario-ceq'running'){$original+='sdkPath='+$sdk+"`n"};[IO.File]::WriteAllText($config,$original)
            $module=Import-Module $path -Force -PassThru -DisableNameChecking
            & $module {
                param($Scenario,$FixtureRoot,$Instance)
                $script:Scenario=$Scenario;$script:FixtureRoot=$FixtureRoot;$script:Instance=$Instance;$script:Starts=0;$script:Queries=0;$script:Prepared=$false;$script:TargetReads=0;$script:Actions=[Collections.Generic.List[string]]::new()
                function script:Initialize-JobsRunnerVirtualHarmony {$env:TOOL_HOME='temporary-tools';return [pscustomobject]@{Flutter='prepared-flutter';Tools=[pscustomobject]@{Root=$script:FixtureRoot};Module='fixture';Emulator='Emulator.exe'}}
                function script:Select-JobsRunnerChoice {if($script:Scenario-ceq'cancel'){return $null};if($script:Scenario-ceq'back'){return [pscustomobject]@{Kind='Back';Index=-1}};if($script:Scenario-ceq'selection-config'){[IO.File]::AppendAllText((Join-Path $script:Instance 'config.ini'),"custom=changed`n")};return [pscustomobject]@{Kind='Selected';Index=0}}
                function script:Invoke-JobsRunnerHarmonyCore {
                    param($Module,$Command,$Arguments)
                    $script:Actions.Add($Command)
                    switch($Command){
                        'Get-JobsHarmonyInstances' {
                            if($script:Scenario-ceq'missing'-or($script:Scenario-ceq'post-missing'-and$script:Prepared)){return @()}
                            $script:Queries++;$uuid=if(($script:Scenario-ceq'identity'-and$script:Queries-gt1)-or($script:Scenario-ceq'post-identity'-and$script:Prepared)){'changed'}else{'original-uuid'}
                            return @([pscustomobject]@{name='Original Phone';uuid=$uuid;instancePath=$script:Instance;deviceType='phone';isRunning=($script:Scenario-ceq'running')},[pscustomobject]@{name='Other Phone'})
                        }
                        'Get-JobsHarmonyInstanceVersion' {return 'HarmonyOS 6.0.1(21)'}
                        'Get-JobsHarmonyImages' {return [pscustomobject]@{DeviceType='phone';OsVersion='HarmonyOS 6.0.1(21)'}}
                        'Confirm-JobsHarmonyLicenses' {if($script:Scenario-ceq'license'){throw 'cancelled agreement'}}
                        'Invoke-JobsHarmonyInteractive' {if(($Arguments[1]-join' ')-cnotmatch'^-start Original Phone -instancePath '){throw 'wrong startup'};$script:Starts++;if($script:Scenario-ceq'boot-dynamic'){[IO.File]::AppendAllText((Join-Path $script:Instance 'config.ini'),"hw.hdc.port=15555`n")}}
                        default {throw ('unexpected: '+$Command)}
                    }
                }
                function script:Get-JobsRunnerHarmonyTarget {$script:TargetReads++;if($script:Scenario-ceq'post-port'-and$script:Prepared){return '127.0.0.1:15557'};return '127.0.0.1:15555'}
                function script:Start-JobsRunnerHarmonyPreparation {param($Flutter,$Project,$Key)if($Flutter-cne'prepared-flutter'-or$Key-cne'127.0.0.1:15555'){throw 'wrong identity'};if($script:Scenario-ceq'app-gate'){throw 'unsupported vendor plugin'};$script:Prepared=$true;if($script:Scenario-ceq'post-config'){[IO.File]::AppendAllText((Join-Path $script:Instance 'config.ini'),"custom=changed`n")};$script:RunnerSelectedPlatform='ohos-arm64';return $Key}
            } $scenario $FixtureRoot $instance
            $savedTools=$env:TOOL_HOME;$failed=$false;$result=$null
            try{$result=&$module {Start-JobsRunnerExistingHarmony 'flutter' '/fixture/project'}}catch{$failed=$true;if($scenario-in@('success','running')){Write-Host $_.Exception.Message;Write-Host $_.ScriptStackTrace}}
            Assert-Virtual ($env:TOOL_HOME-ceq$savedTools) '鸿蒙所有返回路径恢复父进程环境'
            $starts=&$module {$script:Starts};$actions=@(&$module {$script:Actions.ToArray()})
            Assert-Virtual (($actions-join'|')-notmatch'create|delete|reset|stop') '启动入口不新建、删除、重置或重启已有实例'
            if($scenario-in@('success','running','boot-dynamic')){
                Assert-Virtual (-not$failed-and$result.Id-ceq'127.0.0.1:15555'-and$result.Environment.TOOL_HOME-ceq'temporary-tools') '鸿蒙原实例HDC目标与当前SDK承接运行'
                Assert-Virtual ((&$module {$script:TargetReads})-eq2) '长准备后重新核验原实例的HDC目标'
                Assert-Virtual ($starts-eq$(if($scenario-ceq'running'){0}else{1})) '已运行实例复用，停止实例只启动一次'
                Assert-Virtual ([IO.File]::ReadAllText($config).Contains('custom=preserved')) '补SDK保留其它实例配置'
                if($scenario-ceq'success'){$backups=@(Get-ChildItem $instance -Filter '*.jobs-backup-*');Assert-Virtual ($backups.Count-eq1-and[IO.File]::ReadAllText($backups[0].FullName)-ceq$original) '缺失SDK配置原子发布前保留原字节备份'}
            }elseif($scenario-in@('license','identity')){Assert-Virtual ($failed-and$starts-eq0-and[IO.File]::ReadAllText($config)-ceq$original) '许可取消或身份改变不写配置、不启动'}
            elseif($scenario-ceq'selection-config'){Assert-Virtual ($failed-and$starts-eq0) '鸿蒙菜单期间配置改变不能沿用选前实例身份'}
            elseif($scenario-in@('app-gate','post-identity','post-config','post-port','post-missing')){Assert-Virtual ($failed-and$starts-eq1) '项目门禁失败保留已启动实例，不重复启动或运行App'}
            else{Assert-Virtual (-not$failed-and$starts-eq0-and($scenario-ceq'cancel'-or$result.Kind-ceq'Back')) '鸿蒙空列表/返回/取消无启动或新建'}
            Remove-Module $module
        }

        $module=Import-Module $path -Force -PassThru -DisableNameChecking
        $preStartCommands=&$module {(${function:Initialize-JobsRunnerVirtualHarmony}).Ast.FindAll({param($node)$node-is[Management.Automation.Language.CommandAst]},$true)|ForEach-Object{$_.GetCommandName()}}
        Assert-Virtual (($preStartCommands-join'|')-notmatch'Initialize-JobsPrepareSdk|New-JobsPrepareOhosPlatform|Invoke-JobsPrepareProcess|Publish-JobsHarmonyBinding') '仅启动环境准备不先切业务FVM、不生成ohos或解析项目依赖'
        $creator=&$module {Import-JobsRunnerHarmonyCreator}
        $port=&$module {param($Core)Invoke-JobsRunnerHarmonyCore $Core 'Get-JobsHarmonyFlutterPort' @([pscustomobject]@{'hw.hdc.port'='15555'})} $creator
        Assert-Virtual ($port-ceq'15555') '源码闭包可直接加载随包Creator私有函数，不依赖兄弟源码目录'
        Remove-Module $creator
        $core=New-Module -ScriptBlock {
            $script:Seen=@();$script:Installed=$false
            function Invoke-JobsHarmonyQuery {param($Tool,$Arguments)$script:Seen=@($Arguments);return ($Arguments-join'|')}
            function Get-JobsHarmonyImages {
                param($Tool,[switch]$Available)
                if($Available-or$script:Installed){return [pscustomobject]@{DeviceType='phone';OsVersion='HarmonyOS 6.0.1(21)'}}
                return [pscustomobject]@{DeviceType='phone';OsVersion='HarmonyOS 6.1.0(22)'}
            }
            function Invoke-JobsHarmonyInteractive {param($Tool,$Arguments)$script:Seen=@($Arguments);$script:Installed=$true}
            function Write-JobsHarmonyFlutterTarget {[IO.File]::WriteAllText($env:JOBS_FLUTTER_CREATED_DEVICE_FILE,"Harmony`t127.0.0.1:15555`n")}
        }
        $echo=&$module {param($Core)Invoke-JobsRunnerHarmonyCore $Core 'Invoke-JobsHarmonyQuery' @('Emulator.exe',@('-help','-details'))} $core
        Assert-Virtual ($echo-ceq'-help|-details') '私有模块边界保留嵌套argv，不把启动参数拆散或二次解释'
        &$module {function script:Invoke-JobsSdkAcquire {param($Label,$Operation)&$Operation}}
        &$module {param($Core)Initialize-JobsRunnerHarmonyImage $Core 'Emulator.exe' ([pscustomobject]@{DeviceType='phone';Version='HarmonyOS 6.0.1(21)';ImageRoot='/fixture/image root'})} $core
        $argsSeen=&$core {$script:Seen-join'|'}
        Assert-Virtual ($argsSeen-ceq'-install|-deviceType|phone|-osVersion|HarmonyOS 6.0.1(21)|-force|-imageRoot|/fixture/image root') '仅补原实例精确正式镜像并使用原镜像目录，不选其它更新版本'
        &$module {param($Core)Update-JobsRunnerHarmonyCatalog $Core 'Emulator.exe' '-screenProfileList -update'} $core
        Assert-Virtual ((&$core {$script:Seen-join'|'})-ceq'-screenProfileList|-deviceType|phone|-details|-update') '仅在help确认后刷新官方机型目录，不将-update冒称CLT升级'
        if([Environment]::OSVersion.Platform-ne[PlatformID]::Win32NT){
            &$module {function script:New-JobsRunnerVirtualPrivateDirectory {param($Path)[void][IO.Directory]::CreateDirectory($Path);return $Path}}
        }
        $savedReceipt=$env:JOBS_FLUTTER_CREATED_DEVICE_FILE
        $target=&$module {param($Core)Get-JobsRunnerHarmonyTarget $Core 'Emulator.exe' ([pscustomobject]@{name='Original'})} $core
        Assert-Virtual ($target-ceq'127.0.0.1:15555'-and$env:JOBS_FLUTTER_CREATED_DEVICE_FILE-ceq$savedReceipt) 'HDC回执解析承接精确目标并恢复外层回执环境'
        Remove-Module $core
        Remove-Module $module

        $module=Import-Module $path -Force -PassThru -DisableNameChecking
        $partial=Join-Path $temporary ('partial-sdk-'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory((Join-Path $partial 'toolchains'))
        $fakeHdc=Join-Path $partial 'toolchains/hdc.exe';[IO.File]::WriteAllText($fakeHdc,'fixture')
        $snapshot=&$module {Get-JobsRunnerTaskEnvironmentSnapshot @('OHOS_SDK_HOME')}
        try {
            $env:OHOS_SDK_HOME=$partial
            &$module {function script:Get-JobsRunnerHarmonyRoot {throw 'complete SDK must not be required'}}
            Assert-Virtual ((&$module {Get-JobsRunnerHdcExecutable})-ceq$fakeHdc) '部分SDK仅HDC可用仍可独立发现工具，不要求完整编译环境'
        } finally {&$module {param($Snapshot)Restore-JobsRunnerTaskEnvironment $Snapshot} $snapshot}
        &$module {
            function script:Get-JobsRunnerHdcExecutable {return 'hdc'}
            function script:Invoke-JobsRunnerReadOnlyTool {return 'original-phone'}
            function script:Get-JobsRunnerUsbInventory {throw 'USB query denied'}
        }
        $observed=@(&$module {Get-JobsRunnerHarmonyDiagnostics @() '/fixture/project' $null} 6>&1)
        $rows=@($observed|Where-Object{$null-ne$_.PSObject.Properties['Kind']})
        Assert-Virtual ($rows.Count-eq1-and$rows[0].Id-ceq'original-phone') 'USB查询失败仍保留HDC已确认目标，不能隐藏手机'
        &$module {
            function script:Invoke-JobsRunnerReadOnlyTool {throw 'unauthorized channel'}
            function script:Get-JobsRunnerUsbInventory {return @()}
        }
        $observed=@(&$module {Get-JobsRunnerHarmonyDiagnostics @() '/fixture/project' $null} 6>&1)
        $rows=@($observed|Where-Object{$null-ne$_.PSObject.Properties['Kind']})
        Assert-Virtual ($rows.Count-eq0-and($observed-join'|')-match'HDC.*unauthorized') '没有USB证据时HDC授权查询失败仍独立可见，且不造连接设备'
        &$module {function script:Invoke-JobsRunnerReadOnlyTool {return "original-phone`toffline`nUnauthorized"}}
        $observed=@(&$module {Get-JobsRunnerHarmonyDiagnostics @() '/fixture/project' $null} 6>&1)
        $rows=@($observed|Where-Object{$null-ne$_.PSObject.Properties['Kind']})
        Assert-Virtual ($rows.Count-eq1-and$rows[0].Id-ceq'original-phone'-and$rows[0].Detail-match'offline') '离线状态保留真实设备ID并明确原因，不把状态词当设备ID'
        Remove-Module $module

        $module=Import-Module $path -Force -PassThru -DisableNameChecking
        foreach($mode in @('success','auth','hash','beta','host','download-auth','unknown-major','filename','mixed')) {
            &$module {
                param($Mode)
                $script:OfficialMode=$Mode
                function script:Invoke-JobsRunnerHarmonyOfficialService {
                    param($Service,$Request)
                    if($script:OfficialMode-ceq'auth'){return [pscustomobject]@{code='90910011'}}
                    if($Service-ceq'getToolVersionList'){
                        $hash=if($script:OfficialMode-ceq'hash'){'bad'}else{'a'*64}
                        $name=if($script:OfficialMode-ceq'beta'){'6.1.1 Beta'}else{'6.1.1 Release'}
                        $data=[pscustomobject]@{code='00000';value=[pscustomobject]@{versionTypeList=@([pscustomobject]@{osType=1;versionList=@([pscustomobject]@{versionId='v300';versionName=$name;buildVersion=$(if($script:OfficialMode-ceq'unknown-major'){'26.0.0.1'}else{'6.1.1.300'});packageList=@([pscustomobject]@{sdkId='sdk';packageId='win-x64';packageName='commandline-tools-windows-x64-6.1.1.300.zip';packageSize=1000000;sha256=$hash})})})}}
                        if($script:OfficialMode-ceq'mixed'){$data.value.versionTypeList[0].versionList=@([pscustomobject]@{versionId='v26';versionName='26 Release';buildVersion='26.0.0.1';packageList=@()})+@($data.value.versionTypeList[0].versionList)}
                        return $data
                    }
                    if($script:OfficialMode-ceq'download-auth'){return [pscustomobject]@{code='90910011'}}
                    $url=if($script:OfficialMode-ceq'filename'){'https://developer.huawei.com/fixture/wrong.zip'}elseif($script:OfficialMode-ceq'host'){'https://example.invalid/sdk.zip'}else{'https://developer.huawei.com/fixture/commandline-tools-windows-x64-6.1.1.300.zip'}
                    return [pscustomobject]@{code='00000';value=[pscustomobject]@{downloadUrl=$url}}
                }
            } $mode
            $state=&$module {Get-JobsRunnerHarmonyOfficialUpdate}
            if($mode-in@('success','mixed')){Assert-Virtual ($state.State-ceq'Verified'-and$state.Package.Version-ceq'6.1.1.300'-and$state.Package.Sha256-ceq('a'*64)) '成功schema正式Win1包经版本/大小/hash/来源验证有正向下载分支'}
            else{Assert-Virtual ($state.State-cne'Verified'-and$null-eq$state.Package) '授权、hash、预览版或来源错误均阻断，不拿固定旧CLT充当更新'}
        }
        $wrapped=&$module {ConvertFrom-JobsRunnerHarmonyOfficialEnvelope ([pscustomobject]@{returnCode='90910011';resJson='{"code":"00000"}'})}
        Assert-Virtual ($wrapped.code-ceq'90910011') '外层官方授权错误不能被伪成功resJson盖掉'
        $public=[pscustomobject]@{code=0;value=[pscustomobject]@{status=4;content=[pscustomobject]@{content='<h4>DevEco Studio 6.1.1 Release (6.1.1.300)</h4><table><caption>Table 2 Command line tools</caption><tr><td>Command Line</td><td>6.1.1.300</td></tr><tr><td>Emulator</td><td>6.1.1.350</td></tr></table>'}}}
        $version=&$module {param($Response)ConvertFrom-JobsRunnerHarmonyPublicRelease $Response} $public
        Assert-Virtual ($version.Version-ceq'6.1.1.300') '公开兼容Release严格取Command Line行，不把Emulator .350当CLT版本'
        $public.value.content.content=$public.value.content.content.Replace('<td>6.1.1.300</td>','<td>6.1.1.290</td>');$failed=$false
        try{&$module {param($Response)ConvertFrom-JobsRunnerHarmonyPublicRelease $Response} $public}catch{$failed=$true}
        Assert-Virtual $failed '公开Command Line行与Release标题不一致时拒绝假绿'
        $public.value.status=1;$failed=$false
        try{&$module {param($Response)ConvertFrom-JobsRunnerHarmonyPublicRelease $Response} $public}catch{$failed=$true}
        Assert-Virtual $failed '未发布公开正文不能用来判定已最新'
        Remove-Module $module

        $readyRoot=Join-Path $temporary ('ready-'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory((Join-Path $readyRoot 'emulator'));[IO.File]::WriteAllText((Join-Path $readyRoot 'emulator/Emulator.exe'),'fixture')
        foreach($mode in @('equal','newer','old','unknown')){
            $module=Import-Module $path -Force -PassThru -DisableNameChecking
            &$module {
                param($Root,$Mode)
                $script:KnownRoot=$Root;$script:UpdateMode=$Mode;$script:AuthChecks=0
                function script:Get-JobsRunnerHarmonyRoot {return $script:KnownRoot}
                function script:Test-JobsPrepareToolFiles {return $true}
                function script:Get-JobsRunnerHarmonyToolVersion {if($script:UpdateMode-ceq'old'){return '6.1.1.280'};if($script:UpdateMode-ceq'newer'){return '6.1.1.310'};return '6.1.1.300'}
                function script:Get-JobsRunnerHarmonyPublicRelease {if($script:UpdateMode-ceq'unknown'){throw 'public schema failed'};return [pscustomobject]@{Version='6.1.1.300'}}
                function script:Wait-JobsRunnerHarmonyOfficialUpdate {$script:AuthChecks++;return [pscustomobject]@{Kind='Back'}}
                function script:Install-JobsRunnerOfficialHarmonyTools {throw 'blocked/current must not install'}
            } $readyRoot $mode
            $result=&$module {Resolve-JobsRunnerHarmonyToolRoot}
            if($mode-in@('equal','newer')){Assert-Virtual ($result-ceq$readyRoot-and(&$module {$script:AuthChecks})-eq0) '本机已满足公开兼容Release，不强依赖匿名下载授权、不永久阻塞健康CLT'}
            else{Assert-Virtual ($result.Kind-ceq'Back'-and(&$module {$script:AuthChecks})-eq1) '落后或公开目录不可验证才进入真实元数据获取，授权未通过不可启动'}
            Remove-Module $module
        }

        # 官方归档正向侧装使用真实ZIP/大小/SHA/安全解压和version.txt，绝不执行其中假exe。
        $archiveRoot=Join-Path $temporary ('official-'+[guid]::NewGuid().ToString('N'))
        $content=Join-Path $archiveRoot 'command-line-tools'
        foreach($directory in @('emulator','node','ohpm/bin','sdk/default/openharmony/ets','sdk/default/openharmony/native','sdk/default/openharmony/toolchains')){[void][IO.Directory]::CreateDirectory((Join-Path $content $directory))}
        foreach($file in @('emulator/Emulator.exe','node/node.exe','ohpm/bin/ohpm.bat','sdk/default/openharmony/toolchains/hdc.exe')){[IO.File]::WriteAllText((Join-Path $content $file),'fixture, never execute')}
        [IO.File]::WriteAllText((Join-Path $content 'version.txt'),'6.1.1.300')
        $archive=Join-Path $temporary ([guid]::NewGuid().ToString('N')+'.zip')
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::CreateFromDirectory($archiveRoot,$archive)
        $package=[pscustomobject]@{Name='commandline-tools-windows-x64-6.1.1.300.zip';Version='6.1.1.300';Size=(Get-Item $archive).Length;Sha256=(Get-FileHash $archive -Algorithm SHA256).Hash;ArchivePath=$archive;Url=''}
        $module=Import-Module $path -Force -PassThru -DisableNameChecking
        $snapshot=&$module {Get-JobsRunnerTaskEnvironmentSnapshot @('LOCALAPPDATA')}
        try {
            $env:LOCALAPPDATA=Join-Path $temporary ('cache-'+[guid]::NewGuid().ToString('N'))
            $prepare=Join-Path (Split-Path -Parent $path) 'RunPreflight.ps1/PrepareHarmonyRun.ps1/PrepareHarmonyRun.ps1'
            $installed=&$module {
                param($Entry,$Package)
                . $Entry
                $script:JobsPrepareCore=Import-JobsPrepareCore
                Install-JobsRunnerOfficialHarmonyTools $Package
            } $prepare $package
            Assert-Virtual ([IO.Directory]::Exists($installed)-and(&$module {param($Root)Get-JobsRunnerHarmonyToolVersion $Root} $installed)-ceq'6.1.1.300') '完整官方元数据/本地归档正向侧装经真实hash/安全解压/实际版本复检'
            Assert-Virtual ([IO.File]::Exists($archive)-and[IO.Directory]::Exists($content)) '侧装保留原归档及既有安装，不覆盖来源'
        } finally {&$module {param($Snapshot)Restore-JobsRunnerTaskEnvironment $Snapshot} $snapshot}
        Remove-Module $module

    }
    Write-Host ('PASS: FlutterRunnerVirtualStart ('+$script:Checks+' assertions; no real downloads or device/app start)')
} finally {if([IO.Directory]::Exists($temporary)){[IO.Directory]::Delete($temporary,$true)}}

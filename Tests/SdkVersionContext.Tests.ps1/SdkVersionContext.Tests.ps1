# SDK 下载前版本上下文；仅临时元数据和假进程，不执行 Flutter/Dart、不联网。
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('JobsSdkVersionContext-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$script:checks=0
function Assert-Context([bool]$Condition,[string]$Message){$script:checks++;if(-not $Condition){throw $Message}}
function Write-Fixture([string]$Path,[string]$Text){[void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path));[IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))}
$savedEngine=$env:FLUTTER_PREBUILT_ENGINE_VERSION
try {
    $env:FLUTTER_PREBUILT_ENGINE_VERSION=$null
    foreach($relative in @('JobsFlutterRunner/Scripts/Action.psm1','JobsFlutterTools/Scripts/Actions/run/Scripts/Action.psm1')){
        $scope=Join-Path $temporary ([guid]::NewGuid().ToString('N'))
        $project=Join-Path $scope 'Project 中文';$sdk=Join-Path $scope 'sdk';$flutter=Join-Path $sdk 'bin/flutter.exe'
        Write-Fixture $flutter 'must never execute this file'
        Write-Fixture (Join-Path $project '.fvmrc') '{"flutter":"3.38.4"}'
        Write-Fixture (Join-Path $sdk 'version') '3.38.4'
        Write-Fixture (Join-Path $sdk 'bin/internal/engine.version') ('a'*40)
        Write-Fixture (Join-Path $sdk 'bin/cache/engine-dart-sdk.stamp') ('b'*40)
        Write-Fixture (Join-Path $sdk 'bin/cache/dart-sdk/version') '3.0.0'
        Write-Fixture (Join-Path $sdk 'bin/cache/dart-sdk.old/version') '9.9.9'
        Write-Fixture (Join-Path $sdk 'bin/cache/flutter.version.json') ('{"frameworkVersion":"3.0.0","engineRevision":"'+('b'*40)+'","dartSdkVersion":"3.0.0"}')
        $module=Import-Module (Join-Path $root $relative) -PassThru -DisableNameChecking
        try{
            $context=& $module {param($Flutter,$Project)Get-JobsRunnerSdkContext $Flutter $Project} $flutter $project
            Assert-Context ($context.DeclaredFlutter -ceq '3.38.4' -and $context.DeclaredSource -ceq '.fvmrc') '保留项目声明及来源'
            Assert-Context (-not $context.FlutterVersion -and $context.SdkPath -ceq $sdk) '单独旧version文件不能冒充实际SDK身份，实际路径保留'
            $sdkLink=Join-Path $scope 'linked-sdk'
            $linkType=if([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT){'Junction'}else{'SymbolicLink'}
            [void](New-Item -ItemType $linkType -Path $sdkLink -Target $sdk)
            $linked=& $module {param($Flutter,$Project)Get-JobsRunnerSdkContext $Flutter $Project} (Join-Path $sdkLink 'bin/flutter.exe') $project
            Assert-Context ($linked.SdkPath -ceq $sdk -and $linked.SelectedSdkPath -ceq $sdkLink) 'FVM链接位置与实际SDK位置分别展示'
            Assert-Context ($context.Engine -ceq ('a'*40) -and $context.HostSystem -and $context.Architecture) '下载前有目标engine和宿主OS/架构'
            Assert-Context (-not $context.DartVersion) '旧缓存和dart-sdk.old不能冒充目标Dart'
            & $module {
                $script:Events=New-Object 'Collections.Generic.List[string]'
                $script:OfficialFailure=$false
                function script:Invoke-JobsRunnerOfficialMetadata {
                    param($Url,$TimeoutSeconds)
                    if($script:OfficialFailure){throw 'fixture official timeout'}
                    if($Url -like '*releases_windows.json*'){
                        return '{"current_release":{"stable":"cccccccccccccccccccccccccccccccccccccccc"},"releases":[{"hash":"cccccccccccccccccccccccccccccccccccccccc","channel":"stable","version":"3.50.0","dart_sdk_version":"3.13.0","dart_sdk_arch":"x64","release_date":"2026-11-12T12:00:00Z"},{"hash":"cccccccccccccccccccccccccccccccccccccccc","channel":"stable","version":"3.50.0","dart_sdk_version":"3.13.0","dart_sdk_arch":"arm64","release_date":"2026-11-12T12:00:00Z"}]}'
                    }
                    return ('d'*40)
                }
                function script:Get-JobsRunnerPathSdkContext {
                    return [pscustomobject]@{FlutterVersion='3.49.2';FlutterSource='fixture local metadata';SdkPath='fixture PATH SDK';Engine=('e'*40);DartVersion='3.12.1'}
                }
                function script:Write-JobsSdkRetryMessage {param($Message)$script:Events.Add('log:'+$Message)}
                function script:Invoke-JobsSdkAcquireProcess {
                    param($Start,$TimeoutSeconds,$Label)
                    $script:LastSdkArguments=$Start.Arguments
                    $script:LastSdkTimeout=$TimeoutSeconds
                    $script:Events.Add('download:'+$Label)
                    [pscustomobject]@{ExitCode=0;StdOut='{"frameworkVersion":"3.38.4"}';StdErr=''}
                }
            }
            $machine=& $module {param($Flutter,$Project)Invoke-JobsRunnerTool $Flutter @('--version','--machine') $Project} $flutter $project
            $events=@(& $module {$script:Events.ToArray()})
            Assert-Context ($machine -ceq '{"frameworkVersion":"3.38.4"}') '版本日志不污染机器响应'
            Assert-Context ($events[0].StartsWith('log:') -and $events[-1].StartsWith('download:Flutter 3.38.4')) 'SDK版本上下文先于实际获取，重试标签含Flutter版本'
            $display=$events -join "`n"
            Assert-Context ($display.Contains('官网当前最新 stable：Flutter 3.50.0 / Dart 3.13.0 / Engine '+('d'*40))) '官网stable来自当前指针且Engine按该发布提交读取'
            Assert-Context ($display.Contains('官网发布日期：2026-11-12T12:00:00Z') -and $display.Contains('本次查询时间：')) '官网版本带来源日期和本次查询时间'
            Assert-Context ($display.Contains('本机 PATH Flutter：Flutter 3.49.2') -and $display.Contains('项目声明 Flutter：3.38.4')) 'PATH与工程FVM版本保持分开'
            & $module {$script:OfficialFailure=$true;$script:Events.Clear()}
            & $module {param($Context)Write-JobsRunnerSdkContext $Context @('--version')} $context
            $failedDisplay=(@(& $module {$script:Events.ToArray()}) -join "`n")
            Assert-Context ($failedDisplay.Contains('官网当前最新 stable：未知') -and -not $failedDisplay.Contains('官网当前最新 stable：Flutter 3.50.0')) '官方查询失败不沿用上次成功版本冒充最新'
            & $module {$script:OfficialFailure=$false;$script:Events.Clear()}
            Assert-Context ($display.Contains('目标内置 Dart SDK：未解析') -and -not $display.Contains('9.9.9') -and -not $display.Contains('3.0.0')) '未知目标Dart明确说明，不展示不可信旧版本'
            Assert-Context ($display.Contains('项目声明 Flutter：3.38.4') -and $display.Contains('运行平台 / 架构：') -and $display.Contains('目标 engine：'+('a'*40))) '终端日志包含身份及平台上下文'
            & $module {param($Flutter,$Project)Initialize-JobsRunnerDiscoverySdk $Flutter $Project} $flutter $project
            $sdkCall=& $module {[pscustomobject]@{Arguments=$script:LastSdkArguments;Timeout=$script:LastSdkTimeout}}
            Assert-Context ($sdkCall.Arguments-match'precache'-and$sdkCall.Arguments-match'--universal'-and$sdkCall.Timeout-ge1800) '通用资源实际经过现有SDK获取封装，保留实时进度/持续重试并使用长停滞超时'
            Write-Fixture (Join-Path $sdk 'bin/cache/flutter.version.json') ('{"frameworkVersion":"3.38.4","engineRevision":"'+('a'*40)+'","dartSdkVersion":"3.10.3 (stable)"}')
            Remove-Item -LiteralPath (Join-Path $sdk 'version')
            $context=& $module {param($Flutter,$Project)Get-JobsRunnerSdkContext $Flutter $Project} $flutter $project
            Assert-Context ($context.FlutterVersion -ceq '3.38.4' -and $context.DartVersion -ceq '3.10.3' -and $context.DartSource.Contains('engine 一致')) '与目标engine一致的版本元数据可以解析目标Dart'
            Remove-Item -LiteralPath (Join-Path $sdk 'bin/cache/flutter.version.json')
            Write-Fixture (Join-Path $sdk 'bin/cache/engine-dart-sdk.stamp') ('a'*40)
            Write-Fixture (Join-Path $sdk 'bin/cache/dart-sdk/version') '3.10.3'
            $context=& $module {param($Flutter,$Project)Get-JobsRunnerSdkContext $Flutter $Project} $flutter $project
            Assert-Context ($context.DartVersion -ceq '3.10.3' -and $context.DartSource.Contains('engine stamp 一致')) '已下载Dart只有engine stamp一致时作为目标版本'
            $env:FLUTTER_PREBUILT_ENGINE_VERSION='c'*40
            $context=& $module {param($Flutter,$Project)Get-JobsRunnerSdkContext $Flutter $Project} $flutter $project
            Assert-Context ($context.Engine -ceq ('c'*40) -and -not $context.DartVersion) '显式engine目标覆盖时拒绝旧Dart stamp'
            $env:FLUTTER_PREBUILT_ENGINE_VERSION=$null
            Write-Fixture (Join-Path $sdk 'bin/internal/dart-sdk.version') '3.10.3'
            Remove-Item -LiteralPath (Join-Path $sdk 'bin/cache/engine-dart-sdk.stamp')
            $context=& $module {param($Flutter,$Project)Get-JobsRunnerSdkContext $Flutter $Project} $flutter $project
            Assert-Context ($context.DartVersion -ceq '3.10.3' -and $context.DartSource -ceq 'bin/internal/dart-sdk.version') '源码明确版本文件可作为目标Dart来源'
            Remove-Item -LiteralPath (Join-Path $project '.fvmrc') -Force
            Write-Fixture (Join-Path $project '.fvm/fvm_config.json') '{"flutterSdkVersion":"3.38.5"}'
            $context=& $module {param($Flutter,$Project)Get-JobsRunnerSdkContext $Flutter $Project} $flutter $project
            Assert-Context ($context.DeclaredFlutter -ceq '3.38.5' -and $context.DeclaredSource -ceq '.fvm/fvm_config.json') '兼容旧项目版本声明'
            Write-Fixture (Join-Path $project '.fvm/fvm_config.json') '{broken'
            $context=& $module {param($Flutter,$Project)Get-JobsRunnerSdkContext $Flutter $Project} $flutter $project
            Assert-Context (-not $context.DeclaredFlutter) '坏声明只报告未解析，不触发SDK或联网修复'
            # 运行入口必须先准备通用制品；准备失败不能进入设备选择或业务启动。
            & $module {
                $script:RunEvents=New-Object 'Collections.Generic.List[string]'
                $script:FailDiscovery=$false
                $script:FailPreflight=$false
                $script:FixturePreflight=@{Fixture='version-context-preflight'}
                function script:Assert-JobsFlutterProject {param($Path)}
                function script:Get-JobsRunnerProjectRoot {param($Path)return $Path}
                function script:Get-JobsRunnerSession {param($Path)return $null}
                function script:Get-JobsRunnerFlutter {param($Path)return 'selected-project-flutter.exe'}
                function script:Invoke-JobsRunnerTool {
                    param($Flutter,$Arguments,$Project,$TimeoutSeconds)
                    $script:RunEvents.Add(($Arguments-join' '))
                    if($Arguments[0]-ceq'precache'){
                        if(($Arguments-join' ')-cne'precache --universal'-or$TimeoutSeconds-lt1800-or$Flutter-cne'selected-project-flutter.exe'){throw '错误的SDK准备参数'}
                        if($script:FailDiscovery){throw 'fixture SDK acquisition cancelled'}
                        return 'Already up-to-date.'
                    }
                    return '{"frameworkVersion":"3.38.4"}'
                }
                # 本测试只核对阶段衔接；假 Flutter 不进入真实 SDK 路径／宿主体检。
                function script:Get-JobsRunnerPreflight {
                    param($Flutter,$Project)
                    if($Flutter-cne'selected-project-flutter.exe'-or-not[IO.Directory]::Exists($Project)){throw '体检阶段没有收到当前夹具SDK和工程'}
                    $script:RunEvents.Add('preflight')
                    return $script:FixturePreflight
                }
                function script:Write-JobsRunnerPreflight {
                    param($Report)
                    if(-not[object]::ReferenceEquals($Report,$script:FixturePreflight)){throw '展示必须接收本轮体检报告'}
                    $script:RunEvents.Add('preflight-write')
                }
                function script:Assert-JobsRunnerPreflight {
                    param($Report,[string]$Platform)
                    if(-not[object]::ReferenceEquals($Report,$script:FixturePreflight)-or$Platform){throw '初次体检必须校验本轮报告，不能伪造已选平台'}
                    if($script:RunEvents[-1]-cne'preflight-write'){throw '体检报告必须先展示再校验'}
                    $script:RunEvents.Add('preflight-assert')
                    if($script:FailPreflight){throw 'fixture preflight blocked'}
                }
                function script:Select-JobsRunnerDevice {
                    param($Flutter,$Project)
                    if(-not[object]::ReferenceEquals($script:RunnerPreflight,$script:FixturePreflight)-or$script:RunEvents[-1]-cne'preflight-write'){throw '设备阶段必须复用已展示的本轮体检报告'}
                    $script:RunEvents.Add('devices')
                    return $null
                }
                function script:Start-JobsRunnerSession {$script:RunEvents.Add('UNEXPECTED_RUN');throw '不能启动业务'}
            }
            & $module {param($Project)Invoke-JobsFlutterRunAction $Project} $project
            $runEvents=@(& $module {$script:RunEvents.ToArray()})
            Assert-Context (($runEvents-join'|')-ceq'--version --machine|precache --universal|preflight|preflight-write|devices') '实际运行入口先通用SDK，再展示本轮体检并选择设备，所选平台准备后才作运行门禁'
            Assert-Context ('UNEXPECTED_RUN'-cnotin$runEvents) '取消设备不进入运行宿主'
            & $module {$script:RunEvents.Clear();$script:FailDiscovery=$true}
            $stopped=$false
            try{& $module {param($Project)Invoke-JobsFlutterRunAction $Project} $project}catch{$stopped=$_.Exception.Message-ceq'fixture SDK acquisition cancelled'}
            $runEvents=@(& $module {$script:RunEvents.ToArray()})
            Assert-Context ($stopped-and($runEvents-join'|')-ceq'--version --machine|precache --universal') '通用SDK失败/取消原样传播，不进入体检、设备查询或业务'
            & $module {$script:RunEvents.Clear();$script:FailDiscovery=$false;$script:FailPreflight=$true}
            $stopped=$false
            try{& $module {param($Project)Invoke-JobsFlutterRunAction $Project} $project}catch{$stopped=$_.Exception.Message-ceq'fixture preflight blocked'}
            $runEvents=@(& $module {$script:RunEvents.ToArray()})
            Assert-Context (-not$stopped-and($runEvents-join'|')-ceq'--version --machine|precache --universal|preflight|preflight-write|devices') '首次体检缺项允许选定平台后直接准备，取消设备不运行业务'
        }finally{Remove-Module $module}
    }
    Write-Host ('PASS: SdkVersionContext.Tests.ps1 ('+$script:checks+' assertions; no Flutter/Dart/network)')
}finally{$env:FLUTTER_PREBUILT_ENGINE_VERSION=$savedEngine;Remove-Item -LiteralPath $temporary -Recurse -Force}

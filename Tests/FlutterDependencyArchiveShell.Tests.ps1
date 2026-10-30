# FlutterDependencyArchiveShell.Tests.ps1 | 原生归档 wrapper 的根目录、预检与确认边界。
# Created by Jobs on 2026年10月29日，星期四.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$count = 0
function Assert($Value,[string]$Message) { $script:count++; if(-not $Value){throw $Message} }
function Assert-Throws([scriptblock]$Body,[string]$Message){$failed=$false;try{&$Body|Out-Null}catch{$failed=$true};Assert $failed $Message}
$base=if([Environment]::OSVersion.Platform-eq[PlatformID]::Win32NT){[IO.Path]::GetTempPath()}else{'/private/tmp'}
$temp=Join-Path $base ('jobs-native-archive-wrapper-'+[guid]::NewGuid().ToString('N'))
$package=Join-Path $temp 'copied-package'
$project=Join-Path $temp '工程 with spaces & literal'
[void][IO.Directory]::CreateDirectory($project)
[void][IO.Directory]::CreateDirectory($package)
Copy-Item -LiteralPath (Join-Path $root 'JobsFlutterTools/Scripts') -Destination $package -Recurse
$scripts=Join-Path $package 'Scripts'
# shell fixtures 只检查调用协议；真实引擎另有逐文件校验与冲突回归。
[IO.File]::WriteAllText((Join-Path $scripts 'NativeDependencyArchive.dart'),'fixture-only placeholder, never executed')
[IO.File]::WriteAllText((Join-Path $project 'pubspec.yaml'),"name: fixture`ndependencies:`n  flutter:`n    sdk: flutter`n")
[void][IO.Directory]::CreateDirectory((Join-Path $project 'lib'))
[IO.File]::WriteAllText((Join-Path $project 'package.json'),'{}')
$module=Import-Module (Join-Path $scripts 'ProjectSetup.psm1') -PassThru -DisableNameChecking
try {
    $shapes=@(
        @('gradle','android',(Join-Path $temp 'gradle/caches/modules-2'),'modules-2'),
        @('gradle','android',(Join-Path $temp 'gradle/wrapper/dists/gradle-8.14-all'),'gradle-8.14-all'),
        @('ohos','ohos',(Join-Path $project 'ohos/oh_modules'),'oh_modules'),
        @('ohos','ohos',(Join-Path $project 'ohos/.hvigor'),'.hvigor'),
        @('native','android',(Join-Path $project 'build/app'),''),
        @('native','windows',(Join-Path $project 'build/windows'),''),
        @('precache','windows',(Join-Path $temp 'flutter/bin/cache/artifacts'),''),
        @('web','web',(Join-Path $project 'node_modules'),'')
    )
    foreach($row in $shapes){
        &$module {param($p,$k,$t,$r,$l)Assert-JobsArchiveRoot $p $k $t $r $l} $project $row[0] $row[1] $row[2] $row[3]
        Assert $true ('受控根通过：'+$row[0]+'/'+$row[1])
    }
    foreach($row in @(
        @('gradle','android',(Join-Path $temp 'gradle'),'modules-2'),
        @('gradle','android',(Join-Path $temp 'gradle/caches'),'modules-2'),
        @('gradle','android',(Join-Path $temp 'gradle/wrapper/dists/gradle-9.0-all'),'gradle-8.14-all'),
        @('native','windows',(Join-Path $project 'build'),''),
        @('native','android',(Join-Path $project 'build/windows'),''),
        @('precache','windows',(Join-Path $temp 'flutter/bin/cache/dart-sdk'),''),
        @('ohos','ohos',(Join-Path $project 'ohos/oh_modules'),'.hvigor'),
        @('web','web',(Join-Path $temp 'unrelated/node_modules'),'')
    )){
        Assert-Throws {&$module {param($p,$k,$t,$r,$l)Assert-JobsArchiveRoot $p $k $t $r $l} $project $row[0] $row[1] $row[2] $row[3]} ('拒绝扩大根：'+$row[0])
    }
    &$module {
        param($base)
        $script:fixtureRoot=$base
        $script:archiveCalls=New-Object 'System.Collections.Generic.List[string]'
        $script:answer=''
        $script:cancelInitial=$false
        $script:preflightFailure=$false
        $script:applyFailure=$false
        function script:Get-JobsInstallRoot {$script:fixtureRoot}
        function script:Test-JobsSetupInteractive {$true}
        function script:Read-Host {
            param($Prompt)
            if($script:cancelInitial){return 'cancel'}
            if($Prompt.StartsWith('输入精确')){return $script:answer}
            return ''
        }
        function script:Read-JobsArchiveDirectory {param($Prompt,$Default,$MayBeMissing)Join-Path $script:fixtureRoot 'snapshot'}
        function script:Get-JobsSetupFzf {param($p)$script:archiveCalls.Add('fzf');'fixture-fzf'}
        function script:Get-JobsArchiveDart {param($p)$script:archiveCalls.Add('dart-health');'fixture-dart'}
        function script:Get-JobsArchiveCachePlan {
            param($Project,$Kind,$Fzf,$Manifest,[switch]$Import)
            [pscustomobject]@{Root=(Join-Path $Project 'build/windows');Platform='windows';ToolVersion='Flutter 3.29.3 arch windows_x64'}
        }
        function script:Invoke-JobsSetupProcess {
            param($File,[string[]]$Arguments,$Directory,$TimeoutSeconds)
            $script:archiveCalls.Add($Arguments-join '|')
            $env:PATH='changed-only-inside-fixture'
            if('--check'-in$Arguments){if($script:preflightFailure){throw 'fixture hash/lock conflict'};return [pscustomobject]@{StdOut='{"kind":"native","files":2}';StdErr='';ExitCode=0}}
            if($script:applyFailure){throw 'fixture concurrent conflict'}
            return [pscustomobject]@{StdOut='fixture archive complete';StdErr='';ExitCode=0}
        }
    } $temp
    $before=@(Get-ChildItem -LiteralPath $temp -Recurse -Force|ForEach-Object FullName)
    &$module {param($p)Invoke-JobsProjectDependencyArchiveAction $p export-native-dependencies -Check} $project
    Assert ((&$module {$script:archiveCalls.Count})-eq0) 'Check 不调用运行时、选择器或引擎'
    Assert ((@(Get-ChildItem -LiteralPath $temp -Recurse -Force|ForEach-Object FullName)-join'|')-ceq($before-join'|')) 'Check 不创建日志或归档'
    &$module {$script:cancelInitial=$true}
    Assert-Throws {&$module {param($p)Invoke-JobsProjectDependencyArchiveAction $p export-native-dependencies} $project} '初始取消传播'
    Assert ((&$module {$script:archiveCalls.Count})-eq0) '取消零业务调用'
    &$module {$script:cancelInitial=$false}
    $savedPath=$env:PATH
    &$module {param($p)Invoke-JobsProjectDependencyArchiveAction $p export-native-dependencies} $project
    $calls=@(&$module {$script:archiveCalls.ToArray()})
    Assert ($calls.Count-eq4-and$calls[2].EndsWith('|--check')-and-not$calls[3].EndsWith('|--check')) '导出先完整预检后独立执行'
    Assert ($calls[3]-like '*|export|--project|*|--kind|native|*|--source-root|*') '导出明确类型/目标/源根且路径以数据参数传递'
    Assert ($env:PATH-ceq$savedPath) '成功后恢复进程环境'
    $snapshot=Join-Path $temp 'snapshot';[void][IO.Directory]::CreateDirectory($snapshot)
    [IO.File]::WriteAllText((Join-Path $snapshot 'manifest.json'),'{"format":"JobsNativeDependencyArchive","formatVersion":1,"kind":"native","platform":"windows","toolVersion":"Flutter 3.29.3 arch windows_x64"}')
    &$module {$script:archiveCalls.Clear();$script:answer=''}
    Assert-Throws {&$module {param($p)Invoke-JobsProjectDependencyArchiveAction $p import-native-dependencies} $project} '导入空回车拒绝'
    Assert ((&$module {$script:archiveCalls.Count})-eq3) '未YES只读预检，不apply'
    &$module {$script:archiveCalls.Clear();$script:answer='yes'}
    Assert-Throws {&$module {param($p)Invoke-JobsProjectDependencyArchiveAction $p import-native-dependencies} $project} '导入小写yes拒绝'
    &$module {$script:archiveCalls.Clear();$script:answer='YES'}
    &$module {param($p)Invoke-JobsProjectDependencyArchiveAction $p import-native-dependencies} $project
    $calls=@(&$module {$script:archiveCalls.ToArray()})
    Assert ($calls.Count-eq4-and$calls[3].EndsWith('|--confirm|YES')) '只有大写YES进入再次全量校验导入'
    Assert ($calls[3]-like '*|--target-root|*') '目标由本次环境明确传入，不采信快照绝对路径'
    &$module {$script:archiveCalls.Clear();$script:preflightFailure=$true}
    Assert-Throws {&$module {param($p)Invoke-JobsProjectDependencyArchiveAction $p import-native-dependencies} $project} '锁指纹或校验失败停止'
    Assert ((&$module {$script:archiveCalls.Count})-eq3) '预检失败没有apply'
    Assert ($env:PATH-ceq$savedPath) '失败后恢复进程环境'
    &$module {$script:archiveCalls.Clear();$script:preflightFailure=$false;$script:applyFailure=$true}
    Assert-Throws {&$module {param($p)Invoke-JobsProjectDependencyArchiveAction $p import-native-dependencies} $project} '等待确认后并发冲突仍失败传播'
    Assert ($env:PATH-ceq$savedPath) '执行期失败恢复环境'
    Write-Host ('PASS: FlutterDependencyArchiveShell.Tests.ps1 ('+$count+' assertions; isolated shell protocol only)')
}finally{
    Remove-Module $module -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temp -Recurse -Force
}

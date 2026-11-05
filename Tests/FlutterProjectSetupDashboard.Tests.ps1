# FlutterProjectSetupDashboard.Tests.ps1 | 阶段、原始输出与机器协议门禁。
# Created by Jobs on 2026年10月28日，星期三.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$count=0
function Assert($Value,[string]$Message){$script:count++;if(-not$Value){throw $Message}}
$tempBase=if([Environment]::OSVersion.Platform-eq[PlatformID]::Win32NT){[IO.Path]::GetTempPath()}else{'/private/tmp'}
$temp=Join-Path $tempBase ('jobs-setup-dashboard-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$oldSession=$env:JOBS_SETUP_SESSION;$env:JOBS_SETUP_SESSION=$temp
$module=Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetup.psm1') -PassThru -DisableNameChecking
$progress=Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetupProgress.psm1') -PassThru -DisableNameChecking
try{
 if([Environment]::OSVersion.Platform-eq[PlatformID]::Win32NT){
  # Windows CI 直接走系统 Framework csc，防止只经 pwsh Roslyn 验证产生假兼容。
  $csc=Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
  if(-not[IO.File]::Exists($csc)){$csc=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'}
  Assert ([IO.File]::Exists($csc)) 'Windows Framework csc 编译器必须可用'
  $compiled=Join-Path $temp 'FrameworkSetupProcess.dll'
  &$csc /nologo /noconfig /target:library /langversion:5 /reference:System.dll /reference:System.Core.dll ('/out:'+$compiled) (Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetupProcess.cs')
  Assert ($LASTEXITCODE-eq0-and[IO.File]::Exists($compiled)) '日志采集器必须通过系统 Framework C#5 编译'
 }
 Set-JobsSetupProgress sdk.flutter running '正在执行'
 Set-JobsSetupProgress sdk.flutter waiting '等待选择'
 Set-JobsSetupProgress sdk.flutter done '真实完成'
 $events=@([IO.File]::ReadAllLines((Join-Path $temp 'events.jsonl'))|ForEach-Object{$_|ConvertFrom-Json})
 Assert ($events.Count-eq3-and($events.state-join',')-ceq'running,waiting,done') '事件记录真实运行/等待/完成，无虚构百分比'
 Assert ($events[0].PSObject.Properties.Name-notcontains'percent') '事件不提供假百分比'
 Assert ((Get-JobsSetupActiveNode)-ceq'sdk.flutter') '子节点关联可供失败定位'
 $event=&$module{Get-JobsSetupMachineEvent '[{"event":"app.started","params":{"appId":"current"}}]'}
 Assert (&$module{param($e)Test-JobsSetupAppStarted 'current' $e}$event) '本次 appId 的 app.started 才通过'
 Assert (-not(&$module{param($e)Test-JobsSetupAppStarted 'other-session' $e}$event)) '其它会话启动事件不能冒充本次成功'
 Assert (-not(&$module{param($e)Test-JobsSetupAppStarted '' $e}$event)) '未见 app.start appId 时不能成功'
 Assert (@(&$module{Get-JobsSetupMachineEvent 'log: app.started current'}).Count-eq0) '普通日志文本不能冒充机器协议'
 Assert (@(&$module{Get-JobsSetupMachineEvent '[{"event":"app.started"}]'}).Count-eq0) '缺少 params 的事件拒绝'
 $event=&$module{Get-JobsSetupMachineEvent '[{"event":"app.started","params":{"message":"missing appId"}}]'}
 Assert (-not(&$module{param($e)Test-JobsSetupAppStarted 'current' $e}$event)) '缺少 appId 不能成功'
 # 顶层 JSON 数组在 Framework 5.1 也必须逐事件枚举，畸形对象只拒绝不抛错。
 $pair=@(&$module{Get-JobsSetupMachineEvent '[{"event":"app.start","params":{"appId":"current"}},{"event":"app.started","params":{"appId":"current"}}]'})
 Assert ($pair.Count-eq2-and$pair[0].event-ceq'app.start'-and$pair[1].event-ceq'app.started') '机器事件数组逐项解析，顺序不丢失'
 foreach($json in @('null','[null]','[{}]','[{"event":"app.started","params":null}]','[{"event":"app.started","params":"invalid"}]','[[{"event":"app.started","params":{"appId":"current"}}]]')){
  Assert (@(&$module{param($j)Get-JobsSetupMachineEvent $j}$json).Count-eq0) ('空值和畸形事件不进入启动判断：'+$json)
 }
 foreach($invalidEvent in @($null,[pscustomobject]@{},[pscustomobject]@{event='app.started'},[pscustomobject]@{event='app.started';params=$null})){
  Assert (-not(&$module{param($e)Test-JobsSetupAppStarted 'current' $e}$invalidEvent)) '启动门禁拒绝缺失字段而不产生属性异常'
 }
 &$module{
  function script:Invoke-JobsSetupProcess {param($f,$a,$p,$t)[pscustomobject]@{StdOut='[{"id":"android-fixture","name":"测试设备","targetPlatform":"android-arm64","isSupported":true}]';StdErr='';ExitCode=0}}
  function script:Select-JobsSetupChoice {param($f,$t,$items)$items[0]}
 }
 $device=&$module{param($p)Select-JobsSetupDevice $p ([pscustomobject]@{Flutter='fixture'}) 'fixture-fzf' 'Android'}$temp
 Assert ($device-ceq'android-fixture') '设备顶层数组在Windows5.1也返回精确目标ID'
 [void][IO.Directory]::CreateDirectory((Join-Path $temp 'android'))
 $readiness=&$module{param($p)Get-JobsSetupReadiness $p ([pscustomobject]@{Flutter='fixture'})}$temp
 Assert ($readiness.Ready-and$readiness.Issues.Count-eq0) '最终只读诊断不因Windows5.1数组包装误报无设备'
 $executable=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
 $start=&$module{
  param($file,$directory)
  $info=New-Object Diagnostics.ProcessStartInfo;$info.FileName=$file;$info.WorkingDirectory=$directory
  $body='[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false);[Console]::Out.WriteLine("原始 stdout <&> 字符");[Console]::Error.WriteLine("原始 stderr [!] 字符");exit 0'
  $info.Arguments=(@(@('-NoLogo','-NoProfile','-NonInteractive','-Command',$body)|ForEach-Object{Quote-JobsArgument $_})-join' ')
  $info
 }$executable $temp
 $runner=&$module{param($s)New-JobsSetupLiveProcess $s}$start
 try{
  $runner.Start();$clock=[Diagnostics.Stopwatch]::StartNew()
  while(-not$runner.HasExited-and$clock.Elapsed.TotalSeconds-lt15){Start-Sleep -Milliseconds 20}
  Assert $runner.HasExited '真实子进程按时结束'
  Assert ($runner.Drain(5000)-and$runner.ExitCode-eq0) 'stdout/stderr 异步并行读取无死锁'
  Assert ($runner.StdOut.Contains('原始 stdout <&> 字符')-and$runner.StdErr.Contains('原始 stderr [!] 字符')) '保持 stdout/stderr 原始文本'
  $raw=[IO.File]::ReadAllText((Join-Path $temp 'raw.log'))
  Assert ($raw.Contains('原始 stdout <&> 字符')-and$raw.Contains('原始 stderr [!] 字符')) '完整原始输出独立落盘，不被阶段摘要替代'
  Assert ([IO.File]::Exists((Join-Path $temp 'raw.log.stdout.bin'))-and[IO.File]::Exists((Join-Path $temp 'raw.log.stderr.bin'))) '原始字节双流独立保留，避免外部工具编码导致证据丢失'
  Assert (@($runner.TakeLines()).Count-eq2) '机器协议队列不漏掉两条原始输出'
 }finally{$runner.Dispose()}
 # 参数只作为 argv/env 值，不解释为 Shell；目标/Flavor/Defines 由实际文件建立。
 $project=Join-Path $temp '工程 & 空格';[void][IO.Directory]::CreateDirectory((Join-Path $project 'lib'))
 [void][IO.Directory]::CreateDirectory((Join-Path $project 'android/app'))
 [IO.File]::WriteAllText((Join-Path $project 'lib/main_test.dart'),'void main() {}')
 [IO.File]::WriteAllText((Join-Path $project 'android/app/build.gradle.kts'),'productFlavors { create("Test") { dimension = "env" } }')
 &$module{
  function script:Select-JobsSetupChoice {param($f,$title,$items)if($title-eq'Flavor'){'Test'}else{$items[0]}}
  function script:Read-JobsSetupInput {param($prompt,$node)''}
 } 
 $arguments=&$module{param($p)Get-JobsSetupRunArguments $p 'fixture-fzf' 'device-safe' 'Android'}$project
 Assert ('--machine'-in$arguments-and'--target'-in$arguments-and'lib/main_test.dart'-in$arguments) '运行使用机器协议及所选实际入口'
 Assert ('--flavor'-in$arguments-and'Test'-in$arguments) '所选 flavor 作为独立参数保留'
 $start=&$module{param($a)New-JobsSetupBatchStart 'cmd.exe' 'C:\SDK % & 中文\flutter.bat' $a 'C:\工程 空格'}$arguments
 Assert ($start.Arguments-notmatch'main_test|device-safe') '用户参数不拼接进 CMD 源码'
 Assert ($start.EnvironmentVariables['JOBS_SETUP_ARGUMENT_0']-ceq'run') '真实 argv 通过独立环境载体传入'
 $dashboard=[IO.File]::ReadAllText((Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetupDashboard.ps1'))
 # 直接执行仪表盘的状态/布局函数和活动回调，临时对象不创建窗口或启动业务。
 $parseErrors=$null
 $dashboardAst=[Management.Automation.Language.Parser]::ParseInput($dashboard,[ref]$null,[ref]$parseErrors)
 Assert ($parseErrors.Count-eq0) '仪表盘源码可解析'
 foreach($name in @('Get-JobsSetupStatusText','Get-JobsSetupMilestoneHeight')){
  $function=$dashboardAst.Find({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq$name},$true)
  Assert ($null-ne$function) ('可执行的仪表盘函数存在：'+$name)
  Set-Item ('Function:'+ $name) $function.Body.GetScriptBlock()
 }
 $frames=@(0..6|ForEach-Object{Get-JobsSetupStatusText running $_})
 Assert (($frames-join'|')-ceq'◉ 进行中|◉ 进行中.|◉ 进行中..|◉ 进行中...|◉ 进行中....|◉ 进行中.....|◉ 进行中') '进行中真实文案按0至5点循环再归零'
 foreach($state in @('done','failed','waiting','attention','skipped','pending')){
  Assert ((Get-JobsSetupStatusText $state 5)-notmatch'\.') ('非进行中状态清除圆点：'+$state)
 }
 Assert ((Get-JobsSetupMilestoneHeight @(100,196,148) 500)-eq196) '流程高度取实际内容最大值'
 Assert ((Get-JobsSetupMilestoneHeight @(100,196,148) 900)-eq196) '扩大窗口不按比例撑高流程区'
 Assert ((Get-JobsSetupMilestoneHeight @(100,196,148) 300)-eq112) '内容超高时保留终端最小高度供流程滚动'
 Assert ((Get-JobsSetupMilestoneHeight @() 500)-eq64) '空内容仍保留可拖动的最小流程高度'
 $activityAst=$dashboardAst.Find({param($node)$node-is[Management.Automation.Language.InvokeMemberExpressionAst]-and$node.Expression.Extent.Text-ceq'$activityTimer'-and$node.Member.Value-ceq'Add_Tick'},$true)
 $activity=$activityAst.Arguments[0].ScriptBlock.GetScriptBlock()
 $states=@{active='running';done='done';waiting='waiting'}
 $labels=@{active=[pscustomobject]@{Text='◉ 进行中';ForeColor='blue'};done=[pscustomobject]@{Text='✓ 已完成';ForeColor='green'};waiting=[pscustomobject]@{Text='! 等待用户';ForeColor='orange'}}
 $script:runningDotFrame=0
 foreach($dots in @(1,2,3,4,5,0)){
  & $activity
  Assert ($labels.active.Text-ceq('◉ 进行中'+('.'*$dots))) '真实计时回调推进当前执行节点'
 }
 Assert ($labels.done.Text-ceq'✓ 已完成'-and$labels.waiting.Text-ceq'! 等待用户') '计时回调保留完成和等待状态'
 $stopAst=$dashboardAst.Find({param($node)$node-is[Management.Automation.Language.AssignmentStatementAst]-and$node.Left.Extent.Text-ceq'$stopActivity'},$true)
 $stop=$stopAst.Right.Find({param($node)$node-is[Management.Automation.Language.ScriptBlockExpressionAst]},$true).ScriptBlock.GetScriptBlock()
 $activityTimer=[pscustomobject]@{Stopped=$false};$activityTimer|Add-Member ScriptMethod Stop {$this.Stopped=$true}
 $colors=@{attention='orange';pending='gray';done='green';waiting='orange';running='blue';failed='red'}
 $groups=@(,@('fixture','active','活动节点','done','完成节点'));$heads=@([pscustomobject]@{ForeColor='blue'})
 $refreshAst=$dashboardAst.Find({param($node)$node-is[Management.Automation.Language.AssignmentStatementAst]-and$node.Left.Extent.Text-ceq'$refreshGroupHeads'},$true)
 $refreshGroupHeads=$refreshAst.Right.Find({param($node)$node-is[Management.Automation.Language.ScriptBlockExpressionAst]},$true).ScriptBlock.GetScriptBlock()
 & $stop
 Assert ($activityTimer.Stopped-and$states.active-ceq'attention'-and$labels.active.Text-ceq'! 需确认状态'-and$heads[0].ForeColor-ceq'orange') '流程结束停止计时并清除遗留执行点、更新组状态'
 & $activity
 Assert ($labels.active.Text-ceq'! 需确认状态') '终态节点即使收到额外计时回调也保持静止'
 Assert ($dashboard.Contains('SetParent')-and$dashboard.Contains('conhost.exe')-and$dashboard.Contains('MoveWindow')) '真实控制台嵌入实现，不以纯日志假装终端'
 Assert ($dashboard.Contains('系统未允许嵌入')-and$dashboard.Contains('独立 CMD')) '原生限制有明确回退'
 Assert ($dashboard.Contains('/PID')-and$dashboard.Contains('DialogResult]::No')) '关闭可停止本次树或转独立终端'
 Write-Host ('PASS: FlutterProjectSetupDashboard.Tests.ps1 ('+$count+' assertions; native WinForms/conhost embedding not exercised here)')
}finally{
 Remove-Module $module,$progress
 if($null-eq$oldSession){Remove-Item Env:JOBS_SETUP_SESSION -ErrorAction SilentlyContinue}else{$env:JOBS_SETUP_SESSION=$oldSession}
 Remove-Item -LiteralPath $temp -Recurse -Force
}

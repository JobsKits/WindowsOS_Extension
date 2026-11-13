# FlutterProjectSetupDashboard.Tests.ps1 | 阶段、原始输出与机器协议门禁。
# Created by Jobs on 2026年10月28日，星期三.
# BEGIN JOBS_TERMINAL_STYLE_V1 - session-only colors; no profile or registry changes.
function New-JobsTerminalStyleState {
    if ($PSVersionTable.PSVersion.Major -lt 5) { return @{ JobsTerminalPlainFallback = $true; Before = @{} } }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $Host.Name -ne 'ConsoleHost') { return $null }
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected -or [Console]::IsErrorRedirected) { return $null }
    if ((Test-Path Env:NO_COLOR) -or $env:TERM -ieq 'dumb' -or $env:PLAIN_OUTPUT -eq '1') { return $null }
    foreach ($key in [Environment]::GetEnvironmentVariables().Keys) {
        if ([string]$key -match '^(?i:SOURCE_?TREE)') { return $null }
    }
    if (-not ('Jobs.TerminalStyleV1.Native' -as [type])) {
        try {
        Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
namespace Jobs.TerminalStyleV1 {
    public static class Native {
        [StructLayout(LayoutKind.Explicit, Size=20, CharSet=CharSet.Unicode)]
        public struct InputRecord {
            [FieldOffset(0)] public ushort Kind;
            [FieldOffset(4)] public int Down;
            [FieldOffset(8)] public ushort Repeat;
            [FieldOffset(10)] public ushort Key;
            [FieldOffset(12)] public ushort Scan;
            [FieldOffset(14)] public char Character;
            [FieldOffset(16)] public uint Modifiers;
        }
        [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int n);
        [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
        [DllImport("kernel32.dll")] static extern bool GetConsoleMode(IntPtr h, out uint mode);
        [DllImport("kernel32.dll")] static extern bool SetConsoleMode(IntPtr h, uint mode);
        [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h, uint milliseconds);
        [DllImport("kernel32.dll")] static extern bool GetNumberOfConsoleInputEvents(IntPtr h, out uint count);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, ExactSpelling=true)] static extern bool ReadConsoleInputW(IntPtr h, [Out] InputRecord[] records, uint count, out uint read);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, ExactSpelling=true)] static extern bool WriteConsoleInputW(IntPtr h, InputRecord[] records, uint count, out uint written);
        const string OwnerName = "JOBS_TERMINAL_STYLE_WINDOWS_OWNER";
        static readonly string[] Keys = { "10", "11", "4;0", "4;1", "4;2", "4;3", "4;4", "4;5", "4;6", "4;7", "4;8", "4;9", "4;10", "4;11", "4;12", "4;13", "4;14", "4;15" };
        static readonly string[] Hex = { "000000", "ff5f56", "5fd787", "ffd75f", "5fafff", "d787ff", "5fd7ff", "eeeeee", "9e9e9e", "ff8787", "87ffaf", "ffff87", "87bfff", "ffafff", "afffff", "ffffff" };
        static readonly Regex Reply = new Regex("\\x1b\\](?<key>10|11|4;[0-9]{1,2});(?<rgb>rgb:[0-9a-f]{1,4}/[0-9a-f]{1,4}/[0-9a-f]{1,4})(?:\\x07|\\x1b\\\\)", RegexOptions.IgnoreCase);
        public sealed class State {
            public IntPtr Input, Output;
            public uint OutputMode;
            public ConsoleColor Foreground, Background;
            public Dictionary<string,string> Original, Applied;
            public string Owner, PreviousOwner, Recovery;
            public bool Active, ModeChanged, Fallback;
            public Dictionary<string,string> EnvironmentBefore = new Dictionary<string,string>();
        }
        static string Escape(string key, string value) { return "\x1b]" + key + ";" + value + "\x07"; }
        static string Rgb(string hex) { return "rgb:" + hex.Substring(0,2) + "/" + hex.Substring(2,2) + "/" + hex.Substring(4,2); }
        static string Normal(string rgb) {
            string[] parts = rgb.Substring(4).Split('/');
            for (int n=0; n<3; n++) {
                int maximum = (1 << (4 * parts[n].Length)) - 1;
                int value = Convert.ToInt32(parts[n],16);
                parts[n] = ((value * 65535L + maximum/2) / maximum).ToString("x4");
            }
            return String.Join("/",parts);
        }
        // Preserve unrelated key/window records instead of consuming user input during color queries.
        static Dictionary<string,string> Query(State state) {
            uint pending;
            if (!GetNumberOfConsoleInputEvents(state.Input,out pending) || pending != 0) { return null; }
            StringBuilder commands = new StringBuilder();
            foreach (string key in Keys) { commands.Append(Escape(key,"?")); }
            Console.Write(commands.ToString());
            List<InputRecord> records = new List<InputRecord>();
            List<int> characterIndices = new List<int>();
            StringBuilder text = new StringBuilder();
            Dictionary<string,string> result = new Dictionary<string,string>();
            Stopwatch timer = Stopwatch.StartNew();
            try {
                while (timer.ElapsedMilliseconds < 600) {
                    if (result.Count == Keys.Length && GetNumberOfConsoleInputEvents(state.Input,out pending) && pending == 0) { break; }
                    if (WaitForSingleObject(state.Input,20) != 0) { continue; }
                    InputRecord[] item = new InputRecord[1]; uint read;
                    if (!ReadConsoleInputW(state.Input,item,1,out read) || read != 1) { break; }
                    int index = -1;
                    if (item[0].Kind == 1 && item[0].Character != '\0') {
                        if (item[0].Down != 0) { index = text.Length; text.Append(item[0].Character); }
                        else if (text.Length != 0 && text[text.Length-1] == item[0].Character) { index = text.Length-1; }
                    }
                    records.Add(item[0]); characterIndices.Add(index);
                    foreach (Match match in Reply.Matches(text.ToString())) {
                        string key = match.Groups["key"].Value;
                        if (Array.IndexOf(Keys,key) >= 0) { result[key] = match.Groups["rgb"].Value; }
                    }
                }
            } finally {
                bool[] used = new bool[text.Length];
                foreach (Match match in Reply.Matches(text.ToString())) {
                    for (int n=match.Index; n<match.Index+match.Length; n++) { used[n] = true; }
                }
                List<InputRecord> replay = new List<InputRecord>();
                for (int n=0; n<records.Count; n++) {
                    int index = characterIndices[n];
                    if (index < 0 || !used[index]) { replay.Add(records[n]); }
                }
                if (replay.Count != 0) {
                    uint written;
                    if (!WriteConsoleInputW(state.Input,replay.ToArray(),(uint)replay.Count,out written) || written != replay.Count) {
                        Console.Error.WriteLine("[Jobs] Could not replay terminal input; color protection is unavailable.");
                        result.Clear();
                    }
                }
            }
            return result.Count == Keys.Length ? result : null;
        }
        static void Plain(State state) {
            foreach (string key in new string[] { "NO_COLOR", "PLAIN_OUTPUT", "FORCE_COLOR", "CLICOLOR", "ANSI_COLORS_DISABLED" }) {
                state.EnvironmentBefore[key] = Environment.GetEnvironmentVariable(key);
                Environment.SetEnvironmentVariable(key, key == "FORCE_COLOR" || key == "CLICOLOR" ? "0" : "1");
            }
            state.Fallback = true;
        }
        public static void Enter(State state) {
            try {
                state.Input = GetStdHandle(-10); state.Output = GetStdHandle(-11);
                uint inputMode;
                if (!GetConsoleMode(state.Input,out inputMode) || !GetConsoleMode(state.Output,out state.OutputMode)) { Plain(state); return; }
                IntPtr window = GetConsoleWindow();
                if (window == IntPtr.Zero) { Plain(state); return; }
                string identity = window.ToInt64().ToString("x");
                state.PreviousOwner = Environment.GetEnvironmentVariable(OwnerName);
                if (!String.IsNullOrEmpty(state.PreviousOwner)) {
                    string[] owner = state.PreviousOwner.Split(':');
                    int pid; long started;
                    if (owner.Length == 3 && owner[0] == identity && Int32.TryParse(owner[1],out pid) && Int64.TryParse(owner[2],out started)) {
                        try { if (Process.GetProcessById(pid).StartTime.ToUniversalTime().Ticks == started) { return; } } catch {}
                    }
                }
                state.Foreground = Console.ForegroundColor; state.Background = Console.BackgroundColor;
                if ((state.OutputMode & 4) == 0) {
                    if (!SetConsoleMode(state.Output,state.OutputMode | 4)) { Plain(state); return; }
                    state.ModeChanged = true;
                }
                state.Original = Query(state);
                if (state.Original == null) { Restore(state); Plain(state); return; }
                state.Applied = new Dictionary<string,string>();
                state.Applied["10"] = "rgb:ff/ff/ff"; state.Applied["11"] = "rgb:00/00/00";
                for (int n=0; n<16; n++) { state.Applied["4;"+n] = Rgb(Hex[n]); }
                StringBuilder restore = new StringBuilder();
                foreach (string key in Keys) { restore.Append(Escape(key,state.Original[key])); }
                string encoded = Convert.ToBase64String(Encoding.UTF8.GetBytes(restore.ToString()));
                state.Recovery = Path.Combine(Path.GetTempPath(),"JobsTerminalStyle-"+Process.GetCurrentProcess().Id+"-"+Guid.NewGuid().ToString("N")+".ps1");
                string manual = "# Restore only the session colors saved by this Jobs script.\r\n"+
                    "if ([Console]::IsOutputRedirected) { throw 'Run in the original console.' }\r\n"+
                    "Add-Type -Namespace Jobs -Name RecoveryConsole -MemberDefinition '[System.Runtime.InteropServices.DllImport(\"kernel32.dll\")] public static extern System.IntPtr GetStdHandle(int n); [System.Runtime.InteropServices.DllImport(\"kernel32.dll\")] public static extern bool GetConsoleMode(System.IntPtr h, out uint m); [System.Runtime.InteropServices.DllImport(\"kernel32.dll\")] public static extern bool SetConsoleMode(System.IntPtr h, uint m);'\r\n"+
                    "$h = [Jobs.RecoveryConsole]::GetStdHandle(-11); [uint32]$m = 0\r\n"+
                    "if (-not [Jobs.RecoveryConsole]::GetConsoleMode($h, [ref]$m)) { throw 'Run in the original console.' }\r\n"+
                    "try {\r\nif (-not [Jobs.RecoveryConsole]::SetConsoleMode($h, ($m -bor 4))) { throw 'Cannot enable terminal recovery.' }\r\n"+
                    "[Console]::Write([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('"+encoded+"')))\r\n"+
                    "[Console]::ForegroundColor = [ConsoleColor]"+((int)state.Foreground)+"\r\n"+
                    "[Console]::BackgroundColor = [ConsoleColor]"+((int)state.Background)+"\r\n"+
                    "[Console]::Write([string][char]27 + '[39;49m')\r\n"+
                    "} finally { [void][Jobs.RecoveryConsole]::SetConsoleMode($h, $m) }\r\n";
                File.WriteAllText(state.Recovery,manual,new UTF8Encoding(false));
                state.Owner = identity+":"+Process.GetCurrentProcess().Id+":"+Process.GetCurrentProcess().StartTime.ToUniversalTime().Ticks;
                Environment.SetEnvironmentVariable(OwnerName,state.Owner);
                state.Active = true;
                foreach (string key in Keys) { Console.Write(Escape(key,state.Applied[key])); }
                Console.ForegroundColor = ConsoleColor.White; Console.BackgroundColor = ConsoleColor.Black;
                Dictionary<string,string> check = Query(state);
                foreach (string key in Keys) {
                    if (check == null || Normal(check[key]) != Normal(state.Applied[key])) { Restore(state); Plain(state); return; }
                }
            } catch (Exception error) {
                Restore(state); Plain(state);
                Console.Error.WriteLine("[Jobs] Terminal style unavailable: " + error.Message);
            }
        }
        public static void Restore(State state) {
            if (state == null) { return; }
            try {
                if (state.Active) {
                    Dictionary<string,string> current = Query(state);
                    bool complete = current != null;
                    if (current != null) {
                        bool restoreForeground = Console.ForegroundColor == ConsoleColor.White && Normal(current["10"]) == Normal(state.Applied["10"]) && Normal(current["4;15"]) == Normal(state.Applied["4;15"]);
                        bool restoreBackground = Console.BackgroundColor == ConsoleColor.Black && Normal(current["11"]) == Normal(state.Applied["11"]) && Normal(current["4;0"]) == Normal(state.Applied["4;0"]);
                        foreach (string key in Keys) {
                            if (Normal(current[key]) == Normal(state.Applied[key])) { Console.Write(Escape(key,state.Original[key])); }
                            else if (Normal(current[key]) != Normal(state.Original[key])) {
                                complete = false; Console.Error.WriteLine("[Jobs] Kept a concurrent color change: " + key);
                            }
                        }
                        if (restoreForeground) { Console.ForegroundColor = state.Foreground; Console.Write("\x1b[39m"); }
                        if (restoreBackground) { Console.BackgroundColor = state.Background; Console.Write("\x1b[49m"); }
                    }
                    if (complete) {
                        Dictionary<string,string> check = Query(state);
                        foreach (string key in Keys) { if (check == null || Normal(check[key]) != Normal(state.Original[key])) { complete = false; } }
                    }
                    if (complete) { File.Delete(state.Recovery); }
                    else { Console.Error.WriteLine("[Jobs] Color restore needs review. Manual recovery: powershell -NoProfile -File \""+state.Recovery+"\""); }
                }
            } catch (Exception error) {
                Console.Error.WriteLine("[Jobs] Color restore failed: "+error.Message+"; recovery: "+state.Recovery);
            } finally {
                if (state.Owner != null && Environment.GetEnvironmentVariable(OwnerName) == state.Owner) { Environment.SetEnvironmentVariable(OwnerName,state.PreviousOwner); }
                state.Active = false;
                uint currentMode;
                if (state.ModeChanged && GetConsoleMode(state.Output,out currentMode) && currentMode == (state.OutputMode | 4)) { SetConsoleMode(state.Output,state.OutputMode); }
                state.ModeChanged = false;
                if (state.Fallback) {
                    foreach (KeyValuePair<string,string> pair in state.EnvironmentBefore) {
                        string applied = pair.Key == "FORCE_COLOR" || pair.Key == "CLICOLOR" ? "0" : "1";
                        if (Environment.GetEnvironmentVariable(pair.Key) == applied) { Environment.SetEnvironmentVariable(pair.Key,pair.Value); }
                    }
                    state.Fallback = false;
                }
            }
        }
    }
}
'@
        } catch {
            [Console]::Error.WriteLine('[Jobs] Terminal style setup failed; using plain output: ' + $_.Exception.Message)
            return @{ JobsTerminalPlainFallback = $true; Before = @{} }
        }
    }
    return New-Object Jobs.TerminalStyleV1.Native+State
}
# Guard setup is optional; failure keeps business behavior and the user's original terminal settings.
function Start-JobsTerminalStyle {
    param($State)
    if ($State -is [Collections.IDictionary] -and $State.Contains('JobsTerminalPlainFallback')) {
        foreach ($key in @('NO_COLOR', 'PLAIN_OUTPUT', 'FORCE_COLOR', 'CLICOLOR', 'ANSI_COLORS_DISABLED')) {
            $State.Before[$key] = [Environment]::GetEnvironmentVariable($key)
            [Environment]::SetEnvironmentVariable($key, $(if (@('FORCE_COLOR', 'CLICOLOR') -contains $key) { '0' } else { '1' }))
        }
        return
    }
    if ($null -ne $State) { [Jobs.TerminalStyleV1.Native]::Enter($State) }
}
# A finally block also runs for script exit and Ctrl+C; direct .NET calls avoid stopped pipelines.
function Stop-JobsTerminalStyle {
    param($State)
    if ($State -is [Collections.IDictionary] -and $State.Contains('JobsTerminalPlainFallback')) {
        foreach ($key in $State.Before.Keys) {
            $applied = if (@('FORCE_COLOR', 'CLICOLOR') -contains $key) { '0' } else { '1' }
            if ([Environment]::GetEnvironmentVariable($key) -ceq $applied) { [Environment]::SetEnvironmentVariable($key, $State.Before[$key]) }
        }
        return
    }
    if ($null -ne $State) { [Jobs.TerminalStyleV1.Native]::Restore($State) }
}
# END JOBS_TERMINAL_STYLE_V1

$__jobsTerminalStyleState = $null
try {
    if ($MyInvocation.InvocationName -ne '.') {
        $__jobsTerminalStyleState = New-JobsTerminalStyleState
        Start-JobsTerminalStyle $__jobsTerminalStyleState
    }
# BEGIN JOBS_TERMINAL_STYLE_ORIGINAL_BODY
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

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

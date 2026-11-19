# FlutterDependencyMigration.Tests.ps1 | 隔离验证终端选择、ZIP 证据与融合确认。
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
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$count = 0
function Assert($Value,[string]$Message) { $script:count++; if (-not $Value) { throw $Message } }
function Assert-Throws([scriptblock]$Body,[string]$Message) { $failed=$false;try { &$Body | Out-Null } catch { $failed=$true }; Assert $failed $Message }
$tempBase = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { [IO.Path]::GetTempPath() } else { '/private/tmp' }
$temp = Join-Path $tempBase ('JobsMigrationTests-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$module = Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/FlutterDependencyMigration.psm1/FlutterDependencyMigration.psm1') -PassThru -DisableNameChecking
try {
    $bundle = Join-Path $temp 'bundle with 空格'
    [void][IO.Directory]::CreateDirectory((Join-Path $bundle '.hidden'))
    [IO.File]::WriteAllText((Join-Path $bundle '.hidden/value.txt'),'private-source-bytes')
    [IO.File]::WriteAllText((Join-Path $bundle 'manifest.json'),'{}')
    $zip = &$module { param($p) Compress-JobsMigrationBundle $p } $bundle
    Assert ([IO.File]::Exists($zip)) '生成真实 ZIP'
    &$module { param($p,$z) Assert-JobsMigrationZip $p $z } $bundle $zip
    Assert $true '逐文件校验包含隐藏目录'
    Assert-Throws { &$module { param($p) Compress-JobsMigrationBundle $p } $bundle } '已有 ZIP 不覆盖'
    [IO.File]::WriteAllText((Join-Path $bundle '.hidden/value.txt'),'changed')
    Assert-Throws { &$module { param($p,$z) Assert-JobsMigrationZip $p $z } $bundle $zip } '产物变动拒绝删除'
    Assert ([IO.File]::Exists((Join-Path $bundle '.hidden/value.txt'))) '失败仍保留原目录'
    $drag = '"' + $bundle + '"'
    Assert ((&$module {param($p)ConvertFrom-JobsMigrationPath $p} $drag) -ceq $bundle) '引号路径按数据解析'
    Assert-Throws { &$module { ConvertFrom-JobsMigrationPath '$(touch bad)' } } '不执行命令表达式'
    Assert-Throws { &$module { Get-JobsMigrationConflictCount 'missing marker' } } '没有冲突计数的旧引擎不能默认进入覆盖'
    Assert-Throws { &$module { Get-JobsMigrationConflictCount "JOBS_MIGRATION_CONFLICTS=1`nJOBS_MIGRATION_CONFLICTS=2" } } '多个冲突计数拒绝歧义计划'
    Assert-Throws { &$module { Get-JobsMigrationConflictCount 'JOBS_MIGRATION_CONFLICTS=-1' } } '无效冲突计数拒绝'
    $project = Join-Path $temp 'project'
    $destination = Join-Path $temp 'output'
    $raw = Join-Path $temp 'renamed-cache'
    foreach($path in @($project,$destination,$raw)) { [void][IO.Directory]::CreateDirectory($path) }
    $runtime = (Get-Process -Id $PID).Path
    $waitWorker = Join-Path $temp 'wait worker 中文.ps1'
    [IO.File]::WriteAllText($waitWorker, @'
param([string]$Mode,[string]$Marker)
if ($Marker) { [IO.File]::WriteAllText($Marker, [string]$PID) }
if ($Mode -ceq 'streams') {
    [Console]::Out.Write(('o' * 131072))
    [Console]::Error.Write(('e' * 131072))
    exit 7
}
if ($Mode -ceq 'plain') { Start-Sleep -Milliseconds 10200; exit 0 }
if ($Mode -ceq 'quiet') { Start-Sleep -Milliseconds 2200; [Console]::Out.Write('JOBS_MIGRATION_PLAN=fixture'); exit 0 }
Start-Sleep -Seconds 120
'@, (New-Object Text.UTF8Encoding($true)))
    $waitLog = Join-Path $temp 'wait-progress.log'
    &$module {
        param($Log)
        $script:MigrationLog=$Log
        $script:realElapsedConsole=${function:Test-JobsMigrationElapsedConsole}
        $script:waitDisplay=New-Object 'Collections.Generic.List[object]'
        function script:Test-JobsMigrationElapsedConsole { return $true }
        function script:Write-Host {param($Object,[switch]$NoNewline)$script:waitDisplay.Add([pscustomobject]@{Text=[string]$Object;NoNewline=[bool]$NoNewline})}
    } $waitLog
    Assert ((&$module {Format-JobsMigrationElapsed ([TimeSpan]::FromMinutes(2970))}) -ceq '49:30:00') '累计耗时超过一天仍保留完整小时'
    $waitClock = [Diagnostics.Stopwatch]::StartNew()
    $waitResult = &$module {param($r,$f,$p)Invoke-JobsMigrationProcess $r @('-NoProfile','-File',$f,'quiet') $p '扫描并校验导入计划'} $runtime $waitWorker $project
    $waitClock.Stop()
    $display = @(&$module {$script:waitDisplay.ToArray()})
    Assert ($waitResult.ExitCode-eq0 -and $waitResult.StdOut-ceq'JOBS_MIGRATION_PLAN=fixture') '静默进程完成后保持退出码和原始计划输出，计时不混入返回值'
    Assert ($display[0].Text-like'*已耗时 00:00:00*' -and @($display|Where-Object {$_.NoNewline-and$_.Text-like'*已耗时 00:00:0[12]*'}).Count-ge2) '交互阶段立即提示且静默期间逐秒刷新真实耗时'
    $completion = [regex]::Match($display[-1].Text, '完成.*总用时 (?<hours>\d{2,}):(?<minutes>[0-5]\d):(?<seconds>[0-5]\d)$')
    Assert ($completion.Success -and -not $display[-1].NoNewline) '完成后独立换行汇总耗时，不留活动计时行'
    $reportedSeconds = [long]$completion.Groups['hours'].Value * 3600 + [int]$completion.Groups['minutes'].Value * 60 + [int]$completion.Groups['seconds'].Value
    # 子PowerShell启动也计入真实阶段耗时；按外层时钟验值，不把固定秒数当作机器性能要求。
    Assert ($reportedSeconds -ge 2 -and $reportedSeconds -le $waitClock.Elapsed.TotalSeconds -and $waitClock.Elapsed.TotalSeconds - $reportedSeconds -lt 2) '完成汇总按真实阶段计时，包含子进程启动且仅舍去秒的小数部分'
    $displayCount=$display.Count
    Start-Sleep -Milliseconds 1100
    Assert ((&$module {$script:waitDisplay.Count})-eq$displayCount) '阶段结束后不再有后台计时输出'
    $waitResult = &$module {param($r,$f,$p)Invoke-JobsMigrationProcess $r @('-NoProfile','-File',$f,'streams') $p '双流输出夹具'} $runtime $waitWorker $project
    Assert ($waitResult.ExitCode-eq7-and$waitResult.StdOut.Length-eq131072-and$waitResult.StdErr.Length-eq131072) '非零退出和双流大输出均原样返回，未因缓冲区阻塞'
    Assert ((&$module {$script:waitDisplay[-1].Text})-like'*失败（退出码 7）*总用时*') '失败显示真实退出码和阶段耗时'
    &$module {function script:Test-JobsMigrationElapsedConsole {return $false};$script:waitDisplay.Clear()}
    [void](&$module {param($r,$f,$p)Invoke-JobsMigrationProcess $r @('-NoProfile','-File',$f,'plain') $p '纯文本扫描夹具'} $runtime $waitWorker $project)
    $display=@(&$module {$script:waitDisplay.ToArray()})
    Assert ($display.Count-eq3-and$display[1].Text-like'*已耗时 00:00:10*') '非交互阶段开始、十秒心跳和完成各输出完整行'
    Assert (@($display|Where-Object {$_.NoNewline-or$_.Text.Contains("`r")-or$_.Text.Contains([string][char]27)}).Count-eq0) '纯文本和重定向不输出原位刷新或ANSI控制'
    $timeoutMarker = Join-Path $temp 'timed-out.pid'
    # 按刚测得的子宿主启动耗时留出启动窗口，确保验证的是活进程回收而非解释器尚未执行。
    $timeoutLimit = [int][Math]::Max(5, [Math]::Ceiling($waitClock.Elapsed.TotalSeconds) + 2)
    $timeoutClock = [Diagnostics.Stopwatch]::StartNew()
    $timeoutFailure = $null
    try { &$module {param($r,$f,$p,$m,$limit)Invoke-JobsMigrationProcess $r @('-NoProfile','-File',$f,'sleep',$m) $p '超时扫描夹具' $limit} $runtime $waitWorker $project $timeoutMarker $timeoutLimit } catch { $timeoutFailure = $_.Exception.GetBaseException() }
    $timeoutClock.Stop()
    Assert ($timeoutFailure -is [TimeoutException] -and $timeoutClock.Elapsed.TotalSeconds -ge $timeoutLimit -and $timeoutClock.Elapsed.TotalSeconds -lt $timeoutLimit + 15) '真实超时在配置期限后传播，进程树清理有界完成'
    Assert ([IO.File]::Exists($timeoutMarker)) '超时夹具已进入脚本，随后验证该真实子进程被回收'
    $timedOutPid=[int][IO.File]::ReadAllText($timeoutMarker)
    Assert ($null-eq(Get-Process -Id $timedOutPid -ErrorAction SilentlyContinue)) '超时后实际进程已经停止'
    Assert-Throws {&$module {param($p)Invoke-JobsMigrationProcess (Join-Path $p 'missing-runtime') @() $p '启动失败夹具'} $project} '无法启动时仍结束计时并传播原失败'
    $waitLogText=[IO.File]::ReadAllText($waitLog)
    Assert ($waitLogText-like'*纯文本扫描夹具｜已耗时 00:00:10*'-and$waitLogText-like'*失败（退出码 7）*'-and-not$waitLogText.Contains([string][char]27)) '落盘日志保留阶段心跳和结果且没有ANSI'
    &$module {Set-Item Function:script:Test-JobsMigrationElapsedConsole $script:realElapsedConsole;Remove-Item Function:script:Write-Host;$script:MigrationLog=$null}
    $cancelMarker=Join-Path $temp 'cancelled.pid'
    $cancelLog=Join-Path $temp 'cancelled.log'
    $pipeline=[PowerShell]::Create()
    try {
        [void]$pipeline.AddScript({param($modulePath,$runtime,$worker,$project,$marker,$log)
            $module=Import-Module $modulePath -PassThru -DisableNameChecking
            &$module {param($r,$f,$p,$m,$log)$script:MigrationLog=$log;Invoke-JobsMigrationProcess $r @('-NoProfile','-File',$f,'sleep',$m) $p '取消扫描夹具'} $runtime $worker $project $marker $log
        }).AddArgument($module.Path).AddArgument($runtime).AddArgument($waitWorker).AddArgument($project).AddArgument($cancelMarker).AddArgument($cancelLog)
        $pending=$pipeline.BeginInvoke()
        $readyClock=[Diagnostics.Stopwatch]::StartNew()
        while(-not[IO.File]::Exists($cancelMarker)-and$readyClock.Elapsed.TotalSeconds-lt10){Start-Sleep -Milliseconds 100}
        Assert ([IO.File]::Exists($cancelMarker)) '取消夹具确认真实扫描子进程已启动'
        $cancelledPid=[int][IO.File]::ReadAllText($cancelMarker)
        $pipeline.Stop()
        Assert ($null-eq(Get-Process -Id $cancelledPid -ErrorAction SilentlyContinue)) 'PowerShell管道中断执行finally，清理真实扫描子进程'
        Assert ($pipeline.InvocationStateInfo.State-eq[Management.Automation.PSInvocationState]::Stopped) '取消保持Stopped状态，不误报完成'
        Assert ([IO.File]::ReadAllText($cancelLog)-like'*已停止（失败或取消）*总用时*') '可捕获取消同样在日志记录阶段停止与耗时'
    } finally {$pipeline.Dispose()}
    &$module {
        param($t)
        $script:realMigrationDart=${function:Get-JobsMigrationDart}
        $script:fixture=$t
        $script:answers=New-Object 'Collections.Generic.Queue[string]'
        $script:calls=New-Object 'Collections.Generic.List[string]'
        $script:failPreview=$false
        $script:omitPlan=$false
        $script:conflictCount=0
        $script:created=''
        function script:Find-JobsExecutable { return $null }
        function script:Get-JobsMigrationDesktop { return (Join-Path $script:fixture 'output') }
        function script:Read-JobsMigrationLine {
            param($Prompt)
            if ($script:answers.Count-eq0) { throw ('fixture exhausted: '+$Prompt) }
            $value = $script:answers.Dequeue()
            if ($value -ceq '__EOF__') { return $null }
            if ($value -ceq '__INTERRUPT__') { throw (New-Object OperationCanceledException) }
            return $value
        }
        function script:Get-JobsMigrationDart {param($p)'fixture-dart'}
        function script:Invoke-JobsMigrationEngine {
            param($Dart,[string[]]$Arguments,$Project)
            $script:calls.Add(($Arguments-join '|'))
            if ($Arguments[0]-eq'import') {
                if ($script:failPreview) { throw 'fixture conflict' }
                if ($script:omitPlan) { return 'JOBS_MIGRATION_CONFLICTS=0' }
                $fingerprint = if ($Arguments -contains '--conflict-policy') { '1' * 64 } else { '0' * 64 }
                return 'JOBS_MIGRATION_CONFLICTS=' + $script:conflictCount + "`nJOBS_MIGRATION_PLAN=" + $fingerprint
            }
            $script:created=Join-Path (Join-Path $script:fixture 'output') ('created-'+[guid]::NewGuid().ToString('N'))
            [void][IO.Directory]::CreateDirectory($script:created)
            [IO.File]::WriteAllText((Join-Path $script:created 'manifest.json'),'{}')
            [IO.File]::WriteAllText((Join-Path $script:created '.private'),'payload')
            return 'JOBS_MIGRATION_OUTPUT='+$script:created
        }
    } $temp
    &$module {param($p,$d)$script:answers.Clear();foreach($a in @('','',$d,'skip')){$script:answers.Enqueue($a)};Invoke-JobsFlutterMigration $p export-all-dependencies} $project $destination
    $calls=@(&$module {$script:calls.ToArray()})
    Assert ($calls.Count-eq1 -and $calls[0]-notlike '*--all*') '空回车默认私库'
    $created=&$module {$script:created}
    Assert ([IO.Directory]::Exists($created)-and-not[IO.File]::Exists($created+'.zip')) '非空不打包，保留目录'
    &$module {param($p,$d)$script:calls.Clear();foreach($a in @('',' ',$d,'','')){$script:answers.Enqueue($a)};Invoke-JobsFlutterMigration $p export-all-dependencies} $project $destination
    $calls=@(&$module {$script:calls.ToArray()});$created=&$module {$script:created}
    Assert ($calls.Count-eq1 -and $calls[0].EndsWith('|--all')) '空格也明确全提取'
    Assert ([IO.Directory]::Exists($created)-and[IO.File]::Exists($created+'.zip')) '空回车 ZIP 且空回车不删除'
    &$module {param($p,$d)$script:calls.Clear();foreach($a in @('','',$d,'','delete')){$script:answers.Enqueue($a)};Invoke-JobsFlutterMigration $p export-all-dependencies} $project $destination
    $created=&$module {$script:created}
    Assert (-not[IO.Directory]::Exists($created)-and[IO.File]::Exists($created+'.zip')) '明确非空只删除本次已验证产物'
    Assert ([IO.Directory]::Exists($bundle)) '其它目录不受删除影响'
    &$module {param($p,$s)$script:calls.Clear();foreach($a in @('','',$s,'','cancel')){$script:answers.Enqueue($a)};Invoke-JobsFlutterMigration $p import-all-dependencies} $project $raw
    $calls=@(&$module {$script:calls.ToArray()})
    Assert ($calls.Count-eq1 -and $calls[0]-notlike '*--apply*') '目录和最终确认空输入均重问，明确取消零apply'
    &$module {param($p,$s)$script:calls.Clear();foreach($a in @('',$s,'YES')){$script:answers.Enqueue($a)};Invoke-JobsFlutterMigration $p import-all-dependencies} $project $raw
    $calls=@(&$module {$script:calls.ToArray()})
    Assert ($calls.Count-eq2 -and $calls[1].EndsWith('|--apply|--expected-plan|'+('0'*64))) 'YES才执行融合'
    &$module {param($p,$s)$script:calls.Clear();foreach($a in @('',$s,'','','YES')){$script:answers.Enqueue($a)};Invoke-JobsFlutterMigration $p import-all-dependencies} $project $raw
    $calls=@(&$module {$script:calls.ToArray()})
    Assert ($calls.Count-eq2-and$calls[1].EndsWith('|--apply|--expected-plan|'+('0'*64))) '连续空回车只重复确认，同一计划最终YES仅apply一次'
    &$module {param($p,$s)$script:calls.Clear();foreach($a in @('',$s,'','__EOF__')){$script:answers.Enqueue($a)};Invoke-JobsFlutterMigration $p import-all-dependencies} $project $raw
    Assert ((&$module {$script:calls.Count})-eq1) '最终空回车后EOF退出，不循环或apply'
    &$module {param($s)$script:calls.Clear();foreach($a in @('',$s,'','__INTERRUPT__')){$script:answers.Enqueue($a)}} $raw
    Assert-Throws { &$module {param($p)Invoke-JobsFlutterMigration $p import-all-dependencies} $project } '最终空回车后输入取消异常透传退出'
    Assert ((&$module {$script:calls.Count})-eq1) '最终输入中断不apply'
    &$module {param($p,$s)$script:calls.Clear();$crafted='Y'+[char]27+'ES';foreach($a in @('',$s,$crafted)){$script:answers.Enqueue($a)};Invoke-JobsFlutterMigration $p import-all-dependencies} $project $raw
    Assert ((&$module {$script:calls.Count})-eq1) '含隐藏控制字符的YES不能通过精确授权'
    &$module {param($s)$script:calls.Clear();$script:failPreview=$true;foreach($a in @('',$s)){$script:answers.Enqueue($a)}} $raw
    Assert-Throws { &$module {param($p)Invoke-JobsFlutterMigration $p import-all-dependencies} $project } '损坏来源或不可恢复预检失败停止'
    Assert ((&$module {$script:calls.Count})-eq1) '预检失败无apply'
    &$module {param($s)$script:calls.Clear();$script:failPreview=$false;$script:omitPlan=$true;foreach($a in @('',$s)){$script:answers.Enqueue($a)}} $raw
    Assert-Throws { &$module {param($p)Invoke-JobsFlutterMigration $p import-all-dependencies} $project } '缺少计划指纹拒绝进入YES'
    Assert ((&$module {$script:calls.Count})-eq1) '计划指纹缺失无apply'
    &$module { $script:omitPlan=$false; $script:conflictCount=2 }
    &$module {param($s)$script:calls.Clear();foreach($a in @('',$s,'','','','YES')){$script:answers.Enqueue($a)}} $raw
    &$module {param($p)Invoke-JobsFlutterMigration $p import-all-dependencies} $project
    $calls=@(&$module {$script:calls.ToArray()})
    Assert ($calls.Count-eq3 -and $calls[1]-like '*|--conflict-policy|source|--backup-directory|*' -and $calls[1].EndsWith('|'+$destination)) '冲突回车默认推荐导入源且默认备份到桌面'
    Assert ($calls[2].EndsWith('|--apply|--expected-plan|'+('1'*64))) '最终YES绑定策略重算后的计划指纹'
    &$module {param($s)$script:calls.Clear();$dragged='"'+(Join-Path $script:fixture 'future backup 中文')+'"';foreach($a in @('',$s,'1','',$dragged,'YES')){$script:answers.Enqueue($a)}} $raw
    &$module {param($p)Invoke-JobsFlutterMigration $p import-all-dependencies} $project
    $calls=@(&$module {$script:calls.ToArray()})
    Assert ($calls.Count-eq3 -and $calls[1].EndsWith('|'+(Join-Path $temp 'future backup 中文'))) '可拖入带引号中文空格备份路径，不在交互阶段创建目录'
    Assert (-not [IO.Directory]::Exists((Join-Path $temp 'future backup 中文'))) '只读计划与交互不创建备份目录'
    &$module {param($s)$script:calls.Clear();foreach($a in @('',$s,'1',' ','YES')){$script:answers.Enqueue($a)}} $raw
    &$module {param($p)Invoke-JobsFlutterMigration $p import-all-dependencies} $project
    $calls=@(&$module {$script:calls.ToArray()})
    Assert ($calls.Count-eq3 -and $calls[1].EndsWith('|--conflict-policy|source|--no-backup')) '输入空格也明确选择覆盖不备份'
    &$module {param($s)$script:calls.Clear();foreach($a in @('',$s,'2','YES')){$script:answers.Enqueue($a)}} $raw
    &$module {param($p)Invoke-JobsFlutterMigration $p import-all-dependencies} $project
    $calls=@(&$module {$script:calls.ToArray()})
    Assert ($calls.Count-eq3 -and $calls[1].EndsWith('|--conflict-policy|existing') -and ($calls-join '|')-notmatch 'backup') '保留本机跳过冲突，不询问备份'
    foreach ($cancelAnswers in @(@('q'), @([string][char]27), @('__EOF__'), @('1','__EOF__'), @('1','','__EOF__'))) {
        &$module {param($s,$values)$script:calls.Clear();foreach($a in (@('',$s)+$values)){$script:answers.Enqueue($a)}} $raw $cancelAnswers
        &$module {param($p)Invoke-JobsFlutterMigration $p import-all-dependencies} $project
        Assert ((&$module {$script:calls.Count})-eq1) '冲突选择、备份确认或路径输入取消只完成只读计划'
    }
    &$module {param($s)$script:calls.Clear();foreach($a in @('',$s,'1','skip','','cancel')){$script:answers.Enqueue($a)}} $raw
    &$module {param($p)Invoke-JobsFlutterMigration $p import-all-dependencies} $project
    Assert ((&$module {$script:calls.Count})-eq2) '策略已选后最终空回车仍等待，明确非YES取消不apply'
    $savedFzf = @{}
    foreach ($name in @('FZF_DEFAULT_OPTS','FZF_DEFAULT_OPTS_FILE')) { $savedFzf[$name]=@{Present=(Test-Path ('Env:'+$name));Value=[Environment]::GetEnvironmentVariable($name,'Process')} }
    try {
        $env:FZF_DEFAULT_OPTS='--multi --filter=stale'
        $env:FZF_DEFAULT_OPTS_FILE='fixture-options'
        &$module {
            $script:fzfCode=0;$script:fzfChoice='first';$script:fzfHealthy=$true
            function script:Find-JobsExecutable { return 'Invoke-MigrationFixtureFzf' }
            function script:Invoke-JobsProcess { return [pscustomobject]@{ExitCode=$(if($script:fzfHealthy){0}else{1});StdOut='fzf fixture';StdErr=''} }
            function script:Invoke-MigrationFixtureFzf {
                $script:fzfItems=@($input);$script:fzfArguments=@($args)
                $script:fzfIsolated=([string]::IsNullOrEmpty($env:FZF_DEFAULT_OPTS)-and[string]::IsNullOrEmpty($env:FZF_DEFAULT_OPTS_FILE))
                $global:LASTEXITCODE=$script:fzfCode
                if($script:fzfChoice-ceq'first'){return $script:fzfItems[0]}
                if($script:fzfChoice-ceq'second'){return $script:fzfItems[1]}
                return 'unknown choice'
            }
        }
        Assert ((&$module {Select-JobsMigrationConflictPolicy})-ceq'source') 'fzf首项默认推荐导入源'
        Assert ((&$module {$script:fzfItems.Count-eq2-and$script:fzfItems[0]-like'*推荐*'-and'--no-multi'-in$script:fzfArguments-and$script:fzfIsolated})) 'fzf仅二选一，隔离用户默认过滤与多选选项'
        Assert ($env:FZF_DEFAULT_OPTS-ceq'--multi --filter=stale'-and$env:FZF_DEFAULT_OPTS_FILE-ceq'fixture-options') '选择后恢复原fzf配置环境'
        &$module {$script:fzfChoice='second'}
        Assert ((&$module {Select-JobsMigrationConflictPolicy})-ceq'existing') 'fzf可明确保留本机'
        foreach($code in @(1,130)) {
            &$module {param($c)$script:fzfCode=$c} $code
            Assert ($null-eq(&$module {Select-JobsMigrationConflictPolicy})) 'fzf空选或Esc不默认覆盖'
        }
        &$module {param($s)$script:calls.Clear();foreach($a in @('',$s)){$script:answers.Enqueue($a)}} $raw
        &$module {param($p)Invoke-JobsFlutterMigration $p import-all-dependencies} $project
        Assert ((&$module {$script:calls.Count})-eq1) '实际导入流程fzf取消后无策略计划或apply'
        &$module {$script:fzfCode=37}
        Assert-Throws { &$module {Select-JobsMigrationConflictPolicy} } 'fzf执行错误不能按推荐项覆盖'
        &$module {$script:fzfCode=0;$script:fzfChoice='unknown'}
        Assert-Throws { &$module {Select-JobsMigrationConflictPolicy} } 'fzf未知响应拒绝'
        &$module {$script:fzfHealthy=$false;$script:answers.Enqueue('2')}
        Assert ((&$module {Select-JobsMigrationConflictPolicy})-ceq'existing') '损坏fzf回退编号选择'
    } finally {
        foreach($name in $savedFzf.Keys){if($savedFzf[$name].Present){[Environment]::SetEnvironmentVariable($name,$savedFzf[$name].Value,'Process')}else{Remove-Item ('Env:'+$name) -ErrorAction SilentlyContinue}}
        &$module { function script:Find-JobsExecutable { return $null } }
    }
    [IO.File]::WriteAllText((Join-Path $project 'pubspec.yaml'), "name: fixture`ndependencies:`n  flutter:`n    sdk: flutter`n")
    $router = Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/Action.psm1') -PassThru -DisableNameChecking
    &$router {
        param($Migration)
        $script:fixtureMigration=$Migration
        function script:Import-Module {
            param($Name,[switch]$PassThru,[switch]$DisableNameChecking)
            $normalized = ([string]$Name).Replace('\','/')
            if($normalized-notlike'*FlutterDependencyMigration.psm1/FlutterDependencyMigration.psm1'){throw '实际菜单未分发到迁移模块'}
            return $script:fixtureMigration
        }
    } $module
    &$module {param($s)$script:calls.Clear();foreach($a in @('',$s,'2','YES')){$script:answers.Enqueue($a)}} $raw
    &$router {param($p)Invoke-JobsFeature -Target $p -Action import-all-dependencies} $project
    $calls=@(&$module {$script:calls.ToArray()})
    Assert ($calls.Count-eq3-and$calls[2]-like'*|--conflict-policy|existing|--apply|--expected-plan|*') '实际菜单import-all-dependencies分发沿用冲突选择与计划绑定'
    Remove-Module $router -ErrorAction SilentlyContinue
    &$module { $script:conflictCount=0 }
    &$module {$script:answers.Clear();$script:answers.Enqueue('cancel');$script:calls.Clear()}
    &$module {param($p)Invoke-JobsFlutterMigration $p export-all-dependencies} $project
    Assert ((&$module {$script:calls.Count})-eq0) '首屏取消无引擎调用'
    $extract = Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/Actions/extract/Scripts/Action.psm1') -PassThru -DisableNameChecking
    [void][IO.Directory]::CreateDirectory((Join-Path $project '.dart_tool'))
    [IO.File]::WriteAllText((Join-Path $project 'pubspec.yaml'), "name: fixture`ndependencies:`n  flutter:`n    sdk: flutter`n")
    [IO.File]::WriteAllText((Join-Path $project 'pubspec.lock'),'fixture-lock')
    [IO.File]::WriteAllText((Join-Path $project '.dart_tool/package_config.json'),'{}')
    &$extract {
        param($t)
        $script:scopeFixture=$t
        $script:scope=''
        $script:scopeArguments=@()
        function script:Show-JobsExtractorIntro {$true}
        function script:Get-JobsInstallRoot {$script:scopeFixture}
        function script:Get-JobsExtractorDesktop {$script:scopeFixture}
        function script:Find-JobsExtractorDart {param($p)'fixture.exe'}
        function script:Read-Host {param($Prompt) if($Prompt -like '*只提取私库*') {return $script:scope}; return ''}
        function script:Invoke-JobsProcess {
            param($FilePath,$Arguments,$WorkingDirectory,$TimeoutSeconds)
            $script:scopeArguments=@($Arguments)
            [pscustomobject]@{StdOut='fixture complete';StdErr='';ExitCode=0}
        }
    } $temp
    &$extract {param($p)Invoke-JobsFlutterDependencyAction $p} $project
    Assert ((&$extract {'--private-only' -in $script:scopeArguments})) '普通 Pub 提取空回车默认私库'
    &$extract {$script:scope=' '}
    &$extract {param($p)Invoke-JobsFlutterDependencyAction $p} $project
    Assert ((&$extract {'--private-only' -notin $script:scopeArguments})) '普通 Pub 提取空格显式全提取'
    Remove-Module $extract -ErrorAction SilentlyContinue
    $native=Join-Path $temp 'native-dart.exe'
    $header=New-Object byte[] 128
    $header[0]=0x4D;$header[1]=0x5A;$header[0x3C]=0x40;$header[0x40]=0x50;$header[0x41]=0x45;$header[0x44]=0x64;$header[0x45]=0x86
    [IO.File]::WriteAllBytes($native,$header)
    &$module {
        param($exe,$t)
        $script:fixtureNative=$exe
        $script:fixture=$t
        $script:probeCalls=New-Object 'Collections.Generic.List[string]'
        function script:Get-Command {
            param($Name,$CommandType,[switch]$All,$ErrorAction)
            @([pscustomobject]@{Source=(Join-Path $script:fixture 'flutter/bin/dart.bat')},[pscustomobject]@{Source=$script:fixtureNative},[pscustomobject]@{Source='ignored.sh'})
        }
    } $native $temp
    $candidates=@(&$module {Get-JobsMigrationSystemDartCandidates})
    $shimNative = Join-Path $temp 'flutter/bin/cache/dart-sdk/bin/dart.exe'
    Assert ($candidates.Count-eq2 -and $candidates[0]-ceq$shimNative-and$candidates[1]-ceq$native) ('系统Dart候选只取原生exe或Flutter shim旁原生文件，不执行bat；actual='+($candidates-join' | '))
    &$module {
        function script:Get-JobsMigrationSystemDartCandidates {$script:fixtureNative}
        function script:Invoke-JobsProcess {
            param($FilePath,$Arguments,$WorkingDirectory,$TimeoutSeconds)
            $script:probeCalls.Add($FilePath+'|'+($Arguments-join '|'))
            [pscustomobject]@{StdOut='Dart SDK version: 3.9.0';StdErr='';ExitCode=0}
        }
    }
    $selected=&$module {param($p)&$script:realMigrationDart $p} $project
    Assert ($selected-ceq$native) '缺少FVM时通过真实PE头校验后复用已有系统Dart'
    Assert ((&$module {$script:probeCalls.Count-eq1-and$script:probeCalls[0].EndsWith('|--version')})) '只体检原生Dart，不运行shim或安装命令'
    $savedPromptEnvironment=@{}
    foreach($name in @('NO_COLOR','TERM')){$savedPromptEnvironment[$name]=@{Present=(Test-Path ('Env:'+$name));Value=[Environment]::GetEnvironmentVariable($name,'Process')}}
    try {
        $env:NO_COLOR='1';$env:TERM='xterm-256color'
        Assert (-not (&$module {Test-JobsMigrationPromptColor})) 'NO_COLOR时备份选项纯文本'
        Remove-Item Env:NO_COLOR -ErrorAction SilentlyContinue
        $env:TERM='dumb'
        Assert (-not (&$module {Test-JobsMigrationPromptColor})) 'TERM=dumb时备份选项纯文本'
        $env:TERM='xterm-256color'
        if([Console]::IsInputRedirected-or[Console]::IsOutputRedirected){Assert (-not (&$module {Test-JobsMigrationPromptColor})) '非交互或重定向输出时备份选项纯文本'}
        &$module {
            param($Log)
            $script:promptParts=New-Object 'Collections.Generic.List[object]'
            $script:promptAnswer='';$script:promptColor=$true;$script:MigrationLog=$Log
            function script:Test-JobsMigrationPromptColor {return $script:promptColor}
            function script:Test-JobsEnterChoiceColor {return $script:promptColor}
            function script:Test-JobsEnterChoiceBold {return $false}
            function script:Write-Host {param($Text,[string]$ForegroundColor,[switch]$NoNewline)$script:promptParts.Add([pscustomobject]@{Text=[string]$Text;Color=$ForegroundColor;NoNewline=[bool]$NoNewline})}
            function script:Read-JobsMigrationLine {param($Prompt)$script:readPrompt=$Prompt;return $script:promptAnswer}
        } (Join-Path $temp 'prompt-status.log')
        $answer=&$module {Read-JobsMigrationBackupChoice}
        $parts=@(&$module {$script:promptParts.ToArray()})
        Assert ($parts[0].Text-ceq'是否备份将被覆盖的当前文件？'-and[string]::IsNullOrEmpty($parts[0].Color)) '备份问句使用默认文字色'
        Assert ($parts[1].Text-ceq'回车 = 备份'-and$parts[1].Color-ceq'Green'-and$parts[3].Text-ceq'任意字符再回车 = 不备份直接覆盖：'-and$parts[3].Color-ceq'Red') '备份选项绿色，不备份直接覆盖选项红色'
        Assert ($null-ne$answer-and$answer.Length-eq0-and(&$module {$script:readPrompt.Length})-eq0) '片段显示后单独读取，空回车原样返回用于默认备份'
        &$module {$script:promptAnswer=' '}
        Assert ((&$module {Read-JobsMigrationBackupChoice})-ceq' ') '空格原样返回用于不备份'
        &$module {$script:promptAnswer=$null}
        Assert ($null-eq(&$module {Read-JobsMigrationBackupChoice})) '输入结束原样返回，不误当空回车'
        &$module {$script:promptColor=$false;$script:promptParts.Clear();$script:promptAnswer=''}
        [void](&$module {Read-JobsMigrationBackupChoice})
        $parts=@(&$module {$script:promptParts.ToArray()})
        Assert (@($parts|Where-Object {-not[string]::IsNullOrEmpty($_.Color)-or$_.Text.Contains([string][char]27)}).Count-eq0) '纯文本分支不传颜色也不拼ANSI'
        Assert (-not[IO.File]::Exists((Join-Path $temp 'prompt-status.log'))) '彩色提示不混入状态日志'
        &$module {Write-JobsMigrationMessage '状态日志示例'}
        Assert (-not[IO.File]::ReadAllText((Join-Path $temp 'prompt-status.log')).Contains([string][char]27)) '状态日志不带ANSI'
    } finally {
        foreach($name in $savedPromptEnvironment.Keys){if($savedPromptEnvironment[$name].Present){[Environment]::SetEnvironmentVariable($name,$savedPromptEnvironment[$name].Value,'Process')}else{Remove-Item ('Env:'+$name) -ErrorAction SilentlyContinue}}
    }
    Write-Host ('PASS: FlutterDependencyMigration.Tests.ps1 ('+$count+' assertions; no user cache writes)')
} finally { Remove-Module $module -ErrorAction SilentlyContinue; Remove-Item -LiteralPath $temp -Recurse -Force }

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

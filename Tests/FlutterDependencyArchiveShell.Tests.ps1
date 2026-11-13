# FlutterDependencyArchiveShell.Tests.ps1 | 原生归档 wrapper 的根目录、预检与确认边界。
# Created by Jobs on 2026年10月29日，星期四.
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
        @('precache','windows',(Join-Path $temp 'flutter/bin/cache'),''),
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
            if($Prompt -like '*完整提取本层*'){return 'all'}
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

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

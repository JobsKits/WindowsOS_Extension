# FlutterDependencyArchiveEndToEnd.Tests.ps1 | 完整独立发布与真实Dart归档数据链。
# Created by Jobs on 2026年10月29日，星期四.
# 假工具版本/选择、真实文件复制与SHA校验；不联网、不安装SDK、不注册菜单。
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
function Assert-Throws([scriptblock]$Body,[string]$Message){$failed=$false;try{&$Body|Out-Null}catch{$failed=$true};Assert $failed $Message}
$dart=if($env:JOBS_TEST_DART){$env:JOBS_TEST_DART}else{(Get-Command dart -ErrorAction SilentlyContinue).Source}
if(-not$dart){throw '此数据链回归需要现有Dart，可通过JOBS_TEST_DART指定；不会自动安装。'}
$base=if([Environment]::OSVersion.Platform-eq[PlatformID]::Win32NT){[IO.Path]::GetTempPath()}else{'/private/tmp'}
$temp=Join-Path $base ('jobs-archive-published-chain-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$installer=Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
$package=Join-Path $temp '发布包 中文 & spaces'
&$installer {param($p,$d)New-JobsPackageRelease -PackagePath $p -Destination $d} (Join-Path $root 'JobsFlutterTools') $package|Out-Null
$module=Import-Module (Join-Path $package 'Scripts/ProjectSetup.psm1') -PassThru -DisableNameChecking
$project=Join-Path $temp '项目 with spaces'
$target=Join-Path $project 'build/windows'
$output=Join-Path $temp 'exported'
foreach($directory in @($target,$output,(Join-Path $project 'lib'))){[void][IO.Directory]::CreateDirectory($directory)}
[IO.File]::WriteAllText((Join-Path $project 'pubspec.yaml'),"name: fixture`ndependencies:`n  flutter:`n    sdk: flutter`n")
[IO.File]::WriteAllText((Join-Path $project 'pubspec.lock'),"packages: {}`n")
$artifact=Join-Path $target 'native fixture.bin'
[IO.File]::WriteAllBytes($artifact,[byte[]](0..255))
$expected=(Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash
try{
 &$module {
  param($base,$p,$cache,$output,$runtime)
  $script:fixtureRoot=$base;$script:fixtureProject=$p;$script:fixtureCache=$cache;$script:fixtureOutput=$output;$script:fixtureDart=$runtime
  $script:fixtureOperation='export';$script:fixtureSnapshot='';$script:fixtureAnswer='';$script:engineCalls=0
  $script:RealArchiveProcess=${function:Invoke-JobsSetupProcess}
  function script:Get-JobsInstallRoot{$script:fixtureRoot}
  function script:Test-JobsSetupInteractive{$true}
  function script:Read-Host{param($Prompt)if($Prompt -like '*完整提取本层*'){return 'all'};if($Prompt.StartsWith('输入精确')){return $script:fixtureAnswer};return ''}
  function script:Get-JobsSetupFzf{param($p)'fixture-fzf'}
  function script:Get-JobsArchiveDart{param($p)$script:fixtureDart}
  function script:Read-JobsArchiveDirectory{param($Prompt,$Default,$MayBeMissing)if($script:fixtureOperation-ceq'import'){return $script:fixtureSnapshot};return $script:fixtureOutput}
  function script:Get-JobsArchiveCachePlan{param($Project,$Kind,$Fzf,$Manifest,[switch]$Import)[pscustomobject]@{Root=$script:fixtureCache;Platform=$(if($Kind-ceq'precache'){'web'}else{'windows'});ToolVersion='Flutter 3.29.3 arch windows_x64'}}
  function script:Invoke-JobsSetupProcess{
   param($File,[string[]]$Arguments,$Directory,$TimeoutSeconds)
   $script:engineCalls++
   $result=&$script:RealArchiveProcess $File $Arguments $Directory $TimeoutSeconds
   if($Arguments[1]-ceq'export'-and'--check'-cnotin$Arguments){if($result.StdOut-match'(?m)^ARCHIVE_DIRECTORY=([^\r\n]+)'){$script:fixtureSnapshot=$Matches[1]}}
   return $result
  }
 } $temp $project $target $output $dart
 &$module {param($p)Invoke-JobsProjectDependencyArchiveAction $p export-native-dependencies} $project
 $snapshot=&$module{$script:fixtureSnapshot}
 Assert ([IO.File]::Exists((Join-Path $snapshot 'manifest.json'))) '已发布wrapper+真实引擎产生快照'
 Assert ((Get-FileHash -LiteralPath (Join-Path $snapshot 'payload/native fixture.bin') -Algorithm SHA256).Hash-ceq$expected) '导出payload逐字节一致'
 $manifest=Get-Content -LiteralPath (Join-Path $snapshot 'manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
 Assert ($manifest.kind-ceq'native'-and$manifest.platform-ceq'windows'-and$manifest.toolVersion-ceq'Flutter 3.29.3 arch windows_x64') '跨层元数据来自明确本次计划'
 Assert ((&$module{$script:engineCalls})-eq2) '导出预检+实际执行两次独立引擎调用'
 [IO.File]::Delete($artifact)
 &$module{$script:fixtureOperation='import';$script:fixtureAnswer='';$script:engineCalls=0}
 Assert-Throws{&$module{param($p)Invoke-JobsProjectDependencyArchiveAction $p import-native-dependencies}$project} '真实导入预检后取消传播'
 Assert (-not[IO.File]::Exists($artifact)) '未YES前没有恢复文件'
 Assert ((&$module{$script:engineCalls})-eq1) '取消仅执行只读引擎预检'
 &$module{$script:fixtureAnswer='YES';$script:engineCalls=0}
 &$module{param($p)Invoke-JobsProjectDependencyArchiveAction $p import-native-dependencies}$project
 Assert ((Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash-ceq$expected) '大写YES后真实恢复原字节'
 Assert ((&$module{$script:engineCalls})-eq2) '导入确认前后均全量校验'
 [IO.File]::WriteAllText($artifact,'local different file')
 &$module{$script:engineCalls=0}
 Assert-Throws{&$module{param($p)Invoke-JobsProjectDependencyArchiveAction $p import-native-dependencies}$project} '真实同名不同内容拒绝'
 Assert ([IO.File]::ReadAllText($artifact)-ceq'local different file') '冲突不会覆盖本地文件'
 Assert ((&$module{$script:engineCalls})-eq1) '冲突预检失败不进入写入'
 $shell=(Get-Process -Id $PID).Path
 foreach($action in @('android-dependencies','export-native-dependencies','import-gradle-dependencies')){
  $text=@(&$shell -NoLogo -NoProfile -File (Join-Path $package 'Scripts/Invoke.ps1') -Target $project -Action $action -Check 2>&1)-join"`n"
  Assert ($LASTEXITCODE-eq0-and$text-match'只读') ('完整发布CLI只读参数能抵达对应业务：'+$action)
 }
 Assert ([IO.File]::ReadAllText($artifact)-ceq'local different file') '所有CLI Check均未修改工程数据'
 # 平台资源v2必须由已发布Windows wrapper携带白名单标志，并真实恢复Web SDK及配对stamp。
 $cache=Join-Path $temp 'flutter sdk/bin/cache'
 $webFile=Join-Path $cache 'flutter_web_sdk/kernel/dart_sdk.js'
 [void][IO.Directory]::CreateDirectory((Split-Path -Parent $webFile))
 [IO.File]::WriteAllText($webFile,'web sdk bytes')
 [IO.File]::WriteAllText((Join-Path $cache 'flutter_web_sdk.stamp'),'engine revision')
 [IO.File]::WriteAllText((Join-Path $cache 'macos-sdk.stamp'),'missing platform payload')
 [void][IO.Directory]::CreateDirectory((Join-Path $cache 'dart-sdk/bin'))
 [IO.File]::WriteAllText((Join-Path $cache 'dart-sdk/bin/dart'),'excluded runtime')
 [IO.File]::WriteAllText((Join-Path $cache 'engine-dart-sdk.stamp'),'excluded runtime readiness')
 &$module{param($c)$script:fixtureCache=$c;$script:fixtureOperation='export';$script:fixtureAnswer='';$script:engineCalls=0} $cache
 &$module{param($p)Invoke-JobsProjectDependencyArchiveAction $p export-precache-dependencies} $project
 $webSnapshot=&$module{$script:fixtureSnapshot}
 $webManifest=Get-Content -LiteralPath (Join-Path $webSnapshot 'manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
 Assert ($webManifest.formatVersion-eq2-and$webManifest.kind-ceq'precache') '已发布wrapper导出v2平台白名单布局'
 $webNames=@($webManifest.files|ForEach-Object path)
 Assert ($webNames.Count-eq2-and'flutter_web_sdk.stamp'-cin$webNames-and'flutter_web_sdk/kernel/dart_sdk.js'-cin$webNames) '只归档Web SDK及配对stamp，不伪造其它平台/Dart就绪'
 $restoredCache=Join-Path $temp 'restored sdk/bin/cache'
 &$module{param($c)$script:fixtureCache=$c;$script:fixtureOperation='import';$script:fixtureAnswer='YES';$script:engineCalls=0} $restoredCache
 &$module{param($p)Invoke-JobsProjectDependencyArchiveAction $p import-precache-dependencies} $project
 Assert ([IO.File]::ReadAllText((Join-Path $restoredCache 'flutter_web_sdk/kernel/dart_sdk.js'))-ceq'web sdk bytes') 'Windows wrapper真实恢复Web SDK载荷'
 Assert ([IO.File]::ReadAllText((Join-Path $restoredCache 'flutter_web_sdk.stamp'))-ceq'engine revision') 'Windows wrapper真实恢复原配对stamp'
 Assert (-not[IO.File]::Exists((Join-Path $restoredCache 'macos-sdk.stamp'))-and-not[IO.Directory]::Exists((Join-Path $restoredCache 'dart-sdk'))-and-not[IO.File]::Exists((Join-Path $restoredCache 'engine-dart-sdk.stamp'))) '未恢复无载荷平台stamp或SDK运行态'
 Assert ((&$module{$script:engineCalls})-eq2) 'v2导入确认前后均重新完整核验'
 Write-Host ('PASS: FlutterDependencyArchiveEndToEnd.Tests.ps1 ('+$count+' assertions; published Windows wrapper and real Dart on '+[Environment]::OSVersion.Platform+'; not Windows native UI)')
}finally{
 Remove-Module $module -ErrorAction SilentlyContinue
 Remove-Item -LiteralPath $temp -Recurse -Force
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

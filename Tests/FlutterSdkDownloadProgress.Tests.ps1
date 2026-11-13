# FlutterSdkDownloadProgress.Tests.ps1 | SDK 实时进度隔离回归。
# Created by Jobs on 2026年11月4日，星期三.
# 使用假工具与回环 HTTP，不下载真实 SDK、不接触账户缓存或系统菜单。
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
$helper = Join-Path $root 'JobsFlutterTools/Scripts/SdkDownloadOutput.ps1'
. $helper
$engine = Join-Path $PSHOME $(if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { if ($PSVersionTable.PSVersion.Major -le 5) { 'powershell.exe' } else { 'pwsh.exe' } } else { 'pwsh' })
function New-ProgressStart([string]$Script, [string]$Mode) {
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $engine
    $start.Arguments = '-NoLogo -NoProfile -File "' + $Script + '" ' + $Mode
    $start.WorkingDirectory = Split-Path -Parent $Script
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        $native = Join-Path $start.WorkingDirectory 'fake.sh'
        $body = @'
echo $$ > pid
case "$1" in
  hang) exec /bin/sleep 60;;
  fail) printf 'failed-with-37' >&2; exit 37;;
  secret) printf 'https://user:password@example.invalid/pkg?token=query-secret\rauthorization: Bearer header-secret\naccess_token=body-secret' >&2; exit 0;;
  utf8) printf '\360\237\230'; /bin/sleep 0.2; printf '\200'; i=0; while [ "$i" -lt 4095 ]; do printf A; i=$((i+1)); done; exit 0;;
esac
printf '\r下载 25%%' >&2
while [ ! -f release ]; do /bin/sleep 0.05; done
printf yes > finished
printf '\r下载 100%%' >&2
printf '{"frameworkVersion":"3.47.2"}'
'@
        [IO.File]::WriteAllText($native, $body.Replace("`r`n", "`n"), (New-Object Text.UTF8Encoding($false)))
        $start.FileName = '/bin/sh'
        $start.Arguments = '"' + $native + '" ' + $Mode
    }
    return $start
}
$script:assertions = 0
function Assert-Progress([bool]$Condition, [string]$Message) {
    $script:assertions++
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
}
$Temporary = Join-Path ([IO.Path]::GetTempPath()) ('JobsSdkProgress-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($Temporary)
try {
    $fake = Join-Path $Temporary 'fake.ps1'
    $fakeBody = @'
param([string]$Mode)
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'pid'), [string]$PID)
if ($Mode -eq 'hang') { Start-Sleep -Seconds 60; exit 0 }
if ($Mode -eq 'fail') { [Console]::Error.Write('failed-with-37'); exit 37 }
if ($Mode -eq 'secret') { [Console]::Error.Write("https://user:password@example.invalid/pkg?token=query-secret`rauthorization: Bearer header-secret`naccess_token=body-secret"); exit 0 }
if ($Mode -eq 'utf8') {
    $stream = [Console]::OpenStandardOutput()
    $first = [byte[]]@(240,159,152)
    $stream.Write($first,0,$first.Length); $stream.Flush()
    Start-Sleep -Milliseconds 200
    $second = New-Object byte[] 4096
    $second[0] = 128
    for ($i=1;$i -lt $second.Length;$i++) { $second[$i] = 65 }
    $stream.Write($second,0,$second.Length); $stream.Flush()
    exit 0
}
[Console]::Error.Write("`r下载 25%")
for ($i=0; $i -lt 600 -and -not [IO.File]::Exists((Join-Path $PSScriptRoot 'release')); $i++) { Start-Sleep -Milliseconds 100 }
if (-not [IO.File]::Exists((Join-Path $PSScriptRoot 'release'))) { exit 9 }
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'finished'), 'yes')
[Console]::Error.Write("`r下载 100%")
[Console]::Write('{"frameworkVersion":"3.47.2"}')
'@
    [IO.File]::WriteAllText($fake, $fakeBody, (New-Object Text.UTF8Encoding($true)))
    Add-Type -TypeDefinition @'
using System;
using System.IO;
public sealed class JobsSdkProgressWriter : StringWriter {
    readonly string directory;
    public bool ObservedBeforeFinish { get; private set; }
    public JobsSdkProgressWriter(string path) { directory = path; }
    public override void Write(string value) {
        base.Write(value);
        if (ToString().Contains("下载 25%") && !File.Exists(Path.Combine(directory, "finished"))) {
            ObservedBeforeFinish = true;
            File.WriteAllText(Path.Combine(directory, "release"), "yes");
        }
    }
}
'@
    $originalOut = [Console]::Out
    $originalError = [Console]::Error
    $progressDisplay = New-Object JobsSdkProgressWriter($Temporary)
    $jsonDisplay = New-Object IO.StringWriter
    try {
        [Console]::SetError($progressDisplay)
        [Console]::SetOut($jsonDisplay)
        $result = Invoke-JobsSdkLiveProcess (New-ProgressStart $fake 'progress') 90
    } finally { [Console]::SetError($originalError); [Console]::SetOut($originalOut) }
    Assert-Progress ($progressDisplay.ToString().Contains("`r下载 25%")) 'CR 与无换行进度实时显示'
    Assert-Progress $progressDisplay.ObservedBeforeFinish '工具未结束、未换行时已经看到下载进度'
    Assert-Progress ($result.ExitCode -eq 0) '实时泵运行成功'
    Assert-Progress ($jsonDisplay.ToString() -ceq '{"frameworkVersion":"3.47.2"}') '显示JSON不混入额外文字'
    Assert-Progress ($result.StdOut -ceq '{"frameworkVersion":"3.47.2"}') '机器 JSON 返回值不混入展示文字'
    Assert-Progress ($result.StdErr -ceq "`r下载 25%`r下载 100%") '原生 CR 与两档进度完整捕获'
    $failed = Invoke-JobsSdkLiveProcess (New-ProgressStart $fake 'fail') 45
    Assert-Progress ($failed.ExitCode -eq 37 -and $failed.StdErr -ceq 'failed-with-37') '非零退出码及错误输出保留'
    $originalOut = [Console]::Out
    $unicodeDisplay = New-Object IO.StringWriter
    try { [Console]::SetOut($unicodeDisplay); $unicode = Invoke-JobsSdkLiveProcess (New-ProgressStart $fake 'utf8') 45 } finally { [Console]::SetOut($originalOut) }
    Assert-Progress ($unicode.StdOut -ceq ([char]::ConvertFromUtf32(128512) + ('A' * 4095))) '四字节 UTF8 跨块后接完整4096字节不丢失/溢出'
    $originalError = [Console]::Error
    $secretDisplay = New-Object IO.StringWriter
    try { [Console]::SetError($secretDisplay); $secret = Invoke-JobsSdkLiveProcess (New-ProgressStart $fake 'secret') 45 -Sanitize } finally { [Console]::SetError($originalError) }
    Assert-Progress ($secretDisplay.ToString() -notmatch 'password|query-secret|header-secret|body-secret') 'PubGet展示保留URL/认证字段脱敏'
    Assert-Progress ($secret.StdErr.Contains('header-secret')) '脱敏展示不改内部原始响应'
    Remove-Item -LiteralPath (Join-Path $Temporary 'pid')
    $blocked = $false
    try { [void](Invoke-JobsSdkLiveProcess (New-ProgressStart $fake 'hang') 10) } catch { $blocked = $_.Exception.Message.Contains('超时') }
    Assert-Progress $blocked '下载超时明确失败'
    $toolId = [int][IO.File]::ReadAllText((Join-Path $Temporary 'pid'))
    $gone = $false
    for ($i=0;$i -lt 40;$i++) {
        try { $process = [Diagnostics.Process]::GetProcessById($toolId); $gone = $process.HasExited; $process.Dispose() } catch { $gone = $true }
        if ($gone) { break }; Start-Sleep -Milliseconds 25
    }
    Assert-Progress $gone '超时停止本次工具，不留下假下载进程'

    # 回环响应分两段，确保未知宿主进度条偏好不会把下载静默化。
    Add-Type -TypeDefinition @'
using System;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
public sealed class JobsSdkLocalServer : IDisposable {
    readonly TcpListener listener = new TcpListener(IPAddress.Loopback, 0);
    public int Port { get { return ((IPEndPoint)listener.LocalEndpoint).Port; } }
    public JobsSdkLocalServer() {
        listener.Start();
        Thread thread = new Thread(delegate() {
            using (TcpClient client = listener.AcceptTcpClient()) using (NetworkStream stream = client.GetStream()) {
                byte[] request = new byte[4096]; stream.Read(request, 0, request.Length);
                byte[] header = Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nContent-Length: 65536\r\nConnection: close\r\n\r\n");
                stream.Write(header, 0, header.Length);
                byte[] body = new byte[65536]; for(int i=0;i<body.Length;i++) body[i] = 90;
                stream.Write(body, 0, 32768); stream.Flush(); Thread.Sleep(1100);
                stream.Write(body, 32768, 32768); stream.Flush();
            }
        }); thread.IsBackground = true; thread.Start();
    }
    public void Dispose() { listener.Stop(); }
}
'@
    $server = New-Object JobsSdkLocalServer
    $ProgressPreference = 'SilentlyContinue'
    try {
        $download = Join-Path $Temporary 'download.bin'
        $display = @(Receive-JobsSdkWebFile ('http://127.0.0.1:' + $server.Port + '/fixture') $download 10 6>&1 | ForEach-Object { [string]$_ }) -join "`n"
        $intermediate = @([regex]::Matches($display, '下载进度：([0-9]+)/65536') | Where-Object { [long]$_.Groups[1].Value -gt 0 -and [long]$_.Groups[1].Value -lt 65536 })
        Assert-Progress ($intermediate.Count -gt 0 -and $display.Contains('下载完成：65536')) '无curl路径显示实际中间字节与完成总量'
        Assert-Progress ([IO.File]::ReadAllText($download, [Text.Encoding]::ASCII) -ceq ('Z' * 65536) -and (Get-Item -LiteralPath $download).Length -eq 65536) '回环下载字节保持完整'
    } finally { $server.Dispose() }

    $copies = @('JobsFlutterSdkInspector/Scripts','JobsFlutterTools/Scripts/Actions/sdk-version/Scripts','JobsFlutterVersionMgr/Scripts','JobsFlutterRunner/Scripts','JobsFlutterPubGet/Scripts','JobsFlutterPackager/Scripts','JobsFlutterTools/Scripts/Actions/sdk-manage/Scripts','JobsFlutterTools/Scripts/Actions/run/Scripts','JobsFlutterTools/Scripts/Actions/pub-get/Scripts','JobsFlutterTools/Scripts/Actions/package/Scripts')
    $hash = (Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash
    foreach ($copy in $copies) { Assert-Progress ((Get-FileHash -LiteralPath (Join-Path $root ($copy + '/SdkDownloadOutput.ps1')) -Algorithm SHA256).Hash -ceq $hash) ('独立副本一致：' + $copy) }
    Write-Host ('PASS: FlutterSdkDownloadProgress.Tests.ps1 (' + $script:assertions + ' assertions)')
} finally {
    if ([IO.Directory]::Exists($Temporary)) { Remove-Item -LiteralPath $Temporary -Recurse -Force }
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

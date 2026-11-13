# SdkDownloadOutput.ps1 | SDK 初始化与下载的实时输出捕获。
# Created by Jobs on 2026年11月4日，星期三.
# 随独立业务包分发；展示原生命令输出，同时保留机器响应供原解析器使用。
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
function Invoke-JobsSdkLiveProcess {
    param([Diagnostics.ProcessStartInfo]$Start, [int]$TimeoutSeconds = 120, [switch]$Sanitize, [switch]$Acquisition)
    $route = $null
    if ($Acquisition) { Import-JobsSdkDownloadRoute; $route = Initialize-JobsSdkProcessNetworkRoute $Start }
    if (-not ('Jobs.SdkDownloadProcess' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
namespace Jobs {
    public sealed class SdkDownloadProcess : IDisposable {
        readonly Process process = new Process();
        readonly object gate = new object();
        readonly StringBuilder stdout = new StringBuilder(), stderr = new StringBuilder();
        readonly ManualResetEvent outDone = new ManualResetEvent(false), errDone = new ManualResetEvent(false);
        readonly bool sanitize;
        readonly string logFile;
        long lastOutput = DateTime.UtcNow.Ticks;
        public string OutputFailure { get; private set; }
        public SdkDownloadProcess(ProcessStartInfo start, bool safeOutput) : this(start, safeOutput, null) {}
        public SdkDownloadProcess(ProcessStartInfo start, bool safeOutput, string log) {
            sanitize = safeOutput; logFile = log;
            start.UseShellExecute = false; start.CreateNoWindow = true;
            start.RedirectStandardOutput = true; start.RedirectStandardError = true;
            process.StartInfo = start;
        }
        static string Safe(string text) {
            text = Regex.Replace(text, @"(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@", "$1***@");
            text = Regex.Replace(text, @"(?i)(https?://[^\s?#]+)[?#][^\s]*", "$1?[已省略]");
            text = Regex.Replace(text, @"(?im)(authorization\s*[:=]\s*)[^\r\n]+", "$1[已省略]");
            return Regex.Replace(text, @"(?im)((?:access[_-]?token|authorization|password|secret)\s*[:=]\s*)\S+", "$1[已省略]");
        }
        void Display(string text, bool error, StringBuilder pending) {
            TextWriter writer = error ? Console.Error : Console.Out;
            if (!sanitize) { writer.Write(text); return; }
            foreach (char value in text) {
                if (value == '\r' || value == '\n') {
                    writer.Write(Safe(pending.ToString())); writer.Write(value); pending.Length = 0;
                } else { pending.Append(value); }
            }
        }
        void Audit(string text, StringBuilder pending) {
            if (String.IsNullOrEmpty(logFile)) return;
            foreach (char value in text) {
                if (value == '\r' || value == '\n') {
                    File.AppendAllText(logFile, Safe(pending.ToString()) + value, new UTF8Encoding(false)); pending.Length = 0;
                } else { pending.Append(value); }
            }
        }
        void Pump(Stream stream, bool error) {
            try {
                StringBuilder pending = new StringBuilder(), auditPending = new StringBuilder();
                byte[] bytes = new byte[4096]; Encoding encoding = new UTF8Encoding(false);
                char[] chars = new char[encoding.GetMaxCharCount(bytes.Length)];
                Decoder decoder = encoding.GetDecoder(); int count;
                while ((count = stream.Read(bytes, 0, bytes.Length)) > 0) {
                    int length = decoder.GetChars(bytes, 0, count, chars, 0, false);
                    string text = new string(chars, 0, length);
                    lock (gate) {
                        (error ? stderr : stdout).Append(text);
                        Interlocked.Exchange(ref lastOutput, DateTime.UtcNow.Ticks);
                        Audit(text, auditPending);
                        Display(text, error, pending);
                    }
                }
                int remaining = decoder.GetChars(bytes, 0, 0, chars, 0, true);
                if (remaining > 0) {
                    string tail = new string(chars, 0, remaining);
                    lock (gate) { (error ? stderr : stdout).Append(tail); Display(tail, error, pending); }
                }
                if (sanitize && pending.Length > 0) { lock (gate) { (error ? Console.Error : Console.Out).Write(Safe(pending.ToString())); } }
                if (!String.IsNullOrEmpty(logFile) && auditPending.Length > 0) { lock (gate) { File.AppendAllText(logFile, Safe(auditPending.ToString()), new UTF8Encoding(false)); } }
            } catch (Exception exception) { OutputFailure = exception.Message; }
            finally { (error ? errDone : outDone).Set(); }
        }
        public void Start() {
            if (!process.Start()) throw new InvalidOperationException("Unable to start SDK tool");
            Thread output = new Thread(delegate() { Pump(process.StandardOutput.BaseStream, false); });
            Thread errors = new Thread(delegate() { Pump(process.StandardError.BaseStream, true); });
            output.IsBackground = true; errors.IsBackground = true; output.Start(); errors.Start();
        }
        public double IdleSeconds { get { return TimeSpan.FromTicks(DateTime.UtcNow.Ticks - Interlocked.Read(ref lastOutput)).TotalSeconds; } }
        public int Id { get { return process.Id; } }
        public bool HasExited { get { return process.HasExited; } }
        public int ExitCode { get { return process.ExitCode; } }
        public string StdOut { get { lock (gate) return stdout.ToString(); } }
        public string StdErr { get { lock (gate) return stderr.ToString(); } }
        public bool Drain(int milliseconds) {
            Stopwatch clock = Stopwatch.StartNew();
            if (!outDone.WaitOne(milliseconds)) return false;
            return errDone.WaitOne(Math.Max(0, milliseconds - (int)clock.ElapsedMilliseconds));
        }
        public void Dispose() { process.Dispose(); }
    }
}


'@
    }
    $logFile = if ($Acquisition) { Get-JobsSdkRetryLog } else { $null }
    $runner = New-Object Jobs.SdkDownloadProcess($Start, [bool]$Sanitize, $logFile)
    $begun = $false
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        $runner.Start()
        $begun = $true
        while (-not $runner.HasExited) {
            if (($Acquisition -and $runner.IdleSeconds -ge $TimeoutSeconds) -or (-not $Acquisition -and $watch.Elapsed.TotalSeconds -ge $TimeoutSeconds)) { throw 'SDK 工具超时，已请求停止本次进程树。' }
            Start-Sleep -Milliseconds 30
        }
        if (-not $runner.Drain(5000)) { throw 'SDK 工具输出管道未及时关闭。' }
        if ($runner.OutputFailure) { throw ('SDK 工具输出读取失败：' + $runner.OutputFailure) }
        $result = [pscustomobject]@{ ExitCode = $runner.ExitCode; StdOut = $runner.StdOut; StdErr = $runner.StdErr }
        if ($route -and $null -ne $route.PSObject.Properties['AutoSource']) { Add-Member -InputObject $result -NotePropertyName SdkRouteAutoSource -NotePropertyValue $route.AutoSource }
        if ($route -and ($result.ExitCode -ne 0 -or ($result.StdOut + $result.StdErr) -match '(?i)Failed to download|Error downloading|IO exception while downloading|Unable to download')) { Reject-JobsSdkRoute $route }
        return $result
    }
    catch { if ($route) { Reject-JobsSdkRoute $route }; throw }
    finally {
        if ($begun -and -not $runner.HasExited) {
            if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
                & (Join-Path ([Environment]::GetFolderPath('System')) 'taskkill.exe') /PID $runner.Id /T /F 2>&1 | Out-Null
            } else { [Diagnostics.Process]::GetProcessById($runner.Id).Kill() }
        }
        $runner.Dispose()
    }
}

# 无 curl 的终端也显示真实字节、速度与总量；不依赖宿主的进度条偏好。
function Receive-JobsSdkWebFileAttempt {
    param([string]$Uri, [string]$Destination, [int]$TimeoutSeconds = 300)
    $request = [Net.WebRequest]::Create($Uri)
    $request.Timeout = $TimeoutSeconds * 1000
    $request.ReadWriteTimeout = [Math]::Min(30000, $TimeoutSeconds * 1000)
    $request.UserAgent = 'JobsFlutterTools'
    $offset = [long]0
    $resumeFile = $Destination + '.resume.json'
    if ([IO.File]::Exists($Destination) -and [IO.File]::Exists($resumeFile)) {
        $resume = [IO.File]::ReadAllText($resumeFile) | ConvertFrom-Json
        if ($resume.Uri -ceq $Uri -and $resume.Validator) {
            $offset = (Get-Item -LiteralPath $Destination).Length
            if ($offset -gt 0) { $request.AddRange($offset); $request.Headers['If-Range'] = $resume.Validator }
        }
    }
    $response = $null; $input = $null; $output = $null
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $lastDisplay = -1.0; $received = [long]0
    try {
        Write-Host '下载进度：正在连接；已接收 0 字节。'
        $response = $request.GetResponse()
        $input = $response.GetResponseStream()
        $append = $offset -gt 0 -and [int]$response.StatusCode -eq 206
        if ($append -and $response.Headers['Content-Range'] -notmatch ('^bytes ' + $offset + '-')) { throw '响应续传位置不匹配。' }
        if (-not $append) { $offset = [long]0 }
        $validator = if ($response.Headers['ETag']) { $response.Headers['ETag'] } else { $response.Headers['Last-Modified'] }
        [IO.File]::WriteAllText($resumeFile, (@{Uri=$Uri;Validator=$validator}|ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
        $mode = if ($append) { [IO.FileMode]::Append } else { [IO.FileMode]::Create }
        $output = [IO.File]::Open($Destination, $mode, [IO.FileAccess]::Write)
        $buffer = New-Object byte[] 65536
        while (($count = $input.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $output.Write($buffer, 0, $count)
            $received += $count
            if ($watch.Elapsed.TotalSeconds - $lastDisplay -ge 1) {
                $speed = $received / [Math]::Max(0.001, $watch.Elapsed.TotalSeconds)
                $total = if ($response.ContentLength -gt 0) { ('{0}/{1} 字节（{2:P0}）' -f ($offset + $received), ($offset + $response.ContentLength), (($offset + $received) / [double]($offset + $response.ContentLength))) } else { ('{0} 字节（总量未知）' -f $received) }
                Write-Host ('下载进度：{0}；{1:N0} 字节/秒' -f $total, $speed)
                $lastDisplay = $watch.Elapsed.TotalSeconds
            }
        }
        $output.Flush()
        if ($response.ContentLength -ge 0 -and $received -ne $response.ContentLength) { throw 'SDK 下载字节数与响应总量不一致。' }
        Write-Host ('下载完成：{0} 字节；耗时 {1:N1} 秒。' -f ($offset + $received), $watch.Elapsed.TotalSeconds)
    }
    finally {
        if ($null -ne $output) { $output.Dispose() }
        if ($null -ne $input) { $input.Dispose() }
        if ($null -ne $response) { $response.Close() }
        $request.Abort()
    }
}

# 只包 SDK/工具链获取；业务构建、许可和配置写入不进入这个循环。
function Get-JobsSdkRetryLog {
    if (-not (Get-Variable JobsSdkRetryLog -Scope Script -ErrorAction SilentlyContinue)) {
        $script:JobsSdkRetryLog = Join-Path ([IO.Path]::GetTempPath()) ('JobsSdkAcquisition-' + $PID + '.log')
    }
    return $script:JobsSdkRetryLog
}
function Write-JobsSdkRetryMessage {
    param([string]$Message)
    $safe = $Message -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@'
    $safe = $safe -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]'
    $safe = $safe -replace '(?im)(authorization\s*[:=]\s*)[^\r\n]+', '$1[已省略]'
    $safe = $safe -replace '(?im)((?:access[_-]?token|password|secret)\s*[:=]\s*)\S+', '$1[已省略]'
    Write-Host $safe
    [IO.File]::AppendAllText((Get-JobsSdkRetryLog), $safe + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
}
function Invoke-JobsSdkAcquire {
    param([Parameter(Mandatory=$true)][scriptblock]$Operation, [string]$Label = 'SDK 环境', [ValidateRange(0,30)][int]$InitialDelaySeconds = 2)
    $attempt = [long]0
    while ($true) {
        $attempt++
        Write-JobsSdkRetryMessage ('准备 {0}；第 {1} 次；失败自动重试，Ctrl+C/停止结束；日志：{2}' -f $Label,$attempt,(Get-JobsSdkRetryLog))
        try {
            $result = & $Operation
            $detail = ''
            if ($null -ne $result) { foreach ($field in @('StdOut','StdErr')) { if ($null -ne $result.PSObject.Properties[$field]) { $detail += [string]$result.$field } } }
            if ($detail -match '(?i)Failed to find package|version.+(not found|does not exist)|licenses?.*(not accepted|not been accepted)') { throw ('SDK 前置条件无效：' + $detail) }
            if ($null -ne $result -and $null -ne $result.PSObject.Properties['ExitCode'] -and $result.ExitCode -eq 0 -and $detail -match '(?i)Failed to download|Could not (GET|HEAD|download)|IO exception while downloading|Error downloading|Unable to (download|resolve)|Failed to fetch|transfer closed|unexpected end of (file|archive)') { $failure=New-Object InvalidOperationException ('SDK 网络获取未完成：'+$detail);if($result.PSObject.Properties['SdkRouteAutoSource']){$failure.Data['JobsSdkAutoSource']=$result.SdkRouteAutoSource};throw $failure }
            if ($null -ne $result -and $null -ne $result.PSObject.Properties['ExitCode'] -and $result.ExitCode -ne 0) {
                if ($result.ExitCode -in @(129,130,137,143,-1073741510)) { throw (New-Object System.Management.Automation.PipelineStoppedException) }
                $detail = ''
                foreach ($field in @('StdOut','StdErr')) { if ($null -ne $result.PSObject.Properties[$field]) { $detail += [string]$result.$field } }
                $failure=New-Object InvalidOperationException ('SDK 获取失败，退出码 {0}：{1}' -f $result.ExitCode,$detail);if($result.PSObject.Properties['SdkRouteAutoSource']){$failure.Data['JobsSdkAutoSource']=$result.SdkRouteAutoSource};throw $failure
            }
            Write-JobsSdkRetryMessage ('{0} 获取成功；共 {1} 次。' -f $Label,$attempt)
            return $result
        }
        catch [System.Management.Automation.PipelineStoppedException] { throw }
        catch [System.OperationCanceledException] { throw }
        catch {
            $failure = $_.Exception
            $autoSource = [bool]$failure.Data['JobsSdkAutoSource']
            while ($null -ne $failure.InnerException) { $failure = $failure.InnerException }
            if ($failure -is [OperationCanceledException] -or $failure -is [Management.Automation.PipelineStoppedException]) { throw $failure }
            $classification = if ($autoSource) { $failure.Message -replace '404','upstream-unavailable' } else { $failure.Message }
            # 调用方的取消、路径/权限/磁盘/认证错误需要修正，不能伪装成传输故障。
            if ($failure -is [UnauthorizedAccessException] -or $failure -is [IO.DirectoryNotFoundException] -or
                $failure -is [Management.Automation.CommandNotFoundException] -or $failure -is [UriFormatException] -or $failure -is [ComponentModel.Win32Exception] -or
                $classification -match '(?i)FVM 缓存上下文无效|已取消|取消选择|(?:user|operation).*(?:cancelled|canceled)|UAC.*(?:denied|拒绝)|需要重启|requires? (?:a )?re(?:start|boot)|reboot required|restart required|Failed to find package|\(404\)|\b404\s+Not\s*Found|cannot find the (file|path)|找不到指定的(文件|路径)|No such file or directory|access denied|permission denied|no space left|disk.+full|unauthorized|forbidden|authentication failed|syntax error|invalid (argument|option)|unknown option|not recognized|不是内部或外部命令|许可证未接受|licenses?.*(not accepted|not been accepted)|(?:HTTP|status|状态码|response).{0,20}404|version.+(not found|does not exist)|repository.+not found|already exists|路径冲突') { throw }
            $delay = [int][Math]::Min(30, $InitialDelaySeconds * [Math]::Pow(2,[Math]::Min(5,$attempt - 1)))
            Write-JobsSdkRetryMessage ('{0} 第 {1} 次失败：{2}；{3} 秒后自动重试，Ctrl+C/停止结束。' -f $Label,$attempt,$failure.Message,$delay)
            if ($delay -gt 0) { Start-Sleep -Seconds $delay }
        }
    }
}
function Invoke-JobsSdkAcquireProcess {
    param([Diagnostics.ProcessStartInfo]$Start, [int]$TimeoutSeconds = 120, [switch]$Sanitize, [string]$Label = 'SDK 组件')
    return Invoke-JobsSdkAcquire -Label $Label -Operation {
        Invoke-JobsSdkLiveProcess $Start $TimeoutSeconds -Sanitize:$Sanitize -Acquisition
    }
}
function Receive-JobsSdkWebFile {
    param([string]$Uri, [string]$Destination, [int]$TimeoutSeconds = 300, [switch]$SingleAttempt, [string]$ExpectedSha256 = '', [Collections.IDictionary]$EnvironmentOverride)
    if ($ExpectedSha256 -and $ExpectedSha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'SDK 可信 SHA-256 格式无效。' }
    $operation = {
        Import-JobsSdkDownloadRoute
        $environment = if ($null -ne $EnvironmentOverride) { $EnvironmentOverride } else { Get-JobsSdkRouteEnvironment }
        $route = Get-JobsFlutterSdkRoute $Uri ('制品 '+([Uri]$Uri).AbsolutePath) $environment -ExpectedSha256 $ExpectedSha256
        if (-not $route.Ready) { throw 'SDK网络预检未得到已验证路线，保留配置并退避重测。' }
        try {
            if ($route.Verified) { Receive-JobsSdkRoutedFile $route $Destination $TimeoutSeconds $environment }
            else { Receive-JobsSdkWebFileAttempt $Uri $Destination $TimeoutSeconds }
            if ($ExpectedSha256 -and (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash -ine $ExpectedSha256) {
                $rejected = $Destination + '.invalid-' + [guid]::NewGuid().ToString('N')
                Move-Item -LiteralPath $Destination -Destination $rejected
                throw ('SDK 下载 SHA-256 不匹配，坏包保留后重新获取：' + $rejected)
            }
        } catch { Reject-JobsSdkRoute $route; throw }
    }
    if ($SingleAttempt) { & $operation; return }
    [void](Invoke-JobsSdkAcquire -Label ('SDK 文件：' + $Uri) -Operation $operation)
}

function ConvertFrom-JobsSdkMachineOutput {
    param([string]$Output)
    for ($index=0; $index -lt $Output.Length; $index++) {
        if ($Output[$index] -cne '{') { continue }
        try { $value = $Output.Substring($index).Trim() | ConvertFrom-Json -ErrorAction Stop }
        catch { continue }
        if ($null -ne $value -and $null -ne $value.PSObject.Properties['frameworkVersion']) { return $value }
    }
    throw 'Flutter --version --machine 没有返回有效版本 JSON。'
}

function Import-JobsSdkDownloadRoute {
    if (-not (Get-Command Get-JobsFlutterSdkRoute -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'SdkDownloadRoute.ps1/SdkDownloadRoute.ps1')
    }
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

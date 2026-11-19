# HarmonySimulatorCreator.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年10月23日，星期五.
# 临时假 Emulator；不联网、不安装注册、不下载镜像或创建真实设备。
[CmdletBinding()]
param()
# JOBS_SOURCE_LAYOUT_ROOT_V1：只解析本文件逻辑目录，发布 flat 副本保持原资源基准。
$script:JobsLayoutHarmonySimulatorCreatorTestsRoot = $(if ([IO.Path]::GetFileName($PSScriptRoot) -ceq 'HarmonySimulatorCreator.Tests.ps1') { Split-Path -Parent $PSScriptRoot } else { $PSScriptRoot })

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
$root = Split-Path -Parent ${script:JobsLayoutHarmonySimulatorCreatorTestsRoot}
$package = Join-Path $root 'JobsHarmonySimulatorCreator'
$action = Import-Module (Join-Path $package 'Scripts/Action.psm1') -PassThru -DisableNameChecking
$installer = Import-Module (Join-Path $package 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
$script:assertions = 0
function Assert-Harmony { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw ('FAIL: ' + $Message) }; $script:assertions++ }
function Assert-HarmonyThrows { param([scriptblock]$Body, [string]$Message, [string]$Pattern = '.'); $caught = ''; try { & $Body | Out-Null } catch { $caught = $_.Exception.Message }; Assert-Harmony ($caught -match $Pattern) ($Message + ' | ' + $caught) }
$temporaryBase = [IO.Path]::GetTempPath()
if ([IO.Directory]::Exists('/private/tmp')) { $temporaryBase = '/private/tmp' }
$temporary = Join-Path $temporaryBase ('JobsHarmonySimulator-' + [guid]::NewGuid().ToString('N'))
$environmentNames = @('LOCALAPPDATA', 'HARMONY_EMULATOR_BIN', 'DEVECO_STUDIO_HOME', 'TOOL_HOME', 'HARMONY_CLT_ARCHIVE', 'PROCESSOR_ARCHITECTURE', 'PROCESSOR_ARCHITEW6432', 'JOBS_HARMONY_TRACE', 'JOBS_HARMONY_IMAGES', 'JOBS_HARMONY_STATE', 'JOBS_HARMONY_CREATED', 'JOBS_HARMONY_COUNT', 'JOBS_HARMONY_MODE', 'JOBS_HARMONY_FAIL', 'FZF_DEFAULT_OPTS', 'FZF_DEFAULT_OPTS_FILE')
$savedEnvironment = @{}
foreach ($name in $environmentNames) { $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
    [void][IO.Directory]::CreateDirectory($temporary)
    $env:LOCALAPPDATA = Join-Path $temporary 'Local'
    $env:PROCESSOR_ARCHITECTURE = 'AMD64'
    $env:PROCESSOR_ARCHITEW6432 = $null
    $env:DEVECO_STUDIO_HOME = $null
    $env:TOOL_HOME = $null
    $env:HARMONY_CLT_ARCHIVE = $null
    foreach ($name in @('TRACE', 'IMAGES', 'STATE', 'CREATED', 'COUNT')) { [Environment]::SetEnvironmentVariable(('JOBS_HARMONY_' + $name), (Join-Path $temporary ($name.ToLowerInvariant() + '.json')), 'Process') }
    $emulator = Join-Path $temporary 'DevEco 中文 & 100%/tools/emulator/Emulator.exe'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $emulator))
    $body = @'
#!/bin/sh
printf '%s|%s\n' "$#" "$*" >> "$JOBS_HARMONY_TRACE"
if [ "$JOBS_HARMONY_FAIL" = "$1" ]; then echo fixture-error >&2; exit 37; fi
case "$1" in
-help)
    if [ "$JOBS_HARMONY_MODE" = old ]; then echo '-list -start'; else printf '\033[32m-create -imageList -list -start\033[0m\n'; fi ;;
-imageList) if [ "$JOBS_HARMONY_MODE" = empty-native ]; then echo "No images matching the criteria were found." >&2; else cat "$JOBS_HARMONY_IMAGES"; fi ;;
-list)
    if [ "$JOBS_HARMONY_MODE" = empty-native ]; then echo "[Empty]"; exit 0; fi
    count=$(cat "$JOBS_HARMONY_COUNT"); count=$((count + 1)); printf '%s' "$count" > "$JOBS_HARMONY_COUNT"
    if [ "$JOBS_HARMONY_MODE" = race ] && [ "$count" -ge 2 ]; then echo '[{"name":"TestNew"}]'; else cat "$JOBS_HARMONY_STATE"; fi ;;
-create) cp "$JOBS_HARMONY_CREATED" "$JOBS_HARMONY_STATE" ;;
-start) echo fixture-start ;;
-license) echo fixture-license ;;
*) exit 91 ;;
esac
'@
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        $source = Join-Path $temporary 'EmulatorFixture.cs'
        $code = @'
using System;
using System.IO;
using System.Text;
class EmulatorFixture {
    static int Main(string[] args) {
        Console.OutputEncoding = new UTF8Encoding(false);
        File.AppendAllText(Environment.GetEnvironmentVariable("JOBS_HARMONY_TRACE"), args.Length + "|" + String.Join(" ", args) + Environment.NewLine);
        if (args.Length == 0) return 91;
        if (Environment.GetEnvironmentVariable("JOBS_HARMONY_FAIL") == args[0]) { Console.Error.WriteLine("fixture-error"); return 37; }
        string mode = Environment.GetEnvironmentVariable("JOBS_HARMONY_MODE");
        switch(args[0]) {
            case "-help": Console.WriteLine(mode == "old" ? "-list -start" : "\x1b[32m-create -imageList -list -start\x1b[0m"); break;
            case "-imageList": if (mode == "empty-native") Console.Error.WriteLine("No images matching the criteria were found."); else Console.Write(File.ReadAllText(Environment.GetEnvironmentVariable("JOBS_HARMONY_IMAGES"))); break;
            case "-list":
                if (mode == "empty-native") { Console.WriteLine("[Empty]"); break; }
                string countFile = Environment.GetEnvironmentVariable("JOBS_HARMONY_COUNT");
                int count = Int32.Parse(File.ReadAllText(countFile)) + 1; File.WriteAllText(countFile, count.ToString());
                Console.Write(mode == "race" && count >= 2 ? "[{\"name\":\"TestNew\"}]" : File.ReadAllText(Environment.GetEnvironmentVariable("JOBS_HARMONY_STATE"))); break;
            case "-create": File.Copy(Environment.GetEnvironmentVariable("JOBS_HARMONY_CREATED"), Environment.GetEnvironmentVariable("JOBS_HARMONY_STATE"), true); break;
            case "-start": Console.WriteLine("fixture-start"); break;
            case "-license": Console.WriteLine("fixture-license"); break;
            default: return 91;
        }
        return 0;
    }
}
'@
        [IO.File]::WriteAllText($source, $code, (New-Object Text.UTF8Encoding($false)))
        $csc = Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
        & $csc /nologo /target:exe ('/out:' + $emulator) $source
        if ($LASTEXITCODE -ne 0) { throw '临时 Emulator 夹具编译失败。' }
    } else {
        [IO.File]::WriteAllText($emulator, $body.Replace("`r`n", "`n"), (New-Object Text.UTF8Encoding($false)))
        & /bin/chmod 700 $emulator
        if ($LASTEXITCODE -ne 0) { throw '临时 Emulator 权限设置失败。' }
    }
    $agreements = Join-Path (Split-Path -Parent $emulator) 'agreement'
    [void][IO.Directory]::CreateDirectory($agreements)
    foreach ($file in @('HarmonyOS_SDK_Agreement.txt', 'HarmonyOS_Software_Service_Agreement.txt')) { [IO.File]::WriteAllText((Join-Path $agreements $file), 'Official agreement fixture') }
    $env:HARMONY_EMULATOR_BIN = $emulator
    $imageJson = '[{"SoftWareVersion":"6.0.0.112","deviceType":"phone","downloaded":"true","osVersion":"HarmonyOS 6.0.1(21)","releaseType":"Release","upgradable":"false"}]'
    function Reset-HarmonyFixture {
        [IO.File]::WriteAllText($env:JOBS_HARMONY_IMAGES, $imageJson)
        [IO.File]::WriteAllText($env:JOBS_HARMONY_TRACE, '')
        [IO.File]::WriteAllText($env:JOBS_HARMONY_STATE, '[]')
        [IO.File]::WriteAllText($env:JOBS_HARMONY_COUNT, '0')
        [IO.File]::WriteAllText($env:JOBS_HARMONY_CREATED, '[{"name":"TestNew","deviceType":"phone","os":{"osVersion":"HarmonyOS 6.0.1(21)"}}]')
        $env:JOBS_HARMONY_MODE = $null
        $env:JOBS_HARMONY_FAIL = $null
        & $action {
            $script:Answers = New-Object 'System.Collections.Generic.Queue[string]'
            foreach ($answer in @('', '', 'skip')) { $script:Answers.Enqueue($answer) }
        }
    }
    & $action {
        function script:Test-JobsHarmonyDesktop { param($Target) return $Target -ceq 'fixture-desktop' }
        function script:Read-JobsHarmonyInput { param($Prompt); if ($script:Answers.Count -eq 0) { throw 'fixture EOF' }; return $script:Answers.Dequeue() }
        function script:Select-JobsHarmonyChoice { param($Title, $Choices) return $Choices[0] }
    }
    Reset-HarmonyFixture
    Assert-Harmony ((& $action { Get-JobsHarmonyArchitecture }) -ceq 'x86_64') 'x64 宿主支持'
    $env:PROCESSOR_ARCHITEW6432 = 'ARM64'
    Assert-HarmonyThrows { & $action { Get-JobsHarmonyArchitecture } } '原生 ARM64 即使模拟 AMD64 也拒绝'
    $env:PROCESSOR_ARCHITEW6432 = $null
    Assert-Harmony ((& $action { Get-JobsHarmonyEmulator }) -ceq $emulator) '显式工具路径支持中文空格与 CMD 元字符'
    Assert-HarmonyThrows { & $action { param($Path) Get-JobsHarmonyEmulator (Join-Path $Path 'missing.exe') } $temporary } '坏显式路径不回退'
    $env:HARMONY_EMULATOR_BIN = $null
    $env:DEVECO_STUDIO_HOME = Join-Path $temporary 'DevEco 中文 & 100%'
    Assert-Harmony ((& $action { Get-JobsHarmonyEmulator }) -ceq $emulator) 'DevEco 根目录工具发现'
    $env:DEVECO_STUDIO_HOME = Join-Path $temporary 'bad-root'
    Assert-HarmonyThrows { & $action { Get-JobsHarmonyEmulator } } '坏显式 DevEco 根目录不回退'
    $env:DEVECO_STUDIO_HOME = $null
    $env:HARMONY_EMULATOR_BIN = $emulator
    $check = & $action { Get-JobsHarmonyCheck }
    Assert-Harmony ($check.Images.Count -eq 1 -and $check.Instances.Count -eq 0) '只读 Check 识别镜像和空实例数组'
    Assert-Harmony ((Get-Content -LiteralPath $env:JOBS_HARMONY_TRACE) -join '~' -ceq '1|-help~3|-imageList -downloaded true~2|-list -details') 'Check 仅官方只读命令，无下载 / 创建 / 启动'
    Assert-Harmony (-not [IO.Directory]::Exists($env:LOCALAPPDATA)) 'Check 不创建日志或安装状态'
    Reset-HarmonyFixture
    $env:JOBS_HARMONY_MODE = 'empty-native'
    $emptyCheck = & $action { Get-JobsHarmonyCheck }
    Assert-Harmony ($emptyCheck.Images.Count -eq 0 -and $emptyCheck.Instances.Count -eq 0) '实际 CLI 空镜像 / 空实例响应正确识别'
    Reset-HarmonyFixture
    $env:JOBS_HARMONY_MODE = 'old'
    Assert-HarmonyThrows { & $action { Get-JobsHarmonyCheck } } '旧 Emulator / Android 工具能力不足拒绝' '未确认支持 -create'
    Assert-Harmony (@(Get-Content -LiteralPath $env:JOBS_HARMONY_TRACE).Count -eq 1) '能力失败不继续查询或创建'
    Reset-HarmonyFixture
    [IO.File]::WriteAllText($env:JOBS_HARMONY_IMAGES, '[]')
    Assert-HarmonyThrows { & $action { Invoke-JobsHarmonySimulatorAction -Target 'fixture-desktop' -Name 'TestNew' } } '缺镜像提示 Device Manager 并停止' 'Device Manager'
    Assert-Harmony (-not ((Get-Content -LiteralPath $env:JOBS_HARMONY_TRACE) -join ' ').Contains('-create ')) '缺镜像不创建'
    foreach ($bad in @('{}', '[{"deviceType":"phone"}]', '[{"SoftWareVersion":"1","deviceType":"phone","downloaded":"yes","osVersion":"HarmonyOS 6","releaseType":"Release","upgradable":"false"}]')) {
        [IO.File]::WriteAllText($env:JOBS_HARMONY_IMAGES, $bad)
        Assert-HarmonyThrows { & $action { param($File) Get-JobsHarmonyImages $File } $emulator } '拒绝不明确或不完整的镜像 JSON'
    }
    [IO.File]::WriteAllText($env:JOBS_HARMONY_IMAGES, $imageJson.Replace('"Release"', '"Beta"'))
    Assert-Harmony (@(& $action { param($File) Get-JobsHarmonyImages $File } $emulator).Count -eq 0) '未将 Beta 镜像作为 Release 使用'
    [IO.File]::WriteAllText($env:JOBS_HARMONY_IMAGES, $imageJson.Replace('"downloaded":"true"', '"downloaded":false'))
    Assert-Harmony (@(& $action { param($File) Get-JobsHarmonyImages $File } $emulator).Count -eq 0) '不选择未下载镜像'
    foreach ($bad in @('[{"name":123}]', '[{"name":"bad\nname"}]', '[{"name":"One"},{"name":"one"}]', '{"data":[]}')) {
        [IO.File]::WriteAllText($env:JOBS_HARMONY_STATE, $bad)
        Assert-HarmonyThrows { & $action { param($File) Get-JobsHarmonyInstances $File } $emulator } '拒绝数字/控制字符/大小写冲突/未知容器实例'
    }
    [IO.File]::WriteAllText($env:JOBS_HARMONY_STATE, '{"name":"Single"}')
    Assert-Harmony (@(& $action { param($File) Get-JobsHarmonyInstances $File } $emulator).Count -eq 1) '兼容单个具 name 的 JSON 对象'
    Assert-HarmonyThrows { & $action { New-JobsHarmonyName -Existing @([pscustomobject]@{name='testnew'}) -Name 'TestNew' } } '大小写同名拒绝覆盖'
    Assert-HarmonyThrows { & $action { New-JobsHarmonyName -Name 'bad & name' } } '拒绝不合法新名称'
    foreach ($badName in @('JobsHarmony-phone', ' phone', 'phone ', "phone`n", ('P' * 65))) {
        Assert-HarmonyThrows { & $action { param($Value) New-JobsHarmonyName -Name $Value } $badName } '原生命名规则拒绝连字符和边界非法字符' '不支持连字符'
    }
    foreach ($goodName in @('JobsHarmony_phone', 'Phone + 1', ('P' * 64))) {
        Assert-Harmony ((& $action { param($Value) New-JobsHarmonyName -Name $Value } $goodName) -ceq $goodName) '允许官方支持的空格、加号和下划线'
    }
    # 独立 CLT SDK 路径只写入刚创建且匹配名称的实例，已有原生配置必须保留。
    $cltEmulator = Join-Path $temporary 'CLT 中文 & 100%/emulator/Emulator.exe'
    $cltSdk = Join-Path (Split-Path -Parent (Split-Path -Parent $cltEmulator)) 'sdk'
    $cltHdc = Join-Path $cltSdk 'default/openharmony/toolchains/hdc.exe'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $cltHdc))
    [IO.File]::WriteAllText($cltHdc, 'fixture')
    $newDirectory = Join-Path $temporary 'deployed/NewSdk'
    [void][IO.Directory]::CreateDirectory($newDirectory)
    $newConfig = Join-Path $newDirectory 'config.ini'
    $newInstance = [pscustomobject]@{ name = 'NewSdk'; instancePath = $newDirectory }
    [IO.File]::WriteAllText($newConfig, "name=NewSdk`r`nhw.ramSize=4096`r`nsdkPath=`r`n")
    & $action { param($Bin, $Instance) Set-JobsHarmonyCreatedSdk $Bin $Instance } $cltEmulator $newInstance
    Assert-Harmony ([IO.File]::ReadAllText($newConfig) -ceq ("name=NewSdk`r`nhw.ramSize=4096`r`nsdkPath=" + $cltSdk + "`r`n")) 'CLT SDK 指向同包 HDC，保留其它字段和换行'
    $nativeConfig = "name=NewSdk`nharmonyos.sdk.path=/native/sdk`n"
    [IO.File]::WriteAllText($newConfig, $nativeConfig)
    & $action { param($Bin, $Instance) Set-JobsHarmonyCreatedSdk $Bin $Instance } $cltEmulator $newInstance
    Assert-Harmony ([IO.File]::ReadAllText($newConfig) -ceq $nativeConfig) '保留官方已有 SDK 路径'
    [IO.File]::WriteAllText($newConfig, "name=Existing`n")
    Assert-HarmonyThrows { & $action { param($Bin, $Instance) Set-JobsHarmonyCreatedSdk $Bin $Instance } $cltEmulator $newInstance } 'SDK 写入前校验新实例名称' '名称不一致'
    Assert-Harmony ([IO.File]::ReadAllText($newConfig) -ceq "name=Existing`n") '拒绝时配置未改动'
    $first = & $action { New-JobsHarmonyName -Existing @() }
    $second = & $action { New-JobsHarmonyName -Existing @([pscustomobject]@{name=$args[0]}) } $first
    Assert-Harmony ($first -cne $second -and $first -cmatch '\AJobsHarmony_[A-Za-z0-9_]+\z') '自动名称唯一且适合 CLI'
    Assert-HarmonyThrows { & $action { Get-JobsHarmonyInstanceVersion ([pscustomobject]@{'os.osVersion'='A';os=[pscustomobject]@{osVersion='B'}}) } } '平铺与嵌套系统版本冲突拒绝'
    Reset-HarmonyFixture
    & $action { Invoke-JobsHarmonySimulatorAction -Target 'fixture-desktop' -Name 'TestNew' }
    $records = @(Get-Content -LiteralPath $env:JOBS_HARMONY_TRACE)
    Assert-Harmony ($records -join '~' -ceq '1|-help~3|-imageList -downloaded true~2|-list -details~2|-list -details~6|-create TestNew -deviceType phone -osVersion HarmonyOS 6.0.1(21)~2|-list -details') '创建前重读并使用准确 -create NAME 契约，版本完整保持单 argv'
    Assert-Harmony (@($records | Where-Object { $_ -match '-start|-install|-force|-license|-name' }).Count -eq 0) '跳过启动，始终不下载/强制/接受许可/虚构-name参数'
    Reset-HarmonyFixture
    & $action { $script:Answers.Clear(); foreach($answer in @('', '', '', '')) { $script:Answers.Enqueue($answer) } }
    & $action { Invoke-JobsHarmonySimulatorAction -Target 'fixture-desktop' -Name 'TestNew' }
    Assert-Harmony ((Get-Content -LiteralPath $env:JOBS_HARMONY_TRACE)[-1] -ceq '2|-start TestNew') '本人选择后才启动新实例'
    Reset-HarmonyFixture
    $env:JOBS_HARMONY_MODE = 'race'
    Assert-HarmonyThrows { & $action { Invoke-JobsHarmonySimulatorAction -Target 'fixture-desktop' -Name 'TestNew' } } '确认期间新增同名实例时停止' '拒绝覆盖'
    Assert-Harmony (@(Get-Content -LiteralPath $env:JOBS_HARMONY_TRACE | Where-Object { $_ -match '\|-create ' }).Count -eq 0) '并发同名不调用创建'
    Reset-HarmonyFixture
    $env:JOBS_HARMONY_FAIL = '-create'
    Assert-HarmonyThrows { & $action { Invoke-JobsHarmonySimulatorAction -Target 'fixture-desktop' -Name 'TestNew' } } '真实假创建失败传播退出码' '退出码 37'
    Assert-Harmony (-not ((Get-Content -LiteralPath $env:JOBS_HARMONY_TRACE) -join ' ').Contains('-start ')) '创建失败不启动'
    Reset-HarmonyFixture
    [IO.File]::WriteAllText($env:JOBS_HARMONY_CREATED, '[]')
    Assert-HarmonyThrows { & $action { Invoke-JobsHarmonySimulatorAction -Target 'fixture-desktop' -Name 'TestNew' } } '退出0但回读缺实例不能成功' '保留现场'
    Reset-HarmonyFixture
    [IO.File]::WriteAllText($env:JOBS_HARMONY_CREATED, '[{"name":"TestNew","deviceType":"tablet","os":{"osVersion":"HarmonyOS 6.0.1(21)"}}]')
    Assert-HarmonyThrows { & $action { Invoke-JobsHarmonySimulatorAction -Target 'fixture-desktop' -Name 'TestNew' } } '回读产品类型不匹配拒绝' '保留现场'
    Reset-HarmonyFixture
    [IO.File]::WriteAllText($env:JOBS_HARMONY_CREATED, 'non-json output')
    Assert-HarmonyThrows { & $action { Invoke-JobsHarmonySimulatorAction -Target 'fixture-desktop' -Name 'TestNew' } } '创建后未知顶层输出保留现场' '详情回读失败'
    Reset-HarmonyFixture
    & $action { $script:Answers.Clear(); $script:Answers.Enqueue('cancel') }
    Assert-HarmonyThrows { & $action { Invoke-JobsHarmonySimulatorAction -Target 'fixture-desktop' -Name 'TestNew' } } '初始取消不调用工具' '已取消'
    Assert-Harmony ((Get-Item -LiteralPath $env:JOBS_HARMONY_TRACE).Length -eq 0) '初始取消零工具调用'
    Reset-HarmonyFixture
    & $action { $script:Answers.Clear(); $script:Answers.Enqueue(''); $script:Answers.Enqueue('cancel') }
    Assert-HarmonyThrows { & $action { Invoke-JobsHarmonySimulatorAction -Target 'fixture-desktop' -Name 'TestNew' } } '创建确认取消不创建' '已取消'
    Assert-Harmony (@(Get-Content -LiteralPath $env:JOBS_HARMONY_TRACE | Where-Object { $_ -match '\|-create ' }).Count -eq 0) '确认取消不调用创建'
    Assert-HarmonyThrows { & $action { Invoke-JobsHarmonySimulatorAction -Target 'ordinary-folder' } } '业务入口复检桌面边界' '仅适用于系统桌面'
    $manifest = Get-Content -LiteralPath (Join-Path $package 'Extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $release = Join-Path $temporary 'release'
    & $installer { param($Path,$Dest) New-JobsPackageRelease -PackagePath $Path -Destination $Dest } $package $release | Out-Null
    $plan = @(& $installer { param($Manifest,$Release) Get-JobsPackageRegistryPlan -Manifest $Manifest -ReleasePath $Release -PowerShellPath 'powershell.exe' } $manifest $release)
    Assert-Harmony ($plan.Count -eq 2 -and $plan[0].Key.Contains('DesktopBackground') -and $plan[0].Key.Contains('shellex') -and $plan[1].Key -match '95E5B535-2EB8-48CA-98B5-A14D17A0A859') '独立桌面handler与CLSID，不扩展文件夹'
    foreach ($file in @('Run.cmd','Scripts/Action.psm1','Scripts/HarmonyTools.ps1','Scripts/CreateHarmonySimulator.ps1','Scripts/DesktopScope.h','Scripts/ContextMenu.cpp')) { Assert-Harmony ([IO.File]::Exists((Join-Path $release $file))) ('独立发布完整：'+$file) }
    $selector = Import-Module (Join-Path $package 'Scripts/Action.psm1') -PassThru -DisableNameChecking -Force
    & $selector { function script:Find-JobsExecutable { param($Name,$Candidates) return $null }; function script:Read-JobsHarmonyInput { param($Prompt) return '' } }
    Assert-Harmony ((& $selector { Select-JobsHarmonyChoice '镜像' @('手机中文','平板') }) -ceq '手机中文') '无 fzf 编号回车选择第一项'
    & $selector { function script:Read-JobsHarmonyInput { param($Prompt) throw 'fixture EOF' } }
    Assert-HarmonyThrows { & $selector { Select-JobsHarmonyChoice '镜像' @('手机') } } 'EOF 不执行默认选项' 'EOF'
    Write-Host ('PASS: HarmonySimulatorCreator.Tests.ps1 (' + $script:assertions + ' assertions)')
    Write-Host 'SKIP: Windows PowerShell 5.1、真实 Emulator.exe/详情格式、MSVC/Explorer、许可与真实创建启动需 Windows 实机。'
} finally {
    foreach ($name in $savedEnvironment.Keys) {
        if ($null -eq $savedEnvironment[$name]) { Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process') }
    }
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

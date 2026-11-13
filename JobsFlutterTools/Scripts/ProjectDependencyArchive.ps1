# ProjectDependencyArchive.ps1 | 原生依赖分层归档与校验导入。
# Created by Jobs on 2026年10月29日，星期四.
# 随 ProjectSetup 加载；只复制所选缓存层，不执行归档中脚本，不覆盖不同内容。


# Jobs enter-choice emphasis is display-only; input and business decisions stay with callers.
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
function Test-JobsEnterChoiceColor {
    if ((Test-Path Env:NO_COLOR) -or $env:TERM -ieq 'dumb' -or $env:PLAIN_OUTPUT -eq '1') { return $false }
    $consoleType = [Console]
    if ($null -eq $consoleType.GetProperty('IsInputRedirected') -or $null -eq $consoleType.GetProperty('IsOutputRedirected')) { return $false }
    return ($Host.Name -ceq 'ConsoleHost' -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected)
}
# Older hosts keep native colors without sending unsupported bold escape sequences.
function Test-JobsEnterChoiceBold {
    $property = $Host.UI.PSObject.Properties['SupportsVirtualTerminal']
    return ($null -ne $property -and [bool]$property.Value)
}
# Separate ordinary question text from Enter and arbitrary-input options without changing words.
function Get-JobsEnterChoiceParts {
    param([string]$Text)
    $red = '(?:(?:\u8f93\u5165)?(?:\u4efb\u610f(?:\u975e\u7a7a)?(?:\u5b57\u7b26|\u5185\u5bb9|\u6587\u5b57|\u8f93\u5165)?|\u975e\u7a7a(?:\u8f93\u5165|\u5b57\u7b26|\u5185\u5bb9)?|(?:\u5176\u5b83|\u5176\u4ed6)(?:\u975e\u7a7a)?(?:\u8f93\u5165|\u5185\u5bb9|\u5b57\u7b26)?))|(?:any\s+(?:(?:other|non[- ]empty)\s+)?(?:input|text|characters?)|non[- ]empty\s+input)'
    $green = '(?:(?:\u76f4\u63a5|\u53ea\u9700|\u4ec5(?:\u9700)?|\u6309(?:\u4e0b)?|\u7a7a)?\s*\u56de\u8f66|(?:press\s+)?\bEnter\b(?!\s+(?:YES|REPAIR|CLEAN|CONTINUE)\b))'
    $pattern = '(?is)(?<red>(?:' + $red + ')[^;\uFF1B\r\n]*?(?=[;\uFF1B\r\n]|\z))|(?<green>(?:' + $green + ')[^;\uFF1B\r\n]*?(?=(?:' + $red + ')|[;\uFF1B\r\n]|\z))'
    $offset = 0
    foreach ($match in [regex]::Matches($Text, $pattern)) {
        if ($match.Index -gt $offset) { [pscustomobject]@{ Text = $Text.Substring($offset, $match.Index - $offset); Color = '' } }
        $prefix = [regex]::Split($Text.Substring(0, $match.Index), '[;\uFF1B\r\n]')[-1]
        $typed = $prefix -match '(?i)(?:\u8f93\u5165|\u952e\u5165|type|enter)\s*(?:\u5927\u5199\s*)?(?:YES|REPAIR|CLEAN|CONTINUE)\b|\u7cbe\u786e\u8f93\u5165|\u8f93\u5165[^;\uFF1B\r\n]*[\u540e\u518d]\s*$'
        $color = if ($match.Groups['red'].Success) { 'Red' } elseif ($typed) { '' } else { 'Green' }
        [pscustomobject]@{ Text = $match.Value; Color = $color }
        $offset = $match.Index + $match.Length
    }
    if ($offset -lt $Text.Length) { [pscustomobject]@{ Text = $Text.Substring($offset); Color = '' } }
}
# Native host text remains plain in information streams and logs; bold control is console-only.
function Write-JobsEnterChoiceText {
    [CmdletBinding()]
    param([Parameter(Position=0)][AllowNull()][object]$Object, [switch]$NoNewline, [ConsoleColor]$ForegroundColor, [ConsoleColor]$BackgroundColor, [object]$Separator = ' ')
    $text = if ($Object -is [array]) { $Object -join [string]$Separator } else { [string]$Object }
    if (-not (Test-JobsEnterChoiceColor)) {
        Write-Host $Object -NoNewline:$NoNewline -Separator $Separator
        return
    }
    $normal = @{}
    if ($PSBoundParameters.ContainsKey('ForegroundColor')) { $normal.ForegroundColor = $ForegroundColor }
    if ($PSBoundParameters.ContainsKey('BackgroundColor')) { $normal.BackgroundColor = $BackgroundColor }
    foreach ($part in @(Get-JobsEnterChoiceParts $text)) {
        if (-not $part.Color) { Write-Host $part.Text -NoNewline @normal; continue }
        $bold = Test-JobsEnterChoiceBold
        if ($bold) { [Console]::Write(([string][char]27) + '[1m') }
        try { Write-Host $part.Text -ForegroundColor $part.Color -NoNewline }
        finally { if ($bold) { [Console]::Write(([string][char]27) + '[0m') } }
    }
    if (-not $NoNewline) { Write-Host }
}
# Delegate the original reader, including secure input and EOF behavior, after prompt display.
function Read-JobsEnterChoiceHost {
    [CmdletBinding()]
    param([Parameter(Position=0)][string]$Prompt, [switch]$AsSecureString, [switch]$MaskInput)
    if ($AsSecureString -or $MaskInput -or -not (Test-JobsEnterChoiceColor) -or @((Get-JobsEnterChoiceParts $Prompt) | Where-Object { $_.Color }).Count -eq 0) {
        return (Read-Host @PSBoundParameters)
    }
    Write-JobsEnterChoiceText ($Prompt + ': ') -NoNewline
    return (Read-Host)
}

function Read-JobsArchiveDirectory {
    param([string]$Prompt,[string]$Default='',[switch]$MayBeMissing)
    $value = Read-JobsEnterChoiceHost $Prompt
    if ([string]::IsNullOrWhiteSpace($value)) { $value = $Default }
    if (-not [IO.Directory]::Exists($value)) { $value = $value.Trim().Trim('"') }
    if (-not $value -or -not [IO.Path]::IsPathRooted($value)) { throw '需要明确的绝对目录；已取消。' }
    $value = [IO.Path]::GetFullPath($value)
    Assert-JobsSetupDirectory $value
    if (-not $MayBeMissing -and -not [IO.Directory]::Exists($value)) { throw ('目录不存在：'+$value) }
    return $value
}

# FVM SDK 链接为正常绑定，只读取其明确目标；其它缓存链接仍由引擎拒绝。
function Get-JobsArchiveFlutter {
    param([string]$Project)
    $root = Join-Path $Project '.fvm/flutter_sdk'
    if (Test-Path -LiteralPath $root) {
        $item = Get-Item -LiteralPath $root -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            $targets = @($item.Target)
            if ($targets.Count -ne 1 -or -not $targets[0]) { throw '项目 SDK 链接目标不明确。' }
            $root = [string]$targets[0]
            if (-not [IO.Path]::IsPathRooted($root)) { $root = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $item.FullName) $root)) }
        }
    } else {
        $profile = Get-JobsSetupProfile $Project
        if ($profile -and $profile.FlutterMode -ceq 'system') { $root = Split-Path -Parent (Split-Path -Parent $profile.FlutterPath) }
        else { $root = Read-JobsArchiveDirectory '输入已有 Flutter SDK 根目录（空输入取消；本动作不安装 SDK）' }
    }
    Assert-JobsSetupDirectory $root
    $flutter = Get-JobsSetupFlutter (Join-Path $root 'bin/flutter.bat') $Project 'system'
    if ($flutter.Architecture -ceq 'unknown') { throw 'SDK 未返回可确认的本机 Dart 架构，不能生成跨架构误用的缓存快照。' }
    return $flutter
}

function Get-JobsArchiveDart {
    param([string]$Project)
    $candidates = @((Join-Path $Project '.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dart.exe'))
    if ($env:DART_SDK) { $candidates += Join-Path $env:DART_SDK 'bin/dart.exe' }
    $found = Find-JobsExecutable 'dart.exe' @('dart')
    if ($found) { $candidates += $found }
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if ([IO.File]::Exists($candidate)) {
            try {
                $probe = Invoke-JobsSetupProcess $candidate @('--version') $Project 30
                if (($probe.StdOut+$probe.StdErr) -match 'Dart SDK version:') { return $candidate }
            } catch { Write-JobsSetupMessage ('Dart 候选不可用：'+$candidate) }
        }
    }
    $sdk = Read-JobsArchiveDirectory '没有可用 Dart，输入已有 Dart SDK 根目录（空输入取消；不会安装运行时）'
    $candidate = Join-Path $sdk 'bin/dart.exe'
    if (-not [IO.File]::Exists($candidate)) { throw '所选目录没有 bin/dart.exe。' }
    $probe = Invoke-JobsSetupProcess $candidate @('--version') $Project 30
    if (($probe.StdOut+$probe.StdErr) -notmatch 'Dart SDK version:') { throw '所选 Dart 无法确认可运行。' }
    return $candidate
}

function Get-JobsArchiveArchitecture {
    if ($env:PROCESSOR_ARCHITEW6432) { return $env:PROCESSOR_ARCHITEW6432.ToLowerInvariant() }
    if ($env:PROCESSOR_ARCHITECTURE) { return $env:PROCESSOR_ARCHITECTURE.ToLowerInvariant() }
    return ('process-'+([IntPtr]::Size*8))
}

# 文件夹名称与工程位置构成类型边界；不允许把任意用户目录作为缓存根。
function Assert-JobsArchiveRoot {
    param([string]$Project,[string]$Kind,[string]$Platform,[string]$Root,[string]$Layer)
    Assert-JobsSetupDirectory $Root
    $leaf = [IO.Path]::GetFileName($Root.TrimEnd('\','/'))
    switch ($Kind) {
        gradle {
            if ($leaf -cne $Layer) { throw ('Gradle 缓存根必须为所选组件 '+$Layer+'，不能选择整个 Gradle 用户目录。') }
            if ($Layer -ceq 'modules-2' -and [IO.Path]::GetFileName((Split-Path -Parent $Root)) -cne 'caches') { throw 'Maven 缓存必须位于 caches/modules-2。' }
        }
        ohos { if ($leaf -cne $Layer) { throw ('鸿蒙缓存层必须为 '+$Layer+'，不能混入其它层。') } }
        native {
            $name = if ($Platform -ceq 'android') { 'app' } else { $Platform }
            $expected = [IO.Path]::GetFullPath((Join-Path $Project ('build/'+$name)))
            if (-not [string]::Equals($expected,[IO.Path]::GetFullPath($Root),[StringComparison]::OrdinalIgnoreCase)) { throw 'native 只处理当前工程 build 下所选目标目录，不能选择整个 build 或其它平台。' }
        }
        precache {
            $normalized = $Root.Replace('\','/').TrimEnd('/')
            if (-not $normalized.EndsWith('/bin/cache',[StringComparison]::OrdinalIgnoreCase)) { throw 'SDK 平台资源根必须为 bin/cache；内核只处理 artifacts、Web SDK、缓存引擎包和配对 stamp，不能复制整个缓存或 Dart runtime。' }
        }
        web {
            if ($leaf -cne 'node_modules' -or -not [IO.File]::Exists((Join-Path (Split-Path -Parent $Root) 'package.json'))) { throw 'Web 缓存根必须是存在 package.json 的工程 node_modules。' }
            $parent = [IO.Path]::GetFullPath((Split-Path -Parent $Root))
            if ($parent -cnotin @([IO.Path]::GetFullPath($Project),[IO.Path]::GetFullPath((Join-Path $Project 'web')))) { throw '只处理当前工程根或 web/ 的 node_modules。' }
        }
    }
}

function Get-JobsArchiveCachePlan {
    param([string]$Project,[string]$Kind,[string]$Fzf,$Manifest,[switch]$Import)
    $platform = ''; $version = ''; $cache = ''; $layer = ''; $flutter = $null
    if ($Import) { $platform = [string]$Manifest.platform }
    switch ($Kind) {
        gradle {
            $platform = 'android'; $spec = Get-JobsSetupGradleSpec $Project
            $user = if ($env:GRADLE_USER_HOME) { $env:GRADLE_USER_HOME } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) '.gradle' }
            $components = @('Maven 原生库与插件缓存（modules-2）','工程固定 Wrapper 分发')
            if ($Import -and [string]$Manifest.toolVersion -like '* wrapper') { [array]::Reverse($components) }
            $component = Select-JobsSetupChoice $Fzf '选择 Gradle 归档组件（两类快照不可互换）' $components
            if ($component.StartsWith('Maven')) {
                $layer = 'modules-2'; $cache = Join-Path $user 'caches/modules-2'
                $version = 'Gradle '+$spec.Version.ToString()+' modules'
            } else {
                $layer = $spec.Name.Substring(0,$spec.Name.Length-4)
                $archive = Get-JobsSetupWrapperZip $Project $spec
                $cache = Split-Path -Parent (Split-Path -Parent $archive)
                $version = 'Gradle '+$spec.Version.ToString()+' wrapper'
            }
        }
        ohos {
            $platform = 'ohos'
            $layers = @('oh_modules','.hvigor')
            if ($Import -and [string]$Manifest.toolVersion -like 'Hvigor *') { [array]::Reverse($layers) }
            $layer = Select-JobsSetupChoice $Fzf '选择鸿蒙归档层（单独归档，不能互换）' $layers
            $cache = Join-Path $Project ('ohos/'+$layer)
            $directory = Join-Path $Project 'ohos'
            if ($layer -ceq '.hvigor') {
                $tool = $null
                foreach ($name in @('hvigorw.bat','hvigorw.cmd','hvigorw')) { $candidate = Join-Path $directory $name; if ([IO.File]::Exists($candidate)) { $tool = $candidate; break } }
                if (-not $tool) { throw '缺少工程 Hvigor wrapper，无法确认归档工具版本。' }
                $probe = Invoke-JobsSetupProcess $tool @('--version') $directory 60
                $label = 'Hvigor'
            } else {
                $candidates = @('ohpm.cmd','ohpm')
                foreach ($homePath in @($env:TOOL_HOME,$env:DEVECO_STUDIO_HOME)) {
                    if ($homePath) { foreach ($relative in @('tools/ohpm/bin/ohpm.bat','ohpm/bin/ohpm.bat')) { $candidates += Join-Path $homePath $relative } }
                }
                $tool = Find-JobsExecutable 'ohpm.bat' $candidates
                if (-not $tool) { throw '缺少现有 ohpm，请使用匹配工程的 DevEco 工具环境。' }
                $probe = Invoke-JobsSetupProcess $tool @('--version') $directory 30
                $label = 'OHPM'
            }
            if (($probe.StdOut+$probe.StdErr) -notmatch '(?i)(?:^|\s)v?(\d+\.\d+(?:\.[0-9A-Za-z+._-]+)?)') { throw '无法读取鸿蒙缓存层的真实工具版本。' }
            $version = $label+' '+$Matches[1]
        }
        native {
            if (-not $Import) { $platform = (Select-JobsSetupChoice $Fzf '选择当前工程的构建目标（仅打包该目标目录）' (Get-JobsDependencyPlatforms $Project)).ToLowerInvariant() }
            if ($platform -cnotin @('android','windows','web','ohos')) { throw '当前宿主不能处理此 native 平台。' }
            $name = if ($platform -ceq 'android') { 'app' } else { $platform }
            $cache = Join-Path $Project ('build/'+$name)
            $flutter = Get-JobsArchiveFlutter $Project
            $version = 'Flutter '+$flutter.FrameworkVersion+' arch '+$flutter.Architecture
        }
        precache {
            $flutter = Get-JobsArchiveFlutter $Project
            if (-not $Import) { $platform = (Select-JobsSetupChoice $Fzf '选择本次 SDK 产物使用的平台' (Get-JobsDependencyPlatforms $Project)).ToLowerInvariant() }
            if ($platform -cnotin @('android','windows','web','ohos')) { throw '当前宿主不导入此平台 SDK 产物。' }
            $cache = Join-Path $flutter.Root 'bin/cache'
            $version = 'Flutter '+$flutter.FrameworkVersion+' artifacts arch '+$flutter.Architecture
        }
        web {
            $platform = 'web'
            $scopes = @(@($Project,(Join-Path $Project 'web')) | Where-Object { [IO.File]::Exists((Join-Path $_ 'package.json')) })
            if (-not $scopes.Count) { throw 'JS 归档不适用：工程没有 package.json。' }
            if ($Import) {
                $scope = if ([string]$Manifest.toolVersion -like '* scope web') { Join-Path $Project 'web' } else { $Project }
                if ($scope -cnotin $scopes) { throw '目标缺少快照所需的 JS 工程清单。' }
            } elseif ($scopes.Count -eq 1) { $scope = $scopes[0] }
            else { $scope = Select-JobsSetupChoice $Fzf '选择 JS 清单所在目录' $scopes }
            $cache = Join-Path $scope 'node_modules'
            $node = Find-JobsExecutable 'node.exe' @('node')
            if (-not $node) { throw '缺少现有 Node，无法确认 node_modules 的运行时兼容性。' }
            $probe = Invoke-JobsSetupProcess $node @('--version') $scope 30
            if (($probe.StdOut+$probe.StdErr).Trim() -notmatch '^v?(\d+\.\d+\.\d+)$') { throw 'Node 版本输出无效。' }
            $nodeVersion = $Matches[1]
            $architecture = Invoke-JobsSetupProcess $node @('-p','process.arch') $scope 30
            $nodeArchitecture = ($architecture.StdOut+$architecture.StdErr).Trim()
            if ($nodeArchitecture -cnotmatch '^[a-zA-Z0-9_-]+$') { throw 'Node 未返回有效运行时架构。' }
            $scopeName = if ($scope -ceq $Project) { 'root' } else { 'web' }
            $version = 'Node '+$nodeVersion+' arch '+$nodeArchitecture+' scope '+$scopeName
        }
    }
    if ($Import) {
        # 目标由本次环境计算并明确显示，不能沿用快照内的开发机绝对路径。
        $cache = Read-JobsArchiveDirectory ('导入目标根目录（空回车使用 '+$cache+'）') $cache -MayBeMissing
    } else {
        $cache = Read-JobsArchiveDirectory ('导出源根目录（空回车使用 '+$cache+'；可输入同类型缓存根）') $cache
    }
    Assert-JobsArchiveRoot $Project $Kind $platform $cache $layer
    return [pscustomobject]@{Root=$cache;Platform=$platform;ToolVersion=$version}
}

function Invoke-JobsProjectDependencyArchiveAction {
    param([string]$Target,[string]$Action,[switch]$Check)
    if ($Action -cnotmatch '^(export|import)-(gradle|ohos|native|precache|web)-dependencies$') { throw '未知原生依赖归档动作。' }
    $operation = $Matches[1]; $kind = $Matches[2]
    $project = Resolve-JobsTarget $Target
    Assert-JobsSetupDirectory $project
    $identity = Import-Module (Join-Path $PSScriptRoot 'Actions/sdk-manage/Scripts/Action.psm1') -PassThru -DisableNameChecking
    & $identity { param($p) Assert-JobsFlutterProject $p } $project
    if ($Check) {
        Write-Host ('只读归档计划：'+$operation+' / '+$kind+'；工程：'+$project)
        Write-Host '实际运行会选择缓存根和快照目录，核对宿主/目标/工具版本/锁指纹及全部校验；当前未运行工具、联网、复制或写文件。'
        return
    }
    Write-Host ('原生依赖归档：'+$operation+' / '+$kind) -ForegroundColor Red
    Write-Host '只复制所选层；Gradle modules-2 可能含其它工程的共享包，OHPM/Hvigor分开，native是本机目标构建缓存，precache仅含平台资源白名单及配对stamp，不含SDK源码/Dart/tools，JS不执行归档脚本。'
    Write-Host '仅相同宿主、目标、工具版本与工程锁指纹允许导入；同名不同内容拒绝，导入前精确YES。不保证跨系统或完全离线；分享前检查缓存中的私有内容。'
    if (-not (Test-JobsSetupInteractive)) { throw '需要真实交互终端。' }
    if ((Read-JobsEnterChoiceHost '回车继续；任意非空输入取消') -ne '') { throw '已取消，未复制归档。' }
    if ($operation -ceq 'export') {
        Write-JobsEnterChoiceText '🔐 当前原生缓存层不能按来源可靠区分私库；直接回车改用一键私库提取，非空才完整提取本层。' -ForegroundColor Yellow
        $scopeAnswer = Read-JobsEnterChoiceHost '直接回车 = 一键私库提取；任意字符（含空格）再回车 = 完整提取本层'
        if ($null -eq $scopeAnswer) { return }
        if ($scopeAnswer.Length -eq 0) {
            $migration = Import-Module (Join-Path $PSScriptRoot 'FlutterDependencyMigration.psm1/FlutterDependencyMigration.psm1') -PassThru -DisableNameChecking
            & $migration { param($p) Invoke-JobsFlutterMigration -Project $p -Action export-all-dependencies -PrivateOnly } $project
            return
        }
    }
    $saved = Get-JobsSetupEnvironmentSnapshot @('PATH','JAVA_HOME','TOOL_HOME','DEVECO_SDK_HOME','NO_COLOR','FORCE_COLOR','CLICOLOR','ANSI_COLORS_DISABLED','npm_config_color')
    try {
        $logs = Join-Path (Get-JobsInstallRoot) 'logs'
        [void][IO.Directory]::CreateDirectory($logs)
        $script:SetupLog = Join-Path $logs ('native-archive-'+[guid]::NewGuid().ToString('N')+'.log')
        Write-JobsSetupMessage ('归档审计日志：'+$script:SetupLog)
        $fzf = Get-JobsSetupFzf $project
        $manifest = $null
        if ($operation -ceq 'import') {
            $directory = Read-JobsArchiveDirectory '输入或拖入完整原生依赖快照目录（含 manifest.json 与 payload）'
            $file = Join-Path $directory 'manifest.json'; Assert-JobsSetupFile $file
            $manifest = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($manifest.format -cne 'JobsNativeDependencyArchive' -or ($manifest.formatVersion -ne 1 -and -not ($manifest.formatVersion -eq 2 -and $kind -ceq 'precache')) -or $manifest.kind -cne $kind) { throw '快照格式/类型不匹配。' }
        } else {
            $desktop = [Environment]::GetFolderPath('DesktopDirectory')
            $directory = Read-JobsArchiveDirectory '导出父目录（空回车使用系统桌面）' $desktop
        }
        $plan = Get-JobsArchiveCachePlan $project $kind $fzf $manifest -Import:($operation -ceq 'import')
        $dart = Get-JobsArchiveDart $project
        $engine = Join-Path $PSScriptRoot 'NativeDependencyArchive.dart'
        Assert-JobsSetupFile $engine
        if (-not [IO.File]::Exists($engine)) { throw '归档引擎缺失，请取得完整发布包。' }
        $arguments = @($engine,$operation,'--project',$project,'--kind',$kind,'--directory',$directory,'--platform',$plan.Platform,'--tool-version',$plan.ToolVersion)
        if ($kind -ceq 'precache') { $arguments += '--flutter-cache' }
        $arguments += if ($operation -ceq 'import') { @('--target-root',$plan.Root) } else { @('--source-root',$plan.Root) }
        Write-JobsSetupMessage ('缓存层：'+$kind+'；根：'+$plan.Root+'；快照目录：'+$directory+'；版本：'+$plan.ToolVersion)
        # 引擎预检校验全部证据后才确认写入；实际执行仍会重新校验以防等待期间变化。
        $preflight = Invoke-JobsSetupProcess $dart ($arguments+@('--check')) $project 1800
        $proof = $preflight.StdOut | ConvertFrom-Json
        if ($proof.kind -cne $kind) { throw '归档预检未确认本类型。' }
        if ($operation -ceq 'import') {
            if ((Read-Host '输入精确大写 YES 导入；其它输入取消') -cne 'YES') { throw '已取消，未导入缓存。' }
            $arguments += @('--confirm','YES')
        } elseif ((Read-JobsEnterChoiceHost '预检已通过，回车导出；任意非空输入取消') -ne '') { throw '已取消，未导出缓存。' }
        [void](Invoke-JobsSetupProcess $dart $arguments $project 3600)
        Write-JobsSetupMessage '所选缓存层归档操作已完成；没有安装依赖或启动应用。'
    } finally {
        Restore-JobsSetupEnvironment $saved
        Remove-Variable SetupLog -Scope Script -ErrorAction SilentlyContinue
    }
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

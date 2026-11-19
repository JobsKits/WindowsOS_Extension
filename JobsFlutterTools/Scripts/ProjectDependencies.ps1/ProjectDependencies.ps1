# ProjectDependencies.ps1 | 随 ProjectSetup 加载的分层依赖准备内核。
# Created by Jobs on 2026年10月29日，星期四.
# 只处理所选工程及工具缓存；保留工程版本、认证和仓库配置，不启动应用。

# 只列当前 Windows 宿主可处理、且工程真实存在的平台。

# Jobs enter-choice emphasis is display-only; input and business decisions stay with callers.

# JOBS_SOURCE_LAYOUT_ROOT_V1：只解析本文件逻辑目录，发布 flat 副本保持原资源基准。
$script:JobsLayoutProjectDependenciesRoot = $(if ([IO.Path]::GetFileName($PSScriptRoot) -ceq 'ProjectDependencies.ps1') { Split-Path -Parent $PSScriptRoot } else { $PSScriptRoot })

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
    param([Collections.IDictionary]$Capabilities = $null)
    if ($null -eq $Capabilities) {
        try {
            $environment = [Environment]::GetEnvironmentVariables('Process')
            $Capabilities = @{ HostName = $Host.Name; InputRedirected = [Console]::IsInputRedirected; OutputRedirected = [Console]::IsOutputRedirected;
                               ErrorRedirected = [Console]::IsErrorRedirected; NoColorPresent = $environment.Contains('NO_COLOR');
                               PlainOutput = $env:PLAIN_OUTPUT; Term = $env:TERM; Windows = ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT); VirtualTerminal = $false; SourceTree = ($env:IS_SOURCETREE_RUNTIME -eq '1') }
            if ($null -ne $Host.UI.PSObject.Properties['SupportsVirtualTerminal']) { $Capabilities.VirtualTerminal = $Host.UI.SupportsVirtualTerminal }
            foreach ($key in $environment.Keys) { if ([string]$key -match '^(?i:SOURCE_?TREE)') { $Capabilities.SourceTree = $true; break } }
        } catch { return $false }
    }
    return ($Capabilities.HostName -eq 'ConsoleHost' -and -not $Capabilities.InputRedirected -and -not $Capabilities.OutputRedirected -and
            -not $Capabilities.ErrorRedirected -and -not $Capabilities.NoColorPresent -and $Capabilities.PlainOutput -ne '1' -and
            $Capabilities.Term -ine 'dumb' -and (-not [string]::IsNullOrEmpty($Capabilities.Term) -or ($Capabilities.Contains('Windows') -and $Capabilities.Windows)) -and -not $Capabilities.SourceTree -and $Capabilities.VirtualTerminal)
}
# Older hosts keep native colors without sending unsupported bold escape sequences.
function Test-JobsEnterChoiceBold {
    $property = $Host.UI.PSObject.Properties['SupportsVirtualTerminal']
    return ($null -ne $property -and [bool]$property.Value)
}
# Separate ordinary question text from Enter and arbitrary-input options without changing words.
function Get-JobsEnterChoiceParts {
    param([string]$Text)
    $red = '(?:(?:\u8f93\u5165)?(?:\u4efb\u610f(?:\u975e\u7a7a)?(?:\u5b57\u7b26|\u5185\u5bb9|\u6587\u5b57|\u8f93\u5165)?|\u975e\u7a7a(?:\u8f93\u5165|\u5b57\u7b26|\u5185\u5bb9)?|(?:\u5176\u5b83|\u5176\u4ed6)(?:\u975e\u7a7a)?(?:\u8f93\u5165|\u5185\u5bb9|\u5b57\u7b26)?))|(?:any\s+(?:(?:other|non[- ]empty)\s+)?(?:input|text|characters?)|non[- ]empty\s+input)|(?:type\s+(?:anything|any\s+(?:characters?|text|input)))'
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
# 仅在真实询问中突出主体和各类操作选项。
function Get-JobsQuestionChoiceParts {
    param([string]$Text)
    $plain = [regex]::Replace($Text, '\x1b\[[0-9;]*m', '')
    $questionBody = $true
    foreach ($part in @(Get-JobsEnterChoiceParts $plain)) {
        $isOption = $part.Color -eq 'Red' -or $part.Color -eq 'Green'
        foreach ($token in [regex]::Matches($part.Text, '[^；;/|，,、？?：:=＝（）()\[\]【】\r\n]+|[；;/|，,、？?：:=＝（）()\[\]【】\r\n]')) {
            $value = $token.Value
            $separator = $value -match '^[；;/|，,、？?：:=＝（）()\[\]【】\r\n]$'
            $color = ''
            if (-not $separator -and -not [string]::IsNullOrWhiteSpace($value)) {
                if ($isOption) { $color = $part.Color }
                elseif ($questionBody) { $color = 'Cyan' }
            }
            [pscustomobject]@{ Text = $value; Color = $color }
        }
        if ($isOption) { $questionBody = $false }
    }
}
# 识别展示地址边界，保留查询、编码与配对括号。
function Get-JobsUrlRanges {
    param([string]$Text)
    $pattern = '[A-Za-z][A-Za-z0-9+.-]*://[^\s<>"''\x1b]+'
    $punctuation = '，。；：！？、（）【】《》「」『』“”‘’'
    $offset = 0
    while ($offset -lt $Text.Length) {
        $match = [regex]::Match($Text.Substring($offset), $pattern)
        if (-not $match.Success) { break }
        $start = $offset + $match.Index
        $url = $match.Value
        foreach ($mark in $punctuation.ToCharArray()) {
            $at = $url.IndexOf($mark)
            if ($at -ge 0) { $url = $url.Substring(0, $at) }
        }
        while ($url.Length) {
            $last = $url.Substring($url.Length - 1, 1)
            $unmatched = $false
            foreach ($pair in @(@('(', ')'), @('[', ']'), @('{', '}'))) {
                if ($last -eq $pair[1] -and ([regex]::Matches($url, [regex]::Escape($pair[1]))).Count -gt ([regex]::Matches($url, [regex]::Escape($pair[0]))).Count) { $unmatched = $true }
            }
            if ('. , ; : ! ?'.Split(' ') -contains $last -or $unmatched) { $url = $url.Substring(0, $url.Length - 1) }
            else { break }
        }
        [pscustomobject]@{ Start = $start; End = $start + $url.Length }
        $offset = $start + $url.Length
    }
}
# 暂时遮蔽URL，避免询问分段误识别地址内的Enter。
function Protect-JobsDisplayUrls {
    param([string]$Text)
    $builder = New-Object Text.StringBuilder
    $tokens = New-Object 'Collections.Generic.List[object]'
    $offset = 0; $number = 0
    foreach ($range in @(Get-JobsUrlRanges $Text)) {
        do { $number++; $token = [string][char]2 + 'U' + $number + [char]3 } while ($Text.Contains($token))
        [void]$builder.Append($Text.Substring($offset, $range.Start - $offset)).Append($token)
        $tokens.Add([pscustomobject]@{ Token = $token; Text = $Text.Substring($range.Start, $range.End - $range.Start) })
        $offset = $range.End
    }
    [void]$builder.Append($Text.Substring($offset))
    [pscustomobject]@{ Text = $builder.ToString(); Tokens = $tokens.ToArray() }
}
# 给可见地址标绿下划线，并恢复原SGR上下文。
function Format-JobsUrlText {
    param([AllowEmptyString()][string]$Text, [switch]$Color)
    $control = '\x1b\][^\x1b\x07]*(?:\x07|\x1b\\)|\x1b\[[0-?]*[ -/]*[@-~]'
    $sgr = '\x1b\[[0-9;:]*m'
    $value = [regex]::Replace($Text, $control, {
        param($match)
        if ($Color -and $match.Value -match ('^' + $sgr + '$')) { return $match.Value }
        return ''
    })
    if (-not $Color) { return $value }
    $styles = @{}; $visible = New-Object Text.StringBuilder; $offset = 0
    foreach ($match in [regex]::Matches($value, $sgr)) {
        [void]$visible.Append($value.Substring($offset, $match.Index - $offset))
        $index = $visible.Length
        if (-not $styles.ContainsKey($index)) { $styles[$index] = '' }
        $styles[$index] += $match.Value
        $offset = $match.Index + $match.Length
    }
    [void]$visible.Append($value.Substring($offset))
    $plain = $visible.ToString(); $starts = @{}; $ends = @{}
    foreach ($range in @(Get-JobsUrlRanges $plain)) { $starts[$range.Start] = $true; $ends[$range.End - 1] = $true }
    $escape = [string][char]27; $active = ''; $inUrl = $false; $output = New-Object Text.StringBuilder
    for ($index = 0; $index -le $plain.Length; $index++) {
        if ($styles.ContainsKey($index)) {
            $tokens = $styles[$index]; [void]$output.Append($tokens)
            foreach ($match in [regex]::Matches($tokens, $sgr)) {
                $token = $match.Value; $code = $token.Substring(2, $token.Length - 3)
                $fields = $code.Split(';'); $reset = $code -eq ''
                for ($item = 0; $item -lt $fields.Count; $item++) {
                    if ($fields[$item] -eq '0') { $reset = $true }
                    if (@('38', '48', '58') -contains $fields[$item] -and $item + 1 -lt $fields.Count) {
                        if ($fields[$item + 1] -eq '2') { $item += 4 }
                        elseif ($fields[$item + 1] -eq '5') { $item += 2 }
                    }
                }
                if ($reset) { $active = '' }
                $active += $token
            }
            if ($inUrl) { [void]$output.Append($escape + '[32;4m') }
        }
        if ($index -eq $plain.Length) { break }
        if ($starts.ContainsKey($index)) { [void]$output.Append($escape + '[32;4m'); $inUrl = $true }
        [void]$output.Append($plain[$index])
        if ($ends.ContainsKey($index)) { [void]$output.Append($escape + '[0m' + $active); $inUrl = $false }
    }
    return $output.ToString()
}
# 按现行询问规则合成展示字符串，保持输入原文。
function Format-JobsDisplayText {
    param([AllowEmptyString()][string]$Text, [switch]$Question, [switch]$Color, [string]$BaseStyle = '')
    if (-not $Color) { return (Format-JobsUrlText $Text) }
    $plain = Format-JobsUrlText $Text
    $protected = Protect-JobsDisplayUrls $plain
    $parts = if ($Question) { @(Get-JobsQuestionChoiceParts $protected.Text) } else { @(Get-JobsEnterChoiceParts $protected.Text) }
    $escape = [string][char]27
    if (-not $Question -and @($parts | Where-Object { $_.Color }).Count -eq 0) {
        $result = Format-JobsUrlText ($BaseStyle + $Text) -Color
    } else {
        $output = New-Object Text.StringBuilder
        foreach ($part in $parts) {
            $code = switch ($part.Color) { 'Red' { 31 } 'Green' { 32 } 'Cyan' { 36 } default { 0 } }
            if ($code) { [void]$output.Append($escape + '[1;' + $code + 'm' + $part.Text + $escape + '[0m' + $BaseStyle) }
            else { [void]$output.Append($BaseStyle + $part.Text) }
        }
        $formatted = $output.ToString()
        foreach ($item in $protected.Tokens) { $formatted = $formatted.Replace($item.Token, $item.Text) }
        $result = Format-JobsUrlText $formatted -Color
    }
    if ($BaseStyle) { $result += $escape + '[0m' }
    return $result
}
# 按调用者明确指定的ConsoleColor计算临时展示色。
function Get-JobsDisplayBaseStyle {
    param([Collections.IDictionary]$Parameters)
    $codes = @{ Black=30; DarkBlue=34; DarkGreen=32; DarkCyan=36; DarkRed=31; DarkMagenta=35; DarkYellow=33; Gray=37; DarkGray=90; Blue=94; Green=92; Cyan=96; Red=91; Magenta=95; Yellow=93; White=97 }
    $style = ''; $escape = [string][char]27
    if ($Parameters.ContainsKey('ForegroundColor')) { $style += $escape + '[' + $codes[[string]$Parameters.ForegroundColor] + 'm' }
    if ($Parameters.ContainsKey('BackgroundColor')) { $style += $escape + '[' + ($codes[[string]$Parameters.BackgroundColor] + 10) + 'm' }
    return $style
}
function Write-JobsEnterChoiceText {
    [CmdletBinding()]
    param([Parameter(Position=0)][AllowNull()][object]$Object, [switch]$NoNewline, [ConsoleColor]$ForegroundColor, [ConsoleColor]$BackgroundColor, [object]$Separator = ' ', [switch]$Question)
    $text = if ($Object -is [array]) { $Object -join [string]$Separator } else { [string]$Object }
    $plain = Format-JobsUrlText $text
    if (-not (Test-JobsEnterChoiceColor)) { Write-Host $plain -NoNewline:$NoNewline; return }
    $baseStyle = Get-JobsDisplayBaseStyle $PSBoundParameters
    $rendered = Format-JobsDisplayText $text -Question:$Question -Color -BaseStyle $baseStyle
    $message = New-Object Management.Automation.HostInformationMessage
    $message.Message = $plain
    $message.NoNewLine = [bool]$NoNewline
    if ($PSBoundParameters.ContainsKey('ForegroundColor')) { $message.ForegroundColor = $ForegroundColor }
    if ($PSBoundParameters.ContainsKey('BackgroundColor')) { $message.BackgroundColor = $BackgroundColor }
    Write-Information -MessageData $message -Tags 'JobsDisplay' -InformationAction SilentlyContinue
    [Console]::Write($rendered)
    if (-not $NoNewline) { [Console]::WriteLine() }
}
# Delegate the original reader, including secure input and EOF behavior, after prompt display.
function Read-JobsEnterChoiceHost {
    [CmdletBinding()]
    param([Parameter(Position=0)][string]$Prompt, [switch]$AsSecureString, [switch]$MaskInput)
    if (-not (Test-JobsEnterChoiceColor)) {
        $plainArguments = @{}
        foreach ($key in $PSBoundParameters.Keys) { $plainArguments[$key] = $PSBoundParameters[$key] }
        if ($plainArguments.ContainsKey('Prompt')) { $plainArguments.Prompt = Format-JobsUrlText $Prompt }
        return (Read-Host @plainArguments)
    }
    Write-JobsEnterChoiceText ($Prompt + ': ') -NoNewline -Question
    $readerArguments = @{}
    foreach ($key in $PSBoundParameters.Keys) {
        if ($key -ne 'Prompt') { $readerArguments[$key] = $PSBoundParameters[$key] }
    }
    return (Read-Host @readerArguments)
}

function Get-JobsDependencyPlatforms {
    param([string]$Project)
    return @(@('Android','Windows','Web','Ohos') | Where-Object { [IO.Directory]::Exists((Join-Path $Project $_.ToLowerInvariant())) })
}

# 记录只用于本机的显式系统选择；没有记录时仅认工程自身 FVM，不借用 PATH Flutter。
function Get-JobsDependencyFlutter {
    param([string]$Project, [string]$Fzf, [switch]$Ohos)
    $modern = Join-Path $Project '.fvmrc'
    $legacy = Join-Path $Project '.fvm/fvm_config.json'
    $failure = ''
    $pin = ''
    try {
        if ([IO.File]::Exists($modern) -or [IO.File]::Exists($legacy)) {
            $configPath = if ([IO.File]::Exists($modern)) { $modern } else { $legacy }
            Assert-JobsSetupFile $configPath
            $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $pin = if ($config.PSObject.Properties['flutter']) { $config.flutter } elseif ($config.PSObject.Properties['flutterSdkVersion']) { $config.flutterSdkVersion } else { $null }
            if ($pin -isnot [string] -or [string]::IsNullOrWhiteSpace($pin)) { throw 'FVM 版本声明无效。' }
            return Get-JobsSetupFlutter (Join-Path $Project '.fvm/flutter_sdk/bin/flutter.bat') $Project 'fvm'
        }
        $profile = Get-JobsSetupProfile $Project
        if ($profile -and $profile.FlutterMode -ceq 'system') { return Get-JobsSetupFlutter $profile.FlutterPath $Project 'system' }
        throw '目标工程没有已确认的 Flutter SDK 绑定。'
    } catch { $failure = $_.Exception.Message }
    Write-JobsSetupMessage ('项目 SDK 尚未就绪：' + $failure + '；进入现有安装/切换流程，成功后复检。')
if ($Ohos -or $pin -cmatch '^custom_jobs_ohos_') {
    $manager = Import-Module (Join-Path ${script:JobsLayoutProjectDependenciesRoot} 'HarmonySdk.psm1') -PassThru -DisableNameChecking
    & $manager { param($p) Invoke-JobsHarmonySdkAction -Target $p -RequireCompletion } $Project
} else {
    $manager = Import-Module (Join-Path ${script:JobsLayoutProjectDependenciesRoot} 'Actions/sdk-manage/Scripts/Action.psm1') -PassThru -DisableNameChecking
    & $manager { param($p) Invoke-JobsFlutterVersionAction -Directory $p -RequireCompletion } $Project
}
    # 管理器返回成功也必须重新读取真实声明和运行链，不能依赖旧对象。
    $configPath = if ([IO.File]::Exists($modern)) { $modern } else { $legacy }
    Assert-JobsSetupFile $configPath
    if (-not [IO.File]::Exists($configPath)) { throw 'SDK 准备后没有项目 FVM 声明，未继续。' }
    return Get-JobsSetupFlutter (Join-Path $Project '.fvm/flutter_sdk/bin/flutter.bat') $Project 'fvm'
}

# Java 沿本机已确认记录或工程声明复用；不健康才进入既有选择器。
function Get-JobsDependencyJava {
    param([string]$Project, [string]$Fzf)
    $profile = Get-JobsSetupProfile $Project
    if ($profile -and $profile.JavaMode -cin @('jenv','system')) {
        try { $java = Get-JobsSetupJava $profile.JavaHome $Project; $java | Add-Member Mode $profile.JavaMode; return $java }
        catch { Write-JobsSetupMessage ('已记录 JDK 不可用：' + $_.Exception.Message) }
    }
    $file = Join-Path $Project '.jobs/java-environment.json'
    if ([IO.File]::Exists($file)) {
        Assert-JobsSetupFile $file
        $saved = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($saved.Platform -ceq 'Windows' -and $saved.JavaMode -cin @('system','jenv')) {
            try { $java = Get-JobsSetupJava $saved.JavaHome $Project; $java | Add-Member Mode $saved.JavaMode; return $java }
            catch { Write-JobsSetupMessage ('已记录 Java 选择不可用：' + $_.Exception.Message) }
        }
    }
    return Select-JobsSetupJava $Project $Fzf
}

# 临时 Gradle task 强制请求真实文件，不能用 dependencies/help 的图或成功文字代替下载。
function New-JobsDependencyGradleInit {
    param([string]$Directory)
    $file = Join-Path $Directory 'jobs-resolve-artifacts.gradle'
    $source = @'
gradle.projectsEvaluated {
    def root = gradle.rootProject
    if (root.tasks.findByName('jobsResolveDependencyArtifacts') != null) {
        throw new GradleException('jobsResolveDependencyArtifacts task name already exists; refusing to replace it')
    }
    root.tasks.create('jobsResolveDependencyArtifacts') {
        doLast {
            int resolved = 0
            root.allprojects.each { project ->
                [project.buildscript.configurations, project.configurations].each { configurations ->
                    configurations.findAll { it.canBeResolved }.each { configuration ->
                        println('JOBS_RESOLVE|' + project.path + '|' + configuration.name)
                        configuration.resolve().each { artifact ->
                            if (!artifact.exists()) {
                                throw new GradleException('Resolved artifact is missing: ' + artifact)
                            }
                        }
                        resolved++
                    }
                }
            }
            if (resolved == 0) { throw new GradleException('No resolvable Gradle configurations were found') }
            println('JOBS_ARTIFACTS_RESOLVED|' + resolved)
        }
    }
}
'@
    [IO.File]::WriteAllText($file, $source, (New-Object Text.UTF8Encoding($false)))
    return $file
}

function Invoke-JobsDependencyAndroid {
    param([string]$Project, $Flutter, $Java, [string]$Fzf, [string]$Gradle)
    if (-not [IO.Directory]::Exists((Join-Path $Project 'android'))) { throw '工程没有 Android 平台。' }
    Set-JobsSetupLocalProperty $Project 'flutter.sdk' $Flutter.Root
    Set-JobsSetupJavaProcess $Project $Java
    if (-not $Gradle) { $Gradle = Install-JobsSetupGradle $Project $Java $Fzf }
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ('JobsAndroidDependencies-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($temporary)
    try {
        $init = New-JobsDependencyGradleInit $temporary
        Set-JobsSetupProgress deps.plugins running '下载工程全部可解析 Maven 原生库与构建插件'
        $parameters = @('jobsResolveDependencyArtifacts','--no-daemon','--stacktrace','--init-script',$init)
        if ((Get-Variable SetupMavenFallback -Scope Script -ErrorAction SilentlyContinue) -and $script:SetupMavenFallback) { $parameters += @('--init-script',(New-JobsSetupMirrorInit $temporary)) }
        $result = Invoke-JobsSetupProcess $Gradle $parameters (Join-Path $Project 'android') 1800
        if (($result.StdOut + $result.StdErr) -notmatch '(?m)^JOBS_ARTIFACTS_RESOLVED\|[1-9][0-9]*\s*$') { throw 'Gradle 未返回本次真实 artifact 解析完成标记。' }
        Set-JobsSetupProgress deps.plugins done 'Maven 原生库与构建插件已实际解析'
    } finally { if ([IO.Directory]::Exists($temporary)) { [IO.Directory]::Delete($temporary,$true) } }
}

# 使用工程 wrapper 与现有 DevEco 工具；不安装任意最新 npm/Hvigor。
function Invoke-JobsDependencyOhos {
    param([string]$Project)
    $directory = Join-Path $Project 'ohos'
    foreach ($relative in @('oh-package.json5','hvigor/hvigor-config.json5')) {
        $file = Join-Path $directory $relative
        Assert-JobsSetupFile $file
        if (-not [IO.File]::Exists($file)) { throw ('缺少鸿蒙工程声明：' + $file) }
    }
    $tools = Initialize-JobsSetupOhos $Project
    $ohpm = $tools.Ohpm
    $wrapper = $tools.Wrapper
    Set-JobsSetupProgress deps.plugins running 'ohpm 原生库与工程固定 Hvigor 插件同步'
    [void](Invoke-JobsSetupProcess $ohpm @('install') $directory 1800)
    [void](Invoke-JobsSetupProcess $wrapper @('--sync') $directory 1800)
    Set-JobsSetupProgress deps.plugins done 'ohpm 安装与 Hvigor 同步均成功'
}

# 有 JS 清单时才执行；锁文件决定管理器，生命周期脚本与其失败按原样传播。
function Invoke-JobsDependencyWeb {
    param([string]$Project)
    $directories = @(@($Project,(Join-Path $Project 'web')) | Select-Object -Unique | Where-Object { [IO.File]::Exists((Join-Path $_ 'package.json')) })
    if (-not $directories.Count) { Write-JobsSetupMessage 'Web/JS 依赖不适用：工程根和 web/ 均无 package.json；Flutter Web 的 Dart 包仍由 Pub 管理。'; return }
    foreach ($directory in $directories) {
        Assert-JobsSetupFile (Join-Path $directory 'package.json')
        $manifest = Get-Content -LiteralPath (Join-Path $directory 'package.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $locks = @(@('package-lock.json','npm-shrinkwrap.json','pnpm-lock.yaml','yarn.lock') | Where-Object { [IO.File]::Exists((Join-Path $directory $_)) })
        foreach ($name in $locks) { Assert-JobsSetupFile (Join-Path $directory $name) }
        $managers = @($locks | ForEach-Object { if ($_ -in @('package-lock.json','npm-shrinkwrap.json')) { 'npm' } elseif ($_ -eq 'pnpm-lock.yaml') { 'pnpm' } else { 'yarn' } } | Select-Object -Unique)
        if ($managers.Count -ne 1) { throw ('JS 工程必须提供唯一管理器的锁文件（npm/pnpm/yarn），未猜测安装方式：' + $directory) }
        $manager = $managers[0]
        if ($manifest.PSObject.Properties['packageManager'] -and [string]$manifest.packageManager -notmatch ('^' + $manager + '@')) { throw 'packageManager 与锁文件不一致。' }
        $tools = Initialize-JobsSetupWebTools $directory $manifest $manager $Project
        $tool = $tools.Tool
        $version = [pscustomobject]@{StdOut=$tools.Version;StdErr=''}
        $arguments = @('ci')
        if ($manager -ceq 'pnpm') { $arguments = @('install','--frozen-lockfile') }
        elseif ($manager -ceq 'yarn') {
            if (($version.StdOut + $version.StdErr) -notmatch '(?m)^([0-9]+)\.') { throw '无法确认 Yarn 主版本，未猜测命令。' }
            $arguments = if ([int]$Matches[1] -ge 2) { @('install','--immutable') } else { @('install','--frozen-lockfile') }
        }
        Write-JobsSetupMessage ('按工程锁文件安装 JS 依赖；保留生命周期脚本：' + $directory)
        [void](Invoke-JobsSetupProcess $tool $arguments $directory 1800)
    }
}

function Invoke-JobsDependencyPrecache {
    param([string]$Project, $Flutter, [string]$Platform)
    $help = Invoke-JobsSetupProcess $Flutter.Flutter @('precache','--help') $Project 120
    $flag = '--' + $Platform.ToLowerInvariant()
    $capability = '--(?:\[no-\])?' + [regex]::Escape($Platform.ToLowerInvariant()) + '\b'
    if (($help.StdOut + $help.StdErr) -notmatch $capability) { throw ('本 SDK 不支持平台缓存选项：' + $flag) }
    [void](Invoke-JobsSetupProcess $Flutter.Flutter @('precache',$flag) $Project 1800)
}

function Invoke-JobsDependencyNative {
    param([string]$Project, $Flutter, [string]$Fzf, [string]$Platform, [string[]]$BuildArguments)
    if (-not $BuildArguments) { $BuildArguments = Get-JobsSetupRunArguments $Project $Fzf '' $Platform -ForBuild }
    $help = Invoke-JobsSetupProcess $Flutter.Flutter @('build',$BuildArguments[1],'--help') $Project 120
    if (($help.StdOut + $help.StdErr) -notmatch ('(?i)flutter\s+build\s+' + [regex]::Escape($BuildArguments[1]) + '\b')) { throw '此 SDK 未确认支持所选平台构建，未执行原生准备。' }
    Write-JobsSetupMessage '将以所选入口/flavor/define 执行 debug 构建，触发 CMake/NuGet/FFI hooks 与平台库准备；可能编译并生成产物，不安装或启动应用，不保证后续完全离线。'
    Set-JobsSetupProgress deps.native running ('通过实际 debug 构建准备 ' + $Platform + ' 原生产物')
    [void](Invoke-JobsSetupProcess $Flutter.Flutter $BuildArguments $Project 3600)
    Set-JobsSetupProgress deps.native done '所选构建与原生产物准备成功；未启动应用'
    return ,$BuildArguments
}

# 一键配置复用相同内核，并把构建参数交给最终运行，避免两次选择不同入口。
function Invoke-JobsSetupTargetDependencies {
    param([string]$Project, $Flutter, $Java, [string]$Fzf, [string]$Platform, [string]$Gradle)
    if ($Platform -ceq 'Android') { Invoke-JobsDependencyAndroid $Project $Flutter $Java $Fzf $Gradle }
    elseif ($Platform -ceq 'Ohos') { Invoke-JobsDependencyOhos $Project }
    if ($Platform -ceq 'Web') { Invoke-JobsDependencyWeb $Project }
    return Invoke-JobsDependencyNative $Project $Flutter $Fzf $Platform
}

# 两个易混淆入口逐行交代实际层级，正文使用纯文本以兼容 CMD 与非彩色输出。
function Show-JobsDependencyActionDetails {
    param([string]$Action)
    if ($Action -ceq 'flutter-precache') {
        Write-Host '本项：下载Flutter平台资源（flutter precache）'
        Write-Host '  1、调用：使用当前项目 SDK 执行 flutter precache --所选目标。'
        Write-Host '  2、下载对象：当前 Flutter SDK 所选目标的引擎和工具。'
        Write-Host '      Android：引擎二进制，也可能包含 Flutter 自身的 android_maven 制品。'
        Write-Host '      Web：对应的渲染资源与工具。'
        Write-Host '      Apple：例如 iOS Flutter.xcframework 仅 macOS 入口提供；Windows 不提供 iOS 目标。'
        Write-Host '  3、范围：不解析工程全部 Maven / 第三方包，不替代 Pub / Pods 拉取。'
        Write-Host '  4、前提：不等于安装完整 Android SDK 或 Xcode。'
        Write-Host '  5、结果：只准备所选平台的 Flutter SDK 缓存，不编译、安装或启动应用。'
    } elseif ($Action -ceq 'native-dependencies') {
        Write-Host '本项：准备原生库与构建依赖（组合操作）'
        Write-Host '  1、必要前置：先获取当前工程 Pub 依赖，并准备所选目标需要的工具。'
        Write-Host '  2、平台包层：按所选目标处理 Android Maven、OpenHarmony OHPM 或 Web 工程包。'
        Write-Host '  3、构建层：执行所选入口 / flavor / dart-define 对应的 flutter build。'
        Write-Host '      构建会触发对应平台的 CMake、NuGet、FFI hooks 或延迟下载制品。'
        Write-Host '  4、影响：会实际编译并生成产物，不安装或启动应用。'
        Write-Host '  5、范围：只处理本次所选目标，不把所有平台全量都拉取，也不保证后续完全离线。'
    }
}

# 公开只读计划与单项执行，共享同一绑定、取消及进程环境恢复边界。
function Invoke-JobsProjectDependencyAction {
    param([string]$Target, [ValidateSet('pub-get','android-dependencies','ohos-dependencies','native-dependencies','flutter-precache','web-dependencies')][string]$Action, [switch]$Check)
    $project = Resolve-JobsTarget $Target
    Assert-JobsSetupDirectory $project
    $identity = Import-Module (Join-Path ${script:JobsLayoutProjectDependenciesRoot} 'Actions/sdk-manage/Scripts/Action.psm1') -PassThru -DisableNameChecking
    & $identity { param($p) Assert-JobsFlutterProject $p } $project
    $platforms = @(Get-JobsDependencyPlatforms $project)
    if ($Check) {
        Write-Host ('只读计划：' + $Action + '；工程：' + $project + '；Windows可处理已有平台：' + ($platforms -join ', '))
        Write-Host '未运行工具、联网、安装、写日志或修改工程。Apple 平台须 macOS，Linux 须 Linux 宿主。'
        return
    }
    if ($Action -cin @('flutter-precache','native-dependencies') -and
        ((Get-JobsSetupEnvironmentSnapshot @('NO_COLOR'))['NO_COLOR'].Exists -or [Console]::IsOutputRedirected)) {
        Write-Host ('Flutter 分层依赖准备：' + $Action)
    } else {
        Write-Host ('Flutter 分层依赖准备：' + $Action) -ForegroundColor Red
    }
    if ($Action -cin @('flutter-precache','native-dependencies')) {
        Show-JobsDependencyActionDetails $Action
        Write-Host '  SDK 前提：缺少可用绑定时进入现有安装/切换，复检成功后继续；保留工程版本、认证、仓库和全局代理。'
    } else {
        Write-Host '仅处理当前工程及工具缓存；可下载/执行锁定依赖的生命周期脚本或原生构建钩子，native 可能编译但不启动应用。缺少 SDK 时进入现有安装/切换。保留版本、认证、仓库和全局代理。'
    }
    Write-Host 'Esc/Ctrl+C 取消；取消只停止后续，保留已完成的安装或缓存。Apple/Linux 平台需对应宿主，本动作不保证完全离线。'
    if (-not (Test-JobsSetupInteractive)) { throw '需要真实交互终端。' }
    if ((Read-JobsEnterChoiceHost '回车继续；任意非空输入取消') -ne '') { throw '已取消，未执行依赖操作。' }
    if ($Action -eq 'web-dependencies' -and -not @(@($project,(Join-Path $project 'web')) | Where-Object { [IO.File]::Exists((Join-Path $_ 'package.json')) }).Count) { Invoke-JobsDependencyWeb $project; return }
    if ($Action -eq 'android-dependencies' -and 'Android' -cnotin $platforms) { throw '工程没有 Android 平台。' }
    if ($Action -eq 'ohos-dependencies' -and 'Ohos' -cnotin $platforms) { throw '工程没有 ohos 平台。' }
    $saved = Get-JobsSetupEnvironmentSnapshot @('JAVA_HOME','PATH','GRADLE_OPTS','ANDROID_HOME','ANDROID_SDK_ROOT','TOOL_HOME','DEVECO_STUDIO_HOME','DEVECO_SDK_HOME','NO_COLOR','FORCE_COLOR','CLICOLOR','ANSI_COLORS_DISABLED','npm_config_color')
    try {
        $logs = Join-Path (Get-JobsInstallRoot) 'logs'; [void][IO.Directory]::CreateDirectory($logs)
        $script:SetupLog = Join-Path $logs ('dependencies-' + [guid]::NewGuid().ToString('N') + '.log')
        Write-JobsSetupMessage ('工程：' + $project + '；动作：' + $Action + '；日志：' + $script:SetupLog)
        $fzf = $null
        if ($Action -notin @('pub-get','web-dependencies','ohos-dependencies')) { $fzf = Get-JobsSetupFzf $project }
        if ($Action -eq 'web-dependencies') { Invoke-JobsDependencyWeb $project; return }
        if ($Action -eq 'pub-get') { $flutter = Get-JobsDependencyFlutter $project $fzf; [void](Invoke-JobsSetupProcess $flutter.Flutter @('pub','get') $project 900); return }
        $platform = switch ($Action) { 'android-dependencies' { 'Android' } 'ohos-dependencies' { 'Ohos' } default { Select-JobsSetupChoice $fzf '选择工程已有的目标平台' $platforms } }
        $flutter = Get-JobsDependencyFlutter $project $fzf -Ohos:($platform -ceq 'Ohos')
        if ($Action -eq 'flutter-precache') { Invoke-JobsDependencyPrecache $project $flutter $platform; return }
        $java = $null
        if ($platform -ceq 'Android') {
            $java = Get-JobsDependencyJava $project $fzf
            Set-JobsSetupJavaProcess $project $java
            Initialize-JobsSetupAndroid $project $flutter $java $fzf
        } elseif ($platform -ceq 'Windows' -and $Action -eq 'native-dependencies') { Initialize-JobsSetupWindowsDesktop $project $fzf }
        [void](Invoke-JobsSetupProcess $flutter.Flutter @('pub','get') $project 900)
        switch ($Action) {
            'android-dependencies' { Invoke-JobsDependencyAndroid $project $flutter $java $fzf }
            'ohos-dependencies' { Invoke-JobsDependencyOhos $project }
            'native-dependencies' {
                if ($platform -ceq 'Android') { Invoke-JobsDependencyAndroid $project $flutter $java $fzf }
                elseif ($platform -ceq 'Ohos') { Invoke-JobsDependencyOhos $project }
                elseif ($platform -ceq 'Web') { Invoke-JobsDependencyWeb $project }
                Invoke-JobsDependencyPrecache $project $flutter $platform
                [void](Invoke-JobsDependencyNative $project $flutter $fzf $platform)
            }
        }
        Write-JobsSetupMessage '所选依赖阶段已完成；其它平台与应用运行未作保证。'
    } finally {
        Restore-JobsSetupEnvironment $saved
        Remove-Variable SetupLog -Scope Script -ErrorAction SilentlyContinue
    }
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

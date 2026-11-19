# FileContentViewer.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年10月27日，星期二.
# 临时文件和隔离终端输出，不安装、不注册，不读取用户业务文件。

# JOBS_SOURCE_LAYOUT_ROOT_V1：只解析本文件逻辑目录，发布 flat 副本保持原资源基准。

# 源包装与已发布 flat 布局共用路径，兼容旧收据且不跟随包装目录链接。
function Resolve-JobsScriptLayoutPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    if ([IO.Path]::GetExtension($Path) -notin @('.ps1','.cmd','.vbs')) { return $Path }
    if (Test-Path -LiteralPath $Path -PathType Container) {
        $directory = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ('脚本包装不能是链接：' + $Path) }
        return Join-Path $Path $directory.Name
    }
    return $Path
}
# 仅新源码包装压平到原发布名称；原有 SDK 资源包与 README 布局保持原意。
function Convert-JobsReleaseLayoutRelativePath {
    param([string]$Package, [string]$Relative)
    $parts = @($Relative -split '[\\/]')
    if ($parts.Count -lt 2) { return $Relative }
    $last = $parts[$parts.Count - 1]
    $parent = $parts[$parts.Count - 2]
    if ($last -ceq 'README.md' -and [IO.Path]::GetExtension($parent) -in @('.ps1','.cmd','.vbs')) {
        $sibling = Join-Path (Join-Path $Package (($parts[0..($parts.Count-2)]) -join '/')) $parent
        if ((Test-Path -LiteralPath $sibling -PathType Leaf) -and ([IO.File]::ReadAllText($sibling) -match '(?m)^(?:#|rem|\x27) JOBS_SOURCE_LAYOUT_ROOT_V1')) { return $null }
    }
    if ($last -ceq $parent -and [IO.Path]::GetExtension($last) -in @('.ps1','.cmd','.vbs')) {
        $source = Join-Path $Package $Relative
        if ((Test-Path -LiteralPath $source -PathType Leaf) -and ([IO.File]::ReadAllText($source) -match '(?m)^(?:#|rem|\x27) JOBS_SOURCE_LAYOUT_ROOT_V1')) {
            return (($parts[0..($parts.Count-2)]) -join '/')
        }
    }
    return $Relative
}
$script:JobsLayoutFileContentViewerTestsRoot = $(if ([IO.Path]::GetFileName($PSScriptRoot) -ceq 'FileContentViewer.Tests.ps1') { Split-Path -Parent $PSScriptRoot } else { $PSScriptRoot })

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
$root = Split-Path -Parent ${script:JobsLayoutFileContentViewerTestsRoot}
. (Resolve-JobsScriptLayoutPath (Join-Path $root 'JobsFileContentViewer/Scripts/FileViewer.ps1'))
. (Resolve-JobsScriptLayoutPath (Join-Path ${script:JobsLayoutFileContentViewerTestsRoot} 'NativeFixtures.ps1'))
$script:assertions = 0
function Assert-Viewer {
    param([bool]$Condition, [string]$Reason)
    $script:assertions++
    if (-not $Condition) { throw ('FAIL: ' + $Reason) }
}
function Assert-ViewerThrows {
    param([scriptblock]$Run, [string]$Reason)
    $threw = $false
    try { & $Run | Out-Null } catch { $threw = $true }
    Assert-Viewer $threw $Reason
}
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('JobsViewer-' + [guid]::NewGuid().ToString('N'))
$savedLimit = [Environment]::GetEnvironmentVariable('JOBS_FILE_VIEWER_MAX_BYTES')
$savedOut = [Console]::Out
$script:prompts = @()
$script:answers = New-Object 'Collections.Generic.Queue[string]'
$script:hostMessages = @()
function Write-Host { param($Object, $ForegroundColor) $script:hostMessages += [string]$Object }
function Read-Host {
    param($Prompt)
    $script:prompts += $Prompt
    if ($script:answers.Count -eq 0) { return $null }
    return $script:answers.Dequeue()
}
function Invoke-ViewerFixture {
    param([string]$Path, [string[]]$Answers = @())
    $script:prompts = @()
    $script:answers.Clear()
    $script:hostMessages = @()
    foreach ($answer in $Answers) { $script:answers.Enqueue($answer) }
    $writer = New-Object IO.StringWriter
    [Console]::SetOut($writer)
    try {
        Invoke-JobsFileContentViewer -Target $Path
        return $writer.ToString()
    } finally { [Console]::SetOut($savedOut); $writer.Dispose() }
}
try {
    [void][IO.Directory]::CreateDirectory($temporary)
    Remove-Item Env:JOBS_FILE_VIEWER_MAX_BYTES -ErrorAction SilentlyContinue
    Assert-Viewer ((Get-JobsFileViewerLimit) -eq 1048576) '默认阈值为 1 MiB'
    foreach ($invalid in @('0', '-1', '1.5', 'YES', '9223372036854775808', ' 12')) {
        $env:JOBS_FILE_VIEWER_MAX_BYTES = $invalid
        Assert-ViewerThrows { Get-JobsFileViewerLimit } ('非法阈值停止：' + $invalid)
    }
    $env:JOBS_FILE_VIEWER_MAX_BYTES = '12'
    Assert-Viewer ((Get-JobsFileViewerLimit) -eq 12) '自定义阈值按字节处理'
    $file = Join-Path $temporary "中文 & %TEMP% ' `$() [literal].txt"
    $text = '中文 $(throw "must not run") & %TEMP%'
    [IO.File]::WriteAllText($file, $text, (New-Object Text.UTF8Encoding($false)))
    $hash = (Get-FileHash -LiteralPath $file).Hash
    $before = [IO.File]::GetLastWriteTimeUtc($file)
    foreach ($answer in @('', 'yes', ' YES', 'NO')) {
        $result = Invoke-ViewerFixture -Path $file -Answers @($answer)
        Assert-Viewer ($result.Length -eq 0 -and $script:prompts.Count -eq 1) '大文件取消前不输出内容，只有精确 YES 执行'
        Assert-Viewer (($script:hostMessages -join '') -match '未读取文件内容') '取消文案明确未读取正文'
    }
    $result = Invoke-ViewerFixture -Path $file
    Assert-Viewer ($result.Length -eq 0) '输入结束默认取消'
    $result = Invoke-ViewerFixture -Path $file -Answers @('YES')
    Assert-Viewer ($result -ceq $text) '确认后只显示文件原文，特殊路径和脚本正文不求值'
    Assert-Viewer ((Get-FileHash -LiteralPath $file).Hash -ceq $hash -and [IO.File]::GetLastWriteTimeUtc($file) -eq $before) '查看不改文件内容或修改时间'

    $env:JOBS_FILE_VIEWER_MAX_BYTES = ([IO.FileInfo]$file).Length.ToString()
    $result = Invoke-ViewerFixture -Path $file
    Assert-Viewer ($result -ceq $text -and $script:prompts.Count -eq 0) '恰好阈值直接输出'
    $env:JOBS_FILE_VIEWER_MAX_BYTES = '1048576'
    foreach ($encoding in @((New-Object Text.UTF8Encoding($true)), [Text.Encoding]::Unicode, [Text.Encoding]::BigEndianUnicode, [Text.Encoding]::UTF32)) {
        [IO.File]::WriteAllText($file, "中文🙂`r`n下一行", $encoding)
        $result = Invoke-ViewerFixture -Path $file
        Assert-Viewer ($result -ceq "中文🙂`n下一行" -and $script:prompts.Count -eq 0) ('识别 Unicode BOM：' + $encoding.WebName)
    }
    # 第 8192 字节落在 UTF-8 多字节中间，4096 字符落在代理对/CRLF中间。
    foreach ($text in @(('a' * 8191 + '中文🙂'), ('a' * 4095 + '🙂end'), ('a' * 4095 + "`r`nend"), ('a' * 4095 + "`rend"))) {
        [IO.File]::WriteAllText($file, $text, (New-Object Text.UTF8Encoding($false)))
        $result = Invoke-ViewerFixture -Path $file
        $expected = $text.Replace("`r`n", "`n").Replace("`r", '\r')
        Assert-Viewer ($result -ceq $expected -and $script:prompts.Count -eq 0) '采样/输出跨块保持 UTF-8、多码点与CRLF内容'
    }
    [IO.File]::WriteAllText($file, ('safe' + [char]27 + ']0;title' + [char]7 + [char]0), (New-Object Text.UTF8Encoding($false)))
    $result = Invoke-ViewerFixture -Path $file
    Assert-Viewer ($result.Length -eq 0 -and $script:prompts.Count -eq 1) '疑似二进制默认取消'
    $result = Invoke-ViewerFixture -Path $file -Answers @('YES')
    Assert-Viewer ($result -ceq 'safe\u001B]0;title\u0007\u0000') '危险终端控制符仅以转义文字输出'
    [IO.File]::WriteAllBytes($file, [byte[]]@(255, 128, 65))
    $result = Invoke-ViewerFixture -Path $file -Answers @('YES')
    Assert-Viewer ($result -ceq ([string][char]65533 + [char]65533 + 'A')) '未知编码确认后替换无效字节'
    Assert-ViewerThrows { Invoke-ViewerFixture -Path $temporary } '目录后台拒绝'
    Assert-ViewerThrows { Invoke-ViewerFixture -Path (Join-Path $temporary 'missing') } '已删除文件后台拒绝'
    $link = Join-Path $temporary 'link.txt'
    if (New-JobsTestSymbolicLink -Path $link -Target $file) {
        Assert-ViewerThrows { Invoke-ViewerFixture -Path $link } '符号链接后台拒绝'
    }
    $largeText = 'x' * 1048577
    [IO.File]::WriteAllText($file, $largeText, (New-Object Text.UTF8Encoding($false)))
    $result = Invoke-ViewerFixture -Path $file -Answers @('YES')
    Assert-Viewer ($result -ceq $largeText -and $script:prompts.Count -eq 1) '超过默认阈值的大型无换行文本可流式完整查看'
    $installer = Import-Module (Join-Path $root 'JobsFileContentViewer/Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
    $manifest = Get-Content -LiteralPath (Join-Path $root 'JobsFileContentViewer/Extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $plan = @(Get-JobsPackageRegistryPlan -Manifest $manifest -ReleasePath $temporary -PowerShellPath 'C:\Windows\powershell.exe')
    Assert-Viewer ($plan.Count -eq 2) '本包只注册文件 handler 与本包 CLSID'
    Assert-Viewer ($plan[0].Key -ceq 'Software\Classes\*\shellex\ContextMenuHandlers\Jobs.WindowsExtension.file-content-viewer') '无目录或背景菜单'
    Remove-Module $installer
    # 真实子进程经过生产 Action，验证输出编码，不使用内存 StringWriter 代替终端编码。
    [IO.File]::WriteAllText($file, ('a' * 4095 + '🙂中文'), (New-Object Text.UTF8Encoding($false)))
    $harness = Join-Path $temporary 'ViewerProcess.ps1'
    $actionPath = (Join-Path $root 'JobsFileContentViewer/Scripts/Action.psm1').Replace("'", "''")
    $harnessBody = 'param([string]$Target)' + [Environment]::NewLine +
        "Import-Module '$actionPath' -DisableNameChecking" + [Environment]::NewLine +
        'Invoke-JobsFeature -Target $Target'
    [IO.File]::WriteAllText($harness, $harnessBody, (New-Object Text.UTF8Encoding($true)))
    Import-Module (Join-Path $root 'JobsFileContentViewer/Scripts/Common.psm1') -DisableNameChecking
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $start.Arguments = ((@('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $harness, '-Target', $file) | ForEach-Object { Quote-JobsArgument $_ }) -join ' ')
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false, $true)
    $process = [Diagnostics.Process]::Start($start)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(15000)) { $process.Kill(); throw '真实编码输出夹具超时。' }
        Assert-Viewer ($process.ExitCode -eq 0) ('真实 Action 子进程成功：' + $stderr.GetAwaiter().GetResult())
        Assert-Viewer ($stdout.GetAwaiter().GetResult().Contains(('a' * 4095 + '🙂中文'))) '真实UTF8字节输出保留中文和跨块emoji'
    } finally { $process.Dispose() }
    [Console]::WriteLine(('PASS: FileContentViewer.Tests.ps1 ({0} assertions)' -f $script:assertions))
} finally {
    [Console]::SetOut($savedOut)
    [Environment]::SetEnvironmentVariable('JOBS_FILE_VIEWER_MAX_BYTES', $savedLimit)
    if ([IO.Directory]::Exists($temporary)) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

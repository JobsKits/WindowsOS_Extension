#requires -Version 5.1
<#
Clean.ps1 | JobsDiskSpaceInfo 独立 Windows 清理
Created by Jobs on 2026年11月15日，星期日.
用途：终端内选择当前用户缓存、历史、缺失开发登记或明确工程的构建 App 输出；用户缓存首行全选、次行跳过。
交互：Enter勾选，Space提交已有选择；无勾选时提交当前行，无匹配时等待；默认跳过和最终范围确认保留。
影响：点击菜单仅打开本脚本；预览、取消不清理，执行前列范围并默认取消。
恢复：历史、开发快捷方式、AVD 登记和构建 App 先保存可核对备份；缓存直接删除。
失败：开发阶段失败仍进入常规清理并保留失败；常规只重试失败项，回车继续，非空输入或输入结束停止。
保护：按通用工程／依赖／SDK标记、只读内容和扫描预算保留候选，不依赖用户名或环境目录名称。
范围：无提权、无全盘扫描、无安装软件或 SDK、无外部仓库/原 clean 运行依赖。
#>
[CmdletBinding()]
param([ValidateSet('Interactive', 'Plan')][string]$Mode = 'Interactive',
      [ValidateSet('cache', 'history', 'build-apps', 'avd', 'shortcuts')][string]$Category = 'cache',
      [string]$ProjectRoot = '')
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
        static readonly Regex Reply = new Regex("\x1b\](?<key>10|11|4;[0-9]{1,2});(?<rgb>rgb:[0-9a-f]{1,4}/[0-9a-f]{1,4}/[0-9a-f]{1,4})(?:\x07|\x1b\\)", RegexOptions.IgnoreCase);
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
                    if (item[0].Kind == 1 && item[0].Character != '$script:CleanLog = $null') {
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
$script:CleanLog = $null
# 本轮日志与终端同时输出；不将终端颜色写入日志。
function Write-CleanMessage {
    param([string]$Text, [ConsoleColor]$Color = [ConsoleColor]::Gray)
    Write-Host $Text -ForegroundColor $Color
    if ($script:CleanLog) { [IO.File]::AppendAllText($script:CleanLog, $Text + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false))) }
}
# 仅在真实交互且宿主明确支持VT时使用ANSI，NO_COLOR只检查是否存在。
function Test-CleanPromptAnsi {
    param([Collections.IDictionary]$Capabilities = $null)
    if ($null -eq $Capabilities) {
        try {
            $environment = [Environment]::GetEnvironmentVariables('Process')
            $Capabilities = @{ HostName = $Host.Name; InputRedirected = [Console]::IsInputRedirected; OutputRedirected = [Console]::IsOutputRedirected;
                               ErrorRedirected = [Console]::IsErrorRedirected; NoColorPresent = $environment.Contains('NO_COLOR');
                               PlainOutput = $env:PLAIN_OUTPUT; Term = $env:TERM; VirtualTerminal = $false; SourceTree = $false }
            if ($null -ne $Host.UI.PSObject.Properties['SupportsVirtualTerminal']) { $Capabilities.VirtualTerminal = $Host.UI.SupportsVirtualTerminal }
            foreach ($key in $environment.Keys) { if ([string]$key -match '^(?i:SOURCE_?TREE)') { $Capabilities.SourceTree = $true; break } }
        } catch { return $false }
    }
    return ($Capabilities.HostName -eq 'ConsoleHost' -and -not $Capabilities.InputRedirected -and -not $Capabilities.OutputRedirected -and
            -not $Capabilities.ErrorRedirected -and -not $Capabilities.NoColorPresent -and $Capabilities.PlainOutput -ne '1' -and
            $Capabilities.Term -ine 'dumb' -and -not $Capabilities.SourceTree -and $Capabilities.VirtualTerminal)
}
# 分别呈现询问正文和两种输入选项，分隔符前复位，数据与输入语义保持独立。
function Format-CleanPrompt {
    param([string]$Question, [string]$EnterOption = '', [string]$TextOption = '', [bool]$Ansi = $false)
    $esc = [string][char]27
    $body = $Question
    $separator = ''
    if ($Question.EndsWith('：') -or $Question.EndsWith(':')) { $body = $Question.Substring(0, $Question.Length - 1); $separator = $Question.Substring($Question.Length - 1) }
    if ($Ansi) { $body = $esc + '[1;36m' + $body + $esc + '[0m' }
    $body += $separator
    if ($EnterOption -eq '' -and $TextOption -eq '') { return $body }
    $enter = $EnterOption
    $text = $TextOption
    if ($Ansi) { $enter = $esc + '[1;32m' + $enter + $esc + '[0m'; $text = $esc + '[1;31m' + $text + $esc + '[0m' }
    return ($body + '[' + $enter + ' / ' + $text + ']：')
}
# 终端按能力展示询问，日志只追加同一提示的纯文本副本，不负责读取输入。
function Write-CleanPrompt {
    param([string]$Question, [string]$EnterOption = '', [string]$TextOption = '', [switch]$NoNewline)
    $plain = Format-CleanPrompt $Question $EnterOption $TextOption
    if ($script:CleanLog) { [IO.File]::AppendAllText($script:CleanLog, $plain + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false))) }
    $display = Format-CleanPrompt $Question $EnterOption $TextOption -Ansi (Test-CleanPromptAnsi)
    Write-Host $display -NoNewline:$NoNewline
}
# 规范化本机路径，拒绝网络路径、卷根和空路径。
function Get-CleanLocalPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.StartsWith('\\')) { throw '清理范围必须是明确的本机路径。' }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if ([string]::IsNullOrWhiteSpace($full) -or $full -eq [IO.Path]::GetPathRoot($full).TrimEnd([IO.Path]::DirectorySeparatorChar)) { throw '不能清理磁盘根目录。' }
    return $full
}
# 不跟随父链或目标的 junction/symlink；不存在仅接受真实的路径缺失。
function Assert-CleanPath {
    param([string]$Path, [string]$Root, [switch]$AllowRoot)
    $full = Get-CleanLocalPath $Path
    $base = Get-CleanLocalPath $Root
    $prefix = $base + [IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -and -not ($AllowRoot -and $full.Equals($base, [StringComparison]::OrdinalIgnoreCase))) { throw ('清理路径越界：' + $full) }
    $current = $full
    while ($current) {
        try {
            $attributes = [IO.File]::GetAttributes($current)
            if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ('拒绝重解析点：' + $current) }
        } catch [IO.FileNotFoundException] { } catch [IO.DirectoryNotFoundException] { }
        $parent = [IO.Path]::GetDirectoryName($current)
        if ($parent -eq $current) { break }
        $current = $parent
    }
    return $full
}
# 只从当前用户标准位置发现缓存和历史，不接受任意 HISTFILE 或工具自定义路径。
function Get-CleanContext {
    $profile = Get-CleanLocalPath ([Environment]::GetFolderPath('UserProfile'))
    $local = Get-CleanLocalPath ([Environment]::GetFolderPath('LocalApplicationData'))
    $roaming = Get-CleanLocalPath ([Environment]::GetFolderPath('ApplicationData'))
    [void](Assert-CleanPath $local $profile)
    [void](Assert-CleanPath $roaming $profile)
    return [pscustomobject]@{ Profile = $profile; Local = $local; Roaming = $roaming; Now = [DateTime]::UtcNow }
}
# 为每个候选建立独立扫描预算；超限保留整项，不输出不完整计划。
function New-CleanScanBudget {
    return @{ Nodes = 0; MaximumNodes = 10000; MaximumDepth = 64; Timer = [Diagnostics.Stopwatch]::StartNew(); MaximumMilliseconds = 5000 }
}
# 只按标准工程、依赖和SDK标记识别，不依赖用户或环境目录的名称。
function Test-CleanDevelopmentMarker {
    param([IO.FileSystemInfo]$Item)
    if ($Item.PSIsContainer) {
        return ($Item.Name -in @('.git', '.hg', '.svn', 'node_modules', 'Pods', 'PodsManual', '.dart_tool', '.gradle', 'build', 'DerivedData', '.venv', 'venv', 'site-packages', 'conda-meta') -or
                $Item.Extension -in @('.xcodeproj', '.xcworkspace'))
    }
    return ($Item.Name -in @('go.mod', 'go.work', 'package.json', 'package-lock.json', 'pnpm-lock.yaml', 'yarn.lock', 'bun.lock', 'bun.lockb',
                            'Cargo.toml', 'Cargo.lock', 'pyproject.toml', 'requirements.txt', 'Pipfile', 'poetry.lock', 'pyvenv.cfg',
                            'pubspec.yaml', 'pubspec.lock', 'Podfile', 'Gemfile', 'CMakeLists.txt', 'Makefile', '.gitmodules', 'package.xml', 'SDKSettings.plist') -or
            $Item.Extension -in @('.csproj', '.fsproj', '.vbproj', '.sln'))
}
# 流式遍历候选且不跟随重解析点；只读、开发标记或预算超限均保留整项。
function Get-CleanTreeRows {
    param([string]$Path, [string]$Base = '', [switch]$Content, [Collections.IDictionary]$Scan = $null, [int]$Depth = 0)
    if (-not $Base) { $Base = $Path }
    if ($null -eq $Scan) { $Scan = New-CleanScanBudget }
    if ($Scan.Nodes -ge $Scan.MaximumNodes -or $Depth -gt $Scan.MaximumDepth -or $Scan.Timer.ElapsedMilliseconds -gt $Scan.MaximumMilliseconds) { throw ('候选安全扫描超出预算，整体保留：' + $Base) }
    $Scan.Nodes++
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ('候选包含重解析点，保留：' + $Path) }
    if (($item.Attributes -band [IO.FileAttributes]::ReadOnly) -ne 0) { throw ('候选包含只读内容，整体保留：' + $Path) }
    if (Test-CleanDevelopmentMarker $item) { throw ('候选包含工程、依赖或SDK标记，整体保留：' + $Path) }
    $relative = $item.FullName.Substring($Base.Length)
    $attributes = [int]$item.Attributes
    # 暂存根使用点前缀；部分文件系统由文件名推导 Hidden，不代表实体内容变化。
    if ($relative -eq '') { $attributes = $attributes -band (-bnot ([int][IO.FileAttributes]::Hidden -bor [int][IO.FileAttributes]::Normal)) }
    $digest = ''
    if ($Content -and -not $item.PSIsContainer) { $digest = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256 -ErrorAction Stop).Hash }
    if ($Scan.Timer.ElapsedMilliseconds -gt $Scan.MaximumMilliseconds) { throw ('候选安全扫描超出时间预算，整体保留：' + $Base) }
    [pscustomobject]@{ Path = $relative; Directory = $item.PSIsContainer; Length = $(if ($item.PSIsContainer) { 0 } else { $item.Length }); Modified = $item.LastWriteTimeUtc.Ticks; Created = $item.CreationTimeUtc.Ticks; Attributes = $attributes; Hash = $digest }
    if ($item.PSIsContainer) {
        foreach ($childPath in [IO.Directory]::EnumerateFileSystemEntries($Path)) {
            Get-CleanTreeRows $childPath $Base -Content:$Content -Scan $Scan -Depth ($Depth + 1)
        }
    }
}
# 用相对内容与元数据快照复检候选，根目录更名不会使内容比较失效。
function Get-CleanStamp {
    param([string]$Path, [switch]$Content)
    $rows = @(Get-CleanTreeRows $Path -Content:$Content | Sort-Object Path)
    if ($Content) { return (ConvertTo-Json -InputObject @($rows | Select-Object Path, Directory, Length, Hash) -Depth 4 -Compress) }
    return (ConvertTo-Json -InputObject $rows -Depth 4 -Compress)
}
# 只收录存在且全树安全的候选；缺失、被占用或链接都不会变成删除目标。
function Add-CleanCandidate {
    param($Entries, $Notes, [string]$Path, [string]$Root, [bool]$Backup, [string]$MissingTarget = '')
    try {
        $full = Assert-CleanPath $Path $Root
        if (-not [IO.File]::Exists($full) -and -not [IO.Directory]::Exists($full)) { return }
        $stamp = Get-CleanStamp $full
        $Entries.Add([pscustomobject]@{ Path = $full; Root = (Get-CleanLocalPath $Root); Backup = $Backup; Stamp = $stamp; MissingTarget = $MissingTarget })
    } catch { $Notes.Add($_.Exception.Message) }
}
# 只检查用户明确选择的 Flutter 工程的标准 Windows runner 输出。
function Get-CleanBuildApps {
    param([string]$Root)
    $full = Get-CleanLocalPath $Root
    [void](Assert-CleanPath $full $full -AllowRoot)
    $pubspec = Join-Path $full 'pubspec.yaml'
    [void](Assert-CleanPath $pubspec $full)
    if (-not [IO.File]::Exists($pubspec) -or -not [IO.Directory]::Exists((Join-Path $full 'lib')) -or
        [IO.File]::ReadAllText($pubspec) -notmatch '(?m)^\s+sdk:\s*flutter\s*(?:#.*)?$') { throw '仅支持明确选择的 Flutter 根工程；没有匹配时保留全部文件。' }
    foreach ($architecture in @('x64', 'arm64', 'x86')) {
        foreach ($configuration in @('Debug', 'Profile', 'Release')) {
            $path = Join-Path $full ('build/windows/' + $architecture + '/runner/' + $configuration)
            [void](Assert-CleanPath $path $full)
            if ([IO.Directory]::Exists($path) -and @(Get-ChildItem -LiteralPath $path -File -Filter '*.exe' -ErrorAction Stop).Count -gt 0) { $path }
        }
    }
}
# Android 仅清除默认 AVD 集中、实体目录确实缺失的精确 .ini 登记。
function Get-CleanOrphanAvd {
    param($Context)
    $root = Join-Path $Context.Profile '.android/avd'
    [void](Assert-CleanPath $root $Context.Profile)
    if (-not [IO.Directory]::Exists($root)) { return }
    foreach ($file in @(Get-ChildItem -LiteralPath $root -File -Filter '*.ini' -ErrorAction Stop)) {
        if ($file.BaseName -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$') { continue }
        [void](Assert-CleanPath $file.FullName $root)
        $lines = @([IO.File]::ReadAllLines($file.FullName) | Where-Object { $_ -cmatch '^path=' })
        $expected = Join-Path $root ($file.BaseName + '.avd')
        if ($lines.Count -ne 1) { continue }
        $actual = Get-CleanLocalPath $lines[0].Substring(5)
        if (-not $actual.Equals((Get-CleanLocalPath $expected), [StringComparison]::OrdinalIgnoreCase)) { continue }
        [void](Assert-CleanPath $expected $root)
        if (-not [IO.Directory]::Exists($expected) -and -not [IO.File]::Exists($expected)) { $file.FullName }
    }
}
# 只匹配开发输出中的目标；正常应用路径、未知路径和启动参数均不参与。
function Test-CleanDevelopmentTarget {
    param([string]$Path, [string]$Profile)
    try { $full = Assert-CleanPath $Path $Profile } catch { return $false }
    return $full -match '(?i)[\\/]build[\\/]windows[\\/](x64|arm64|x86)[\\/]runner[\\/](Debug|Profile|Release)[\\/][^\\/]+\.exe$'
}
# Windows 没有 LaunchServices；仅备份并移除目标已缺失的用户开发快捷方式。
function Get-CleanStaleShortcuts {
    param($Context)
    $root = Join-Path $Context.Roaming 'Microsoft/Windows/Start Menu/Programs'
    [void](Assert-CleanPath $root $Context.Profile)
    if (-not [IO.Directory]::Exists($root)) { return }
    $shell = New-Object -ComObject WScript.Shell
    try {
        # 先校验树再递归枚举；不扫描公用 Start Menu 或桌面其它文件。
        [void](Get-CleanStamp $root)
        foreach ($file in @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.lnk' -ErrorAction Stop)) {
            $shortcut = $shell.CreateShortcut($file.FullName)
            try { $target = [string]$shortcut.TargetPath } finally { if ([Runtime.InteropServices.Marshal]::IsComObject($shortcut)) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) } }
            if ((Test-CleanDevelopmentTarget $target $Context.Profile) -and -not [IO.File]::Exists($target) -and -not [IO.Directory]::Exists($target)) { [pscustomobject]@{ Path = $file.FullName; Target = $target } }
        }
    } finally { if ([Runtime.InteropServices.Marshal]::IsComObject($shell)) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) } }
}
# 各类别只生成准确清单，读取不创建日志、备份或修改文件。
function Get-CleanPlan {
    param($Context, [string]$Kind, [string]$Project = '')
    $entries = New-Object 'Collections.Generic.List[object]'
    $notes = New-Object 'Collections.Generic.List[string]'
    switch ($Kind) {
        'cache' {
            $temp = Join-Path $Context.Local 'Temp'
            $roots = @($temp)
            foreach ($root in $roots) {
                try {
                    [void](Assert-CleanPath $root $Context.Profile)
                    if (-not [IO.Directory]::Exists($root)) { continue }
                    foreach ($child in @(Get-ChildItem -LiteralPath $root -Force -ErrorAction Stop)) {
                        if ($child.Name -like '.JobsClean-*') { continue }
                        if ($root -eq $temp -and $child.LastWriteTimeUtc -ge $Context.Now.AddDays(-7)) { continue }
                        Add-CleanCandidate $entries $notes $child.FullName $root $false
                    }
                } catch { $notes.Add($_.Exception.Message) }
            }
        }
        'dev-caches' {
            foreach ($root in @((Join-Path $Context.Local 'D3DSCache'), (Join-Path $Context.Local 'pip/Cache'),
                               (Join-Path $Context.Local 'npm-cache/_cacache'), (Join-Path $Context.Local 'NuGet/v3-cache'))) {
                try {
                    [void](Assert-CleanPath $root $Context.Profile)
                    if (-not [IO.Directory]::Exists($root)) { continue }
                    foreach ($child in @(Get-ChildItem -LiteralPath $root -Force -ErrorAction Stop)) {
                        if ($child.Name -notlike '.JobsClean-*') { Add-CleanCandidate $entries $notes $child.FullName $root $false }
                    }
                } catch { $notes.Add($_.Exception.Message) }
            }
        }
        'history' {
            foreach ($relative in @('Microsoft/Windows/PowerShell/PSReadLine/ConsoleHost_history.txt', 'Microsoft/PowerShell/PSReadLine/ConsoleHost_history.txt')) {
                Add-CleanCandidate $entries $notes (Join-Path $Context.Roaming $relative) $Context.Roaming $true
            }
        }
        'build-apps' { foreach ($path in @(Get-CleanBuildApps $Project)) { Add-CleanCandidate $entries $notes $path $Project $true } }
        'archives' {
            # 发行包不是普通缓存；只列明确工程标准输出中的实际 APK/AAB，逐项备份。
            [void]@(Get-CleanBuildApps $Project)
            foreach ($relative in @('build/app/outputs/apk', 'build/app/outputs/bundle')) {
                $root = Join-Path $Project $relative
                [void](Assert-CleanPath $root $Project)
                if (-not [IO.Directory]::Exists($root)) { continue }
                [void](Get-CleanStamp $root)
                foreach ($file in @(Get-ChildItem -LiteralPath $root -File -Recurse -ErrorAction Stop | Where-Object { $_.Extension -in @('.apk', '.aab') })) {
                    Add-CleanCandidate $entries $notes $file.FullName $Project $true
                }
            }
        }
        'avd' {
            foreach ($path in @(Get-CleanOrphanAvd $Context)) {
                $target = Join-Path ([IO.Path]::GetDirectoryName($path)) ([IO.Path]::GetFileNameWithoutExtension($path) + '.avd')
                Add-CleanCandidate $entries $notes $path (Join-Path $Context.Profile '.android/avd') $true $target
            }
        }
        'shortcuts' { foreach ($link in @(Get-CleanStaleShortcuts $Context)) { Add-CleanCandidate $entries $notes $link.Path $Context.Profile $true $link.Target } }
        default { throw '未知清理类别。' }
    }
    return [pscustomobject]@{ Kind = $Kind; Project = $Project; Entries = @($entries.ToArray() | Sort-Object Path); Notes = @($notes.ToArray()) }
}
# 复制可恢复项目且不跟随链接；备份完整性由调用方内容摘要核验。
function Copy-CleanTree {
    param([string]$Source, [string]$Destination)
    $item = Get-Item -LiteralPath $Source -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw '备份时出现重解析点，保留源文件。' }
    if ($item.PSIsContainer) {
        [void][IO.Directory]::CreateDirectory($Destination)
        foreach ($child in @(Get-ChildItem -LiteralPath $Source -Force -ErrorAction Stop)) { Copy-CleanTree $child.FullName (Join-Path $Destination $child.Name) }
    } else { [IO.File]::Copy($Source, $Destination, $false) }
}
# 删除已暂存且复检过的精确候选，任何新增重解析点都会使本项失败并保留。
function Remove-CleanTree {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ('删除前发现重解析点，保留：' + $Path) }
    if ($item.PSIsContainer) {
        foreach ($child in @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop)) { Remove-CleanTree $child.FullName }
        [IO.Directory]::Delete($Path)
    } else { [IO.File]::Delete($Path) }
}
# 单项先复检、按需备份、同父目录更名暂存；范围变化/备份失败不删源。
function Invoke-CleanEntry {
    param($Entry, [string]$BackupRoot)
    [void](Assert-CleanPath $Entry.Path $Entry.Root)
    if ((Get-CleanStamp $Entry.Path) -cne $Entry.Stamp) { throw ('候选发生变化，保留：' + $Entry.Path) }
    if ($Entry.MissingTarget) {
        [void](Assert-CleanPath $Entry.MissingTarget $Entry.Root)
        if ([IO.File]::Exists($Entry.MissingTarget) -or [IO.Directory]::Exists($Entry.MissingTarget)) { throw '登记目标已经恢复，保留登记。' }
    }
    if ($Entry.Backup) {
        [void](Assert-CleanPath $BackupRoot $BackupRoot -AllowRoot)
        $destination = Join-Path $BackupRoot ([guid]::NewGuid().ToString('N'))
        $content = Get-CleanStamp $Entry.Path -Content
        [void][IO.Directory]::CreateDirectory($BackupRoot)
        Copy-CleanTree $Entry.Path $destination
        if ((Get-CleanStamp $destination -Content) -cne $content -or (Get-CleanStamp $Entry.Path) -cne $Entry.Stamp) { throw '备份或源内容复核失败，保留源文件。' }
        [IO.File]::WriteAllText(($destination + '.restore.json'), (ConvertTo-Json @{ OriginalPath = $Entry.Path; BackupPath = $destination; Created = [DateTime]::UtcNow } -Depth 3), (New-Object Text.UTF8Encoding($false)))
        Write-CleanMessage ('可恢复备份：' + $destination)
    }
    if ($Entry.MissingTarget) {
        [void](Assert-CleanPath $Entry.MissingTarget $Entry.Root)
        if ([IO.File]::Exists($Entry.MissingTarget) -or [IO.Directory]::Exists($Entry.MissingTarget)) { throw '备份后登记目标恢复，保留登记。' }
    }
    $stage = Join-Path ([IO.Path]::GetDirectoryName($Entry.Path)) ('.JobsClean-' + [guid]::NewGuid().ToString('N'))
    Move-Item -LiteralPath $Entry.Path -Destination $stage -ErrorAction Stop
    try {
        [void](Assert-CleanPath $stage $Entry.Root)
        if ((Get-CleanStamp $stage) -cne $Entry.Stamp) { throw '暂存后候选发生变化，停止删除。' }
        Remove-CleanTree $stage
    } catch {
        if (-not [IO.File]::Exists($Entry.Path) -and -not [IO.Directory]::Exists($Entry.Path)) {
            try { Move-Item -LiteralPath $stage -Destination $Entry.Path -ErrorAction Stop } catch { Write-CleanMessage ('保留暂存项目，请人工恢复：' + $stage) Yellow }
        }
        throw
    }
}
# 执行前整组重新发现；确认清单改变时本组不清理，子项失败继续并汇总非零结果。
function Invoke-CleanPlan {
    param($Plan, $Context, [Collections.Generic.List[object]]$FailedEntries = $null)
    $fresh = Get-CleanPlan $Context $Plan.Kind $Plan.Project
    $previous = ConvertTo-Json -InputObject $Plan.Entries -Depth 5 -Compress
    if ($null -ne $Plan.PSObject.Properties['SelectedOnly'] -and $Plan.SelectedOnly) {
        $freshEntries = @($fresh.Entries | Where-Object { $_.Path -cin @($Plan.Entries.Path) })
    } else { $freshEntries = $fresh.Entries }
    if ((ConvertTo-Json -InputObject $freshEntries -Depth 5 -Compress) -cne $previous) { throw '确认后的清理清单已改变，请重新选择；本组未执行。' }
    $backup = Join-Path $Context.Local ('Jobs/WindowsExtension/extensions/disk-space-info/clean-backups/' + [guid]::NewGuid().ToString('N'))
    $success = 0; $failed = 0
    foreach ($entry in $Plan.Entries) {
        try { Invoke-CleanEntry $entry $backup; $success++; Write-CleanMessage ('完成：' + $entry.Path) Green }
        catch [Management.Automation.PipelineStoppedException] { throw }
        catch [OperationCanceledException] { throw }
        catch {
            $failed++
            if ($null -ne $FailedEntries) { $FailedEntries.Add($entry) }
            Write-CleanMessage ('失败并保留可恢复项：' + $entry.Path + '；' + $_.Exception.Message) Red
        }
    }
    Write-CleanMessage ('结果：成功 ' + $success + '；失败 ' + $failed)
    return $failed
}
# 常规类别只保留原确认清单中的失败项；成功出队，重试仍复检原快照与备份。
function Invoke-CleanRegularPlan {
    param($Plan, $Context, [scriptblock]$ReadAnswer = { [Console]::ReadLine() })
    $labels = @{ cache = '用户临时文件'; history = 'PowerShell 历史'; shortcuts = '失效开发快捷方式' }
    $label = $labels[$Plan.Kind]
    $pending = $Plan
    $round = 1
    while ($true) {
        Write-CleanMessage ('常规清理第 ' + $round + ' 轮：' + $label) Cyan
        $remaining = New-Object 'Collections.Generic.List[object]'
        try { $failed = Invoke-CleanPlan $pending $Context $remaining }
        catch [Management.Automation.PipelineStoppedException] { throw }
        catch [OperationCanceledException] { throw }
        catch {
            foreach ($entry in $pending.Entries) { $remaining.Add($entry) }
            $failed = $remaining.Count
            Write-CleanMessage ('本轮未完成，保留原确认范围：' + $_.Exception.Message) Red
        }
        if (-not $failed) { return [pscustomobject]@{ Failed = 0; Stopped = $false } }
        $pending = [pscustomobject]@{ Kind = $Plan.Kind; Project = $Plan.Project; Entries = @($remaining.ToArray()); SelectedOnly = $true }
        Write-CleanMessage ('清理未全部完成：' + $label + '，剩余 ' + $failed + ' 项；详情：' + $script:CleanLog) Yellow
        foreach ($entry in $pending.Entries) { Write-CleanMessage ('  待重试：' + $entry.Path) Yellow }
        Write-CleanPrompt '是否继续清理以上失败项？' '回车 = 继续' '输入任意字符后回车 = 停止' -NoNewline
        $answer = & $ReadAnswer
        if ($null -eq $answer -or $answer -cne '') {
            Write-CleanMessage '已停止重试；未完成项目与全部日志保留。' Yellow
            return [pscustomobject]@{ Failed = $failed; Stopped = $true }
        }
        $round++
        Write-CleanMessage ('继续重试失败项，第 ' + $round + ' 轮；已完成项目不再执行。') Cyan
    }
}
# 开始执行后才初始化持久日志，取消和预览不会创建日志文件。
function Initialize-CleanLog {
    param($Context)
    if ($script:CleanLog) { return }
    $script:CleanLog = Join-Path $Context.Local ('Jobs/WindowsExtension/extensions/disk-space-info/logs/clean-' + [guid]::NewGuid().ToString('N') + '.log')
    [void](Assert-CleanPath $script:CleanLog $Context.Profile)
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($script:CleanLog))
    Write-CleanMessage ('日志：' + $script:CleanLog)
}
# 只解析本轮不可执行的候选ID；全组选项不混入真实路径或空选默认值。
function ConvertFrom-CleanFzfSelection {
    param($Plan, [string[]]$Rows)
    if (-not $Rows.Count) { return @() }
    $ids = @($Rows | ForEach-Object { ($_ -split "`t", 2)[0] } | Select-Object -Unique)
    foreach ($id in $ids) { if ($id -cnotin @('__ALL__', '__SKIP__', '__EMPTY__') -and ($id -notmatch '^\d+$' -or [long]$id -ge $Plan.Entries.Count)) { throw '选择结果不属于本轮清单，未执行。' } }
    if ($ids -ccontains '__SKIP__' -or $ids -ccontains '__EMPTY__') { return @() }
    if ($ids -ccontains '__ALL__') { return @($Plan.Entries) }
    return @($ids | ForEach-Object { $Plan.Entries[[int]$_] })
}
# 用户明确继续后才调用健康的已有 fzf；不下载、不安装、不退回数字输入。
function Select-CleanGroupEntries {
    param($Plan, [string]$Fzf, [switch]$UserCache)
    $rows = @('__ALL__' + "`t" + $(if ($UserCache) { '全选用户缓存（下一步核对范围）' } else { '清理当前组全部' }))
    if ($UserCache) { $rows += '__SKIP__' + "`t" + '跳过用户缓存清理（默认）' }
    for ($index = 0; $index -lt $Plan.Entries.Count; $index++) { $rows += [string]$index + "`t" + $Plan.Entries[$index].Path }
    $options = @('--multi', '--no-sort', '--layout=reverse', '--height=80%', ('--delimiter=' + "`t"), '--with-nth=2..',
                 '--header=首行：当前组全部。↑↓/Tab移动，Enter勾选/取消，Space确认，未勾选则取当前行，←/Esc取消；下一步仍需范围确认。',
                 '--bind=up:up,down:down,tab:down,btab:up,enter:toggle,space:accept-non-empty,left:abort')
    if ($UserCache) {
        $options = @('--multi', '--no-sort', '--layout=reverse', '--height=80%', ('--delimiter=' + "`t"), '--with-nth=2..',
                     '--header=首行全选、次行跳过（默认）；↑↓/Tab移动，Enter勾选/取消，Space确认，未勾选则取当前行，←/Esc取消。下一步仍需范围确认。',
                     '--bind=load:pos(2),up:up,down:down,tab:down,btab:up,enter:toggle,space:accept-non-empty,esc:abort,left:abort')
    }
    $start = New-CleanFzfStartInfo $Fzf $options
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    $started = $false
    try {
        $started = $process.Start()
        if (-not $started) { throw 'fzf 未启动，该组保留。' }
        $output = $process.StandardOutput.ReadToEndAsync()
        $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes(($rows -join "`n") + "`n")
        $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
        $process.StandardInput.Close()
        $process.WaitForExit()
        $selected = @($output.GetAwaiter().GetResult() -split '\r?\n' | Where-Object { $_ -cne '' })
        if ($process.ExitCode -in @(1, 130)) { return @() }
        if ($process.ExitCode -ne 0) { throw ('fzf 失败，未执行该组：' + $process.ExitCode) }
        return @(ConvertFrom-CleanFzfSelection $Plan $selected)
    } finally {
        if ($started -and -not $process.HasExited) { $process.Kill() }
        $process.Dispose()
    }
}
# 仅在 fzf 子进程清除用户自动筛选配置；父进程的未设置/空/非空状态完全保留。
function New-CleanFzfStartInfo {
    param([string]$Fzf, [string[]]$Options)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Fzf
    $quoted = foreach ($option in $Options) { '"' + ([regex]::Replace($option, '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"' }
    $start.Arguments = $quoted -join ' '
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $start.EnvironmentVariables.Remove('FZF_DEFAULT_OPTS')
    $start.EnvironmentVariables.Remove('FZF_DEFAULT_OPTS_FILE')
    return $start
}
# 版本自检复用相同子环境隔离；异常只结束本次自检，不安装或接管其它进程。
function Test-CleanFzf {
    param([string]$Fzf)
    $process = New-Object Diagnostics.Process
    $process.StartInfo = New-CleanFzfStartInfo $Fzf @('--version')
    $started = $false
    try {
        $started = $process.Start()
        if (-not $started) { return $false }
        $process.StandardInput.Close()
        $output = $process.StandardOutput.ReadToEndAsync()
        if (-not $process.WaitForExit(3000)) { return $false }
        return $process.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($output.GetAwaiter().GetResult())
    } catch { return $false }
    finally {
        if ($started -and -not $process.HasExited) { $process.Kill() }
        $process.Dispose()
    }
}
# 展示开发范围专用确认，复用询问样式与纯文本日志，不读取或改变用户输入。
function Show-CleanDevelopmentConfirmation {
    Write-CleanPrompt '确认仅执行以上开发范围：' '回车确认执行' '输入任意字符后回车取消开发阶段并继续常规清理' -NoNewline
}
# 可选开发阶段先问后扫描；Windows只提供有证据的等价组，不触碰Apple目录。
function Invoke-CleanDevelopmentStage {
    param($Context, [scriptblock]$ReadAnswer = { [Console]::ReadLine() })
    Write-CleanMessage '可选：开发存储分组清理（位于常规 clean 之前）' Red
    Write-CleanMessage 'Windows没有 Xcode Device Support、SwiftUI Previews、DerivedData或.xcarchive；不扫描或删除这些目录。' Blue
    Write-CleanMessage '适用组：Simulators → 实体缺失Android AVD登记；DerivedData → 选定Flutter的Windows App输出；Archives → 明确选择的APK/AAB；Caches → 已知下载/着色器缓存。' Blue
    Write-CleanMessage '这些组仅在此处理，跳过、取消或未选择项目不会被后面的常规 clean 补清。' Yellow
    Write-CleanMessage '最终范围回车确认执行；非空输入取消开发阶段并进入常规清理；EOF / Ctrl+C 取消整轮。' Yellow
    Write-CleanPrompt '是否进入开发分组？' '回车进入开发分组' '输入任意内容后回车跳过' -NoNewline
    $answer = & $ReadAnswer
    if ($null -eq $answer) { Write-CleanMessage '输入已结束，取消整轮 clean；没有收集候选。'; return -1 }
    if ($answer -cne '') { Write-CleanMessage '已跳过开发分组；没有收集候选。'; return 0 }
    $command = Get-Command fzf.exe, fzf -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) { Write-CleanMessage '未找到已有 fzf，开发分组未执行；不安装工具，全部开发组保留。' Yellow; return 0 }
    if (-not (Test-CleanFzf $command.Source)) { Write-CleanMessage 'fzf 不健康，开发分组未执行；全部开发组保留。' Yellow; return 0 }
    $groups = @('', 'avd', 'build-apps', 'archives', 'dev-caches')
    $labels = @('完成分组 / 返回常规 clean', 'Simulators · 仅实体缺失的 Android AVD 登记', 'DerivedData 对应项 · 明确 Flutter 工程的 Windows App 输出', 'Archives 对应项 · 明确工程内逐个 APK / AAB', 'Caches · 下载与着色器缓存')
    $failed = 0
    while ($true) {
        $choice = Read-CleanChoice '选择需要收集的开发组；不选择的组不扫描。' $labels
        if ($choice -eq 0) { return $failed }
        try {
            $project = ''
            if ($groups[$choice] -in @('build-apps', 'archives')) { $project = Select-CleanProject; if (-not $project) { continue } }
            $plan = Get-CleanPlan $Context $groups[$choice] $project
            foreach ($note in $plan.Notes) { Write-CleanMessage ('保留 / 跳过：' + $note) Yellow }
            if (-not $plan.Entries.Count) { Write-CleanMessage '该组没有安全匹配候选。'; continue }
            $selected = @(Select-CleanGroupEntries $plan $command.Source)
            if (-not $selected.Count) { Write-CleanMessage '已取消 / 空选，该组未清理。'; continue }
            $selectedPlan = [pscustomobject]@{ Kind = $plan.Kind; Project = $plan.Project; Entries = $selected; SelectedOnly = $true }
            Write-CleanMessage ('最终范围：' + $selected.Count + ' 项。缓存直接删除；其它项完整备份后移除。') Yellow
            foreach ($entry in $selected) { Write-CleanMessage ('  ' + $entry.Path) }
            Show-CleanDevelopmentConfirmation
            $answer = & $ReadAnswer
            if ($null -eq $answer) { Write-CleanMessage '输入已结束，取消整轮 clean。'; return -1 }
            if ($answer -cne '') { Write-CleanMessage '已取消开发阶段；所选项目未执行，继续常规清理。'; return $failed }
            Initialize-CleanLog $Context
            $failed += Invoke-CleanPlan $selectedPlan $Context
            if ($failed -gt 0) { return $failed }
        } catch [Management.Automation.PipelineStoppedException] { throw }
        catch [OperationCanceledException] { throw }
        catch { $failed++; Write-CleanMessage $_.Exception.Message Red; return $failed }
    }
}
# 不依赖额外 fzf 的原生键盘菜单；默认取消、↑↓/Tab 导航、Enter 选择，危险项需空格确认。
function Read-CleanChoice {
    param([string]$Title, [string[]]$Choices, [switch]$Dangerous, [scriptblock]$ReadKey = { [Console]::ReadKey($true).Key })
    $selected = 0
    Write-CleanPrompt $Title
    Write-CleanMessage '↑/↓ 或 Tab 选择；Esc / ← 取消。普通项回车确认；清理项必须按空格确认。'
    while ($true) {
        Write-Host ('> ' + $Choices[$selected])
        $key = & $ReadKey
        switch ($key) {
            'UpArrow' { $selected = ($selected + $Choices.Count - 1) % $Choices.Count }
            'DownArrow' { $selected = ($selected + 1) % $Choices.Count }
            'Tab' { $selected = ($selected + 1) % $Choices.Count }
            'Escape' { return 0 }
            'LeftArrow' { return 0 }
            'Enter' { if (-not $Dangerous -or $selected -eq 0) { return $selected } }
            'Spacebar' { if ($Dangerous) { return $selected } }
        }
    }
}
# 只请求工程路径，不把任意文件夹或当前启动目录当作可清理工程。
function Select-CleanProject {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object Windows.Forms.FolderBrowserDialog
    $dialog.Description = '选择 Flutter 根工程；仅检查标准 Windows runner 构建 App 输出'
    $dialog.ShowNewFolderButton = $false
    try { if ($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) { return $dialog.SelectedPath }; return '' }
    finally { $dialog.Dispose() }
}
# 终端固定自述独立于 README；交互前只显示，不清理或创建日志。
function Show-CleanIntro {
    Write-CleanMessage 'Jobs clean · Windows 当前用户清理' Red
    Write-CleanMessage '点击磁盘空间只打开本终端；选择类别、核对准确清单并确认后才执行。' Blue
    Write-CleanMessage '常规缓存：仅用户 Temp 中至少7天未改动的直属项目。开发缓存、AVD和构建输出只由前置分组处理，跳过不会在此补清。' Blue
    Write-CleanMessage '候选含工程、依赖或SDK标记、只读内容、重解析点，或安全扫描超出预算时整体保留；不按用户名或目录自定义名称判断。' Blue
    Write-CleanMessage '可恢复项：PSReadLine历史与目标实体已缺失的开发快捷方式。' Blue
    Write-CleanMessage '不执行 macOS 专用 Homebrew/LaunchServices/CoreSimulator；不删依赖/SDK/正常模拟器，不提权，不重启Explorer。' Blue
    Write-CleanMessage '缓存直接删除，不能自动恢复；应用/构建可能重建缓存。请先关闭使用这些缓存或输出的应用与构建。' Yellow
    Write-CleanMessage '开发阶段失败仍进入本常规清理，最后保留未完成结果；EOF / Ctrl+C 立即取消整轮。常规失败后回车仅重试失败项；非空输入或输入结束停止，保留日志与失败结果。' Blue
}
# 独立开发阶段失败仍进入常规清理；取消立即传播，最后汇总两个阶段的未完成项。
function Invoke-CleanInteractiveStages {
    param($Context)
    $failed = 0
    try { $failed = Invoke-CleanDevelopmentStage $Context }
    catch [Management.Automation.PipelineStoppedException] { throw }
    catch [OperationCanceledException] { throw }
    catch { $failed = 1; Write-CleanMessage ('开发阶段未完成：' + $_.Exception.Message + '；继续常规清理。') Red }
    if ($failed -lt 0) { throw (New-Object OperationCanceledException('输入已结束，取消整轮 clean。')) }
    if ($failed -gt 0) { Write-CleanMessage ('开发阶段未完成 ' + $failed + ' 项；继续常规清理，最终仍报告失败。') Yellow }
    Show-CleanIntro
    $kinds = @('', 'cache', 'history', 'shortcuts')
    $labels = @('取消 / 退出', '清理用户临时文件', '备份后清理 PowerShell 历史', '备份后清理失效开发快捷方式')
    while ($true) {
        $choice = Read-CleanChoice '选择本轮清理类别' $labels
        if ($choice -eq 0) { break }
        $project = ''
        if ($kinds[$choice] -eq 'build-apps') { $project = Select-CleanProject; if (-not $project) { continue } }
        try {
            $plan = Get-CleanPlan $context $kinds[$choice] $project
            foreach ($note in $plan.Notes) { Write-CleanMessage ('保留 / 跳过：' + $note) Yellow }
            if (-not $plan.Entries.Count) { Write-CleanMessage '没有安全匹配的候选，未执行清理。'; continue }
            if ($plan.Kind -eq 'cache') {
                $command = Get-Command fzf.exe, fzf -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
                if (-not $command -or -not (Test-CleanFzf $command.Source)) { throw '用户缓存需要已有健康 fzf；未删除，不自动安装。' }
                $selected = @(Select-CleanGroupEntries $plan $command.Source -UserCache)
                if (-not $selected.Count) { Write-CleanMessage '用户缓存未勾选或已跳过，未删除。'; continue }
                $plan = [pscustomobject]@{ Kind = $plan.Kind; Project = $plan.Project; Entries = $selected; SelectedOnly = $true }
            }
            Write-CleanMessage ('准确范围：' + $plan.Entries.Count + ' 项；缓存直接删除，其它项先备份。') Yellow
            foreach ($entry in $plan.Entries) { Write-CleanMessage ('  ' + $entry.Path) }
            if ((Read-CleanChoice '此操作会移除上述项目；默认取消。选择清理后按空格复核。' @('取消本轮', '确认清理上述项目') -Dangerous) -ne 1) { Write-CleanMessage '已取消，未执行本轮清理。'; continue }
            if (-not $script:CleanLog) {
                $script:CleanLog = Join-Path $context.Local ('Jobs/WindowsExtension/extensions/disk-space-info/logs/clean-' + [guid]::NewGuid().ToString('N') + '.log')
                [void](Assert-CleanPath $script:CleanLog $context.Profile)
                [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($script:CleanLog))
                Write-CleanMessage ('日志：' + $script:CleanLog)
            }
            $outcome = Invoke-CleanRegularPlan $plan $context
            $failed += $outcome.Failed
            if ($outcome.Stopped) { break }
        } catch [Management.Automation.PipelineStoppedException] { throw }
        catch [OperationCanceledException] { throw }
        catch { $failed++; Write-CleanMessage $_.Exception.Message Red }
    }
    if ($script:CleanLog) { Write-CleanMessage ('完整日志：' + $script:CleanLog) }
    if ($failed) { throw ('存在未完成清理：' + $failed + ' 项。已完成结果与备份保留。') }
}
# 入口校验平台并建立上下文；Plan 始终只读，交互阶段由同一编排处理。
function Main {
    if ($Mode -eq 'Interactive' -and ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or [Console]::IsInputRedirected -or $Host.Name -ne 'ConsoleHost')) { throw '请在 Windows 独立交互终端中运行；Plan 仅预览，不执行清理。' }
    Set-StrictMode -Version 2.0
    $script:ErrorActionPreference = 'Stop'
    $context = Get-CleanContext
    if ($Mode -eq 'Plan') { return Get-CleanPlan $context $Category $ProjectRoot }
    Invoke-CleanInteractiveStages $context
}
if ($MyInvocation.InvocationName -ne '.') {
    $cleanTerminalState = New-JobsTerminalStyleState
    try { Start-JobsTerminalStyle $cleanTerminalState; Main }
    finally { Stop-JobsTerminalStyle $cleanTerminalState }
}

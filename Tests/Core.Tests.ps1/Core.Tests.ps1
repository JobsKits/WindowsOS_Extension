# Core.Tests.ps1
# WindowsOS@Extension
# Created by Jobs on 2026年10月18日，星期日.

[CmdletBinding()]
param()
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

# JOBS_SOURCE_LAYOUT_ROOT_V1：只解析本文件逻辑目录，发布 flat 副本保持原资源基准。
$script:JobsLayoutCoreTestsRoot = $(if ([IO.Path]::GetFileName($PSScriptRoot) -ceq 'Core.Tests.ps1') { Split-Path -Parent $PSScriptRoot } else { $PSScriptRoot })


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
$ErrorActionPreference = 'Stop'
. (Resolve-JobsScriptLayoutPath (Join-Path ${script:JobsLayoutCoreTestsRoot} 'NativeFixtures.ps1'))
Set-StrictMode -Version Latest
$project = Split-Path -Parent ${script:JobsLayoutCoreTestsRoot}
Import-Module (Join-Path $project 'JobsPathCopier/Scripts/Common.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $project 'Scripts/Catalog.psm1') -Force -DisableNameChecking
$tokens = $null
$errors = $null
$gitAction = [Management.Automation.Language.Parser]::ParseFile((Join-Path $project 'JobsGitRemoteOpener/Scripts/Action.psm1'), [ref]$tokens, [ref]$errors)
if ($errors) { throw ($errors | Out-String) }
# 复制沿用分支/origin 优先级；打开多远端的选择由专项夹具验证。
$copyGitAction = [Management.Automation.Language.Parser]::ParseFile((Join-Path $project 'JobsGitRemoteCopier/Scripts/Action.psm1'), [ref]$tokens, [ref]$errors)
if ($errors) { throw ($errors | Out-String) }
foreach ($definition in @($copyGitAction.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-JobsGitRemote' }, $false)) + @($gitAction.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'ConvertTo-JobsWebUrl' }, $false))) {
    . ([scriptblock]::Create($definition.Extent.Text))
}

$script:assertions = 0
function Assert-Equal {
    param($Actual, $Expected, [string]$Because)
    $script:assertions++
    if ($Actual -cne $Expected) {
        throw ('断言失败：' + $Because + [Environment]::NewLine + '实际：' + $Actual + [Environment]::NewLine + '预期：' + $Expected)
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Because)
    $script:assertions++
    if (-not $Condition) {
        throw ('断言失败：' + $Because)
    }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Because)
    $script:assertions++
    $thrown = $false
    try {
        & $Action | Out-Null
    }
    catch {
        $thrown = $true
    }
    if (-not $thrown) {
        throw ('预期阻止该操作：' + $Because)
    }
}

function Invoke-TestGit {
    param([string[]]$GitArguments)
    $result = Invoke-JobsProcess -FilePath $script:git -Arguments $GitArguments
    if ($result.ExitCode -ne 0) {
        throw ('临时 Git 测试准备失败：' + $result.StdErr)
    }
    return $result.StdOut.Trim()
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("Jobs WindowsExtension [中文] ' & " + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$savedLocalData = [Environment]::GetEnvironmentVariable('LOCALAPPDATA')
try {
    $features = @(Get-JobsFeaturePackages -Root $project)
    $parsedCatalog = Get-Content -LiteralPath (Join-Path (Split-Path -Parent ${script:JobsLayoutCoreTestsRoot}) 'Extensions.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $expectedFeatureCount = @($parsedCatalog).Count
    Assert-Equal $features.Count $expectedFeatureCount '清单内菜单功能均可独立选择'
    Assert-Equal (@($features.Id | Sort-Object -Unique).Count) $expectedFeatureCount '功能标识唯一'
    Assert-True (@($features | Where-Object { $_.DirectoryOnly }).Count -ge 3) '写操作只显示在文件夹上'

    $quoteCases = @(
        @('', '""'),
        @('hello', '"hello"'),
        @('C:\', '"C:\\"'),
        @('C:\directory with spaces\', '"C:\directory with spaces\\"'),
        @('a"b', '"a\"b"'),
        @('a\"b', '"a\\\"b"'),
        @('中文 & $(echo forbidden); %PATH%', '"中文 & $(echo forbidden); %PATH%"')
    )
    foreach ($quoteCase in $quoteCases) {
        Assert-Equal (Quote-JobsArgument -Value $quoteCase[0]) $quoteCase[1] 'Win32 argv 引号与反斜杠'
    }
    Assert-Throws { Quote-JobsArgument -Value ('a' + [char]0 + 'b') } '拒绝 NUL 字符'

    $file = Join-Path $testRoot 'test [1] 中文.txt'
    [IO.File]::WriteAllText($file, 'test')
    $fullRoot = (Get-Item -LiteralPath $testRoot).FullName
    Assert-Equal (Resolve-JobsTarget -Target ($testRoot + '|JobsPathEnd')) $fullRoot '仅去除结尾路径哨兵'
    Assert-Equal (Resolve-JobsTarget -Target $file) (Get-Item -LiteralPath $file).FullName '特殊字符采用 LiteralPath'
    Assert-Equal (Get-JobsDirectory -Target $file) $fullRoot '文件目标使用父目录'
    Assert-Equal (Get-JobsDirectory -Target $testRoot) $fullRoot '目录目标保持自身'
    $volumeRoot = [IO.Path]::GetPathRoot($fullRoot)
    Assert-Equal (Resolve-JobsTarget -Target ($volumeRoot + '|JobsPathEnd')) (Get-Item -LiteralPath $volumeRoot).FullName '盘符根目录及尾部反斜杠保持完整'
    Assert-Equal (Get-JobsDirectory -Target $volumeRoot) (Get-Item -LiteralPath $volumeRoot).FullName '根目录不能退到空父目录'
    Assert-Throws { Resolve-JobsTarget -Target (Join-Path $testRoot 'missing') } '不存在路径停止'
    Assert-Throws { Resolve-JobsTarget -Target ($testRoot + '|JobsPathEnd/extra') } '中间哨兵不被删除'
    if ([IO.Path]::DirectorySeparatorChar -ne [char]92) {
        $literalSentinel = Join-Path $testRoot 'literal|JobsPathEnd-child'
        [void][IO.Directory]::CreateDirectory($literalSentinel)
        Assert-Equal (Resolve-JobsTarget -Target $literalSentinel) $literalSentinel '名称中包含哨兵片段时不改变路径'
    }

    $urlCases = @(
        @('https://github.com/JobsKits/Repo.git', 'https://github.com/JobsKits/Repo'),
        @('https://user:secret@example.com:8443/team/Repo.git', 'https://example.com:8443/team/Repo'),
        @('https://token@example.com:443/team/Repo.git?secret=hidden#private', 'https://example.com:443/team/Repo'),
        @('http://git.example.com:8080/group/Repo.git/', 'http://git.example.com:8080/group/Repo'),
        @('ssh://git@git.example.com:2222/group/Repo.git', 'https://git.example.com/group/Repo'),
        @('git@gitee.com:JobsGo/Repo.git', 'https://gitee.com/JobsGo/Repo'),
        @('git://example.com:9418/group/Repo.git', 'https://example.com/group/Repo'),
        @('git@[2001:db8::1]:group/Repo.git', 'https://[2001:db8::1]/group/Repo'),
        @('git@ssh.dev.azure.com:v3/Jobs/Project/Repo', 'https://dev.azure.com/Jobs/Project/_git/Repo'),
        @('ssh://git@ssh.dev.azure.com:22/v3/Jobs/Project/Repo.git', 'https://dev.azure.com/Jobs/Project/_git/Repo'),
        @('Jobs@vs-ssh.visualstudio.com:v3/Jobs/Project/Repo', 'https://dev.azure.com/Jobs/Project/_git/Repo'),
        @('git@example.com:group/Repo.git?secret=hidden', 'https://example.com/group/Repo')
    )
    foreach ($urlCase in $urlCases) {
        Assert-Equal (ConvertTo-JobsWebUrl -Remote $urlCase[0]) $urlCase[1] '仓库协议转网页并清除凭据'
    }
    foreach ($invalidRemote in @('file:///tmp/repo', 'ext::some-command', 'C:\repo', '/tmp/repo', '../repo', 'ftp://example.com/repo', 'javascript:alert(1)', 'https:example.com/repo', 'git@example.com:', 'https://example.com/')) {
        Assert-Throws { ConvertTo-JobsWebUrl -Remote $invalidRemote } '本地路径及不支持协议不能交给浏览器'
    }

    $powerShell = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    Assert-Equal (Find-JobsExecutable -Name '__jobs_missing_executable__' -Candidates @($powerShell)) $powerShell '程序候选采用真实可执行文件'
    function global:JobsTestFakeApplication { 'not an application' }
    Set-Alias -Name JobsTestFakeAlias -Value $powerShell -Scope Global
    Assert-True ($null -eq (Find-JobsExecutable -Name 'JobsTestFakeApplication')) '不执行同名函数'
    Assert-True ($null -eq (Find-JobsExecutable -Name 'JobsTestFakeAlias')) '不执行同名别名'

    $argumentProbe = New-JobsTestArgumentProbe -Directory $testRoot
    $probeArguments = @('simple', '', 'C:\', 'path with spaces\', 'a"b', 'a\"b', "中文 ' & ; `$() %PATH%", "line1`nline2")
    $roundTrip = Invoke-JobsProcess -FilePath $argumentProbe.Executable -Arguments (@($argumentProbe.Prefix) + $probeArguments) -WorkingDirectory $testRoot
    Assert-Equal $roundTrip.ExitCode 0 '原生子进程正常返回'
    $decoded = $roundTrip.StdOut | ConvertFrom-Json
    $received = @($decoded)
    Assert-Equal $received.Count $probeArguments.Count '参数数量不被 Shell 元字符改变'
    for ($index = 0; $index -lt $probeArguments.Count; $index++) {
        Assert-Equal $received[$index] $probeArguments[$index] '特殊参数真实子进程往返保持一致'
    }

    $streamProbe = Join-Path $testRoot 'probe streams.ps1'
    [IO.File]::WriteAllText($streamProbe, "[Console]::Out.Write(('O' * 262144)); [Console]::Error.Write(('E' * 262144)); exit 7")
    $streams = Invoke-JobsProcess -FilePath $powerShell -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $streamProbe)
    Assert-Equal $streams.ExitCode 7 '非零退出码保留'
    Assert-Equal $streams.StdOut.Length 262144 '大量标准输出不死锁'
    Assert-Equal $streams.StdErr.Length 262144 '大量标准错误不死锁'

    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    Assert-Throws { Invoke-JobsProcess -FilePath $powerShell -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 15') -TimeoutSeconds 1 } '超时停止本次子进程'
    Assert-True ($stopwatch.Elapsed.TotalSeconds -lt 12) '超时后能够按时返回'

    $childProbe = Join-Path $testRoot 'probe descendant.ps1'
    $parentProbe = Join-Path $testRoot 'probe parent.ps1'
    $childHeartbeat = Join-Path $testRoot 'child heartbeat.txt'
    $childPidFile = Join-Path $testRoot 'child pid.txt'
    [IO.File]::WriteAllText($childProbe, 'while ($true) { [IO.File]::AppendAllText($args[0], "."); Start-Sleep -Milliseconds 100 }')
    $parentSource = @'
$start = New-Object Diagnostics.ProcessStartInfo
$start.FileName = $args[0]
$start.Arguments = $args[1]
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$child = [Diagnostics.Process]::Start($start)
[IO.File]::WriteAllText($args[2], $child.Id.ToString())
Start-Sleep -Seconds 30
'@
    [IO.File]::WriteAllText($parentProbe, $parentSource)
    $childArguments = (@('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $childProbe, $childHeartbeat) | ForEach-Object { Quote-JobsArgument $_ }) -join ' '
    try {
        Assert-Throws { Invoke-JobsProcess -FilePath $powerShell -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $parentProbe, $powerShell, $childArguments, $childPidFile) -TimeoutSeconds 3 } '超时停止本次父进程及派生子进程'
        Assert-True ([IO.File]::Exists($childPidFile) -and [IO.File]::Exists($childHeartbeat)) '测试父进程实际派生了持续运行的子进程'
        $heartbeatLength = [IO.File]::ReadAllText($childHeartbeat).Length
        Start-Sleep -Milliseconds 700
        Assert-Equal ([IO.File]::ReadAllText($childHeartbeat).Length) $heartbeatLength '父进程超时后派生子进程不再执行工作'
    }
    finally {
        if ([IO.File]::Exists($childPidFile)) {
            $testChildId = [int][IO.File]::ReadAllText($childPidFile)
            $testChild = $null
            try {
                $testChild = [Diagnostics.Process]::GetProcessById($testChildId)
                if (-not $testChild.HasExited) {
                    $testChild.Kill()
                }
            }
            catch {
                # 正常清理路径中，测试子进程已由超时处理结束。
            }
            finally {
                if ($null -ne $testChild) { $testChild.Dispose() }
            }
        }
    }

    $script:git = Find-JobsExecutable -Name 'git'
    Assert-True (-not [string]::IsNullOrWhiteSpace($script:git)) 'Git 集成测试需要 Git'
    $repository = Join-Path $testRoot 'repository [git] 中文'
    [void](Invoke-TestGit @('init', '-q', $repository))
    [void](Invoke-TestGit @('-C', $repository, '-c', 'user.name=Jobs Test', '-c', 'user.email=jobs-test@example.invalid', 'commit', '--allow-empty', '-m', 'test seed'))
    $branchName = Invoke-TestGit @('-C', $repository, 'symbolic-ref', '--short', 'HEAD')
    [void](Invoke-TestGit @('-C', $repository, 'remote', 'add', 'origin', 'git@example.com:team/origin.git'))
    Assert-Equal (Get-JobsGitRemote -Directory $repository) 'git@example.com:team/origin.git' '默认使用 origin 原始地址'
    [void](Invoke-TestGit @('-C', $repository, 'config', 'url.https://mirror.example.invalid/.insteadOf', 'git@example.com:'))
    Assert-Equal (Invoke-TestGit @('-C', $repository, 'remote', 'get-url', 'origin')) 'https://mirror.example.invalid/team/origin.git' '测试配置实际触发了 Git insteadOf 地址重写'
    Assert-Equal (Get-JobsGitRemote -Directory $repository) 'git@example.com:team/origin.git' '复制保留配置原始 scp 地址而不应用 insteadOf'
    [void](Invoke-TestGit @('-C', $repository, 'config', '--add', 'remote.origin.url', 'https://example.com/team/fallback.git'))
    Assert-Equal (Get-JobsGitRemote -Directory $repository) 'git@example.com:team/origin.git' '多条 URL 明确采用第一条配置原值'
    $nestedDirectory = Join-Path $repository 'nested'
    [void][IO.Directory]::CreateDirectory($nestedDirectory)
    Assert-Equal (Get-JobsGitRemote -Directory $nestedDirectory) 'git@example.com:team/origin.git' '工作树内子目录自动定位仓库'
    [void](Invoke-TestGit @('-C', $repository, 'remote', 'add', 'upstream', 'https://example.com/team/upstream.git'))
    [void](Invoke-TestGit @('-C', $repository, 'config', ('branch.' + $branchName + '.remote'), 'upstream'))
    Assert-Equal (Get-JobsGitRemote -Directory $repository) 'https://example.com/team/upstream.git' '当前分支远端优先于 origin'
    [void](Invoke-TestGit @('-C', $repository, 'config', '--unset', ('branch.' + $branchName + '.remote')))
    $worktree = Join-Path $testRoot 'linked worktree [中文]'
    [void](Invoke-TestGit @('-C', $repository, 'worktree', 'add', '--detach', $worktree))
    Assert-True (Test-Path -LiteralPath (Join-Path $worktree '.git') -PathType Leaf) 'worktree 使用 .git 指针文件'
    Assert-Equal (Get-JobsGitRemote -Directory $worktree) 'git@example.com:team/origin.git' '工作树指针由 Git 自行解析'
    [void](Invoke-TestGit @('-C', $repository, 'remote', 'remove', 'origin'))
    Assert-Equal (Get-JobsGitRemote -Directory $repository) 'https://example.com/team/upstream.git' '无 origin 时采用唯一远端'
    [void](Invoke-TestGit @('-C', $repository, 'remote', 'add', 'another', 'https://example.com/team/another.git'))
    Assert-Throws { Get-JobsGitRemote -Directory $repository } '多个远端无 origin 且无分支配置时停止'
    [void](Invoke-TestGit @('-C', $repository, 'remote', 'remove', 'upstream'))
    [void](Invoke-TestGit @('-C', $repository, 'remote', 'remove', 'another'))
    Assert-Throws { Get-JobsGitRemote -Directory $repository } '无远端时停止'
    Assert-Throws { Get-JobsGitRemote -Directory $testRoot } '非 Git 工作树时停止'
    $bare = Join-Path $testRoot 'bare.git'
    [void](Invoke-TestGit @('init', '--bare', '-q', $bare))
    Assert-Throws { Get-JobsGitRemote -Directory $bare } '裸仓库没有工作树不提供菜单动作'

    # 打开功能单独验证；浏览器和控制台调度均被拦截，不触碰桌面。
    $openerModule = Import-Module (Join-Path $project 'JobsGitRemoteOpener/Scripts/Action.psm1') -PassThru -DisableNameChecking
    try {
        & $openerModule {
            $script:OpenedUrl = $null
            $script:DispatchedDirectory = $null
            $script:Selection = 'alpha'
            $script:SelectionCalls = 0
            function script:Start-Process { param($FilePath) $script:OpenedUrl = $FilePath }
            function script:Start-JobsGitRemoteSelector { param($Directory) $script:DispatchedDirectory = $Directory }
            function script:Select-JobsGitRemoteName { param($Git, $Directory, $Remotes) $script:SelectionCalls++; return $script:Selection }
        }
        [void](Invoke-TestGit @('-C', $repository, 'remote', 'add', 'alpha', 'git@example.com:team/alpha.git'))
        & $openerModule { param($Path) Invoke-JobsFeature -Target $Path } $repository
        Assert-Equal (& $openerModule { $script:OpenedUrl }) 'https://example.com/team/alpha' '唯一远端直接打开且不套用 insteadOf'
        Assert-Equal (& $openerModule { $script:SelectionCalls }) 0 '唯一远端不依赖 fzf'
        [void](Invoke-TestGit @('-C', $repository, 'remote', 'add', 'origin', 'https://example.com/team/origin.git'))
        [void](Invoke-TestGit @('-C', $repository, 'config', ('branch.' + $branchName + '.remote'), 'origin'))
        $configurationBefore = [IO.File]::ReadAllText((Join-Path $repository '.git/config'))
        & $openerModule { param($Path) $script:OpenedUrl = $null; Invoke-JobsFeature -Target $Path } $repository
        Assert-Equal (& $openerModule { $script:DispatchedDirectory }) $repository '多远端隐藏入口转交本包可见控制台'
        Assert-True ($null -eq (& $openerModule { $script:OpenedUrl })) '控制台调度未打开默认远端'
        & $openerModule { param($Path) Invoke-JobsFeature -Target $Path -Interactive } $repository
        Assert-Equal (& $openerModule { $script:OpenedUrl }) 'https://example.com/team/alpha' '多远端遵从选择而不自动采用 origin 或跟踪远端'
        Assert-Equal (& $openerModule { $script:SelectionCalls }) 1 '多远端进入选择器'
        & $openerModule { param($Path) $script:OpenedUrl = $null; $script:Selection = $null; Invoke-JobsFeature -Target $Path -Interactive } $repository
        Assert-True ($null -eq (& $openerModule { $script:OpenedUrl })) '取消选择不打开浏览器'
        & $openerModule { function script:Select-JobsGitRemoteName { param($Git, $Directory, $Remotes) throw 'isolated selector failure' } }
        Assert-Throws { & $openerModule { param($Path) Invoke-JobsFeature -Target $Path -Interactive } $repository } '选择器失败明确返回错误'
        Assert-True ($null -eq (& $openerModule { $script:OpenedUrl })) '选择器失败不回退默认远端'
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $repository '.git/config'))) $configurationBefore '打开和取消均不改仓库配置'
        [void](Invoke-TestGit @('-C', $repository, 'remote', 'remove', 'alpha'))
        [void](Invoke-TestGit @('-C', $repository, 'remote', 'remove', 'origin'))
        Assert-Throws { & $openerModule { param($Path) Invoke-JobsFeature -Target $Path } $repository } '打开功能无远端时停止'
    }
    finally { Remove-Module $openerModule }

    $submoduleSource = Join-Path $testRoot 'submodule source'
    [void](Invoke-TestGit @('init', '-q', $submoduleSource))
    [void](Invoke-TestGit @('-C', $submoduleSource, '-c', 'user.name=Jobs Test', '-c', 'user.email=jobs-test@example.invalid', '-c', 'commit.gpgsign=false', 'commit', '--allow-empty', '-m', 'submodule seed'))
    [void](Invoke-TestGit @('-C', $repository, '-c', 'protocol.file.allow=always', 'submodule', 'add', $submoduleSource, 'dependencies/source'))
    $submodule = Join-Path (Join-Path $repository 'dependencies') 'source'
    [void](Invoke-TestGit @('-C', $submodule, 'remote', 'set-url', 'origin', 'git@example.com:team/submodule.git'))
    Assert-True (Test-Path -LiteralPath (Join-Path $submodule '.git') -PathType Leaf) '子模块使用 .git 指针文件'
    Assert-Equal (Get-JobsGitRemote -Directory $submodule) 'git@example.com:team/submodule.git' '子模块读取自身远端而非父仓远端'

    [Environment]::SetEnvironmentVariable('LOCALAPPDATA', (Join-Path $testRoot 'local app data'))
    Assert-Equal (Get-JobsInstallRoot) (Join-Path (Join-Path (Join-Path $testRoot 'local app data') 'Jobs/WindowsExtension/extensions') 'copy-path') '安装目录限定当前用户与本功能'
    Write-JobsLog -Message '测试状态；https://user:password@example.invalid/private；C:\secret\private'
    $log = Get-ChildItem -LiteralPath (Join-Path (Get-JobsInstallRoot) 'logs') -File | Select-Object -First 1
    $logContent = [IO.File]::ReadAllText($log.FullName)
    Assert-True (-not $logContent.Contains('password') -and -not $logContent.Contains('C:\secret')) '日志不保留误传凭据或路径'

    Write-Host ('通过：' + $script:assertions + ' 项核心断言（参数、路径、协议、子进程、真实 Git/worktree、日志）。')
}
finally {
    [Environment]::SetEnvironmentVariable('LOCALAPPDATA', $savedLocalData)
    Remove-Item -LiteralPath 'Function:\JobsTestFakeApplication' -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath 'Alias:\JobsTestFakeAlias' -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

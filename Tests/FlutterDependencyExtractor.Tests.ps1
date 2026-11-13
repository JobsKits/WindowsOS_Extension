# FlutterDependencyExtractor.Tests.ps1 | 临时夹具与参数边界
# Created by Jobs on 2026年10月19日，星期一.
# 不运行菜单安装器、不写注册表、不联网、不修改真实 Flutter 项目。
[CmdletBinding()]
param()
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
. (Join-Path $PSScriptRoot 'NativeFixtures.ps1')
$script:assertions = 0
function Assert-Extractor {
    param([bool]$Condition, [string]$Message)
    $script:assertions++
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
}
function Assert-ExtractorThrows {
    param([scriptblock]$Action, [string]$Message)
    $threw = $false
    try { & $Action | Out-Null } catch { $threw = $true }
    Assert-Extractor $threw $Message
}
$root = Split-Path -Parent $PSScriptRoot
$testParent = [IO.Path]::GetTempPath()
if ([IO.Directory]::Exists('/private/tmp')) { $testParent = '/private/tmp' }
$temporary = Join-Path $testParent ("Jobs Extract [中文] & 100% ! ' " + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$savedLocal = $env:LOCALAPPDATA
$module = $null
try {
    $env:LOCALAPPDATA = Join-Path $temporary 'State'
    $standalone = Join-Path $temporary 'JobsFlutterDependencyExtractor'
    Copy-Item -LiteralPath (Join-Path $root 'JobsFlutterDependencyExtractor') -Destination $standalone -Recurse
    $module = Import-Module (Join-Path $standalone 'Scripts/Action.psm1') -PassThru -DisableNameChecking
    $project = Join-Path $temporary "Flutter 工程 & 100% ! '"
    [void][IO.Directory]::CreateDirectory($project)
    $good = "name: app`ndependencies:`n  flutter:`n    sdk: flutter`n"
    $cases = @(
        @{ Text = $good; Good = $true },
        @{ Text = 'dependencies: {flutter: {sdk: flutter}}'; Good = $true },
        @{ Text = "'dependencies':`n  'flutter':`n    'sdk': 'flutter' # 尾注释"; Good = $true },
        @{ Text = "dev_dependencies:`n  flutter_test:`n    sdk: flutter"; Good = $false },
        @{ Text = "description: |`n  dependencies:`n    flutter:`n      sdk: flutter"; Good = $false },
        @{ Text = "# dependencies:`n#   flutter:`n#     sdk: flutter"; Good = $false },
        @{ Text = "dependencies:`n  flutter:`n    path: ../flutter`n  other:`n    sdk: flutter"; Good = $false },
        @{ Text = "dependencies:`n  flutter:`n    nested:`n      sdk: flutter"; Good = $false },
        @{ Text = 'dependencies: {flutter: {sdk: flutter}, flutter: {sdk: other}}'; Good = $false },
        @{ Text = "dependencies:`n  flutter: *alias"; Good = $false }
    )
    foreach ($case in $cases) {
        Assert-Extractor ((& $module { param($Text) Test-JobsFlutterPubspec $Text } $case.Text) -eq $case.Good) 'Flutter 根清单真实声明和伪装区分'
    }
    [IO.File]::WriteAllText((Join-Path $project 'pubspec.yaml'), $good)
    & $module { param($Path) Assert-JobsFlutterProject $Path } $project
    Assert-ExtractorThrows { & $module { param($Path) Assert-JobsFlutterProject $Path } $temporary } '不沿父子目录猜测 Flutter 项目'
    Assert-ExtractorThrows { & $module { Assert-JobsExtractorDirectory 'relative' } } '项目必须绝对路径'
    Assert-Extractor ((& $module { param($Default) ConvertFrom-JobsExtractorPathInput '' $Default } $temporary) -eq $temporary) '空行精确采用传入的系统桌面默认值'
    Assert-Extractor ((& $module { param($Path) ConvertFrom-JobsExtractorPathInput ('"' + $Path + '"') 'unused' } $project) -eq $project) '双引号拖入路径'
    Assert-Extractor ((& $module { param($Path) ConvertFrom-JobsExtractorPathInput ("& '" + $Path.Replace("'", "''") + "'") 'unused' } $project) -eq $project) '单引号拖入只解外层表示，保留单引号'
    Assert-ExtractorThrows { & $module { ConvertFrom-JobsExtractorPathInput 'Get-ChildItem; whoami' 'unused' } } '命令文本不能作为输出路径执行'
    Assert-ExtractorThrows { & $module { ConvertFrom-JobsExtractorPathInput "`n" 'unused' } } '控制字符拒绝'
    $safe = & $module { ConvertTo-JobsExtractorSafeMessage 'https://user:pass@example.invalid/pkg?token=SECRET password=HIDDEN' }
    Assert-Extractor ($safe -notmatch 'user:pass|SECRET|HIDDEN') '终端与日志地址凭据脱敏'
    # SDK 原生路径发现兼容项目 FVM 和 package_config 指向的 IDE SDK。
    $sdk = Join-Path $temporary 'IDE Flutter SDK'
    [void][IO.Directory]::CreateDirectory((Join-Path $sdk 'packages/flutter'))
    [void][IO.Directory]::CreateDirectory((Join-Path $project '.dart_tool'))
    $sdkUri = (New-Object Uri ((Join-Path $sdk 'packages/flutter') + [IO.Path]::DirectorySeparatorChar)).AbsoluteUri
    @{ configVersion = 2; packages = @(@{ name = 'flutter'; rootUri = $sdkUri }) } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $project '.dart_tool/package_config.json') -Encoding UTF8
    $candidates = @(& $module { param($Path) Get-JobsExtractorDartCandidates $Path } $project)
    Assert-Extractor ($candidates[0] -ceq (Join-Path $project '.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dart.exe')) '项目 FVM SDK 先于全局 SDK'
    Assert-Extractor ((Join-Path $sdk 'bin/cache/dart-sdk/bin/dart.exe') -in $candidates) 'IDE 独立 SDK 可由包配置定位'
    $brokenDart = Join-Path $temporary 'broken-dart.exe'
    $healthyDart = Join-Path $temporary 'healthy-dart.exe'
    $spoof = Join-Path $temporary 'renamed-script.exe'
    [IO.File]::WriteAllText($spoof, '@echo off')
    Assert-Extractor (-not (& $module { param($Path) Test-JobsExtractorNativeExecutable $Path } $spoof)) '重命名脚本不能冒充原生 PE 程序'
    $pe = New-Object byte[] 128
    $pe[0] = 0x4D; $pe[1] = 0x5A; $pe[0x3C] = 0x40
    $pe[0x40] = 0x50; $pe[0x41] = 0x45; $pe[0x44] = 0x64; $pe[0x45] = 0x86
    [IO.File]::WriteAllBytes($brokenDart, $pe)
    [IO.File]::WriteAllBytes($healthyDart, $pe)
    Assert-Extractor (& $module { param($Path) Test-JobsExtractorNativeExecutable $Path } $healthyDart) 'PE 签名和机器类型通过后才允许版本体检'
    $chosen = & $module {
        param($Project, $Broken, $Healthy)
        $script:ProbeCandidates = @($Broken, $Healthy)
        function script:Get-JobsExtractorDartCandidates { param($Directory) return $script:ProbeCandidates }
        function script:Invoke-JobsProcess {
            param($FilePath, $Arguments, $WorkingDirectory, $TimeoutSeconds)
            if ($Arguments.Count -ne 1 -or $Arguments[0] -cne '--version') { throw '体检只允许 --version' }
            if ($FilePath -eq $script:ProbeCandidates[0]) { return [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = 'broken' } }
            return [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = 'Dart SDK version: 3.9.0 (stable)' }
        }
        Find-JobsExtractorDart $Project
    } $project $brokenDart $healthyDart
    Assert-Extractor ($chosen -ceq $healthyDart) '损坏工具跳过，复用下一个健康原生 Dart'
    & $module { $script:ProbeCandidates = @() }
    Assert-ExtractorThrows { & $module { param($Path) Find-JobsExtractorDart $Path } $project } '缺健康 Dart 明确停止不安装'
    # 取消是行为边界，不能创建日志、探测工具或写项目。
    $canceled = & $module {
        param($Path)
        function script:Show-JobsExtractorIntro { return $false }
        function script:Find-JobsExtractorDart { throw '取消后不应探测 Dart' }
        Invoke-JobsFlutterDependencyAction $Path
    } $project
    Assert-Extractor (-not (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Jobs'))) '首屏取消不创建业务状态'
    # 无解析记录先停止，不弹出目标路径输入或调用提取引擎。
    & $module {
        function script:Show-JobsExtractorIntro { return $true }
        function script:Read-Host { param($Prompt) throw '缺记录时不应请求输出目录' }
    }
    Assert-ExtractorThrows { & $module { param($Path) Invoke-JobsFlutterDependencyAction $Path } $project } '缺少 lock/config 时停止'
    [IO.File]::WriteAllText((Join-Path $project 'pubspec.lock'), "packages: {}`n")
    [void][IO.Directory]::CreateDirectory((Join-Path $project '.dart_tool'))
    [IO.File]::WriteAllText((Join-Path $project '.dart_tool/package_config.json'), '{"configVersion":2,"packages":[]}')
    $recorded = & $module {
        param($Project, $Destination)
        function script:Get-JobsExtractorDesktop { return $script:TestDestination }
        function script:Read-Host { param($Prompt) return '' }
        function script:Find-JobsExtractorDart { param($Directory) return 'dart-native.exe' }
        function script:Invoke-JobsProcess {
            param($FilePath, $Arguments, $WorkingDirectory, $TimeoutSeconds)
            $script:Captured = [pscustomobject]@{ File = $FilePath; Arguments = @($Arguments); WorkingDirectory = $WorkingDirectory }
            return [pscustomobject]@{ ExitCode = 0; StdOut = 'fixture complete'; StdErr = '' }
        }
        $script:TestDestination = $Destination
        Invoke-JobsFlutterDependencyAction $Project
        return $script:Captured
    } $project $temporary
    Assert-Extractor ($recorded.File -ceq 'dart-native.exe') '引擎用原生 Dart 调用'
    Assert-Extractor ($recorded.Arguments.Count -eq 5 -and $recorded.Arguments[1] -ceq '--project' -and $recorded.Arguments[2] -ceq $project -and $recorded.Arguments[3] -ceq '--destination' -and $recorded.Arguments[4] -ceq $temporary) '项目与输出各自原样作为独立 argv，默认桌面生效'
    Assert-Extractor ($recorded.WorkingDirectory -ceq $project) '提取引擎工作目录精确到所选项目'
    & $module {
        function script:Invoke-JobsProcess {
            param($FilePath, $Arguments, $WorkingDirectory, $TimeoutSeconds)
            return [pscustomobject]@{ ExitCode = 4; StdOut = ''; StdErr = 'fixture failure' }
        }
    }
    Assert-ExtractorThrows { & $module { param($Path) Invoke-JobsFlutterDependencyAction $Path } $project } '引擎非零退出不能报告成功'
    # 独立安装 release 必须携带真正的 Dart 源码，而非只复制 PowerShell 入口。
    $installer = Import-Module (Join-Path $standalone 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
    $release = Join-Path $temporary 'release'
    & $installer { param($Path, $Destination) New-JobsPackageRelease -PackagePath $Path -Destination $Destination } $standalone $release | Out-Null
    $engine = Join-Path $release 'Scripts/ExtractFlutterDependencies.dart'
    Assert-Extractor (Test-Path -LiteralPath $engine -PathType Leaf) '独立 release 含 Dart 引擎'
    Assert-Extractor ((Get-FileHash -LiteralPath $engine).Hash -ceq (Get-FileHash -LiteralPath (Join-Path $standalone 'Scripts/ExtractFlutterDependencies.dart')).Hash) '部署引擎逐字节一致'
    # 使用真实原生进程回传参数，验证 Common argv 遇中文、空格、引号和 Shell 符号仍是数据。
    $argvProbe = New-JobsTestArgumentProbe -Directory $temporary
    $common = Import-Module (Join-Path $standalone 'Scripts/Common.psm1') -PassThru -DisableNameChecking
    $special = @($project, (Join-Path $temporary 'a"b'), '--destination', (Join-Path $temporary '$(whoami); & %PATH% !'))
    $native = & $common { param($Probe, $Values, $Directory) Invoke-JobsProcess -FilePath $Probe.Executable -Arguments (@($Probe.Prefix) + $Values) -WorkingDirectory $Directory } $argvProbe $special $temporary
    Assert-Extractor ($native.ExitCode -eq 0) '真实原生进程回传成功'
    # 5.1 把 JSON 数组作为一个管道对象输出，先赋值再枚举真实参数。
    $decoded = $native.StdOut | ConvertFrom-Json
    $actual = @($decoded)
    Assert-Extractor ($actual.Count -eq $special.Count) ('原生参数数量保持：实际 {0}，预期 {1}' -f $actual.Count, $special.Count)
    for ($i = 0; $i -lt $special.Count; $i++) { Assert-Extractor ($actual[$i] -ceq $special[$i]) '特殊字符未经 Shell 展开'
    }
    Write-Host ('PASS: FlutterDependencyExtractor.Tests.ps1 (' + $script:assertions + ' assertions)')
} finally {
    if ($null -ne $module) { Remove-Module $module }
    foreach ($loaded in @(Get-Module | Where-Object { $_.Path -and $_.Path.StartsWith($temporary, [StringComparison]::OrdinalIgnoreCase) })) { Remove-Module $loaded }
    $env:LOCALAPPDATA = $savedLocal
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

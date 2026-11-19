# FlutterVersionMgr.Tests.ps1
# WindowsOS@Extension
# Created by Jobs on 2026年10月19日，星期一.
# 全部业务操作为隔离夹具，不运行真实 FVM、WinGet 或网络下载。

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
$script:JobsLayoutFlutterVersionMgrTestsRoot = $(if ([IO.Path]::GetFileName($PSScriptRoot) -ceq 'FlutterVersionMgr.Tests.ps1') { Split-Path -Parent $PSScriptRoot } else { $PSScriptRoot })

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
. (Resolve-JobsScriptLayoutPath (Join-Path ${script:JobsLayoutFlutterVersionMgrTestsRoot} 'NativeFixtures.ps1'))
$script:assertions = 0
function Assert-Fvm {
    param([bool]$Condition, [string]$Message)
    $script:assertions++
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
}
function Assert-FvmThrows {
    param([scriptblock]$Action, [string]$Message)
    $threw = $false
    try { & $Action | Out-Null } catch { $threw = $true }
    Assert-Fvm $threw $Message
}

$root = Split-Path -Parent ${script:JobsLayoutFlutterVersionMgrTestsRoot}
$testParent = [IO.Path]::GetTempPath()
if ([IO.Directory]::Exists('/private/tmp')) { $testParent = '/private/tmp' }
$temporary = Join-Path $testParent ("JobsFvm [中文] & 100% ' " + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$savedLocal = $env:LOCALAPPDATA
$module = $null
try {
    $env:LOCALAPPDATA = Join-Path $temporary 'UserData'
    $standalone = Join-Path $temporary 'JobsFlutterVersionMgr'
    Copy-Item -LiteralPath (Join-Path $root 'JobsFlutterVersionMgr') -Destination $standalone -Recurse
    $module = Import-Module (Join-Path $standalone 'Scripts/Action.psm1') -PassThru -DisableNameChecking
    $cases = @(
        @{ Text = "name: app`ndependencies:`n  flutter:`n    sdk: flutter`n"; Good = $true; Name = '常见 block 项目' },
        @{ Text = "dependencies:`n  flutter: {sdk: flutter}`n  cupertino_icons: ^1.0.0"; Good = $true; Name = 'flutter inline' },
        @{ Text = 'dependencies: {flutter: {sdk: flutter}, collection: ^1.0.0}'; Good = $true; Name = 'dependencies inline' },
        @{ Text = 'DEPENDENCIES: {FLUTTER: {SDK: flutter}}'; Good = $false; Name = 'YAML 根键区分大小写' },
        @{ Text = 'dependencies: {FLUTTER: {sdk: flutter}}'; Good = $false; Name = 'YAML flow flutter 键区分大小写' },
        @{ Text = 'dependencies: {flutter: {SDK: flutter}}'; Good = $false; Name = 'YAML flow sdk 键区分大小写' },
        @{ Text = 'dependencies: {flutter: {sdk:flutter}}'; Good = $false; Name = '无空格纯量并非 sdk 映射' },
        @{ Text = "'dependencies':`n  'flutter':`n    'sdk': 'flutter' # 正常注释"; Good = $true; Name = '引用键和值及尾注释' },
        @{ Text = "description: 'sdk: flutter # merely text'`ndependencies:`n  flutter:`n    sdk: flutter"; Good = $true; Name = '描述中含井号不影响真实依赖' },
        @{ Text = "name: dart_app`nenvironment:`n  sdk: ^3.0.0"; Good = $false; Name = '纯 Dart' },
        @{ Text = "# dependencies:`n#   flutter:`n#     sdk: flutter"; Good = $false; Name = '注释伪装' },
        @{ Text = "description: |`n  dependencies:`n    flutter:`n      sdk: flutter"; Good = $false; Name = 'description 标量伪装' },
        @{ Text = "dev_dependencies:`n  flutter_test:`n    sdk: flutter"; Good = $false; Name = '仅 flutter_test' },
        @{ Text = "dependencies:`n  flutter_test:`n    sdk: flutter"; Good = $false; Name = 'dependencies 仅 flutter_test' },
        @{ Text = "dependencies:`n  flutter:`n    path: ../flutter`n  other:`n    sdk: flutter"; Good = $false; Name = '其它依赖 sdk 不得串入' },
        @{ Text = "dependencies:`n  flutter:`n    description: |`n      sdk: flutter"; Good = $false; Name = 'flutter 描述标量伪装' },
        @{ Text = "dependencies:`n  flutter:`n    nested:`n      sdk: flutter"; Good = $false; Name = '嵌套 sdk 伪装' },
        @{ Text = "dependencies:`n  flutter:`n    sdk: flutter`n    sdk: other"; Good = $false; Name = '重复 sdk' },
        @{ Text = "dependencies:`n  flutter:`n    sdk: flutter`ndependencies: {}"; Good = $false; Name = '重复根 dependencies' },
        @{ Text = 'dependencies: {flutter: {sdk: flutter}, flutter: {sdk: other}}'; Good = $false; Name = '重复 flow flutter' },
        @{ Text = "dependencies:`n  flutter: *flutter_dependency"; Good = $false; Name = '未解释 YAML 别名安全拒绝' },
        @{ Text = "dependencies:`n`tflutter:`n`t  sdk: flutter"; Good = $false; Name = 'Tab 缩进拒绝' }
    )
    foreach ($case in $cases) {
        $actual = & $module { param($Text) Test-JobsFlutterPubspec $Text } $case.Text
        Assert-Fvm ($actual -eq $case.Good) ('pubspec：' + $case.Name)
    }
    $project = Join-Path $temporary 'parent/app'
    [void][IO.Directory]::CreateDirectory($project)
    $pubspec = Join-Path $project 'pubspec.yaml'
    [IO.File]::WriteAllText($pubspec, "name: app`ndependencies:`n  flutter:`n    sdk: flutter`n")
    $parentConfig = Join-Path (Split-Path -Parent $project) '.fvmrc'
    [IO.File]::WriteAllText($parentConfig, '{"flutter":"3.16.0","keep":"parent"}')
    $melos = Join-Path (Split-Path -Parent $project) 'melos.yaml'
    [IO.File]::WriteAllText($melos, 'sdkPath: old-parent-path')
    $inspection = & $module { param($Project) New-JobsFvmInspection $Project } $project
    $shadowConfig = Get-Content -LiteralPath (Join-Path $inspection '.fvmrc') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Fvm ($null -eq $shadowConfig.PSObject.Properties['flutter']) '未绑定子项目使用独立空影子配置，不能继承父版本'
    Assert-Fvm ([IO.File]::ReadAllText((Join-Path $inspection 'pubspec.yaml')) -ceq [IO.File]::ReadAllText($pubspec)) '影子体检使用目标pubspec原文'
    Remove-Item -LiteralPath $inspection -Recurse -Force
    & $module { param($Project) Assert-JobsFlutterProject $Project } $project
    Assert-Fvm $true 'Flutter 项目不要求已有 SDK 或 lib 目录'
    Assert-FvmThrows { & $module { param($Project) Assert-JobsFlutterProject $Project } (Split-Path -Parent $project) } '不递归发现子工程'
    & $module {
        function script:Get-JobsFvmToolchain { param($Directory) throw '不应触发工具链' }
    }
    Assert-FvmThrows { & $module { param($Project) Invoke-JobsFlutterVersionAction $Project } (Split-Path -Parent $project) } '非法项目在任何工具体检前阻断'
    $beforeParent = [IO.File]::ReadAllBytes($parentConfig)
    $beforeMelos = [IO.File]::ReadAllBytes($melos)
    & $module { param($Project) Set-JobsProjectFvmVersion $Project '3.19.0' } $project
    $config = Get-Content -LiteralPath (Join-Path $project '.fvmrc') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Fvm ($config.flutter -ceq '3.19.0' -and $config.updateMelosSettings -eq $false) '精确根配置且关闭向父 Melos 传播'
    $config | Add-Member -NotePropertyName 'flavors' -NotePropertyValue @{ staging = '3.16.0' }
    $config | Add-Member -NotePropertyName 'custom' -NotePropertyValue @{ nested = @{ keep = 'retained' } }
    [IO.File]::WriteAllText((Join-Path $project '.fvmrc'), ($config | ConvertTo-Json -Depth 8))
    & $module { param($Project) Set-JobsProjectFvmVersion $Project '3.22.0' } $project
    $afterConfig = Get-Content -LiteralPath (Join-Path $project '.fvmrc') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Fvm ($afterConfig.flavors.staging -ceq '3.16.0' -and $afterConfig.custom.nested.keep -ceq 'retained') '切换保留既有配置字段'
    Assert-Fvm ([Convert]::ToBase64String([IO.File]::ReadAllBytes($parentConfig)) -ceq [Convert]::ToBase64String($beforeParent)) '父 .fvmrc 字节保持'
    Assert-Fvm ([Convert]::ToBase64String([IO.File]::ReadAllBytes($melos)) -ceq [Convert]::ToBase64String($beforeMelos)) '父 melos.yaml 字节保持'
    Assert-FvmThrows { & $module { param($Project) Set-JobsProjectFvmVersion $Project 'stable' } $project } '禁止把浮动渠道当指定版本'
    Assert-FvmThrows { & $module { param($Project) Set-JobsProjectFvmVersion $Project '3.19.0 & whoami' } $project } '版本参数注入拒绝'
    Assert-Fvm (& $module { Test-JobsFlutterVersion '1.12.13+hotfix.9' }) '官方旧 hotfix 具体版本保留'
    $legacyProject = Join-Path $temporary 'legacy'
    [void][IO.Directory]::CreateDirectory((Join-Path $legacyProject '.fvm'))
    [IO.File]::WriteAllText((Join-Path $legacyProject '.fvm/fvm_config.json'), '{"flutterSdkVersion":"3.16.0","flavors":{"dev":"3.10.0"},"cachePath":"custom-cache","flutterUrl":"custom-url","updateVscodeSettings":false}')
    & $module { param($Project) Set-JobsProjectFvmVersion $Project '3.22.0' } $legacyProject
    $legacyMigrated = Get-Content -LiteralPath (Join-Path $legacyProject '.fvmrc') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Fvm ($legacyMigrated.flutter -ceq '3.22.0' -and $null -eq $legacyMigrated.PSObject.Properties['flutterSdkVersion']) '旧flutterSdkVersion迁移且不覆盖新选择'
    Assert-Fvm ($legacyMigrated.flavors.dev -ceq '3.10.0' -and $legacyMigrated.cachePath -ceq 'custom-cache' -and $legacyMigrated.flutterUrl -ceq 'custom-url' -and $legacyMigrated.updateVscodeSettings -eq $false) '旧版flavors/源/缓存/IDE策略迁移保留'
    Assert-FvmThrows { & $module { param($Project) New-JobsFvmInspection $Project } $legacyProject } '相对cachePath明确阻断而非改变缓存语义'
    [IO.File]::WriteAllText((Join-Path $project '.gitignore'), "existing/`n")
    [IO.File]::WriteAllText((Join-Path $project 'app.code-workspace'), '{"folders":[],"settings":{"keep":true}}')
    $backup = & $module { param($Project) Backup-JobsFvmProject $Project } $project
    Assert-Fvm ([IO.File]::ReadAllText((Join-Path $backup 'files/.gitignore')) -ceq "existing/`n") '备份保留配置字节'
    $snapshot = Get-Content -LiteralPath (Join-Path $backup 'snapshot.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Fvm (@($snapshot.Entries | Where-Object { $_.Path -ceq '.fvm' -and $_.Type -ceq 'Absent' }).Count -eq 1) '备份记录原本不存在的目标'
    Assert-Fvm ([IO.File]::Exists((Join-Path $backup 'files/app.code-workspace'))) 'FVM可能修改的根workspace已精确备份'
    $guardProject = Join-Path $temporary 'guard-project'
    [void][IO.Directory]::CreateDirectory((Join-Path $guardProject '.fvm'))
    $outsideFile = Join-Path $temporary 'outside-settings.json'
    [IO.File]::WriteAllText($outsideFile, 'outside-retained')
    foreach ($relative in @('.fvm/fvm_config.json', '.fvm/version', '.fvm/release', '.fvm/.gitignore', 'unsafe.code-workspace')) {
        $link = Join-Path $guardProject $relative
        if (New-JobsTestSymbolicLink -Path $link -Target $outsideFile) {
            Assert-FvmThrows { & $module { param($Project) Assert-JobsFvmWritePaths $Project } $guardProject } ('FVM已知写路径拒绝链接：' + $relative)
            [IO.File]::Delete($link)
        }
    }
    $dangling = Join-Path $guardProject '.fvm/version'
    if (New-JobsTestSymbolicLink -Path $dangling -Target (Join-Path $temporary 'missing-outside')) {
        Assert-FvmThrows { & $module { param($Project) Assert-JobsFvmWritePaths $Project } $guardProject } '悬空配置链接不得伪装不存在'
        [IO.File]::Delete($dangling)
    }
    Assert-Fvm ([IO.File]::ReadAllText($outsideFile) -ceq 'outside-retained') '门禁没有写出项目边界'
    & $module {
        function script:Read-JobsFvmWebJson {
            param($Uri)
            return [pscustomobject]@{
                current_release = [pscustomobject]@{ stable = 'newhash'; beta = 'betahash' }
                releases = @(
                    [pscustomobject]@{ version = '3.22.0'; channel = 'stable'; hash = 'newhash'; release_date = '2024-05-14T00:00:00Z' },
                    [pscustomobject]@{ version = '3.19.0'; channel = 'stable'; hash = 'oldhash'; release_date = '2024-02-14T00:00:00Z' },
                    [pscustomobject]@{ version = '3.23.0-0.1.pre'; channel = 'beta'; hash = 'betahash'; release_date = '2024-05-15T00:00:00Z' }
                )
            }
        }
    }
    $cached = @([pscustomobject]@{ Version = '3.19.0'; Ready = $true; Directory = 'unused' }, [pscustomobject]@{ Version = '3.16.0'; Ready = $false; Directory = 'unused' })
    $choices = @(& $module { param($Cached) Get-JobsFlutterReleaseChoices $Cached '3.19.0' } $cached)
    Assert-Fvm ($choices.Count -eq 3) '联网列出历史与最新并去除未就绪的无发布缓存'
    Assert-Fvm (@($choices | Where-Object { $_.Label -match '最新stable' -and $_.Version -ceq '3.22.0' }).Count -eq 1) '最新 stable 使用官方 current_release'
    Assert-Fvm (@($choices | Where-Object { $_.Label -match '当前项目' -and $_.Ready }).Count -eq 1) '当前项目和就绪缓存标注'
    Assert-Fvm (@($choices | Where-Object { $_.Version -ceq '3.23.0-0.1.pre' -and $_.Label -match '最新beta' }).Count -eq 1) '历史 beta 精确版本可选'
    & $module { function script:Read-JobsFvmWebJson { param($Uri) throw 'offline fixture' } }
    $offline = @(& $module { param($Cached) Get-JobsFlutterReleaseChoices $Cached '3.19.0' } $cached)
    Assert-Fvm ($offline.Count -eq 1 -and $offline[0].Ready -and $offline[0].Offline -and $offline[0].Label -match '最新未知') '离线仅允许已初始化缓存且最新未知'
    Assert-FvmThrows { & $module { Get-JobsFlutterReleaseChoices @() '' } } '无网络无就绪缓存时停止'
    & $module {
        function script:Get-JobsFvmToolchain { param($Directory) return [pscustomobject]@{ Fvm = 'fixture.exe'; Fzf = 'fzf-fixture.exe'; Context = [pscustomobject]@{ versionsCachePath = 'fixture-cache'; flutterUrl = 'fixture-source' } } }
        function script:Get-JobsFvmCachedVersions { param($Fvm, $Directory) $script:LastInspection = $Directory; return [pscustomobject]@{ Version = '3.22.0'; Ready = $true; Directory = 'unused' } }
        function script:Get-JobsFlutterReleaseChoices { param($Cached, $Current) return [pscustomobject]@{ Version = '3.22.0'; Ready = $true; Offline = $true; Label = 'fixture' } }
        function script:Select-JobsFlutterVersion { param($Fzf, $Choices, $Directory) return $null }
    }
    $hashBefore = (Get-FileHash -LiteralPath (Join-Path $project '.fvmrc')).Hash
    $pathBefore = $env:PATH
    & $module { param($Project) Invoke-JobsFlutterVersionAction $Project } $project
    Assert-Fvm ((Get-FileHash -LiteralPath (Join-Path $project '.fvmrc')).Hash -ceq $hashBefore) 'fzf Esc 取消不写项目'
    Assert-Fvm ($env:PATH -ceq $pathBefore) '退出恢复进程 PATH'
    $usedInspection = & $module { $script:LastInspection }
    Assert-Fvm ($usedInspection -cne $project -and -not [IO.Directory]::Exists($usedInspection)) 'API缓存体检使用项目外影子目录且退出精确清理'
    & $module {
        function script:Select-JobsFlutterVersion { param($Fzf, $Choices, $Directory) return $Choices[0] }
        function script:Read-Host { param($Prompt) return $script:FinalConfirmationInput }
    }
    foreach ($cancelInput in @('go', ' ', '取消')) {
        & $module { param($InputText) $script:FinalConfirmationInput = $InputText } $cancelInput
        & $module { param($Project) Invoke-JobsFlutterVersionAction $Project } $project
        Assert-Fvm ((Get-FileHash -LiteralPath (Join-Path $project '.fvmrc')).Hash -ceq $hashBefore) ('最终非空输入取消不写项目：[' + $cancelInput + ']')
    }
    & $module {
        $script:Commands = @()
        function script:Read-Host { param($Prompt) return '' }
        function script:Assert-JobsFvmSymlinkSupport { param($Directory) }
        function script:Invoke-JobsFvmTool {
            param($File, $Arguments, $Directory, [switch]$Visible, $TimeoutSeconds)
            $script:Commands += ($Arguments -join ' ')
            if ($Arguments[0] -ceq 'api') {
                return [pscustomobject]@{ ExitCode = 0; StdOut = '{"context":{"versionsCachePath":"fixture-cache","flutterUrl":"fixture-source"}}'; StdErr = '' }
            }
            if ($Arguments[0] -ceq 'use') {
                # 模拟FVM已知字段序列化会丢未知custom字段，业务收尾须补回。
                [IO.File]::WriteAllText((Join-Path $Directory '.fvmrc'), '{"flutter":"3.22.0","updateMelosSettings":false}')
                $sdk = Join-Path (Split-Path -Parent $Directory) 'sdk-cache'
                [void][IO.Directory]::CreateDirectory((Join-Path $sdk 'bin'))
                [IO.File]::WriteAllText((Join-Path $sdk 'bin/flutter.bat'), '@echo fixture')
                [void][IO.Directory]::CreateDirectory((Join-Path $Directory '.fvm'))
                if (-not (Test-Path -LiteralPath (Join-Path $Directory '.fvm/flutter_sdk'))) {
                    $kind = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'Junction' } else { 'SymbolicLink' }
                    $linkTarget = $sdk
                    if ($PSVersionTable.PSVersion.Major -eq 5) { $linkTarget = [Management.Automation.WildcardPattern]::Escape($sdk) }
                    [void](New-Item -ItemType $kind -Path (Join-Path $Directory '.fvm/flutter_sdk') -Target $linkTarget)
                }
            }
            return [pscustomobject]@{ ExitCode = 0; StdOut = '{"frameworkVersion":"3.22.0"}'; StdErr = '' }
        }
    }
    & $module { param($Project) Invoke-JobsFlutterVersionAction $Project } $project
    $commands = @(& $module { $script:Commands })
    Assert-Fvm ($commands.Count -eq 3 -and $commands[0] -ceq 'api context --compress' -and $commands[1] -ceq 'use 3.22.0 --skip-pub-get --skip-setup' -and $commands[2] -ceq 'flutter --version --machine') '最终回车执行离线缓存切换并复核，不安装/联网pub'
    $finalConfig = Get-Content -LiteralPath (Join-Path $project '.fvmrc') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Fvm ($finalConfig.custom.nested.keep -ceq 'retained' -and $finalConfig.flavors.staging -ceq '3.16.0') 'FVM序列化丢弃的原有字段已补回'
    Assert-Fvm (@($commands | Where-Object { $_ -match '^global|pub get' }).Count -eq 0) '不设置全局版本或获取项目依赖'
    Assert-Fvm ([Convert]::ToBase64String([IO.File]::ReadAllBytes($parentConfig)) -ceq [Convert]::ToBase64String($beforeParent)) '完整模拟操作后父配置保持'
    & $module {
        $script:Commands = @()
        function script:Get-JobsFlutterReleaseChoices { param($Cached, $Current) return [pscustomobject]@{ Version = '3.22.0'; Ready = $false; Offline = $false; Label = 'uncached fixture' } }
    }
    & $module { param($Project) Invoke-JobsFlutterVersionAction $Project } $project
    $installCommands = @(& $module { $script:Commands })
    Assert-Fvm ($installCommands.Count -eq 4 -and $installCommands[1] -ceq 'install 3.22.0 --skip-pub-get' -and $installCommands[2] -ceq 'use 3.22.0 --skip-pub-get --skip-setup') '最终回车执行未缓存版本安装后绑定精确版本'
    $beforeConcurrent = (Get-FileHash -LiteralPath (Join-Path $project '.fvmrc')).Hash
    & $module {
        $script:Commands = @()
        function script:Select-JobsFlutterVersion {
            param($Fzf, $Choices, $Directory)
            [IO.File]::AppendAllText((Join-Path $Directory 'pubspec.yaml'), "`n# external edit during selection")
            return $Choices[0]
        }
    }
    Assert-FvmThrows { & $module { param($Project) Invoke-JobsFlutterVersionAction $Project } $project } '选版期间项目变动在写入前停止'
    Assert-Fvm ((Get-FileHash -LiteralPath (Join-Path $project '.fvmrc')).Hash -ceq $beforeConcurrent) '并发变动阻断保留原配置'
    Assert-Fvm (@(& $module { $script:Commands }).Count -eq 0) '并发阻断没有执行安装/切换'
    & $module {
        $script:Commands = @()
        function script:Select-JobsFlutterVersion { param($Fzf, $Choices, $Directory) return $Choices[0] }
        function script:Invoke-JobsFvmTool {
            param($File, $Arguments, $Directory, [switch]$Visible, $TimeoutSeconds)
            $script:Commands += ($Arguments -join ' ')
            return [pscustomobject]@{ ExitCode = 0; StdOut = '{"context":{"versionsCachePath":"different-cache","flutterUrl":"fixture-source"}}'; StdErr = '' }
        }
    }
    Assert-FvmThrows { & $module { param($Project) Invoke-JobsFlutterVersionAction $Project } $project } '新根配置改变继承缓存时阻断旧Ready状态'
    $driftCommands = @(& $module { $script:Commands })
    Assert-Fvm ($driftCommands.Count -eq 1 -and $driftCommands[0] -ceq 'api context --compress') '上下文变化后没有下载或切换'
    Write-Host ('PASS: FlutterVersionMgr.Tests.ps1 (' + $script:assertions + ' assertions; fixtures only)')
}
finally {
    if ($null -ne $module) { Remove-Module $module }
    $env:LOCALAPPDATA = $savedLocal
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

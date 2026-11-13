# FlutterRunner.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年10月20日，星期二.
# 临时文件 / 假 Flutter；不注册菜单、不启动真实设备、不访问项目。
[CmdletBinding()]
param([switch]$Native)
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
$package = Join-Path $root 'JobsFlutterRunner'
$action = Import-Module (Join-Path $package 'Scripts/Action.psm1') -PassThru -DisableNameChecking
$installer = Import-Module (Join-Path $package 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
$script:assertions = 0
function Assert-Runner { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw ('FAIL: ' + $Message) }; $script:assertions++ }
function Assert-RunnerThrows { param([scriptblock]$Body, [string]$Message); $threw = $false; try { & $Body | Out-Null } catch { $threw = $true }; Assert-Runner $threw $Message }
$temporaryBase = [IO.Path]::GetTempPath()
if ([IO.Directory]::Exists('/private/tmp')) { $temporaryBase = '/private/tmp' }
$temporary = Join-Path $temporaryBase ('JobsFlutterRun-' + [guid]::NewGuid().ToString('N'))
$savedLocal = $env:LOCALAPPDATA
try {
    [void][IO.Directory]::CreateDirectory($temporary)
    $env:LOCALAPPDATA = Join-Path $temporary 'Local'
    $fixtures = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Fixtures/FlutterRunnerPubspec.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($fixture in $fixtures) {
        $result = & $action { param($Text) Test-JobsFlutterPubspec $Text } $fixture.Text
        Assert-Runner ($result -eq $fixture.Expected) ('精确识别：' + $fixture.Name)
    }
    $project = Join-Path $temporary 'Project 中文 & 100%'
    [void][IO.Directory]::CreateDirectory((Join-Path $project 'android'))
    [void][IO.Directory]::CreateDirectory((Join-Path $project 'web'))
    [IO.File]::WriteAllText((Join-Path $project 'pubspec.yaml'), "dependencies:`n  flutter:`n    sdk: flutter`n")
    & $action { param($Path) Assert-JobsFlutterProject $Path } $project
    Assert-RunnerThrows { & $action { param($Path) Assert-JobsFlutterProject $Path } $temporary } '不向下扫描子项目'
    Assert-RunnerThrows { & $action { param($Path) Assert-JobsFlutterProject $Path } (Join-Path $project 'android') } '不沿用父工程'
    [IO.File]::WriteAllText((Join-Path $project '.fvmrc'), '{"flutter":"3.0.0"}')
    Assert-RunnerThrows { & $action { param($Path) Get-JobsRunnerFlutter $Path } $project } 'FVM 已声明但本地 SDK 缺失时不改用全局 Flutter'
    $boundSdk = Join-Path $project '.fvm/flutter_sdk/bin'
    [void][IO.Directory]::CreateDirectory($boundSdk)
    [IO.File]::WriteAllText((Join-Path $boundSdk 'flutter.bat'), '@echo fixture')
    Assert-Runner ((& $action { param($Path) Get-JobsRunnerFlutter $Path } $project) -eq (Join-Path $boundSdk 'flutter.bat')) '优先采用项目绑定的 Flutter'
    $devices = @(& $action { ConvertFrom-JobsRunnerList '[{"id":"android-1","name":"Pixel","targetPlatform":"android"},{"id":"win","name":"Windows","targetPlatform":"windows-x64"},{"id":"chrome","name":"Chrome","targetPlatform":"web-javascript"},{"id":"ios","name":"iPhone","targetPlatform":"ios"}]' })
    Assert-Runner ($devices.Count -eq 4) '正确枚举 JSON 顶层数组'
    $supported = @(& $action { param($Devices, $Project) Get-JobsRunnerSupportedDevices $Devices $Project } $devices $project)
    Assert-Runner ($supported.Count -eq 2 -and $supported[0].id -eq 'android-1' -and $supported[1].id -eq 'chrome') '按项目平台目录过滤 Windows / iOS 不兼容设备'
    Assert-Runner (@(& $action { ConvertFrom-JobsRunnerList '[]' }).Count -eq 0) '无设备返回真实空列表'
    Assert-Runner (@(& $action { ConvertFrom-JobsRunnerList "Preparing Flutter`n[]" }).Count -eq 0) '准备信息后仍支持空列表'
    Assert-RunnerThrows { & $action { ConvertFrom-JobsRunnerList '[{"name":"missing id"}]' } } '无效设备响应停止'
    Assert-RunnerThrows { & $action { ConvertFrom-JobsRunnerList 'not JSON' } } '损坏 JSON 不能当空列表成功'
    $dataRoot = & $action { param($Path) Get-JobsRunnerProjectRoot $Path } $project
    Assert-Runner (-not (Test-Path -LiteralPath $dataRoot)) '查询项目数据位置不创建文件'
    $session = Join-Path $dataRoot 'session'
    [void][IO.Directory]::CreateDirectory($session)
    $statePath = Join-Path $session 'state.json'
    $ownProcess = Get-Process -Id $PID
    $state = @{ Status = 'Running'; WorkerPid = $PID; WorkerStartUtc = $ownProcess.StartTime.ToUniversalTime().ToString('o'); Session = $session }
    [IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json))
    Assert-Runner ($null -ne (& $action { param($Path) Get-JobsRunnerSession $Path } $dataRoot)) 'PID 与开始时间均匹配才允许重连'
    $state.WorkerStartUtc = [DateTime]::UtcNow.AddDays(-1).ToString('o')
    [IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json))
    Assert-Runner ($null -eq (& $action { param($Path) Get-JobsRunnerSession $Path } $dataRoot)) 'PID 复用不能误认成运行会话'
    & $action { param($Path) Send-JobsRunnerControl $Path 'reload'; Send-JobsRunnerControl $Path 'restart'; Send-JobsRunnerControl $Path 'stop' } $session
    $controls = @(Get-ChildItem -LiteralPath $session -Filter 'control-*.json')
    Assert-Runner ($controls.Count -eq 3 -and @(Get-ChildItem -LiteralPath $session -Filter '*.tmp').Count -eq 0) '控制请求独立原子写入，没有半写临时文件'
    $commands = @($controls | ForEach-Object { (Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json).Command } | Sort-Object)
    Assert-Runner (($commands -join ',') -ceq 'reload,restart,stop') 'r / R / s 映射为独立命令'
    $manifest = Get-Content -LiteralPath (Join-Path $package 'Extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $release = Join-Path $temporary 'release'
    & $installer { param($Path, $Destination) New-JobsPackageRelease -PackagePath $Path -Destination $Destination } $package $release | Out-Null
    foreach ($name in @('ContextMenu.cpp', 'FlutterProject.h', 'ContextMenu.def', 'RunnerHost.cs', 'Build.ps1', 'OpenCmd.ps1', 'AndroidRuntime.ps1')) {
        Assert-Runner (Test-Path -LiteralPath (Join-Path $release ('Scripts/' + $name)) -PathType Leaf) ('独立 release 包含：' + $name)
    }
    $plan = @(& $installer { param($Manifest, $Release) Get-JobsPackageRegistryPlan -Manifest $Manifest -ReleasePath $Release -PowerShellPath 'powershell.exe' } $manifest $release)
    Assert-Runner ($plan.Count -eq 4) '三个动态上下文 + 一个本包 CLSID'
    Assert-Runner (@($plan | Where-Object { $_.Key -match '\\shell\\' }).Count -eq 0) '注册计划没有全目录可见的静态 verb'
    Assert-Runner ($plan[3].InProcServer -eq (Join-Path $release 'bin/JobsFlutterContextMenu.dll')) 'CLSID 绑定本次独立 release 的原生 DLL'
    $disabled = @(& $installer { param($Manifest, $Release) Get-JobsPackageRegistryPlan -Manifest $Manifest -ReleasePath $Release -PowerShellPath 'powershell.exe' -Enabled $false } $manifest $release)
    Assert-Runner (@($disabled | Where-Object Enabled).Count -eq 0) '卸载包括菜单与 COM CLSID'
    if ($Native -and [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        & (Join-Path $package 'Scripts/Build.ps1') -OutputRoot (Join-Path $release 'bin')
        Add-Type -Path (Join-Path $PSScriptRoot 'FlutterRunnerMenuProbe.cs')
        $library = Join-Path $release 'bin/JobsFlutterContextMenu.dll'
        Assert-Runner ([JobsFlutterRunnerTests.MenuProbe]::Count($library, $project, 0) -eq 1) '原生 COM 在 Flutter 工程背景插入一项'
        Assert-Runner ([JobsFlutterRunnerTests.MenuProbe]::Count($library, $project, 1) -eq 1) '原生 COM 在所选 Flutter 文件夹插入一项'
        Assert-Runner ([JobsFlutterRunnerTests.MenuProbe]::Count($library, $temporary, 0) -eq 0) '原生 COM 在普通背景真实插入零项'
        Assert-Runner ([JobsFlutterRunnerTests.MenuProbe]::Count($library, $temporary, 1) -eq 0) '原生 COM 在普通文件夹真实插入零项'
        Assert-Runner ([JobsFlutterRunnerTests.MenuProbe]::Count($library, $project, 2) -eq 0) '原生 COM 多选不显示'
        $fake = Join-Path $temporary 'FakeFlutter.cs'
        $fakeSource = @'
using System;
using System.IO;
using System.Threading;
class FakeFlutter {
    static void Main() {
        Console.WriteLine("[{\"event\":\"app.start\",\"params\":{\"appId\":\"fake-app\"}}]");
        Console.WriteLine("[{\"event\":\"app.started\",\"params\":{\"appId\":\"fake-app\"}}]");
        Console.Out.Flush();
        string line;
        while ((line = Console.ReadLine()) != null) {
            File.AppendAllText(Path.Combine(Environment.CurrentDirectory, "commands.log"), line + Environment.NewLine);
            if (line.Contains("app.stop")) return;
            Console.WriteLine("[{\"event\":\"app.log\",\"params\":{\"log\":\"control received\"}}]");
            Console.Out.Flush();
        }
    }
}
'@
        [IO.File]::WriteAllText($fake, $fakeSource)
        $csc = Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
        $fakeExe = Join-Path $temporary 'FakeFlutter.exe'
        & $csc /nologo /target:exe ('/out:' + $fakeExe) $fake
        if ($LASTEXITCODE -ne 0) { throw '假 Flutter 编译失败。' }
        $nativeRoot = Join-Path $temporary 'Native'
        $nativeSession = Join-Path $nativeRoot 'session'
        [void][IO.Directory]::CreateDirectory($nativeSession)
        $request = Join-Path $nativeSession 'request.json'
        [IO.File]::WriteAllText($request, (@{ Project = $project; Flutter = $fakeExe; Device = 'fake-device' } | ConvertTo-Json))
        $hostExe = Join-Path $release 'bin/JobsFlutterRunnerHost.exe'
        $starter = Start-Process -FilePath $hostExe -ArgumentList @('start', ('"' + $request + '"')) -PassThru -Wait
        Assert-Runner ($starter.ExitCode -eq 0) '前台启动进程正常退出'
        $clock = [Diagnostics.Stopwatch]::StartNew()
        do {
            Start-Sleep -Milliseconds 100
            $nativeStatePath = Join-Path $nativeSession 'state.json'
            $nativeState = $null
            if (Test-Path -LiteralPath $nativeStatePath) { $nativeState = Get-Content -LiteralPath $nativeStatePath -Raw -Encoding UTF8 | ConvertFrom-Json }
        } while (($null -eq $nativeState -or $nativeState.Status -eq 'Starting') -and $clock.Elapsed.TotalSeconds -lt 15)
        Assert-Runner ($nativeState.Status -eq 'Running') '启动者退出后独立监督进程与 Flutter 继续运行'
        & $action { param($Path) Send-JobsRunnerControl $Path reload; Send-JobsRunnerControl $Path restart } $nativeSession
        Start-Sleep -Milliseconds 500
        & $action { param($Path) Send-JobsRunnerControl $Path stop } $nativeSession
        $clock.Restart()
        do {
            Start-Sleep -Milliseconds 100
            $nativeState = Get-Content -LiteralPath $nativeStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        } while ($nativeState.Status -notin @('Stopped', 'Failed') -and $clock.Elapsed.TotalSeconds -lt 15)
        Assert-Runner ($nativeState.Status -eq 'Stopped') 's 通过 app.stop 结束本次会话'
        $requests = Get-Content -LiteralPath (Join-Path $project 'commands.log') -Raw -Encoding UTF8
        Assert-Runner ($requests.Contains('"fullRestart":false') -and $requests.Contains('"fullRestart":true') -and $requests.Contains('app.stop')) 'machine 控制实际到达假 Flutter'
    } else { Write-Host 'SKIP: MSVC/.NET 编译、Win32 detached / Job 与真实菜单需要 Windows。可在 Windows 使用 -Native。' }
    Write-Host ('PASS: FlutterRunner.Tests.ps1 (' + $script:assertions + ' assertions)')
} finally {
    $env:LOCALAPPDATA = $savedLocal
    Remove-Module $action
    Remove-Module $installer
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

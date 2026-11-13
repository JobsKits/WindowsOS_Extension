# FlutterRunnerAndroid.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年10月29日，星期四.
# 临时 SDK 与函数夹具；不联网、不创建真实 AVD、不启动设备或注册扩展。
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
$root = Split-Path -Parent $PSScriptRoot
$path = Join-Path $root 'JobsFlutterRunner/Scripts/Action.psm1'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('JobsRunnerAndroid-' + [guid]::NewGuid().ToString('N'))
$script:checks = 0
function Assert-AndroidRunner {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
    $script:checks++
}
function New-RunnerFixture {
    $module = Import-Module $path -Force -PassThru -DisableNameChecking
    & $module {
        $script:Calls = [Collections.Generic.List[string]]::new()
        function script:Get-JobsRunnerHarmonyDiagnostics { return @() }
        function script:Start-Sleep { param($Seconds, $Milliseconds) }
        function script:Write-JobsLog { param($Text) $script:Calls.Add('log:' + $Text) }
    }
    return $module
}
$savedHome = $env:ANDROID_HOME
$savedRoot = $env:ANDROID_SDK_ROOT
$savedJava = $env:JAVA_HOME
try {
    [void][IO.Directory]::CreateDirectory($temporary)
    $project = Join-Path $temporary 'Project 中文 & 100%'
    [void][IO.Directory]::CreateDirectory((Join-Path $project 'android'))
    $module = New-RunnerFixture
    & $module {
        function script:Invoke-FixtureJava { $global:LASTEXITCODE = 0; return 'fixture license output' }
    }
    $licenseOutput = @(& $module { Invoke-JobsAndroidTool 'Invoke-FixtureJava' '/fixture/tools' sdkmanager @('--licenses') -Interactive })
    Assert-AndroidRunner ($licenseOutput.Count -eq 0) '许可证交互输出不混入AVD名称返回值'
    & $module {
        function script:Invoke-JobsProcess {
            param($FilePath, $Arguments)
            if ($Arguments[0] -eq 'devices') { return [pscustomobject]@{ ExitCode = 0; StdOut = "emulator-5560`tdevice"; StdErr = '' } }
            return [pscustomobject]@{ ExitCode = 0; StdOut = "Pixel_existing`nOK"; StdErr = '' }
        }
        function script:Test-JobsAndroidBoot { return $true }
    }
    Assert-AndroidRunner ((& $module { Start-JobsAndroidAvd '/fixture/sdk' 'Pixel_existing' }) -ceq 'emulator-5560') '已运行AVD直接返回匹配serial，不重复启动'
    Remove-Module $module
    $module = New-RunnerFixture
    & $module {
        function script:Test-JobsRunnerInteractiveMenu { return $true }
        function script:Find-JobsExecutable { return 'Invoke-TestFzf' }
        function script:Invoke-JobsProcess { return [pscustomobject]@{ ExitCode = 0; StdOut = '--expect --bind'; StdErr = '' } }
        function script:Invoke-TestFzf { $global:LASTEXITCODE = $script:FakeCode; return $script:FakeOutput }
        $script:FakeCode = 1
        $script:FakeOutput = @('left')
    }
    $selection = & $module { Select-JobsRunnerChoice '镜像' @('Android 35') -Back }
    Assert-AndroidRunner ($selection.Kind -eq 'Back') '无匹配时左键仍返回上一层'
    & $module { $script:FakeCode = 130; $script:FakeOutput = @() }
    Assert-AndroidRunner ($null -eq (& $module { Select-JobsRunnerChoice '镜像' @('Android 35') -Back })) 'Esc取消不自动选择'
    & $module { $script:FakeCode = 0; $script:FakeOutput = @('', '1  Android 35') }
    Assert-AndroidRunner ((& $module { Select-JobsRunnerChoice '镜像' @('Android 35') -Back }).Index -eq 0) '回车返回明确选中项'
    Remove-Module $module

    $module = New-RunnerFixture
    & $module {
        function script:Read-JobsRunnerInput { return 'cancel' }
        function script:Get-JobsAndroidArchitecture { throw '取消后不应检查或创建 SDK' }
    }
    $cancelSdk = Join-Path $temporary 'cancelled-sdk'
    Assert-AndroidRunner ($null -eq (& $module { param($Sdk, $Project) New-JobsRunnerAndroidAvd $Sdk $Project @() } $cancelSdk $project)) '初始化准备前取消'
    Assert-AndroidRunner (-not [IO.Directory]::Exists($cancelSdk)) '取消准备不创建SDK目录'
    Remove-Module $module

    $module = New-RunnerFixture
    & $module {
        $script:Answers = [Collections.Generic.Queue[string]]::new()
        $script:Answers.Enqueue('')
        $script:Answers.Enqueue('')
        $script:Selections = [Collections.Generic.Queue[object]]::new()
        $script:Selections.Enqueue([pscustomobject]@{ Kind = 'Selected'; Index = 0 })
        $script:Selections.Enqueue([pscustomobject]@{ Kind = 'Back'; Index = -1 })
        $script:Selections.Enqueue([pscustomobject]@{ Kind = 'Selected'; Index = 0 })
        $script:Selections.Enqueue([pscustomobject]@{ Kind = 'Selected'; Index = 0 })
        $script:ImageInstalled = $true
        $script:CreatedName = ''
        function script:Read-JobsRunnerInput { param($Prompt) return $script:Answers.Dequeue() }
        function script:Get-JobsAndroidArchitecture { return 'x86_64' }
        function script:Get-JobsAndroidJava { return '/fixture/jdk/bin/java.exe' }
        function script:Get-JobsAndroidHealthyTools { return '/fixture/tools' }
        function script:Repair-JobsAndroidComponents { $script:Calls.Add('repair') }
        function script:Get-JobsAndroidAvdHome { return '/fixture/avd-home' }
        function script:Select-JobsRunnerChoice { param($Title, $Items, [switch]$Back) $script:Calls.Add('select:' + $Title); return $script:Selections.Dequeue() }
        function script:Invoke-JobsAndroidTool {
            param($Java, $Tools, $Tool, $Arguments, $InputText, [switch]$Interactive)
            $script:Calls.Add($Tool + ':' + ($Arguments -join ' '))
            if ($Arguments -contains 'create') {
                $script:CreatedName = $Arguments[[Array]::IndexOf($Arguments, '--name') + 1]
                return ''
            }
            if ($Tool -eq 'avdmanager') { return 'id: 1 or "pixel_8"' }
            if ($Arguments -contains '--list_installed') {
                if ($script:ImageInstalled) { return 'system-images;android-35;google_apis;x86_64 | 1 | Android 35' }
                return ''
            }
            if ($Arguments -contains '--list') { return 'system-images;android-35;google_apis;x86_64 | 1 | Android 35' }
            if ($Arguments -contains '--install') { $script:ImageInstalled = $true }
        }
        function script:Get-JobsRunnerAvds { return $script:CreatedName }
    }
    $env:JAVA_HOME = 'original-java'
    $name = & $module { param($Sdk, $Project) New-JobsRunnerAndroidAvd $Sdk $Project @('Jobs_existing') } (Join-Path $temporary 'sdk') $project
    $calls = @(& $module { $script:Calls.ToArray() })
    Assert-AndroidRunner ($name -match '^Jobs_pixel_8_API35_[a-f0-9]{8}$') '按所选型号镜像生成唯一AVD名称'
    Assert-AndroidRunner (@($calls | Where-Object { $_ -like 'select:选择 Android 设备型号' }).Count -eq 2) '镜像左键返回型号选择'
    Assert-AndroidRunner (@($calls | Where-Object { $_ -like '*--install*' }).Count -eq 0) '已安装镜像不重新下载'
    Assert-AndroidRunner (@($calls | Where-Object { $_ -like '*create avd*' }).Count -eq 1) '只创建一次AVD'
    Assert-AndroidRunner (@($calls | Where-Object { $_ -like '*--force*' }).Count -eq 0) '创建不覆盖既有AVD'
    Assert-AndroidRunner ($env:JAVA_HOME -ceq 'original-java') '初始化恢复Java环境'
    & $module {
        $script:Calls.Clear()
        $script:CreatedName = ''
        $script:Answers.Enqueue('')
        $script:Answers.Enqueue('cancel')
        $script:Selections.Enqueue([pscustomobject]@{ Kind = 'Selected'; Index = 0 })
        $script:Selections.Enqueue([pscustomobject]@{ Kind = 'Selected'; Index = 0 })
        $script:ImageInstalled = $false
    }
    Assert-AndroidRunner ($null -eq (& $module { param($Sdk, $Project) New-JobsRunnerAndroidAvd $Sdk $Project @() } (Join-Path $temporary 'sdk') $project)) '最终确认取消'
    $calls = @(& $module { $script:Calls.ToArray() })
    Assert-AndroidRunner (@($calls | Where-Object { $_ -like '*--list --channel=0*' }).Count -eq 1) '缺少镜像读取官方稳定通道'
    Assert-AndroidRunner (@($calls | Where-Object { $_ -like '*--install*' -or $_ -like '*create avd*' }).Count -eq 0) '取消后不下载镜像不创建AVD'
    & $module {
        $script:Calls.Clear()
        $script:CreatedName = ''
        $script:Answers.Enqueue('')
        $script:Answers.Enqueue('')
        $script:Selections.Enqueue([pscustomobject]@{ Kind = 'Selected'; Index = 0 })
        $script:Selections.Enqueue([pscustomobject]@{ Kind = 'Selected'; Index = 0 })
    }
    $name = & $module { param($Sdk, $Project) New-JobsRunnerAndroidAvd $Sdk $Project @() } (Join-Path $temporary 'sdk') $project
    $calls = @(& $module { $script:Calls.ToArray() })
    Assert-AndroidRunner (@($calls | Where-Object { $_ -like '*--install system-images;android-35;google_apis;x86_64' }).Count -eq 1) '确认后只下载所选镜像'
    Assert-AndroidRunner ($calls.IndexOf('sdkmanager:--sdk_root=' + (Join-Path $temporary 'sdk') + ' --licenses') -lt $calls.IndexOf('sdkmanager:--sdk_root=' + (Join-Path $temporary 'sdk') + ' --install system-images;android-35;google_apis;x86_64')) '镜像安装前交由官方工具确认许可证'
    Remove-Module $module

    $module = New-RunnerFixture
    & $module {
        function script:Get-JobsAndroidSdk { return $env:ANDROID_HOME }
        function script:Get-JobsRunnerAvds { return 'Pixel_existing' }
        function script:Select-JobsRunnerChoice { return [pscustomobject]@{ Kind = 'Selected'; Index = 0 } }
        function script:New-JobsRunnerAndroidAvd { throw '已有AVD不应初始化' }
        function script:Start-JobsAndroidAvd { param($Sdk, $Name) $script:Calls.Add('start:' + $Name); return 'emulator-5558' }
        function script:Wait-JobsRunnerAndroidDevice { param($Flutter, $Project, $Serial) return $Serial }
    }
    $sdk = Join-Path $temporary 'sdk'
    [void][IO.Directory]::CreateDirectory((Join-Path $sdk 'emulator'))
    [IO.File]::WriteAllText((Join-Path $sdk 'emulator/emulator.exe'), 'fixture')
    $env:ANDROID_HOME = $sdk
    $env:ANDROID_SDK_ROOT = 'original-sdk-root'
    Assert-AndroidRunner ((& $module { param($Project) Start-JobsRunnerAndroid 'flutter' $Project } $project) -ceq 'emulator-5558') '启动所选已有AVD并等待其serial'
    Assert-AndroidRunner ($env:ANDROID_HOME -ceq $sdk -and $env:ANDROID_SDK_ROOT -ceq 'original-sdk-root') '启动后恢复SDK环境'
    Assert-AndroidRunner ((& $module { $script:RunnerSelectedSdk }) -ceq $sdk) '将所选SDK交给后续Flutter运行上下文'
    Assert-AndroidRunner ((@(& $module { $script:Calls.ToArray() }) -join ',') -ceq 'start:Pixel_existing') '已有AVD不重复创建'
    & $module {
        function script:Get-JobsRunnerAvds { return }
        function script:New-JobsRunnerAndroidAvd { $script:Calls.Add('initialize'); return $null }
    }
    Assert-AndroidRunner ($null -eq (& $module { param($Project) Start-JobsRunnerAndroid 'flutter' $Project } $project)) '缺失AVD时进入初始化且取消不启动'
    Remove-Module $module

    $module = New-RunnerFixture
    & $module {
        $script:Query = 0
        function script:Invoke-JobsRunnerTool {
            $script:Query++
            if ($script:Query -eq 1) { return '[{"id":"emulator-5554","name":"Other","targetPlatform":"android"}]' }
            return '[{"id":"emulator-5554","name":"Other","targetPlatform":"android"},{"id":"emulator-5558","name":"Selected","targetPlatform":"android"}]'
        }
    }
    Assert-AndroidRunner ((& $module { param($Project) Wait-JobsRunnerAndroidDevice 'flutter' $Project 'emulator-5558' } $project) -ceq 'emulator-5558') '等待Flutter识别选定设备，不取其它已启动模拟器'
    Assert-AndroidRunner ((& $module { $script:Query }) -eq 2) '设备延迟出现时重新查询'
    Remove-Module $module

    $module = New-RunnerFixture
    & $module {
        $script:MenuStep = 0
        function script:Invoke-JobsRunnerTool { return '[]' }
        function script:Select-JobsRunnerChoice {
            param($Title, $Items)
            $script:MenuStep++
            if ($script:MenuStep -eq 1) { $script:Labels = $Items; return [pscustomobject]@{ Kind = 'Selected'; Index = 2 } }
            if ($script:MenuStep -eq 2) { $script:CreateLabels = $Items }
            return $null
        }
        function script:New-JobsRunnerSimulator { throw '取消不应创建模拟器' }
    }
    Assert-AndroidRunner ($null -eq (& $module { param($Project) Select-JobsRunnerDevice 'flutter' $Project } $project)) '无设备时仍可进入新建分组且取消不执行业务'
    Assert-AndroidRunner ((& $module { $script:Labels[0] }) -ceq '目前已有的设备') '根菜单分组显示已有设备'
    Assert-AndroidRunner ((& $module { $script:CreateLabels[1] }) -ceq '新建 Harmony 模拟器（鸿蒙）') '无ohos目录仍提供鸿蒙新建入口'
    Remove-Module $module
    $module = New-RunnerFixture
    & $module {
        function script:Assert-JobsFlutterProject { }
        function script:Get-JobsRunnerProjectRoot { return '/fixture/runs' }
        function script:Get-JobsRunnerSession { return $null }
        function script:Get-JobsRunnerFlutter { return '/fixture/flutter' }
        function script:Get-JobsRunnerPreflight { return @{ base=(New-JobsRunnerPreflightStatus 'Flutter' 'ready' 'fixture'); android=(New-JobsRunnerPreflightStatus 'Android' 'ready' 'fixture') } }
        function script:Write-JobsRunnerPreflight { }
        function script:Invoke-JobsRunnerTool { return '{"frameworkVersion":"fixture"}' }
        function script:Select-JobsRunnerDevice { $script:RunnerSelectedSdk = '/fixture/selected-sdk'; $script:RunnerSelectedPlatform = 'android'; return 'emulator-5558' }
        function script:Start-JobsRunnerSession { $script:Calls.Add('sdk:' + $env:ANDROID_HOME + '|' + $env:ANDROID_SDK_ROOT); return '/fixture/session' }
        function script:Show-JobsRunnerLog { }
    }
    $env:ANDROID_HOME = 'old-home'
    $env:ANDROID_SDK_ROOT = 'old-root'
    & $module { Invoke-JobsFlutterRunAction '/fixture/project' }
    Assert-AndroidRunner ((@(& $module { $script:Calls.ToArray() }) -join ',') -ceq 'sdk:/fixture/selected-sdk|/fixture/selected-sdk') 'Flutter后台启动继承统一的所选SDK'
    Assert-AndroidRunner ($env:ANDROID_HOME -ceq 'old-home' -and $env:ANDROID_SDK_ROOT -ceq 'old-root') '后台启动后恢复调用方SDK环境'
    Remove-Module $module
    Write-Host ('PASS: FlutterRunnerAndroid.Tests.ps1 (' + $script:checks + ' assertions)')
} finally {
    $env:ANDROID_HOME = $savedHome
    $env:ANDROID_SDK_ROOT = $savedRoot
    $env:JAVA_HOME = $savedJava
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

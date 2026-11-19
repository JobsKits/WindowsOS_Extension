# FlutterRunnerDeviceGroups.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年11月6日，星期五.
# 假设备与临时 release；不安装 SDK、创建真实设备、注册菜单或启动业务工程。
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
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('JobsRunnerGroups-' + [guid]::NewGuid().ToString('N'))
$script:checks = 0
# 逐项断言行为与隔离边界。
function Assert-Group {
    param([bool]$Value, [string]$Message)
    if (-not $Value) { throw ('FAIL: ' + $Message) }
    $script:checks++
}
# 仅替代设备查询、选择输入与模拟器业务；保留真实菜单编排及平台过滤。
function New-GroupFixture {
    param([string]$Path, [object[]]$Selections, [string]$Devices = '[]')
    $module = Import-Module $Path -Force -PassThru -DisableNameChecking
    & $module {
        param($Selections, $Devices)
        $script:Selections = [Collections.Generic.Queue[object]]::new()
        foreach ($selection in $Selections) { $script:Selections.Enqueue($selection) }
        $script:Menus = [Collections.Generic.List[object]]::new()
        $script:Calls = [Collections.Generic.List[string]]::new()
        $script:Devices = $Devices
        function script:Invoke-JobsRunnerTool { return $script:Devices }
        function script:Get-JobsRunnerHarmonyDiagnostics { return @() }
        function script:Select-JobsRunnerChoice {
            param($Title, $Items, [switch]$Back)
            $script:Menus.Add([pscustomobject]@{ Title = $Title; Items = @($Items); Back = [bool]$Back })
            if ($script:Selections.Count -eq 0) { throw '场景输入耗尽；不应隐式选择设备。' }
            $value = $script:Selections.Dequeue()
            if ($value -ceq 'Cancel') { return $null }
            if ($value -ceq 'Back') { return [pscustomobject]@{ Kind = 'Back'; Index = -1 } }
            return [pscustomobject]@{ Kind = 'Selected'; Index = [int]$value }
        }
        function script:New-JobsRunnerSimulator { param($Platform) $script:Calls.Add('create:' + $Platform); return [pscustomobject]@{ Platform = $Platform; Id = 'emulator-5554' } }
        function script:Initialize-JobsRunnerVirtualAndroid { return '/fixture/sdk' }
        function script:Get-JobsRunnerAvds { return @() }
        function script:Initialize-JobsRunnerVirtualHarmony { return [pscustomobject]@{ Module='fixture'; Tools=[pscustomobject]@{Root='/fixture/harmony'}; Emulator='fixture-emulator' } }
        function script:Invoke-JobsRunnerHarmonyCore { return @() }
        function script:Get-JobsRunnerVirtualEnvironment { return @{} }
    } $Selections $Devices
    return $module
}
try {
    $project = Join-Path $temporary '工程 中文 & 100%'
    [void][IO.Directory]::CreateDirectory((Join-Path $project 'android'))
    $deviceJson = '[{"id":"phone-1","name":"Pixel","targetPlatform":"android"},{"id":"harmony-1","name":"Harmony","targetPlatform":"ohos-arm64"},{"id":"apple","name":"iPhone","targetPlatform":"ios"}]'
    foreach ($relative in @('JobsFlutterRunner/Scripts/Action.psm1', 'JobsFlutterTools/Scripts/Actions/run/Scripts/Action.psm1')) {
        $path = Join-Path $root $relative
        $module = New-GroupFixture $path @('0', '0') $deviceJson
        $selected = & $module { param($Project) Select-JobsRunnerDevice 'flutter' $Project } $project
        Assert-Group ($selected -ceq 'phone-1') '已有组返回明确选择的真实设备 ID'
        $menus = @(& $module { $script:Menus.ToArray() })
        Assert-Group (($menus[0].Items -join '|') -ceq '目前已有的真实设备|虚拟设备|其他运行目标（桌面 / Web）|重新加载设备列表') '根菜单区分真实、虚拟及其它目标，去掉冗余取消项'
        Assert-Group ($menus[1].Back -and $menus[1].Items[0] -ceq 'Pixel') '已有子层提供真实设备与返回绑定'
        Assert-Group (($menus[1].Items -join '|') -notmatch 'Harmony|iPhone|初始化|新建') '已有列表按当前工程能力过滤，且不混入创建动作'
        Assert-Group ((& $module { $script:Calls.Count }) -eq 0) '已有设备直接运行不触发创建或启动其它设备'
        Remove-Module $module

        $module = New-GroupFixture $path @('0','1') '[{"id":"phone-first-hidden","name":"Same Phone","targetPlatform":"android"},{"id":"phone-second-hidden","name":"Same Phone","targetPlatform":"android"}]'
        $selected=&$module {param($Project)Select-JobsRunnerDevice 'flutter' $Project} $project
        $menus=@(&$module {$script:Menus.ToArray()})
        Assert-Group ($selected-ceq'phone-second-hidden'-and$menus[1].Items[0]-ceq'Same Phone'-and$menus[1].Items[1]-ceq'Same Phone') '同名真实设备只显示名称，选第二项仍返回第二个精确ID'
        Assert-Group (($menus[1].Items-join'|')-notmatch'phone-first-hidden|phone-second-hidden|android') '设备可见行不拼接内部ID或平台字段'
        Remove-Module $module

        $module=Import-Module $path -Force -PassThru -DisableNameChecking
        &$module {
            function script:Test-JobsRunnerInteractiveMenu {return $true}
            function script:Select-JobsFzfItems {param($Title,$Items,[switch]$Child)$script:VisibleNames=@($Items|ForEach-Object{[string]$_});return [pscustomobject]@{Action='selected';Items=@($Items[1])}}
            $env:JOBS_FLUTTER_RUNNER_FZF=$null
        }
        $choice=&$module {Select-JobsRunnerChoice 'names' @('同名设备','同名设备') -Back}
        Assert-Group ($choice.Index-eq1-and(@(&$module {$script:VisibleNames})-join'|')-ceq'同名设备|同名设备') '通用选择器以对象索引处理重名，传给fzf的可见文字不带索引或内部key'
        Remove-Module $module

        $module = New-GroupFixture $path @('0', '1') $deviceJson
        & $module {
            function script:Get-JobsRunnerHarmonyDiagnostics { return [pscustomobject]@{Kind='HarmonyDiagnostic';Id='original-hdc';Name='鸿蒙USB设备—已连接，环境未就绪';Detail='缺少HDC/ohos'} }
            function script:Invoke-JobsRunnerPrepareHarmony { param($Flutter,$Project,$Key) $script:Calls.Add('prepare:'+$Key);return [pscustomobject]@{Flutter='prepared-flutter';DiagnosticKey=$Key;Environment=@{};DeviceId=$Key;DevicePlatform='ohos-arm64'} }
        }
        $selected = & $module { param($Project) Select-JobsRunnerDevice 'flutter' $Project } $project
        $menus = @(& $module { $script:Menus.ToArray() })
        Assert-Group ($menus[1].Items[1] -match '鸿蒙USB设备.*已连接.*环境未就绪') '已有设备列表同时展示未就绪的鸿蒙USB诊断行'
        Assert-Group ($selected -ceq 'original-hdc' -and (@(& $module { $script:Calls.ToArray() }) -join '|') -ceq 'prepare:original-hdc') '选择鸿蒙诊断在当前运行流程准备环境并直接承接原设备'
        Assert-Group ($menus.Count -eq 2 -and (& $module {$script:RunnerPreparedHarmony.Flutter}) -ceq 'prepared-flutter') '准备成功使用新SDK且不跳其它配置入口或重复选择设备'
        Remove-Module $module

        $module = New-GroupFixture $path @('0', '0') '[]'
        & $module {
            function script:Get-JobsRunnerHarmonyDiagnostics { return [pscustomobject]@{Kind='HarmonyDiagnostic';Id='original-hdc';Name='鸿蒙USB设备—已连接，环境未就绪';Detail='缺少HDC/ohos'} }
            function script:Invoke-JobsRunnerPrepareHarmony { $script:Calls.Add('prepare-cancel');throw '已取消官方许可' }
        }
        $failed=$false
        try { & $module { param($Project) Select-JobsRunnerDevice 'flutter' $Project } $project } catch { $failed=$true }
        Assert-Group ($failed -and $null -eq (& $module { $script:RunnerSelectedPlatform })) '准备取消时不把USB诊断标识变成可运行目标'
        Assert-Group ((@(& $module { $script:Calls.ToArray() }) -join '|') -ceq 'prepare-cancel') '取消不创建模拟器或启动应用'
        Remove-Module $module

        foreach($platform in @('Android','Harmony')) {
            $index=if($platform-ceq'Android'){'0'}else{'1'}
            $module=New-GroupFixture $path @('1',$index) $deviceJson
            &$module {
                function script:Start-JobsRunnerExistingAndroid { param($Flutter,$Project,[switch]$AllowCreate) if(-not$AllowCreate){throw 'missing merged menu'}; $script:Calls.Add('start:Android');return [pscustomobject]@{Kind='Ready';Id='emulator-5568';Platform='android';Sdk='selected-sdk';Environment=@{}} }
                function script:Start-JobsRunnerExistingHarmony { param($Flutter,$Project,[switch]$AllowCreate) if(-not$AllowCreate){throw 'missing merged menu'}; $script:Calls.Add('start:Harmony');return [pscustomobject]@{Kind='Ready';Id='127.0.0.1:15555';Platform='ohos-arm64';Environment=@{}} }
            }
            $selected=&$module {param($Project)Select-JobsRunnerDevice 'flutter' $Project} $project
            $menus=@(&$module {$script:Menus.ToArray()})
            Assert-Group (($menus[1].Items-join'|')-ceq'Android 虚拟设备|Harmony 虚拟设备') 'Windows虚拟设备只含Android/Harmony，不含iOS或独立新建组'
            Assert-Group (($platform-ceq'Android'-and$selected-ceq'emulator-5568')-or($platform-ceq'Harmony'-and$selected-ceq'127.0.0.1:15555')) '已有虚拟设备精确承接目标，不重新选择其它设备'
            Assert-Group ((@(&$module {$script:Calls.ToArray()})-join'|')-ceq('start:'+$platform)-and$menus.Count-eq2) '启动成功不重复弹菜单或新建设备'
            Remove-Module $module
        }

        $createdJson = '[{"id":"emulator-5554","name":"Created Pixel","targetPlatform":"android","emulator":true},{"id":"other-phone","name":"Other","targetPlatform":"android"}]'
        $module = New-GroupFixture $path @('1', '0', '0') $createdJson
        $selected = & $module { param($Project) Select-JobsRunnerDevice 'flutter' $Project } $project
        $menus = @(& $module { $script:Menus.ToArray() })
        Assert-Group ($selected -ceq 'emulator-5554') '空Android清单的新建成功后精确承接目标'
        Assert-Group ($menus.Count -eq 3 -and $menus[2].Items.Count -eq 1 -and $menus[2].Items[-1] -ceq '新建 Android 虚拟设备') '空清单仍显示唯一新建入口，且新建位于末尾'
        Assert-Group ((@(& $module { $script:Calls.ToArray() }) -join '|') -ceq 'create:Android') '创建只执行一次'
        Remove-Module $module

        $module = New-GroupFixture $path @('1','1','0','Back','0','0') $deviceJson
        $selected = & $module { param($Project) Select-JobsRunnerDevice 'flutter' $Project } $project
        $menus = @(& $module { $script:Menus.ToArray() })
        Assert-Group ($menus[2].Items[-1] -ceq '新建 Harmony 虚拟设备') '无ohos目录仍在Harmony清单提供新建入口'
        Assert-Group ($selected -ceq 'phone-1' -and (@(& $module {$script:Calls.ToArray()}) -join '|') -ceq 'create:Harmony') '不支持的新建目标保留实例并返回本人选择，不自动改设备'
        Remove-Module $module

        $module = New-GroupFixture $path @('1', '0', '0') $createdJson
        & $module {
            $script:Runs = 0
            function script:Assert-JobsFlutterProject { }
            function script:Get-JobsRunnerProjectRoot { return 'fixture-runs' }
            function script:Get-JobsRunnerSession { return $null }
            function script:Get-JobsRunnerFlutter { return 'fixture-flutter' }
            function script:Invoke-JobsRunnerTool { param($Flutter, $Arguments) if ($Arguments[0] -ceq '--version') { return '{"frameworkVersion":"fixture"}' }; return $script:Devices }
            function script:Initialize-JobsRunnerDiscoverySdk { }
            function script:Get-JobsRunnerPreflight { return @{ base=(New-JobsRunnerPreflightStatus 'Flutter' 'ready' 'fixture'); android=(New-JobsRunnerPreflightStatus 'Android' 'ready' 'fixture') } }
            function script:Write-JobsRunnerPreflight { }
            function script:Initialize-JobsRunnerPlatformSdk { }
            function script:Start-JobsRunnerSession { param($Project, $Flutter, $Device) if ($Device -cne 'emulator-5554') { throw '错误目标' }; $script:Runs++; return 'fixture-session' }
            function script:Show-JobsRunnerLog { }
        }
        & $module { param($Project) Invoke-JobsFlutterRunAction $Project } $project
        Assert-Group ((& $module { $script:Runs }) -eq 1 -and (@(& $module { $script:Calls.ToArray() }) -join '|') -ceq 'create:Android') '完整新建分支只创建一次并运行精确目标一次'
        Remove-Module $module

        $module = New-GroupFixture $path @('1', '0', '0', 'Cancel') $createdJson
        & $module { function script:New-JobsRunnerSimulator { return $null }; function script:Wait-JobsRunnerSelectedDevice { throw '取消不得等待或运行设备' } }
        Assert-Group ($null -eq (& $module { param($Project) Select-JobsRunnerDevice 'flutter' $Project } $project)) '创建取消后不将其它已有设备作为目标'
        Remove-Module $module

        $module = New-GroupFixture $path @('0','0') '[{"id":"emulator-5554","name":"Android emulator","targetPlatform":"android"},{"id":"other-virtual","name":"Virtual flag","targetPlatform":"android","emulator":true},{"id":"phone","name":"Phone","targetPlatform":"android"}]'
        Assert-Group ((& $module {param($Project) Select-JobsRunnerDevice 'flutter' $Project} $project) -ceq 'phone') '真实设备清单同时排除模拟器标记和emulator序列号'
        $menus=@(&$module {$script:Menus.ToArray()})
        Assert-Group (($menus[1].Items -join '|') -notmatch 'emulator|Virtual flag') '真实设备文案与实际过滤一致'
        Remove-Module $module

        [void][IO.Directory]::CreateDirectory((Join-Path $project 'windows'))
        [void][IO.Directory]::CreateDirectory((Join-Path $project 'web'))
        $module=New-GroupFixture $path @('2','0') '[{"id":"windows","name":"Windows","targetPlatform":"windows-x64"},{"id":"chrome","name":"Chrome","targetPlatform":"web-javascript"}]'
        Assert-Group ((& $module {param($Project) Select-JobsRunnerDevice 'flutter' $Project} $project) -ceq 'windows') '桌面与Web保留在其他运行目标组'
        $menus=@(&$module {$script:Menus.ToArray()})
        Assert-Group (($menus[1].Items -join '|') -match 'Windows.*Chrome') '其他运行目标同时包含桌面和Web'
        Remove-Module $module

        foreach ($platform in @('Android','Harmony')) {
            $index=if($platform-ceq'Android'){'0'}else{'1'}
            $module=New-GroupFixture $path @('1',$index,'Cancel') $deviceJson
            & $module {
                function script:Get-JobsRunnerAvds { return @('Known Android 1','Known Android 2') }
                function script:Get-JobsRunnerAndroidAvdIdentity { return [pscustomobject]@{Path='fixture'} }
                function script:Invoke-JobsRunnerHarmonyCore { return @([pscustomobject]@{name='Known Harmony 1'},[pscustomobject]@{name='Known Harmony 2'}) }
                function script:Get-JobsRunnerHarmonyInstanceIdentity { return [pscustomobject]@{Path='fixture'} }
            }
            Assert-Group ($null -eq (& $module {param($Project) Select-JobsRunnerDevice 'flutter' $Project} $project)) '平台清单Esc不触发启动或创建'
            $menus=@(&$module {$script:Menus.ToArray()})
            Assert-Group ($menus[2].Items.Count -eq 3 -and $menus[2].Items[0] -ceq ('Known '+$platform+' 1') -and $menus[2].Items[1] -ceq ('Known '+$platform+' 2') -and $menus[2].Items[-1] -ceq ('新建 '+$platform+' 虚拟设备')) '真实平台清单先列已有实例，最后才是对应系统新建入口'
            Assert-Group (($menus[2].Items -join '|') -notmatch '返回|取消' -and $menus[2].Back) '平台清单用左键返回，末尾不插入冗余行'
            Remove-Module $module
        }

        $module = Import-Module $path -Force -PassThru -DisableNameChecking
        & $module {
            $script:DiscoveryCount = 0
            function script:Start-Sleep { }
            function script:Invoke-JobsRunnerTool {
                $script:DiscoveryCount++
                if ($script:DiscoveryCount -eq 1) { return '[{"id":"other-phone","name":"Other","targetPlatform":"android"}]' }
                return '[{"id":"emulator-5554","name":"Created","targetPlatform":"android"}]'
            }
        }
        $selected = & $module { param($Project) Wait-JobsRunnerSelectedDevice 'flutter' $Project ([pscustomobject]@{ Platform = 'Android'; Id = 'emulator-5554' }) } $project
        Assert-Group ($selected -ceq 'emulator-5554' -and (& $module { $script:DiscoveryCount }) -eq 2) '延迟出现时继续等待，绝不选择先出现的其它设备'
        & $module { function script:Invoke-JobsRunnerTool { return '[]' } }
        $failed = $false
        try { & $module { param($Project) Wait-JobsRunnerSelectedDevice 'flutter' $Project ([pscustomobject]@{ Platform = 'Android'; Id = 'emulator-5554' }) -TimeoutSeconds 0 } $project } catch { $failed = $true }
        Assert-Group $failed '目标发现超时明确失败，未运行其它设备'
        Remove-Module $module

        $module = New-GroupFixture $path @('1', 'Back', '0', 'Back', 'Cancel')
        Assert-Group ($null -eq (& $module { param($Project) Select-JobsRunnerDevice 'flutter' $Project } $project)) '真实和虚拟子层左键返回根层，Esc取消'
        Assert-Group ((& $module { $script:Calls.Count }) -eq 0) '返回与取消没有模拟器业务'
        Remove-Module $module

        $module = New-GroupFixture $path @('1', 'Cancel')
        Assert-Group ($null -eq (& $module { param($Project) Select-JobsRunnerDevice 'flutter' $Project } $project)) '新建组 Esc 取消整个选择'
        Assert-Group ((& $module { $script:Calls.Count }) -eq 0) '新建组取消不创建任何设备'
        Remove-Module $module

        $module = New-GroupFixture $path @('1', '0', 'Back', 'Back', 'Cancel')
        Assert-Group ($null -eq (& $module { param($Project) Select-JobsRunnerDevice 'flutter' $Project } $project)) '无设备仍可启动已有 Android，再刷新/返回/取消'
        Assert-Group ((& $module { $script:Calls.Count }) -eq 0) '虚拟设备清单返回不执行新建'
        Remove-Module $module

        $module = New-GroupFixture $path @('0', '0', 'Back', 'Cancel')
        Assert-Group ($null -eq (& $module { param($Project) Select-JobsRunnerDevice 'flutter' $Project } $project)) '空设备重新加载后仍可返回取消'
        Assert-Group ((& $module { $script:Calls.Count }) -eq 0) '重新加载不创建或启动设备'
        Remove-Module $module

        $module = Import-Module $path -Force -PassThru -DisableNameChecking
        & $module {
            function script:Initialize-JobsRunnerVirtualAndroid { return '/fixture/sdk' }
            function script:Get-JobsRunnerAvds { return @('Pixel_existing') }
            function script:Invoke-JobsRunnerTool { return "Pixel_existing`nInvalid Name" }
            function script:Select-JobsRunnerChoice { return $null }
            function script:Start-Process { throw '取消/返回不得启动模拟器' }
        }
        Assert-Group ($null-eq(& $module { param($Project) Start-JobsRunnerExistingAndroid 'flutter' $Project } $project)) '已有 AVD 子层 Esc 明确取消，未启动'
        & $module { function script:Select-JobsRunnerChoice { return [pscustomobject]@{ Kind = 'Back'; Index = -1 } } }
        Assert-Group ((& $module { param($Project) Start-JobsRunnerExistingAndroid 'flutter' $Project } $project).Kind-ceq'Back') '已有 AVD 左键仅返回已有设备层，未启动'
        Remove-Module $module

        $module = Import-Module $path -Force -PassThru -DisableNameChecking
        & $module {
            $script:Calls = [Collections.Generic.List[string]]::new()
            function script:Invoke-JobsRunnerTool {
                param($Flutter, $Arguments)
                $script:Calls.Add(($Arguments -join ' '))
                return '--[no-]ohos'
            }
        }
        & $module { param($Project) Initialize-JobsRunnerPlatformSdk 'flutter' $Project 'ohos-arm64' } $project
        Assert-Group ((@(& $module { $script:Calls.ToArray() }) -join '|') -ceq 'precache --help|precache --ohos') '鸿蒙目标先核对 SDK 能力，再准备对应平台缓存'
        & $module { $script:Calls.Clear(); function script:Invoke-JobsRunnerTool { param($Flutter, $Arguments) $script:Calls.Add(($Arguments -join ' ')); return '--android' } }
        $failed = $false
        try { & $module { param($Project) Initialize-JobsRunnerPlatformSdk 'flutter' $Project 'ohos-arm64' } $project } catch { $failed = $true }
        Assert-Group ($failed -and (& $module { $script:Calls.Count }) -eq 1) '普通 SDK 不支持鸿蒙时停止，不获取错误目标缓存'
        Remove-Module $module

        $package = if ($relative.StartsWith('JobsFlutterRunner/')) { 'JobsFlutterRunner' } else { 'JobsFlutterTools' }
        $scriptsRelative = if ($package -ceq 'JobsFlutterRunner') { 'Scripts' } else { 'Scripts/Actions/run/Scripts' }
        $installer = Import-Module (Join-Path $root ($package + '/Scripts/PackageInstaller.psm1')) -Force -PassThru -DisableNameChecking
        $release = Join-Path $temporary ($package + ' 移植 release')
        & $installer { param($Source, $Destination) New-JobsPackageRelease $Source $Destination } (Join-Path $root $package) $release | Out-Null
        foreach ($file in @('AndroidRuntime.ps1', 'RunPreflight.ps1/RunPreflight.ps1', 'RunPreflight.ps1/DoctorScope.dart', 'RunPreflight.ps1/README.md')) {
            $copy = Join-Path $release ($scriptsRelative + '/' + $file)
            Assert-Group (Test-Path -LiteralPath $copy -PathType Leaf) ('独立 release 包含运行前体检资源：' + $file)
            $sourcePreflight = & $installer { param($Path) Resolve-JobsScriptLayoutPath $Path } (Join-Path $root ($relative.Replace('/Action.psm1', '') + '/' + $file))
            Assert-Group ((Get-FileHash -LiteralPath $sourcePreflight).Hash -ceq (Get-FileHash -LiteralPath $copy).Hash) ('运行前体检资源逐字节一致：' + $file)
        }
        $sourceHealth=Join-Path $root ($relative.Replace('/Action.psm1','')+'/RunPreflight.ps1')
        foreach($resource in Get-ChildItem -LiteralPath $sourceHealth -File -Recurse){
            $suffix=$resource.FullName.Substring($sourceHealth.Length+1)
            $releaseRelative=&$installer {param($Package,$Relative)Convert-JobsReleaseLayoutRelativePath $Package $Relative} (Join-Path $root $package) ($scriptsRelative+'/RunPreflight.ps1/'+$suffix)
            if($null-eq$releaseRelative){continue}
            $copy=Join-Path $release $releaseRelative
            Assert-Group ([IO.File]::Exists($copy)-and(Get-FileHash $copy).Hash-ceq(Get-FileHash $resource.FullName).Hash) ('移植release包含同字节鸿蒙自动准备依赖：'+$suffix)
        }
        $privateSdk=Import-Module (Join-Path $release ($scriptsRelative+'/RunPreflight.ps1/PrepareHarmonyRun.ps1/Core/HarmonySdk.psm1')) -PassThru -DisableNameChecking
        Assert-Group (@(&$privateSdk {Get-JobsHarmonyTagChoices ((('a'*40)+"`trefs/tags/3.41.9+ohos-1.0.2"))}).Count-eq1) '迁移release可仅用内部依赖加载正式tag管理器'
        Remove-Module $privateSdk
        foreach ($platform in @('Android', 'Harmony')) {
            $origin = Join-Path $root ('Jobs' + $platform + 'SimulatorCreator')
            $payload = Join-Path $release ($scriptsRelative + '/SimulatorCreators/' + $platform)
            $required = @('Extension.json', ('Scripts/Create' + $platform + 'Simulator.ps1'), 'Scripts/Action.psm1', 'Scripts/Common.psm1', 'Scripts/SdkDownloadOutput.ps1', 'Scripts/SdkDownloadRoute.ps1/SdkDownloadRoute.ps1')
            if ($platform -ceq 'Harmony') { $required += 'Scripts/HarmonyTools.ps1' }
            foreach ($file in $required) {
                $copy = Join-Path $payload $file
                Assert-Group (Test-Path -LiteralPath $copy -PathType Leaf) ('独立 release 包含创建依赖：' + $file)
                $sourceFile=&$installer {param($Path)Resolve-JobsScriptLayoutPath $Path} (Join-Path $origin $file)
                Assert-Group ((Get-FileHash -LiteralPath $sourceFile).Hash -ceq (Get-FileHash -LiteralPath $copy).Hash) ('逐字节复用原桌面创建器：' + $file)
            }
        }
        # 复制的 release 中替换唯一创建入口为假脚本，验证真实子进程参数和退出传播。
        $copyAction = Join-Path $release ($scriptsRelative + '/Action.psm1')
        $module = Import-Module $copyAction -Force -PassThru -DisableNameChecking
        $hostPath = (Get-Process -Id $PID).Path
        $record = Join-Path $temporary ($package + '-creator.txt')
        $env:JOBS_TEST_CREATOR_RECORD = $record
        & $module { param($HostPath) $script:CreatorHost = $HostPath; function script:Get-JobsRunnerCreatorPowerShell { return $script:CreatorHost } } $hostPath
        $entry = Join-Path $release ($scriptsRelative + '/SimulatorCreators/Android/Scripts/CreateAndroidSimulator.ps1')
        [IO.File]::WriteAllText($entry, 'param([switch]$Create); [IO.File]::WriteAllText($env:JOBS_TEST_CREATOR_RECORD, [string]$Create); [IO.File]::WriteAllText($env:JOBS_FLUTTER_CREATED_DEVICE_FILE, "Android`temulator-5554`n"); exit 0')
        $hadReceipt = Test-Path Env:JOBS_FLUTTER_CREATED_DEVICE_FILE
        $savedReceipt = $env:JOBS_FLUTTER_CREATED_DEVICE_FILE
        $env:JOBS_FLUTTER_CREATED_DEVICE_FILE = 'original-receipt-path'
        $target = & $module { New-JobsRunnerSimulator Android }
        Assert-Group ([IO.File]::ReadAllText($record) -ceq 'True') '从迁移后的独立 release 调用 Android，强制新建参数传到子进程'
        Assert-Group ($target.Platform -ceq 'Android' -and $target.Id -ceq 'emulator-5554') '真实子PowerShell通过独立结果文件返回精确目标'
        Assert-Group ($env:JOBS_FLUTTER_CREATED_DEVICE_FILE -ceq 'original-receipt-path') '子创建器返回后精确恢复父进程结果文件环境'
        if ($hadReceipt) { $env:JOBS_FLUTTER_CREATED_DEVICE_FILE = $savedReceipt } else { Remove-Item Env:JOBS_FLUTTER_CREATED_DEVICE_FILE }
        [IO.File]::WriteAllText($entry, 'param([switch]$Create); exit 0')
        Assert-Group ($null -eq (& $module { New-JobsRunnerSimulator Android })) '退出0但没有创建结果时不运行应用'
        [IO.File]::WriteAllText($entry, 'param([switch]$Create); [IO.File]::WriteAllText($env:JOBS_FLUTTER_CREATED_DEVICE_FILE, "Harmony`t127.0.0.1:5555`n"); exit 0')
        $invalid = $false
        try { & $module { New-JobsRunnerSimulator Android } } catch { $invalid = $true }
        Assert-Group $invalid '拒绝创建器返回与请求不同的平台'
        $entry = Join-Path $release ($scriptsRelative + '/SimulatorCreators/Harmony/Scripts/CreateHarmonySimulator.ps1')
        [IO.File]::WriteAllText($entry, '[IO.File]::WriteAllText($env:JOBS_TEST_CREATOR_RECORD, "Harmony"); [IO.File]::WriteAllText($env:JOBS_FLUTTER_CREATED_DEVICE_FILE, "Harmony`t127.0.0.1:5555`n"); exit 1')
        Assert-Group ($null -eq (& $module { New-JobsRunnerSimulator Harmony })) '创建器非零退出即使写了目标也不运行应用'
        Assert-Group ([IO.File]::ReadAllText($record) -ceq 'Harmony') 'Harmony 取消/失败返回调用方，且不回放创建'
        Remove-Module $module
        Remove-Module $installer
    }
    $harmony = Import-Module (Join-Path $root 'JobsHarmonySimulatorCreator/Scripts/Action.psm1') -Force -PassThru -DisableNameChecking
    $sdk = Join-Path $temporary 'Harmony SDK 中文'
    $hdc = Join-Path $sdk 'default/openharmony/toolchains/hdc.exe'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $hdc))
    [IO.File]::WriteAllText($hdc, 'fixture-only')
    $receipt = Join-Path $temporary 'harmony-device.tsv'
    $hadReceipt = Test-Path Env:JOBS_FLUTTER_CREATED_DEVICE_FILE
    $savedReceipt = $env:JOBS_FLUTTER_CREATED_DEVICE_FILE
    try {
        $env:JOBS_FLUTTER_CREATED_DEVICE_FILE = $receipt
        & $harmony {
            param($Sdk)
            $script:FixtureEmulator = Join-Path $Sdk 'emulator/Emulator.exe'
            $script:Instance = [pscustomobject]@{ name = 'NewHarmony'; instancePath = 'new-instance'; uuid = 'uuid-1'; isRunning = $true; sdkPath = $Sdk; 'hw.hdc.port' = '15555' }
            function script:Get-JobsHarmonyInstances { return $script:Instance }
            function script:Invoke-JobsProcess { param($FilePath, $Arguments) if (($Arguments -join ' ') -cne 'list targets') { throw '只允许只读HDC目标发现' }; return [pscustomobject]@{ ExitCode = 0; StdOut = "127.0.0.1:14444`n127.0.0.1:15555"; StdErr = '' } }
        } $sdk
        & $harmony { Write-JobsHarmonyFlutterTarget $script:FixtureEmulator $script:Instance -TimeoutSeconds 0 }
        Assert-Group ([IO.File]::ReadAllText($receipt) -ceq "Harmony`t127.0.0.1:15555`n") '鸿蒙结果只返回新实例端口对应且HDC已实际发现的目标'
        [IO.File]::Delete($receipt)
        & $harmony { function script:Invoke-JobsProcess { return [pscustomobject]@{ ExitCode = 0; StdOut = '127.0.0.1:14444'; StdErr = '' } } }
        $failed = $false
        try { & $harmony { Write-JobsHarmonyFlutterTarget $script:FixtureEmulator $script:Instance -TimeoutSeconds 0 } } catch { $failed = $true }
        Assert-Group ($failed -and -not [IO.File]::Exists($receipt)) '其它鸿蒙设备已连接不能冒充新建目标'
        & $harmony { $script:Instance | Add-Member -NotePropertyName hw -NotePropertyValue ([pscustomobject]@{ hdc = [pscustomobject]@{ port = 15556 } }) }
        $failed = $false
        try { & $harmony { Write-JobsHarmonyFlutterTarget $script:FixtureEmulator $script:Instance -TimeoutSeconds 0 } } catch { $failed = $true }
        Assert-Group ($failed -and -not [IO.File]::Exists($receipt)) '鸿蒙平铺与嵌套端口冲突不返回任何运行目标'
        & $harmony {
            $script:Instance.hw.hdc.port = 15555
            function script:Invoke-JobsProcess { return [pscustomobject]@{ ExitCode = 0; StdOut = '127.0.0.1:15555'; StdErr = '' } }
        }
        & $harmony { Write-JobsHarmonyFlutterTarget $script:FixtureEmulator $script:Instance -TimeoutSeconds 0 }
        Assert-Group ([IO.File]::ReadAllText($receipt) -ceq "Harmony`t127.0.0.1:15555`n") '鸿蒙平铺与嵌套端口一致时兼容官方详情'
        [IO.File]::Delete($receipt)
        & $harmony { function script:Get-JobsHarmonyInstances { return @($script:Instance, [pscustomobject]@{ name = 'Other'; isRunning = $true; 'hw.hdc.port' = '15555' }) } }
        $failed = $false
        try { & $harmony { Write-JobsHarmonyFlutterTarget $script:FixtureEmulator $script:Instance -TimeoutSeconds 0 } } catch { $failed = $true }
        Assert-Group ($failed -and -not [IO.File]::Exists($receipt)) '两个运行实例共用HDC端口时拒绝自动运行'
        $configHome = Join-Path $temporary 'Harmony Instance'
        [void][IO.Directory]::CreateDirectory($configHome)
        [IO.File]::WriteAllText((Join-Path $configHome 'config.ini'), "name=NewHarmony`nsdkPath=$sdk`n")
        $fromConfig = & $harmony { param($Path) $copy = $script:Instance.PSObject.Copy(); $copy.instancePath = $Path; $copy.sdkPath = ''; Get-JobsHarmonyFlutterSdk $copy } $configHome
        Assert-Group ($fromConfig -ceq $sdk) '元数据缺SDK时只复用该实例自身配置的SDK'
        $conflictSdk = Join-Path $temporary 'Other SDK'
        $failed = $false
        try { & $harmony { param($Path, $Sdk) $copy = $script:Instance.PSObject.Copy(); $copy.instancePath = $Path; $copy.sdkPath = $Sdk; Get-JobsHarmonyFlutterSdk $copy } $configHome $conflictSdk } catch { $failed = $true }
        Assert-Group $failed '实例元数据与config.ini的SDK冲突时拒绝自动运行'
    } finally {
        if ($hadReceipt) { $env:JOBS_FLUTTER_CREATED_DEVICE_FILE = $savedReceipt } else { Remove-Item Env:JOBS_FLUTTER_CREATED_DEVICE_FILE -ErrorAction SilentlyContinue }
        Remove-Module $harmony
    }
    Write-Host ('PASS: FlutterRunnerDeviceGroups.Tests.ps1 (' + $script:checks + ' assertions)')
} finally {
    Remove-Item Env:JOBS_TEST_CREATOR_RECORD -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

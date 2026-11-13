# AndroidSimulatorRepairer.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年10月23日，星期五.
# 只调用隔离文件/假 ADB/CIM；不访问真实设备、注册表、网络或系统菜单。
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
$script:assertions = 0
function Assert-Repairer { param([bool]$Condition, [string]$Why) $script:assertions++; if (-not $Condition) { throw ('FAIL: ' + $Why) } }
function Assert-RepairerThrows { param([scriptblock]$Action, [string]$Why) $threw = $false; try { & $Action | Out-Null } catch { $threw = $true }; Assert-Repairer $threw $Why }
$temporary = Join-Path ([IO.Path]::GetTempPath()) ("JobsAndroidRepairer 中文 & 100% ' " + [guid]::NewGuid().ToString('N'))
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -and $temporary.StartsWith('/var/')) { $temporary = '/private' + $temporary }
$module = $null
$oldAvd = $env:ANDROID_AVD_HOME
$oldAndroidUser = $env:ANDROID_USER_HOME
$oldLocal = $env:LOCALAPPDATA
$oldSdkHome = $env:ANDROID_HOME
$oldSdkRoot = $env:ANDROID_SDK_ROOT
try {
    [void][IO.Directory]::CreateDirectory($temporary)
    $env:ANDROID_AVD_HOME = Join-Path $temporary 'avd'
    $env:ANDROID_USER_HOME = Join-Path $temporary 'android-home'
    $env:LOCALAPPDATA = Join-Path $temporary 'user-data'
    $directory = Join-Path $env:ANDROID_AVD_HOME 'Demo.avd'
    [void][IO.Directory]::CreateDirectory($directory)
    $config = Join-Path $directory 'config.ini'
    $original = "AvdId=Demo`r`ndisk.dataPartition.size=2G`r`nhw.ramSize=2048`r`n"
    [IO.File]::WriteAllText($config, $original, (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $env:ANDROID_AVD_HOME 'Demo.ini'), ('path=' + $directory + "`n"))
    [IO.File]::WriteAllText((Join-Path $directory 'userdata-qemu.img'), 'userdata fixture preserve me')
    $module = Import-Module (Join-Path $root 'JobsAndroidSimulatorRepairer/Scripts/Action.psm1') -PassThru -DisableNameChecking -Force
    & $module {
        $script:Commands = @(); $script:Logs = @(); $script:Qemu = '1'; $script:Avd = 'Demo'; $script:Location = 2
        $script:FreeKB = 1024000; $script:Approve = $true; $script:MutationFailure = $false; $script:UninstallOutput = 'Success'; $script:PackagePresent = $true
        $script:DeviceList = "List of devices attached`nemulator-5554`tdevice`nREALPHONE`tdevice`nemulator-5556`toffline`nemulator-5558`tunauthorized`n"
        function script:Write-JobsLog { param($Message) $script:Logs += $Message }
        function script:Confirm-JobsRepairDanger { param($Description) return $script:Approve }
        function script:Invoke-JobsProcess {
            param($FilePath, $Arguments, $TimeoutSeconds)
            $command = $Arguments -join ' '
            $script:Commands += $command
            $output = ''
            switch -Regex ($command) {
                '^devices$' { $output = $script:DeviceList; break }
                ' get-state$' { $output = 'device'; break }
                ' getprop ro.kernel.qemu$' { $output = $script:Qemu; break }
                ' emu avd name$' { $output = $script:Avd + "`nOK`n"; break }
                ' pm get-install-location$' { $output = [string]$script:Location + '[auto]'; break }
                ' pm set-install-location 0$' { if (-not $script:MutationFailure) { $script:Location = 0 }; break }
                ' df -k /data$' { $output = "Filesystem 1K-blocks Used Available Use% Mounted on`n/dev/block/dm-5 2097152 1000 " + $script:FreeKB + " 1% /data`n"; break }
                ' pm path ' { $output = 'package:/data/app/example/base.apk'; break }
                ' uninstall ' { $output = $script:UninstallOutput; if ($output -ceq 'Success') { $script:PackagePresent = $false }; break }
                ' pm list packages ' { if ($script:PackagePresent) { $output = 'package:com.example.app' }; break }
                ' compile --reset -a$' { if ($script:MutationFailure) { $output = 'Error: not supported' } else { $output = 'Success' }; break }
                ' emu kill$' { $output = 'OK'; break }
                '^version$|^-version$' { $output = 'Android tool version fixture'; break }
                default { throw ('Unexpected fixture call: ' + $command) }
            }
            return [pscustomobject]@{ ExitCode = 0; StdOut = $output; StdErr = '' }
        }
    }
    $env:ANDROID_HOME = Join-Path $temporary 'missing-sdk'
    Assert-RepairerThrows { & $module { Get-JobsRepairTool adb } } '显式SDK缺失时停止，不切换PATH或默认SDK'
    $sdk = Join-Path $temporary 'SDK'
    [void][IO.Directory]::CreateDirectory((Join-Path $sdk 'platform-tools'))
    [IO.File]::WriteAllText((Join-Path $sdk 'platform-tools/adb.exe'), 'fake adb')
    $env:ANDROID_HOME = $sdk
    Assert-Repairer ((& $module { Get-JobsRepairTool adb }) -eq (Join-Path $sdk 'platform-tools/adb.exe')) '显式SDK健康工具复用且路径含特殊字符不经shell'
    $env:ANDROID_HOME = $oldSdkHome
    $env:ANDROID_SDK_ROOT = $oldSdkRoot
    $devices = @(& $module { Get-JobsRepairDevices adb })
    Assert-Repairer ($devices.Count -eq 1 -and $devices[0] -ceq 'emulator-5554') '仅在线模拟器进入选择，真机/offline/unauthorized均排除'
    Assert-Repairer ((& $module { Assert-JobsRepairEmulator adb emulator-5554 }) -ceq 'Demo') 'QEMU身份与唯一AVD名一致'
    Assert-RepairerThrows { & $module { Assert-JobsRepairEmulator adb REALPHONE } } '真机序列号拒绝'
    & $module { $script:Qemu = '0'; $script:Commands = @() }
    Assert-RepairerThrows { & $module { Invoke-JobsRepairDeviceWrite adb emulator-5554 Demo @('shell','pm','set-install-location','0') } } 'emulator前缀伪装真机但QEMU标记不为1时拒绝写入'
    Assert-Repairer (& $module { @($script:Commands | Where-Object { $_ -like '*set-install-location*' }).Count -eq 0 }) '拒绝后无设备写命令'
    & $module { $script:Qemu = '1'; $script:Avd = 'Other' }
    Assert-RepairerThrows { & $module { Assert-JobsRepairEmulator adb emulator-5554 Demo } } '端口被其它AVD复用时拒绝'
    & $module { $script:Avd = "Demo`nOther" }
    Assert-RepairerThrows { & $module { Assert-JobsRepairEmulator adb emulator-5554 } } '多行AVD名称拒绝'
    & $module { $script:Avd = '../escape' }
    Assert-RepairerThrows { & $module { Assert-JobsRepairEmulator adb emulator-5554 } } '不安全AVD名称拒绝'
    & $module { $script:Avd = 'Demo'; $script:Location = 2 }
    & $module { Set-JobsRepairInstallLocation adb emulator-5554 Demo }
    Assert-Repairer (& $module { $script:Location -eq 0 }) '安装位置恢复为自动并回读'
    & $module { $script:Location = 2; $script:MutationFailure = $true }
    Assert-RepairerThrows { & $module { Set-JobsRepairInstallLocation adb emulator-5554 Demo } } '设置退出0但读回未改变则失败'
    & $module { $script:MutationFailure = $false; $script:Location = 0 }
    $space = & $module { Get-JobsRepairSpace adb emulator-5554 }
    Assert-Repairer ($space.FreeMB -eq 1000 -and $space.TotalKB -eq 2097152) 'df按KB解析并转换MB'
    foreach ($text in @('', 'df: permission denied', "Filesystem 1K-blocks Used Available Use% Mounted on`n/dev/x unknown 0 0 0% /data", '/dev/x 1 0 2 0% /data')) {
        Assert-RepairerThrows { & $module { param($Text) ConvertFrom-JobsRepairDf $Text } $text } '未知或异常df不可触发0空间修复'
    }
    foreach ($size in @('1G','8G','1024M','2147483648','1T')) {
        Assert-Repairer ((& $module { param($Size) ConvertTo-JobsRepairSize $Size } $size) -gt 0) ('支持明确容量格式：' + $size)
    }
    foreach ($size in @('0G','-1G','8g','8G;evil','9999999999999999T')) {
        Assert-RepairerThrows { & $module { param($Size) ConvertTo-JobsRepairSize $Size } $size } ('拒绝不合理容量：' + $size)
    }
    foreach ($id in @('com.example.*','com.example.app;id','-x','com.app/evil','com..app')) {
        Assert-RepairerThrows { & $module { param($Id) Remove-JobsRepairPackage adb emulator-5554 Demo $Id } $id } '不接受模糊或含注入的卸载包名'
    }
    & $module { $script:Approve = $false; $script:Commands = @() }
    & $module { Remove-JobsRepairPackage adb emulator-5554 Demo com.example.app }
    Assert-Repairer (& $module { @($script:Commands | Where-Object { $_ -match ' uninstall ' }).Count -eq 0 }) '卸载未精确YES时没有写命令'
    & $module { $script:Approve = $true; $script:UninstallOutput = 'Failure [DELETE_FAILED_INTERNAL_ERROR]' }
    Assert-RepairerThrows { & $module { Remove-JobsRepairPackage adb emulator-5554 Demo com.example.app } } '卸载host退出0但Failure仍报失败'
    & $module { $script:UninstallOutput = 'Success'; $script:PackagePresent = $true }
    & $module { Remove-JobsRepairPackage adb emulator-5554 Demo com.example.app }
    Assert-Repairer (& $module { $script:Commands -contains '-s emulator-5554 uninstall com.example.app' }) '卸载只操作用户精确指定包名'
    Assert-Repairer (& $module { @($script:Commands | Where-Object { $_ -match 'com.android.chrome|youtube|--user 0' }).Count -eq 0 }) '没有内置应用卸载清单'
    & $module { $script:MutationFailure = $true }
    Assert-RepairerThrows { & $module { Reset-JobsRepairCompileCache adb emulator-5554 Demo } } 'compile打印Error而host退出0不报成功'
    & $module { $script:MutationFailure = $false }
    $paths = & $module { Get-JobsRepairAvdConfig Demo }
    Assert-Repairer ($paths.Config -eq $config -and $paths.Directory -eq $directory) '从AVD定位文件读取配置，路径含中文与shell字符可用'
    [IO.File]::WriteAllText($config, $original.Replace('AvdId=Demo','AvdId=Other'))
    Assert-RepairerThrows { & $module { Get-JobsRepairAvdConfig Demo } } '定位到别的AVD配置时拒绝'
    [IO.File]::WriteAllText($config, ($original + "AvdId=Demo`n"))
    Assert-RepairerThrows { & $module { Get-JobsRepairAvdConfig Demo } } '重复AvdId拒绝'
    [IO.File]::WriteAllText($config, $original, (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $env:ANDROID_AVD_HOME 'Demo.ini'), 'path.rel=avd/Demo.avd')
    Assert-Repairer ((& $module { Get-JobsRepairAvdConfig Demo }).Config -eq $config) 'path.rel相对AVD根父目录解析'
    [IO.File]::WriteAllText((Join-Path $env:ANDROID_AVD_HOME 'Demo.ini'), 'path.rel=../escape')
    Assert-RepairerThrows { & $module { Get-JobsRepairAvdConfig Demo } } '拒绝path.rel越界'
    [IO.File]::WriteAllText((Join-Path $env:ANDROID_AVD_HOME 'Demo.ini'), ("path=" + $directory + "`npath=" + $directory))
    Assert-RepairerThrows { & $module { Get-JobsRepairAvdConfig Demo } } '拒绝重复AVD定位路径'
    [IO.File]::WriteAllText((Join-Path $env:ANDROID_AVD_HOME 'Demo.ini'), ('path=' + $directory))
    Assert-RepairerThrows { & $module { param($Paths) Assert-JobsRepairSameAvdConfig $Paths } $paths } '确认期间定位文件字节变化时拒绝旧快照'
    $paths = & $module { Get-JobsRepairAvdConfig Demo }
    & $module {
        $script:FakeProcesses = @(); $script:DeviceList = 'List of devices attached'
        function script:Get-CimInstance { param($ClassName, $ErrorAction) return $script:FakeProcesses }
    }
    & $module { param($Directory) Assert-JobsRepairAvdStopped adb emulator-5554 $Directory } $directory
    Assert-Repairer $true '设备消失且无进程/锁才接受停机'
    & $module { $script:FakeProcesses = @([pscustomobject]@{ Name='qemu-system-x86_64.exe'; CommandLine='qemu-system-x86_64.exe -avd Demo' }) }
    Assert-RepairerThrows { & $module { param($Directory) Assert-JobsRepairAvdStopped adb emulator-5554 $Directory } $directory } 'ADB消失但QEMU还在运行时拒绝写配置'
    & $module { $script:FakeProcesses = @() }
    $lock = Join-Path $directory 'hardware-qemu.ini.lock'
    [void][IO.Directory]::CreateDirectory($lock)
    Assert-RepairerThrows { & $module { param($Directory) Assert-JobsRepairAvdStopped adb emulator-5554 $Directory } $directory } '锁仍在时拒绝写配置'
    Remove-Item -LiteralPath $lock
    Assert-RepairerThrows { & $module { param($Paths) Set-JobsRepairAvdSize $Paths 1G adb emulator-5554 } $paths } '不允许缩容'
    Assert-RepairerThrows { & $module { param($Paths) Set-JobsRepairAvdSize $Paths 2G adb emulator-5554 } $paths } '同容量不当成扩容'
    Assert-Repairer ([IO.File]::ReadAllText($config) -ceq $original) '取消或拒绝分支保留配置原字节'
    foreach ($text in @('hw.ramSize=2048', "disk.dataPartition.size=2G`ndisk.dataPartition.size=4G", 'disk.dataPartition.size=unknown')) {
        Assert-RepairerThrows { & $module { param($Text) Get-JobsRepairConfiguredSize $Text } $text } '未知/缺失/重复原容量拒绝'
    }
    & $module { $script:FakeProcesses = @([pscustomobject]@{ Name='emulator.exe'; CommandLine='emulator.exe -avd Demo -data C:\outside.img' }) }
    Assert-RepairerThrows { & $module { param($Paths) Assert-JobsRepairDefaultStorage $Paths Demo } $paths } '-data外部userdata拒绝自动扩容'
    & $module { $script:FakeProcesses = @([pscustomobject]@{ Name='emulator.exe'; CommandLine='emulator.exe -avd Demo -datadir C:\outside' }) }
    Assert-RepairerThrows { & $module { param($Paths) Assert-JobsRepairDefaultStorage $Paths Demo } $paths } '-datadir外部目录拒绝自动扩容'
    & $module { $script:FakeProcesses = @([pscustomobject]@{ Name='emulator.exe'; CommandLine=$null }) }
    Assert-RepairerThrows { & $module { param($Paths) Assert-JobsRepairDefaultStorage $Paths Demo } $paths } '不可读进程参数拒绝自动扩容'
    & $module { $script:FakeProcesses = @([pscustomobject]@{ Name='emulator.exe'; CommandLine='emulator.exe -avd Other' }) }
    Assert-RepairerThrows { & $module { param($Paths) Assert-JobsRepairDefaultStorage $Paths Demo } $paths } '未关联目标AVD拒绝自动扩容'
    & $module { $script:FakeProcesses = @([pscustomobject]@{ Name='emulator.exe'; CommandLine='emulator.exe -avd "Demo"' }) }
    & $module { param($Paths) Assert-JobsRepairDefaultStorage $Paths Demo } $paths
    Assert-Repairer $true '已有明确AVD进程且默认数据路径通过检查'
    [IO.File]::AppendAllText($config, "disk.dataPartition.path=C:\outside.img`n")
    Assert-RepairerThrows { & $module { param($Paths) Assert-JobsRepairDefaultStorage $Paths Demo } $paths } '显式配置数据路径拒绝自动扩容'
    [IO.File]::WriteAllText($config, $original, (New-Object Text.UTF8Encoding($false)))
    & $module { $script:FakeProcesses = @() }
    $backup = & $module { param($Paths) Set-JobsRepairAvdSize $Paths 4G adb emulator-5554 } $paths
    Assert-Repairer (Test-Path -LiteralPath (Join-Path $backup 'avd/userdata-qemu.img')) '完整备份包含userdata，非仅config备份'
    Assert-Repairer ([IO.File]::ReadAllText((Join-Path $backup 'avd/config.ini')) -ceq $original) '备份精确保留原配置字节'
    Assert-Repairer ([IO.File]::ReadAllText((Join-Path $backup 'avd/userdata-qemu.img')) -ceq 'userdata fixture preserve me') '备份userdata内容通过SHA256核验'
    Assert-Repairer (Test-Path -LiteralPath (Join-Path $backup 'locator.ini')) '备份包含AVD定位文件'
    $updated = [IO.File]::ReadAllText($config)
    Assert-Repairer ($updated -ceq $original.Replace('size=2G','size=4G')) '只改容量，保留CRLF和其它配置'
    Assert-Repairer ([IO.File]::ReadAllText((Join-Path $directory 'userdata-qemu.img')) -ceq 'userdata fixture preserve me') '脚本不删除或改写userdata'
    $freshPaths = & $module { Get-JobsRepairAvdConfig Demo }
    & $module { function script:Backup-JobsRepairAvd { param($Paths,$AdditionalBytes) throw 'fixture no backup space' } }
    Assert-RepairerThrows { & $module { param($Paths) Set-JobsRepairAvdSize $Paths 8G adb emulator-5554 } $freshPaths } '完整备份失败立即停止'
    Assert-Repairer ([IO.File]::ReadAllText($config) -ceq $updated) '备份失败不写容量配置'
    & $module {
        $script:Started = $false; $script:Edited = $false
        function script:Stop-JobsRepairAvd { param($Adb,$Serial,$Avd,$Directory) throw 'fixture shutdown timeout' }
        function script:Get-JobsRepairTool { param($Name) return $Name }
        function script:Assert-JobsRepairDefaultStorage { param($Paths,$Avd) }
        function script:Set-JobsRepairAvdSize { param($Paths,$TargetDataSize,$Adb,$Serial) $script:Edited = $true }
        function script:Start-JobsRepairColdAvd { param($Emulator,$Avd,$Serial) $script:Started = $true }
    }
    Assert-RepairerThrows { & $module { Expand-JobsRepairAvd adb emulator-5554 Demo 8G 800 } } '停机超时向上失败'
    Assert-Repairer (& $module { -not $script:Edited -and -not $script:Started }) '停机失败绝不修改配置或重启'
    & $module {
        function script:Stop-JobsRepairAvd { param($Adb,$Serial,$Avd,$Directory) }
        function script:Set-JobsRepairAvdSize { param($Paths,$TargetDataSize,$Adb,$Serial) $script:Edited = $true; return 'fixture-backup' }
        function script:Wait-JobsRepairBoot { param($Adb,$Serial,$Avd) }
        function script:Get-JobsRepairSpace { param($Adb,$Serial) return [pscustomobject]@{TotalKB=2097152; FreeKB=1024000; FreeMB=1000} }
    }
    Assert-RepairerThrows { & $module { Expand-JobsRepairAvd adb emulator-5554 Demo 8G 800 } } '冷启动后空间够但分区总量没增加仍不能报告扩容成功'
    Assert-Repairer (& $module { $script:Edited -and $script:Started }) '实际走过配置与冷启动后执行复测门禁'
    & $module {
        $script:SpaceCalls = 0
        function script:Get-JobsRepairSpace {
            param($Adb,$Serial)
            $script:SpaceCalls++
            if ($script:SpaceCalls -eq 1) { return [pscustomobject]@{TotalKB=2097152;FreeKB=1024;FreeMB=1} }
            return [pscustomobject]@{TotalKB=6291456;FreeKB=1024;FreeMB=1}
        }
    }
    Assert-RepairerThrows { & $module { Expand-JobsRepairAvd adb emulator-5554 Demo 8G 800 } } '容量增加但可用空间不足不报告修复成功'
    & $module {
        $script:SpaceCalls = 0
        function script:Get-JobsRepairSpace {
            param($Adb,$Serial)
            $script:SpaceCalls++
            if ($script:SpaceCalls -eq 1) { return [pscustomobject]@{TotalKB=2097152;FreeKB=1024;FreeMB=1} }
            return [pscustomobject]@{TotalKB=6291456;FreeKB=2097152;FreeMB=2048}
        }
    }
    & $module { Expand-JobsRepairAvd adb emulator-5554 Demo 8G 800 }
    Assert-Repairer (& $module { $script:SpaceCalls -eq 2 }) '前后实际分区与可用空间均满足才通过'
    & $module { function script:Get-JobsRepairSpace { param($Adb,$Serial) return ConvertFrom-JobsRepairDf (Invoke-JobsRepairAdb $Adb @('-s',$Serial,'shell','df','-k','/data')) } }
    & $module {
        $script:ReadonlyWrites = 0; $script:FreeKB = 1024000; $script:Location = 0
        $script:DeviceList = "List of devices attached`nemulator-5554`tdevice`n"
        function script:Get-JobsRepairTool { param($Name) return $Name }
        function script:Read-JobsRepairInput { param($Prompt) throw 'Check must not prompt' }
        function script:Write-JobsLog { param($Message) $script:ReadonlyWrites++; throw 'Check must not log' }
    }
    $hashBefore = (Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash
    & $module { Invoke-JobsAndroidRepair -Check }
    Assert-Repairer (& $module { $script:ReadonlyWrites -eq 0 }) '只读模式无确认、日志和设备写入'
    Assert-Repairer ((Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash -ceq $hashBefore) 'Check完整业务保留config字节'
    & $module { $script:FreeKB = 1024; $script:Commands = @() }
    Assert-RepairerThrows { & $module { Invoke-JobsAndroidRepair -Check } } 'Check低空间返回失败而非假成功'
    Assert-Repairer (& $module { @($script:Commands | Where-Object { $_ -match 'set-install-location|uninstall|compile|emu kill' }).Count -eq 0 }) 'Check异常也不执行修复写命令'
    $manifest = Get-Content -LiteralPath (Join-Path $root 'JobsAndroidSimulatorRepairer/Extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $installer = Import-Module (Join-Path $root 'JobsAndroidSimulatorRepairer/Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking -Force
    $plan = @(& $installer { param($Manifest,$Release) Get-JobsPackageRegistryPlan $Manifest $Release 'powershell.exe' } $manifest (Join-Path $temporary 'release'))
    Assert-Repairer ($plan.Count -eq 2) '安装仅包含一个桌面handler与独立CLSID'
    Assert-Repairer ($plan[0].Key -ceq 'Software\Classes\DesktopBackground\shellex\ContextMenuHandlers\Jobs.WindowsExtension.android-simulator-repair') '不注册所有目录背景'
    Assert-Repairer ($plan[1].InProcServer -like '*JobsAndroidSimulatorRepairerContextMenu.dll') '原生DLL属于独立修复包'
    Remove-Module $installer
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $root 'JobsAndroidSimulatorRepairer/Scripts') -File | Where-Object { $_.Extension -in @('.ps1','.psm1') })) {
        $bytes = [IO.File]::ReadAllBytes($file.FullName)
        Assert-Repairer ($bytes.Length -gt 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) ('5.1中文源码UTF8 BOM：' + $file.Name)
        $tokens = $null; $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
        Assert-Repairer (@($errors).Count -eq 0) ('Parser通过：' + $file.Name)
    }
    Write-Host ('PASS: AndroidSimulatorRepairer.Tests.ps1 (' + $script:assertions + ' assertions)')
} finally {
    if ($module) { Remove-Module $module -ErrorAction SilentlyContinue }
    $env:ANDROID_AVD_HOME = $oldAvd; $env:ANDROID_USER_HOME = $oldAndroidUser; $env:LOCALAPPDATA = $oldLocal
    $env:ANDROID_HOME = $oldSdkHome; $env:ANDROID_SDK_ROOT = $oldSdkRoot
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

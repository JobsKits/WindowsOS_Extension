# AndroidSimulatorCreator.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年10月22日，星期四.
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
function Assert-Android { param([bool]$Condition, [string]$Why) $script:assertions++; if (-not $Condition) { throw ('FAIL: ' + $Why) } }
function Assert-AndroidThrows { param([scriptblock]$Action, [string]$Why) $threw = $false; try { & $Action | Out-Null } catch { $threw = $true }; Assert-Android $threw $Why }
$package = Join-Path $root 'JobsAndroidSimulatorCreator'
$module = Import-Module (Join-Path $package 'Scripts/Action.psm1') -PassThru -DisableNameChecking
$installer = Import-Module (Join-Path $package 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
$temporary = Join-Path ([IO.Path]::GetTempPath()) ("JobsAndroid 中文 & 100% ' " + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$oldArch = $env:PROCESSOR_ARCHITECTURE; $oldArch2 = $env:PROCESSOR_ARCHITEW6432
$oldAvd = $env:ANDROID_AVD_HOME; $oldJava = $env:JAVA_HOME; $oldSdk = $env:ANDROID_HOME; $oldSdkRoot = $env:ANDROID_SDK_ROOT
try {
    $manifest = Get-Content -LiteralPath (Join-Path $package 'Extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $plan = @(Get-JobsPackageRegistryPlan $manifest $temporary 'powershell.exe')
    Assert-Android ($plan.Count -eq 2) '只注册桌面背景与 CLSID'
    Assert-Android ($plan[0].Key -eq 'Software\Classes\DesktopBackground\shellex\ContextMenuHandlers\Jobs.WindowsExtension.android-simulator-create') '系统桌面专用 handler'
    Assert-Android ($plan[1].InProcServer -eq (Join-Path $temporary 'bin/JobsAndroidSimulatorCreatorContextMenu.dll')) 'DLL 在自身 release'
    Assert-Android (@($plan | Where-Object { $_.Key -match '\\Directory|\\Drive|\\\*|\\shell\\' }).Count -eq 0) '不注册普通目录、磁盘、选中项静态菜单'
    $release = Join-Path $temporary 'release'
    New-JobsPackageRelease $package $release | Out-Null
    foreach ($name in @('ContextMenu.cpp', 'ContextMenu.def', 'DesktopScope.h', 'Build.ps1', 'OpenCmd.ps1', 'CreateAndroidSimulator.ps1')) {
        Assert-Android (Test-Path -LiteralPath (Join-Path $release ('Scripts/' + $name))) ('独立 release 包含 ' + $name)
    }
    $env:PROCESSOR_ARCHITEW6432 = ''; $env:PROCESSOR_ARCHITECTURE = 'AMD64'
    Assert-Android ((& $module { Get-JobsAndroidArchitecture }) -ceq 'x86_64') 'x64 对应 x86_64 镜像'
    $env:PROCESSOR_ARCHITEW6432 = 'ARM64'
    Assert-AndroidThrows { & $module { Get-JobsAndroidArchitecture } } '真实 ARM 宿主不误用 WOW64 x64 镜像'
    $env:PROCESSOR_ARCHITEW6432 = ''; $env:PROCESSOR_ARCHITECTURE = 'x86'
    Assert-AndroidThrows { & $module { Get-JobsAndroidArchitecture } } '32 位宿主明确停止'
    $listing = @'
Installed packages:
system-images;android-35;google_apis;x86_64 | 1 | Android 35
system-images;android-36;default;x86_64 | 1 | Android 36
system-images;android-36;google_apis;x86_64 | 1 | Android 36
system-images;android-36;google_apis;x86_64 | 1 | duplicate
system-images;android-36.1;google_apis;x86_64 | 1 | stable minor
system-images;android-36-ext19;google_apis;x86_64 | 1 | stable extension
system-images;android-37-preview;google_apis;x86_64 | 1 | preview
system-images;android-99;google_apis;arm64-v8a | 1 | wrong host
system-images;android-36;android-tv;x86_64 | 1 | not phone
'@
    $images = @(& $module { param($Text) Get-JobsAndroidImages $Text x86_64 } $listing)
    Assert-Android ($images.Count -eq 5) '镜像去重且支持稳定 minor/ext，排除异构、代号预览、TV'
    Assert-Android ($images[0] -ceq 'system-images;android-36.1;google_apis;x86_64') '默认最新稳定 Google APIs'
    $devices = @(& $module { Get-JobsAndroidDevices "id: 0 or `"Nexus 5`"`nid: 1 or `"pixel_9`"`nid: 2 or `"pixel_8`"" })
    Assert-Android ($devices.Count -eq 3 -and $devices[0] -eq 'pixel_9') '保留含空格的有效硬件 id'
    $env:ANDROID_AVD_HOME = $temporary
    Assert-Android ((& $module { Get-JobsAndroidAvdHome }) -ceq $temporary) '保留用户自定义 AVD_HOME'
    $name = & $module { param($Path) New-JobsAndroidAvdName pixel_9 'system-images;android-36;google_apis;x86_64' @() $Path } $temporary
    Assert-Android ($name -match '^Jobs_pixel_9_API36_[0-9a-f]{8}$') '新名字安全且带设备/API/唯一标识'
    & $module { $script:Answer = ''; function script:Read-JobsAndroidInput { param($Prompt) return $script:Answer } }
    Assert-Android ((& $module { Read-JobsAndroidChoice '选择' @('first', 'second') }) -eq 'first') '编号回车选择首项'
    & $module { $script:Answer = '2' }
    Assert-Android ((& $module { Read-JobsAndroidChoice '选择' @('first', 'second') }) -eq 'second') '编号选择第二项'
    & $module { $script:Answer = 'q' }
    Assert-AndroidThrows { & $module { Read-JobsAndroidChoice '选择' @('first') } } 'q 停止'
    & $module { $script:Answer = '' }
    & $module { Show-JobsAndroidIntro 'sdk-fixture' }
    Assert-Android $true '首屏自述回车继续自动补齐'
    & $module { $script:Answer = 'cancel' }
    Assert-AndroidThrows { & $module { Show-JobsAndroidIntro 'sdk-fixture' } } '首屏非空输入在补齐前取消'
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        $result = & $module { Invoke-JobsAndroidTool /bin/echo "SDK 中文 & 100% '" sdkmanager @('--sdk_root=SDK 中文 & 100%', '--version') }
        Assert-Android ($result -match 'toolsdir=SDK 中文 & 100% '' -classpath' -and $result -match 'SdkManagerCli --sdk_root=SDK 中文 & 100% --version') 'Java argv 保留特殊路径且参数彼此独立'
        Assert-AndroidThrows { & $module { Invoke-JobsAndroidTool /usr/bin/false tools sdkmanager @('--version') } } 'Java 非零退出传播'
    }
    & $module {
        param($Sdk)
        $script:FixtureSdk = $Sdk; $script:Calls = @(); $script:Created = $false; $script:Booted = $false; $script:FailCreate = $false; $script:Choice = 'create'; $script:ModePromptCount = 0; $script:ImagesInstalled = $true; $script:CancelImages = $false
        function script:Test-JobsAndroidDesktop { param($Target) return $Target -eq 'desktop-fixture' }
        function script:Get-JobsAndroidArchitecture { return 'x86_64' }
        function script:Get-JobsAndroidSdk { return $script:FixtureSdk }
        function script:Get-JobsAndroidJava { return (Join-Path $script:FixtureSdk 'jbr/bin/java.exe') }
        function script:Get-JobsAndroidTools { param($Sdk) return $Sdk }
        function script:Read-JobsAndroidChoice { param($Prompt, $Items) if ($Prompt -like '*待安装*' -and $script:CancelImages) { throw 'fixture cancelled image selection' }; if ($Prompt -eq '操作') { $script:ModePromptCount++ }; if ($Prompt -eq '操作' -and $script:Choice -eq 'existing') { return $Items[1] }; return $Items[0] }
        function script:Read-JobsAndroidInput { param($Prompt) return '' }
        function script:Write-JobsLog { param($Message) }
        function script:Invoke-JobsAndroidTool {
            param($Java, $Tools, $Tool, $Arguments, $InputText, [switch]$Interactive)
            $script:Calls += ($Tool + ' ' + ($Arguments -join ' '))
            if ($Arguments -contains '--list_installed') { if ($script:ImagesInstalled) { return 'system-images;android-36;google_apis;x86_64 | 1 | Android' }; return '' }
            if ($Arguments -contains '--list') { return 'system-images;android-36;google_apis;x86_64 | 1 | Android' }
            if ($Arguments -contains '--install') { $script:ImagesInstalled = $true }
            if ($Arguments -contains 'create') {
                if ($script:FailCreate) { throw 'fixture create failed' }
                $script:Created = $true; $script:CreatedName = $Arguments[[array]::IndexOf($Arguments, '--name') + 1]
                if ($InputText -ne "no`n") { throw 'AVD prompt answer missing' }
            }
            if ($Arguments -contains 'device' -and $Arguments -notcontains '-c') { return 'id: 0 or "pixel_9"' }
            return 'healthy'
        }
        function script:Invoke-JobsProcess {
            param($FilePath, $Arguments, $TimeoutSeconds)
            $output = ''
            if ($Arguments -contains '-list-avds') { $output = 'existing'; if ($script:Created) { $output += "`n" + $script:CreatedName } }
            return [pscustomobject]@{ ExitCode = 0; StdOut = $output; StdErr = '' }
        }
        function script:Start-JobsAndroidAvd { param($Sdk, $Name) $script:Booted = $true; $script:BootName = $Name }
    } $temporary
    # Both prerequisites exist, so this branch must never ask to download.
    [void][IO.Directory]::CreateDirectory((Join-Path $temporary 'emulator'))
    [void][IO.Directory]::CreateDirectory((Join-Path $temporary 'platform-tools'))
    [IO.File]::WriteAllText((Join-Path $temporary 'emulator/emulator.exe'), 'fixture')
    [IO.File]::WriteAllText((Join-Path $temporary 'platform-tools/adb.exe'), 'fixture')
    $env:ANDROID_HOME = 'original-sdk'; $env:JAVA_HOME = 'original-java'; $env:ANDROID_SDK_ROOT = 'original-sdk-root'
    & $module { Invoke-JobsAndroidSimulatorAction desktop-fixture }
    Assert-Android (& $module { $script:Created -and $script:Booted -and $script:BootName -eq $script:CreatedName }) '创建、清单复核后再启动同一个 AVD'
    Assert-Android (& $module { @($script:Calls | Where-Object { $_ -match '--force|--install|--licenses|delete' }).Count -eq 0 }) '已有 SDK/镜像不下载、不覆盖、不删除'
    Assert-Android ($env:ANDROID_HOME -eq 'original-sdk' -and $env:JAVA_HOME -eq 'original-java' -and $env:ANDROID_SDK_ROOT -eq 'original-sdk-root') '成功后恢复进程变量'
    & $module { $script:Created = $false; $script:Booted = $false; $script:FailCreate = $true }
    Assert-AndroidThrows { & $module { Invoke-JobsAndroidSimulatorAction desktop-fixture } } '创建失败原样传播'
    Assert-Android (-not (& $module { $script:Booted })) '创建失败不启动或报告成功'
    Assert-Android ($env:ANDROID_HOME -eq 'original-sdk' -and $env:JAVA_HOME -eq 'original-java' -and $env:ANDROID_SDK_ROOT -eq 'original-sdk-root') '失败后恢复进程变量'
    Assert-AndroidThrows { & $module { Invoke-JobsAndroidSimulatorAction folder-fixture } } '点击时复核普通 folder 目标'
    & $module { $script:Choice = 'existing'; $script:FailCreate = $false; $script:Calls = @() }
    & $module { Invoke-JobsAndroidSimulatorAction desktop-fixture }
    Assert-Android (& $module { $script:BootName -eq 'existing' -and @($script:Calls | Where-Object { $_ -match ' create ' }).Count -eq 0 }) '已有 AVD 分支仅启动选择项'
    & $module { $script:ModePromptCount = 0; $script:Choice = 'existing'; Invoke-JobsAndroidSimulatorAction desktop-fixture -Create }
    Assert-Android (& $module { $script:ModePromptCount -eq 0 -and $script:Created -and $script:BootName -eq $script:CreatedName }) '桌面入口直接新建，不多弹操作选择'

    $hadReceipt = Test-Path Env:JOBS_FLUTTER_CREATED_DEVICE_FILE
    $savedReceipt = $env:JOBS_FLUTTER_CREATED_DEVICE_FILE
    $receipt = Join-Path $temporary 'created-device.tsv'
    try {
        $env:JOBS_FLUTTER_CREATED_DEVICE_FILE = $receipt
        & $module { function script:Start-JobsAndroidAvd { return 'emulator-5570' }; Invoke-JobsAndroidSimulatorAction desktop-fixture -Create }
        Assert-Android ([IO.File]::ReadAllText($receipt) -ceq "Android`temulator-5570`n") '创建并启动成功后才返回精确serial供Flutter承接'
        [IO.File]::Delete($receipt)
        & $module { $script:FailCreate = $true }
        Assert-AndroidThrows { & $module { Invoke-JobsAndroidSimulatorAction desktop-fixture -Create } } '创建失败仍保持失败码'
        Assert-Android (-not [IO.File]::Exists($receipt)) '创建失败不写入Flutter目标结果'
    } finally {
        & $module { $script:FailCreate = $false; function script:Start-JobsAndroidAvd { param($Sdk, $Name) $script:Booted = $true; $script:BootName = $Name } }
        if ($hadReceipt) { $env:JOBS_FLUTTER_CREATED_DEVICE_FILE = $savedReceipt } else { Remove-Item Env:JOBS_FLUTTER_CREATED_DEVICE_FILE -ErrorAction SilentlyContinue }
    }

    & $module { $script:ImagesInstalled = $false; $script:Calls = @(); Invoke-JobsAndroidSimulatorAction desktop-fixture -Create }
    Assert-Android (& $module { @($script:Calls | Where-Object { $_ -match '--list --channel=0' }).Count -eq 1 }) '镜像为空自动查询官方清单'
    Assert-Android (& $module { @($script:Calls | Where-Object { $_ -match '--install system-images;' }).Count -eq 1 -and $script:Booted }) '选中镜像直接安装并复检后创建'
    Assert-Android (& $module { @($script:Calls | Where-Object { $_ -match '--licenses' }).Count -eq 1 }) 'SDK许可仍由官方原生交互处理'
    & $module { $script:ImagesInstalled = $false; $script:CancelImages = $true; $script:Calls = @() }
    Assert-AndroidThrows { & $module { Invoke-JobsAndroidSimulatorAction desktop-fixture -Create } } '自动查询后仍可取消镜像选择'
    Assert-Android (& $module { @($script:Calls | Where-Object { $_ -match '--install' }).Count -eq 0 }) '取消镜像选择不安装镜像'
    $native = Get-Content -LiteralPath (Join-Path $package 'Scripts/ContextMenu.cpp') -Raw -Encoding UTF8
    Assert-Android ($native.Contains('if (selection) return S_OK;') -and $native.Contains('!IsDesktop(target)')) '原生菜单生成/点击双检且拒绝选中项'
    $source = Get-Content -LiteralPath (Join-Path $package 'Scripts/Action.psm1') -Raw -Encoding UTF8
    Assert-Android ($source.Contains('sys.boot_completed') -and $source.Contains('AddSeconds(180)')) '成功需要系统启动完成且有等待上限'
    Assert-Android (-not $source.Contains('Confirm-JobsAndroidDownload') -and -not $source.Contains('输入 YES')) '依赖与镜像没有逐项确认'
    Assert-Android (-not $source.Contains('Start-Process -FilePath $java')) 'Java 不经二次 Shell'
    Write-Host ('PASS: AndroidSimulatorCreator.Tests.ps1 (' + $script:assertions + ' assertions)')
} finally {
    $env:PROCESSOR_ARCHITECTURE = $oldArch; $env:PROCESSOR_ARCHITEW6432 = $oldArch2
    $env:ANDROID_AVD_HOME = $oldAvd; $env:JAVA_HOME = $oldJava; $env:ANDROID_HOME = $oldSdk; $env:ANDROID_SDK_ROOT = $oldSdkRoot
    Remove-Module $module; Remove-Module $installer
    Remove-Item -LiteralPath $temporary -Recurse -Force
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

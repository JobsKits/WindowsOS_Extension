# Installer.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026-10-18.
# Windows 注册测试只写入本次 GUID 隔离目录，绝不使用真实菜单键。
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
$script:Assertions = 0
$scripts = Join-Path (Split-Path -Parent $PSScriptRoot) 'Scripts'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'JobsPathCopier/Scripts/Common.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $scripts 'Catalog.psm1') -Force -DisableNameChecking
$packageInstaller = Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'JobsPathCopier/Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
function Get-JobsRegistryPlan {
    param([string[]]$Features, [string]$ReleasePath, [string]$PowerShellPath)
    $known = @(Get-JobsFeaturePackages)
    foreach ($id in $Features) { if ($id -notin @($known.Id)) { throw 'Unknown feature' } }
    foreach ($feature in $known) {
        $ownInstaller = Import-Module (Join-Path $feature.PackagePath 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
        & $ownInstaller { param($Manifest, $Release, $PowerShell, $Enabled) Get-JobsPackageRegistryPlan -Manifest $Manifest -ReleasePath $Release -PowerShellPath $PowerShell -Enabled $Enabled } $feature $ReleasePath $PowerShellPath ($feature.Id -in $Features)
    }
}

function Assert-JobsTest {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
    $script:Assertions++
}

function Assert-JobsThrows {
    param([scriptblock]$Body, [string]$Message)
    $threw = $false
    try { & $Body } catch { $threw = $true }
    Assert-JobsTest $threw $Message
}

$features = @(Get-JobsFeaturePackages)
$parsedCatalog = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'Extensions.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$expectedCount = @($parsedCatalog).Count
Assert-JobsTest ($features.Count -eq $expectedCount) '提供登记的独立功能'
Assert-JobsTest (@($features.Id | Select-Object -Unique).Count -eq $expectedCount) '功能标识唯一'
$release = Join-Path ([IO.Path]::GetTempPath()) 'Jobs 中文 & 100% release'
$powerShell = Join-Path $PSHOME 'powershell.exe'
$all = @(Get-JobsRegistryPlan -Features @($features.Id) -ReleasePath $release -PowerShellPath $powerShell)
Assert-JobsTest ($all.Count -gt 0) '注册计划非空'
Assert-JobsTest (@($all.Key | Select-Object -Unique).Count -eq $all.Count) '每个菜单键唯一'
Assert-JobsTest (@($all | Where-Object { -not $_.Enabled -and $_.Key -notmatch 'Jobs\.WindowsExtension\.flutter-(pub-get|version-manager|sdk-inspector|dependency-extract|run|package|doctor|codegen)$' -and $_.Key -notmatch '\\shell\\Jobs\.WindowsExtension\.open-(android-studio|vscode)$' }).Count -eq 0) '全选当前功能启用；仅固定旧 Flutter / IDE 静态菜单按迁移计划停用'

foreach ($feature in $features) {
    if ($feature.Id -eq 'flutter-tools') {
        $native = @($all | Where-Object { $_.Enabled -and ($_.Key.EndsWith('Jobs.WindowsExtension.flutter-tools') -or $_.Key.EndsWith('CLSID\{55C8C7A9-8625-4AF0-8598-DFA975064F0C}')) })
        Assert-JobsTest ($native.Count -eq 4) '统一 Flutter 只启用三个项目 handler 和 CLSID'
        Assert-JobsTest (@($native | Where-Object { $_.Key -match '\\shell\\' }).Count -eq 0) '统一 Flutter 不启用始终可见的静态菜单'
        continue
    }
    if ($feature.Id -eq 'hidden-files-toggle') {
        $clsid = '{F92F7AF9-65B6-41CB-A6D8-712F01F79126}'
        $native = @($all | Where-Object { $_.Key.EndsWith('Jobs.WindowsExtension.hidden-files-toggle') -or $_.Key.EndsWith('CLSID\' + $clsid) })
        Assert-JobsTest ($native.Count -eq 2) '隐藏文件只注册桌面 handler 和独立 CLSID'
        Assert-JobsTest (@($native | Where-Object { $_.Key -eq 'Software\Classes\DesktopBackground\shellex\ContextMenuHandlers\Jobs.WindowsExtension.hidden-files-toggle' }).Count -eq 1) '隐藏文件只适用于桌面背景'
        continue
    }
    if ($feature.Id -in @('open-android-studio', 'open-vscode')) {
        $clsid = '{9D337A22-B981-4C26-B586-9CC8CE7B3292}'
        if ($feature.Id -eq 'open-vscode') { $clsid = '{5B0C107E-53D8-4787-AE32-13D11CC5A07A}' }
        $native = @($all | Where-Object { $_.Enabled -and ($_.Key.EndsWith('Jobs.WindowsExtension.' + $feature.Id) -or $_.Key.EndsWith('CLSID\' + $clsid)) })
        Assert-JobsTest ($native.Count -eq 4) 'IDE 只启用三个目录 handler 和独立 CLSID'
        Assert-JobsTest (@($native | Where-Object { $_.Key.Contains('\shell\') }).Count -eq 0) 'IDE 不启用旧静态入口'
        $legacy = @($all | Where-Object { -not $_.Enabled -and $_.Key.EndsWith('\shell\Jobs.WindowsExtension.' + $feature.Id) })
        Assert-JobsTest ($legacy.Count -eq 4) 'IDE 精确停用四个旧静态入口'
        continue
    }
    if ($feature.Id -eq 'open-sourcetree') {
        $clsid = '{CF4D4697-749B-4C37-98EC-0952B2EF1E16}'
        $native = @($all | Where-Object { $_.Key.EndsWith('Jobs.WindowsExtension.open-sourcetree') -or $_.Key.EndsWith('CLSID\' + $clsid) })
        Assert-JobsTest ($native.Count -eq 4) 'Sourcetree只注册三个动态处理器和独立 CLSID'
        Assert-JobsTest (@($native | Where-Object { $_.Key -match '\\shell\\' }).Count -eq 0) 'Sourcetree不注册始终可见的静态菜单'
        foreach ($class in @('Directory', 'Directory\Background', 'Drive')) {
            $key='Software\Classes\' + $class + '\shellex\ContextMenuHandlers\Jobs.WindowsExtension.open-sourcetree'
            Assert-JobsTest (@($native | Where-Object { $_.Key -ceq $key -and $_.Values[''] -ceq $clsid }).Count -eq 1) ('Sourcetree精确上下文：' + $class)
        }
        $server=@($native | Where-Object { $_.Key.EndsWith('CLSID\' + $clsid) })
        Assert-JobsTest ($server.Count -eq 1 -and $server[0].InProcServer -ceq (Join-Path $release 'bin/JobsSourcetreeOpenerContextMenu.dll')) 'Sourcetree CLSID 精确归属于本包 DLL'
        continue
    }
    if ($feature.Id -eq 'git-rollback') {
        $clsid = '{E58D6868-A650-42EB-9629-E97338918229}'
        $native = @($all | Where-Object { $_.Key.EndsWith('Jobs.WindowsExtension.git-rollback') -or $_.Key.EndsWith('CLSID\' + $clsid) })
        Assert-JobsTest ($native.Count -eq 4) 'Git 回退只注册三个动态处理器和独立 CLSID'
        Assert-JobsTest (@($native | Where-Object { $_.Key -match '\\shell\\' }).Count -eq 0) 'Git 回退不注册始终可见的静态菜单'
        foreach ($class in @('Directory', 'Directory\Background', 'Drive')) {
            $key='Software\Classes\' + $class + '\shellex\ContextMenuHandlers\Jobs.WindowsExtension.git-rollback'
            Assert-JobsTest (@($native | Where-Object { $_.Key -ceq $key -and $_.Values[''] -ceq $clsid }).Count -eq 1) ('Git 回退精确上下文：' + $class)
        }
        $server=@($native | Where-Object { $_.Key.EndsWith('CLSID\' + $clsid) })
        Assert-JobsTest ($server.Count -eq 1 -and $server[0].InProcServer -ceq (Join-Path $release 'bin/JobsGitRollbackContextMenu.dll')) 'Git 回退 CLSID 精确归属于本包 DLL'
        continue
    }
    if ($feature.Id -eq 'git-proxy-configure') {
        $desktop = @($all | Where-Object { $_.Key.EndsWith('Jobs.WindowsExtension.git-proxy-configure') })
        Assert-JobsTest ($desktop.Count -eq 1) 'Git 配置只注册一个桌面空白入口'
        Assert-JobsTest ($desktop[0].Key -eq 'Software\Classes\DesktopBackground\shell\Jobs.WindowsExtension.git-proxy-configure') 'Git 配置不进入普通目录、磁盘和选中项'
        continue
    }
    if ($feature.Id -in @('android-simulator-create', 'android-simulator-repair', 'harmony-simulator-create', 'harmony-simulator-repair')) {
        $clsid = '{9591D98B-3481-4E05-BE24-470FCDFD0E23}'
        if ($feature.Id -eq 'android-simulator-repair') { $clsid = '{A6D8DCE0-B691-4CC9-A3C5-F02B8BC704E5}' }
        if ($feature.Id -eq 'harmony-simulator-repair') { $clsid = '{C91A8F93-CA7B-4F28-B705-A0AC90C5F231}' }
        if ($feature.Id -eq 'harmony-simulator-create') { $clsid = '{95E5B535-2EB8-48CA-98B5-A14D17A0A859}' }
        $native = @($all | Where-Object { $_.Key.EndsWith('Jobs.WindowsExtension.' + $feature.Id) -or $_.Key.EndsWith('CLSID\' + $clsid) })
        Assert-JobsTest ($native.Count -eq 2) ('模拟器桌面 handler 与 CLSID 独立：' + $feature.Id)
        Assert-JobsTest (@($native | Where-Object { $_.Key -eq ('Software\Classes\DesktopBackground\shellex\ContextMenuHandlers\Jobs.WindowsExtension.' + $feature.Id) }).Count -eq 1) ('只登记系统桌面背景 handler：' + $feature.Id)
        Assert-JobsTest (@($native | Where-Object { $_.Key -match '\\Directory|\\Drive|\\\*|\\shell\\' }).Count -eq 0) ('模拟器不注册普通目录与选中项：' + $feature.Id)
        continue
    }
    if ($feature.Id -in @('flutter-run', 'flutter-package', 'flutter-doctor', 'flutter-codegen')) {
        $clsid = '{239D7884-83C5-4D66-AB0C-14A2667DCD61}'
        if ($feature.Id -eq 'flutter-package') { $clsid = '{64A7C5BE-E031-4E89-A2D7-75C3F62B1AC9}' }
        if ($feature.Id -eq 'flutter-doctor') { $clsid = '{A41E939F-64E7-49DD-85FA-81F9B8CFD5E2}' }
        if ($feature.Id -eq 'flutter-codegen') { $clsid = '{DD71AE09-8A16-4B08-9868-5A40A9F39F63}' }
        $native = @($all | Where-Object { $_.Key.EndsWith('Jobs.WindowsExtension.' + $feature.Id) -or $_.Key.EndsWith('CLSID\' + $clsid) })
        Assert-JobsTest ($native.Count -eq 4) 'Flutter 运行包只注册三个动态处理器和独立 CLSID'
        Assert-JobsTest (@($native | Where-Object { $_.Key -match '\\shell\\' }).Count -eq 0) 'Flutter 运行包不残留始终可见的静态菜单'
        continue
    }
    if ($feature.Id -eq 'command-shortcut-create') {
        $clsid = '{A29030C5-2C96-48BF-BBF2-75D80CC8AF80}'
        $native = @($all | Where-Object { $_.Key.EndsWith('Jobs.WindowsExtension.' + $feature.Id) -or $_.Key.EndsWith('CLSID\' + $clsid) })
        Assert-JobsTest ($native.Count -eq 2) '快捷入口包仅目录 handler 和本包 CLSID'
        Assert-JobsTest (@($native | Where-Object { $_.Key -match '\\shell\\|DesktopBackground|\\Drive|\\Directory\\Background' }).Count -eq 0) '快捷入口不注册始终可见的静态或背景菜单'
        continue
    }
    if ($feature.Id -in @('run-authorize', 'run-authorization-revoke', 'file-content-viewer', 'file-hash', 'file-volumes')) {
        $clsid = '{AE09A13F-EF17-4CE3-8BA1-F557C34280DE}'
        if ($feature.Id -eq 'run-authorization-revoke') { $clsid = '{6AC50F49-6915-4130-8474-F99DA4D074D6}' }
        if ($feature.Id -eq 'file-content-viewer') { $clsid = '{DBC7884D-ECD9-43CB-A026-AFD8A9BBC2A7}' }
                if ($feature.Id -eq 'file-hash') { $clsid = '{CD2D9483-9017-4717-96E3-B7153427F0C6}' }
        if ($feature.Id -eq 'file-volumes') { $clsid = '{6F7BA84C-324C-472C-B618-B0E3D44244DB}' }
        $native = @($all | Where-Object { $_.Key.EndsWith('Jobs.WindowsExtension.' + $feature.Id) -or $_.Key.EndsWith('CLSID\' + $clsid) })
        Assert-JobsTest ($native.Count -eq 2) '权限包仅普通单文件原生 handler 和 CLSID'
        Assert-JobsTest (@($native | Where-Object { $_.Key -match '\\Directory|\\Drive|DesktopBackground' }).Count -eq 0) '运行权限不注册目录或背景'
        continue
    }
    $items = @($all | Where-Object { $_.Key.EndsWith('\Jobs.WindowsExtension.' + $feature.Id) })
    $expectedCount = 4
    if ($feature.DirectoryOnly) { $expectedCount = 3 }
    Assert-JobsTest ($items.Count -eq $expectedCount) ('上下文数量：' + $feature.Id)
    foreach ($class in @('Directory', 'Directory\Background', 'Drive')) {
        $key = 'Software\Classes\' + $class + '\shell\Jobs.WindowsExtension.' + $feature.Id
        Assert-JobsTest (@($items | Where-Object { $_.Key -eq $key }).Count -eq 1) ('目录/背景/磁盘：' + $class + '/' + $feature.Id)
    }
    $fileCount = @($items | Where-Object { $_.Key.StartsWith('Software\Classes\*\') }).Count
    Assert-JobsTest ($fileCount -eq [int](-not $feature.DirectoryOnly)) ('文件上下文遵守适用条件：' + $feature.Id)
    foreach ($item in $items) {
        $placeholder = '%1'
        if ($item.Key.Contains('\Directory\Background\')) { $placeholder = '%V' }
        Assert-JobsTest ($item.Command.EndsWith('-Target "' + $placeholder + '|JobsPathEnd"')) ('占位符和盘符反斜杠保护：' + $item.Key)
        Assert-JobsTest ($item.Command.Contains('-File ' + (Quote-JobsArgument (Join-Path $release 'Scripts/Invoke.ps1')))) '运行文件使用独立参数'
        Assert-JobsTest (-not $item.Command.Contains(' -Command ')) '注册命令不解释目标路径为脚本'
    }
}

$one = @(Get-JobsRegistryPlan -Features @($features[0].Id) -ReleasePath $release -PowerShellPath $powerShell)
Assert-JobsTest (@($one | Where-Object { $_.Enabled }).Count -eq @($all | Where-Object { $_.Key.EndsWith('\Jobs.WindowsExtension.' + $features[0].Id) }).Count) '单项选择只启用该项上下文'
$none = @(Get-JobsRegistryPlan -Features @() -ReleasePath $release -PowerShellPath $powerShell)
Assert-JobsTest (@($none | Where-Object { $_.Enabled }).Count -eq 0) '全不选保留完整删除计划'
Assert-JobsThrows { Get-JobsRegistryPlan -Features @('unknown-feature') -ReleasePath $release -PowerShellPath $powerShell } '未知标识立即拒绝'

if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
    if (-not ('Jobs.InstallerTestNative' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Jobs {
    public static class InstallerTestNative {
        [DllImport("shell32.dll", SetLastError = true)]
        private static extern IntPtr CommandLineToArgvW([MarshalAs(UnmanagedType.LPWStr)] string commandLine, out int count);
        [DllImport("kernel32.dll")]
        private static extern IntPtr LocalFree(IntPtr memory);
        public static string[] Arguments(string commandLine) {
            int count;
            IntPtr values = CommandLineToArgvW(commandLine, out count);
            if (values == IntPtr.Zero) throw new InvalidOperationException("CommandLineToArgvW failed");
            try {
                string[] result = new string[count];
                for (int i = 0; i < count; i++) result[i] = Marshal.PtrToStringUni(Marshal.ReadIntPtr(values, i * IntPtr.Size));
                return result;
            } finally { LocalFree(values); }
        }
    }
}
'@
    }
    $rootPath = [IO.Path]::GetPathRoot([Environment]::SystemDirectory)
    foreach ($target in @($rootPath, 'C:\研发 & 团队\100% done', 'C:\引号''与`字符\file.txt')) {
        foreach ($item in @($all[0], @($all | Where-Object { $_.Key.Contains('\Directory\Background\') })[0])) {
            $placeholder = '%1'
            if ($item.Key.Contains('\Directory\Background\')) { $placeholder = '%V' }
            $command = $item.Command.Replace($placeholder, $target)
            $argv = [Jobs.InstallerTestNative]::Arguments($command)
            Assert-JobsTest ($argv[0] -eq $powerShell) '原生 argv 保留 PowerShell 路径'
            $fileIndex = [Array]::IndexOf($argv, '-File')
            $targetIndex = [Array]::IndexOf($argv, '-Target')
            Assert-JobsTest ($fileIndex -gt 0 -and $argv[$fileIndex + 1] -eq (Join-Path $release 'Scripts/Invoke.ps1')) '原生 argv 保留中文/空格/&/% 的安装路径'
            Assert-JobsTest ($targetIndex -gt 0 -and $argv[$targetIndex + 1] -eq ($target + '|JobsPathEnd')) '原生 argv 保留中文/&/%/根盘符目标'
            Assert-JobsTest ($argv.Count -eq $targetIndex + 2) '目标字符没有增加命令参数'
        }
    }

} else {
    Write-Host 'SKIP: 原生 argv 测试需要 Windows；注册事务另见 PackageInstaller.Tests.ps1。'
}
Write-Host ('PASS: Installer.Tests.ps1 (' + $script:Assertions + ' assertions)')

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

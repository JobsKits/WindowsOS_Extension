# Architecture.Tests.ps1 | WindowsOS@Extension 独立包架构回归
# Created by Jobs on 2026年10月18日，星期日.

# JOBS_SOURCE_LAYOUT_ROOT_V1：只解析本文件逻辑目录，发布 flat 副本保持原资源基准。

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
$script:JobsLayoutArchitectureTestsRoot = $(if ([IO.Path]::GetFileName($PSScriptRoot) -ceq 'Architecture.Tests.ps1') { Split-Path -Parent $PSScriptRoot } else { $PSScriptRoot })

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
$root = Split-Path -Parent ${script:JobsLayoutArchitectureTestsRoot}
Import-Module (Join-Path $root 'Scripts/Catalog.psm1') -Force -DisableNameChecking
$script:assertions = 0
function Assert-Architecture {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
    $script:assertions++
}
$packages = @(Get-JobsFeaturePackages -Root $root)
$parsedCatalog = Get-Content -LiteralPath (Join-Path $root 'Extensions.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$expectedCount = @($parsedCatalog).Count
Assert-Architecture ($packages.Count -eq $expectedCount) '登记的功能工程单独列出'
Assert-Architecture (@($packages.Name | Select-Object -Unique).Count -eq $expectedCount) '功能目录唯一'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('JobsStandalone-' + [guid]::NewGuid().ToString('N'))
$savedLocal = $env:LOCALAPPDATA
try {
    [void][IO.Directory]::CreateDirectory($temporary)
    $env:LOCALAPPDATA = Join-Path $temporary 'UserData'
    $roots = @()
    foreach ($package in $packages) {
        # 整个独立目录拷到一个没有父工程的临时位置，导入/打包时没有父目录可回退。
        $standalone = Join-Path $temporary $package.Name
        Copy-Item -LiteralPath $package.PackagePath -Destination $standalone -Recurse
        foreach ($name in @('Extension.json', 'Manage.cmd', 'README.md', 'Scripts/Action.psm1')) {
            Assert-Architecture (Test-Path -LiteralPath (Join-Path $standalone $name) -PathType Leaf) ('独立交付文件齐全：' + $package.Id + '/' + $name)
        }
        foreach ($script in Get-ChildItem -LiteralPath (Join-Path $standalone 'Scripts') -File) {
            $source = Get-Content -LiteralPath $script.FullName -Raw
            Assert-Architecture ($source -notmatch '(?:\.\.[\\/])+(?:Scripts|Infrastructure|Jobs[A-Z])') ('包不引用父工程或其它功能：' + $script.Name)
        }
        if ($package.Id -eq 'harmony-simulator-create') {
            foreach ($name in @('Run.cmd', 'Scripts/Build.ps1', 'Scripts/ContextMenu.cpp', 'Scripts/DesktopScope.h', 'Scripts/CreateHarmonySimulator.ps1', 'Scripts/HarmonyTools.ps1')) {
                Assert-Architecture (Test-Path -LiteralPath (Join-Path $standalone $name) -PathType Leaf) ('鸿蒙独立运行与原生源码齐全：' + $name)
            }
            Assert-Architecture (@($package.InfrastructureOverrides).Count -eq 1 -and $package.InfrastructureOverrides[0] -ceq 'PackageInstaller.psm1') '鸿蒙安装器独立覆盖且保留其它基础设施模板'
        }
        if ($package.Id -ceq 'open-git-remote') {
            Assert-Architecture ($package.Name -ceq 'JobsGitRemoteOpener' -and @($package.InfrastructureOverrides).Count -eq 1 -and $package.InfrastructureOverrides[0] -ceq 'Invoke.ps1') 'Git 远端包仅覆盖自己的多远端选择入口'
            $invokeSource = [IO.File]::ReadAllText((Resolve-JobsScriptLayoutPath (Join-Path $standalone 'Scripts/Invoke.ps1')))
            Assert-Architecture ($invokeSource.Contains('[switch]$SelectRemote') -and $invokeSource.Contains('$console = [bool]$manifest.Console -or $SelectRemote')) '独立远端入口保留显式多远端控制台模式'
            Assert-Architecture ($invokeSource.Contains('Invoke-JobsFeature -Target $Path -Interactive:$Interactive')) '多远端选择仍转交本包业务并保留交互标志'
        }
        $action = Import-Module (Join-Path $standalone 'Scripts/Action.psm1') -PassThru -DisableNameChecking
        Assert-Architecture ($action.ExportedCommands.ContainsKey('Invoke-JobsFeature')) ('独立业务可载入：' + $package.Id)
        $common = Import-Module (Join-Path $standalone 'Scripts/Common.psm1') -PassThru -DisableNameChecking
        $ownRoot = & $common { Get-JobsInstallRoot }
        $roots += $ownRoot
        Assert-Architecture ($ownRoot.EndsWith($package.Id, [StringComparison]::Ordinal)) ('运行状态归属于本包：' + $package.Id)
        $installer = Import-Module (Join-Path $standalone 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
        $release = Join-Path $temporary ('release-' + $package.Id)
        & $installer { param($Path, $Destination) New-JobsPackageRelease -PackagePath $Path -Destination $Destination } $standalone $release | Out-Null
        if ($package.Id -ceq 'open-git-remote') {
            Assert-Architecture ([IO.File]::ReadAllText((Resolve-JobsScriptLayoutPath (Join-Path $release 'Scripts/Invoke.ps1'))) -ceq $invokeSource) '独立发布保留多远端专用入口原文'
        }
        $plan = @(& $installer { param($Manifest, $Release, $PowerShell) Get-JobsPackageRegistryPlan -Manifest $Manifest -ReleasePath $Release -PowerShellPath $PowerShell -Enabled $true } $package $release (Join-Path $PSHOME 'powershell.exe'))
        $expected = 4
        if ($package.DirectoryOnly) { $expected = 3 }
        if ($package.Id -in @('flutter-run', 'flutter-package', 'flutter-doctor', 'flutter-codegen', 'git-rollback', 'open-sourcetree')) { $expected = 4 }
        if ($package.Id -in @('android-simulator-create', 'android-simulator-repair', 'harmony-simulator-create', 'harmony-simulator-repair')) { $expected = 2 }
        if ($package.Id -in @('run-authorize', 'run-authorization-revoke', 'file-content-viewer', 'file-hash', 'file-volumes')) { $expected = 2 }
        if ($package.Id -eq 'command-shortcut-create') { $expected = 2 }
        if ($package.Id -eq 'file-visibility') { $expected = 3 }
        if ($package.Id -eq 'hidden-files-toggle') { $expected = 2 }
        if ($package.Id -eq 'disk-space-info') { $expected = 6 }
        if ($package.Id -in @('open-android-studio', 'open-vscode')) { $expected = 8 }
        if ($package.Id -eq 'git-proxy-configure') { $expected = 1 }
        if ($package.Id -eq 'flutter-tools') { $expected = 68 }
        Assert-Architecture ($plan.Count -eq $expected) ('本包只注册自己的上下文：' + $package.Id)
        foreach ($item in $plan) {
            if ($package.Id -eq 'disk-space-info') {
                $clsid = '{E10272DD-32AF-4BD0-97D2-B74D201FA6F1}'
                Assert-Architecture ($item.Key.EndsWith('Jobs.WindowsExtension.disk-space-info') -or $item.Key.EndsWith('CLSID\' + $clsid)) '磁盘空间只注册本包动态描述处理器与 CLSID'
                Assert-Architecture ($null -eq $item.PSObject.Properties['Command']) '磁盘只读描述不登记执行命令'
                continue
            }
            if ($package.Id -eq 'flutter-tools') {
                if ($item.Enabled) {
                    Assert-Architecture ($item.Key.EndsWith('Jobs.WindowsExtension.flutter-tools') -or $item.Key.EndsWith('CLSID\{55C8C7A9-8625-4AF0-8598-DFA975064F0C}')) '统一 Flutter 只启用自己的处理器'
                } else {
                    Assert-Architecture ($item.Owner -eq 'Jobs.WindowsExtension.v1' -and $item.Key -match 'Jobs\.WindowsExtension\.flutter-(pub-get|version-manager|sdk-inspector|dependency-extract|run|package|doctor|codegen)$') '迁移只停用固定旧 Flutter 入口'
                }
                continue
            }
            if ($package.Id -in @('android-simulator-create', 'android-simulator-repair', 'harmony-simulator-create', 'harmony-simulator-repair')) {
                $clsid = '{9591D98B-3481-4E05-BE24-470FCDFD0E23}'
                if ($package.Id -eq 'android-simulator-repair') { $clsid = '{A6D8DCE0-B691-4CC9-A3C5-F02B8BC704E5}' }
                if ($package.Id -eq 'harmony-simulator-create') { $clsid = '{95E5B535-2EB8-48CA-98B5-A14D17A0A859}' }
                if ($package.Id -eq 'harmony-simulator-repair') { $clsid = '{C91A8F93-CA7B-4F28-B705-A0AC90C5F231}' }
                Assert-Architecture ($item.Key -eq ('Software\Classes\DesktopBackground\shellex\ContextMenuHandlers\Jobs.WindowsExtension.' + $package.Id) -or $item.Key -eq ('Software\Classes\CLSID\' + $clsid)) ('模拟器只注册桌面背景及本包 CLSID：' + $package.Id)
                if ($item.Key.EndsWith('CLSID\' + $clsid)) {
                    Assert-Architecture ($item.InProcServer -eq (Join-Path $release ('bin/' + $package.Name + 'ContextMenu.dll'))) ('原生 DLL 归属于本包 release：' + $package.Id)
                }
                continue
            }
            if ($package.Id -in @('open-android-studio', 'open-vscode')) {
                if ($item.Enabled) {
                    Assert-Architecture ($item.Key.Contains('\shellex\ContextMenuHandlers\Jobs.WindowsExtension.' + $package.Id) -or $item.Key.Contains('\CLSID\')) 'IDE 原生门禁只注册自己的目录上下文与 CLSID'
                } else {
                    Assert-Architecture ($item.Key.EndsWith('\shell\Jobs.WindowsExtension.' + $package.Id)) 'IDE 迁移只停用自己的四个旧静态入口'
                }
                continue
            }
            if ($package.Id -eq 'hidden-files-toggle') {
                $clsid = '{F92F7AF9-65B6-41CB-A6D8-712F01F79126}'
                Assert-Architecture ($item.Key -eq ('Software\Classes\DesktopBackground\shellex\ContextMenuHandlers\Jobs.WindowsExtension.' + $package.Id) -or $item.Key -eq ('Software\Classes\CLSID\' + $clsid)) '隐藏文件切换只注册桌面背景和本包 CLSID'
                continue
            }
            if ($package.Id -eq 'open-sourcetree') {
                Assert-Architecture ($item.Key.EndsWith('Jobs.WindowsExtension.open-sourcetree') -or $item.Key.EndsWith('CLSID\{CF4D4697-749B-4C37-98EC-0952B2EF1E16}')) 'Sourcetree 只注册自己的动态处理器和 CLSID'
                continue
            }
            if ($package.Id -eq 'git-rollback') {
                Assert-Architecture ($item.Key.EndsWith('Jobs.WindowsExtension.git-rollback') -or $item.Key.EndsWith('CLSID\{E58D6868-A650-42EB-9629-E97338918229}')) 'Git 回退只注册自己的动态处理器和 CLSID'
                continue
            }
            if ($package.Id -in @('flutter-run', 'flutter-package', 'flutter-doctor', 'flutter-codegen')) {
                Assert-Architecture ($item.Key.EndsWith('Jobs.WindowsExtension.' + $package.Id) -or $item.Key.EndsWith('CLSID\{239D7884-83C5-4D66-AB0C-14A2667DCD61}') -or $item.Key.EndsWith('CLSID\{64A7C5BE-E031-4E89-A2D7-75C3F62B1AC9}') -or $item.Key.EndsWith('CLSID\{A41E939F-64E7-49DD-85FA-81F9B8CFD5E2}') -or $item.Key.EndsWith('CLSID\{DD71AE09-8A16-4B08-9868-5A40A9F39F63}')) '原生 COM 只注册本包处理器及 CLSID'
                continue
            }
            if ($package.Id -eq 'file-visibility') {
                $allowed = @('Software\Classes\*\shellex\ContextMenuHandlers\Jobs.WindowsExtension.file-visibility', 'Software\Classes\Directory\shellex\ContextMenuHandlers\Jobs.WindowsExtension.file-visibility', 'Software\Classes\CLSID\{F667A0A8-C7A6-4C79-A420-12DA30EBF981}')
                Assert-Architecture ($item.Key -cin $allowed) '所选项目隐藏属性仅登记本包文件/目录 handler 和 CLSID'
                continue
            }
            if ($package.Id -eq 'command-shortcut-create') {
                $clsid = '{A29030C5-2C96-48BF-BBF2-75D80CC8AF80}'
                Assert-Architecture ($item.Key -eq ('Software\Classes\Directory\shellex\ContextMenuHandlers\Jobs.WindowsExtension.' + $package.Id) -or $item.Key -eq ('Software\Classes\CLSID\' + $clsid)) '脚本快捷入口仅注册目录 handler 与本包 CLSID'
                continue
            }
            if ($package.Id -in @('run-authorize', 'run-authorization-revoke', 'file-content-viewer', 'file-hash', 'file-volumes')) {
                $clsid = '{AE09A13F-EF17-4CE3-8BA1-F557C34280DE}'
                if ($package.Id -eq 'run-authorization-revoke') { $clsid = '{6AC50F49-6915-4130-8474-F99DA4D074D6}' }
                if ($package.Id -eq 'file-content-viewer') { $clsid = '{DBC7884D-ECD9-43CB-A026-AFD8A9BBC2A7}' }
                if ($package.Id -eq 'file-hash') { $clsid = '{CD2D9483-9017-4717-96E3-B7153427F0C6}' }
                if ($package.Id -eq 'file-volumes') { $clsid = '{6F7BA84C-324C-472C-B618-B0E3D44244DB}' }
                Assert-Architecture ($item.Key -eq ('Software\Classes\*\shellex\ContextMenuHandlers\Jobs.WindowsExtension.' + $package.Id) -or $item.Key -eq ('Software\Classes\CLSID\' + $clsid)) '权限包只注册普通文件动态处理器和自己的 CLSID'
                continue
            }
            Assert-Architecture ($item.Key.EndsWith('Jobs.WindowsExtension.' + $package.Id)) '菜单计划不包含其它功能'
            Assert-Architecture ($item.Command -notmatch '\s-Action\s' -and $item.Command -match 'Invoke\.ps1') '菜单直接启动本功能'
            Assert-Architecture ($item.Command.Contains($release)) '注册命令使用本包独立运行版本'
        }
        $copied = Get-Content -LiteralPath (Join-Path $release 'Extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-Architecture ($copied.Id -eq $package.Id) '部署只包含所选包的清单'
        $actions=@(Get-ChildItem -LiteralPath $release -Recurse -File | Where-Object Name -ceq 'Action.psm1' | ForEach-Object {$_.FullName.Substring($release.Length+1).Replace('\','/')})
        $public=@($actions|Where-Object{$_-cmatch'^Scripts/(?:Actions/[^/]+/Scripts/)?Action\.psm1$'})
        $expectedPublic=if($package.Id-ceq'flutter-tools'){10}else{1}
        Assert-Architecture ($public.Count-eq$expectedPublic) '公共动作层只计根调度与直属动作，不把随包内部闭包当额外菜单'
        $internal=@($actions|Where-Object{$_-cnotin$public})
        $expectedInternal=@()
        if($package.Id-in@('flutter-tools','flutter-run')){
            $run=if($package.Id-ceq'flutter-tools'){'Scripts/Actions/run/Scripts'}else{'Scripts'}
            $expectedInternal=@(($run+'/SimulatorCreators/Android/Scripts/Action.psm1'),($run+'/SimulatorCreators/Harmony/Scripts/Action.psm1'),($run+'/RunPreflight.ps1/PrepareHarmonyRun.ps1/Core/Actions/sdk-manage/Scripts/Action.psm1'))
            foreach($dependency in @('AndroidRuntime.ps1','RunPreflight.ps1/StartVirtualDevice.ps1/StartVirtualDevice.ps1','RunPreflight.ps1/StartVirtualDevice.ps1/OfficialHarmonyTools.ps1/OfficialHarmonyTools.ps1','RunPreflight.ps1/PrepareHarmonyRun.ps1/Core/HarmonySdk.psm1')){
                Assert-Architecture ([IO.File]::Exists((Join-Path $release ($run+'/'+$dependency)))) ('运行内部闭包独立交付完整：'+$dependency)
            }
        }
        Assert-Architecture ((($internal|Sort-Object)-join'|')-ceq(($expectedInternal|Sort-Object)-join'|')) '仅允许已声明的内部SDK/创建器依赖，不随意夹带其它动作'

    }
    Assert-Architecture (@($roots | Select-Object -Unique).Count -eq $expectedCount) '登记的功能安装状态彼此独立'
    $single = @(Get-JobsPackageOperationPlan -Packages $packages -Selected @($packages[2].Id) -Installed @() -Mode Install)
    Assert-Architecture ($single.Count -eq 1 -and $single[0].Id -eq $packages[2].Id) '首次只选一项只部署一项'
    $configure = @(Get-JobsPackageOperationPlan -Packages $packages -Selected @($packages[2].Id) -Installed @($packages[0].Id, $packages[2].Id) -Mode Configure)
    Assert-Architecture ($configure.Count -eq 2 -and $configure[0].Mode -eq 'Uninstall' -and $configure[1].Mode -eq 'Install') '配置面板分开编排卸载和安装'
    $uninstall = @(Get-JobsPackageOperationPlan -Packages $packages -Selected @($packages[0].Id) -Installed @($packages[0].Id, $packages[2].Id) -Mode Uninstall)
    Assert-Architecture ($uninstall.Count -eq 1 -and $uninstall[0].Id -eq $packages[0].Id) '仅卸载选择的功能，保留其它已安装功能'
    $script:executed = @()
    $result = Invoke-JobsPackageOperations -Plan $single -Executor { param($Operation) $script:executed += $Operation.Id }
    Assert-Architecture ($result.Success -and $script:executed.Count -eq 1) '总入口只调用选中的独立安装器'
    $failure = Invoke-JobsPackageOperations -Plan @($single[0], $configure[0], $single[0]) -Executor {
        param($Operation)
        if ($Operation.Mode -eq 'Uninstall') { throw 'isolated package failure' }
    }
    Assert-Architecture (-not $failure.Success -and @($failure.Completed).Count -eq 2 -and $failure.Failed -eq $configure[0].Id) '单包失败后继续其它所选包并保留成功结果'
    foreach ($name in @('Worker.ps1', 'Invoke-Menu.ps1', 'Common.psm1')) {
        Assert-Architecture (-not (Test-Path -LiteralPath (Join-Path $root ('Scripts/' + $name)))) ('总入口不再承载集中业务：' + $name)
    }
    # 在独立夹具中执行同步写入，验证例外入口不被模板覆盖及白名单拒绝边界。
    $syncRoot = Join-Path $temporary 'infrastructure-override'
    $syncScripts = Join-Path $syncRoot 'Scripts'
    [void][IO.Directory]::CreateDirectory($syncScripts)
    Copy-Item -LiteralPath (Join-Path $root 'Infrastructure') -Destination $syncRoot -Recurse
    foreach ($name in @('Installer.psm1', 'Sync-PackageInfrastructure.ps1')) {
        Copy-Item -LiteralPath (Join-Path $root ('Scripts/' + $name)) -Destination $syncScripts
    }
    $syncPackage = Join-Path $syncRoot 'JobsGitRemoteOpener'
    [void][IO.Directory]::CreateDirectory((Join-Path $syncPackage 'Scripts'))
    $syncInvoke = Resolve-JobsScriptLayoutPath (Join-Path $syncPackage 'Scripts/Invoke.ps1')
    Copy-Item -LiteralPath (Resolve-JobsScriptLayoutPath (Join-Path $root 'JobsGitRemoteOpener/Scripts/Invoke.ps1')) -Destination $syncInvoke
    $invokeHash = (Get-FileHash -LiteralPath $syncInvoke).Hash
    $syncManifest = Get-Content -LiteralPath (Join-Path $root 'JobsGitRemoteOpener/Extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $manifestJson = $syncManifest | ConvertTo-Json -Depth 10
    $catalogJson = '[{"Id":"open-git-remote","Name":"JobsGitRemoteOpener"}]'
    [IO.File]::WriteAllText((Join-Path $syncPackage 'Extension.json'), $manifestJson)
    [IO.File]::WriteAllText((Join-Path $syncRoot 'Extensions.json'), $catalogJson)
    & (Resolve-JobsScriptLayoutPath (Join-Path $syncScripts 'Sync-PackageInfrastructure.ps1')) -Write 6>$null
    Assert-Architecture ((Get-FileHash -LiteralPath $syncInvoke).Hash -ceq $invokeHash) '同步写入保留白名单多远端入口的完整字节'
    Assert-Architecture ((Get-FileHash -LiteralPath (Join-Path $syncPackage 'Scripts/Common.psm1')).Hash -ceq (Get-FileHash -LiteralPath (Join-Path $root 'Infrastructure/Common.psm1')).Hash) '专用入口覆盖不豁免其它通用模板同步'
    foreach ($invalid in @(@{Overrides=@('Invoke.ps1','Invoke.ps1')}, @{Overrides=@('Invoke.ps1','Common.psm1')}, @{Overrides=@('invoke.ps1')}, @{Overrides=@('PackageInstaller.psm1')}, @{Id='other-remote'}, @{Name='JobsOtherRemote'}, @{CatalogId='other-remote'}, @{CatalogName='JobsOtherRemote'})) {
        $candidate = $manifestJson | ConvertFrom-Json
        $entry = [pscustomobject]@{Id='open-git-remote';Name='JobsGitRemoteOpener'}
        if ($invalid.ContainsKey('Overrides')) { $candidate.InfrastructureOverrides = $invalid.Overrides }
        if ($invalid.ContainsKey('Id')) { $candidate.Id = $invalid.Id }
        if ($invalid.ContainsKey('Name')) { $candidate.Name = $invalid.Name }
        if ($invalid.ContainsKey('CatalogId')) { $entry.Id = $invalid.CatalogId }
        if ($invalid.ContainsKey('CatalogName')) { $entry.Name = $invalid.CatalogName }
        $candidateRoot = Join-Path $syncRoot $entry.Name
        [void][IO.Directory]::CreateDirectory($candidateRoot)
        [IO.File]::WriteAllText((Join-Path $candidateRoot 'Extension.json'), ($candidate | ConvertTo-Json -Depth 10))
        [IO.File]::WriteAllText((Join-Path $syncRoot 'Extensions.json'), (ConvertTo-Json -InputObject @($entry)))
        $blocked = $false
        try { & (Resolve-JobsScriptLayoutPath (Join-Path $syncScripts 'Sync-PackageInfrastructure.ps1')) 6>$null }
        catch { $blocked = $_.Exception.Message -match '基础设施覆盖白名单|只允许本包多远端选择' }
        Assert-Architecture $blocked '同步白名单拒绝重复、额外、错名、大小写及不匹配的目录/包身份'
        Assert-Architecture ((Get-FileHash -LiteralPath $syncInvoke).Hash -ceq $invokeHash) '拒绝非法覆盖清单后保留远端专用入口'
    }
    Write-Host ('PASS: Architecture.Tests.ps1 (' + $script:assertions + ' assertions)')
} finally {
    $env:LOCALAPPDATA = $savedLocal
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

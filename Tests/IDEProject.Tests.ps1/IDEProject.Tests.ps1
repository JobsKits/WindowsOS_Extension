# IDEProject.Tests.ps1 | Jobs IDE menu and dispatch boundaries
# Created by Jobs on 2026年10月26日，星期一.
# Real temporary directories and stubbed launchers; no IDE or user project is opened.
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
$script:JobsLayoutIDEProjectTestsRoot = $(if ([IO.Path]::GetFileName($PSScriptRoot) -ceq 'IDEProject.Tests.ps1') { Split-Path -Parent $PSScriptRoot } else { $PSScriptRoot })

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
$root = Split-Path -Parent ${script:JobsLayoutIDEProjectTestsRoot}
$temporaryRoot = [IO.Path]::GetTempPath()
if ([IO.Directory]::Exists('/private/tmp')) { $temporaryRoot = '/private/tmp' }
$temporary = Join-Path $temporaryRoot ('JobsIDEProjects-' + [guid]::NewGuid().ToString('N'))
$script:count = 0
function Assert { param([bool]$Value, [string]$Why); if (-not $Value) { throw ('FAIL: ' + $Why) }; $script:count++ }
function Write-File { param([string]$Path, [string]$Text); [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path)); [IO.File]::WriteAllText($Path, $Text) }
function New-Case { param([string]$Name, [hashtable]$Files); $path = Join-Path $temporary $Name; [void][IO.Directory]::CreateDirectory($path); foreach ($relative in $Files.Keys) { Write-File (Join-Path $path $relative) $Files[$relative] }; return $path }
$android = Import-Module (Join-Path $root 'JobsAndroidStudioOpener/Scripts/Action.psm1') -PassThru -DisableNameChecking
$vscode = Import-Module (Join-Path $root 'JobsVSCodeOpener/Scripts/Action.psm1') -PassThru -DisableNameChecking
function Check {
    param([string]$Path, [bool]$AndroidExpected, [bool]$VSCodeExpected, [string]$Why)
    $actualAndroid = & $android { param($Path) Test-JobsIDEProject -Directory $Path -IDE android-studio } $Path
    $actualVSCode = & $vscode { param($Path) Test-JobsIDEProject -Directory $Path -IDE vscode } $Path
    Assert ($actualAndroid -eq $AndroidExpected) ('AndroidStudio: ' + $Why)
    Assert ($actualVSCode -eq $VSCodeExpected) ('VSCode: ' + $Why)
}
try {
    [void][IO.Directory]::CreateDirectory($temporary)
    $empty = New-Case empty @{}; Check $empty $false $false 'empty folder'
    $noise = New-Case noise @{ '.DS_Store' = 'metadata'; 'Thumbs.db' = 'metadata'; 'desktop.ini' = 'metadata' }; Check $noise $false $false 'metadata-only folder'
    $plain = New-Case plain @{ 'README.md' = 'notes' }; Check $plain $false $true 'ordinary nonempty folder'
    $hidden = New-Case hidden @{}; [void][IO.Directory]::CreateDirectory((Join-Path $hidden '.git')); Check $hidden $false $true 'meaningful hidden entry counts as nonempty'
    $flutter = New-Case flutter @{ 'pubspec.yaml' = "name: sample`ndependencies:`n  flutter:`n    sdk: flutter`n" }; Check $flutter $true $true 'official Flutter root'
    Write-File (Join-Path $flutter 'ios/Runner.xcodeproj/project.pbxproj') 'SDKROOT = iphoneos;'; Check $flutter $true $true 'Flutter root containing iOS subproject'
    $harmony = New-Case harmony @{ 'pubspec.yaml' = 'dependencies: {flutter: {sdk: flutter}}'; 'ohos/build-profile.json5' = '{}' }; Check $harmony $true $true 'OpenHarmony Flutter root'
    $index = 0
    foreach ($source in @("description: 'dependencies flutter sdk flutter'`n", "dev_dependencies:`n  flutter_test:`n    sdk: flutter`n", "dependencies:`n  flutter:`n    sdk: dart`n", "dependencies: {flutter: {sdk: flutter}}`ndependencies: {}`n")) {
        $index++; Check (New-Case ('invalid-' + $index) @{ 'pubspec.yaml' = $source }) $false $true 'invalid or misleading Flutter manifest'
    }
    $native = New-Case android @{ 'settings.gradle' = "rootProject.name='fixture'"; 'build.gradle' = "plugins { id 'com.android.application' }" }; Check $native $true $true 'native Android root'
    $kotlin = New-Case kotlin @{ 'settings.gradle.kts' = 'include(":app")'; 'app/build.gradle.kts' = 'plugins { id("com.android.library") }' }; Check $kotlin $true $true 'Android module plugin under current settings root'
    $manifest = New-Case manifest @{ 'settings.gradle' = "include ':app'"; 'app/build.gradle' = 'android {}'; 'app/src/main/AndroidManifest.xml' = '<manifest />' }; Check $manifest $true $true 'Android application manifest evidence'
    Check (New-Case java @{ 'settings.gradle' = "rootProject.name='java'"; 'build.gradle' = "plugins { id 'java' }" }) $false $true 'ordinary Gradle is not Android'
    Check (New-Case comment @{ 'settings.gradle' = "rootProject.name='java'"; 'build.gradle' = "// id 'com.android.application'`n/* apply plugin: 'com.android.library' */`ndescription = 'com.android.application';" }) $false $true 'Gradle comments and plain description are not Android plugin declarations'
    Check (New-Case alias @{ 'settings.gradle' = "include ':app'"; 'app/build.gradle.kts' = 'plugins { alias(libs.plugins.android.application) }' }) $true $true 'Android version-catalog plugin alias'
    Check (New-Case noSettings @{ 'build.gradle' = "plugins { id 'com.android.application' }" }) $false $true 'only current root accepted, no settings root'
    $ios = New-Case ios @{ 'Demo.xcodeproj/project.pbxproj' = 'SDKROOT = iphoneos;' }; Check $ios $false $false 'iOS project excluded from VSCode'
    Check (New-Case simulator @{ 'Demo.xcodeproj/project.pbxproj' = 'SUPPORTED_PLATFORMS = "iphonesimulator";' }) $false $false 'iPhone simulator-only project'
    Check (New-Case mac @{ 'Demo.xcodeproj/project.pbxproj' = 'SDKROOT = macosx;' }) $false $true 'macOS Xcode project is not iOS'
    Check (New-Case swiftPackage @{ 'Package.swift' = '.iOS(.v17)' }) $false $true 'pure Swift package is not inferred as iOS Xcode project'
    Check (New-Case nested @{ 'ios/Demo.xcodeproj/project.pbxproj' = 'SDKROOT = iphoneos;' }) $false $true 'generic parent does not inherit a child project type'
    Check (New-Case workspace @{ 'Demo.xcworkspace/contents.xcworkspacedata' = '<Workspace><FileRef location="group:Child/Demo.xcodeproj" /></Workspace>'; 'Child/Demo.xcodeproj/project.pbxproj' = 'SDKROOT = iphoneos;' }) $false $false 'workspace explicit project reference'
    Check (New-Case unicode @{ 'Demo.xcworkspace/contents.xcworkspacedata' = '<FileRef location="group:中文 &amp; file/Demo.xcodeproj" />'; '中文 & file/Demo.xcodeproj/project.pbxproj' = 'SDKROOT = iphoneos;' }) $false $false 'workspace Unicode and XML entities'
    [void](New-Case siblingApp @{ 'Demo.xcodeproj/project.pbxproj' = 'SDKROOT = iphoneos;' })
    Check (New-Case siblingWorkspace @{ 'Demo.xcworkspace/contents.xcworkspacedata' = '<FileRef location="group:../siblingApp/Demo.xcodeproj" />' }) $false $false 'workspace explicit parent-relative project association'
    Check (New-Case largeIOS @{ 'Demo.xcodeproj/project.pbxproj' = (('x' * 1048577) + 'SDKROOT = iphoneos;') }) $false $false 'oversized iOS metadata is unknown rather than non-iOS'
    Check (New-Case largeWorkspace @{ 'Demo.xcworkspace/contents.xcworkspacedata' = ('x' * 1048577) }) $false $false 'oversized workspace metadata does not admit VSCode'
    Check (Join-Path $plain 'README.md') $false $false 'selected file is never mapped to its parent'
    $bundle = New-Case bundle @{ 'Tool.app/Contents/Info.plist' = 'metadata' }; Check (Join-Path $bundle 'Tool.app') $false $false 'application bundle excluded'
    foreach ($entry in @(@($android, $native, 'Get-JobsAndroidStudio', 'studio.exe'), @($vscode, $plain, 'Get-JobsVSCode', 'code.exe'))) {
        $module = $entry[0]; $path = $entry[1]
        & $module {
            $script:starts = 0
            function script:Get-JobsAndroidStudio { return 'studio.exe' }
            function script:Get-JobsVSCode { return 'code.exe' }
            function script:Start-JobsApplication { param($Executable, $Arguments, $Directory); $script:starts++; $script:opened = $Directory }
        }
        & $module { param($Path) Invoke-JobsFeature -Target $Path } $path
        Assert ((& $module { $script:starts }) -eq 1) 'eligible directory reaches only the stubbed IDE launcher'
        $rejected = $false
        try { & $module { param($Path) Invoke-JobsFeature -Target $Path } $empty } catch { $rejected = $true }
        Assert ($rejected -and (& $module { $script:starts }) -eq 1) 'empty directory rejected before IDE lookup/open'
    }
    foreach ($name in @('JobsAndroidStudioOpener', 'JobsVSCodeOpener')) {
        $package = Join-Path $root $name
        $installer = Import-Module (Join-Path $package 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
        $manifest = Get-Content -LiteralPath (Join-Path $package 'Extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $plan = @(& $installer { param($Manifest) Get-JobsPackageRegistryPlan $Manifest '/temporary/release' 'powershell.exe' } $manifest)
        Assert ($plan.Count -eq 8 -and @($plan | Where-Object Enabled).Count -eq 4) 'native directory/background/drive handler plus CLSID, four old static entries retired'
        Assert (@($plan | Where-Object { -not $_.Enabled -and $_.Key.Contains('\shell\Jobs.WindowsExtension.' + $manifest.Id) }).Count -eq 4) 'migration removes only this package legacy static scopes'
        Assert (@($plan | Where-Object { $_.Enabled -and $_.PSObject.Properties['InProcServer'] -and $_.InProcServer.EndsWith((Join-Path 'bin' ($name + 'ContextMenu.dll'))) }).Count -eq 1) 'own native binary name'
        $build = [IO.File]::ReadAllText((Resolve-JobsScriptLayoutPath (Join-Path $package 'Scripts/Build.ps1')))
        foreach ($source in [regex]::Matches($build, 'Join-Path \$scripts ''([^'']+\.(?:cs|cpp|def))''')) {
            Assert ([IO.File]::Exists((Join-Path $package ('Scripts/' + $source.Groups[1].Value)))) 'every declared native build source is shipped in its own package'
        }
    }
    foreach ($file in @('IDEProject.h', 'IDEProject.cs', 'ProjectEligibility.ps1', 'FlutterProject.h')) {
        Assert ((Get-FileHash -LiteralPath (Join-Path $root ('JobsAndroidStudioOpener/Scripts/' + $file))).Hash -ceq (Get-FileHash -LiteralPath (Join-Path $root ('JobsVSCodeOpener/Scripts/' + $file))).Hash) 'independent packages carry the same project policy'
    }
    Write-Host ('PASS: IDEProject (' + $script:count + ' assertions; no IDE launched)')
} finally {
    Remove-Module $android, $vscode -ErrorAction SilentlyContinue
    if ([IO.Directory]::Exists($temporary)) { [IO.Directory]::Delete($temporary, $true) }
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

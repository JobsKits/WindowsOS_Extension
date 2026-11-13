# HarmonyFlutterSdk.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年10月23日，星期五.
# 使用临时项目与假 FVM；不联网、不安装工具、不注册菜单。
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
$script:count = 0
function Assert-HarmonySdk($Value, [string]$Message) { $script:count++; if (-not $Value) { throw ('FAIL: ' + $Message) } }
function Assert-HarmonyThrows([scriptblock]$Action, [string]$Message) {
    $blocked = $false
    try { & $Action | Out-Null } catch { $blocked = $true }
    Assert-HarmonySdk $blocked $Message
}
$root = Split-Path -Parent $PSScriptRoot
$temporaryRoot = [IO.Path]::GetTempPath()
if ([IO.Directory]::Exists('/private/tmp')) { $temporaryRoot = '/private/tmp' }
$temporary = Join-Path $temporaryRoot ('JobsHarmonySdk [中文] & 100% ' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$saved = @{}
foreach ($key in @('LOCALAPPDATA','FVM_CACHE_PATH','FVM_FLUTTER_URL','FVM_USE_GIT_CACHE','PATH')) { $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
try {
    $env:LOCALAPPDATA = Join-Path $temporary 'local'
    $path = Join-Path $root 'JobsFlutterTools/Scripts/HarmonySdk.psm1'
    $module = Import-Module $path -PassThru -Force -DisableNameChecking
    $sha = '0123456789abcdef0123456789abcdef01234567'
    $tagSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    $ref = '3.35.7+ohos-1.0.5'
    $remote = $tagSha + "`trefs/tags/" + $ref + "`n" + $sha + "`trefs/tags/" + $ref + '^{}'
    $choices = @(& $module { param($Text) ConvertFrom-JobsHarmonyTags $Text } $remote)
    Assert-HarmonySdk ($choices.Count -eq 1 -and $choices[0].Commit -ceq $sha) 'annotated tag resolves peeled commit'
    Assert-HarmonySdk ($choices[0].Version -ceq ('custom_jobs_ohos_' + $sha)) 'custom cache key uses immutable commit'
    Assert-HarmonySdk ((& $module { param($Text,$Ref) Resolve-JobsHarmonyCommit $Text $Ref } $remote $ref) -ceq $sha) 'selection commit resolves exact tag'
    Assert-HarmonyThrows { & $module { param($Text,$Ref) Resolve-JobsHarmonyCommit $Text $Ref } ($remote + "`n" + $sha + "`trefs/heads/" + $ref) $ref } 'same-name tag and branch rejected'
    Assert-HarmonyThrows { & $module { ConvertFrom-JobsHarmonyTags "not-a-sha`trefs/tags/3.35.7+ohos-1.0.5" } } 'invalid remote record rejected'
    Assert-HarmonySdk (@(& $module { ConvertFrom-JobsHarmonyTags "0123456789abcdef0123456789abcdef01234567`trefs/tags/3.35.7" }).Count -eq 0) 'upstream native tags excluded'
    $variant = @(& $module { ConvertFrom-JobsHarmonyTags "0123456789abcdef0123456789abcdef01234567`trefs/tags/v3.47.7+ohos-0.0.1-pre" })
    Assert-HarmonySdk ($variant.Count -eq 1 -and $variant[0].Prerelease -eq $true -and $variant[0].BaseVersion -eq [version]'3.47.7') 'v-prefix and prerelease tag parsed explicitly'
    $sorting = @(& $module {
        Get-JobsHarmonyTagChoices "0123456789abcdef0123456789abcdef01234567`trefs/tags/3.41.9+ohos-1.0.9`n0123456789abcdef0123456789abcdef01234567`trefs/tags/3.41.9+ohos-1.0.10`n0123456789abcdef0123456789abcdef01234567`trefs/tags/v3.47.7+ohos-0.0.1-pre"
    })
    Assert-HarmonySdk ($sorting[0].Ref -ceq '3.41.9+ohos-1.0.10' -and $sorting[1].Ref -ceq '3.41.9+ohos-1.0.9' -and $sorting[2].Prerelease -eq $true) 'stable tags first and OH numeric suffix sorts 1.0.10 before 1.0.9'
    $project = Join-Path $temporary 'parent/app'
    [void][IO.Directory]::CreateDirectory((Join-Path $project 'lib'))
    [IO.File]::WriteAllText((Join-Path $project 'pubspec.yaml'), "name: app`ndependencies:`n  flutter:`n    sdk: flutter`n")
    [IO.File]::WriteAllText((Join-Path (Split-Path -Parent $project) '.fvmrc'), '{"flutter":"3.16.0","parent":true}')
    [IO.File]::WriteAllText((Join-Path $project '.fvmrc'), '{"flutter":"3.38.5","custom":{"keep":true},"flavors":{"dev":"3.38.4"}}')
    [void][IO.Directory]::CreateDirectory((Join-Path $project '.vscode'))
    [IO.File]::WriteAllText((Join-Path $project '.vscode/settings.json'), '{"dart.flutterSdkPath":"keep/ide","keep":true}')
    [IO.File]::WriteAllText((Join-Path $project '.gitignore'), "keep/`n")
    $oldSdk = Join-Path $temporary 'native-sdk'
    [void][IO.Directory]::CreateDirectory($oldSdk)
    [void][IO.Directory]::CreateDirectory((Join-Path $project '.fvm'))
    $linkType = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'Junction' } else { 'SymbolicLink' }
    $linkTarget = $oldSdk
    if ($PSVersionTable.PSVersion.Major -eq 5) { $linkTarget = [Management.Automation.WildcardPattern]::Escape($oldSdk) }
    [void](New-Item -ItemType $linkType -Path (Join-Path $project '.fvm/flutter_sdk') -Target $linkTarget)
    $before = [IO.File]::ReadAllText((Join-Path $project '.fvmrc'))
    $beforeIde = [IO.File]::ReadAllText((Join-Path $project '.vscode/settings.json'))
    $beforeIgnore = [IO.File]::ReadAllText((Join-Path $project '.gitignore'))
    & $module { function script:Invoke-JobsHarmonyGit { throw 'network must not run during check' } }
    & $module { param($Project) Invoke-JobsHarmonySdkAction -Target $Project -Check } $project
    Assert-HarmonySdk ([IO.File]::ReadAllText((Join-Path $project '.fvmrc')) -ceq $before) 'check leaves project config unchanged'
    Assert-HarmonySdk (-not [IO.Directory]::Exists((Join-Path $env:LOCALAPPDATA 'JobsFlutter'))) 'check creates no cache'
    $cache = & $module { Get-JobsHarmonyCache }
    $sdk = Join-Path $cache ('versions/custom_jobs_ohos_' + $sha)
    [void][IO.Directory]::CreateDirectory((Join-Path $sdk '.git'))
    [void][IO.Directory]::CreateDirectory((Join-Path $sdk 'bin'))
    [IO.File]::WriteAllText((Join-Path $sdk 'bin/flutter.bat'), 'fake sdk only')
    $stamp = & $module { param($Project) Get-JobsHarmonyBindingStamp $Project } $project
    $shadow = Join-Path $temporary 'shadow'
    [void][IO.Directory]::CreateDirectory($shadow)
    Copy-Item -LiteralPath (Join-Path $project '.fvmrc') -Destination (Join-Path $shadow '.fvmrc')
    $config = & $module { param($Project,$Version,$Cache) Set-JobsHarmonyConfig $Project $Version $Cache } $shadow ('custom_jobs_ohos_' + $sha) $cache
    Assert-HarmonySdk ($config.custom.keep -eq $true -and $config.flavors.dev -ceq '3.38.4') 'existing fields and flavors preserved'
    Assert-HarmonySdk ($config.updateMelosSettings -eq $false -and $config.useGitCache -eq $false) 'parent Melos updates and shared git cache disabled'
    $body = ($config | ConvertTo-Json -Depth 100) + [Environment]::NewLine
    & $module { function script:Complete-JobsHarmonyConfigPublication { throw 'injected publication failure after link move' } }
    Assert-HarmonyThrows { & $module { param($Project,$Sdk,$Config,$Stamp) Publish-JobsHarmonyBinding $Project $Sdk $Config $Stamp } $project $sdk $body $stamp } 'publishing failure reported'
    Assert-HarmonySdk ([IO.File]::ReadAllText((Join-Path $project '.fvmrc')) -ceq $before) 'failed native-to-OH switch restores original config bytes'
    Assert-HarmonySdk ([string]@(Get-Item -LiteralPath (Join-Path $project '.fvm/flutter_sdk')).Target -ceq $oldSdk) 'failed native-to-OH switch restores original SDK link'
    Assert-HarmonySdk ([IO.File]::ReadAllText((Join-Path $project '.vscode/settings.json')) -ceq $beforeIde -and [IO.File]::ReadAllText((Join-Path $project '.gitignore')) -ceq $beforeIgnore) 'failure preserves IDE and ignore'
    $module = Import-Module $path -PassThru -Force -DisableNameChecking
    & $module { param($Project,$Sdk,$Config,$Stamp) Publish-JobsHarmonyBinding $Project $Sdk $Config $Stamp } $project $sdk $body $stamp
    Assert-HarmonySdk ((Get-Content -LiteralPath (Join-Path $project '.fvmrc') -Raw -Encoding UTF8 | ConvertFrom-Json).flutter -ceq ('custom_jobs_ohos_' + $sha)) 'successful project config published'
    Assert-HarmonySdk ([string]@(Get-Item -LiteralPath (Join-Path $project '.fvm/flutter_sdk')).Target -ceq $sdk) 'published SDK link is absolute selected cache'
    Assert-HarmonySdk ([IO.File]::ReadAllText((Join-Path $project '.vscode/settings.json')) -ceq $beforeIde -and [IO.File]::ReadAllText((Join-Path $project '.gitignore')) -ceq $beforeIgnore) 'success preserves IDE and ignore'
    Assert-HarmonySdk ([IO.File]::ReadAllText((Join-Path (Split-Path -Parent $project) '.fvmrc')) -ceq '{"flutter":"3.16.0","parent":true}') 'parent project untouched'
    Assert-HarmonyThrows { & $module { param($Project,$Sdk,$Config,$Stamp) Publish-JobsHarmonyBinding $Project $Sdk $Config $Stamp } $project $sdk $body $stamp } 'stale project fingerprint prevents publication'
    $guard = Join-Path $temporary 'unsafe'
    [void][IO.Directory]::CreateDirectory((Join-Path $guard '.fvm/flutter_sdk'))
    Copy-Item -LiteralPath (Join-Path $project 'pubspec.yaml') -Destination (Join-Path $guard 'pubspec.yaml')
    Assert-HarmonyThrows { & $module { param($Project) Assert-JobsHarmonyBindingPaths $Project } $guard } 'real SDK source directory never overwritten'
    & $module {
        $script:TestCommit = '0123456789abcdef0123456789abcdef01234567'
        function script:Read-Host { param($Prompt) return '' }
        function script:Invoke-JobsHarmonyGit {
            param($Git,$Arguments,$Directory,$TimeoutSeconds)
            if ($Arguments[0] -ceq 'ls-remote') { return $script:TestCommit + "`trefs/tags/3.35.7+ohos-1.0.5" }
            if ($Arguments[2] -ceq 'rev-parse') { return $script:TestCommit }
            if ($Arguments[2] -ceq 'remote') { return 'https://gitcode.com/CPF-Flutter/flutter_flutter.git' }
            if ($Arguments[2] -ceq 'status') { return '' }
            throw 'unexpected Git operation in fixture'
        }
        & $script:HarmonyManager {
            $script:TestCommit = '0123456789abcdef0123456789abcdef01234567'
            $script:FailHap = $true
            function script:Get-JobsFvmToolchain { param($Directory,$InspectionDirectory) return [pscustomobject]@{Git='fake-git';Fvm='fake-fvm';Fzf='fake-fzf'} }
            function script:Select-JobsFlutterVersion { param($Fzf,$Choices,$Directory) return @($Choices)[0] }
            function script:Invoke-JobsFvmTool {
                param($File,$Arguments,$Directory,[switch]$Visible,$TimeoutSeconds)
                if ($Arguments[0] -ceq 'use') {
                    [void][IO.Directory]::CreateDirectory((Join-Path $Directory '.fvm'))
                    $target = Join-Path $env:FVM_CACHE_PATH ('versions/' + $Arguments[1])
                    $kind = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'Junction' } else { 'SymbolicLink' }
                    $linkTarget = $target
                    if ($PSVersionTable.PSVersion.Major -eq 5) { $linkTarget = [Management.Automation.WildcardPattern]::Escape($target) }
                    [void](New-Item -ItemType $kind -Path (Join-Path $Directory '.fvm/flutter_sdk') -Target $linkTarget)
                    return [pscustomobject]@{ExitCode=0;StdOut='';StdErr=''}
                }
                if ($Arguments[1] -ceq '--version') { return [pscustomobject]@{ExitCode=0;StdOut=('{"frameworkRevision":"' + $script:TestCommit + '"}');StdErr=''} }
                if ($script:FailHap) { return [pscustomobject]@{ExitCode=1;StdOut='';StdErr='unsupported hap'} }
                return [pscustomobject]@{ExitCode=0;StdOut='Build hap';StdErr=''}
            }
        }
    }
    $existingCache = Join-Path $temporary 'keep-existing-cache'
    $env:FVM_CACHE_PATH = $existingCache; $env:FVM_FLUTTER_URL = 'keep-existing-url'; $env:FVM_USE_GIT_CACHE = 'true'
    $pathBefore = $env:PATH
    $currentBeforeFailure = [IO.File]::ReadAllText((Join-Path $project '.fvmrc'))
    Assert-HarmonyThrows { & $module { param($Project) Invoke-JobsHarmonySdkAction -Target $Project } $project } 'SDK without hap capability fails before real project publication'
    Assert-HarmonySdk ([IO.File]::ReadAllText((Join-Path $project '.fvmrc')) -ceq $currentBeforeFailure) 'failed shadow capability check leaves live binding bytes'
    Assert-HarmonySdk ($env:FVM_CACHE_PATH -ceq $existingCache -and $env:FVM_FLUTTER_URL -ceq 'keep-existing-url' -and $env:FVM_USE_GIT_CACHE -ceq 'true' -and $env:PATH -ceq $pathBefore) 'failure restores all process environment'
    & $module { & $script:HarmonyManager { $script:FailHap = $false } }
    & $module { param($Project) Invoke-JobsHarmonySdkAction -Target $Project } $project
    Assert-HarmonySdk ($env:FVM_CACHE_PATH -ceq $existingCache -and $env:FVM_FLUTTER_URL -ceq 'keep-existing-url' -and $env:FVM_USE_GIT_CACHE -ceq 'true' -and $env:PATH -ceq $pathBefore) 'success restores all process environment'
    Assert-HarmonySdk ([IO.File]::ReadAllText((Join-Path $project '.vscode/settings.json')) -ceq $beforeIde -and [IO.File]::ReadAllText((Join-Path $project '.gitignore')) -ceq $beforeIgnore) 'shadow workflow never rewrites live IDE or ignore'
    Assert-HarmonySdk (@(Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'Jobs/WindowsExtension/extensions/flutter-tools') -Directory -Filter 'inspection-*').Count -eq 0) 'private shadow cleaned after success and failure'
    Assert-HarmonySdk (& $module { param($Project) Test-JobsManagedHarmonyBinding $Project } $project) 'known CPF convention recognized for native return path'
    & $module {
        function script:Invoke-JobsHarmonyGit {
            param($Git,$Arguments,$Directory,$TimeoutSeconds)
            if ($Arguments[2] -ceq 'remote') { return 'https://github.com/flutter/flutter.git' }
            throw 'unexpected native fixture Git operation'
        }
        & $script:HarmonyManager {
            $script:NativeFails = $true
            function script:Get-JobsFvmToolchain {
                param($Directory,$InspectionDirectory)
                return [pscustomobject]@{Git='fake-git';Fvm='fake-fvm';Fzf='fake-fzf';Context=[pscustomobject]@{flutterUrl=$env:FVM_FLUTTER_URL;versionsCachePath=(Join-Path $env:FVM_CACHE_PATH 'versions')}}
            }
            function script:Get-JobsFvmCachedVersions { return @() }
            function script:Get-JobsFlutterReleaseChoices { return [pscustomobject]@{Version='3.38.5';Ready=$false;Offline=$false;Label='3.38.5 | official stable'} }
            function script:Invoke-JobsFvmTool {
                param($File,$Arguments,$Directory,[switch]$Visible,$TimeoutSeconds)
                if ($Arguments[0] -ceq 'install') {
                    $sdk = Join-Path $env:FVM_CACHE_PATH ('versions/' + $Arguments[1])
                    [void][IO.Directory]::CreateDirectory((Join-Path $sdk 'bin'))
                    [void][IO.Directory]::CreateDirectory((Join-Path $sdk '.git'))
                    [IO.File]::WriteAllText((Join-Path $sdk 'bin/flutter.bat'), 'fixture sdk only')
                    return [pscustomobject]@{ExitCode=0;StdOut='';StdErr=''}
                }
                if ($Arguments[0] -ceq 'use') {
                    [void][IO.Directory]::CreateDirectory((Join-Path $Directory '.fvm'))
                    $target = Join-Path $env:FVM_CACHE_PATH ('versions/' + $Arguments[1])
                    $kind = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'Junction' } else { 'SymbolicLink' }
                    $linkTarget = $target
                    if ($PSVersionTable.PSVersion.Major -eq 5) { $linkTarget = [Management.Automation.WildcardPattern]::Escape($target) }
                    [void](New-Item -ItemType $kind -Path (Join-Path $Directory '.fvm/flutter_sdk') -Target $linkTarget)
                    return [pscustomobject]@{ExitCode=0;StdOut='';StdErr=''}
                }
                if ($script:NativeFails) { return [pscustomobject]@{ExitCode=1;StdOut='';StdErr='fake initialization failure'} }
                return [pscustomobject]@{ExitCode=0;StdOut='{"frameworkVersion":"3.38.5"}';StdErr=''}
            }
        }
    }
    $beforeNativeFailure = [IO.File]::ReadAllText((Join-Path $project '.fvmrc'))
    Assert-HarmonyThrows { & $module { param($Project) Invoke-JobsNativeSdkFromHarmony -Target $Project } $project } 'native return initialization failure reported'
    Assert-HarmonySdk ([IO.File]::ReadAllText((Join-Path $project '.fvmrc')) -ceq $beforeNativeFailure -and [string]@(Get-Item -LiteralPath (Join-Path $project '.fvm/flutter_sdk')).Target -ceq $sdk) 'failed OH-to-native initialization preserves complete OH binding'
    & $module { & $script:HarmonyManager { $script:NativeFails = $false } }
    & $module { param($Project) Invoke-JobsNativeSdkFromHarmony -Target $Project } $project
    $nativeConfig = Get-Content -LiteralPath (Join-Path $project '.fvmrc') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-HarmonySdk ($nativeConfig.flutter -ceq '3.38.5' -and $nativeConfig.flutterUrl -ceq 'https://github.com/flutter/flutter.git' -and $nativeConfig.cachePath -ceq (Join-Path (Split-Path -Parent $cache) 'official')) 'OH-to-native return selects explicit official source and separate cache'
    Assert-HarmonySdk ($nativeConfig.custom.keep -eq $true -and $nativeConfig.flavors.dev -ceq '3.38.4') 'native return preserves user config fields'
    Assert-HarmonySdk ([IO.File]::ReadAllText((Join-Path $project '.vscode/settings.json')) -ceq $beforeIde -and [IO.File]::ReadAllText((Join-Path $project '.gitignore')) -ceq $beforeIgnore) 'round-trip preserves live IDE and ignore'
    Assert-HarmonySdk ($env:FVM_CACHE_PATH -ceq $existingCache -and $env:FVM_FLUTTER_URL -ceq 'keep-existing-url' -and $env:FVM_USE_GIT_CACHE -ceq 'true' -and $env:PATH -ceq $pathBefore) 'native return restores inherited environment'
    Assert-HarmonyThrows { & $module { param($Project) Invoke-JobsNativeSdkFromHarmony -Target $Project } $project } 'native return route rejects unrelated native binding'
    [IO.File]::WriteAllText((Join-Path $project '.fvmrc'), '{"flutter":"custom_unknown","flutterUrl":"https://example.invalid/fork.git"}')
    Assert-HarmonyThrows { & $module { param($Project) & $script:HarmonyManager { param($Path) Invoke-JobsFlutterVersionAction $Path } $Project } $project } 'native selector rejects unknown fork before toolchain operations'
    $menu = [IO.File]::ReadAllText((Join-Path $root 'JobsFlutterTools/Scripts/FlutterToolsMenu.h'))
    $entryBlock = [regex]::Match($menu, '(?s)static const Entry Entries\[\]\s*=\s*\{(.*?)\n\};').Groups[1].Value
    $actions = @([regex]::Matches($entryBlock, '\{L"([^"]+)",') | ForEach-Object { $_.Groups[1].Value })
    Assert-HarmonySdk ($actions.Count -eq 36 -and $actions[20] -ceq 'sdk-manage' -and $actions[21] -ceq 'ohos-sdk-manage' -and $actions[22] -ceq 'java-manage') 'regrouping keeps stable native/OH/Java SDK command offsets'
    foreach ($name in @('Action.psm1','Invoke.ps1','OpenCmd.ps1')) {
        Assert-HarmonySdk ([IO.File]::ReadAllText((Join-Path $root ('JobsFlutterTools/Scripts/' + $name))).Contains("'ohos-sdk-manage'")) ('dispatch whitelist includes OH: ' + $name)
    }
    $native = [IO.File]::ReadAllText((Join-Path $root 'JobsFlutterTools/Scripts/ContextMenu.cpp'))
    Assert-HarmonySdk ($native.Contains('JobsFlutterTools::DevelopmentLayout(selected)') -and $native.Contains('JobsFlutterTools::SelectedGroupEntries(group, selected)')) 'native menus consume the shared hierarchy while retaining leaf indices'
    Assert-HarmonySdk ($menu.Contains('selected[index] && IsActionVisible(index)') -and $native.Contains('!selected[index]')) 'selected actions are checked both while displaying and invoking'
    Assert-HarmonySdk ($native.Contains('JobsFlutterTools::IsActionAvailable(index, IsHarmonyProject(target))') -and $native.Contains('return E_ACCESSDENIED;')) 'Harmony build remains visible while invocation rechecks adaptation and rejects unavailable targets'
    Assert-HarmonySdk ($menu.Contains('!SelectedGroupEntries(group, selected).empty()') -and $native.Contains('GetMenuItemCount(repairs) > 0')) 'empty diagnostic and repair submenus stay hidden'
    foreach ($file in @('JobsFlutterTools/Scripts/HarmonySdk.psm1','JobsFlutterTools/Scripts/CheckHarmonySdk.ps1')) {
        $tokens = $null; $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $root $file), [ref]$tokens, [ref]$errors)
        Assert-HarmonySdk (@($errors).Count -eq 0) ('PowerShell syntax: ' + $file)
        $bytes = [IO.File]::ReadAllBytes((Join-Path $root $file))
        Assert-HarmonySdk ($bytes[0] -eq 0xef -and $bytes[1] -eq 0xbb -and $bytes[2] -eq 0xbf) ('PowerShell 5.1 UTF-8 BOM: ' + $file)
    }
    Write-Host ('PASS: ' + $script:count + ' OpenHarmony SDK assertions; no network or registry changes')
} finally {
    foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
    if ([IO.Directory]::Exists($temporary)) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

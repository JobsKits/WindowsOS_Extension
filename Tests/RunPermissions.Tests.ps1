# RunPermissions.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年10月24日，星期六.
# Cross-platform transaction fixtures; real ACL checks only use temporary NTFS files on Windows.
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
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('JobsRunPermissions-' + [guid]::NewGuid().ToString('N'))
$module = Import-Module (Join-Path $root 'JobsRunAuthorizer/Scripts/Action.psm1') -PassThru -DisableNameChecking
$script:count = 0
function Assert { param([bool]$Value, [string]$Why); if (-not $Value) { throw ('FAIL: ' + $Why) }; $script:count++ }
function Throws { param([scriptblock]$Body, [string]$Why); $caught = $false; try { & $Body | Out-Null } catch { $caught = $true }; Assert $caught $Why }
function New-Fixture {
    $file = [pscustomobject]@{ Identity = 'fixture-id'; Hash = 'hash-1'; Path = 'fixture-path'; Sddl = 'base'; Applies = 0; ForceDeny = $false }
    $file | Add-Member ScriptMethod Capture { return $this.Sddl }
    $file | Add-Member ScriptMethod Apply { param($Expected, $Replacement); if ($Expected -cne $this.Sddl) { throw 'conflict' }; $this.Sddl = $Replacement; $this.Applies++ }
    $file | Add-Member ScriptMethod HasExecute { return $this.Sddl.EndsWith('|Grant') -and -not $this.ForceDeny }
    return $file
}
try {
    [void][IO.Directory]::CreateDirectory($temporary)
    $core = Join-Path $root 'JobsRunAuthorizer/Scripts/RunPermissionFile.cs'
    Add-Type -Path $core
    Assert ($null -ne ('Jobs.RunPermissionFile' -as [type])) 'native handle core compiles'
    $native = [IO.File]::ReadAllText($core)
    Assert ($native -notmatch 'IsExecutablePath') 'backend accepts ordinary single files without extension filtering'
    . (Join-Path $root 'JobsRunAuthorizer/Scripts/TerminalLauncher.ps1')
    $transportTarget = Join-Path $temporary '脚本 & 100% !.exe'
    [IO.File]::WriteAllText($transportTarget, 'inert transport fixture')
    $start = New-JobsPermissionTerminalStart $transportTarget (Join-Path $root 'JobsRunAuthorizer/Scripts') $temporary 'powershell.exe'
    Assert ($start.WorkingDirectory -ceq (Get-Item -LiteralPath $transportTarget).DirectoryName) 'single-file terminal starts in parent directory, never file path'
    Assert ($start.EnvironmentVariables['JOBS_RUN_PERMISSION_TARGET'] -ceq $transportTarget -and -not $start.Arguments.Contains($transportTarget)) 'CMD keeps metacharacter file path in process environment'
    Assert ($start.Arguments.StartsWith('/d /v:off /k ') -and -not $start.UseShellExecute) 'fixed transport disables delayed expansion and shell interpolation'
    Throws { New-JobsPermissionTerminalStart $temporary $root $temporary 'powershell.exe' } 'terminal refuses directory target'
    foreach ($name in @('RunPermissions.ps1', 'RunPermissionFile.cs', 'RunPermissionTarget.h')) {
        Assert ((Get-FileHash -LiteralPath (Join-Path $root ('JobsRunAuthorizer/Scripts/' + $name))).Hash -ceq (Get-FileHash -LiteralPath (Join-Path $root ('JobsRunAuthorizationRevoker/Scripts/' + $name))).Hash) 'paired packages carry identical independent core'
    }
    & $module { function script:Get-JobsPermissionReplacement { param($Original, $Sid, $Allow); if ($Allow) { return $Original + '|Grant' }; return $Original + '|Revoke' } }
    $record = Join-Path $temporary 'fixture.json'
    $alreadyDenied = New-Fixture
    $unusedRecord = Join-Path $temporary 'already-denied.json'
    & $module { param($File, $Record) Invoke-JobsPermissionChange $File 'fixture-sid' Revoke $Record } $alreadyDenied $unusedRecord
    Assert ($alreadyDenied.Applies -eq 0 -and -not [IO.File]::Exists($unusedRecord)) 'already denied file stays untouched without creating a record'
    $file = New-Fixture
    & $module { param($File, $Record) Invoke-JobsPermissionChange $File 'fixture-sid' Grant $Record } $file $record
    Assert ($file.Sddl -ceq 'base|Grant' -and $file.Applies -eq 1) 'grant adds only our allowed state'
    & $module { param($File, $Record) Invoke-JobsPermissionChange $File 'fixture-sid' Grant $Record } $file $record
    Assert ($file.Applies -eq 1) 'repeated grant does not rewrite'
    $file.Hash = 'edited-content'
    & $module { param($File, $Record) Invoke-JobsPermissionChange $File 'fixture-sid' Revoke $Record } $file $record
    Assert ($file.Sddl -ceq 'base|Revoke') 'normal same-file content edit does not prevent revoke'
    & $module { param($File, $Record) Invoke-JobsPermissionChange $File 'fixture-sid' Grant $Record } $file $record
    Assert ($file.Sddl -ceq 'base|Grant') 'grant after revoke removes only our deny and restores original base'
    $old = $file.Sddl
    $file.Sddl = 'external-acl'
    Throws { & $module { param($File, $Record) Invoke-JobsPermissionChange $File 'fixture-sid' Revoke $Record } $file $record } 'external DACL edit stops'
    Assert ($file.Sddl -ceq 'external-acl') 'conflict never overwrites external rules'
    $file.Sddl = $old
    $file.Identity = 'replaced-file'
    Throws { & $module { param($File, $Record) Invoke-JobsPermissionChange $File 'fixture-sid' Revoke $Record } $file $record } 'replaced identity rejected'
    $file = New-Fixture
    $failureRecord = Join-Path $temporary 'failure.json'
    $file.ForceDeny = $true
    Throws { & $module { param($File, $Record) Invoke-JobsPermissionChange $File 'fixture-sid' Grant $Record } $file $failureRecord } 'effective group denial fails grant'
    Assert ($file.Sddl -ceq 'base' -and -not [IO.File]::Exists($failureRecord)) 'failed grant precisely restores ACL and prior record absence'
    $file = New-Fixture
    $prepared = Join-Path $temporary 'prepared.json'
    @{ Version = 1; Identity = $file.Identity; Hash = $file.Hash; Path = $file.Path; Sid = 'fixture-sid'; OriginalSddl = 'base'; BeforeSddl = 'base'; ExpectedSddl = 'base|Revoke'; Mode = 'Revoke'; Stage = 'Prepared' } | ConvertTo-Json | Set-Content -LiteralPath $prepared -Encoding UTF8
    $file.Sddl = 'base|Revoke'
    & $module { param($File, $Record) Invoke-JobsPermissionChange $File 'fixture-sid' Grant $Record } $file $prepared
    Assert ($file.Sddl -ceq 'base|Grant') 'interrupted applied Prepared state can switch without stacking ACEs'
    Remove-Module $module
    $module = Import-Module (Join-Path $root 'JobsRunAuthorizer/Scripts/Action.psm1') -PassThru -DisableNameChecking
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        $target = Join-Path $temporary '普通文件 & 100%.txt'
        [IO.File]::WriteAllText($target, 'inert fixture, never executed')
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $realRecord = Join-Path $temporary 'real.json'
        $held = $null
        $baseline = ''
        try {
            $held = New-Object Jobs.RunPermissionFile($target)
            $baseline = $held.Capture()
            & $module { param($Path) Assert-JobsPermissionPath $Path } $target | Out-Null
            & $module { param($File, $Sid, $Record) Invoke-JobsPermissionChange $File $Sid Revoke $Record } $held $sid $realRecord
            Assert (-not $held.HasExecute()) 'real native new ExecuteFile open denied after revoke'
            $denied = $held.Capture()
            $raw = New-Object Security.AccessControl.RawSecurityDescriptor($denied)
            Assert ($raw.DiscretionaryAcl[0].AccessMask -eq 32 -and $raw.DiscretionaryAcl[0].SecurityIdentifier.Value -ceq $sid) 'real DACL adds only current SID execute deny at front'
            $held.Dispose(); $held = $null
            [IO.File]::AppendAllText($target, ' ordinary edit')
            $held = New-Object Jobs.RunPermissionFile($target)
            & $module { param($File, $Sid, $Record) Invoke-JobsPermissionChange $File $Sid Grant $Record } $held $sid $realRecord
            Assert ($held.HasExecute()) 'real edited file regains direct execution access without executing'
            $allowed = $held.Capture()
            $baselineRaw = New-Object Security.AccessControl.RawSecurityDescriptor($baseline)
            $allowedRaw = New-Object Security.AccessControl.RawSecurityDescriptor($allowed)
            Assert ($allowedRaw.DiscretionaryAcl.Count -eq $baselineRaw.DiscretionaryAcl.Count + 1) 'real roundtrip leaves original ACE count plus one own allow'
            $held.Apply($allowed, $baseline)
            Assert ($held.Capture() -ceq $baseline) 'real exact original ACL restoration for fixture cleanup'
            Throws { $stream = [IO.File]::Open($target, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::Read); $stream.Dispose() } 'held file excludes concurrent content writes'
        } finally {
            if ($null -ne $held) {
                try { $now = $held.Capture(); if ($baseline -and $now -cne $baseline) { $held.Apply($now, $baseline) } } finally { $held.Dispose() }
            }
        }
        $hardLink = Join-Path $temporary 'hard-link.exe'
        New-Item -ItemType HardLink -Path $hardLink -Target $target | Out-Null
        Throws { $linked = New-Object Jobs.RunPermissionFile($target); $linked.Dispose() } 'hard-link target rejected'
        Throws { & $module { param($Path) Assert-JobsPermissionPath $Path } $temporary } 'directory rejected'
        Write-Host 'Windows temporary NTFS ACL behavior verified; no user file or executable launch.'
    } else { Write-Host 'SKIP: real NTFS ACL/API branch requires Windows; native compile and isolated transaction tests completed.' }
    foreach ($name in @('JobsRunAuthorizer', 'JobsRunAuthorizationRevoker')) {
        $installer = Import-Module (Join-Path $root ($name + '/Scripts/PackageInstaller.psm1')) -PassThru -DisableNameChecking
        $manifest = Get-Content -LiteralPath (Join-Path $root ($name + '/Extension.json')) -Raw -Encoding UTF8 | ConvertFrom-Json
        $plan = @(& $installer { param($Manifest) Get-JobsPackageRegistryPlan $Manifest '/temporary/release' 'powershell.exe' } $manifest)
        Assert ($plan.Count -eq 2 -and $plan[0].Key.Contains('Classes\*\shellex\')) 'single-file native registration only'
    }
    Write-Host ('PASS: RunPermissions (' + $script:count + ' assertions)')
} finally {
    Remove-Module $module -ErrorAction SilentlyContinue
    if ([IO.Directory]::Exists($temporary)) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

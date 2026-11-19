# FileVolumes.ps1 | JobsFileVolumes
# Created by Jobs on 2026年10月28日，星期三.
# 文件分卷内核；固定内存流式读写，无覆盖发布，始终保留原件。

# JOBS_SOURCE_LAYOUT_ROOT_V1：只解析本文件逻辑目录，发布 flat 副本保持原资源基准。
$script:JobsLayoutFileVolumesRoot = $(if ([IO.Path]::GetFileName($PSScriptRoot) -ceq 'FileVolumes.ps1') { Split-Path -Parent $PSScriptRoot } else { $PSScriptRoot })

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

function Get-JobsVolumeFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not [IO.Path]::IsPathRooted($Path)) { throw '文件路径必须是绝对路径。' }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSProvider.Name -ne 'FileSystem' -or $item.PSIsContainer -or
        ($item.Attributes -band ([IO.FileAttributes]::ReparsePoint -bor [IO.FileAttributes]::Device)) -ne 0) { throw '仅支持普通文件，不接受文件夹、链接或设备。' }
    return $item
}

function Get-JobsVolumePart {
    param([string]$Name)
    if ($Name -cnotmatch '^(.+)@([0-9]{1,9})of([0-9]{1,9})$') { throw '分卷命名必须是 完整文件名@序号of总数。' }
    $original = $Matches[1]
    $index = [int]::Parse($Matches[2], [Globalization.CultureInfo]::InvariantCulture)
    $total = [int]::Parse($Matches[3], [Globalization.CultureInfo]::InvariantCulture)
    if ($original -in @('.', '..') -or $original -match '[<>:"/\\|?*\x00-\x1f]|[. ]$' -or
        $original -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)' -or
        $total -lt 1 -or $index -lt 1 -or $index -gt $total) { throw '非法原文件名或卷号。' }
    return [pscustomobject]@{ Name = $original; Index = $index; Total = $total }
}

function Get-JobsVolumeGroup {
    param([Parameter(Mandatory = $true)][string[]]$Paths)
    if ($Paths.Count -lt 2 -or $Paths.Count -gt 10000) { throw '合并必须完整多选同组分卷（2 至 10000 卷）。' }
    $directory = ''; $name = ''; $parts = @{}; $bytes = [long]0
    foreach ($path in $Paths) {
        $file = Get-JobsVolumeFile $path
        $part = Get-JobsVolumePart $file.Name
        if ($part.Total -ne $Paths.Count -or $file.Length -le 0) { throw '总数与选择数量不符，或存在空分卷。' }
        if ($name.Length -eq 0) { $name = $part.Name; $directory = $file.DirectoryName }
        if ($part.Name -cne $name -or $file.DirectoryName -cne $directory -or $parts.ContainsKey($part.Index)) { throw '请选择同目录、同原文件名、无重复编号的一组完整分卷。' }
        $parts[$part.Index] = $file
        if ($bytes -gt ([long]::MaxValue - $file.Length)) { throw '分卷总长度超出支持范围。' }
        $bytes += $file.Length
    }
    $ordered = @()
    for ($index = 1; $index -le $Paths.Count; $index++) {
        if (-not $parts.ContainsKey($index)) { throw ('缺少第 ' + $index + ' 卷；请全选后重试。') }
        $ordered += $parts[$index]
    }
    return [pscustomobject]@{ Name = $name; Directory = $directory; Files = $ordered; Bytes = $bytes }
}

function Assert-JobsVolumeUnchanged {
    param($Snapshot)
    $current = Get-JobsVolumeFile $Snapshot.FullName
    if ($current.Length -ne $Snapshot.Length -or $current.LastWriteTimeUtc -ne $Snapshot.LastWriteTimeUtc -or
        $current.CreationTimeUtc -ne $Snapshot.CreationTimeUtc) { throw ('输入文件已变化，停止发布：' + $Snapshot.FullName) }
}

function Get-JobsVolumeDigest {
    param([Parameter(Mandatory = $true)][IO.Stream]$Stream)
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToBase64String($hash.ComputeHash($Stream)) } finally { $hash.Dispose() }
}

function Add-JobsVolumeStream {
    param([IO.Stream]$InputStream, [IO.Stream]$OutputStream, $Hash, [byte[]]$Buffer, [long]$Count)
    $remaining = $Count
    while ($remaining -gt 0) {
        $take = [int][Math]::Min($Buffer.Length, $remaining)
        $read = $InputStream.Read($Buffer, 0, $take)
        if ($read -le 0) { throw '输入提前结束，候选结果不发布。' }
        $OutputStream.Write($Buffer, 0, $read)
        [void]$Hash.TransformBlock($Buffer, 0, $read, $Buffer, 0)
        $remaining -= $read
    }
}

function Invoke-JobsFileMerge {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string[]]$Paths)
    $group = Get-JobsVolumeGroup $Paths
    $destination = Join-Path $group.Directory $group.Name
    if (Test-Path -LiteralPath $destination) { throw ('目标已存在，拒绝覆盖：' + $destination) }
    $candidate = Join-Path $group.Directory ('.JobsMerge-' + [guid]::NewGuid().ToString('N') + '.partial')
    $inputs = New-Object 'Collections.Generic.List[IO.Stream]'
    $hash = [Security.Cryptography.SHA256]::Create()
    $output = $null
    try {
        # FileShare.Read 在 Windows 上阻止写入和删除；所有输入先锁定，再生成输出。
        foreach ($file in $group.Files) {
            $stream = [IO.File]::Open($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            $inputs.Add($stream)
            Assert-JobsVolumeUnchanged $file
            if ($stream.Length -ne $file.Length) { throw '输入长度已变化。' }
        }
        $output = [IO.File]::Open($candidate, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $buffer = New-Object byte[] 1048576
        for ($index = 0; $index -lt $inputs.Count; $index++) {
            Add-JobsVolumeStream -InputStream $inputs[$index] -OutputStream $output -Hash $hash -Buffer $buffer -Count $group.Files[$index].Length
        }
        [void]$hash.TransformFinalBlock([byte[]]@(), 0, 0)
        $expected = [Convert]::ToBase64String($hash.Hash)
        $output.Flush($true); $output.Dispose(); $output = $null
        $verify = [IO.File]::Open($candidate, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            if ($verify.Length -ne $group.Bytes -or (Get-JobsVolumeDigest $verify) -cne $expected) { throw '候选长度 / SHA-256 校验失败。' }
        } finally { $verify.Dispose() }
        foreach ($file in $group.Files) { Assert-JobsVolumeUnchanged $file }
        [IO.File]::Move($candidate, $destination)
        Write-Host ('✔ 合并完成：' + $destination + '；全部分卷保留。') -ForegroundColor Green
        return $destination
    } catch {
        if ([IO.File]::Exists($candidate)) { Write-Warning ('未发布候选保留：' + $candidate) }
        throw
    } finally {
        if ($null -ne $output) { $output.Dispose() }
        foreach ($stream in $inputs) { $stream.Dispose() }
        $hash.Dispose()
    }
}

function Invoke-JobsFileSplit {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][long]$LimitBytes)
    $file = Get-JobsVolumeFile $Path
    if ($LimitBytes -lt 1 -or $file.Length -le $LimitBytes) { throw '文件必须大于所选分卷上限；请调小上限后重试。' }
    $total = [long][Math]::Ceiling([decimal]$file.Length / [decimal]$LimitBytes)
    if ($total -gt 10000) { throw '超过 10000 卷，请调大分卷上限。' }
    $chunk = [long][Math]::Ceiling([decimal]$file.Length / [decimal]$total)
    $destination = Join-Path $file.DirectoryName ($file.Name + '.chunks')
    if (Test-Path -LiteralPath $destination) { throw ('分卷目录已存在，拒绝覆盖：' + $destination) }
    $candidate = Join-Path $file.DirectoryName ('.JobsSplit-' + [guid]::NewGuid().ToString('N') + '.partial')
    $inputStream = $null; $hash = [Security.Cryptography.SHA256]::Create()
    try {
        $inputStream = [IO.File]::Open($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        Assert-JobsVolumeUnchanged $file
        if ($inputStream.Length -ne $file.Length) { throw '源文件长度已变化。' }
        [void][IO.Directory]::CreateDirectory($candidate)
        $buffer = New-Object byte[] 1048576
        $remaining = $file.Length
        $volumes = @()
        for ($index = 1; $index -le $total; $index++) {
            $path = Join-Path $candidate ($file.Name + '@' + $index + 'of' + $total)
            $output = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            $size = [long][Math]::Min($chunk, $remaining)
            try {
                Add-JobsVolumeStream -InputStream $inputStream -OutputStream $output -Hash $hash -Buffer $buffer -Count $size
                $output.Flush($true)
            } finally { $output.Dispose() }
            $volumes += $path; $remaining -= $size
        }
        if ($remaining -ne 0 -or $inputStream.Position -ne $inputStream.Length) { throw '拆分总长度校验失败。' }
        [void]$hash.TransformFinalBlock([byte[]]@(), 0, 0)
        $expected = [Convert]::ToBase64String($hash.Hash)
        $composed = [Security.Cryptography.SHA256]::Create()
        try {
            foreach ($path in $volumes) {
                $part = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
                try {
                    if ($part.Length -lt 1 -or $part.Length -gt $LimitBytes) { throw '分卷长度超出范围。' }
                    while (($read = $part.Read($buffer, 0, $buffer.Length)) -gt 0) { [void]$composed.TransformBlock($buffer, 0, $read, $buffer, 0) }
                } finally { $part.Dispose() }
            }
            [void]$composed.TransformFinalBlock([byte[]]@(), 0, 0)
            if ([Convert]::ToBase64String($composed.Hash) -cne $expected) { throw '分卷重组 SHA-256 不一致。' }
        } finally { $composed.Dispose() }
        $inputStream.Position = 0
        if ((Get-JobsVolumeDigest $inputStream) -cne $expected) { throw '源文件内容在拆分期间发生变化。' }
        Assert-JobsVolumeUnchanged $file
        [IO.Directory]::Move($candidate, $destination)
        Write-Host ('✔ 拆分完成：' + $destination + '；源文件保留。') -ForegroundColor Green
        return $destination
    } catch {
        if ([IO.Directory]::Exists($candidate)) { Write-Warning ('未发布分卷保留：' + $candidate) }
        throw
    } finally {
        if ($null -ne $inputStream) { $inputStream.Dispose() }
        $hash.Dispose()
    }
}

function Show-JobsVolumeLimit {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $form = New-Object Windows.Forms.Form
    $form.Text = 'Jobs · 选择分卷上限'; $form.ClientSize = New-Object Drawing.Size(430, 180)
    $form.StartPosition = 'CenterScreen'; $form.FormBorderStyle = 'FixedDialog'; $form.MaximizeBox = $false
    $options = New-Object Windows.Forms.ComboBox
    $options.SetBounds(20, 20, 390, 30); $options.DropDownStyle = 'DropDownList'
    [void]$options.Items.AddRange([object[]]@('50 MiB', '100 MiB', '1900 MiB', '自定义 MiB'))
    $options.SelectedIndex = 0; $form.Controls.Add($options)
    $custom = New-Object Windows.Forms.NumericUpDown
    $custom.SetBounds(20, 65, 390, 30); $custom.Minimum = [decimal]0.001; $custom.Maximum = [decimal]1048576
    $custom.DecimalPlaces = 3; $custom.Value = [decimal]50; $custom.Enabled = $false
    $options.Add_SelectedIndexChanged({ $custom.Enabled = $options.SelectedIndex -eq 3 })
    $form.Controls.Add($custom)
    $confirm = New-Object Windows.Forms.Button
    $confirm.Text = '开始拆分'; $confirm.SetBounds(220, 120, 90, 35); $confirm.DialogResult = 'OK'
    $cancel = New-Object Windows.Forms.Button
    $cancel.Text = '取消'; $cancel.SetBounds(320, 120, 90, 35); $cancel.DialogResult = 'Cancel'
    $form.Controls.AddRange([Windows.Forms.Control[]]@($confirm, $cancel)); $form.CancelButton = $cancel
    try {
        if ($form.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { return [long]0 }
        $mib = $custom.Value
        if ($options.SelectedIndex -lt 3) { $mib = @([decimal]50, [decimal]100, [decimal]1900)[$options.SelectedIndex] }
        return [long][Math]::Floor($mib * 1048576)
    } finally { $form.Dispose() }
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

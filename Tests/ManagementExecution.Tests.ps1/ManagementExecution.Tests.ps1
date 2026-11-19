# ManagementExecution.Tests.ps1 | GUI 后台安装事务与输出回归
# Created by Jobs on 2026年10月28日，星期三.
# 只执行临时目录中的假安装器；不访问用户状态或注册表，不构建真实扩展。
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
$script:JobsLayoutManagementExecutionTestsRoot = $(if ([IO.Path]::GetFileName($PSScriptRoot) -ceq 'ManagementExecution.Tests.ps1') { Split-Path -Parent $PSScriptRoot } else { $PSScriptRoot })

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
Write-Host 'CHECKPOINT: entering management execution suite'
$root = Split-Path -Parent ${script:JobsLayoutManagementExecutionTestsRoot}
$panel = Import-Module (Join-Path $root 'Scripts/Installer.psm1') -PassThru -Force -DisableNameChecking
Initialize-JobsManagementProcess
Write-Host 'CHECKPOINT: management process type initialized'
$script:Assertions = 0
function Assert-Management {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
    $script:Assertions++
}
$temp = Join-Path ([IO.Path]::GetTempPath()) ('Jobs Management 中文 ' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
function Write-TestFile {
    param([string]$Path, [string]$Text)
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($true)))
}
function New-TestOperation {
    param([string]$Id, [string]$Mode = 'Install')
    [pscustomobject]@{ Id = $Id; Label = $Id; PackagePath = (Join-Path $temp $Id); Mode = $Mode; DisplayMode = $Mode; FeatureIds = @($Id) }
}
function Invoke-TestWorker {
    param([object[]]$Plan)
    $request = Join-Path $temp ([guid]::NewGuid().ToString('N') + '.json')
    Write-TestFile $request (ConvertTo-Json -InputObject @{ Plan = @($Plan) } -Depth 8)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = (Get-Process -Id $PID).Path
    $start.Arguments = '-NoLogo -NoProfile -NonInteractive -File "' + (Resolve-JobsScriptLayoutPath (Join-Path $root 'Scripts/ManagementWorker.ps1')) + '" -RequestPath "' + $request + '"'
    $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $start.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    $pump = New-Object JobsManagement.OutputPump
    $chunks = @()
    $live = $false
    $stderrLive = $false
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        $pump.Start($start)
        do {
            while ($null -ne ($chunk = $pump.Take())) {
                $chunks += $chunk
                if ($chunk.Text.Contains('正在编译42%') -and -not $pump.Process.HasExited) { $live = $true }
                if ($chunk.Text.Contains('标准错误中文') -and -not $pump.Process.HasExited) { $stderrLive = $true }
            }
            if ($clock.ElapsedMilliseconds -gt 20000) { $pump.Process.Kill(); throw '假后台超时。' }
            [void]$pump.Process.WaitForExit(25)
        } until ($pump.Process.HasExited -and $pump.Drained -and $pump.Lines.IsEmpty)
        $events = @($chunks | Where-Object { $_.IsEvent } | ForEach-Object { $_.Text.Substring(16) | ConvertFrom-Json })
        return [pscustomobject]@{ ExitCode = $pump.Process.ExitCode; Chunks = $chunks; Events = $events; Live = $live; StderrLive = $stderrLive; Text = (($chunks | ForEach-Object { $_.Text }) -join '') }
    } finally { $pump.Dispose() }
}
try {
    # 真实 Timer 回调从模块外执行，覆盖动态闭包对私有函数的寻址，不需要图形桌面。
    $timerPump = [pscustomobject]@{ Process=[pscustomobject]@{HasExited=$false} }
    $timerPump | Add-Member ScriptMethod Take { return $null }
    $timerState = [pscustomobject]@{
        Running=$true; Pump=$timerPump; FeatureStates=@{alpha='Pending'}; Operation='Install'
        RunClocks=@{Install=(New-Object Diagnostics.Stopwatch)}
        Progress=[pscustomobject]@{Value=0;Maximum=1}; StatusLabel=[pscustomobject]@{Text=''}
    }
    $timerCallback = & $panel { param($State) New-JobsManagementTimerCallback $State } $timerState
    & $timerCallback
    Assert-Management ($timerState.StatusLabel.Text.Contains('安装用时') -and $timerState.StatusLabel.Text.Contains('0 / 1')) '真实 Timer 闭包在模块外仍能读取输出并调用私有进度函数'
    $module = @'
function Invoke-JobsPackageChange {
    param([string]$PackagePath, [string]$Mode, [string[]]$ActionIds)
    [Console]::Out.Write('正在编译42%'); [Console]::Out.Flush()
    [Console]::Error.Write('标准错误中文'); [Console]::Error.Flush()
    Start-Sleep -Milliseconds 700
    Write-Host '实时宿主日志'
    Add-Content -LiteralPath (Join-Path $PackagePath 'called.txt') -Value ($Mode + ':' + ($ActionIds -join ',')) -Encoding UTF8
    if ((Split-Path -Leaf $PackagePath) -eq 'beta') { throw '隔离安装失败' }
    [pscustomobject]@{ Backup = (Join-Path $PackagePath 'fake-backup') }
}
Export-ModuleMember -Function Invoke-JobsPackageChange
'@
    foreach ($id in @('alpha', 'beta', 'gamma')) {
        Write-TestFile (Join-Path $temp ($id + '/Scripts/PackageInstaller.psm1')) $module
        Write-TestFile (Join-Path $temp ($id + '/Extension.json')) (ConvertTo-Json -InputObject @{ Id = $id })
    }
    $operation = New-TestOperation 'alpha'
    $operation | Add-Member -NotePropertyName ActionIds -NotePropertyValue @('single-action')
    Write-Host 'CHECKPOINT: starting isolated workers'
    $success = Invoke-TestWorker @($operation)
    Assert-Management ($success.ExitCode -eq 0) '成功事务返回零'
    Assert-Management ($success.Live -and $success.StderrLive) '未换行中文 stdout 与 stderr 在进程结束前分别可见'
    Assert-Management ($success.Text.Contains('实时宿主日志') -and $success.Text.Contains('fake-backup')) '宿主与备份日志进入同一输出'
    Assert-Management (($success.Events.State -join ',') -eq 'Running,Succeeded,Finished') '成功状态有明确开始完成与会话结束'
    Assert-Management ((Get-Content (Join-Path $temp 'alpha/called.txt') -Raw).Contains('Install:single-action')) '单元素动作数组完整传入假安装器'
    $failed = Invoke-TestWorker @((New-TestOperation 'alpha' 'Uninstall'), (New-TestOperation 'beta'), (New-TestOperation 'gamma'))
    Assert-Management ($failed.ExitCode -ne 0) '失败事务返回非零'
    Assert-Management (($failed.Events.State -join ',') -eq 'Running,Succeeded,Running,Failed,Running,Succeeded,Finished') '单包失败保留前项并继续后续包，最后汇总失败'
    Assert-Management ([IO.File]::Exists((Join-Path $temp 'gamma/called.txt'))) '前项失败后仍执行其它所选假安装器'
    Assert-Management ($failed.Text.Contains('隔离安装失败')) '失败原因保留在实时输出'
    Assert-Management (@($failed.Events | Where-Object { $_.State -eq 'Failed' })[0].FeatureIds[0] -eq 'beta') '失败精确映射到本包叶 ID'
    $missing = Invoke-TestWorker @((New-TestOperation 'missing-source'), (New-TestOperation 'gamma' 'Uninstall'))
    Assert-Management ($missing.ExitCode -ne 0) '所选包缺失源码时汇总失败'
    Assert-Management (($missing.Events.State -join ',') -eq 'Running,Failed,Running,Succeeded,Finished') '缺失所选包仅标记自身，后续卸载仍执行'
    Assert-Management ((Get-Content (Join-Path $temp 'gamma/called.txt') -Raw).Contains('Uninstall:')) '卸载入口不要求存在构建脚本'
    $betaCalls = Get-Content (Join-Path $temp 'beta/called.txt') -Raw
    Write-TestFile (Join-Path $temp 'beta/Extension.json') '{"Id":"wrong-owner"}'
    $identity = Invoke-TestWorker @((New-TestOperation 'beta'), (New-TestOperation 'gamma'))
    Assert-Management (($identity.Events.State -join ',') -eq 'Running,Failed,Running,Succeeded,Finished') '身份不一致的包在导入前失败，但其它包继续'
    Assert-Management ((Get-Content (Join-Path $temp 'beta/called.txt') -Raw) -ceq $betaCalls) '身份错误时不调用该包安装器'
    $empty = Invoke-TestWorker @()
    Assert-Management ($empty.ExitCode -ne 0 -and $empty.Events.Count -eq 0) '全局计划为空时立即停止，不开始任何包'
    Write-Host 'CHECKPOINT: isolated workers completed, checking launchers'
    foreach ($folder in Get-ChildItem $root -Directory | Where-Object { $_.Name -like 'Jobs*' -and (Test-Path (Resolve-JobsScriptLayoutPath (Join-Path $_.FullName 'Scripts/Manage.ps1'))) }) {
        $vbs = Get-Content -LiteralPath (Resolve-JobsScriptLayoutPath (Join-Path $folder.FullName 'Manage.vbs')) -Raw
        $cmd = Get-Content -LiteralPath (Join-Path $folder.FullName 'Manage.cmd') -Raw
        $code = @($cmd -split '\r?\n' | Where-Object { $_ -notmatch '^\s*(rem\b|::)' }) -join "`n"
        Assert-Management ($vbs.Contains('shell.Run command, 0, False') -and $vbs.Contains('-WindowStyle Hidden')) ('无控制台入口：' + $folder.Name)
        Assert-Management ($cmd.Contains('wscript.exe') -and $cmd -notmatch '\bpause\b') ('CMD 兼容入口仅转交隐藏 GUI：' + $folder.Name)
        Assert-Management ($code -match '(?im)^exit /b %errorlevel%\s*$' -and $code -notmatch '(?i)taskkill|start\s+/wait|powershell|Read-Host') ('CMD 唤起后立即结束脚本，不关闭已有会话或承担后台任务：' + $folder.Name)
    }
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        Add-Type -AssemblyName System.Windows.Forms
        # 事件异常直接令夹具失败，不能弹默认错误对话框卡住原生回归。
        [Windows.Forms.Application]::SetUnhandledExceptionMode([Windows.Forms.UnhandledExceptionMode]::ThrowException)
        # 真实 CMD / WScript 链只启动临时假界面进程，验证启动脚本不会等待其任务结束。
        Write-Host 'CHECKPOINT: starting real CMD and WScript fixture'
        $launcherRoot = Join-Path $temp 'CMD 启动 中文'
        $fakeManager = @'
$directory = Split-Path -Parent $PSScriptRoot
[IO.File]::WriteAllText((Join-Path $directory 'started'), 'ready')
$deadline = [DateTime]::UtcNow.AddSeconds(15)
while (-not [IO.File]::Exists((Join-Path $directory 'release')) -and [DateTime]::UtcNow -lt $deadline) {
    [Threading.Thread]::Sleep(25)
}
[IO.File]::WriteAllText((Join-Path $directory 'finished'), 'done')
'@
        Write-TestFile (Resolve-JobsScriptLayoutPath (Join-Path $launcherRoot 'Scripts/Manage.ps1')) $fakeManager
        Copy-Item -LiteralPath (Join-Path $root 'Infrastructure/Manage.cmd') -Destination (Join-Path $launcherRoot 'Manage.cmd')
        Copy-Item -LiteralPath (Resolve-JobsScriptLayoutPath (Join-Path $root 'Infrastructure/Manage.vbs')) -Destination (Resolve-JobsScriptLayoutPath (Join-Path $launcherRoot 'Manage.vbs'))
        $launchStart = New-Object Diagnostics.ProcessStartInfo
        $launchStart.FileName = Join-Path $env:SystemRoot 'System32/cmd.exe'
        $launchStart.Arguments = '/d /c ""' + (Join-Path $launcherRoot 'Manage.cmd') + '""'
        $launchStart.UseShellExecute = $false
        $launchStart.CreateNoWindow = $true
        $launch = [Diagnostics.Process]::Start($launchStart)
        try {
            if (-not $launch.WaitForExit(10000)) { $launch.Kill(); throw 'CMD 轻量启动器未及时退出。' }
            Assert-Management ($launch.ExitCode -eq 0) '原 CMD 成功唤起 WScript 后结束'
            $deadline = [DateTime]::UtcNow.AddSeconds(10)
            while (-not (Test-Path -LiteralPath (Join-Path $launcherRoot 'started')) -and [DateTime]::UtcNow -lt $deadline) { [Threading.Thread]::Sleep(25) }
            Assert-Management (Test-Path -LiteralPath (Join-Path $launcherRoot 'started')) '中文空格目录经原 CMD 和 VBS 启动隐藏假界面'
            Assert-Management (-not (Test-Path -LiteralPath (Join-Path $launcherRoot 'finished'))) 'CMD 结束时隐藏界面仍在运行，任务不依附启动窗口'
        } finally {
            [IO.File]::WriteAllText((Join-Path $launcherRoot 'release'), 'finish')
            $deadline = [DateTime]::UtcNow.AddSeconds(10)
            while (-not (Test-Path -LiteralPath (Join-Path $launcherRoot 'finished')) -and [DateTime]::UtcNow -lt $deadline) { [Threading.Thread]::Sleep(25) }
            $launch.Dispose()
        }
        Write-Host 'CHECKPOINT: CMD and WScript fixture completed, creating form'
        $features = @([pscustomobject]@{ Id = 'alpha'; Label = '假安装功能'; Description = '隔离测试'; Group = '测试' })
        $plan = @($operation)
        $factory = { param($Choice) $plan }.GetNewClosure()
        $state = & $panel { param($Features, $BuildPlan, $Worker) New-JobsFeatureSelectionForm -Packages $Features -Selected @('alpha') -BuildPlan $BuildPlan -WorkerPath $Worker } $features $factory (Resolve-JobsScriptLayoutPath (Join-Path $root 'Scripts/ManagementWorker.ps1'))
        try {
            Assert-Management ($state.LogView.ReadOnly -and $state.LogView.ShortcutsEnabled) 'GUI 日志只读且允许键盘复制'
            Assert-Management (-not $state.Form.TopMost) '任务面板是普通窗口，不在其它应用之上置顶'
            Write-Host 'CHECKPOINT: starting form background transaction'
            Start-JobsManagementRun $state ([pscustomobject]@{ Features = @('alpha'); Mode = 'Install' })
            Assert-Management ($state.Running -and -not $state.CancelButton.Enabled -and -not $state.Checks[0].Enabled) '执行时禁用选择与关闭，保留事务生命周期'
            Write-Host 'CHECKPOINT: pumping form events and output'
            $clock = [Diagnostics.Stopwatch]::StartNew()
            while ($state.Running -and $clock.ElapsedMilliseconds -lt 20000) {
                [Windows.Forms.Application]::DoEvents()
                [Threading.Thread]::Sleep(25)
                Read-JobsManagementOutput $state
            }
            Assert-Management (-not $state.Running -and $state.FeatureStates['alpha'] -eq 'Succeeded') 'GUI 完成后显示叶项成功并保留面板'
            Assert-Management ($state.LogView.Text.Contains('正在编译42%') -and $state.CancelButton.Enabled) 'GUI 内可读执行日志并恢复关闭'
        } finally {
            $state.Timer.Dispose(); $state.LogView.Font.Dispose(); $state.Form.Dispose(); $state.ToolTip.Dispose(); $state.Font.Dispose()
        }
    } else { Write-Host 'SKIP: WinForms 实际控件需要 Windows；假后台与无换行双流已验证。' }
} finally { Remove-Item -LiteralPath $temp -Recurse -Force }
Write-Host ('PASS: ManagementExecution.Tests.ps1 (' + $script:Assertions + ' assertions)')

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

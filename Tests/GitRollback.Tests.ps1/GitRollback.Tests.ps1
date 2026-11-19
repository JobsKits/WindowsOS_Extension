# GitRollback.Tests.ps1 | 临时 Git 工作树隔离回归
# Created by Jobs on 2026年10月26日，星期一.
[CmdletBinding()]
param([string]$FzfProbeExecutable)
# JOBS_SOURCE_LAYOUT_ROOT_V1：只解析本文件逻辑目录，发布 flat 副本保持原资源基准。
$script:JobsLayoutGitRollbackTestsRoot = $(if ([IO.Path]::GetFileName($PSScriptRoot) -ceq 'GitRollback.Tests.ps1') { Split-Path -Parent $PSScriptRoot } else { $PSScriptRoot })

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
$root = Split-Path -Parent ${script:JobsLayoutGitRollbackTestsRoot}
$base = [IO.Path]::GetTempPath()
if ([IO.Directory]::Exists('/private/tmp')) { $base = '/private/tmp' }
$temp = Join-Path $base ('JobsRollback 中文 & ' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$savedLocal = $env:LOCALAPPDATA
$savedGlobal = $env:GIT_CONFIG_GLOBAL
$savedSystem = $env:GIT_CONFIG_NOSYSTEM
$env:LOCALAPPDATA = Join-Path $temp 'AppData'
$env:GIT_CONFIG_GLOBAL = Join-Path $temp 'global.gitconfig'
$env:GIT_CONFIG_NOSYSTEM = '1'
[IO.File]::WriteAllText($env:GIT_CONFIG_GLOBAL, '')
Import-Module (Join-Path $root 'Infrastructure/Common.psm1') -DisableNameChecking
$git = Find-JobsExecutable 'git.exe' @('git')
if (-not $git) { throw 'Test requires Git.' }
$module = Import-Module (Join-Path $root 'JobsGitRollback/Scripts/Action.psm1') -PassThru -DisableNameChecking
$script:assertions = 0
function Assert-Rollback { param([bool]$Condition,[string]$Message) $script:assertions++; if (-not $Condition) { throw ('FAIL: ' + $Message) } }
function Run-Git {
    param([string]$Directory,[string[]]$Arguments)
    $result = Invoke-JobsProcess -FilePath $git -Arguments (@('-c','core.hooksPath=','-C',$Directory) + $Arguments) -TimeoutSeconds 30
    if ($result.ExitCode -ne 0) { throw ('Fixture Git failed: ' + $Arguments[0] + ' ' + $result.StdErr) }
    return $result.StdOut.TrimEnd("`r", "`n")
}
function New-Fixture {
    param([string]$Name)
    $directory = Join-Path $temp $Name
    [void][IO.Directory]::CreateDirectory($directory)
    [void](Run-Git $directory @('init','-b','main'))
    [void](Run-Git $directory @('config','user.name','Jobs Test'))
    [void](Run-Git $directory @('config','user.email','jobs@example.invalid'))
    [void](Run-Git $directory @('config','commit.gpgSign','false'))
    [void](Run-Git $directory @('config','core.autocrlf','false'))
    [IO.File]::WriteAllText((Join-Path $directory 'a.txt'), 'base')
    [void](Run-Git $directory @('add','.'))
    [void](Run-Git $directory @('commit','-m','base'))
    $baseCommit = Run-Git $directory @('rev-parse','HEAD')
    [IO.File]::WriteAllText((Join-Path $directory 'a.txt'), 'second')
    [void](Run-Git $directory @('commit','-am','second'))
    return @{ Root=$directory; Base=$baseCommit; Head=(Run-Git $directory @('rev-parse','HEAD')) }
}
function New-Context {
    param([string]$Directory)
    & $module {
        param($Directory,$Git)
        $boundary = Get-JobsRollbackBoundary $Directory
        $context = @{Git=$Git;Root=$boundary.Root;Metadata=$boundary.Metadata;Selected=$Directory}
        $context.Branch = Get-JobsRollbackBranch $context
        $context.Head = Get-JobsRollbackValue $context @('rev-parse','--verify','HEAD^{commit}')
        Assert-JobsRollbackContext $context
        return $context
    } $Directory $git
}
function Expect-Throw {
    param([scriptblock]$Action,[string]$Message)
    $didThrow=$false
    try { & $Action | Out-Null } catch { $didThrow=$true }
    Assert-Rollback $didThrow $Message
}
try {
    $f = New-Fixture 'normal'
    $nested = Join-Path $f.Root 'inside 中文'
    [void][IO.Directory]::CreateDirectory($nested)
    $context=New-Context $nested
    Assert-Rollback ($context.Root -ceq $f.Root) '普通内部目录解析最近工作树'
    $inner = New-Fixture 'normal/inner'
    Assert-Rollback ((New-Context $inner.Root).Root -ceq $inner.Root) '独立嵌套仓库使用自身'
    $broken=Join-Path $f.Root 'broken'
    [void][IO.Directory]::CreateDirectory($broken)
    [IO.File]::WriteAllText((Join-Path $broken '.git'),'malformed')
    Expect-Throw { New-Context $broken } '畸形内层 gitfile 不回落父仓'
    Expect-Throw { New-Context (Join-Path $f.Root '.git/objects') } 'Git 元数据内部拒绝'
    Expect-Throw { New-Context $temp } '普通非Git目录拒绝'
    $bare=Join-Path $temp 'bare'
    [void](Run-Git $temp @('init','--bare',$bare))
    Expect-Throw { New-Context $bare } '裸仓拒绝'
    $worktree=Join-Path $temp 'linked worktree'
    [void](Run-Git $f.Root @('worktree','add','-b','linked',$worktree))
    Assert-Rollback ((New-Context $worktree).Root -ceq $worktree) 'worktree gitfile和commondir识别'
    [void](Run-Git $f.Root @('-c','protocol.file.allow=always','submodule','add',$inner.Root,'module'))
    $sub=Join-Path $f.Root 'module'
    Assert-Rollback ((New-Context $sub).Root -ceq $sub) '真实子模块gitfile不指向父仓'
    $symlink=Join-Path $temp 'link'
    try {
        New-Item -ItemType SymbolicLink -Path $symlink -Target $f.Root -ErrorAction Stop | Out-Null
        Expect-Throw { New-Context $symlink } '链接目录拒绝'
    } catch { Write-Host 'SKIP symbolic link fixture creation (host privilege)' }
    $s=New-Fixture 'soft'
    [IO.File]::WriteAllText((Join-Path $s.Root 'a.txt'),'staged')
    [void](Run-Git $s.Root @('add','a.txt'))
    [IO.File]::WriteAllText((Join-Path $s.Root 'a.txt'),'unstaged')
    $index=Join-Path $s.Root '.git/index'
    $indexBefore=(Get-FileHash -LiteralPath $index).Hash
    $ctx=New-Context $s.Root
    & $module { param($C,$Commit) Invoke-JobsRollbackSoft $C $Commit 'base' } $ctx $s.Base
    Assert-Rollback ((Run-Git $s.Root @('rev-parse','HEAD')) -ceq $s.Base) 'soft移动HEAD到祖先'
    Assert-Rollback ((Get-FileHash -LiteralPath $index).Hash -ceq $indexBefore) 'soft索引字节保持'
    Assert-Rollback ([IO.File]::ReadAllText((Join-Path $s.Root 'a.txt')) -ceq 'unstaged') 'soft工作树内容保持'
    $softNow=New-Context $s.Root
    Expect-Throw { & $module {param($C,$Commit) Invoke-JobsRollbackSoft $C $Commit 'descendant'} $softNow $s.Head } 'soft拒绝非祖先目标'
    $h=New-Fixture 'hard'
    [IO.File]::WriteAllText((Join-Path $h.Root 'a.txt'),'dirty')
    $ctx=New-Context $h.Root
    & $module { function script:Read-JobsRollbackInput { param($Prompt) return '' } }
    & $module { param($C,$Commit) Invoke-JobsRollbackHard $C $Commit 'base' } $ctx $h.Base
    Assert-Rollback ((Run-Git $h.Root @('rev-parse','HEAD')) -ceq $h.Head) 'hard回车取消不移动HEAD'
    Assert-Rollback ([IO.File]::ReadAllText((Join-Path $h.Root 'a.txt')) -ceq 'dirty') 'hard取消保留修改'
    & $module { function script:Read-JobsRollbackInput { param($Prompt) return 'yes' } }
    & $module { param($C,$Commit) Invoke-JobsRollbackHard $C $Commit 'base' } $ctx $h.Base
    Assert-Rollback ((Run-Git $h.Root @('rev-parse','HEAD')) -ceq $h.Head) 'hard小写yes取消'
    & $module { param($Path) $script:mutatePath=$Path; function script:Read-JobsRollbackInput { param($Prompt) [IO.File]::WriteAllText($script:mutatePath,'concurrent'); return 'YES' } } (Join-Path $h.Root 'a.txt')
    Expect-Throw { & $module { param($C,$Commit) Invoke-JobsRollbackHard $C $Commit 'base' } $ctx $h.Base } 'hard确认期间工作树变化停止'
    Assert-Rollback ((Run-Git $h.Root @('rev-parse','HEAD')) -ceq $h.Head) '变化停止保留HEAD'
    & $module { function script:Read-JobsRollbackInput { param($Prompt) return 'YES' } }
    & $module { param($C,$Commit) Invoke-JobsRollbackHard $C $Commit 'base' } $ctx $h.Base
    Assert-Rollback ((Run-Git $h.Root @('rev-parse','HEAD')) -ceq $h.Base) 'hard YES移动HEAD'
    Assert-Rollback ([IO.File]::ReadAllText((Join-Path $h.Root 'a.txt')) -ceq 'base') 'hard检出固定提交'
    $r=New-Fixture 'ready'
    $ctx=New-Context $r.Root
    [IO.File]::WriteAllText((Join-Path $r.Root '.git/MERGE_HEAD'),$r.Base)
    Expect-Throw { & $module { param($C,$Commit) Invoke-JobsRollbackSoft $C $Commit 'base' } $ctx $r.Base } '未完成merge停止'
    [IO.File]::Delete((Join-Path $r.Root '.git/MERGE_HEAD'))
    [void](Run-Git $r.Root @('checkout','--detach'))
    $detached=New-Context $r.Root
    Assert-Rollback ($detached.Branch -ceq '') '游离HEAD记录空身份'
    Expect-Throw { & $module { param($C) Get-JobsRollbackRemoteTarget $C } $detached } '游离HEAD远端模式停止'
    & $module { param($C,$Commit) Invoke-JobsRollbackSoft $C $Commit 'detached base' } $detached $r.Base
    Assert-Rollback ((Run-Git $r.Root @('rev-parse','HEAD')) -ceq $r.Base) '游离HEAD显式历史soft仍保持祖先限制'
    $r=New-Fixture 'branch-change'
    $ctx=New-Context $r.Root
    [void](Run-Git $r.Root @('checkout','-b','other'))
    Expect-Throw { & $module { param($C,$Commit) Invoke-JobsRollbackSoft $C $Commit 'base' } $ctx $r.Base } '选择期间切分支停止'
    $e=New-Fixture 'environment'
    $envBefore=[Environment]::GetEnvironmentVariable('GIT_DIR')
    try {
        $env:GIT_DIR=Join-Path $h.Root '.git'
        $ctx=New-Context $e.Root
        Assert-Rollback ($ctx.Head -ceq $e.Head) '子进程清理GIT_DIR覆盖'
        Assert-Rollback ($env:GIT_DIR -ceq (Join-Path $h.Root '.git')) '父环境GIT_DIR保持'
    } finally {
        if ([string]::IsNullOrEmpty($envBefore)) { Remove-Item Env:GIT_DIR -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable('GIT_DIR',$envBefore) }
    }
    # 全局 recurse=true 也不能让当前父仓 hard 影响子仓工作树。
    [void](Run-Git $f.Root @('add','.gitmodules','module'))
    [void](Run-Git $f.Root @('commit','-m','record submodule'))
    [void](Run-Git $f.Root @('config','submodule.recurse','true'))
    [void](Run-Git $sub @('checkout','--detach',$inner.Base))
    [IO.File]::WriteAllText((Join-Path $sub 'a.txt'),'child dirty')
    $parentContext=New-Context $f.Root
    $childHead=Run-Git $sub @('rev-parse','HEAD')
    & $module {param($C) Invoke-JobsRollbackHard $C $C.Head 'same parent'} $parentContext
    Assert-Rollback ((Run-Git $sub @('rev-parse','HEAD')) -ceq $childHead) 'hard不递归移动子仓HEAD'
    Assert-Rollback ([IO.File]::ReadAllText((Join-Path $sub 'a.txt')) -ceq 'child dirty') 'hard不递归丢弃子仓修改'
    $m=New-Fixture 'multi-remote'
    [void](Run-Git $m.Root @('remote','add','origin','https://example.invalid/jobs'))
    [void](Run-Git $m.Root @('remote','add','gitee','https://example.invalid/jobs-mirror'))
    [void](Run-Git $m.Root @('update-ref','refs/remotes/origin/main',$m.Base))
    [void](Run-Git $m.Root @('update-ref','refs/remotes/gitee/main',$m.Head))
    $ctx=New-Context $m.Root
    & $module {
        $script:chosen=0
        function script:Select-JobsRollbackEntry {
            param($Title,$Entries,[switch]$Back)
            $script:chosen++
            if ($Entries.Count -ne 2 -or -not $Back) { throw 'Remote selector lost candidates or back.' }
            return @{Action='Selected';Value=($Entries | Where-Object { $_ -like 'refs/remotes/origin/*' })}
        }
    }
    $chosen=& $module {param($C) Get-JobsRollbackRemoteTarget $C} $ctx
    Assert-Rollback ($chosen.Value -ceq $m.Base -and $chosen.Description -ceq 'refs/remotes/origin/main') '多远端目标是明确选定本地快照'
    & $module {
        param($Git,$Directory,$Commit)
        $script:changeGit=$Git;$script:changeDirectory=$Directory;$script:changeCommit=$Commit
        function script:Select-JobsRollbackEntry {
            param($Title,$Entries,[switch]$Back)
            $entry=@($Entries | Where-Object { $_ -like 'refs/remotes/origin/*' })[0]
            [void](Invoke-JobsRollbackGit $script:changeGit $script:changeDirectory @('update-ref','refs/remotes/origin/main',$script:changeCommit))
            return @{Action='Selected';Value=$entry}
        }
    } $git $m.Root $m.Head
    Expect-Throw { & $module {param($C) Get-JobsRollbackRemoteTarget $C} $ctx } '多远端选择期间快照变化停止'
    & $module {
        function script:Select-JobsRollbackEntry {param($Title,$Entries,[switch]$Back) return @{Action='Back';Value=''} }
    }
    $back=& $module {param($C) Get-JobsRollbackRemoteTarget $C} $ctx
    Assert-Rollback ($back.Action -ceq 'Back') '远端目标层左键返回模式层'
    # 模式到目标的返回用真实业务调度循环验证，不在返回后隐式执行 reset。
    & $module {
        $script:step=0;$script:resets=0
        function script:Select-JobsRollbackEntry {
            param($Title,$Entries,[switch]$Back)
            $script:step++
            if ($script:step -eq 1) { return @{Action='Selected';Value='选择提交 hard 回退'} }
            if ($script:step -eq 2) { if(-not $Back){throw 'Missing back layer'}; return @{Action='Back';Value=''} }
            return @{Action='Cancel';Value=''}
        }
        function script:Invoke-JobsRollbackHard {param($Context,$Commit,$Description) $script:resets++}
        Invoke-JobsRollbackMenu $args[0]
        if($script:step -ne 3 -or $script:resets -ne 0){throw 'Back/cancel dispatched reset.'}
    } $ctx
    Assert-Rollback $true '目标返回模式再取消无业务动作'
    foreach($case in @(
        @{Lines=@('left');Code=1;Back=$true;Expected='Back'},
        @{Lines=@('left','x');Code=0;Back=$true;Expected='Back'},
        @{Lines=@('','x');Code=0;Back=$true;Expected='Selected'},
        @{Lines=@('x');Code=0;Back=$false;Expected='Selected'},
        @{Lines=@();Code=130;Back=$true;Expected='Cancel'},
        @{Lines=@();Code=1;Back=$false;Expected='Cancel'})) {
        $choice=& $module {param($Case) ConvertFrom-JobsRollbackSelection -Lines $Case.Lines -ExitCode $Case.Code -Entries @('x') -Back:$Case.Back} $case
        Assert-Rollback ($choice.Action -ceq $case.Expected) ('fzf结果解析 '+$case.Expected)
    }
    Expect-Throw { & $module { ConvertFrom-JobsRollbackSelection -Lines @('evil') -ExitCode 0 -Entries @('x') } } '选择器列表外结果停止'
    Expect-Throw { & $module { ConvertFrom-JobsRollbackSelection -Lines @() -ExitCode 2 -Entries @('x') } } '选择器异常失败传播'
    if ($FzfProbeExecutable) {
        & $module {
            param($Executable)
            $script:encodingProbe=$Executable
            function script:Find-JobsExecutable { param($Name,$Candidates) return $script:encodingProbe }
            # 恢复真实生产选择函数，前面的菜单调度夹具曾临时替换它。
            $parseTokens=$null;$parseErrors=$null
            $ast=[Management.Automation.Language.Parser]::ParseFile($ExecutionContext.SessionState.Module.Path,[ref]$parseTokens,[ref]$parseErrors)
            if($parseErrors.Count){throw 'Production selector parse failed.'}
            $definition=$ast.Find({param($Node) $Node -is [Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -ceq 'Select-JobsRollbackEntry'},$false)
            Set-Item Function:script:Select-JobsRollbackEntry ([scriptblock]::Create($definition.Body.Extent.Text.Substring(1,$definition.Body.Extent.Text.Length-2)))
            $outputBefore=$OutputEncoding
            $consoleBefore=[Console]::OutputEncoding
            $inputBefore=[Console]::InputEncoding
            $keys=@('FZF_DEFAULT_OPTS','FZF_DEFAULT_OPTS_FILE','JOBS_FZF_PROBE_MODE')
            $environmentBefore=[Environment]::GetEnvironmentVariables('Process')
            if([Environment]::OSVersion.Platform-eq[PlatformID]::Win32NT-and-not('Jobs.RollbackEnvironmentProbe'-as[type])){
                Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; namespace Jobs { public static class RollbackEnvironmentProbe { [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] public static extern bool SetEnvironmentVariable(string name, string value); } }'
            }
            # Windows 的空环境值需要原生 API；夹具也必须区分空值和未设置。
            function Set-RollbackProbeEnvironment {
                param([string]$Key,[bool]$Exists,[string]$Value)
                if(-not$Exists){[Environment]::SetEnvironmentVariable($Key,[NullString]::Value,'Process')}
                elseif($Value-ceq''-and[Environment]::OSVersion.Platform-eq[PlatformID]::Win32NT){
                    if(-not[Jobs.RollbackEnvironmentProbe]::SetEnvironmentVariable($Key,'')){throw 'Cannot prepare empty probe environment.'}
                }else{[Environment]::SetEnvironmentVariable($Key,$Value,'Process')}
            }
            try {
                $script:OutputEncoding=[Text.Encoding]::ASCII
                [Console]::OutputEncoding=[Text.Encoding]::ASCII
                [Console]::InputEncoding=New-Object Text.UTF8Encoding($true)
                foreach($environmentKind in @('absent','empty','value')){
                    foreach($key in $keys){Set-RollbackProbeEnvironment $key ($environmentKind-cne'absent') $(if($environmentKind-ceq'value'){'parent-value'}else{''})}
                    foreach($case in @(
                        @{Mode='select';Back=$false;Action='Selected'},@{Mode='select';Back=$true;Action='Selected'},
                        @{Mode='back';Back=$true;Action='Back'},@{Mode='cancel';Back=$true;Action='Cancel'},
                        @{Mode='empty';Back=$false;Action='Cancel'},@{Mode='early-cancel';Back=$false;Action='Cancel'},
                        @{Mode='early-select';Back=$true;Action='Selected'},
                        @{Mode='early-select';Back=$false;Action='Selected'},@{Mode='early-back-zero';Back=$true;Action='Back'},
                        @{Mode='early-back';Back=$true;Action='Back'},@{Mode='failure';Back=$false;Error='退出码：2'},
                        @{Mode='outside';Back=$false;Error='列表外内容'},@{Mode='outside';Back=$true;Error='列表外内容'},
                        @{Mode='invalid-utf8';Back=$false;Error='InvalidUtf8'})){
                        [Environment]::SetEnvironmentVariable('JOBS_FZF_PROBE_MODE',$case.Mode,'Process')
                        $expectedEnvironment=[Environment]::GetEnvironmentVariables('Process')
                        $entries=@('选择提交 soft 回退','hard 回退到 upstream')
                        if($case.Mode.StartsWith('early-')){$entries+=('x'*1048576)}
                        $failure=$null;$result=$null
                        try{$result=Select-JobsRollbackEntry '中文编码' $entries -Back:$case.Back}catch{$failure=$_}
                        if($case.ContainsKey('Error')){
                            if($null-eq$failure){throw ('Native probe should reject '+$case.Mode)}
                            if($case.Error-ceq'InvalidUtf8'){
                                if($failure.Exception.GetBaseException()-isnot[Text.DecoderFallbackException]){throw $failure}
                            }elseif(-not$failure.Exception.Message.Contains($case.Error)){throw $failure}
                        }else{
                            if($null-ne$failure){throw $failure}
                            if($result.Action-cne$case.Action){throw ('Native probe wrong action: '+$case.Mode)}
                            if($case.Action-ceq'Selected'-and$result.Value-cne$entries[0]){throw 'Native pipe corrupted Chinese mode.'}
                        }
                        if($OutputEncoding.CodePage-ne20127-or[Console]::OutputEncoding.CodePage-ne20127){throw 'Original ASCII encoding changed.'}
                        if([Console]::InputEncoding.CodePage-ne65001-or[Console]::InputEncoding.GetPreamble().Length-ne3){throw 'Original UTF8 BOM input encoding not restored.'}
                        $actualEnvironment=[Environment]::GetEnvironmentVariables('Process')
                        foreach($key in $keys){
                            if($actualEnvironment.Contains($key)-ne$expectedEnvironment.Contains($key)-or$actualEnvironment[$key]-cne$expectedEnvironment[$key]){throw ('Parent environment changed: '+$key)}
                        }
                    }
                }
            } finally {
                $script:OutputEncoding=$outputBefore;[Console]::OutputEncoding=$consoleBefore;[Console]::InputEncoding=$inputBefore
                foreach($key in $keys){Set-RollbackProbeEnvironment $key $environmentBefore.Contains($key) $environmentBefore[$key]}
            }
        } ([IO.Path]::GetFullPath($FzfProbeExecutable))
        Assert-Rollback $true '42组原生字节管道覆盖中文、返回取消、早退断管、失败与非法输出并保留父环境及编码'
    } else { Write-Host 'SKIP optional native encoding shim: compile GitRollbackFzfProbe.cpp and pass -FzfProbeExecutable.' }
    Write-Host ('PASS GitRollback: ' + $script:assertions + ' assertions; temporary repositories only.')
} finally {
    Remove-Module $module
    [Environment]::SetEnvironmentVariable('LOCALAPPDATA',$savedLocal)
    [Environment]::SetEnvironmentVariable('GIT_CONFIG_GLOBAL',$savedGlobal)
    [Environment]::SetEnvironmentVariable('GIT_CONFIG_NOSYSTEM',$savedSystem)
    Remove-Item -LiteralPath $temp -Recurse -Force
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

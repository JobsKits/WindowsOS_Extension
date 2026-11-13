# Worker.Tests.ps1
# WindowsOS@Extension
# Created by Jobs on 2026年10月18日，星期日.

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
$project = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $project 'JobsCodeGraphUpdater/Scripts/Common.psm1') -Force -DisableNameChecking
$worker = Join-Path $project 'JobsCodeGraphUpdater/Scripts/Action.psm1'
foreach ($name in @('JobsFlutterPubGet', 'JobsCodeGraphUpdater', 'JobsGitEmptyCommitPusher')) {
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $project ($name + '/Scripts/Action.psm1')), [ref]$tokens, [ref]$errors)
    if ($errors) { throw ($errors | Out-String) }
    foreach ($definition in $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
        if ($definition.Name -ne 'Invoke-JobsFeature') { . ([scriptblock]::Create($definition.Extent.Text)) }
    }
}

$script:assertions = 0
function Assert-True {
    param([bool]$Condition, [string]$Because)
    $script:assertions++
    if (-not $Condition) { throw "断言失败：$Because" }
}
function Assert-Throws {
    param([scriptblock]$Action, [string]$Because)
    $script:assertions++
    $thrown = $false
    try { & $Action | Out-Null } catch { $thrown = $true }
    if (-not $thrown) { throw "应阻止该操作：$Because" }
}
function Write-JobsLog { param([string]$Message) }
function Get-JobsInstallRoot { return $script:root }
function Invoke-TestGit {
    param([string[]]$Arguments)
    $result = Invoke-JobsProcess -FilePath $script:git -Arguments $Arguments -WorkingDirectory $script:repository
    if ($result.ExitCode -ne 0) { throw "临时 Git 准备失败：$($result.StdErr)" }
    return $result.StdOut.Trim()
}

$temporary = [IO.Path]::GetTempPath()
if ([IO.Directory]::Exists('/private/tmp')) { $temporary = '/private/tmp' }
$script:root = Join-Path $temporary ("JobsWorker [中文] '& %PATH% ! " + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($script:root)
try {
    $bytes = [IO.File]::ReadAllBytes($worker)
    Assert-True ($bytes.Length -gt 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) '独立业务模块中文源码采用 UTF-8 BOM'
    Assert-True (Test-JobsSamePath $script:root ($script:root + [IO.Path]::DirectorySeparatorChar)) '目录末尾分隔符归一'
    Assert-True (-not (Test-JobsSamePath 'relative-path' $script:root)) 'JSON 项目身份必须为绝对路径'
    Assert-True (-not (Test-JobsSamePath '' $script:root)) 'JSON 项目身份不能为空'
    Assert-True ((Assert-JobsOrdinaryDirectory $script:root) -eq $script:root) '特殊字符原样作为路径处理'
    Assert-Throws { Assert-JobsOrdinaryDirectory 'relative-path' } '目标必须绝对目录'
    Assert-Throws { Invoke-JobsFlutterProcess 'C:\sdk"\flutter.bat' @('--version') $script:root } '拒绝非法双引号工具路径'
    Assert-Throws { Invoke-JobsFlutterProcess 'C:\flutter\flutter.bat' @('pub', 'get & whoami') $script:root } 'Flutter 仅接受固定命令参数'
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        $fakeFlutter = Join-Path $script:root 'flutter.bat'
        $capturedDirectory = Join-Path $script:root 'flutter-working-directory.txt'
        [IO.File]::WriteAllText($fakeFlutter, "@echo off`r`n> `"%JOBS_FLUTTER_TEST_OUTPUT%`" <nul set /p `"=%CD%`"`r`nexit /b 0`r`n", [Text.Encoding]::ASCII)
        $savedOutput = [Environment]::GetEnvironmentVariable('JOBS_FLUTTER_TEST_OUTPUT', 'Process')
        try {
            $env:JOBS_FLUTTER_TEST_OUTPUT = $capturedDirectory
            Invoke-JobsFlutterProcess $fakeFlutter @('--version') $script:root 10
            Assert-True ([IO.File]::ReadAllText($capturedDirectory) -eq $script:root) 'cmd 工具和工作目录中的中文、百分号、叹号、单引号、& 不展开或注入'
        } finally { [Environment]::SetEnvironmentVariable('JOBS_FLUTTER_TEST_OUTPUT', $savedOutput, 'Process') }
    }

    $package = Join-Path $script:root 'fake-package'
    [void][IO.Directory]::CreateDirectory($package)
    @{ name = '@colbymchenry/codegraph'; version = '1.6.2'; bin = @{ codegraph = '../outside.js' } } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $package 'package.json') -Encoding UTF8
    Assert-Throws { Get-JobsPackageEntry $package '@colbymchenry/codegraph' 'codegraph' } 'npm bin 不得越过包目录'
    @{ name = '@colbymchenry/codegraph'; version = '99.0.0'; bin = @{ codegraph = 'entry.js' } } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $package 'package.json') -Encoding UTF8
    Assert-True ($null -eq (Get-JobsPackageEntry $package '@colbymchenry/codegraph' 'codegraph')) '未知 CodeGraph 版本不可执行'

    $prefix = Join-Path $script:root 'tools-codegraph'
    $mainPackage = Join-Path $prefix 'node_modules/@colbymchenry/codegraph'
    $nestedBundle = Join-Path $mainPackage 'node_modules/@colbymchenry/codegraph-win32-x64'
    [void][IO.Directory]::CreateDirectory((Join-Path $nestedBundle 'lib/dist/bin'))
    @{ name = '@colbymchenry/codegraph'; version = '1.6.2'; bin = @{ codegraph = 'npm-shim.js' } } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $mainPackage 'package.json') -Encoding UTF8
    @{ name = '@colbymchenry/codegraph-win32-x64'; version = '1.6.2' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $nestedBundle 'package.json') -Encoding UTF8
    [IO.File]::WriteAllText((Join-Path $mainPackage 'npm-shim.js'), '')
    [IO.File]::WriteAllText((Join-Path $nestedBundle 'node.exe'), '')
    [IO.File]::WriteAllText((Join-Path $nestedBundle 'lib/dist/bin/codegraph.js'), '')
    $script:CodeGraphPlatform = 'win32-x64'
    $resolved = Get-JobsCodeGraphCommand 'unused-node' $prefix
    Assert-True ($resolved.SchemaNode -eq (Join-Path $nestedBundle 'node.exe')) '复用 npm global 常见的包内嵌套 platform runtime'
    $siblingBundle = Join-Path ([IO.Path]::GetDirectoryName($mainPackage)) 'codegraph-win32-x64'
    Move-Item -LiteralPath $nestedBundle -Destination $siblingBundle
    $resolved = Get-JobsCodeGraphCommand 'unused-node' $prefix
    Assert-True ($resolved.SchemaNode -eq (Join-Path $siblingBundle 'node.exe')) '复用本地 npm prefix 的同级 platform runtime'

    $graphFunctions = @{}
    foreach ($name in @('Assert-JobsCodeGraphHost', 'Get-JobsCodeGraphNodeTools', 'Get-JobsCodeGraphWinget',
        'Get-JobsCodeGraphCommand', 'Assert-JobsCodeGraphRuntime', 'Invoke-JobsCheckedProcess',
        'Repair-JobsCodeGraphNodeTools', 'Update-JobsCodeGraphSessionPath', 'Get-JobsGraphStatus',
        'Find-JobsExecutable', 'Get-JobsPackageEntry', 'Read-Host')) {
        $definition = Get-Command $name
        $graphFunctions[$name] = if ($definition.CommandType -eq 'Function') { $definition.ScriptBlock } else { $null }
    }
    $graphEnvironment = @{}
    foreach ($name in @('CODEGRAPH_DIR', 'CODEGRAPH_TELEMETRY', 'DO_NOT_TRACK', 'CODEGRAPH_NO_DOWNLOAD',
        'CODEGRAPH_NO_WATCH', 'CODEGRAPH_NO_DAEMON', 'NO_COLOR', 'FORCE_COLOR', 'NODE_OPTIONS', 'NODE_PATH',
        'npm_config_global', 'npm_config_omit', 'npm_config_include', 'npm_config_platform', 'npm_config_arch')) {
        $graphEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
    try {
        function Reset-GraphFixture {
            $script:healthLayers = @()
            $script:graphCalls = @()
            $script:resolveCount = 0
            $script:runtimeChecks = 0
            $script:nodeRepairs = 0
            $script:statusChecks = 0
            $script:runtimeFailure = ''
            $script:repairFailure = $false
            $script:graphConfirm = ''
            $script:availableNodeVersions = "Version`n-------`n26.1.0`n24.9.0`n24.18.0`n22.0.0"
            $script:healthNodeVersion = 'v24.18.0'
            $script:healthNodeDigest = '2f17a0f8d518e491c5a0c490b2c1991828dd87d173994ba40996e1da59d4e368'
            $script:healthNpmRoot = $script:root
            $script:existingGraphCommand = @{ Executable = 'bundled-node.exe'; Prefix = @('--liftoff-only', 'codegraph.js'); SchemaNode = 'bundled-node.exe' }
            $script:nodeTools = $null
        }
        function Assert-JobsCodeGraphHost { $script:healthLayers += 'PowerShell/.NET'; $script:CodeGraphPlatform = 'win32-x64' }
        function Get-JobsCodeGraphNodeTools { param($Directory) $script:healthLayers += 'Node/npm'; return $script:nodeTools }
        function Get-JobsCodeGraphWinget { param($Directory) $script:healthLayers += 'WinGet'; return $null }
        function Get-JobsCodeGraphCommand {
            param($Node, $Prefix)
            $script:resolveCount++
            if ($script:resolveCount -eq 1) { return $script:existingGraphCommand }
            return @{ Executable = 'repaired-node.exe'; Prefix = @('--liftoff-only', 'repaired-codegraph.js'); SchemaNode = 'repaired-node.exe' }
        }
        function Assert-JobsCodeGraphRuntime {
            param($Command, $Directory)
            $script:runtimeChecks++
            if ($script:runtimeFailure -eq 'always' -or ($script:runtimeFailure -eq 'first' -and $script:runtimeChecks -eq 1)) { throw 'simulated unhealthy runtime' }
        }
        function Invoke-JobsCheckedProcess {
            param($Executable, $Arguments, $Directory, $TimeoutSeconds = 30, [switch]$Quiet)
            $script:graphCalls += [pscustomobject]@{ Executable = $Executable; Arguments = $Arguments; Directory = $Directory }
            $output = ''
            if ($Arguments[0] -eq 'show' -and '--versions' -in $Arguments) { $output = $script:availableNodeVersions }
            if ($Arguments[0] -eq '--version') { $output = $script:healthNodeVersion }
            if ($Arguments[0] -eq '-e') { $output = $script:healthNodeDigest }
            if ($Arguments[0] -eq 'npm.js') {
                if ($Arguments[1] -eq '--version') { $output = '11.0.0' }
                if ($Arguments[1] -eq 'config') { $output = $script:root }
                if ($Arguments[1] -eq 'root') { $output = $script:healthNpmRoot }
            }
            return [pscustomobject]@{ ExitCode = 0; StdOut = $output; StdErr = '' }
        }
        function Repair-JobsCodeGraphNodeTools {
            param($Winget, $Directory)
            $script:nodeRepairs++
            if ($script:repairFailure) { throw 'simulated node repair failure' }
            return @{ Node = 'node.exe'; NpmEntry = 'npm.js' }
        }
        function Update-JobsCodeGraphSessionPath { }
        function Get-JobsGraphStatus { param($Command, $Directory, [switch]$Complete) $script:statusChecks++ }
        function Read-Host { param($Prompt) return $script:graphConfirm }

        Reset-GraphFixture
        Invoke-JobsCodeGraphAction $script:root 6>$null
        Assert-True (($script:healthLayers -join ',') -eq 'PowerShell/.NET,Node/npm,WinGet') '健康 CLI 分支也体检每一层已有安装上游'
        Assert-True ($script:nodeRepairs -eq 0 -and $script:graphCalls.Count -eq 1) '健康随包运行时不强装缺失 Node/npm 或 WinGet'
        Assert-True ($script:graphCalls[0].Arguments[-3] -eq 'init' -and $script:graphCalls[0].Arguments[-1] -eq $script:root) '首次建图精确使用 init --yes 及目标绝对路径'

        Reset-GraphFixture
        $script:existingGraphCommand = $null
        $script:nodeTools = @{ Node = 'node.exe'; NpmEntry = 'npm.js' }
        Invoke-JobsCodeGraphAction $script:root 6>$null
        Assert-True ($script:nodeRepairs -eq 0 -and $script:runtimeChecks -eq 1 -and $script:graphCalls.Count -eq 3) '缺 CLI 复用健康上游，只安装一次并复检'
        Assert-True ($script:graphCalls[0].Arguments[1] -eq 'ping' -and '--registry=https://registry.npmjs.org/' -in $script:graphCalls[0].Arguments) '安装前核验官方 npm 源连通性'
        Assert-True ('--ignore-scripts' -in $script:graphCalls[1].Arguments -and '@colbymchenry/codegraph@1.6.2' -in $script:graphCalls[1].Arguments) '私有安装锁定官方包版本并禁止生命周期脚本'
        Assert-True ('--global=false' -in $script:graphCalls[1].Arguments -and $env:npm_config_arch -eq 'x64' -and $env:npm_config_platform -eq 'win32' -and $env:npm_config_include -eq 'optional') '私有安装固定范围与平台，不继承漏装 optional 的配置'
        Assert-True ('--os=win32' -in $script:graphCalls[1].Arguments -and '--cpu=x64' -in $script:graphCalls[1].Arguments -and $script:graphCalls[1].Directory -ne $script:root) 'npm 在私有目录运行并显式固定 optional 平台，隔离项目 npmrc'

        Reset-GraphFixture
        $script:runtimeFailure = 'first'
        Invoke-JobsCodeGraphAction $script:root 6>$null
        Assert-True ($script:nodeRepairs -eq 1 -and $script:runtimeChecks -eq 2 -and $script:resolveCount -eq 2) '损坏 CLI 向上修复必需层后仅修复一次并复检'

        Reset-GraphFixture
        $script:existingGraphCommand = $null
        $script:repairFailure = $true
        Assert-Throws { Invoke-JobsCodeGraphAction $script:root 6>$null } '上游修复失败立即停止'
        Assert-True ($script:graphCalls.Count -eq 0 -and $script:nodeRepairs -eq 1) '上游失败不执行 npm 安装或目标建图'

        Reset-GraphFixture
        $script:runtimeFailure = 'always'
        Assert-Throws { Invoke-JobsCodeGraphAction $script:root 6>$null } 'CLI 修复后二次体检仍失败时停止'
        Assert-True ($script:runtimeChecks -eq 2 -and $script:graphCalls.Count -eq 2) 'CLI 只修复一次且失败不建图'

        Reset-GraphFixture
        $existingGraph = Join-Path $script:root '.codegraph'
        [void][IO.Directory]::CreateDirectory($existingGraph)
        try {
            Invoke-JobsCodeGraphAction $script:root 6>$null
            Assert-True ($script:graphCalls[0].Arguments[-2] -eq 'sync' -and $script:graphCalls[0].Arguments[-1] -eq $script:root) '已有地图同步精确目标'
            Assert-True ($script:statusChecks -eq 2) '已有地图写前核对身份，写后核对完成状态'
        } finally { [IO.Directory]::Delete($existingGraph) }

        Reset-GraphFixture
        $script:nodeTools = @{ Node = 'node.exe'; NpmEntry = 'npm.js' }
        [void](& $graphFunctions['Repair-JobsCodeGraphNodeTools'] 'winget.exe' $script:root 6>$null)
        $installArguments = $script:graphCalls[2].Arguments
        $versionPosition = [Array]::IndexOf($installArguments, '--version')
        Assert-True ($installArguments[0] -eq 'install' -and $installArguments[$versionPosition + 1] -eq '24.18.0' -and '--force' -in $installArguments) 'WinGet 只强制重跑官方源最高精确 24.x，忽略26.x且不按字典序误选24.9'

        Reset-GraphFixture
        $script:availableNodeVersions = "Version`n26.1.0"
        Assert-Throws { & $graphFunctions['Repair-JobsCodeGraphNodeTools'] 'winget.exe' $script:root 6>$null } '官方源没有兼容24.x时停止'
        Assert-True ($script:graphCalls.Count -eq 1) '无兼容版本不调用安装器'

        Reset-GraphFixture
        $script:graphConfirm = $null
        Assert-Throws { & $graphFunctions['Repair-JobsCodeGraphNodeTools'] 'winget.exe' $script:root 6>$null } '非交互EOF不默认为安装确认'
        Assert-True ($script:graphCalls.Count -eq 2) '无确认时仅查询来源而不安装'

        function Find-JobsExecutable { param($Name, $Candidates) return (Join-Path $script:root 'node.exe') }
        function Get-JobsPackageEntry { param($PackageDirectory, $PackageName, $CommandName) return 'npm.js' }
        Reset-GraphFixture
        Assert-True ($null -ne (& $graphFunctions['Get-JobsCodeGraphNodeTools'] $script:root 6>$null)) 'Node24标准库、npm入口与配置体检通过'
        $script:healthNodeVersion = 'v22.20.0'
        Assert-True ($null -ne (& $graphFunctions['Get-JobsCodeGraphNodeTools'] $script:root 6>$null)) '健康Node22符合官方兼容范围并复用'
        $script:healthNodeVersion = 'v25.0.0'
        Assert-True ($null -eq (& $graphFunctions['Get-JobsCodeGraphNodeTools'] $script:root 6>$null)) 'Node25不能误判为兼容安装工具链'
        $script:healthNodeVersion = 'v24.18.0'
        $script:healthNodeDigest = 'wrong'
        Assert-True ($null -eq (& $graphFunctions['Get-JobsCodeGraphNodeTools'] $script:root 6>$null)) 'Node标准库退出0但摘要结果错误仍不健康'
        $script:healthNodeDigest = '2f17a0f8d518e491c5a0c490b2c1991828dd87d173994ba40996e1da59d4e368'
        $script:healthNpmRoot = 'relative-root'
        Assert-True ($null -eq (& $graphFunctions['Get-JobsCodeGraphNodeTools'] $script:root 6>$null)) 'npm全局包配置异常时阻止安装路径'
    } finally {
        foreach ($name in $graphFunctions.Keys) {
            if ($graphFunctions[$name]) { Set-Item -LiteralPath ('Function:' + $name) -Value $graphFunctions[$name] }
            else { Remove-Item -LiteralPath ('Function:' + $name) -ErrorAction SilentlyContinue }
        }
        foreach ($name in $graphEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $graphEnvironment[$name], 'Process') }
        Remove-Item -LiteralPath Function:Reset-GraphFixture -ErrorAction SilentlyContinue
    }

    $gitCommand = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($gitCommand) {
        $script:git = $gitCommand.Source
        $script:repository = Join-Path $script:root 'repository'
        [void][IO.Directory]::CreateDirectory($script:repository)
        [void](Invoke-TestGit @('init', '-b', 'main'))
        [void](Invoke-TestGit @('config', 'user.name', 'Jobs Worker Tests'))
        [void](Invoke-TestGit @('config', 'user.email', 'worker-tests@example.invalid'))
        [void](Invoke-TestGit @('config', 'commit.gpgSign', 'false'))
        [void](Invoke-TestGit @('-c', 'core.hooksPath=', 'commit', '--allow-empty', '-m', 'seed'))
        Assert-Throws { Get-JobsGitPushPlan $script:git $script:repository } '没有 upstream 不推送'
        [void](Invoke-TestGit @('remote', 'add', 'origin', 'https://example.invalid/repository.git'))
        [void](Invoke-TestGit @('config', 'branch.main.remote', 'origin'))
        [void](Invoke-TestGit @('config', 'branch.main.merge', 'refs/heads/main'))
        [void](Invoke-TestGit @('update-ref', 'refs/remotes/origin/main', 'HEAD'))
        $plan = Get-JobsGitPushPlan $script:git $script:repository
        Assert-True ($plan.Branch -eq 'main' -and $plan.Remote -eq 'origin' -and $plan.Ref -eq 'refs/heads/main') '只映射当前已有 upstream 分支'
        [void](Assert-JobsGitIndexEmpty $script:git $script:repository)
        [IO.File]::WriteAllText((Join-Path $script:repository 'staged.txt'), 'preserve')
        [void](Invoke-TestGit @('add', '--', 'staged.txt'))
        Assert-Throws { Assert-JobsGitIndexEmpty $script:git $script:repository } '暂存区非空时阻止空白提交'
        Assert-True ((Invoke-TestGit @('diff', '--cached', '--name-only')) -eq 'staged.txt') '检查不改变暂存内容'
        [void](Invoke-TestGit @('config', 'branch.main.pushRemote', 'other'))
        Assert-Throws { Get-JobsGitPushPlan $script:git $script:repository } 'pushRemote 冲突时停止'
        [void](Invoke-TestGit @('config', '--unset', 'branch.main.pushRemote'))
        [void](Invoke-TestGit @('config', 'remote.origin.mirror', 'true'))
        Assert-Throws { Get-JobsGitPushPlan $script:git $script:repository } 'mirror 配置不能进入推送'
        [void](Invoke-TestGit @('config', '--unset', 'remote.origin.mirror'))
        [void](Invoke-TestGit @('config', '--add', 'remote.origin.pushurl', 'https://example.invalid/first.git'))
        [void](Invoke-TestGit @('config', '--add', 'remote.origin.pushurl', 'https://example.invalid/second.git'))
        Assert-Throws { Get-JobsGitPushPlan $script:git $script:repository } '多个 pushurl 时停止'
        [void](Invoke-TestGit @('config', '--unset-all', 'remote.origin.pushurl'))
        [void](Invoke-TestGit @('checkout', '--detach'))
        Assert-Throws { Get-JobsGitPushPlan $script:git $script:repository } '游离 HEAD 时停止'
    } else { Write-Host '跳过临时 Git 测试：缺少 git。' }

    $node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($node) {
        $sqlite = Invoke-JobsProcess -FilePath $node.Source -Arguments @('-e', 'require("node:sqlite")') -WorkingDirectory $script:root
        if ($sqlite.ExitCode -eq 0) {
            $target = Join-Path $script:root 'graph-target'
            $graph = Join-Path $target '.codegraph'
            [void][IO.Directory]::CreateDirectory($graph)
            $database = Join-Path $graph 'codegraph.db'
            $create = 'const {DatabaseSync}=require("node:sqlite");const db=new DatabaseSync(process.argv[1]);db.exec("CREATE TABLE nodes(id TEXT)");db.close();'
            [void](Invoke-JobsCheckedProcess $node.Source @('-e', $create, $database) $script:root -Quiet)
            $fakeCli = Join-Path $script:root 'status.js'
            $status = @{ initialized = $true; version = '1.6.2'; projectPath = $target; indexPath = $graph; lastIndexed = '2026-10-18T00:00:00.000Z'; pendingChanges = @{ added = 0; modified = 0; removed = 0 }; index = @{ state = 'complete'; pendingRefs = 0 } }
            [IO.File]::WriteAllText($fakeCli, 'console.log(JSON.stringify(' + ($status | ConvertTo-Json -Depth 5 -Compress) + '));')
            $command = @{ Executable = $node.Source; Prefix = @($fakeCli); SchemaNode = $node.Source }
            $before = (Get-FileHash -LiteralPath $database -Algorithm SHA256).Hash
            Get-JobsGraphStatus $command $target -Complete
            Assert-True ((Get-FileHash -LiteralPath $database -Algorithm SHA256).Hash -eq $before) '节点表健康检查只读且不修改数据库'
            $status.projectPath = $script:root
            [IO.File]::WriteAllText($fakeCli, 'console.log(JSON.stringify(' + ($status | ConvertTo-Json -Depth 5 -Compress) + '));')
            Assert-Throws { Get-JobsGraphStatus $command $target } '状态不得回退父项目'
            [IO.File]::WriteAllText($fakeCli, 'console.log("invalid JSON");')
            Assert-Throws { Get-JobsGraphStatus $command $target } '无效状态 JSON 停止'
            $drop = 'const {DatabaseSync}=require("node:sqlite");const db=new DatabaseSync(process.argv[1]);db.exec("DROP TABLE nodes");db.close();'
            [void](Invoke-JobsCheckedProcess $node.Source @('-e', $drop, $database) $script:root -Quiet)
            $marker = Join-Path $script:root 'status-was-called'
            [IO.File]::WriteAllText($fakeCli, 'require("fs").writeFileSync(' + (ConvertTo-Json $marker -Compress) + ',"called");')
            Assert-Throws { Get-JobsGraphStatus $command $target 6>$null } '存在 SQLite header 但缺 nodes 表时停止'
            Assert-True (-not [IO.File]::Exists($marker)) '损坏 schema 在运行 status 前被拦截'
        } else { Write-Host '跳过 SQLite 集成测试：Node 不支持 node:sqlite。' }
    } else { Write-Host '跳过 SQLite 集成测试：缺少 Node。' }
    $savedFunctions = @{}
    foreach ($name in @('Find-JobsExecutable', 'Get-JobsGitPushPlan', 'Assert-JobsGitIndexEmpty', 'Invoke-JobsCheckedProcess', 'Read-Host')) {
        $command = Get-Command $name
        $savedFunctions[$name] = if ($command.CommandType -eq 'Function') { $command.ScriptBlock } else { $null }
    }
    $savedEnvironment = @{}
    foreach ($name in @('GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR', 'GIT_INDEX_FILE', 'GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_NAMESPACE')) {
        $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
    try {
        function Find-JobsExecutable { param([string]$Name, [string[]]$Candidates) return 'mock-git.exe' }
        function Assert-JobsGitIndexEmpty { param([string]$Git, [string]$Directory) }
        function Read-Host { param([string]$Prompt) return 'YES' }
        function Get-JobsGitPushPlan {
            param([string]$Git, [string]$Directory)
            return @{ Branch = 'main'; Remote = 'origin'; Ref = 'refs/heads/main'; Url = 'https://example.invalid/captured.git' }
        }
        $script:capturedCommit = '1111111111111111111111111111111111111111'
        $script:pushedArguments = @()
        function Invoke-JobsCheckedProcess {
            param([string]$Executable, [string[]]$Arguments, [string]$Directory, [int]$TimeoutSeconds = 30, [switch]$Quiet)
            $output = ''
            if ($Arguments[0] -eq 'rev-parse') {
                switch ($Arguments[1]) {
                    '--is-inside-work-tree' { $output = 'true' }
                    '--git-path' { $output = Join-Path $script:root ('mock-state-' + $Arguments[2]) }
                    'HEAD^{tree}' { $output = 'unchanged-tree' }
                    'HEAD' { $output = $script:capturedCommit }
                }
            }
            if ($Arguments[0] -eq 'push') { $script:pushedArguments = $Arguments }
            return [pscustomobject]@{ ExitCode = 0; StdOut = $output; StdErr = '' }
        }
        Invoke-JobsGitAction $script:root 6>$null
        Assert-True ($script:pushedArguments[-1] -eq ($script:capturedCommit + ':refs/heads/main')) '推送固定已核验 Commit，后续 HEAD 变化不会带走新提交'
        Assert-True ($script:pushedArguments[-2] -eq 'https://example.invalid/captured.git') '推送使用确认时捕获的唯一 URL'
        Assert-True ('--no-follow-tags' -in $script:pushedArguments -and '--recurse-submodules=no' -in $script:pushedArguments) '单分支推送不附带 tags 或子仓推送'
    } finally {
        foreach ($name in $savedFunctions.Keys) {
            if ($savedFunctions[$name]) { Set-Item -LiteralPath ('Function:' + $name) -Value $savedFunctions[$name] }
            else { Remove-Item -LiteralPath ('Function:' + $name) -ErrorAction SilentlyContinue }
        }
        foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process') }
    }
    Write-Host ("独立终端功能验证通过：{0} 项断言。仅使用临时仓库；未访问网络或执行业务安装、建图、提交、推送。" -f $script:assertions)
} finally {
    Remove-Item -LiteralPath $script:root -Recurse -Force -ErrorAction SilentlyContinue
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

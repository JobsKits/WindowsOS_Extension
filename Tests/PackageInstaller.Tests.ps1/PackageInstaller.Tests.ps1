# PackageInstaller.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年10月18日，星期日.
# 文件和状态使用隔离临时目录；Windows 注册验证只在 GUID 隔离子键下运行。
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
$script:JobsLayoutPackageInstallerTestsRoot = $(if ([IO.Path]::GetFileName($PSScriptRoot) -ceq 'PackageInstaller.Tests.ps1') { Split-Path -Parent $PSScriptRoot } else { $PSScriptRoot })


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
$project = Split-Path -Parent ${script:JobsLayoutPackageInstallerTestsRoot}
$template = Join-Path $project 'Infrastructure/PackageInstaller.psm1'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('JobsPackageTests-' + [guid]::NewGuid().ToString('N'))
$oldLocalAppData = [Environment]::GetEnvironmentVariable('LOCALAPPDATA')
$encoding = New-Object Text.UTF8Encoding($true)

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

function Write-JobsTestText {
    param([string]$Path, [string]$Text)
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Write-JobsTestJson {
    param([string]$Path, $Value)
    Write-JobsTestText -Path $Path -Text ($Value | ConvertTo-Json -Depth 8)
}

function New-JobsTestPackage {
    param([string]$Path, [string]$Id, [string]$Name, [bool]$DirectoryOnly, [bool]$Console)
    Write-JobsTestJson -Path (Join-Path $Path 'Extension.json') -Value @{
        Id = $Id; Name = $Name; Label = '测试功能'; Description = '隔离测试。'; DirectoryOnly = $DirectoryOnly; Console = $Console
    }
    $scripts = Join-Path $Path 'Scripts'
    Write-JobsTestText -Path (Join-Path $scripts 'Common.psm1') -Text 'function Get-JobsTestValue { return 42 }; Export-ModuleMember -Function Get-JobsTestValue'
    Write-JobsTestText -Path (Join-Path $scripts 'Action.psm1') -Text 'function Invoke-JobsFeature { param([string]$Target) return $Target }; Export-ModuleMember -Function Invoke-JobsFeature'
    Write-JobsTestText -Path (Resolve-JobsScriptLayoutPath (Join-Path $scripts 'Invoke.ps1')) -Text 'param([string]$Target); Import-Module (Join-Path $PSScriptRoot "Action.psm1"); Invoke-JobsFeature -Target $Target'
    Copy-Item -LiteralPath $template -Destination (Join-Path $scripts 'PackageInstaller.psm1')
    Copy-Item -LiteralPath (Resolve-JobsScriptLayoutPath (Join-Path $project 'Infrastructure/Manage.ps1')) -Destination (Resolve-JobsScriptLayoutPath (Join-Path $scripts 'Manage.ps1'))
    Write-JobsTestText -Path (Join-Path $Path 'Manage.cmd') -Text '@echo off'
    Write-JobsTestText -Path (Join-Path $Path 'README.md') -Text '测试功能包。'
}

try {
    [Environment]::SetEnvironmentVariable('LOCALAPPDATA', (Join-Path $temporary 'Local'))
    $installer = Import-Module $template -PassThru -DisableNameChecking
    Assert-JobsTest (-not (Test-Path -LiteralPath $temporary)) '导入安装器不创建文件或执行安装'
    $first = Join-Path $temporary 'Sources/JobsFirst'
    $second = Join-Path $temporary 'Sources/JobsSecond'
    New-JobsTestPackage -Path $first -Id 'test-first' -Name 'JobsFirst' -DirectoryOnly $false -Console $false
    New-JobsTestPackage -Path $second -Id 'test-second' -Name 'JobsSecond' -DirectoryOnly $true -Console $true
    $manifest = Get-JobsPackageManifest -PackagePath $first
    Assert-JobsTest ($manifest.Id -eq 'test-first' -and $manifest.Label -ceq '测试功能') '按本包读取 UTF8 manifest'
    $manifestPath = Join-Path $first 'Extension.json'
    $originalManifest = [IO.File]::ReadAllBytes($manifestPath)
    foreach ($badId in @('../test', 'Test-first', 'first\other', '')) {
        $manifest.Id = $badId
        Write-JobsTestJson $manifestPath $manifest
        Assert-JobsThrows { Get-JobsPackageManifest -PackagePath $first } ('拒绝非法 Id：' + $badId)
    }
    [IO.File]::WriteAllBytes($manifestPath, $originalManifest)
    $manifest = Get-JobsPackageManifest -PackagePath $first
    $manifest.Name = 'OtherFeature'
    Write-JobsTestJson $manifestPath $manifest
    Assert-JobsThrows { Get-JobsPackageManifest -PackagePath $first } '拒绝非法功能包名称'
    [IO.File]::WriteAllBytes($manifestPath, $originalManifest)
    $manifest = Get-JobsPackageManifest -PackagePath $first
    $manifest.Console = 'false'
    Write-JobsTestJson $manifestPath $manifest
    Assert-JobsThrows { Get-JobsPackageManifest -PackagePath $first } '布尔开关拒绝字符串'
    [IO.File]::WriteAllBytes($manifestPath, $originalManifest)
    $manifest = Get-JobsPackageManifest -PackagePath $first

    $state = Get-JobsPackageState -PackagePath $first
    $base = Join-Path ([Environment]::GetEnvironmentVariable('LOCALAPPDATA')) 'Jobs/WindowsExtension'
    Assert-JobsTest (-not $state.Enabled -and $state.Source -eq 'None') '新包初始为未安装'
    Assert-JobsTest ($state.Root -eq (Join-Path $base 'extensions/test-first')) '每个功能有自己的安装根目录'
    Assert-JobsTest (-not (Test-Path -LiteralPath $base)) '查询安装状态不创建目录'
    $legacyRelease = Join-Path $base 'releases/legacy'
    Write-JobsTestJson -Path (Join-Path $base 'settings.json') -Value @{ Version = 1; Features = @('test-first'); ReleasePath = $legacyRelease }
    Assert-JobsTest (-not (Get-JobsPackageState -PackagePath $first).Enabled) '仅旧选择清单而无旧运行文件时不能判定已安装'
    Write-JobsTestText -Path (Join-Path $legacyRelease 'Invoke-Menu.ps1') -Text '# legacy entry'
    $legacy = Get-JobsPackageState -PackagePath $first
    Assert-JobsTest ($legacy.Enabled -and $legacy.Source -eq 'Legacy') '已有旧安装可逐包迁移状态'
    Assert-JobsTest (-not (Get-JobsPackageState -PackagePath $second).Enabled) '旧全局设置未启用的另包保持禁用'
    $settingsPath = Join-Path $state.Root 'settings.json'
    Write-JobsTestJson -Path $settingsPath -Value @{ Version = 2; Id = 'test-first'; Enabled = $false; ReleasePath = $legacyRelease }
    $disabled = Get-JobsPackageState -PackagePath $first
    Assert-JobsTest (-not $disabled.Enabled -and $disabled.Source -eq 'Package') '卸载禁用墓碑覆盖旧全局安装状态'
    Write-JobsTestJson -Path $settingsPath -Value @{ Version = 2; Id = 'test-first'; Enabled = $true; ReleasePath = 'own-release' }
    Assert-JobsTest ((Get-JobsPackageState -PackagePath $first).ReleasePath -eq 'own-release') '独立状态优先于旧全局设置'
    Write-JobsTestJson -Path $settingsPath -Value @{ Version = 2; Id = 'test-second'; Enabled = $true; ReleasePath = 'own-release' }
    Assert-JobsThrows { Get-JobsPackageState -PackagePath $first } '状态 Id 不匹配时拒绝操作'
    [IO.File]::Delete($settingsPath)

    $release = Join-Path $temporary 'Release 中文 & 100%'
    $powerShell = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
    $plan = @(Get-JobsPackageRegistryPlan -Manifest $manifest -ReleasePath $release -PowerShellPath $powerShell)
    Assert-JobsTest ($plan.Count -eq 4) '文件功能仅生成本包四个上下文'
    Assert-JobsTest (@($plan.Key | Select-Object -Unique).Count -eq 4) '菜单路径唯一'
    foreach ($item in $plan) {
        Assert-JobsTest ($item.Key.EndsWith('\Jobs.WindowsExtension.test-first')) '菜单只指向当前包 Id'
        Assert-JobsTest ($item.Enabled -and $item.Owner -eq 'Jobs.WindowsExtension.v1') '维持旧 owner 兼容并启用本包'
        Assert-JobsTest ($item.Command.Contains('-WindowStyle Hidden -File "' + (Resolve-JobsScriptLayoutPath (Join-Path $release 'Scripts/Invoke.ps1')) + '"')) '非控制台功能隐藏窗口且直接使用本包入口'
        Assert-JobsTest (-not $item.Command.Contains(' -Action ') -and -not $item.Command.Contains(' -Command ')) '注册命令无需全局分派器'
        $placeholder = '%1'
        if ($item.Key.Contains('\Directory\Background\')) { $placeholder = '%V' }
        Assert-JobsTest ($item.Command.EndsWith('-Target "' + $placeholder + '|JobsPathEnd"')) '保留盘符反斜杠保护和正确目标占位符'
    }
    $quoteCases = @(
        @{ Value = ''; Expected = '""' },
        @{ Value = 'C:\'; Expected = '"C:\\"' },
        @{ Value = 'C:\研发 & 团队\100% done'; Expected = '"C:\研发 & 团队\100% done"' },
        @{ Value = 'C:\a"b\'; Expected = '"C:\a\"b\\"' }
    )
    foreach ($case in $quoteCases) {
        $quoted = & $installer { param($Value) ConvertTo-JobsPackageArgument -Value $Value } $case.Value
        Assert-JobsTest ($quoted -ceq $case.Expected) '参数引用遵守 Windows 反斜杠及引号规则'
    }
    $secondManifest = Get-JobsPackageManifest -PackagePath $second
    $otherPlan = @(Get-JobsPackageRegistryPlan -Manifest $secondManifest -ReleasePath $release -PowerShellPath $powerShell -Enabled $false)
    Assert-JobsTest ($otherPlan.Count -eq 3) '仅目录功能只生成三个上下文'
    Assert-JobsTest (@($otherPlan | Where-Object { $_.Enabled }).Count -eq 0) '禁用计划仍保留完整删除范围'
    Assert-JobsTest (@($otherPlan | Where-Object { $_.Command -notmatch '-WindowStyle Normal -File' }).Count -eq 0) '控制台业务使用可见窗口'
    Assert-JobsTest (@($plan.Key | Where-Object { $_ -in $otherPlan.Key }).Count -eq 0) '两个包没有共享菜单键'

    Write-JobsTestText -Path (Join-Path $first 'Scripts/LocalHelper.psm1') -Text 'function Test-LocalHelper { return 1 }'
    Write-JobsTestText -Path (Join-Path $first 'Scripts/Action.Tests.ps1') -Text 'throw "tests must not ship"'
    Write-JobsTestText -Path (Join-Path $first 'Scripts/Tests/Nested.ps1') -Text 'throw "nested tests must not ship"'
    Write-JobsTestText -Path (Join-Path $first 'logs/private.log') -Text 'not shipped'
    Write-JobsTestText -Path (Join-Path $first 'Tests/private.ps1') -Text 'throw "not shipped"'
    [void](New-JobsPackageRelease -PackagePath $first -Destination $release)
    Assert-JobsTest ((Get-JobsPackageManifest -PackagePath $release).Id -eq 'test-first') 'release 保留完整本包清单'
    foreach ($name in @('Common.psm1', 'Action.psm1', 'Invoke.ps1', 'Manage.ps1', 'PackageInstaller.psm1', 'LocalHelper.psm1')) {
        $relative = 'Scripts/' + $name
        Assert-JobsTest ((Get-FileHash -LiteralPath (Join-Path $first $relative)).Hash -eq (Get-FileHash -LiteralPath (Join-Path $release $relative)).Hash) ('复制 SHA256 一致：' + $relative)
    }
    foreach ($name in @('Manage.cmd', 'README.md')) {
        Assert-JobsTest (Test-Path -LiteralPath (Join-Path $release $name) -PathType Leaf) ('release 附带独立管理入口：' + $name)
    }
    foreach ($relative in @('Tests', 'logs', 'Scripts/Tests', 'Scripts/Action.Tests.ps1', 'JobsSecond', 'Extensions.json')) {
        Assert-JobsTest (-not (Test-Path -LiteralPath (Join-Path $release $relative))) ('release 排除测试/日志/总入口/其它包：' + $relative)
    }
    Assert-JobsThrows { New-JobsPackageRelease -PackagePath $first -Destination $release } '拒绝覆盖已有 release'
    Write-JobsTestText -Path (Join-Path $first 'Scripts/Broken.psm1') -Text 'function Broken {'
    Assert-JobsThrows { New-JobsPackageRelease -PackagePath $first -Destination (Join-Path $temporary 'BadRelease') } '复制前拒绝语法错误的运行文件'
    Assert-JobsTest (-not (Test-Path -LiteralPath (Join-Path $temporary 'BadRelease'))) '语法校验失败不产生半成品目录'
    [IO.File]::Delete((Join-Path $first 'Scripts/Broken.psm1'))
    # 从两个不同目录导入同名模块仍按参数定位本包；随后移走源目录验证独立性。
    $moduleA = Import-Module (Join-Path $first 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
    $moduleB = Import-Module (Join-Path $second 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
    $fromA = & $moduleA { param($Path) Get-JobsPackageManifest -PackagePath $Path } $first
    $fromB = & $moduleB { param($Path) Get-JobsPackageManifest -PackagePath $Path } $second
    Assert-JobsTest ($fromA.Id -eq 'test-first' -and $fromB.Id -eq 'test-second') '同名模块对象保持调用隔离'
    Move-Item -LiteralPath (Join-Path $temporary 'Sources') -Destination (Join-Path $temporary 'HiddenSources')
    $releaseModule = Import-Module (Join-Path $release 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
    $releaseManifest = & $releaseModule { param($Path) Get-JobsPackageManifest -PackagePath $Path } $release
    Assert-JobsTest ($releaseManifest.Id -eq 'test-first') '移走源码和其它功能后已部署包仍可独立管理'
    $action = Import-Module (Join-Path $release 'Scripts/Action.psm1') -PassThru -DisableNameChecking
    Assert-JobsTest ((& $action { Invoke-JobsFeature -Target '独立目标' }) -ceq '独立目标') '移走其它包后仍可运行本包业务'
    $atomicPath = Join-Path $temporary 'atomic-settings.json'
    & $releaseModule { param($Path) Set-JobsPackageSettingsFile -Path $Path -Bytes ([Text.Encoding]::UTF8.GetBytes('first')) } $atomicPath
    & $releaseModule { param($Path) Set-JobsPackageSettingsFile -Path $Path -Bytes ([Text.Encoding]::UTF8.GetBytes('second')) } $atomicPath
    Assert-JobsTest ((Get-Content -LiteralPath $atomicPath -Raw -Encoding UTF8) -eq 'second') 'settings 原子写入支持首次创建和重复替换'
    $closureResult = & $releaseModule {
        param($Path)
        $module = $ExecutionContext.SessionState.Module
        $bytes = [Text.Encoding]::UTF8.GetBytes('closure')
        $commit = { & $module { param($Path, $Bytes) Set-JobsPackageSettingsFile -Path $Path -Bytes $Bytes } $Path $bytes }.GetNewClosure()
        & $commit
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    } $atomicPath
    Assert-JobsTest ($closureResult -eq 'closure') '事务闭包通过所持模块对象访问私有写入函数'

    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        if (-not ('Jobs.PackageTestNative' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Jobs {
    public static class PackageTestNative {
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
        foreach ($target in @('C:\', 'C:\研发 & 团队\100% done', 'C:\引号''与`字符\file.txt')) {
            foreach ($item in $plan) {
                $placeholder = '%1'
                if ($item.Key.Contains('\Directory\Background\')) { $placeholder = '%V' }
                $argv = [Jobs.PackageTestNative]::Arguments($item.Command.Replace($placeholder, $target))
                $fileIndex = [Array]::IndexOf($argv, '-File')
                $targetIndex = [Array]::IndexOf($argv, '-Target')
                Assert-JobsTest ($argv[0] -eq $powerShell) '原生 argv 保留 PowerShell 路径'
                Assert-JobsTest ($argv[$fileIndex + 1] -eq (Resolve-JobsScriptLayoutPath (Join-Path $release 'Scripts/Invoke.ps1'))) '原生 argv 保留本包运行路径'
                Assert-JobsTest ($argv[$targetIndex + 1] -eq ($target + '|JobsPathEnd') -and $argv.Count -eq $targetIndex + 2) '根盘符/中文/&/%目标只占一个参数'
            }
        }
        $registryPath = 'Software\JobsPackageInstallerTests\' + [guid]::NewGuid().ToString('N')
        Assert-JobsTest ($registryPath -match '^Software\\JobsPackageInstallerTests\\[0-9a-f]{32}$') '注册测试仅使用 GUID 隔离子键'
        $registryRoot = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($registryPath)
        try {
            & $releaseModule { param($Plan, $Root) Set-JobsPackageRegistry -Plan $Plan -RegistryRoot $Root } $otherPlan $registryRoot
            foreach ($item in $otherPlan) { $item.Enabled = $true }
            & $releaseModule { param($Plan, $Root) Set-JobsPackageRegistry -Plan $Plan -RegistryRoot $Root } $otherPlan $registryRoot
            & $releaseModule { param($Plan, $Root) Set-JobsPackageRegistry -Plan $Plan -RegistryRoot $Root } $plan $registryRoot
            foreach ($item in $plan) {
                $key = $registryRoot.OpenSubKey($item.Key)
                try { Assert-JobsTest ($key.GetValue('JobsOwner') -eq 'Jobs.WindowsExtension.v1') '独立安装维持旧归属标记' } finally { $key.Dispose() }
            }
            foreach ($item in $plan) { $item.Enabled = $false }
            & $releaseModule { param($Plan, $Root) Set-JobsPackageRegistry -Plan $Plan -RegistryRoot $Root } $plan $registryRoot
            foreach ($item in $otherPlan) {
                $key = $registryRoot.OpenSubKey($item.Key)
                try { Assert-JobsTest ($null -ne $key) '卸载一个功能保留另一个包的全部菜单' } finally { if ($key) { $key.Dispose() } }
            }
            $foreign = $registryRoot.CreateSubKey($plan[1].Key)
            try { $foreign.SetValue('JobsOwner', 'other-owner'); $foreign.SetValue('Keep', 'foreign') } finally { $foreign.Dispose() }
            Assert-JobsThrows { & $releaseModule { param($Plan, $Root) Get-JobsPackageRegistrySnapshot -Plan $Plan -RegistryRoot $Root } $plan $registryRoot } '归属不明时预检拒绝整包操作'
            $foreign = $registryRoot.OpenSubKey($plan[1].Key)
            try { Assert-JobsTest ($foreign.GetValue('Keep') -eq 'foreign') '归属冲突保留外部键内容' } finally { $foreign.Dispose() }
            $registryRoot.DeleteSubKeyTree($plan[1].Key, $false)
            $original = $registryRoot.CreateSubKey($plan[0].Key)
            try {
                $original.SetValue('JobsOwner', 'Jobs.WindowsExtension.v1')
                $original.SetValue('MUIVerb', 'original')
                $original.SetValue('Multi', [string[]]@('甲', '乙'), [Microsoft.Win32.RegistryValueKind]::MultiString)
                $child = $original.CreateSubKey('child')
                try { $child.SetValue('Binary', [byte[]]@(0, 42, 255), [Microsoft.Win32.RegistryValueKind]::Binary) } finally { $child.Dispose() }
            }
            finally { $original.Dispose() }
            foreach ($item in $plan) { $item.Enabled = $true }
            $snapshot = & $releaseModule { param($Plan, $Root) Get-JobsPackageRegistrySnapshot -Plan $Plan -RegistryRoot $Root } $plan $registryRoot
            Assert-JobsThrows {
                & $releaseModule {
                    param($Plan, $Root, $Snapshot, $Path)
                    $module = $ExecutionContext.SessionState.Module
                    $before = [IO.File]::ReadAllBytes($Path)
                    $commit = {
                        & $module { param($Path) Set-JobsPackageSettingsFile -Path $Path -Bytes ([Text.Encoding]::UTF8.GetBytes('new')) } $Path
                        throw '模拟状态提交失败'
                    }.GetNewClosure()
                    $rollback = { & $module { param($Path, $Bytes) Set-JobsPackageSettingsFile -Path $Path -Bytes $Bytes } $Path $before }.GetNewClosure()
                    Invoke-JobsPackageTransaction -Plan $Plan -RegistryRoot $Root -Snapshot $Snapshot -Commit $commit -Rollback $rollback
                } $plan $registryRoot $snapshot $atomicPath
            } '状态提交失败触发注册表和文件联合回滚'
            Assert-JobsTest ((Get-Content -LiteralPath $atomicPath -Raw -Encoding UTF8) -eq 'closure') '事务失败恢复设置原始字节'
            $restored = $registryRoot.OpenSubKey($plan[0].Key)
            try {
                Assert-JobsTest ($restored.GetValue('MUIVerb') -eq 'original') '事务失败恢复旧菜单标签'
                Assert-JobsTest ($restored.GetValueKind('Multi') -eq [Microsoft.Win32.RegistryValueKind]::MultiString -and ($restored.GetValue('Multi') -join ',') -ceq '甲,乙') '事务失败恢复多字符串及值类型'
                $child = $restored.OpenSubKey('child')
                try { Assert-JobsTest (($child.GetValue('Binary') -join ',') -eq '0,42,255') '事务失败恢复子键与二进制值' } finally { $child.Dispose() }
            }
            finally { $restored.Dispose() }
            $newKey = $registryRoot.OpenSubKey($plan[1].Key)
            try { Assert-JobsTest ($null -eq $newKey) '事务失败移除本次新建菜单' } finally { if ($newKey) { $newKey.Dispose() } }
        }
        finally {
            $registryRoot.Dispose()
            [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($registryPath, $false)
        }
    }
    else { Write-Host 'SKIP: Windows 原生 argv 与隔离注册事务验证需在 Windows 执行。' }
}
finally {
    [Environment]::SetEnvironmentVariable('LOCALAPPDATA', $oldLocalAppData)
    foreach ($name in @('installer', 'moduleA', 'moduleB', 'releaseModule', 'action')) {
        $variable = Get-Variable -Name $name -ErrorAction SilentlyContinue
        if ($null -ne $variable -and $null -ne $variable.Value) { Remove-Module $variable.Value -ErrorAction SilentlyContinue }
    }
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
Write-Host ('PASS: PackageInstaller.Tests.ps1 (' + $script:Assertions + ' assertions)')

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

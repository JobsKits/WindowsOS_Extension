# FlutterDoctorCodegen.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年10月22日，星期四.
# 仅临时项目、假工具及内存调用记录；不注册、不运行真实 Flutter。
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
$script:JobsLayoutFlutterDoctorCodegenTestsRoot = $(if ([IO.Path]::GetFileName($PSScriptRoot) -ceq 'FlutterDoctorCodegen.Tests.ps1') { Split-Path -Parent $PSScriptRoot } else { $PSScriptRoot })

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
$root = Split-Path -Parent ${script:JobsLayoutFlutterDoctorCodegenTestsRoot}
$script:assertions = 0
function Assert-Flutter { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw ('FAIL: ' + $Message) }; $script:assertions++ }
function Assert-FlutterThrows { param([scriptblock]$Body, [string]$Message); $failed = $false; try { & $Body | Out-Null } catch { $failed = $true }; Assert-Flutter $failed $Message }
$tempBase = [IO.Path]::GetTempPath()
if ([IO.Directory]::Exists('/private/tmp')) { $tempBase = '/private/tmp' }
$temporary = Join-Path $tempBase ('JobsDoctorCodegen-' + [guid]::NewGuid().ToString('N'))
$savedLocal = $env:LOCALAPPDATA
$modules = @()
try {
    [void][IO.Directory]::CreateDirectory($temporary)
    $env:LOCALAPPDATA = Join-Path $temporary 'Local'
    $project = Join-Path $temporary "Project 中文 & 100% ! [test] '"
    [void][IO.Directory]::CreateDirectory($project)
    $pubspec = Join-Path $project 'pubspec.yaml'
    $plain = "name: fixture`ndependencies:`n  flutter:`n    sdk: flutter`n"
    [IO.File]::WriteAllText($pubspec, $plain)
    foreach ($kind in @('Doctor', 'Codegen')) {
        $package = Join-Path $root ('JobsFlutter' + $kind)
        $action = Import-Module (Join-Path $package 'Scripts/Action.psm1') -PassThru -DisableNameChecking
        $modules += $action
        $fixtures = Get-Content -LiteralPath (Join-Path ${script:JobsLayoutFlutterDoctorCodegenTestsRoot} 'Fixtures/FlutterRunnerPubspec.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($fixture in $fixtures) {
            Assert-Flutter ((& $action { param($Text) Test-JobsFlutterPubspec $Text } $fixture.Text) -eq $fixture.Expected) ($kind + ' 精确根项目：' + $fixture.Name)
        }
        Assert-FlutterThrows { & $action { param($Path) Assert-JobsFlutterProject $Path } $temporary } ($kind + ' 不向下扫描子工程')
        [IO.File]::WriteAllText((Join-Path $project '.fvmrc'), '{"flutter":"3.0.0"}')
        Assert-FlutterThrows { & $action { param($Path) Get-JobsFlutterSdk $Path } $project } ($kind + ' FVM 缺本地 SDK 不回退系统')
        [void][IO.Directory]::CreateDirectory((Join-Path $project '.fvm/flutter_sdk/bin'))
        foreach ($name in @('flutter.bat', 'dart.bat')) { [IO.File]::WriteAllText((Join-Path $project ('.fvm/flutter_sdk/bin/' + $name)), '@echo fake') }
        $sdk = & $action { param($Path) Get-JobsFlutterSdk $Path } $project
        Assert-Flutter ($sdk.Flutter -eq (Join-Path $project '.fvm/flutter_sdk/bin/flutter.bat') -and $sdk.Dart -eq (Join-Path $project '.fvm/flutter_sdk/bin/dart.bat')) ($kind + ' Flutter 与 Dart 同源')
        Remove-Item -LiteralPath (Join-Path $project '.fvmrc') -Force
        Remove-Item -LiteralPath (Join-Path $project '.fvm') -Recurse -Force
        $arguments = @('run', 'pigeon', '--input', "pigeons/消息 & 100%! [x] '.dart")
        $start = & $action { param($Path, $Arguments) New-JobsFlutterToolStartInfo 'C:\SDK & 100%!\dart.bat' $Arguments $Path } $project $arguments
        Assert-Flutter ($start.Arguments.Contains('/v:off') -and -not $start.Arguments.Contains('消息')) ($kind + ' CMD 使用固定命令与延迟展开关闭')
        Assert-Flutter ($start.EnvironmentVariables['JOBS_FLUTTER_ARG_3'] -ceq $arguments[3]) ($kind + ' 特殊参数经环境变量原样传递')
        Assert-FlutterThrows { & $action { New-JobsFlutterToolStartInfo 'bad"tool.bat' @('run') 'C:\' } } ($kind + ' 拒绝引号注入工具路径')
        Assert-FlutterThrows { & $action { New-JobsFlutterToolStartInfo 'tool.bat' @("bad`nline") 'C:\' } } ($kind + ' 拒绝控制字符参数')
        $installer = Import-Module (Join-Path $package 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
        $modules += $installer
        $release = Join-Path $temporary ('release-' + $kind)
        & $installer { param($Path, $Destination) New-JobsPackageRelease $Path $Destination } $package $release | Out-Null
        foreach ($name in @('ContextMenu.cpp', 'FlutterProject.h', 'ContextMenu.def', 'OpenCmd.ps1', 'Build.ps1', 'Check.ps1')) {
            Assert-Flutter (Test-Path -LiteralPath (Join-Path $release ('Scripts/' + $name)) -PathType Leaf) ($kind + ' 独立 release 包含 ' + $name)
        }
        $manifest = Get-Content -LiteralPath (Join-Path $package 'Extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $plan = @(& $installer { param($Manifest, $Release) Get-JobsPackageRegistryPlan $Manifest $Release 'powershell.exe' } $manifest $release)
        Assert-Flutter ($plan.Count -eq 4 -and @($plan | Where-Object { $_.Key -match '\\shell\\' }).Count -eq 0) ($kind + ' 仅原生动态菜单与独立 CLSID')
        Assert-Flutter ($plan[3].InProcServer -eq (Join-Path $release ('bin/JobsFlutter' + $kind + 'ContextMenu.dll'))) ($kind + ' COM 使用自身 DLL')
        $cpp = Get-Content -LiteralPath (Join-Path $package 'Scripts/ContextMenu.cpp') -Raw -Encoding UTF8
        Assert-Flutter ($cpp.Contains('L"' + $manifest.Label + '"') -and $cpp.Contains('DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0) == 1')) ($kind + ' 菜单标签与单选门禁')
        $check = Get-Content -LiteralPath (Resolve-JobsScriptLayoutPath (Join-Path $package 'Scripts/Check.ps1')) -Raw -Encoding UTF8
        Assert-Flutter ($check -notmatch 'Invoke-JobsFlutterTool|Invoke-JobsFeature') ($kind + ' Check 不执行 SDK 或业务动作')
        & $action {
            function script:Write-JobsLog { param($Message) }
            function script:Get-JobsFlutterSdk { param($Project) [pscustomobject]@{ Flutter = 'fake-flutter'; Dart = 'fake-dart' } }
            function script:Invoke-JobsFlutterTool { param($Executable, $Arguments, $Project, $TimeoutSeconds); $script:Calls += [pscustomobject]@{ Executable = $Executable; Arguments = @($Arguments) } }
            $script:Calls = @()
        }
    }
    $codegenAnswers = $modules[2]
    Assert-FlutterThrows { & $codegenAnswers { ConvertFrom-JobsCodegenDeleteAnswer $null } } '冲突确认 EOF 必须停止，不继续 pub get'
    Assert-Flutter (-not (& $codegenAnswers { ConvertFrom-JobsCodegenDeleteAnswer '' })) '冲突确认回车不追加删除参数'
    Assert-Flutter (-not (& $codegenAnswers { ConvertFrom-JobsCodegenDeleteAnswer 'yes' })) '小写 yes 不能启用冲突删除'
    Assert-Flutter (& $codegenAnswers { ConvertFrom-JobsCodegenDeleteAnswer 'YES' }) '精确大写 YES 启用冲突删除'
    $doctor = $modules[0]
    $codegen = $modules[2]
    & $doctor { param($Path) Invoke-JobsFlutterDoctorAction $Path } $project
    $calls = @(& $doctor { $script:Calls })
    Assert-Flutter ($calls.Count -eq 2 -and ($calls[0].Arguments -join ' ') -ceq '--version' -and ($calls[1].Arguments -join ' ') -ceq 'doctor -v') '体检仅执行版本与 doctor'
    Assert-Flutter (@(& $codegen { param($Path) Get-JobsCodegenPlan $Path } $project).Count -eq 0) '普通工程没有可用生成器'
    [void][IO.Directory]::CreateDirectory((Join-Path $project 'protos'))
    [IO.File]::WriteAllText((Join-Path $project 'protos/a.proto'), 'syntax = "proto3";')
    [void][IO.Directory]::CreateDirectory((Join-Path $project 'pigeons'))
    [IO.File]::WriteAllText((Join-Path $project 'pigeons/messages.dart'), '@ConfigurePigeon(PigeonOptions(dartOut: "lib/messages.dart"))')
    Assert-Flutter (@(& $codegen { param($Path) Get-JobsCodegenPlan $Path } $project).Count -eq 0) '只有 protos/pigeons 目录不启动生成器'
    $all = $plain + @'
dev_dependencies:
  build_runner: any
  flutter_launcher_icons: any
  flutter_native_splash: any
  ffigen: any
  pigeon: any
  protobuf: any
  grpc: any
flutter:
  generate: true
flutter_launcher_icons:
  android: true
flutter_native_splash:
  color: '#ffffff'
ffigen:
  output: lib/ffi.dart
'@
    [IO.File]::WriteAllText($pubspec, $all)
    [IO.File]::WriteAllText((Join-Path $project 'l10n.yaml'), 'arb-dir: lib/l10n')
    $plan = @(& $codegen { param($Path) Get-JobsCodegenPlan $Path } $project)
    Assert-Flutter ($plan.Count -eq 7) '依赖和明确配置启用七类生成器'
    Assert-Flutter (($plan | Where-Object Name -eq 'protobuf').Arguments[0] -ceq '--dart_out=grpc:lib/generated') 'grpc 仅直接声明才启用'
    Assert-Flutter (($plan | Where-Object Name -eq 'pigeon').Arguments -notcontains '--dart_out') 'Pigeon 遵从已有输出配置，不猜文件'
    Assert-Flutter (($plan | Where-Object Name -eq 'build_runner').Arguments -notcontains '--delete-conflicting-outputs') '默认计划没有冲突删除参数'
    [IO.File]::WriteAllText((Join-Path $project 'ffigen.yaml'), 'output: lib/ffi.dart')
    $plan = @(& $codegen { param($Path) Get-JobsCodegenPlan $Path } $project)
    Assert-Flutter ((($plan | Where-Object Name -eq 'ffigen').Arguments -join ' ') -ceq 'run ffigen --config ffigen.yaml') '外置 ffigen 配置明确传参'
    [IO.File]::WriteAllText((Join-Path $project 'pigeons/messages.dart'), '@pigeon.ConfigurePigeon(PigeonOptions(dartOut: "lib/messages.dart"))')
    Assert-Flutter (@(& $codegen { param($Path) Get-JobsCodegenPlan $Path } $project).Count -eq 7) 'Pigeon 导入别名 annotation 同样作为显式配置'
    [IO.File]::WriteAllText((Join-Path $project 'pigeons/messages.dart'), '// @ConfigurePigeon(PigeonOptions())')
    Assert-Flutter (@(& $codegen { param($Path) Get-JobsCodegenPlan $Path } $project).Count -eq 6) '注释中的 Pigeon 配置不启用生成'
    [IO.File]::WriteAllText($pubspec, $plain + "dev_dependencies:`n  build_runner: any`n  build_runner: any`n")
    Assert-FlutterThrows { & $codegen { param($Path) Get-JobsCodegenPlan $Path } $project } '重复依赖键拒绝猜测'
    [IO.File]::WriteAllText($pubspec, "dependencies: {flutter: {sdk: flutter}}`ndev_dependencies: {build_runner: any, flutter_launcher_icons: any}`n")
    Assert-Flutter (@(& $codegen { param($Path) Get-JobsCodegenPlan $Path } $project).Count -eq 1) 'flow 依赖可识别，icons 缺配置跳过'
    & $codegen {
        function script:Read-JobsCodegenConsent { return $false }
        function script:Get-JobsCodegenRequiredSdk { param($Project) $script:RequiredSdkCalls++; return Get-JobsFlutterSdk $Project }
        function script:Get-JobsCodegenProtobufTools { throw 'HARD_DENY_UNPLANNED_PROTOBUF' }
        function script:Get-JobsRequiredWinget { throw 'HARD_DENY_REAL_WINGET' }
        function script:Invoke-JobsSdkAcquireProcess { throw 'HARD_DENY_REAL_SDK' }
        $script:RequiredSdkCalls = 0
        $script:Calls = @()
    }
    & $codegen { param($Path) Invoke-JobsFlutterCodegenAction $Path } $project
    Assert-Flutter (@(& $codegen { $script:Calls }).Count -eq 0 -and (& $codegen {$script:RequiredSdkCalls}) -eq 0) '取消发生在SDK必要获取及pub get之前'
    & $codegen { function script:Read-JobsCodegenConsent { return $true }; function script:Read-JobsCodegenDeleteConsent { return $false } }
    & $codegen { param($Path) Invoke-JobsFlutterCodegenAction $Path } $project
    $calls = @(& $codegen { $script:Calls })
    Assert-Flutter ($calls.Count -eq 3 -and ($calls[0].Arguments -join ' ') -ceq '--version' -and ($calls[1].Arguments -join ' ') -ceq 'pub get') '确认后先补齐SDK、获取依赖再生成'
    Assert-Flutter ($calls[2].Arguments -notcontains '--delete-conflicting-outputs') '未明确同意不追加冲突删除参数'
    & $codegen { function script:Read-JobsCodegenDeleteConsent { return $true }; $script:Calls = @() }
    & $codegen { param($Path) Invoke-JobsFlutterCodegenAction $Path } $project
    $calls = @(& $codegen { $script:Calls })
    Assert-Flutter ($calls[2].Arguments -contains '--delete-conflicting-outputs') '明确 YES 才追加冲突删除参数'
    & $codegen { function script:Invoke-JobsFlutterTool { param($Executable, $Arguments, $Project); $script:Calls += 'failure'; throw 'fake pub get failed' }; $script:Calls = @() }
    Assert-FlutterThrows { & $codegen { param($Path) Invoke-JobsFlutterCodegenAction $Path } $project } '获取依赖失败向上抛出错误'
    Assert-Flutter (@(& $codegen { $script:Calls }).Count -eq 1) '首步失败立即停止，不能误报后续成功'
    $actual = Import-Module (Join-Path $root 'JobsFlutterDoctor/Scripts/Action.psm1') -Force -PassThru -DisableNameChecking
    $modules += $actual
    & $actual { function script:Write-JobsLog { param($Message) } }
    $fakeTool = Join-Path $temporary 'FakeTool.ps1'
    [IO.File]::WriteAllText($fakeTool, "Write-Output 'fake stdout'`n[Console]::Error.WriteLine('fake stderr')`nexit 7`n")
    $powerShell = (Get-Process -Id $PID).Path
    Assert-FlutterThrows { & $actual { param($Exe, $Script, $Project) Invoke-JobsFlutterTool $Exe @('-NoProfile', '-File', $Script) $Project 30 } $powerShell $fakeTool $project } '假子进程 stdout/stderr 正常收集且非零退出传播'
    [IO.File]::WriteAllText($fakeTool, "Write-Output '[!] Android toolchain missing'`nWrite-Output 'Doctor found issues in 1 category.'`nexit 0`n")
    Assert-FlutterThrows { & $actual { param($Exe, $Script, $Project) Invoke-JobsFlutterTool $Exe @('-NoProfile', '-File', $Script) $Project 30 -Doctor } $powerShell $fakeTool $project } 'doctor exit 0 但诊断有问题仍失败'
    & $actual { param($Exe, $Script, $Project) Invoke-JobsFlutterTool $Exe @('-NoProfile', '-File', $Script) $Project 30 } $powerShell $fakeTool $project
    Assert-Flutter $true 'doctor 判定不误作用于其它子命令'
    $before = [IO.File]::ReadAllText($pubspec)
    $beforeFiles = @(Get-ChildItem -LiteralPath $env:LOCALAPPDATA -File -Recurse -ErrorAction SilentlyContinue).Count
    & (Resolve-JobsScriptLayoutPath (Join-Path $root 'JobsFlutterCodegen/Scripts/Check.ps1')) -Target $project
    Assert-Flutter ([IO.File]::ReadAllText($pubspec) -ceq $before) '真实 Check 入口只读配置'
    Assert-Flutter (@(Get-ChildItem -LiteralPath $env:LOCALAPPDATA -File -Recurse -ErrorAction SilentlyContinue).Count -eq $beforeFiles) 'Check 缺配置诊断也不创建日志文件'
    Write-Host ('PASS: FlutterDoctorCodegen.Tests.ps1 (' + $script:assertions + ' assertions)')
} finally {
    foreach ($module in $modules) { Remove-Module $module -ErrorAction SilentlyContinue }
    $env:LOCALAPPDATA = $savedLocal
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

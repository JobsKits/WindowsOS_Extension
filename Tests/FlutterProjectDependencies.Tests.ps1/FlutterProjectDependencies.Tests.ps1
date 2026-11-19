# FlutterProjectDependencies.Tests.ps1 | 分层依赖、取消与真实解析门禁隔离回归。
# Created by Jobs on 2026年10月29日，星期四.

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
$script:JobsLayoutFlutterProjectDependenciesTestsRoot = $(if ([IO.Path]::GetFileName($PSScriptRoot) -ceq 'FlutterProjectDependencies.Tests.ps1') { Split-Path -Parent $PSScriptRoot } else { $PSScriptRoot })

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
$root = Split-Path -Parent ${script:JobsLayoutFlutterProjectDependenciesTestsRoot}
$count = 0
function Assert($Value,[string]$Message) { $script:count++; if (-not $Value) { throw $Message } }
function Assert-Throws([scriptblock]$Body,[string]$Message) { $failed=$false; try { & $Body | Out-Null } catch { $failed=$true }; Assert $failed $Message }
$base = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { [IO.Path]::GetTempPath() } else { '/private/tmp' }
$temp = Join-Path $base ('jobs-dependency-layers-' + [guid]::NewGuid().ToString('N'))
$project = Join-Path $temp '项目 空格 & $literal'
[void][IO.Directory]::CreateDirectory((Join-Path $project 'lib'))
[IO.File]::WriteAllText((Join-Path $project 'pubspec.yaml'),"name: fixture`ndependencies:`n  flutter:`n    sdk: flutter`n")
$module = Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetup.psm1') -PassThru -DisableNameChecking
try {
    & $module {
        param($base)
        $script:fixture = $base
        $script:calls = New-Object 'System.Collections.Generic.List[string]'
        $script:fixtureResult = ''
        $script:failCommand = ''
        $script:cancel = $false
        function script:Invoke-JobsSetupProcess {
            param($File,[string[]]$Arguments,$Directory,$TimeoutSeconds)
            $command = $Arguments -join ' '
            $script:calls.Add($File+'|'+$command+'|'+$Directory)
            if ($script:failCommand -and $command.StartsWith($script:failCommand)) { throw 'fixture command failure' }
            $output = switch -Regex ($command) {
                '^jobsResolveDependencyArtifacts' { if($script:fixtureResult){$script:fixtureResult}else{'JOBS_ARTIFACTS_RESOLVED|3'}; break }
                '^precache --help$' { '--[no-]android --[no-]windows --[no-]web --[no-]ohos'; break }
                '^build .+ --help$' { 'flutter '+($command -replace ' --help$',''); break }
                '^--help$' { '--sync Synchronize project dependencies'; break }
                '^--version$' { '9.1.0'; break }
                '^-version$' { 'openjdk version "17.0.1"'; break }
                default { 'fixture success' }
            }
            return [pscustomobject]@{ExitCode=0;StdOut=$output;StdErr=''}
        }
        function script:Find-JobsExecutable { param($Name,$Candidates) 'tool-'+$Name }
        function script:Get-JobsInstallRoot { $script:fixture }
        function script:Test-JobsSetupInteractive { $true }
        function script:Read-Host { param($Prompt) if($script:cancel){'cancel'}else{''} }
        function script:Read-JobsSetupInput { param($Prompt,$Node) Read-Host $Prompt }
        function script:Get-JobsSetupFzf { param($p) $script:calls.Add('fzf'); 'fixture-fzf' }
        function script:Get-JobsDependencyFlutter { param($p,$f) $script:calls.Add('flutter-health'); [pscustomobject]@{Mode='fvm';Flutter='flutter.bat';Dart='dart.exe';Root='fixture-sdk'} }
        function script:Get-JobsDependencyJava { param($p,$f) $script:calls.Add('java-health'); [pscustomobject]@{Mode='system';Home='fixture-java';Major=17} }
        function script:Set-JobsSetupJavaProcess { param($p,$j) $script:calls.Add('java-bind'); $env:GRADLE_OPTS='fixture-changed' }
        function script:Initialize-JobsSetupAndroid { param($p,$f,$j,$z) $script:calls.Add('android-tools') }
        function script:Initialize-JobsSetupWindowsDesktop { param($p,$z) $script:calls.Add('windows-tools') }
        function script:Install-JobsSetupGradle { param($p,$j,$z) $script:calls.Add('gradle-wrapper'); 'gradlew.bat' }
        function script:Select-JobsSetupChoice { param($Fzf,$Title,$Choices,$Back) $Choices[0] }
    } $temp

    $before = @(Get-ChildItem -LiteralPath $temp -Recurse -Force | ForEach-Object FullName)
    & $module { param($p) Invoke-JobsProjectDependencyAction $p android-dependencies -Check } $project
    Assert ((& $module { $script:calls.Count }) -eq 0) 'Check 不调用命令、选择器或 SDK'
    Assert ((@(Get-ChildItem -LiteralPath $temp -Recurse -Force | ForEach-Object FullName) -join '|') -ceq ($before -join '|')) 'Check 不写文件'
    & $module { $script:cancel=$true }
    Assert-Throws { & $module { param($p) Invoke-JobsProjectDependencyAction $p pub-get } $project } '初始取消传播'
    Assert ((& $module { $script:calls.Count }) -eq 0) '取消无 SDK/下载副作用'
    & $module { $script:cancel=$false }
    & $module { param($p) Invoke-JobsProjectDependencyAction $p pub-get } $project
    $calls = @(& $module { $script:calls.ToArray() })
    Assert ($calls.Count -eq 2 -and $calls[0] -ceq 'flutter-health' -and $calls[1] -like '*|pub get|*') 'Pub 只检查 SDK 并获取 Pub，不调用其它平台或 fzf'
    & $module { $script:calls.Clear(); $script:failCommand='pub get' }
    Assert-Throws { & $module { param($p) Invoke-JobsProjectDependencyAction $p pub-get } $project } 'Pub 失败传播'
    & $module { $script:failCommand=''; $script:calls.Clear() }
    & $module { param($p) Invoke-JobsProjectDependencyAction $p web-dependencies } $project
    Assert ((& $module { $script:calls.Count }) -eq 0) '无 package.json 的 Web 不安装 Node 或 SDK'

    [void][IO.Directory]::CreateDirectory((Join-Path $project 'android'))
    $savedOpts = [Environment]::GetEnvironmentVariable('GRADLE_OPTS','Process')
    & $module { param($p) Invoke-JobsProjectDependencyAction $p android-dependencies } $project
    $calls = @(& $module { $script:calls.ToArray() })
    Assert (($calls -join ';') -match 'pub get' -and ($calls -join ';') -match 'jobsResolveDependencyArtifacts') 'Android 真正解析 Pub 后 Maven artifacts'
    Assert (-not (($calls -join ';') -match '\|help\b')) 'Android 不把 Gradle help 当原生库下载'
    Assert ([Environment]::GetEnvironmentVariable('GRADLE_OPTS','Process') -ceq $savedOpts) '成功后恢复进程 Gradle 环境'
    & $module { $script:calls.Clear(); $script:fixtureResult='dependency graph only' }
    Assert-Throws { & $module { param($p) Invoke-JobsProjectDependencyAction $p android-dependencies } $project } '没有真实解析标记不得报成功'
    Assert ([Environment]::GetEnvironmentVariable('GRADLE_OPTS','Process') -ceq $savedOpts) '失败后恢复进程环境'
    & $module { $script:fixtureResult=''; $script:calls.Clear(); $script:failCommand='jobsResolveDependencyArtifacts' }
    Assert-Throws { & $module { param($p) Invoke-JobsProjectDependencyAction $p android-dependencies } $project } '任一 configuration 解析失败停止'
    & $module { $script:failCommand=''; $script:calls.Clear() }
    $init = & $module { param($d) New-JobsDependencyGradleInit $d } $temp
    $groovy = [IO.File]::ReadAllText($init)
    Assert ($groovy.Contains('it.canBeResolved') -and $groovy.Contains('configuration.resolve()') -and $groovy.Contains('artifact.exists()')) 'init 同时请求真实 artifact 文件并检验存在'
    Assert ($groovy.Contains('project.buildscript.configurations') -and $groovy.Contains('project.configurations')) '构建插件与项目 configurations 同时覆盖'
    Assert (-not $groovy.Contains('lenient') -and -not $groovy.Contains('catch')) '未宽松吞掉配置解析错误'

    & $module { param($p) Invoke-JobsProjectDependencyAction $p flutter-precache } $project
    $calls = @(& $module { $script:calls.ToArray() })
    Assert (($calls -join ';') -match 'precache --android') 'SDK 产物按所选目标 precache'
    Assert (-not (($calls -join ';') -match 'java-health|android-tools|gradle-wrapper|pub get|build apk')) 'precache 不混入 SDK manager 之外的平台工具或 Pub/构建'

    [IO.File]::WriteAllText((Join-Path $project 'package.json'),'{}')
    [IO.File]::WriteAllText((Join-Path $project 'package-lock.json'),'{}')
    & $module { $script:calls.Clear() }
    & $module { param($p) Invoke-JobsDependencyWeb $p } $project
    Assert ((& $module { $script:calls -join ';' }) -match 'tool-npm.cmd\|ci\|') 'npm 锁文件使用 ci，生命周期输出不关闭'
    [IO.File]::Delete((Join-Path $project 'package-lock.json'))
    [IO.File]::WriteAllText((Join-Path $project 'pnpm-lock.yaml'),'lockfileVersion: 9')
    & $module { $script:calls.Clear() }
    & $module { param($p) Invoke-JobsDependencyWeb $p } $project
    Assert ((& $module { $script:calls -join ';' }) -match 'tool-pnpm.cmd\|install --frozen-lockfile\|') 'pnpm 使用冻结锁'
    [IO.File]::WriteAllText((Join-Path $project 'yarn.lock'),'fixture')
    Assert-Throws { & $module { param($p) Invoke-JobsDependencyWeb $p } $project } '多个管理器锁拒绝猜测'
    [IO.File]::Delete((Join-Path $project 'pnpm-lock.yaml'))
    & $module { $script:calls.Clear() }
    & $module { param($p) Invoke-JobsDependencyWeb $p } $project
    Assert ((& $module { $script:calls -join ';' }) -match 'tool-yarn.cmd\|install --immutable\|') '现代 Yarn 使用 immutable'
    [IO.File]::WriteAllText((Join-Path $project 'package.json'),'{"packageManager":"npm@9.1.0"}')
    Assert-Throws { & $module { param($p) Invoke-JobsDependencyWeb $p } $project } 'packageManager 与锁文件冲突拒绝'
    [IO.File]::WriteAllText((Join-Path $project 'package.json'),'{"packageManager":"yarn@9.2.0"}')
    Assert-Throws { & $module { param($p) Invoke-JobsDependencyWeb $p } $project } '已装管理器不符合精确版本拒绝'
    [IO.File]::WriteAllText((Join-Path $project 'package.json'),'{}')

    & $module { $script:calls.Clear() }
    $arguments = @('build','apk','--debug','--target','lib/main_custom.dart','--flavor','demo','--dart-define-from-file=C:\config space\env.json')
    $result = & $module { param($p,$a) Invoke-JobsDependencyNative $p ([pscustomobject]@{Flutter='flutter.bat'}) 'fixture-fzf' 'Android' $a } $project $arguments
    Assert (($result -join '|') -ceq ($arguments -join '|')) '实际 native 构建返回原选定入口/flavor/define'
    $calls = @(& $module { $script:calls.ToArray() })
    Assert ($calls[0] -match '\|build apk --help\|' -and $calls[1] -match '\|build apk --debug --target lib/main_custom.dart --flavor demo') '构建前先验证目标命令能力'
    Assert (-not (($calls -join ';') -match '\|run\b')) 'native 准备不会启动应用'

    $packager = Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/Actions/package/Scripts/Action.psm1') -PassThru -DisableNameChecking
    $savedHarmonySdk=$env:DEVECO_SDK_HOME
    $env:DEVECO_SDK_HOME=Join-Path $temp 'harmony-sdk'
    [void][IO.Directory]::CreateDirectory($env:DEVECO_SDK_HOME)
    & $packager { function script:Initialize-JobsPackagerHarmonyEnvironment { } }
    $ohos = Join-Path $project 'ohos'
    [void][IO.Directory]::CreateDirectory((Join-Path $ohos 'hvigor'))
    [IO.File]::WriteAllText((Join-Path $ohos 'oh-package.json5'),'{}')
    [IO.File]::WriteAllText((Join-Path $ohos 'hvigor/hvigor-config.json5'),'{}')
    [IO.File]::WriteAllText((Join-Path $ohos 'hvigorw.bat'),'fixture wrapper')
    & $module { $script:calls.Clear() }
    & $module { param($p) Invoke-JobsDependencyOhos $p } $project
    $calls = @(& $module { $script:calls.ToArray() })
    Assert ($calls.Count -eq 8 -and $calls[2] -match 'ohpm.bat\|--version' -and $calls[5] -match 'hvigorw.bat\|--help') 'OHOS 先核验 Node/npm/Java/OHPM 与工程 wrapper 能力'
    Assert ($calls[6] -match 'ohpm.bat\|install\|' -and $calls[7] -match 'hvigorw.bat\|--sync\|') 'OHOS 原生库和固定插件分别实际执行'
    Assert (@($calls | Where-Object { $_ -notlike ('*|'+$ohos) }).Count -eq 0) 'ohpm 与 Hvigor 均在目标 ohos 目录运行'
    & $module { $script:calls.Clear(); $script:failCommand='install' }
    Assert-Throws { & $module { param($p) Invoke-JobsDependencyOhos $p } $project } 'ohpm 失败停止 Hvigor'
    Assert (-not ((& $module { $script:calls -join ';' }) -match '\|--sync\|')) 'ohpm 失败后未继续插件同步'
    & $module { $script:failCommand=''; $script:calls.Clear() }
    [IO.File]::Delete((Join-Path $ohos 'hvigorw.bat'))
    Assert-Throws { & $module { param($p) Invoke-JobsDependencyOhos $p } $project } '缺少项目 wrapper 不安装全局最新 Hvigor'
    Assert ((& $module { $script:calls.Count }) -eq 0) 'wrapper 缺失没有联网命令'

    $env:DEVECO_SDK_HOME=$savedHarmonySdk
    [IO.File]::WriteAllText((Join-Path $project 'lib/main_custom.dart'),'void main() {}')
    $plan = & $module { param($p) Get-JobsSetupRunArguments $p 'fzf' '' 'Windows' -ForBuild } $project
    Assert (($plan -join '|') -ceq 'build|windows|--debug|--target|lib/main_custom.dart') '原生准备不强制不存在的 lib/main.dart'
    $release = Join-Path $temp 'release'
    $installer = Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
    & $installer { param($p,$d) New-JobsPackageRelease -PackagePath $p -Destination $d } (Join-Path $root 'JobsFlutterTools') $release | Out-Null
    Assert ([IO.File]::Exists((Resolve-JobsScriptLayoutPath (Join-Path $release 'Scripts/ProjectSetupToolchains.ps1')))) '发布目录包含完整平台工具链 helper，不依赖外部工作树'
    Assert ((Get-FileHash (Resolve-JobsScriptLayoutPath (Join-Path $release 'Scripts/ProjectDependencies.ps1'))).Hash -ceq (Get-FileHash (Resolve-JobsScriptLayoutPath (Join-Path $root 'JobsFlutterTools/Scripts/ProjectDependencies.ps1'))).Hash) '独立发布携带同字节依赖内核'
    Assert ((Get-FileHash (Join-Path $release 'Scripts/HarmonySdk.psm1')).Hash -ceq (Get-FileHash (Join-Path $root 'JobsFlutterTools/Scripts/HarmonySdk.psm1')).Hash) '独立发布携带同字节鸿蒙取消契约'

    # SDK 缺失/损坏复用真实管理模块的完成契约，外部安装过程换成测试函数。
    $fresh = Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetup.psm1') -Force -PassThru -DisableNameChecking
    $sdk = Join-Path $temp 'version-sdk'
    [void][IO.Directory]::CreateDirectory((Join-Path $sdk 'bin/cache/dart-sdk/bin'))
    foreach ($relative in @('bin/flutter.bat','bin/cache/dart-sdk/bin/dart.exe')) { [IO.File]::WriteAllText((Join-Path $sdk $relative),'fixture file, not executed') }
    & $fresh {
        function script:Invoke-JobsSetupProcess {
            param($File,$Arguments,$Directory,$TimeoutSeconds)
            $text = if ($Arguments -contains '--machine') { '{"frameworkVersion":"3.29.3","dartSdkVersion":"3.7.2"}' } else { 'Dart SDK version: 3.7.2 (stable) on "windows_x64"' }
            [pscustomobject]@{StdOut=$text;StdErr='';ExitCode=0}
        }
    }
    $metadata = & $fresh { param($file,$p) Get-JobsSetupFlutter $file $p 'system' } (Join-Path $sdk 'bin/flutter.bat') $project
    Assert ($metadata.FrameworkVersion -ceq '3.29.3' -and $metadata.Architecture -ceq 'windows_x64') '从真实格式输出解析归档所需SDK版本与架构'
    $manager = Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/Actions/sdk-manage/Scripts/Action.psm1') -PassThru -DisableNameChecking
    & $manager {
        $script:preparations=0
        $script:cancelPreparation=$false
        function script:Invoke-JobsFlutterVersionAction {
            param($Directory,[switch]$RequireCompletion)
            if(-not $RequireCompletion){throw 'dependency chain did not require completion'}
            $script:preparations++
            if($script:cancelPreparation){throw 'fixture SDK cancelled'}
            [IO.File]::WriteAllText((Join-Path $Directory '.fvmrc'),'{"flutter":"3.29.3"}')
        }
    }
    & $fresh {
        $script:healthCalls=0
        $script:healthFailure=$false
        function script:Get-JobsSetupFlutter { param($f,$p,$m) $script:healthCalls++; if($script:healthFailure){throw 'fixture broken runtime'};[pscustomobject]@{Mode=$m;Flutter=$f;Root='fixture'} }
    }
    & $fresh { param($p) Get-JobsDependencyFlutter $p '' } $project | Out-Null
    Assert ((& $manager {$script:preparations}) -eq 1 -and (& $fresh {$script:healthCalls}) -eq 1) '缺SDK走安装后真实复检一次'
    & $fresh { param($p) Get-JobsDependencyFlutter $p '' } $project | Out-Null
    Assert ((& $manager {$script:preparations}) -eq 1) '健康已绑定不重复准备'
    & $fresh { $script:healthFailure=$true }
    Assert-Throws { & $fresh { param($p) Get-JobsDependencyFlutter $p '' } $project } '准备后健康复检仍失败即停止'
    Assert ((& $manager {$script:preparations}) -eq 2) '损坏 SDK 只修复一次'
    & $manager { $script:cancelPreparation=$true }
    Assert-Throws { & $fresh { param($p) Get-JobsDependencyFlutter $p '' } $project } 'SDK 取消不继续复检/下游'
    Remove-Module $fresh
    Write-Host ('PASS: FlutterProjectDependencies.Tests.ps1 ('+$count+' assertions; mock tools only, no install/network/native build/registry)')
} finally {
    Remove-Module ProjectSetup -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temp -Recurse -Force
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

# DeploymentRoutes.Tests.ps1 | Jobs Windows 两种部署路线与清理边界
# Created by Jobs on 2026年11月2日，星期一.
# 全部文件位于临时目录；系统登记、通知和快捷方式通过临时模块内假实现阻断。
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
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempBase = [IO.Path]::GetTempPath()
if ($tempBase.StartsWith('/var/') -and (Test-Path ('/private' + $tempBase))) { $tempBase = '/private' + $tempBase }
$temp = Join-Path $tempBase ('JobsRoutes 中文 ' + [guid]::NewGuid().ToString('N'))
$oldLocal = $env:LOCALAPPDATA
$script:assertions = 0
function Assert-Route { param([bool]$Value, [string]$Message) if (-not $Value) { throw ('FAIL: ' + $Message) }; $script:assertions++ }
function Write-Fixture { param([string]$Path, [string]$Text) [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path)); [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($true))) }
function Assert-Rejected { param([scriptblock]$Action, [string]$Message) $rejected = $false; try { & $Action } catch { $rejected = $true }; Assert-Route $rejected $Message }
try {
    $env:LOCALAPPDATA = Join-Path $temp 'LocalData'
    $package = Join-Path $temp 'Source/JobsFixture'
    Write-Fixture (Join-Path $package 'Extension.json') '{"Id":"fixture-route","Name":"JobsFixture","Label":"测试","Description":"隔离","DirectoryOnly":false,"Console":false}'
    foreach ($name in @('Invoke.ps1', 'Action.psm1', 'Manage.ps1')) { Write-Fixture (Join-Path $package ('Scripts/' + $name)) '# isolated' }
    Copy-Item -LiteralPath (Join-Path $root 'Infrastructure/Common.psm1') -Destination (Join-Path $package 'Scripts/Common.psm1')
    Write-Fixture (Join-Path $package 'Scripts/Build.ps1') @'
param($SourceRoot, $OutputRoot)
[void][IO.Directory]::CreateDirectory($OutputRoot)
[IO.File]::WriteAllText((Join-Path $OutputRoot 'JobsFileVolumesContextMenu.dll'), 'runtime-dll')
[IO.File]::WriteAllText((Join-Path $OutputRoot 'fixture.obj'), 'intermediate')
[IO.File]::WriteAllText((Join-Path $OutputRoot 'native.rsp'), 'compiler-arguments')
'@
    $installerText = Get-Content -LiteralPath (Join-Path $root 'JobsFileVolumes/Scripts/PackageInstaller.psm1') -Raw
    $installerText = $installerText.Replace("if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT)", 'if ($false)').Replace("if (`$PSVersionTable.PSEdition -ne 'Desktop' -or `$PSVersionTable.PSVersion -lt [version]'5.1')", 'if ($false)')
    Write-Fixture (Join-Path $package 'Scripts/PackageInstaller.psm1') $installerText
    $module = Import-Module (Join-Path $package 'Scripts/PackageInstaller.psm1') -PassThru -Force -DisableNameChecking
    & $module {
        # 注册表、Shell 和开始菜单均为隔离替身；构建只写假 DLL。
        function script:Get-JobsPackageRegistrySnapshot { param($Plan, $RegistryRoot) return @{} }
        function script:Set-JobsPackageRegistry { param($Plan, $RegistryRoot) }
        function script:Restore-JobsPackageRegistrySnapshot { param($Snapshot, $RegistryRoot) }
        function script:Set-JobsPackageUninstallShortcut { param($Manifest, $ReleasePath, $Mode) }
        function script:Send-JobsPackageShellChange { }
    }
    $installed = & $module { param($Path) Invoke-JobsPackageChange -PackagePath $Path -Mode Install -DeploymentMode installed } $package
    Assert-Route ($installed.ReleasePath.StartsWith($env:LOCALAPPDATA)) '默认安装沿用当前用户 LocalAppData'
    $runtime = Import-Module (Join-Path $installed.ReleasePath 'Scripts/Common.psm1') -PassThru -Force -DisableNameChecking
    $boundRoot = & $runtime { Get-JobsInstallRoot }
    Assert-Route ($boundRoot -eq $installed.Root) '运行脚本从自身部署绑定找到状态根，无 GUI 环境变量'
    $outer = Join-Path $temp 'nested-flutter-release'
    Write-Fixture (Join-Path $outer 'deployment.json') (ConvertTo-Json -InputObject @{ Version = 1; Id = 'flutter-tools'; Root = $installed.Root })
    Write-Fixture (Join-Path $outer 'Scripts/Actions/run/Extension.json') '{"Id":"flutter-run"}'
    [void][IO.Directory]::CreateDirectory((Join-Path $outer 'Scripts/Actions/run/Scripts'))
    Copy-Item -LiteralPath (Join-Path $root 'JobsFlutterTools/Scripts/Actions/run/Scripts/Common.psm1') -Destination (Join-Path $outer 'Scripts/Actions/run/Scripts/Common.psm1') -ErrorAction Stop
    $nestedRuntime = Import-Module (Join-Path $outer 'Scripts/Actions/run/Scripts/Common.psm1') -PassThru -Force -DisableNameChecking
    Assert-Route ((& $nestedRuntime { Get-JobsInstallRoot }) -eq (Join-Path $installed.Root 'actions/flutter-run')) '统一 Flutter 内嵌动作随外层当前路线定位'

    # 对真实构建包装执行假 Build.ps1，核对中间文件与运行 DLL 分离。
    & $module { param($Path, $Release) Build-JobsPackageNativeRelease -PackagePath $Path -ReleasePath $Release -DeploymentMode installed } $package $installed.ReleasePath
    $firstBuild = & $module { $script:LastBuildPath }
    & $module { param($Path, $Release) Build-JobsPackageNativeRelease -PackagePath $Path -ReleasePath $Release -DeploymentMode installed } $package $installed.ReleasePath
    $secondBuild = & $module { $script:LastBuildPath }
    Assert-Route (Test-Path -LiteralPath (Join-Path $installed.ReleasePath 'bin/JobsFileVolumesContextMenu.dll')) '部署 DLL 存于运行 release/bin'
    Assert-Route (-not (Test-Path -LiteralPath (Join-Path $installed.ReleasePath 'bin/fixture.obj'))) '编译中间文件不混入运行 bin'
    $dllHash = (Get-FileHash (Join-Path $installed.ReleasePath 'bin/JobsFileVolumesContextMenu.dll')).Hash
    Clear-JobsPackageBuildArtifacts -PackagePath $package -BuildPath $secondBuild
    Assert-Route (-not (Test-Path $secondBuild) -and (Test-Path $firstBuild)) '自动清理只删除本次 GUID 工作区，历史构建保留'
    Assert-Route ((Get-FileHash (Join-Path $installed.ReleasePath 'bin/JobsFileVolumesContextMenu.dll')).Hash -eq $dllHash) '自动清理不改变已安装 DLL'
    Assert-Rejected { Clear-JobsPackageBuildArtifacts -PackagePath $package -BuildPath $installed.ReleasePath } '清理拒绝运行 release 路径'
    $build = & $module { param($Path) Invoke-JobsPackageChange -PackagePath $Path -Mode Install -DeploymentMode build } $package
    Assert-Route ($build.ReleasePath.StartsWith((Join-Path $package 'work/WindowsExtension'))) '临时路线只使用本包 work 运行目录'
    $buildRuntime = Import-Module (Join-Path $build.ReleasePath 'Scripts/Common.psm1') -PassThru -Force -DisableNameChecking
    Assert-Route ((& $buildRuntime { Get-JobsInstallRoot }) -eq $build.Root) 'Explorer 启动临时路线时独立找到 build 状态'
    $oldInstalled = Get-JobsPackageState -PackagePath $package -DeploymentMode installed
    Assert-Route (-not $oldInstalled.Enabled) '切换路线后原路线不再误报已启用'
    $beforeDefault = [IO.File]::ReadAllBytes((Join-Path $installed.Root 'settings.json'))
    & $module {
        param($FailPath)
        $script:TestFailPath = $FailPath
        $script:TestFailOnce = $true
        $script:RealSettingsWriter = ${function:Set-JobsPackageSettingsFile}
        function script:Set-JobsPackageSettingsFile {
            param($Path, [byte[]]$Bytes)
            if ($script:TestFailOnce -and $Path -eq $script:TestFailPath) { $script:TestFailOnce = $false; throw 'isolated-settings-failure' }
            & $script:RealSettingsWriter $Path $Bytes
        }
    } (Join-Path $installed.Root 'settings.json')
    Assert-Rejected { & $module { param($Path) Invoke-JobsPackageChange -PackagePath $Path -Mode Install -DeploymentMode installed } $package } '新路线提交失败返回失败'
    Assert-Route ((Get-JobsPackageState -PackagePath $package -DeploymentMode build).Enabled) '提交失败完整恢复原 build 路线启用状态'
    Assert-Route ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $installed.Root 'settings.json'))) -ceq [Convert]::ToBase64String($beforeDefault)) '提交失败逐字恢复 installed 原状态'

    Assert-Rejected { Clear-JobsPackageBuildArtifacts -PackagePath $package } '没有默认位置正常安装时禁止独立清理'
    $uninstall = & $module { param($Path) Invoke-JobsPackageChange -PackagePath $Path -Mode Uninstall -DeploymentMode installed } $package
    Assert-Route ($uninstall.Outcome -ceq 'NotInstalled' -and $uninstall.Mode -ceq 'Uninstall' -and $uninstall.Backup -eq $null) '当前路线未安装返回独立无需卸载结果，不伪造成功或备份'
    Assert-Route ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $installed.Root 'settings.json'))) -ceq [Convert]::ToBase64String($beforeDefault)) '无需卸载逐字保留当前禁用状态及另一条路线'
    Assert-Route ((Get-JobsPackageState -PackagePath $package -DeploymentMode build).Enabled) '卸载未启用路线不会移除另一条生效路线'
    $installed = & $module { param($Path) Invoke-JobsPackageChange -PackagePath $Path -Mode Install -DeploymentMode installed } $package
    $buildRoot = Join-Path $package 'work/JobsExtensionBuild'
    $ownerPath = Join-Path $buildRoot 'build-owner.json'
    $ownerBytes = [IO.File]::ReadAllBytes($ownerPath)
    Write-Fixture $ownerPath '{"Id":"another-feature","PackagePath":"unknown"}'
    Assert-Rejected { Clear-JobsPackageBuildArtifacts -PackagePath $package } '归属标记不匹配时禁止删除工作区'
    [IO.File]::WriteAllBytes($ownerPath, $ownerBytes)
    $lock = [IO.File]::Open((Join-Path $env:LOCALAPPDATA 'Jobs/WindowsExtension/manage.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try { Assert-Rejected { Clear-JobsPackageBuildArtifacts -PackagePath $package } '另一个事务持锁时清理拒绝执行' } finally { $lock.Dispose() }
    $link = Join-Path $buildRoot 'external-link'
    $outside = Join-Path $temp 'outside/sentinel'
    Write-Fixture $outside 'preserve'
    $linked = $false
    try { [void](New-Item -ItemType SymbolicLink -Path $link -Target (Split-Path -Parent $outside) -ErrorAction Stop); $linked = $true } catch { Write-Host 'SKIP: 创建测试链接需要权限。' }
    if ($linked) {
        Assert-Rejected { Clear-JobsPackageBuildArtifacts -PackagePath $package } '子项为链接时禁止递归删除'
        Assert-Route ([IO.File]::ReadAllText($outside) -ceq 'preserve') '拒绝清理后外部目标保持原样'
        Remove-Item -LiteralPath $link -Force
    }
    Clear-JobsPackageBuildArtifacts -PackagePath $package
    Assert-Route (-not (Test-Path (Join-Path $package 'work/JobsExtensionBuild'))) '独立清理删除专用编译工作区'
    Assert-Route (Test-Path (Join-Path $build.ReleasePath 'Scripts/Invoke.ps1')) '独立清理保留临时路线既有 release 与脚本'
    Assert-Route (Test-Path (Join-Path $installed.Root 'settings.json')) '清理保留已安装状态配置'
    Assert-Route (Test-Path (Join-Path $package 'Scripts/Build.ps1')) '清理保留源码与安装管理入口'
    $worker = Join-Path $root 'Scripts/ManagementWorker.ps1'
    $fake = @'
function Invoke-JobsPackageChange {
    param($PackagePath, $Mode, $DeploymentMode)
    Add-Content -LiteralPath (Join-Path $PackagePath 'called') -Value ($Mode + ':' + $DeploymentMode)
    $stop = Join-Path $PackagePath 'stop-target'
    if (Test-Path $stop) { [IO.File]::WriteAllText(([IO.File]::ReadAllText($stop)), 'requested') }
    [Threading.Thread]::Sleep(80)
    [IO.File]::WriteAllText((Join-Path $PackagePath 'transaction-finished'), 'committed')
    if (Test-Path (Join-Path $PackagePath 'fail')) { throw 'isolated-failure' }
    [pscustomobject]@{ BuildPath = (Join-Path $PackagePath 'fake-build') }
}
function Clear-JobsPackageBuildArtifacts {
    param($PackagePath, $BuildPath)
    if (Test-Path (Join-Path $PackagePath 'cleanup-fail')) { throw 'isolated-cleanup-refused' }
    [IO.File]::WriteAllText((Join-Path $PackagePath 'cleaned'), [string]$BuildPath)
}
Export-ModuleMember -Function Invoke-JobsPackageChange, Clear-JobsPackageBuildArtifacts
'@
    $plan = @()
    foreach ($id in @('worker-one', 'worker-two')) {
        $path = Join-Path $temp $id
        Write-Fixture (Join-Path $path 'Extension.json') ('{"Id":"' + $id + '"}')
        Write-Fixture (Join-Path $path 'Scripts/PackageInstaller.psm1') $fake
        $plan += [pscustomobject]@{ Id = $id; Label = $id; PackagePath = $path; Mode = 'Install'; DisplayMode = 'Install'; FeatureIds = @($id) }
    }
    function Invoke-IsolatedWorker {
        param([string]$Route, [bool]$Cleanup, [string]$StopPath)
        $requestPath = Join-Path $temp ('request-' + [guid]::NewGuid().ToString('N') + '.json')
        Write-Fixture $requestPath (ConvertTo-Json -InputObject @{ Plan = $plan; DeploymentMode = $Route; AutoCleanup = $Cleanup; StopRequestPath = $StopPath } -Depth 8)
        $lines = @(& (Get-Process -Id $PID).Path -NoLogo -NoProfile -NonInteractive -File $worker -RequestPath $requestPath 2>&1)
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = (($lines | ForEach-Object { [string]$_ }) -join "`n") }
    }
    $run = Invoke-IsolatedWorker build $true ''
    Assert-Route ($run.ExitCode -eq 0 -and (Get-Content (Join-Path $temp 'worker-one/called') -Raw).Contains('Install:build')) 'worker 显式把 build 路线传至安装器'
    Assert-Route (-not (Test-Path (Join-Path $temp 'worker-one/cleaned'))) 'build 路线即使收到清理标志也不清理'
    $run = Invoke-IsolatedWorker installed $true ''
    Assert-Route ($run.ExitCode -eq 0 -and (Test-Path (Join-Path $temp 'worker-one/cleaned'))) 'installed 成功后才清理本轮 BuildPath'
    Write-Fixture (Join-Path $temp 'worker-one/cleanup-fail') 'locked'
    $run = Invoke-IsolatedWorker installed $true ''
    Assert-Route ($run.ExitCode -eq 0 -and $run.Text.Contains('安装成功，清理失败') -and -not $run.Text.Contains('"State":"Failed"')) '自动清理安全拒绝不把已成功安装标为失败'
    Assert-Route ($run.Text.Contains('"State":"Succeeded"')) '自动清理拒绝后安装仍发出成功事件'
    $plan[0].Mode = 'Cleanup'; $plan[1].Mode = 'Cleanup'
    $run = Invoke-IsolatedWorker installed $false ''
    Assert-Route ($run.ExitCode -ne 0 -and $run.Text.Contains('"State":"Failed"')) '独立清理失败仍按清理失败报告'
    $plan[0].Mode = 'Install'; $plan[1].Mode = 'Install'
    Remove-Item (Join-Path $temp 'worker-one/cleanup-fail')

    Remove-Item (Join-Path $temp 'worker-one/cleaned')
    Write-Fixture (Join-Path $temp 'worker-one/fail') 'fail'
    $run = Invoke-IsolatedWorker installed $true ''
    Assert-Route ($run.ExitCode -ne 0 -and -not (Test-Path (Join-Path $temp 'worker-one/cleaned'))) '安装失败保留本轮构建产物'
    Assert-Route ($run.Text.Contains('isolated-failure') -and $run.Text.Contains('worker-two')) '单包失败仍继续后续包'
    Remove-Item (Join-Path $temp 'worker-one/fail')
    Remove-Item (Join-Path $temp 'worker-two/called')
    $stopPath = Join-Path $temp 'stop-after-current'
    Write-Fixture (Join-Path $temp 'worker-one/stop-target') $stopPath
    $run = Invoke-IsolatedWorker installed $false $stopPath
    Assert-Route ($run.ExitCode -eq 0 -and $run.Text.Contains('"State":"Stopped"') -and $run.Text.Contains('"State":"Skipped"')) '停止不是失败，余项明确发出未执行事件'
    Assert-Route (Test-Path (Join-Path $temp 'worker-one/transaction-finished')) '停止请求保留当前事务至结束'
    Assert-Route (-not (Test-Path (Join-Path $temp 'worker-two/called'))) '停止后不再调用下一包'
    Remove-Item (Join-Path $temp 'worker-one/called')
    $run = Invoke-IsolatedWorker installed $false $stopPath
    Assert-Route (-not (Test-Path (Join-Path $temp 'worker-one/called'))) '启动前已有停止请求时所有项目均不执行'
    Remove-Item $stopPath
    $plan[0].Mode = 'Cleanup'; $plan[1].Mode = 'Cleanup'
    $run = Invoke-IsolatedWorker installed $false ''
    Assert-Route ($run.ExitCode -eq 0 -and -not (Test-Path (Join-Path $temp 'worker-one/called'))) '独立清理不调用安装器事务'
    $panel = Import-Module (Join-Path $root 'Scripts/Installer.psm1') -PassThru -Force -DisableNameChecking
    $progress = & $panel { Get-JobsManagementProgress ([pscustomobject]@{ FeatureStates = @{ first = 'Succeeded'; second = 'Skipped'; third = 'Skipped' } }) }
    Assert-Route ($progress.Finished -eq 1 -and $progress.Percent -eq '33.3') '未执行项目不计失败或完成百分比'
    $stopState = [pscustomobject]@{ Running = $true; Operation = 'Install'; StopRequested = $false; StopRequestPath = (Join-Path $temp 'panel-stop'); ConfirmButton = [pscustomobject]@{ Enabled = $true; Text = '停止安装' } }
    & $panel {
        param($State)
        function script:Add-JobsManagementLog { param($State, $Text) }
        function script:Update-JobsManagementProgress { param($State) }
        Request-JobsManagementStop $State
    } $stopState
    Assert-Route ($stopState.StopRequested -and -not $stopState.ConfirmButton.Enabled -and (Test-Path $stopState.StopRequestPath)) 'GUI 停止只写请求文件并等待，不结束进程'

} finally {
    $env:LOCALAPPDATA = $oldLocal
    foreach ($name in @('module', 'runtime', 'buildRuntime', 'nestedRuntime', 'panel')) { $value = Get-Variable $name -ValueOnly -ErrorAction SilentlyContinue; if ($null -ne $value) { Remove-Module $value -ErrorAction SilentlyContinue } }
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
Write-Host ('PASS: DeploymentRoutes.Tests.ps1 (' + $script:assertions + ' assertions)')

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

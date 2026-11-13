# FlutterFeatureSelection.Tests.ps1 | 子菜单选择、兼容和部分卸载
# Created by Jobs on 2026年10月24日，星期六.
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
$count = 0
function Assert($value, $message) { $script:count++; if (-not $value) { throw $message } }
function Assert-Throws([scriptblock]$Body, [string]$Message) {
    $failed = $false
    try { & $Body | Out-Null } catch { $failed = $true }
    Assert $failed $Message
}
Import-Module (Join-Path $root 'Scripts/Catalog.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/FeatureActions.psm1') -Force -DisableNameChecking
$packages = @(Get-JobsFeaturePackages -Root $root)
$features = @(Get-JobsSelectableFeatures -Packages $packages)
$actions = @(Get-JobsFlutterActionCatalog)
Assert ($actions.Count -eq 38) '列出全部现有 Windows Flutter 叶动作'
$stableOrder = 'run,pub-get,android-dependencies,ohos-dependencies,native-dependencies,flutter-precache,web-dependencies,extract,import-dependencies,export-gradle-dependencies,import-gradle-dependencies,export-ohos-dependencies,import-ohos-dependencies,export-native-dependencies,import-native-dependencies,export-precache-dependencies,import-precache-dependencies,export-web-dependencies,import-web-dependencies,sdk-version,sdk-manage,ohos-sdk-manage,java-manage,gradle-download,project-setup,package,build-harmony,codegen,native-doctor,harmony-doctor,maintenance,repair-android,repair-imports,repair-namespace,export-private-dependencies,import-private-dependencies,export-all-dependencies,import-all-dependencies'
Assert (($actions.Id -join ',') -ceq $stableOrder) '重分组不改原34个ID与偏移保持顺序，新私库动作追加'
$groupContract = [ordered]@{
    '📥 拉取Flutter项目工程相关依赖' = @('pub-get','android-dependencies','ohos-dependencies','web-dependencies')
    '🧩 提取Flutter项目工程依赖' = @('extract','export-gradle-dependencies','export-ohos-dependencies','export-native-dependencies','export-precache-dependencies','export-web-dependencies','export-private-dependencies','export-all-dependencies')
    '📤 导入Flutter项目工程依赖' = @('import-dependencies','import-gradle-dependencies','import-ohos-dependencies','import-native-dependencies','import-precache-dependencies','import-web-dependencies','import-private-dependencies','import-all-dependencies')
    '🔀 安装/切换Flutter运行环境' = @('sdk-manage','ohos-sdk-manage','java-manage')
    '🧱 Flutter 资源与构建依赖' = @('native-dependencies','flutter-precache','gradle-download')
    '🏥 Flutter项目体检' = @('sdk-version','native-doctor','harmony-doctor')
}
foreach ($group in $groupContract.Keys) {
    $actualIds = @($actions | Where-Object { $_.Group -ceq $group } | ForEach-Object Id)
    Assert (($actualIds -join ',') -ceq ($groupContract[$group] -join ',')) ('精确父分组及完整叶集合：' + $group)
}
Assert (@($actions | Where-Object { $_.Id -ceq 'native-dependencies' })[0].Group -ceq '🧱 Flutter 资源与构建依赖') '组合操作归入资源与构建依赖组'
Assert (@($actions | Where-Object { $_.Id -ceq 'native-dependencies' })[0].Label -ceq '🧱 准备原生库与构建依赖（组合操作）') '组合操作在菜单与管理面板醒目标识'
$exactLabels = @{
    'sdk-manage' = '🔀 安装/切换Flutter SDK'
    'ohos-sdk-manage' = '🕊️ 安装/切换Flutter@OpenHarmony SDK'
    'java-manage' = '☕ 安装/切换Java SDK'
    'flutter-precache' = '🗃️ 下载Flutter平台资源'
    'sdk-version' = '🔎 查看当前Flutter项目工程的SDK版本'
}
foreach ($id in $exactLabels.Keys) { Assert (@($actions | Where-Object { $_.Id -ceq $id })[0].Label -ceq $exactLabels[$id]) ('精确叶显示名：' + $id) }
Assert ($features.Count -eq $packages.Count + 37) '总面板展开单包而不重复显示包级复选框'
Assert (@($features | Where-Object { $_.Id -ceq 'flutter-tools' }).Count -eq 0) '只有可实际执行的子功能可选'
$header = [IO.File]::ReadAllText((Join-Path $root 'JobsFlutterTools/Scripts/FlutterToolsMenu.h'))
$entryBlock = [regex]::Match($header, '(?s)static const Entry Entries\[\]\s*=\s*\{(.*?)\n\};').Groups[1].Value
$matches = [regex]::Matches($entryBlock, '\{L"([a-z-]+)", L"([^"]+)"\}')
Assert ($matches.Count -eq $actions.Count) '选择目录与原生动作数量相同'
for ($i = 0; $i -lt $actions.Count; $i++) {
    Assert ($matches[$i].Groups[1].Value -ceq $actions[$i].Id -and $matches[$i].Groups[2].Value -ceq $actions[$i].Label) ('动作标识和标签同源核对：' + $actions[$i].Id)
    $plan = @(Get-JobsPackageOperationPlan -Packages $packages -Selected @('flutter-' + $actions[$i].Id) -Installed @() -Mode Install)
    Assert ($plan.Count -eq 1 -and $plan[0].Id -ceq 'flutter-tools' -and @($plan[0].ActionIds).Count -eq 1 -and $plan[0].ActionIds[0] -ceq $actions[$i].Id) '首次逐项安装只启用所选动作'
}
$dependencyActions = @('android-dependencies','ohos-dependencies','native-dependencies','flutter-precache','web-dependencies')
foreach ($id in $dependencyActions) {
    Assert (@($actions | Where-Object { $_.Id -ceq $id }).Count -eq 1) ('每类依赖各有单独菜单动作：' + $id)
    $plan = @(Get-JobsPackageOperationPlan -Packages $packages -Selected @('flutter-' + $id) -Installed @('flutter-run', ('flutter-' + $id)) -Mode Uninstall)
    Assert ($plan.Count -eq 1 -and $plan[0].Mode -ceq 'Install' -and ($plan[0].ActionIds -join ',') -ceq 'run') ('独立卸载依赖叶保留运行：' + $id)
}
foreach ($id in @('pods-dependencies','spm-dependencies')) {
    Assert (@($actions | Where-Object { $_.Id -ceq $id }).Count -eq 0) ('Windows 不增加 Apple 专属依赖入口：' + $id)
    Assert-Throws { Expand-JobsFeatureSelection -Packages $packages -Selected @('flutter-' + $id) } '不支持的平台叶不能进入安装计划'
}
Assert (@($actions | Where-Object { $_.Id -ceq 'pub-get' })[0].Label -ceq '📥 拉取 Flutter Pub 依赖') 'Pub 依赖与平台原生依赖明确区分'
Assert (@($actions | Where-Object { $_.Id -ceq 'gradle-download' })[0].Label -ceq '📚 下载Gradled分发与构建插件') 'Gradle 入口明确分发与构建插件范围'
$combined = @(Get-JobsPackageOperationPlan -Packages $packages -Selected @('flutter-codegen') -Installed @('flutter-run') -Mode Install)
Assert ($combined.Count -eq 1 -and ($combined[0].ActionIds -join ',') -ceq 'run,codegen') '安装一个动作不会关闭已启用的兄弟动作'
$replace = @(Get-JobsPackageOperationPlan -Packages $packages -Selected @('flutter-codegen') -Installed @('flutter-run') -Mode Configure)
Assert ($replace.Count -eq 1 -and ($replace[0].ActionIds -join ',') -ceq 'codegen') '显式配置模式仍按完整选择替换'
$legacy = @(Expand-JobsFeatureSelection -Packages $packages -Selected @('flutter-tools'))
Assert ($legacy.Count -eq 38) '旧总体功能标识保持全选兼容'
$plan = @(Get-JobsPackageOperationPlan -Packages $packages -Selected @('flutter-run') -Installed @('flutter-run', 'flutter-codegen') -Mode Uninstall)
Assert ($plan.Count -eq 1 -and $plan[0].Mode -ceq 'Install' -and @($plan[0].ActionIds).Count -eq 1 -and $plan[0].ActionIds[0] -ceq 'codegen') '部分卸载仅保留其它叶功能'
$plan = @(Get-JobsPackageOperationPlan -Packages $packages -Selected @('flutter-run') -Installed @('flutter-run') -Mode Uninstall)
Assert ($plan.Count -eq 1 -and $plan[0].Mode -ceq 'Uninstall') '移除最后一项时卸载整个菜单包'
Assert (@(Get-JobsPackageOperationPlan -Packages $packages -Selected @() -Installed @('flutter-run') -Mode Install).Count -eq 0) '安装不选整个Flutter组时保留已安装组'
$plan = @(Get-JobsPackageOperationPlan -Packages $packages -Selected @() -Installed @('flutter-run') -Mode Configure)
Assert ($plan.Count -eq 1 -and $plan[0].Mode -ceq 'Uninstall') '配置全不选可关闭Flutter组'
Assert-Throws { Expand-JobsFeatureSelection -Packages $packages -Selected @('flutter-unknown') } '未知叶动作拒绝进入计划'
Assert (@(Get-JobsFlutterStateActionIds -Settings ([pscustomobject]@{ Version = 2 })).Count -eq 38) '旧设置缺ActionIds保持全开'
Assert (@(Get-JobsFlutterStateActionIds -Settings ([pscustomobject]@{ ActionIds = @('codegen') }))[0] -ceq 'codegen') '单项数组只启用该动作'
Assert (@(Get-JobsFlutterStateActionIds -Settings ([pscustomobject]@{ ActionIds = @() })).Count -eq 0) '空数组不复活任何动作'
Assert-Throws { Get-JobsFlutterStateActionIds -Settings ([pscustomobject]@{ ActionIds = 'run' }) } '标量配置拒绝'
Assert-Throws { Get-JobsFlutterStateActionIds -Settings ([pscustomobject]@{ ActionIds = @('run', 'run') }) } '重复配置拒绝'
Assert-Throws { Get-JobsFlutterStateActionIds -Settings ([pscustomobject]@{ ActionIds = @('unknown') }) } '未知配置拒绝'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('jobs-flutter-selection-' + [guid]::NewGuid().ToString('N'))
try {
    [void][IO.Directory]::CreateDirectory((Join-Path $fixture 'Scripts'))
    $stub = @'
function Invoke-JobsPackageChange {
    param([string]$PackagePath, [string]$Mode, [string[]]$ActionIds)
    if ($Mode -cne 'Install' -or @($ActionIds).Count -ne 2 -or ($ActionIds -join ',') -cne 'run,codegen') { throw 'leaf choices were lost in lifecycle dispatch' }
}
Export-ModuleMember -Function Invoke-JobsPackageChange
'@
    [IO.File]::WriteAllText((Join-Path $fixture 'Scripts/PackageInstaller.psm1'), $stub)
    $result = Invoke-JobsPackageOperations -Plan @([pscustomobject]@{ Id = 'flutter-tools'; PackagePath = $fixture; Mode = 'Install'; ActionIds = @('run', 'codegen') })
    Assert ($result.Success -and $result.Completed[0] -ceq 'Install:flutter-tools') '两项选择经真实编排调用只进入一次包生命周期且保持数组'
} finally {
    foreach ($loaded in @(Get-Module | Where-Object { $_.Path -and $_.Path.StartsWith($fixture, [StringComparison]::OrdinalIgnoreCase) })) { Remove-Module $loaded }
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
    $ui = Import-Module (Join-Path $root 'Scripts/Installer.psm1') -PassThru -DisableNameChecking
    $state = & $ui { param($Items) New-JobsFeatureSelectionForm -Packages $Items -Selected @() -Mode Install } $features
    try {
        Assert (@($state.Checks).Count -eq $features.Count -and $state.Groups.Count -eq 9) '真实面板包含全部叶功能及用途分组'
        Assert ($state.ContentPanel.AutoScroll -and $state.Footer.Dock -eq [Windows.Forms.DockStyle]::Bottom) '仅内容区滚动且操作区固定'
        $group = @($state.Groups | Where-Object { $_.Name -ceq '🏥 Flutter项目体检' })[0]
        $click = $group.All.GetType().GetMethod('OnClick', [Reflection.BindingFlags]'Instance,NonPublic')
        [void]$click.Invoke($group.All, @([EventArgs]::Empty))
        Assert (@($state.Checks | Where-Object Checked).Count -eq 3 -and $group.Counter.Text -eq '已选 3 / 3') '组内全选只勾选本组且更新计数'
        [void]$click.Invoke($group.None, @([EventArgs]::Empty))
        Assert (@($state.Checks | Where-Object Checked).Count -eq 0 -and -not $state.ConfirmButton.Enabled -and $null -eq $state.Form.AcceptButton) '组内全不选恢复空选门禁'
    } finally { $state.Form.Dispose(); $state.ToolTip.Dispose(); $state.Font.Dispose() }
}
Write-Host ('PASS: FlutterFeatureSelection.Tests.ps1 (' + $count + ' assertions; no registry writes)')

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

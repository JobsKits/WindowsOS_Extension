# FileVolumes.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年10月28日，星期三.
# 仅临时目录、真实文件流、注册计划和独立打包；不注册或打开菜单。
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
. (Join-Path $root 'JobsFileVolumes/Scripts/FileVolumes.ps1')
. (Join-Path $root 'JobsFileVolumes/Scripts/SelectionRequest.ps1')
. (Join-Path $PSScriptRoot 'NativeFixtures.ps1')
$script:assertions = 0
function Assert-Volumes {
    param([bool]$Condition, [string]$Message)
    $script:assertions++
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
}
function Assert-VolumesThrows {
    param([scriptblock]$Run, [string]$Message)
    $threw = $false
    try { & $Run | Out-Null } catch { $threw = $true }
    Assert-Volumes $threw $Message
}
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('JobsVolumes-' + [guid]::NewGuid().ToString('N'))
try {
    [void][IO.Directory]::CreateDirectory($temporary)
    $file = Join-Path $temporary "中文 & %TEMP% ' `$() [x]@extra.bin"
    $data = New-Object byte[] 3145733
    $random = New-Object Random 492
    $random.NextBytes($data)
    [IO.File]::WriteAllBytes($file, $data)
    $digest = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    $split = Invoke-JobsFileSplit -Path $file -LimitBytes 300000
    Assert-Volumes ($split -ceq ($file + '.chunks')) '拆分采用完整源文件名.chunks目录'
    $parts = @(Get-ChildItem -LiteralPath $split -File)
    Assert-Volumes ($parts.Count -eq 11) '均匀拆分为ceil(size/limit)卷'
    Assert-Volumes (@($parts | Where-Object { $_.Length -gt 300000 -or $_.Length -lt 1 }).Count -eq 0) '每卷正长度且不超过上限'
    Assert-Volumes ((Get-FileHash -LiteralPath $file).Hash -ceq $digest) '拆分保留源文件且内容不变'
    $reverse = @($parts | Sort-Object Name -Descending | ForEach-Object FullName)
    $group = Get-JobsVolumeGroup -Paths $reverse
    Assert-Volumes ($group.Files[0].Name.EndsWith('@1of11') -and $group.Files[10].Name.EndsWith('@11of11')) '按数值排序而非字典序或选择序'
    $merged = Invoke-JobsFileMerge -Paths $reverse
    Assert-Volumes ((Get-FileHash -LiteralPath $merged).Hash -ceq $digest) '跨块真实随机字节拆分再合并SHA256一致'
    Assert-Volumes (@(Get-ChildItem -LiteralPath $split -File).Count -eq 12) '合并后原有11分卷保留'
    Assert-VolumesThrows { Invoke-JobsFileMerge -Paths $reverse } '同名合并目标不覆盖'
    Assert-Volumes ((Get-FileHash -LiteralPath $merged).Hash -ceq $digest) '拒绝覆盖后原有目标不变'
    Assert-VolumesThrows { Invoke-JobsFileSplit -Path $file -LimitBytes 300000 } '同名分卷目录不覆盖'
    foreach ($limit in @([long]0, [long]-1, [long]$data.Length, [long]($data.Length + 1))) {
        Assert-VolumesThrows { Invoke-JobsFileSplit -Path $file -LimitBytes $limit } '零负数/文件不大于上限均拒绝'
    }
    Assert-VolumesThrows { Get-JobsVolumeGroup -Paths @($reverse[0]) } '单卷不能触发合并'
    Assert-VolumesThrows { Get-JobsVolumeGroup -Paths @($reverse[0], $reverse[0]) } '重复路径拒绝'
    Assert-VolumesThrows { Get-JobsVolumeGroup -Paths @($reverse[0], $reverse[1]) } '不扫描目录补齐未选分卷'
    Assert-VolumesThrows { Get-JobsVolumeGroup -Paths @($reverse + $file) } '混入普通文件拒绝'
    Assert-VolumesThrows { Get-JobsVolumeFile $temporary } '目录拒绝'
    $bad = Join-Path $temporary 'bad.bin@1of2'
    $bad2 = Join-Path $temporary 'bad.bin@2of2'
    [IO.File]::WriteAllBytes($bad, [byte[]]@(1)); [IO.File]::WriteAllBytes($bad2, [byte[]]@())
    Assert-VolumesThrows { Get-JobsVolumeGroup @($bad, $bad2) } '空卷拒绝'
    [IO.File]::WriteAllBytes($bad2, [byte[]]@(2))
    $duplicate = Join-Path $temporary 'bad.bin@01of2'
    [IO.File]::WriteAllBytes($duplicate, [byte[]]@(3))
    Assert-VolumesThrows { Get-JobsVolumeGroup @($bad, $duplicate) } '补零后的编号重复拒绝'
    foreach ($name in @('CON@1of2', 'nul.txt@1of2', 'com1@1of2', 'abc.@1of2', 'abc @1of2', '.@1of2', '..@1of2', 'a@0of2', 'a@3of2', 'a@1of0', 'a@1000000000of2', "bad`nname@1of2")) {
        Assert-VolumesThrows { Get-JobsVolumePart $name } ('非法卷名拒绝：' + $name)
    }
    $one = Get-JobsVolumePart 'x@nested.tar.gz@001of002'
    Assert-Volumes ($one.Name -ceq 'x@nested.tar.gz' -and $one.Index -eq 1 -and $one.Total -eq 2) '最后一个@解析且兼容补零'
    # Windows共享锁真实验证；Mac / PS7 的文件共享语义不推断为NTFS锁。
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        $writer = [IO.File]::Open($bad, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::Read)
        try { Assert-VolumesThrows { Invoke-JobsFileMerge @($bad, $bad2) } '输入已有写入者时停止且不创建结果' } finally { $writer.Dispose() }
    }
    $link = Join-Path $temporary 'linked@1of2'
    if (New-JobsTestSymbolicLink -Path $link -Target $bad) { Assert-VolumesThrows { Get-JobsVolumeFile $link } '真实符号链接拒绝' }
    $snapshot = Get-JobsVolumeFile $bad
    [IO.File]::AppendAllText($bad, 'changed')
    Assert-VolumesThrows { Assert-JobsVolumeUnchanged $snapshot } '输入状态变化拒绝发布'
    # 流失败必须保留独占候选、源文件及全部分卷；不产生看似完整的结果。
    $functionBody = ${function:Add-JobsVolumeStream}
    function Add-JobsVolumeStream { throw 'injected read failure' }
    try { Assert-VolumesThrows { Invoke-JobsFileMerge -Paths @($bad, $bad2) } '中途失败向调用者报告失败' }
    finally { ${function:Add-JobsVolumeStream} = $functionBody }
    Assert-Volumes (-not [IO.File]::Exists((Join-Path $temporary 'bad.bin'))) '失败候选不会发布为完整文件'
    Assert-Volumes (@(Get-ChildItem -LiteralPath $temporary -Force -Filter '.JobsMerge-*.partial').Count -eq 1) '失败候选保留供排查'
    $module = Import-Module (Join-Path $root 'JobsFileVolumes/Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
    $manifest = Get-Content -LiteralPath (Join-Path $root 'JobsFileVolumes/Extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $plan = @(Get-JobsPackageRegistryPlan -Manifest $manifest -ReleasePath $temporary -PowerShellPath 'C:\Windows\powershell.exe')
    Assert-Volumes ($plan.Count -eq 2 -and $plan[0].Key -ceq 'Software\Classes\*\shellex\ContextMenuHandlers\Jobs.WindowsExtension.file-volumes') '只注册文件动态handler和本包CLSID'
    Assert-Volumes ($plan[1].InProcServer -ceq (Join-Path $temporary 'bin/JobsFileVolumesContextMenu.dll')) '原生DLL归本包且无静态菜单降级'
    Remove-Module $module
    $requestDirectory = Join-Path ([IO.Path]::GetTempPath()) 'JobsFileVolumes'
    [void][IO.Directory]::CreateDirectory($requestDirectory)
    $requests = @()
    try {
        $request = Join-Path $requestDirectory ('selection-' + [guid]::NewGuid().ToString() + '.json')
        $requests += $request
        $json = ConvertTo-Json -InputObject @($file, $bad) -Compress
        [IO.File]::WriteAllText($request, $json, (New-Object Text.UTF8Encoding($false)))
        $selection = @(Read-JobsVolumeRequest $request)
        Assert-Volumes ($selection.Count -eq 2 -and $selection[0] -ceq $file -and $selection[1] -ceq $bad) 'JSON精确路径含中文和脚本符号按数据往返'
        Assert-Volumes (-not [IO.File]::Exists($request)) '成功消费只删除本次临时请求'
        foreach ($invalid in @('[]', '[null]', '[42]', '[""]', '"path"', '{"path":"x"}', '[["x"]]', '["x",["y"]]', '["x"')) {
            $request = Join-Path $requestDirectory ('selection-' + [guid]::NewGuid().ToString() + '.json')
            $requests += $request
            [IO.File]::WriteAllText($request, $invalid, (New-Object Text.UTF8Encoding($false)))
            Assert-VolumesThrows { Read-JobsVolumeRequest $request } ('无效清单拒绝：' + $invalid)
            Assert-Volumes ([IO.File]::Exists($request)) '无效请求不擅自删除文件'
        }
        $outside = Join-Path $temporary ('selection-' + [guid]::NewGuid().ToString() + '.json')
        [IO.File]::WriteAllText($outside, '["x"]')
        Assert-VolumesThrows { Read-JobsVolumeRequest $outside } '拒绝本包临时目录之外请求'
        Assert-Volumes ([IO.File]::Exists($outside)) '目录之外文件保持不动'
    } finally {
        foreach ($request in $requests) { if ([IO.File]::Exists($request)) { [IO.File]::Delete($request) } }
    }
    [Console]::WriteLine(('PASS: FileVolumes.Tests.ps1 ({0} assertions)' -f $script:assertions))
} finally {
    if ([IO.Directory]::Exists($temporary)) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

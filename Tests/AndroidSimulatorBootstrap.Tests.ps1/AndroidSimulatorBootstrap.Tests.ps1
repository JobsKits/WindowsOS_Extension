# AndroidSimulatorBootstrap.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年10月23日，星期五.
[CmdletBinding()]
param()
# JOBS_SOURCE_LAYOUT_ROOT_V1：只解析本文件逻辑目录，发布 flat 副本保持原资源基准。
$script:JobsLayoutAndroidSimulatorBootstrapTestsRoot = $(if ([IO.Path]::GetFileName($PSScriptRoot) -ceq 'AndroidSimulatorBootstrap.Tests.ps1') { Split-Path -Parent $PSScriptRoot } else { $PSScriptRoot })

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
$root = Split-Path -Parent ${script:JobsLayoutAndroidSimulatorBootstrapTestsRoot}
$script:assertions = 0
function Assert-Bootstrap { param([bool]$Condition, [string]$Why) $script:assertions++; if (-not $Condition) { throw ('FAIL: ' + $Why) } }
function Assert-BootstrapThrows { param([scriptblock]$Action, [string]$Why) $threw = $false; try { & $Action | Out-Null } catch { $threw = $true }; Assert-Bootstrap $threw $Why }
$path = Join-Path $root 'JobsAndroidSimulatorCreator/Scripts/Action.psm1'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ("JobsAndroidBootstrap 中文 & 100% ' " + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$oldJavaHome = $env:JAVA_HOME; $oldAndroidHome = $env:ANDROID_HOME; $oldSdkRoot = $env:ANDROID_SDK_ROOT
$module = $null
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $payload = Join-Path $temporary 'payload'
    [void][IO.Directory]::CreateDirectory((Join-Path $payload 'jdk-21-fixture/bin'))
    [IO.File]::WriteAllText((Join-Path $payload 'jdk-21-fixture/bin/java.exe'), 'fixture executable')
    $zip = Join-Path $temporary 'java.zip'
    [IO.Compression.ZipFile]::CreateFromDirectory($payload, $zip)
    $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    $metadata = @([ordered]@{ vendor = 'eclipse'; version = @{ major = 21 }; binary = @{ architecture = 'x64'; os = 'windows'; image_type = 'jdk'; package = @{ link = 'https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21-fixture/OpenJDK21U-jdk_x64_windows_hotspot_21-fixture.zip'; checksum = $hash } } }) | ConvertTo-Json -Depth 6
    $javaRoot = Join-Path $temporary 'user-java-on-SDK-independent-volume'
    [void][IO.Directory]::CreateDirectory((Join-Path $javaRoot 'old-jdk'))
    [IO.File]::WriteAllText((Join-Path $javaRoot 'old-jdk/keep.txt'), 'existing JDK stays')
    $module = Import-Module $path -PassThru -DisableNameChecking -Force
    & $module {
        param($Parent, $Archive, $Metadata)
        $script:Parent = $Parent; $script:Archive = $Archive; $script:Metadata = $Metadata; $script:Downloads = @(); $script:JavaFails = $false; $script:CorruptDownloads = 0
        function script:Get-JobsAndroidJavaRoot { return $script:Parent }
        function script:Receive-JobsSdkWebFile {
            param($Uri, $Destination, $TimeoutSeconds)
            $OutFile = $Destination
            $script:Downloads += @{ Uri = $Uri; OutFile = $OutFile }
            if ($Uri -like 'https://api.adoptium.net/*') { [IO.File]::WriteAllText($OutFile, $script:Metadata) }
            elseif ($script:CorruptDownloads -gt 0) { $script:CorruptDownloads--; [IO.File]::WriteAllText($OutFile, 'incomplete fixture transfer') }
            else { Copy-Item -LiteralPath $script:Archive -Destination $OutFile }
        }
        function script:Start-Sleep { param($Seconds) }
        function script:Invoke-JobsProcess {
            param($FilePath, $Arguments, $TimeoutSeconds)
            if ($script:JavaFails) { return [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = 'broken Java' } }
            return [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = 'openjdk version "21.0.9" 2025-10-21 LTS' }
        }
    } $javaRoot $zip $metadata
    $java = & $module { Install-JobsAndroidJava }
    Assert-Bootstrap (Test-Path -LiteralPath $java -PathType Leaf) 'SHA-256 验证后的用户目录 Java ZIP 安装成功'
    Assert-Bootstrap ((Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $java))) -eq $javaRoot) 'Java 安装仅位于当前用户工具目录'
    $downloads = @(& $module { $script:Downloads })
    Assert-Bootstrap ($downloads.Count -eq 2 -and $downloads[0].Uri -like 'https://api.adoptium.net/v3/assets/latest/21/*') '仅查询官方 Temurin 21 元数据和选定归档'
    foreach ($download in $downloads) {
        Assert-Bootstrap ((Split-Path -Parent (Split-Path -Parent $download.OutFile)) -eq $javaRoot) 'Java 下载/解压stage与最终JDK同卷'
    }
    Assert-Bootstrap (@(Get-ChildItem -LiteralPath $javaRoot -Force | Where-Object { $_.Name -like '.jobs-stage-*' }).Count -eq 0) 'Java 成功后清理本次 stage'
    Assert-Bootstrap ([IO.File]::ReadAllText((Join-Path $javaRoot 'old-jdk/keep.txt')) -eq 'existing JDK stays') '已有 Java 完整保留'
    Assert-Bootstrap ($env:JAVA_HOME -eq $oldJavaHome) '用户目录 Java 安装不修改 JAVA_HOME'
    & $module { $script:Metadata = $script:Metadata.Replace('https://github.com/adoptium/', 'https://untrusted.example/adoptium/') }
    Assert-BootstrapThrows { & $module { Install-JobsAndroidJava } } '非官方归档地址在下载前拒绝'
    Assert-Bootstrap (Test-Path -LiteralPath $java) '失败不影响上一次健康Java'
    $verifiedArchive = Join-Path $temporary 'verified-after-corrupt-transfer.zip'
    $downloadsBefore = & $module { $script:CorruptDownloads = 1; $script:Downloads.Count }
    & $module { param($Destination, $Hash) Receive-JobsAndroidVerifiedArchive -Uri 'https://fixture.invalid/sdk.zip' -Destination $Destination -Algorithm SHA256 -Checksum $Hash } $verifiedArchive $hash
    Assert-Bootstrap ((Get-FileHash -LiteralPath $verifiedArchive -Algorithm SHA256).Hash -eq $hash) '损坏归档持续重取并校验成功'
    Assert-Bootstrap ((& $module { $script:Downloads.Count }) -eq $downloadsBefore + 2) '摘要失败仅重取归档，未重放安装'
    Assert-Bootstrap (@(Get-ChildItem -LiteralPath $javaRoot -Force | Where-Object { $_.Name -like '.jobs-stage-*' }).Count -gt 0) '失败暂存保留供排查和续传'
    & $module { param($Metadata) $script:Metadata = $Metadata; $script:JavaFails = $true } $metadata
    Assert-BootstrapThrows { & $module { Install-JobsAndroidJava } } '下载后Java仍不能运行立即停止'
    Assert-Bootstrap (@(Get-ChildItem -LiteralPath $javaRoot -Directory | Where-Object { $_.Name -like 'temurin-21-*' }).Count -eq 1) '不提交未经健康检查的新JDK目录'
    Remove-Module $module
    $module = Import-Module $path -PassThru -DisableNameChecking -Force
    & $module {
        $script:InstallCount = 0
        function script:Find-JobsExecutable { param($Name) return $null }
        function script:Get-JobsAndroidJavaRoot { return 'missing-java-root-fixture' }
        function script:Test-JobsAndroidJava { param($Path) return $false }
        function script:Install-JobsAndroidJava { $script:InstallCount++; return 'installed-java-fixture' }
    }
    Assert-BootstrapThrows { & $module { Get-JobsAndroidJava -ReadOnly } } 'Check 无健康Java时报告错误'
    Assert-Bootstrap (& $module { $script:InstallCount -eq 0 }) 'Check Java 零下载/安装'
    Assert-Bootstrap ((& $module { Get-JobsAndroidJava }) -eq 'installed-java-fixture') '运行模式缺Java自动补齐'
    Assert-Bootstrap (& $module { $script:InstallCount -eq 1 }) 'Java只补齐一次'
    Remove-Module $module
    $module = Import-Module $path -PassThru -DisableNameChecking -Force
    & $module {
        $script:JavaMajor = 8; $script:ThrowNative = $false
        function script:Invoke-JobsProcess {
            param($FilePath, $Arguments, $TimeoutSeconds)
            if ($script:ThrowNative) { throw 'fixture invalid executable' }
            return [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = ('openjdk version "' + $script:JavaMajor + '.0.1"') }
        }
    }
    Assert-Bootstrap (-not (& $module { param($Java) Test-JobsAndroidJava $Java } $java)) 'Java8退出0仍不当作健康依赖'
    & $module { $script:JavaMajor = 21 }
    Assert-Bootstrap (& $module { param($Java) Test-JobsAndroidJava $Java } $java) 'Java21解析与运行均正常才复用'
    & $module { $script:ThrowNative = $true }
    Assert-Bootstrap (-not (& $module { param($Java) Test-JobsAndroidJava $Java } $java)) '坏候选原生异常作为不健康继续检查'
    $env:ANDROID_HOME = 'relative-sdk-fixture'
    Assert-BootstrapThrows { & $module { Get-JobsAndroidSdk } } '显式相对SDK路径在任何目录创建前拒绝'
    $collision = Join-Path $temporary 'SDK-is-file'
    [IO.File]::WriteAllText($collision, 'leave file unchanged')
    $env:ANDROID_HOME = $collision
    Assert-BootstrapThrows { & $module { Get-JobsAndroidSdk } } 'SDK文件碰撞停止'
    $uncreated = Join-Path $temporary 'cancel-before-ensure-sdk'
    & $module {
        param($Sdk)
        $script:IntroSdk = $Sdk; $script:InstallCount = 0
        function script:Test-JobsAndroidDesktop { param($Target) return $true }
        function script:Get-JobsAndroidArchitecture { return 'x86_64' }
        function script:Get-JobsAndroidSdk { return $script:IntroSdk }
        function script:Read-JobsAndroidInput { param($Prompt) return 'cancel' }
        function script:Get-JobsAndroidJavaRoot { return 'user-java-fixture' }
        function script:Get-JobsAndroidJava { $script:InstallCount++; throw 'must not install' }
    } $uncreated
    Assert-BootstrapThrows { & $module { Invoke-JobsAndroidSimulatorAction desktop-fixture -Create } } '入口首屏可取消自动补齐'
    Assert-Bootstrap (-not (Test-Path -LiteralPath $uncreated)) '首屏取消不创建SDK根'
    Assert-Bootstrap (& $module { $script:InstallCount -eq 0 }) '首屏取消不进入Java和下游工具安装'
    $retrySdk = Join-Path $temporary 'sdk-retry-fixture'
    & $module {
        param($Sdk)
        $script:RetrySdk = $Sdk
        $script:SdkAttempts = 0
        function script:Start-Sleep { param($Seconds) }
        function script:Invoke-JobsSdkLiveProcess {
            param($Start, $TimeoutSeconds, [switch]$Sanitize, [switch]$Acquisition)
            if (-not $Acquisition) { throw 'SDK 获取必须启用停滞超时模式' }
            $script:SdkAttempts++
            if ($script:SdkAttempts -le 4) { return [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = 'connection reset fixture' } }
            if ($script:SdkAttempts -ge 6) {
                [void][IO.Directory]::CreateDirectory((Join-Path $script:RetrySdk 'platform-tools'))
                foreach ($name in @('package.xml', 'adb.exe')) { [IO.File]::WriteAllText((Join-Path $script:RetrySdk ('platform-tools/' + $name)), 'fixture') }
            }
            return [pscustomobject]@{ ExitCode = 0; StdOut = 'sdk fixture installed'; StdErr = '' }
        }
    } $retrySdk
    $installOutput = @(& $module { Invoke-JobsAndroidTool 'fixture-java' 'fixture-tools' sdkmanager @(('--sdk_root=' + $script:RetrySdk), '--install', 'platform-tools') -Interactive })
    Assert-Bootstrap ((& $module { $script:SdkAttempts }) -eq 6) 'SDK安装失败四次及退出0但缺文件后，自动第六次成功'
    Assert-Bootstrap ($installOutput.Count -eq 0) '安装进度不污染调用方返回值'
    $listing = & $module { Invoke-JobsAndroidTool 'fixture-java' 'fixture-tools' sdkmanager @('--list', '--channel=0') }
    Assert-Bootstrap ($listing -eq 'sdk fixture installed') 'SDK远程清单在重试后返回原始机器输出'
    foreach ($component in @(@('platform-tools','adb.exe'), @('platforms;android-35','android.jar'), @('build-tools;35.0.0','aapt2.exe'), @('ndk;27.0.1','ndk-build.cmd'), @('cmake;3.22.1','bin/cmake.exe'))) {
        $attempts = & $module {
            param($Sdk, $Identifier, $Required)
            $script:SdkAttempts = 0; $script:RetrySdk = $Sdk; $script:RetryPackage = $Identifier; $script:RetryRequired = $Required
            function script:Invoke-JobsSdkLiveProcess {
                param($Start, $TimeoutSeconds, [switch]$Sanitize, [switch]$Acquisition)
                $script:SdkAttempts++
                $directory = Join-Path $script:RetrySdk ($script:RetryPackage.Replace(';', [IO.Path]::DirectorySeparatorChar))
                [void][IO.Directory]::CreateDirectory($directory)
                [IO.File]::WriteAllText((Join-Path $directory 'package.xml'), 'fixture metadata only')
                if ($script:SdkAttempts -ge 2) {
                    $binary = Join-Path $directory $script:RetryRequired
                    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $binary))
                    [IO.File]::WriteAllText($binary, 'fixture binary')
                }
                return [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = '' }
            }
            Invoke-JobsAndroidTool 'fixture-java' 'fixture-tools' sdkmanager @(('--sdk_root=' + $Sdk), '--install', $Identifier) -Interactive
            return $script:SdkAttempts
        } (Join-Path $temporary ('metadata-only-' + $component[0].Replace(';','-'))) $component[0] $component[1]
        Assert-Bootstrap ($attempts -eq 2) ($component[0] + ' 仅元数据不算成功，关键文件就绪才结束获取')
    }
    Write-Host ('PASS: AndroidSimulatorBootstrap.Tests.ps1 (' + $script:assertions + ' assertions)')
} finally {
    if ($module) { Remove-Module $module -ErrorAction SilentlyContinue }
    $env:JAVA_HOME = $oldJavaHome; $env:ANDROID_HOME = $oldAndroidHome; $env:ANDROID_SDK_ROOT = $oldSdkRoot
    Remove-Item -LiteralPath $temporary -Recurse -Force
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

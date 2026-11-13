# FlutterProjectSetupVersion.Tests.ps1 | 真实版本字段与工具单源回归。
# Created by Jobs on 2026年10月29日，星期四.
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
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$count=0
function Assert($Value,[string]$Message){$script:count++;if(-not$Value){throw $Message}}
$tempBase=if([Environment]::OSVersion.Platform-eq[PlatformID]::Win32NT){[IO.Path]::GetTempPath()}else{'/private/tmp'}
$temp=Join-Path $tempBase ('jobs-setup-version-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$oldSession=$env:JOBS_SETUP_SESSION;$env:JOBS_SETUP_SESSION=$temp
$module=Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetup.psm1') -PassThru -DisableNameChecking
$progress=Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetupProgress.psm1') -PassThru -DisableNameChecking
try{
 $tool=Get-JobsSetupVersion
 $metadata=Get-Content -LiteralPath (Join-Path $root 'JobsFlutterTools/Scripts/SetupVersion.json') -Raw|ConvertFrom-Json
 Assert ($tool.Version-ceq$metadata.version-and$tool.Build-ceq$metadata.build) '工具版号只有 SetupVersion.json 一个源'
 Assert ($tool.Label-ceq('v'+$metadata.version+' build '+$metadata.build)) '窗口同时显示语义版本与 build'
 Assert ((Get-JobsSetupVersion (Join-Path $temp 'missing.json')).Label-ceq'工具版本未检测') '缺失版本文件不伪造默认值'
 $bad=Join-Path $temp 'bad.json';[IO.File]::WriteAllText($bad,'{"version":"fake","build":"2026"}')
 Assert ((Get-JobsSetupVersion $bad).Label-ceq'工具版本未检测') '无效元数据明确未检测'
 Set-JobsSetupProgress sdk.flutter done '真实探测' -Version 'Flutter 3.38.2 / Dart 3.10.0 / FVM 4.0.1'
 Set-JobsSetupProgress run.device done '已选择'
 $events=@([IO.File]::ReadAllLines((Join-Path $temp 'events.jsonl'))|ForEach-Object{$_|ConvertFrom-Json})
 Assert ($events[0].version-ceq'Flutter 3.38.2 / Dart 3.10.0 / FVM 4.0.1') '事件独立传递完整版本'
 Assert ($events[1].PSObject.Properties.Name-notcontains'version') '旧事件与非版本步骤兼容'
 Assert ((Get-JobsSetupDetectedVersion ([pscustomobject]@{Mode='system'}))-ceq'尚未检测') '旧对象缺字段时明确未检测'
 $sdk=Join-Path $temp 'flutter';$jdk=Join-Path $temp 'jdk'
 foreach($file in @((Join-Path $sdk 'bin/flutter.bat'),(Join-Path $sdk 'bin/cache/dart-sdk/bin/dart.exe'),(Join-Path $jdk 'bin/java.exe'),(Join-Path $jdk 'bin/javac.exe'))){[void][IO.Directory]::CreateDirectory((Split-Path -Parent $file));[IO.File]::WriteAllText($file,'fixture, never executed')}
 &$module{
  param($base)
  $script:versionRoot=$base
  Import-JobsSdkDownloadRoute
  $script:managerCalls=New-Object 'System.Collections.Generic.List[string]'
  $script:managerCancel=$false;$script:metadataCancel=$false
  function script:Initialize-JobsSdkFvmRuntime{
   param($Tool,$Directory,$Environment)
   $script:managerCalls.Add('runtime')
   if($script:managerCancel){throw (New-Object OperationCanceledException('fixture manager runtime cancellation'))}
  }
  function script:Read-JobsSdkLocalToolMetadata{
   param($Tool,$Arguments,$Directory,$Environment)
   $script:managerCalls.Add('metadata')
   if($script:metadataCancel){throw (New-Object OperationCanceledException('fixture native metadata exit 130'))}
   return 'FVM 4.0.1'
  }
  function script:Get-JobsInstallRoot{$script:versionRoot}
  function script:Find-JobsExecutable{param($Name)if($Name-ceq'fvm.exe'){return (Join-Path $script:versionRoot 'fvm.exe')}}
  function script:Invoke-JobsSetupProcess{
   param($File,$Arguments,$Directory,$TimeoutSeconds)
   $name=[IO.Path]::GetFileName($File)
   $out='';$err=''
   switch($name){
    'flutter.bat'{$out='Bootstrap preamble'+"`n"+'{"frameworkVersion":"3.38.2","dartSdkVersion":"3.10.0"}';if(($Arguments-join',')-cne'--version,--machine'){throw 'Flutter 必须查询 machine 版本'}}
    'dart.exe'{$err='Dart SDK version: 3.10.0 (stable)'}
    'fvm.exe'{$out='FVM 4.0.1'}
    'java.exe'{$err='openjdk version "17.0.16" 2025-07-15'+"`n"+'OpenJDK Runtime Environment Temurin-17.0.16+8 (build 17.0.16+8)'}
    'javac.exe'{$out='javac 17.0.16'}
    default{throw ('未知夹具工具 '+$name)}
   }
   [pscustomobject]@{ExitCode=0;StdOut=$out;StdErr=$err}
  }
 }$temp
 $flutter=&$module{param($p,$base)Get-JobsSetupFlutter $p $base 'fvm'}(Join-Path $sdk 'bin/flutter.bat') $temp
 Assert ($flutter.VersionText-ceq'Flutter 3.38.2 / Dart 3.10.0 / FVM 4.0.1') 'Flutter/Dart/FVM 分别读取实际工具输出'
 Assert ((&$module{$script:managerCalls-join','})-ceq'runtime,metadata') 'FVM版本probe前先准备实际管理器Dart运行时'
 &$module{$script:managerCancel=$true;$script:managerCalls.Clear()}
 $cancelled=$false
 try{[void](&$module{param($p)Get-JobsSetupManagerVersion 'fvm' $p}$temp)}catch [OperationCanceledException]{$cancelled=$true}
 Assert ($cancelled-and((&$module{$script:managerCalls-join','})-ceq'runtime')) '运行时准备取消必须穿透且不调用FVM版本元数据'
 &$module{$script:managerCancel=$false;$script:metadataCancel=$true;$script:managerCalls.Clear()}
 $cancelled=$false
 try{[void](&$module{param($p)Get-JobsSetupManagerVersion 'fvm' $p}$temp)}catch [OperationCanceledException]{$cancelled=$true}
 Assert ($cancelled-and((&$module{$script:managerCalls-join','})-ceq'runtime,metadata')) '元数据本身的原生取消不能吞成版本未检测'
 &$module{$script:metadataCancel=$false;function script:Find-JobsExecutable{param($Name)return $null};$script:managerCalls.Clear()}
 $missing=&$module{param($p)Get-JobsSetupManagerVersion 'fvm' $p}$temp
 Assert ($missing-ceq'FVM 版本未检测'-and((&$module{$script:managerCalls.Count})-eq0)) '未安装manager沿用版本未检测，不启动其它PATH Flutter'
 $flutter=&$module{param($p,$base)Get-JobsSetupFlutter $p $base 'system'}(Join-Path $sdk 'bin/flutter.bat') $temp
 Assert ($flutter.VersionText.Contains('FVM 不适用')) '系统模式不声称使用了 FVM'
 $java=&$module{param($p,$base)Get-JobsSetupJava $p $base}$jdk $temp
 Assert ($java.Major-eq17-and$java.VersionText.Contains('Java 17.0.16 / javac 17.0.16')) 'Java 与 javac 完整补丁版本同时保留'
 Assert ($java.VersionText.Contains('Temurin-17.0.16+8')) 'Java 厂商与构建号不被主版本替代'
 $jenv=Join-Path $temp 'toolchains/JEnv-for-Windows/src/jenv.ps1';[void][IO.Directory]::CreateDirectory((Split-Path -Parent $jenv));[IO.File]::WriteAllText($jenv,'$JENV_VERSION = "v2.2.1"; throw "never import manager initialization"')
 $version=&$module{param($p)Get-JobsSetupManagerVersion 'jenv' $p}$temp
 Assert ($version-ceq'jEnv Windows v2.2.1') 'jEnv 从已装官方源码读取版本，不执行全局初始化'
 $properties=Join-Path $temp 'source.properties';[IO.File]::WriteAllText($properties,"Pkg.Revision= 29.0.14033849`nAndroidVersion.ApiLevel=36`n")
 Assert ((&$module{param($p)Get-JobsSetupPropertyValue $p 'Pkg.Revision'}$properties)-ceq'29.0.14033849') 'Android 组件实际 source.properties 版本可读取'
 Assert ((&$module{param($p)Get-JobsSetupPropertyValue $p 'Absent.Key'}$properties)-ceq'未检测') 'Android 缺失版本不采用期望安装值'
 Assert ((&$module{Get-JobsSetupPluginVersion "JOBS_TOOL_VERSION|AGP|8.12.2`nJOBS_TOOL_VERSION|AGP|8.12.2"})-ceq'AGP 8.12.2') 'AGP 显示同进程插件类加载器实际版本并去重'
 Assert ((&$module{Get-JobsSetupPluginVersion 'build successful'}).Contains('实际版本未检测')) '解析成功不等于知道 AGP 版本'
 $init=&$module{param($p)New-JobsSetupVersionInit $p}$temp;$initText=[IO.File]::ReadAllText($init)
 Assert ($initText.Contains('plugin.class.classLoader.loadClass')-and$initText.Contains('ANDROID_GRADLE_PLUGIN_VERSION')) '版本探针读取实际已加载 AGP'
 Assert (-not$initText.Contains('repositories')-and-not$initText.Contains('setProperty')) '版本探针不修改插件仓库或工程配置'
 # 完整依赖调用只替换外部进程边界，核对实际 AGP 事件与临时探针回收。
 [void][IO.Directory]::CreateDirectory((Join-Path $temp 'android'))
 &$module{
  $script:versionCommands=New-Object 'System.Collections.Generic.List[string]'
  function script:Invoke-JobsSetupProcess{
   param($File,$Arguments,$Directory,$TimeoutSeconds)
   $script:versionCommands.Add($Arguments[0])
   if($Arguments[0]-ceq'help'){
    $index=[array]::IndexOf($Arguments,'--init-script');if($index-lt0){throw '缺少实际 AGP 版本探针'}
    $script:versionProbe=$Arguments[$index+1];if(-not[IO.File]::Exists($script:versionProbe)){throw '探针未落盘'}
    return [pscustomobject]@{ExitCode=0;StdOut='JOBS_TOOL_VERSION|AGP|8.12.2';StdErr=''}
   }
   return [pscustomobject]@{ExitCode=0;StdOut='pub get fixture';StdErr=''}
  }
 }
 &$module{param($p,$f)Invoke-JobsSetupDependencies $p $f (Join-Path $p 'android/gradlew.bat') 'fixture-fzf'}$temp $flutter
 $last=@([IO.File]::ReadAllLines((Join-Path $temp 'events.jsonl'))|ForEach-Object{$_|ConvertFrom-Json}|Where-Object{$_.node-ceq'deps.plugins'})[-1]
 Assert ($last.state-ceq'done'-and$last.version-ceq'AGP 8.12.2') '插件阶段真正传递实际解析版本'
 Assert ((&$module{$script:versionCommands-join','})-ceq'pub,help') 'pub get 先于构建插件配置解析'
 Assert (-not[IO.File]::Exists((&$module{$script:versionProbe}))) 'Gradle 完成后清理临时版本探针，不污染项目目录'
 $dashboard=[IO.File]::ReadAllText((Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetupDashboard.ps1'))
 Assert ($dashboard.Contains("`$arrow.Text='>>>>>'")-and$dashboard.Contains("Drawing.Font('Consolas',9")) '里程碑 ASCII >>>>> 使用独立等宽连接符'
 Assert ($dashboard.Contains('Get-JobsSetupVersion')-and$dashboard.Contains('$toolVersion.Label')) '窗口版本只读取单文件版本源'
 Assert ($dashboard.Contains('$versionLabel.Visible=$false')-and$dashboard.Contains('$versionLabel.Visible=$true')-and$dashboard.Contains('$toolTips.SetToolTip($versionLabel')) '实际版本独立小字显示且完整 tooltip 可访问，等待时不占空行'
 $run=[IO.File]::ReadAllText((Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetupRun.ps1'))
 $windowsTools=[IO.File]::ReadAllText((Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetupToolchains.ps1'))
 Assert ($windowsTools.Contains("'installationVersion'")-and$windowsTools.Contains('VC/Tools/MSVC')-and$windowsTools.Contains('Windows Kits/10')-and$windowsTools.Contains("Join-Path `$sdkRoot 'Include'")) 'Windows C++ 版本取本机 VS/MSVC/SDK 清单'
 Assert ($run.Contains('FileVersionInfo')-and$run.Contains('Get-JobsSetupBrowserVersion')) '浏览器读取已安装二进制版本，不启动浏览器冒充探测'
 Assert ($dashboard.Contains('Windows.Forms.SplitContainer')-and$dashboard.Contains('Orientation]::Horizontal')-and$dashboard.Contains('$split.IsSplitterFixed=$false')) '上下区域使用真实可拖动水平分隔'
 Assert ($dashboard.Contains('$split.Panel1MinSize=64')-and$dashboard.Contains('$split.Panel2MinSize=180')-and$dashboard.Contains('$split.Add_SplitterMoved($resize)')-and$dashboard.Contains('FixedPanel]::Panel1')) '流程紧凑且保留真实分隔拖动和原生控制台 resize'
 Assert ($dashboard.Contains("`$title.Text='一键配置 Flutter 项目'")-and$dashboard.Contains('$nodeTitle.Text=$groups[$g][$j+1]')-and$dashboard.Contains('$activityTimer.Interval=350')) '窗口与节点标题独立显示，活动状态每350毫秒刷新'
 $process=[IO.File]::ReadAllText((Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetupProcess.cs'))
 Assert (-not$process.Contains('WaitHandle.WaitAll')-and$process.Contains('outDone.WaitOne(timeout)')-and$process.Contains('errDone.WaitOne(remaining)')) 'Framework STA 排空不使用多句柄 WaitAll，沿用单一超时预算'
 Assert (-not$process.Contains('Kill(true)')-and-not$process.Contains('ArgumentList')) '日志采集没有 .NET Core 专用进程 API'
 Write-Host ('PASS: FlutterProjectSetupVersion.Tests.ps1 ('+$count+' assertions; fixture-only, no SDK installation or native GUI)')
}finally{
 if($null-eq$oldSession){Remove-Item Env:JOBS_SETUP_SESSION -ErrorAction SilentlyContinue}else{$env:JOBS_SETUP_SESSION=$oldSession}
 Remove-Item -LiteralPath $temp -Recurse -Force
 Remove-Module $module,$progress -ErrorAction SilentlyContinue
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

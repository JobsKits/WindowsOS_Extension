# FlutterDependencyMigrationEndToEnd.Tests.ps1 | 真实发布副本、Dart 读写和 ZIP 往返。
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
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$count=0
function Assert($Value,[string]$Message){$script:count++;if(-not$Value){throw $Message}}
function Assert-Throws([scriptblock]$Body,[string]$Message){$failed=$false;try{&$Body|Out-Null}catch{$failed=$true};Assert $failed $Message}
function ConvertTo-FixtureUri([string]$Path){$builder=New-Object UriBuilder;$builder.Scheme='file';$builder.Host='';$builder.Port=-1;$builder.Path=$Path.TrimEnd('\','/')+'/';return $builder.Uri.AbsoluteUri}
function Write-Fixture([string]$Path,[string]$Value){[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path));[IO.File]::WriteAllText($Path,$Value)}
$dart=if($env:JOBS_TEST_DART){$env:JOBS_TEST_DART}else{(Get-Command dart -ErrorAction Stop).Source}
$tempBase=if([Environment]::OSVersion.Platform-eq[PlatformID]::Win32NT){[IO.Path]::GetTempPath()}else{'/private/tmp'}
$temp=Join-Path $tempBase ('JobsMigrationPublished-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$saved=@{}
foreach($name in @('PUB_CACHE','GRADLE_USER_HOME','MAVEN_REPO_LOCAL')){$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
$module=$null
try{
    $package=Join-Path $temp 'copied-release'
    $installer=Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
    &$installer {param($p,$d)New-JobsPackageRelease -PackagePath $p -Destination $d} (Join-Path $root 'JobsFlutterTools') $package | Out-Null
    foreach($path in @('Scripts/FlutterDependencyMigration.psm1/FlutterDependencyMigration.psm1','Scripts/FlutterDependencyMigration.dart','Scripts/ExtractFlutterDependencies.dart','Scripts/ImportFlutterDependencies.dart')){
        Assert ((Get-FileHash -LiteralPath (Join-Path $package $path)).Hash -ceq (Get-FileHash -LiteralPath (Join-Path $root ('JobsFlutterTools/'+$path))).Hash) ('独立发布完整性：'+$path)
    }
    $module=Import-Module (Join-Path $package 'Scripts/FlutterDependencyMigration.psm1/FlutterDependencyMigration.psm1') -PassThru -DisableNameChecking
    $project=Join-Path $temp 'source 工程'
    $target=Join-Path $temp 'target 工程'
    $output=Join-Path $temp 'output'
    $donor=Join-Path $temp 'donor'
    $sourcePub=Join-Path $donor 'renamed dart'
    $sourceGradle=Join-Path $donor 'renamed android'
    $targetPub=Join-Path $temp 'environment/pub'
    $targetGradle=Join-Path $temp 'environment/gradle'
    $spec="name: fixture`ndependencies:`n  flutter:`n    sdk: flutter`n  alpha:`n    git: https://private.invalid/alpha.git`n  beta: ^1.0.0`n"
    Write-Fixture (Join-Path $project 'pubspec.yaml') $spec
    Write-Fixture (Join-Path $target 'pubspec.yaml') $spec
    Write-Fixture (Join-Path $project 'pubspec.lock') "packages:`n  alpha:`n    source: git`n    version: '1.0.0'`n  beta:`n    description:`n      name: beta`n      url: https://pub.dev`n    source: hosted`n    version: '1.0.0'`n  flutter:`n    source: sdk`n    version: '0.0.0'`n"
    $alpha=Join-Path $sourcePub 'git/alpha-ref'
    $beta=Join-Path $sourcePub 'hosted/pub.dev/beta-1.0.0'
    $flutter=Join-Path $temp 'fake-flutter'
    Write-Fixture (Join-Path $alpha 'pubspec.yaml') "name: alpha`nversion: 1.0.0`n"
    Write-Fixture (Join-Path $alpha 'lib/alpha.dart') '// private alpha'
    Write-Fixture (Join-Path $beta 'pubspec.yaml') "name: beta`nversion: 1.0.0`n"
    Write-Fixture (Join-Path $beta 'lib/beta.dart') '// public beta'
    Write-Fixture (Join-Path $flutter 'pubspec.yaml') "name: flutter`nversion: 0.0.0`n"
    $config=@{configVersion=2;packages=@(@{name='fixture';rootUri=(ConvertTo-FixtureUri $project)},@{name='alpha';rootUri=(ConvertTo-FixtureUri $alpha)},@{name='beta';rootUri=(ConvertTo-FixtureUri $beta)},@{name='flutter';rootUri=(ConvertTo-FixtureUri $flutter)})}|ConvertTo-Json -Depth 6
    Write-Fixture (Join-Path $project '.dart_tool/package_config.json') $config
    Write-Fixture (Join-Path $project 'android/build.gradle.kts') "repositories { maven { url = uri(`"https://private.invalid/maven`"); content { includeGroup(`"private.group`") } } }"
    foreach($relative in @('pubspec.lock','android/build.gradle.kts')) { Write-Fixture (Join-Path $target $relative) ([IO.File]::ReadAllText((Join-Path $project $relative))) }
    $privateJar='caches/modules-2/files-2.1/private.group/sdk/1/hash/sdk.jar'
    $publicJar='caches/modules-2/files-2.1/public.group/sdk/1/hash/sdk.jar'
    Write-Fixture (Join-Path $sourceGradle $privateJar) 'private-jar'
    Write-Fixture (Join-Path $sourceGradle $publicJar) 'public-jar'
    Write-Fixture (Join-Path $sourceGradle 'gradle.properties') 'do not copy credential'
    Write-Fixture (Join-Path $sourcePub 'credentials.json') 'do not copy credential'
    [void][IO.Directory]::CreateDirectory($output)
    $env:PUB_CACHE=$sourcePub;$env:GRADLE_USER_HOME=$sourceGradle;$env:MAVEN_REPO_LOCAL=Join-Path $temp 'source-maven'
    &$module {
        param($runtime,$BackupParent)
        $script:testDart=$runtime
        $script:backupParent=$BackupParent
        $script:answers=New-Object 'Collections.Generic.Queue[string]'
        $script:mutateSource=''
        $script:mutateTarget=''
        function script:Get-JobsMigrationDart {param($p)$script:testDart}
        function script:Find-JobsExecutable {return $null}
        function script:Get-JobsMigrationDesktop {return $script:backupParent}
        function script:Read-JobsMigrationLine {param($Prompt)if($script:answers.Count-eq0){throw ('fixture exhausted: '+$Prompt)};if($Prompt -like '*大写 YES*'){if($script:mutateSource){[IO.File]::WriteAllText($script:mutateSource,'changed during confirmation')};if($script:mutateTarget){[IO.File]::WriteAllText($script:mutateTarget,'concurrent target edit')}};$script:answers.Dequeue()}
    } $dart (Join-Path $temp 'backup parent 中文')
    &$module {param($p,$d)foreach($a in @('','',$d,'','')){$script:answers.Enqueue($a)};Invoke-JobsFlutterMigration $p export-all-dependencies} $project $output
    $bundles=@(Get-ChildItem -LiteralPath $output -Directory)
    Assert ($bundles.Count-eq1) '真实引擎默认私库产生唯一完整产物'
    $bundle=$bundles[0].FullName
    Assert ([IO.File]::Exists((Join-Path $bundle 'migration.json'))-and[IO.File]::Exists($bundle+'.zip')) '完整清单及真实ZIP存在'
    $manifest=Get-Content -LiteralPath (Join-Path $bundle 'migration.json') -Raw -Encoding UTF8|ConvertFrom-Json
    Assert ($manifest.scope-ceq'private-candidates') '私库默认值抵达真实引擎'
    Assert ([IO.File]::Exists((Join-Path $bundle ('payload/gradle/'+$privateJar)))-and-not[IO.File]::Exists((Join-Path $bundle ('payload/gradle/'+$publicJar)))) '私有Maven组有证据提取，公共组不提取'
    $env:PUB_CACHE=$targetPub;$env:GRADLE_USER_HOME=$targetGradle;$env:MAVEN_REPO_LOCAL=Join-Path $temp 'environment/maven'
    &$module {param($p,$s)foreach($a in @('',$s,'','cancel')){$script:answers.Enqueue($a)};Invoke-JobsFlutterMigration $p import-all-dependencies} $target $bundle
    Assert (-not[IO.Directory]::Exists($targetGradle)-and-not[IO.Directory]::Exists((Join-Path $target 'vendor'))) '真实预检取消零写入'
    &$module {param($p,$s)foreach($a in @('',$s,'','','YES')){$script:answers.Enqueue($a)};Invoke-JobsFlutterMigration $p import-all-dependencies} $target $bundle
    Assert ([IO.File]::ReadAllText((Join-Path $targetGradle $privateJar))-ceq'private-jar') '真实原生缓存融合保留原字节'
    Assert ([IO.File]::ReadAllText((Join-Path $target 'pubspec_overrides.yaml'))-match'alpha') '真实Pub私库恢复本地相对覆盖'
    &$module {param($p,$s)foreach($a in @('',$s,'YES')){$script:answers.Enqueue($a)};Invoke-JobsFlutterMigration $p import-all-dependencies} $target $donor
    Assert ([IO.File]::ReadAllText((Join-Path $targetGradle $publicJar))-ceq'public-jar') '改名原始Gradle目录按内容识别融合'
    Assert ([IO.File]::ReadAllText((Join-Path $targetPub 'hosted/pub.dev/beta-1.0.0/lib/beta.dart'))-ceq'// public beta') '改名原始Pub目录按内容识别融合'
    Assert (-not[IO.File]::Exists((Join-Path $targetGradle 'gradle.properties'))-and-not[IO.File]::Exists((Join-Path $targetPub 'credentials.json'))) '原始缓存认证文件未迁移'
    $changing='caches/modules-2/files-2.1/private.group/new/1/hash/new.jar'
    Write-Fixture (Join-Path $sourceGradle $changing) 'before confirmation'
    &$module {param($s,$f)$script:mutateSource=$f;foreach($a in @('',$s,'YES')){$script:answers.Enqueue($a)}} $donor (Join-Path $sourceGradle $changing)
    Assert-Throws {&$module {param($p)Invoke-JobsFlutterMigration $p import-all-dependencies} $target} '确认期间源文件变化，真实计划指纹阻断写入'
    Assert (-not[IO.File]::Exists((Join-Path $targetGradle $changing))) '变化后的新文件未写入目标'
    &$module {$script:mutateSource=''}
    Write-Fixture (Join-Path $targetGradle $publicJar) 'local conflict'
    &$module {param($p,$s)foreach($a in @('',$s,'q')){$script:answers.Enqueue($a)};Invoke-JobsFlutterMigration $p import-all-dependencies} $target $donor
    Assert ([IO.File]::ReadAllText((Join-Path $targetGradle $publicJar))-ceq'local conflict') '真实冲突选择取消保留本机内容'
    &$module {param($p,$s)foreach($a in @('',$s,'2','YES')){$script:answers.Enqueue($a)};Invoke-JobsFlutterMigration $p import-all-dependencies} $target $donor
    Assert ([IO.File]::ReadAllText((Join-Path $targetGradle $publicJar))-ceq'local conflict') '真实existing策略跳过冲突文件'
    Assert ([IO.File]::ReadAllText((Join-Path $targetGradle $changing))-ceq'changed during confirmation') 'existing策略仍融合无冲突新增文件'
    &$module {param($p,$s)foreach($a in @('',$s,'1',' ','YES')){$script:answers.Enqueue($a)};Invoke-JobsFlutterMigration $p import-all-dependencies} $target $donor
    Assert ([IO.File]::ReadAllText((Join-Path $targetGradle $publicJar))-ceq'public-jar') '真实source且非空不备份使用导入源覆盖'
    $backupParent=Join-Path $temp 'backup parent 中文'
    Assert (-not[IO.Directory]::Exists($backupParent)) '无备份选择没有创建备份目录'
    Write-Fixture (Join-Path $targetGradle $publicJar) 'local before backup'
    &$module {param($p,$s)foreach($a in @('',$s,'','','','','cancel')){$script:answers.Enqueue($a)};Invoke-JobsFlutterMigration $p import-all-dependencies} $target $donor
    Assert (-not[IO.Directory]::Exists($backupParent)-and[IO.File]::ReadAllText((Join-Path $targetGradle $publicJar))-ceq'local before backup') '备份选择后最终非YES仍零备份和覆盖'
    &$module {param($p,$s)foreach($a in @('',$s,'','','','YES')){$script:answers.Enqueue($a)};Invoke-JobsFlutterMigration $p import-all-dependencies} $target $donor
    Assert ([IO.File]::ReadAllText((Join-Path $targetGradle $publicJar))-ceq'public-jar') '默认推荐导入源且默认备份后覆盖成功'
    $backups=@(Get-ChildItem -LiteralPath $backupParent -Directory)
    Assert ($backups.Count-eq1) '引擎仅在YES后创建唯一持久备份子目录'
    $oldCopies=@(Get-ChildItem -LiteralPath $backups[0].FullName -Recurse -File | Where-Object {[IO.File]::ReadAllText($_.FullName)-ceq'local before backup'})
    Assert ($oldCopies.Count-eq1) '真实持久备份保存覆盖前本机原字节'
    Write-Fixture (Join-Path $targetGradle $publicJar) 'local before concurrent edit'
    &$module {param($s,$f)$script:mutateTarget=$f;foreach($a in @('',$s,'','','','YES')){$script:answers.Enqueue($a)}} $donor (Join-Path $targetGradle $publicJar)
    Assert-Throws {&$module {param($p)Invoke-JobsFlutterMigration $p import-all-dependencies} $target} '覆盖确认期间目标变化，真实expected-plan阻断写入'
    Assert ([IO.File]::ReadAllText((Join-Path $targetGradle $publicJar))-ceq'concurrent target edit') '并发新改动不被旧计划覆盖'
    Assert (@(Get-ChildItem -LiteralPath $backupParent -Directory).Count-eq1) '并发校验失败没有新增持久备份目录'
    Write-Host ('PASS: FlutterDependencyMigrationEndToEnd.Tests.ps1 ('+$count+' assertions; real Dart/copied Windows release on '+[Environment]::OSVersion.Platform+'; not Windows native UI)')
} finally {
    foreach($name in $saved.Keys){[Environment]::SetEnvironmentVariable($name,$saved[$name],'Process')}
    if($module){Remove-Module $module -ErrorAction SilentlyContinue}
    Remove-Item -LiteralPath $temp -Recurse -Force
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

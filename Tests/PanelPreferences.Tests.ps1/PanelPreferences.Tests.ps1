# PanelPreferences.Tests.ps1 | 安装面板偏好、语言和副本回归
# Created by Jobs on 2026年11月4日，星期三.
# 只写临时偏好；不安装、注册扩展、修改系统主题或重启资源管理器。
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
$module = Import-Module (Join-Path $root 'Scripts/Installer.psm1') -PassThru -Force -DisableNameChecking
Import-Module (Join-Path $root 'Scripts/Catalog.psm1') -Force -DisableNameChecking
$script:assertions = 0
$temp = Join-Path ([IO.Path]::GetTempPath()) ('JobsPanel 中文 ' + [guid]::NewGuid().ToString('N'))
$path = Join-Path $temp 'preferences.json'
function Assert-Panel {
    param([bool]$Value, [string]$Message)
    if (-not $Value) { throw ('FAIL: ' + $Message) }
    $script:assertions++
}
try {
    $defaults = Read-JobsPanelPreferences -Path $path
    Assert-Panel ($defaults.Theme -ceq 'system' -and $defaults.Language -ceq 'system') '缺失设置默认双跟随系统'
    Assert-Panel (-not [IO.Directory]::Exists($temp)) '读取默认值不创建偏好目录'
    foreach ($theme in @('system', 'dark', 'light')) {
        foreach ($language in @('system', 'zh-Hans', 'zh-Hant', 'bo', 'en', 'ja', 'fr', 'es', 'de', 'ru', 'ko')) {
            Save-JobsPanelPreferences $theme $language -Path $path
            $saved = Read-JobsPanelPreferences -Path $path
            Assert-Panel ($saved.Theme -ceq $theme -and $saved.Language -ceq $language) '所有主题语言组合原子保存并读回'
        }
    }
    Assert-Panel (@(Get-ChildItem -LiteralPath $temp -Filter '*.tmp').Count -eq 0) '成功保存无遗留临时文件'
    $before = [IO.File]::ReadAllBytes($path)
    $rejected = $false
    try { Save-JobsPanelPreferences 'blue' 'en' -Path $path } catch { $rejected = $true }
    Assert-Panel ($rejected -and [Convert]::ToBase64String($before) -ceq [Convert]::ToBase64String([IO.File]::ReadAllBytes($path))) '无效枚举拒绝且旧文件逐字保留'
    [IO.File]::WriteAllText($path, '{"Theme":"unknown","Language":"unsupported"}')
    $unknown = Read-JobsPanelPreferences -Path $path
    Assert-Panel ($unknown.Theme -ceq 'system' -and $unknown.Language -ceq 'system') '未知枚举回退系统'
    [IO.File]::WriteAllText($path, '{broken json')
    $broken = Read-JobsPanelPreferences -Path $path
    Assert-Panel ($broken.Theme -ceq 'system' -and $broken.Language -ceq 'system' -and $broken.Error.Length -gt 0) '坏设置回退系统并保留诊断'
    Assert-Panel ([IO.File]::ReadAllText($path) -ceq '{broken json') '坏设置不会自动被覆盖'
    foreach ($culture in @('zh-TW', 'zh-HK', 'zh-MO', 'zh-Hant', 'zh-Hant-CN')) { Assert-Panel ((Resolve-JobsPanelLanguage -SystemLanguage $culture) -ceq 'zh-Hant') '繁体UI语言映射' }
    foreach ($culture in @('zh', 'zh-CN', 'zh-SG', 'zh-Hans', 'zh-Hans-HK')) { Assert-Panel ((Resolve-JobsPanelLanguage -SystemLanguage $culture) -ceq 'zh-Hans') '简体及显式Hans映射' }
    foreach ($culture in @('en-US', 'bo-CN', 'fr-FR', 'ja-JP', 'de-DE', 'es-ES', 'ru-RU', 'ko-KR')) { Assert-Panel ((Resolve-JobsPanelLanguage -SystemLanguage $culture) -ceq $culture.Substring(0,2)) '十语言系统地区映射' }
    foreach ($culture in @('it-IT','ar-SA','pt-BR')) { Assert-Panel ((Resolve-JobsPanelLanguage -SystemLanguage $culture) -ceq 'en') '未支持系统语言英文回退' }
    Assert-Panel ((Resolve-JobsPanelLanguage -Preference 'zh-Hant' -SystemLanguage en-US) -ceq 'zh-Hant') '显式语言覆盖系统'
    Assert-Panel ((Resolve-JobsPanelTheme -SystemDark $true) -ceq 'dark' -and (Resolve-JobsPanelTheme -SystemDark $false) -ceq 'light') '系统亮暗两种变化'
    Assert-Panel ((Resolve-JobsPanelTheme -Preference light -SystemDark $true) -ceq 'light') '显式主题覆盖系统'
    $packages = @(Get-JobsFeaturePackages -Root $root)
    $features = @(Get-JobsSelectableFeatures -Packages $packages)
    $texts = @($packages | ForEach-Object { $_.Label; $_.Description }) + @($features | ForEach-Object { $_.Label; if ($null -ne $_.PSObject.Properties['Group']) { $_.Group } })
    foreach ($text in $texts) {
        $english = Get-JobsPanelText $text en
        Assert-Panel ($english -notmatch '[\u3400-\u9fff]') ('当前清单英文资源齐全：' + $text)
        Assert-Panel ((Get-JobsPanelText $text zh-Hans) -ceq $text) '简体文本保持原样'
    }
    Assert-Panel ((Get-JobsPanelText '安装 / 更新' zh-Hant) -ceq '安裝 / 更新') '繁体切换使用内置资源'
    $resources = & $module {
        [pscustomobject]@{
            Languages=$script:PanelLanguageCodes
            Names=$script:PanelLanguageNames
            Catalog=$script:PanelExtendedTranslations
            English=@($script:PanelTranslations.Values | ForEach-Object { $_[1] })+@($script:PanelTextPatterns | ForEach-Object { $_.Text[1] })
        }
    }
    $canonical=&$module {
        param($Path)
        $stream=New-Object IO.MemoryStream(,[IO.File]::ReadAllBytes($Path))
        try { return $translationSerializer.ReadObject($stream) } finally { $stream.Dispose() }
    } (Join-Path $root 'Scripts/ManagerPanelTranslations.json')
    Assert-Panel ($canonical.Count-eq7-and$resources.Catalog.Count-eq7) '标准词库与内嵌运行词库均含七种新增语言'
    foreach($locale in $canonical.Keys) {
        Assert-Panel ($canonical[$locale].Count-eq$resources.Catalog[$locale].Count) '标准词库和发布内嵌词库键数一致'
        foreach($key in $canonical[$locale].Keys){Assert-Panel ($resources.Catalog[$locale].ContainsKey($key)-and$resources.Catalog[$locale][$key]-ceq$canonical[$locale][$key]) ('全部内嵌译文逐项等于跨端标准源：'+$locale+': '+$key)}
    }
    Assert-Panel ($resources.Languages.Count-eq11-and$resources.Names.Count-eq11-and($resources.Languages|Select-Object -Unique).Count-eq11) 'system加十语言选项与固定自称完整'
    Assert-Panel ($resources.Names[2]-ceq'བོད་ཡིག'-and$resources.Names[5]-ceq'Français'-and$resources.Names[8]-ceq'Русский') '语言名称使用自称，不随当前语言翻译'
    foreach($locale in @('bo','ja','fr','es','de','ru','ko')) {
        $table=$resources.Catalog[$locale]
        Assert-Panel ($table.Count-eq352) '共享词库每语含352项完整正文和动态模板'
        foreach($english in $resources.English){Assert-Panel ($table.ContainsKey([string]$english)-and-not[string]::IsNullOrWhiteSpace($table[[string]$english])) ('Windows当前全部文案有译文：'+$locale+': '+$english)}
        foreach($key in $table.Keys){
            $expected=@([regex]::Matches($key,'\{\d+\}')|ForEach-Object Value|Sort-Object)-join'|'
            $actual=@([regex]::Matches($table[$key],'\{\d+\}')|ForEach-Object Value|Sort-Object)-join'|'
            Assert-Panel ($actual-ceq$expected) ('动态占位保持：'+$locale+': '+$key)
            Assert-Panel ($table[$key]-cne$key-or$key-in@('{0} {1}','{0}{1} {2}')-or($locale-ceq'ja'-and$key-ceq'OK')) '已知完整UI文案不回退英文'
        }
        foreach($text in $texts){$english=Get-JobsPanelText $text en;Assert-Panel ((Get-JobsPanelText $text $locale)-ceq$table[$english]) ('全部功能名/描述/分组实际进入当前语言路由：'+$locale)}
        Assert-Panel ((Get-JobsPanelText '已选 12 / 81 项；关闭或取消窗口不执行操作。' $locale)-ceq($table['Selected {0} / {1}. Closing or cancelling makes no changes.']-f12,81)) '真实动态规则使用同一完整语言模板'
        $expectedProgress=$table['{0} in progress; completed {1} / {2} ({3}% by completed items); {4} {5}']-f$table['Install / update'],12,81,'14.8',$table['Install time'],'100:01:23'
        Assert-Panel ((Get-JobsPanelText '安装 / 更新中；已处理 12 / 81 项（14.8%，按完成项计数）；安装用时 100:01:23' $locale)-ceq$expectedProgress) '动态操作名计时标签与进度正文同时换语'
        $rawPath='C:\安装\已完成\日志.txt'
        Assert-Panel ((Get-JobsPanelText ('读取日志失败：'+$rawPath) $locale)-ceq($table['Could not read the log: ']+$rawPath)) '本地化诊断前缀且原始路径逐字保留'
    }
    $portableDirectory=Join-Path $temp 'portable panel'
    [void][IO.Directory]::CreateDirectory($portableDirectory)
    $portablePath=Join-Path $portableDirectory 'SelectionPanel.psm1'
    [IO.File]::Copy((Join-Path $root 'Scripts/Installer.psm1'),$portablePath)
    $portableModule=Import-Module $portablePath -Prefix Isolated -PassThru -DisableNameChecking
    try {
        foreach($locale in @('bo','ja','fr','es','de','ru','ko')) {
            $actual=&$portableModule {param($Locale)Get-JobsPanelText '自定义Explorer右键菜单' $Locale} $locale
            Assert-Panel ($actual-ceq$resources.Catalog[$locale]['Custom Explorer context menu']) '迁移后单模块不依赖源码目录、外置词库或在线翻译'
        }
        Assert-Panel (@(Get-ChildItem $portableDirectory -File).Count-eq1) '独立语言资源确实只依赖内嵌面板模块'
    } finally { Remove-Module $portableModule }
    Assert-Panel ($resources.Catalog['fr'].ContainsKey('Install / Update')-and$resources.Catalog['fr'].ContainsKey('Install / update')) 'PS5兼容词库保留大小写不同的独立English键'
    $fontChoices=&$module {
        @(Get-JobsPanelFontName bo @('Segoe UI','Microsoft Himalaya');Get-JobsPanelFontName bo @('Segoe UI','Noto Sans Tibetan');Get-JobsPanelFontName bo @('Segoe UI');Get-JobsPanelFontName ja @('Segoe UI','Yu Gothic UI');Get-JobsPanelFontName ko @('Segoe UI','Malgun Gothic'))
    }
    Assert-Panel (($fontChoices-join'|')-ceq'Microsoft Himalaya|Noto Sans Tibetan|Segoe UI|Yu Gothic UI|Malgun Gothic') '藏文与日韩选择已安装字体，缺专用字体正常回退'

    $count = '已选 12 / 81 项；关闭或取消窗口不执行操作。'
    Assert-Panel ((Get-JobsPanelText $count en) -ceq 'Selected 12 / 81. Closing or cancelling makes no changes.') '动态选中数量可翻译'
    $progress = '安装 / 更新中；已处理 12 / 81 项（14.8%，按完成项计数）；安装用时 100:01:23'
    Assert-Panel ((Get-JobsPanelText $progress en) -ceq 'Install / update in progress; completed 12 / 81 (14.8% by completed items); Install time 100:01:23') '动态进度保留数量百分比及累计小时'
    $sourcePath = 'C:\安装\已完成\卸载\日志.txt'
    Assert-Panel ((Get-JobsPanelText ('读取日志失败：' + $sourcePath) en) -ceq ('Could not read the log: ' + $sourcePath)) '诊断中的中文路径完整保留'
    Assert-Panel ((Get-JobsPanelText $sourcePath en) -ceq $sourcePath) '未知路径不参与词语替换'
    foreach ($language in @('en', 'zh-Hant', 'zh-Hans', 'en', 'zh-Hant')) { Assert-Panel ((Get-JobsPanelText $count $language).Contains('12')) '重复切换从原文重算数值不丢失' }
    $tooltipChecks = & $module {
        $tip = [pscustomobject]@{ Text = '' }
        $tip | Add-Member ScriptMethod SetToolTip { param($Control, $Text) $this.Text = $Text }
        $state = [pscustomobject]@{ Language = 'en'; FeatureStates = @{ fixture = 'Failed' }; FeatureLabels = @{ fixture = [pscustomobject]@{} }; ToolTip = $tip; LogPath = 'C:\安装\已完成\日志.txt' }
        $message = "原始卸载错误`r`nC:\安装\已完成\原始.log"
        Set-JobsPanelFeatureToolTip $state fixture $message
        $english = $tip.Text
        $state.Language = 'zh-Hant'
        Set-JobsPanelFeatureToolTip $state fixture $message
        [pscustomobject]@{ English = $english; Traditional = $tip.Text; Message = $message; Path = $state.LogPath }
    }
    Assert-Panel ($tooltipChecks.English.StartsWith($tooltipChecks.Message) -and $tooltipChecks.Traditional.StartsWith($tooltipChecks.Message)) '失败消息包含中文路径和换行也逐字保留'
    Assert-Panel ($tooltipChecks.English.EndsWith($tooltipChecks.Path) -and $tooltipChecks.Traditional.EndsWith($tooltipChecks.Path)) '失败日志定位路径逐字保留'
    Assert-Panel ($tooltipChecks.English.Contains('Click to read the full session log') -and $tooltipChecks.Traditional.Contains('點擊在新 PowerShell 窗口讀取')) '同一失败项固定提示跟随英文和繁体切换'
    # 几何模型不依赖WinForms，覆盖中英宽度、缩放、窄窗与右上角重定位。
    foreach ($scale in @(1.0, 1.5, 2.0)) {
        foreach ($english in @($false, $true)) {
            $titleWidth = 240; $themeWidth = 32; $languageWidth = 32
            if ($english) { $titleWidth = 300; $themeWidth = 58; $languageWidth = 80 }
            $arguments = @{ Padding = [int](20 * $scale); Scale = $scale; TitleWidth = [int]($titleWidth * $scale); TitleHeight = [int](24 * $scale); ThemeLabelWidth = [int]($themeWidth * $scale); LanguageLabelWidth = [int]($languageWidth * $scale); ChoiceWidth = [int](140 * $scale); ControlHeight = [int](28 * $scale) }
            foreach ($baseWidth in @(480, 680, 1280, 1600)) {
                $width = [int]($baseWidth * $scale)
                $layout = Get-JobsPanelHeaderLayout -Width $width @arguments
                Assert-Panel ($layout.PreferenceLeft + $layout.PreferenceWidth -eq $width - $arguments.Padding) '工具组始终按内容右边距对齐'
                Assert-Panel ($layout.PreferenceLeft -ge $arguments.Padding -and $layout.PreferenceTop -ge $arguments.Padding) '窄窗与高DPI的工具组仍在内容范围'
                Assert-Panel ($layout.ThemeChoiceLeft + $arguments.ChoiceWidth -le $layout.PreferenceWidth -and $layout.LanguageChoiceLeft + $arguments.ChoiceWidth -le $layout.PreferenceWidth) '两组标签下拉都在工具容器内'
                Assert-Panel ($layout.DetailsTop -ge $layout.PreferenceTop + $layout.PreferenceHeight -and $layout.DetailsTop -ge $layout.TitleTop + $arguments.TitleHeight) '正文不与标题或工具组重叠'
                if ($layout.Inline) {
                    Assert-Panel ($layout.PreferenceTop -eq $arguments.Padding -and $layout.TitleTop -lt $arguments.Padding + $arguments.ControlHeight) '常规宽屏工具组与标题共用顶行'
                    Assert-Panel ($arguments.Padding + $layout.TitleWidth -lt $layout.PreferenceLeft) '同排标题与工具组留出间距'
                    Assert-Panel ($layout.DetailsTop -le $arguments.Padding + $arguments.ControlHeight + [int][Math]::Ceiling(8 * $scale)) '同排不额外预留整行空白'
                } else {
                    Assert-Panel ($layout.PreferenceTop -ge $layout.TitleTop + $arguments.TitleHeight + [int][Math]::Ceiling(8 * $scale)) '窄窗换行保留完整标题'
                }
                if ($layout.Stacked) {
                    Assert-Panel ($layout.LanguageTop -ge $arguments.ControlHeight + [int][Math]::Ceiling(8 * $scale)) '极窄窗口两组选择上下排无重叠'
                    Assert-Panel ($layout.ThemeChoiceLeft -eq $layout.LanguageChoiceLeft) '上下两行下拉保持同一右边界'
                }
                if ($baseWidth -ge 1280) { Assert-Panel $layout.Inline '宽屏中英及高DPI都共用顶行' }
            }
            $normal = Get-JobsPanelHeaderLayout -Width ([int](1280 * $scale)) @arguments
            $expanded = Get-JobsPanelHeaderLayout -Width ([int](1600 * $scale)) @arguments
            Assert-Panel ($expanded.PreferenceLeft - $normal.PreferenceLeft -eq [int](320 * $scale)) '窗口变宽只平移工具组至新右上角'
        }
    }
    foreach ($scale in @(1.0, 1.5, 2.0)) {
        foreach ($english in @($false, $true)) {
            $routeWidth = 220; $autoWidth = 220; $buttonWidth = 150
            if ($english) { $routeWidth = 330; $autoWidth = 320; $buttonWidth = 180 }
            $metrics = @{ Scale = $scale; RouteWidth = [int]($routeWidth * $scale); RouteHeight = [int](26 * $scale); AutoCleanupWidth = [int]($autoWidth * $scale); AutoCleanupHeight = [int](30 * $scale); CleanupButtonWidth = [int]($buttonWidth * $scale); CleanupButtonHeight = [int](32 * $scale) }
            foreach ($width in @([int](540 * $scale), [int](980 * $scale), [int](1240 * $scale))) {
                $row = Get-JobsPanelDeploymentRowLayout -AvailableWidth $width -CleanupVisible $true @metrics
                $routeCenter = $row.RouteTop + $metrics.RouteHeight / 2.0
                $autoCenter = $row.AutoCleanupTop + $metrics.AutoCleanupHeight / 2.0
                Assert-Panel ([Math]::Abs($routeCenter - $autoCenter) -le 1) '部署位置和自动清理勾选共用中心线'
                Assert-Panel ($row.RouteWidth -eq $metrics.RouteWidth -and $row.CleanupLeft -eq $metrics.RouteWidth + [int][Math]::Ceiling(12 * $scale)) '自动清理紧邻部署位置，不随窗口拉大留空'
                Assert-Panel ($row.CleanupWidth -eq $metrics.AutoCleanupWidth -and $row.RowHeight -eq $metrics.AutoCleanupHeight) '独立红色清理按钮不占用顶部部署行'
                Assert-Panel ($row.CleanupLeft + $row.CleanupWidth -eq $row.ContentWidth) '部署行自然宽度仅包含下拉与复选框'
                Assert-Panel ($row.ScrollRequired -eq ($row.ContentWidth -gt $width)) '窄窗只在真实溢出时提供水平滚动'
                $build = Get-JobsPanelDeploymentRowLayout -AvailableWidth $width -CleanupVisible $false @metrics
                Assert-Panel ($build.CleanupWidth -eq 0 -and $build.ContentWidth -eq $metrics.RouteWidth -and $build.RowHeight -eq $metrics.RouteHeight) '构建目录隐藏自动清理后保留下拉自然宽度'
            }
        }
    }
    # 模型与真实JSON往返可在macOS验证，不假称已操作Windows原生拖放。
    $groups = @([pscustomobject]@{Key='ide';IsFlutter=$false}, [pscustomobject]@{Key='git';IsFlutter=$false}, [pscustomobject]@{Key='flutter';IsFlutter=$true}, [pscustomobject]@{Key='ios';IsFlutter=$false})
    $cards = @(Get-JobsPanelDefaultGroupLayout $groups)
    Assert-Panel (@($cards | Where-Object {$_.Column -eq 1}).Count -eq 1 -and @($cards | Where-Object {$_.Column -eq 1})[0].Key -ceq 'flutter') '默认右侧只有Flutter，其余左侧'
    $sourceKeys = @($cards.Key) -join ','
    $moved = @(Move-JobsPanelGroup $cards 'ios' 0 'git')
    Assert-Panel ((@($moved | Where-Object {$_.Column -eq 0}).Key -join ',') -ceq 'ide,ios,git') '同列在目标卡片前插入'
    Assert-Panel ((@($cards.Key) -join ',') -ceq $sourceKeys) '视觉移动不改变原执行清单'
    $moved = @(Move-JobsPanelGroup $moved 'flutter' 0 '')
    Assert-Panel ((@($moved | Where-Object {$_.Column -eq 0}).Key -join ',') -ceq 'ide,ios,git,flutter' -and @($moved | Where-Object {$_.Column -eq 1}).Count -eq 0) '可跨列并允许空右列'
    $moved = @(Move-JobsPanelGroup $moved 'git' 1 '')
    Assert-Panel ((@($moved | Where-Object {$_.Column -eq 1}).Key -join ',') -ceq 'git') '可拖回空右列'
    Assert-Panel (@($moved.Key | Select-Object -Unique).Count -eq $groups.Count) '跨列移动没有重复或遗漏卡片'
    $layoutPath = Get-JobsPanelGroupLayoutPath $path $groups
    $singlePath = Get-JobsPanelGroupLayoutPath $path @($groups[2])
    Assert-Panel ($layoutPath -cne $singlePath -and $layoutPath -ceq (Get-JobsPanelGroupLayoutPath $path @($groups[3],$groups[0],$groups[2],$groups[1]))) '独立面板scope隔离，源卡片枚举顺序不改变持久键'
    $dropState = [pscustomobject]@{GroupColumns=2;Scale=1;Font=[pscustomobject]@{Height=16};ContentPanel=[pscustomobject]@{ClientSize=[pscustomobject]@{Width=1200}};GroupLayout=@($cards);Groups=@(
        [pscustomobject]@{Key='ide';Box=[pscustomobject]@{Top=0;Height=200;Bottom=200}},
        [pscustomobject]@{Key='git';Box=[pscustomobject]@{Top=212;Height=240;Bottom=452}},
        [pscustomobject]@{Key='flutter';Box=[pscustomobject]@{Top=0;Height=2000;Bottom=2000}},
        [pscustomobject]@{Key='ios';Box=[pscustomobject]@{Top=464;Height=300;Bottom=764}})}
    $before=Get-JobsPanelGroupDrop $dropState 900 5 'git'
    $after=Get-JobsPanelGroupDrop $dropState 900 20 'git'
    Assert-Panel ($before.Column -eq 1 -and $before.BeforeKey -ceq 'flutter') '高Flutter卡片可从标题上半区前插入'
    Assert-Panel ($after.Column -eq 1 -and -not $after.BeforeKey -and $after.MarkerTop -le 24) '高Flutter卡片可从标题下半区后插入，无需滚到底部'
    $dropState.GroupColumns=1
    $collapsed=Get-JobsPanelGroupDrop $dropState 20 218 'ide'
    Assert-Panel ($collapsed.Column -eq 0 -and $collapsed.BeforeKey -ceq 'git') '单列折叠落点继承目标的持久列'
    Assert-Panel ((@($dropState.GroupLayout.Key)-join',') -ceq $sourceKeys) '折叠或拖拽预览不修改持久模型'
    Save-JobsPanelGroupLayout $moved $layoutPath
    $read = Read-JobsPanelGroupLayout $groups $layoutPath
    Assert-Panel (-not $read.Error -and (@($read.Entries | Sort-Object Column,Order | ForEach-Object {$_.Key+':'+$_.Column+':'+$_.Order}) -join ',') -ceq (@($moved | Sort-Object Column,Order | ForEach-Object {$_.Key+':'+$_.Column+':'+$_.Order}) -join ',')) '真实JSON Int32/Int64读写往返完整恢复排序'
    Save-JobsPanelPreferences 'dark' 'bo' $path
    Assert-Panel (-not (Read-JobsPanelGroupLayout $groups $layoutPath).Error -and (Read-JobsPanelPreferences $path).Language -ceq 'bo') '主题语言保存与卡片布局互不覆盖'
    foreach ($bad in @('unknown','duplicate','column','fraction','string','negative','broken')) {
        $entries = @($moved | ForEach-Object {[pscustomobject]@{Key=$_.Key;Column=$_.Column;Order=$_.Order}})
        switch ($bad) {
            'unknown' {$entries[0].Key='gone'}
            'duplicate' {$entries[1].Key=$entries[0].Key}
            'column' {$entries[0].Column=3}
            'fraction' {$entries[0].Order=0.5}
            'string' {$entries[0].Order='0'}
            'negative' {$entries[0].Order=-1}
        }
        $raw = ConvertTo-Json @{Version=1;Groups=$entries} -Depth 4
        if ($bad -ceq 'broken') {$raw='{'}
        [IO.File]::WriteAllText($layoutPath,$raw)
        $read=Read-JobsPanelGroupLayout $groups $layoutPath
        Assert-Panel ([bool]$read.Error -and @($read.Entries).Count -eq $groups.Count -and @($read.Entries | Where-Object {$_.Column -eq 1})[0].Key -ceq 'flutter') ('坏布局恢复默认且无卡片丢失：'+$bad)
        Assert-Panel ([IO.File]::ReadAllText($layoutPath) -ceq $raw) '只读坏布局不覆盖原始文件'
    }
    $main = Join-Path $root 'Scripts/Installer.psm1'
    $hash = (Get-FileHash -LiteralPath $main).Hash
    $copies = @((Join-Path $root 'Scripts/SelectionPanel.psm1'), (Join-Path $root 'Infrastructure/SelectionPanel.psm1')) + @(Get-ChildItem -LiteralPath $root -Directory -Filter 'Jobs*' | ForEach-Object { Join-Path $_.FullName 'Scripts/SelectionPanel.psm1' } | Where-Object { Test-Path -LiteralPath $_ })
    foreach ($copy in $copies) {
        Assert-Panel ((Get-FileHash -LiteralPath $copy).Hash -ceq $hash) '总面板、模板与独立包同字节'
        $bytes = [IO.File]::ReadAllBytes($copy)
        Assert-Panel ($bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) 'PowerShell5.1中文保留UTF8 BOM'
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($copy, [ref]$null, [ref]$errors)
        Assert-Panel (@($errors).Count -eq 0) '所有面板副本语法通过'
    }
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        Save-JobsPanelPreferences light zh-Hans -Path $path
        $fixture = @([pscustomobject]@{ Id = 'fixture'; Label = '📋 复制绝对路径'; Description = '复制文件或文件夹的绝对路径。'; Group = '本功能' })
        $state = & $module { param($Items, $Path) New-JobsFeatureSelectionForm -Packages $Items -Selected @('fixture') -Installed @() -Mode Manage -PreferencesPath $Path } $fixture $path
        try {
            $originalForm = $state.Form
            Assert-Panel ($state.LanguageBox.Items.Count-eq11) '原生下拉含跟随系统与全部十种语言'
            $autonyms=@($state.LanguageBox.Items)[0..9]-join'|'

            $state.LogView.Text = "日志原文`r`nC:\安装\日志.txt"
            $state.LogView.Select(1, 3)
            $savedLog = $state.LogView.Text
            $state.Running = $true
            $state.FeatureStates['fixture'] = 'Running'
            foreach ($theme in @('dark', 'light')) {
                foreach ($language in @('zh-Hans','zh-Hant','bo','en','ja','fr','es','de','ru','ko')) {
                    $state.Preferences.Theme = $theme; $state.Preferences.Language = $language
                    Update-JobsPanelPresentation $state -Force
                    Assert-Panel (-not $state.HeaderLabel.Bounds.IntersectsWith($state.PreferencePanel.Bounds) -and -not $state.HeaderDetailsLabel.Bounds.IntersectsWith($state.PreferencePanel.Bounds)) '十语言工具组不遮挡页眉标题和正文'
                    Assert-Panel ($state.PreferencePanel.Right -eq $state.Form.ClientSize.Width - $state.Padding) '十语言工具组右边距一致'
                    Assert-Panel ($state.ThemeBox.Height -eq $state.LanguageBox.Height -and $state.ThemeLabel.Height -eq $state.ThemeBox.Height -and $state.LanguageLabel.Height -eq $state.LanguageBox.Height) '主题语言标签与下拉同高并垂直居中'
                    $routeCenter = $state.RouteBox.Top + $state.RouteBox.Height / 2.0
                    $autoCenter = $state.CleanupPanel.Top + $state.AutoCleanup.Top + $state.AutoCleanup.Height / 2.0
                    $buttonCenter = $state.CleanupPanel.Top + $state.CleanupButton.Top + $state.CleanupButton.Height / 2.0
                    Assert-Panel ([Math]::Abs($routeCenter - $autoCenter) -le 1 -and [Math]::Abs($routeCenter - $buttonCenter) -le 1) '原生十语言位置自动清理与独立按钮同排垂直居中'
                    Assert-Panel ([object]::ReferenceEquals($state.RouteBox.Parent, $state.DeploymentRow) -and [object]::ReferenceEquals($state.CleanupPanel.Parent, $state.DeploymentRow)) '位置和清理控件共用同一部署行'
                    Assert-Panel ($state.CleanupPanel.Left -ge $state.RouteBox.Right + [int](12 * $state.Scale)) '原生位置下拉不覆盖清理控件'
                    Assert-Panel ([object]::ReferenceEquals($state.CleanupButton.Parent, $state.Footer) -and $state.CleanupButton.Left -ge $state.ConfirmButton.Right + [int](10*$state.Scale)) '红色清理按钮位于底部主执行按钮右侧'
                    Assert-Panel ($state.DeploymentRow.AutoScroll -and $state.DeploymentRow.AutoScrollMinSize.Width -ge $state.CleanupPanel.Right) '窄窗可水平访问完整部署行'
                    Assert-Panel ([object]::ReferenceEquals($state.Form, $originalForm) -and $state.Running -and $state.Checks[0].Checked -and $state.FeatureStates.fixture -eq 'Running') '活动任务换肤换语保留窗口事务与勾选'
                    Assert-Panel ((@($state.LanguageBox.Items)[0..9]-join'|')-ceq$autonyms) '切换UI语言保留全部语言自称'
                    $row=$state.FeatureRows.fixture;$featureStatus=$state.FeatureLabels.fixture
                    Assert-Panel ($row.Title.Right-lt$featureStatus.Left-and$row.Icon.Right-le$row.Title.Left) '长译文仍保留图标、名称与固定状态列'
                    Assert-Panel ($state.ThemeBox.AccessibleName-ceq(Get-JobsPanelText '主题' $language)-and$state.LanguageBox.AccessibleName-ceq(Get-JobsPanelText '语言' $language)) '原生辅助名称即时换语'
                    Assert-Panel ($state.LogView.Text -ceq $savedLog -and $state.LogView.SelectionStart -eq 1 -and $state.LogView.SelectionLength -eq 3) '旧日志文本与选择保持'
                    $state.LogView.SelectAll()
                    Assert-Panel ($state.LogView.SelectionColor.ToArgb() -eq $state.LogView.ForeColor.ToArgb()) '旧日志随主题重着色'
                    $state.LogView.Select(1, 3)
                    foreach ($button in @($state.ConfirmButton, $state.CancelButton, $state.SelectAllButton, $state.ClearButton)) {
                        Assert-Panel ($button.GetPreferredSize((New-Object Drawing.Size(0, 0))).Width -le $button.Width) '十语言底部按钮完整显示'
                    }
                }
            }
            $savedSize = $state.Form.ClientSize
            foreach ($width in @([int](680 * $state.Scale), [int](1280 * $state.Scale), [int](1600 * $state.Scale))) {
                $state.Form.ClientSize = New-Object Drawing.Size($width, $savedSize.Height)
                $state.Form.PerformLayout()
                Assert-Panel ($state.PreferencePanel.Right -eq $state.Form.ClientSize.Width - $state.Padding) 'ClientSize变化自动重定位右上工具组'
                Assert-Panel (-not $state.HeaderLabel.Bounds.IntersectsWith($state.PreferencePanel.Bounds)) '调整宽度后标题与工具组不重叠'
                Assert-Panel ($state.Running -and $state.Checks[0].Checked -and $state.LogView.Text -ceq $savedLog) '调整宽度保留活动任务勾选和日志'
            }
            $state.Form.ClientSize = $savedSize
            $rawMessage = "外部卸载错误`r`nC:\安装\已完成\原始.log"
            Set-JobsManagementFeatureState $state @('fixture') Failed $rawMessage
            foreach ($language in @('en', 'zh-Hant')) {
                $state.Preferences.Language = $language
                Update-JobsPanelPresentation $state -Force
                $tip = $state.ToolTip.GetToolTip($state.FeatureLabels.fixture)
                Assert-Panel ($tip.StartsWith($rawMessage) -and $tip.EndsWith($state.LogPath)) '运行中失败行切语言保留原始诊断和路径'
                $hint = Get-JobsPanelText '点击在新 PowerShell 窗口读取本次完整会话日志；当前任务继续运行。' $language
                Assert-Panel ($tip.Contains($hint) -and $state.FeatureLabels.fixture.Links.Count -eq 1) '失败链接提示即时换语并保持可点击'
            }
            Assert-Panel ($state.ThemeBox.DrawMode -eq 'OwnerDrawFixed' -and $state.LanguageBox.DrawMode -eq 'OwnerDrawFixed' -and $state.ThemeBox.Width -eq [int][Math]::Ceiling(112*$state.Scale)) '主题与语言使用紧凑居中文字控件'
            $state.Running = $false
            foreach ($operation in @('Install','Uninstall')) {
                & $module { param($s,$mode) Set-JobsPanelOperation $s $mode } $state $operation
                Update-JobsPanelPresentation $state -Force
                Assert-Panel ([object]::ReferenceEquals($state.CleanupButton.Parent,$state.Footer) -and $state.CleanupButton.Left -ge $state.ConfirmButton.Right+[int](10*$state.Scale)) '安装与卸载都保留主按钮右侧的清理入口'
            }

        } finally { $state.Form.Dispose(); $state.LogView.Font.Dispose(); $state.Font.Dispose(); $state.ToolTip.Dispose(); $state.Timer.Dispose() }
    } else { Write-Host 'SKIP: WinForms原生主题、十语言布局和系统跟随交互需在Windows运行；跨平台偏好、资源和语法已覆盖。' }
} finally {
    if ([IO.Directory]::Exists($temp)) { [IO.Directory]::Delete($temp, $true) }
}
Write-Host ('PASS: PanelPreferences.Tests.ps1 (' + $script:assertions + ' assertions)')

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

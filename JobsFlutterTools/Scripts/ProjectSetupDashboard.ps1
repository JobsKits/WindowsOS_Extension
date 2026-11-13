# ProjectSetupDashboard.ps1 | 里程碑与原生交互控制台。
# Created by Jobs on 2026年10月28日，星期三.
param([string]$Target=$env:JOBS_SETUP_TARGET,[switch]$Preview)
# 状态文案与点数独立计算，终态不保留执行动画。
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
function Get-JobsSetupStatusText {
 param([string]$State,[int]$DotCount=0)
 switch($State){
  'running' { return '◉ 进行中'+('.'*([Math]::Max(0,$DotCount)%6)) }
  'done' { return '✓ 已完成' }
  'waiting' { return '! 等待用户' }
  'failed' { return '✕ 失败 / 待处理' }
  'skipped' { return '○ 不适用' }
  'attention' { return '! 需确认状态' }
  default { return '○ 未开始' }
 }
}
# 依实际内容保留高度，窗口扩大时把额外空间交给终端。
function Get-JobsSetupMilestoneHeight {
 param([int[]]$ColumnHeights,[int]$AvailableHeight,[int]$TerminalMinimum=180,[int]$DividerWidth=8)
 $contentHeight=64
 foreach($height in $ColumnHeights){$contentHeight=[Math]::Max($contentHeight,$height)}
 return [Math]::Min($contentHeight,[Math]::Max(64,$AvailableHeight-$TerminalMinimum-$DividerWidth))
}
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw '运行仪表盘需要 Windows 图形桌面。' }
Import-Module (Join-Path $PSScriptRoot 'ProjectSetupLogTail.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'ProjectSetupProgress.psm1') -DisableNameChecking
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class JobsEmbeddedConsole {
 [DllImport("user32.dll",SetLastError=true)] public static extern IntPtr SetParent(IntPtr child,IntPtr parent);
 [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr child);
 [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr window);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr window);
 [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr window);
 [StructLayout(LayoutKind.Sequential)] public struct ClientRectangle { public int Left,Top,Right,Bottom; }
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr window,out ClientRectangle rectangle);
 // ConPTY may return a message-only HWND: it cannot serve as a visible console.
 public static bool HasDrawableClient(IntPtr window) { ClientRectangle rectangle; return IsWindow(window) && IsWindowVisible(window) && !IsIconic(window) && GetClientRect(window,out rectangle) && rectangle.Right > rectangle.Left && rectangle.Bottom > rectangle.Top; }
 [DllImport("user32.dll",EntryPoint="GetWindowLongW")] public static extern int GetStyle(IntPtr window,int index);
 [DllImport("user32.dll",EntryPoint="SetWindowLongW")] public static extern int SetStyle(IntPtr window,int index,int style);
 [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr window,int x,int y,int width,int height,bool repaint);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window,int action);
 public static int ChildStyle(int style) { return unchecked((int)(((uint)style & ~(0x80000000u | 0x00C00000u | 0x00040000u)) | 0x40000000u)); }
}
'@
$session=Join-Path ([IO.Path]::GetTempPath()) ('JobsFlutterSetup-'+[guid]::NewGuid().ToString('N'))
if (-not $Preview) { [void][IO.Directory]::CreateDirectory($session) }
$form=New-Object Windows.Forms.Form
$toolVersion=Get-JobsSetupVersion
$form.Text='Jobs · 一键配置 Flutter 项目至运行 · '+$toolVersion.Label
$workArea=[Windows.Forms.Screen]::FromPoint([Windows.Forms.Cursor]::Position).WorkingArea
$form.Size=New-Object Drawing.Size([Math]::Min(1240,[Math]::Max(900,$workArea.Width-40)),[Math]::Min(850,[Math]::Max(650,$workArea.Height-40)))
$form.MinimumSize=New-Object Drawing.Size(900,650)
$form.StartPosition='CenterScreen'
$form.Font=New-Object Drawing.Font('Microsoft YaHei UI',9)
$toolTips=New-Object Windows.Forms.ToolTip
$heading=New-Object Windows.Forms.Panel;$heading.Dock='Top';$heading.Height=78
$title=New-Object Windows.Forms.Label;$title.Text='一键配置 Flutter 项目';$title.Left=16;$title.Top=12;$title.Height=28;$title.Width=700;$title.Font=New-Object Drawing.Font($form.Font.FontFamily,15,[Drawing.FontStyle]::Bold)
$projectName=if([string]::IsNullOrWhiteSpace($Target)){'未指定项目'}else{Split-Path -Leaf $Target}
$metadata=New-Object Windows.Forms.Label;$metadata.Text=$projectName+'  ·  '+$toolVersion.Label;$metadata.Left=16;$metadata.Top=44;$metadata.Height=22;$metadata.Width=$form.ClientSize.Width-32;$metadata.Anchor='Top,Left,Right';$metadata.AutoEllipsis=$true;$metadata.ForeColor=[Drawing.Color]::DimGray
$toolTips.SetToolTip($metadata,$Target+"`r`n"+$toolVersion.Label)
$heading.Controls.Add($title);$heading.Controls.Add($metadata)
$top=New-Object Windows.Forms.TableLayoutPanel
$top.Dock='Top';$top.ColumnCount=9;$top.RowCount=1;$top.Margin=New-Object Windows.Forms.Padding(0)
for($i=0;$i-lt9;$i++){
 $style=if($i%2-eq0){New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,20)}else{New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,48)}
 [void]$top.ColumnStyles.Add($style)
}
$groups=@(
 @('环境','sdk.flutter','Flutter SDK','sdk.java','Java / jEnv'),
 @('平台工具链','platform.select','选择平台','platform.tools','SDK / C++ / 浏览器','platform.licenses','许可 / 私库'),
 @('依赖','deps.gradle','Gradle 分发','deps.pub','Pub 依赖','deps.plugins','构建插件'),
 @('设备与启动参数','run.device','设备 / 模拟器','run.arguments','入口 / Flavor / Defines'),
 @('运行验收','run.doctor','Doctor 检查','run.launch','编译 / 安装 / 启动','run.started','app.started 确认')
)
$componentNodes=@('sdk.flutter','sdk.java','platform.tools','deps.gradle','deps.plugins')
$labels=@{};$versionLabels=@{};$nodeTitles=@{};$nodeViews=@{};$heads=@();$columns=@()
for($g=0;$g-lt$groups.Count;$g++){
 $column=New-Object Windows.Forms.FlowLayoutPanel
 $column.Dock='Fill';$column.FlowDirection='TopDown';$column.WrapContents=$false;$column.Padding=New-Object Windows.Forms.Padding(12,10,8,8);$column.Margin=New-Object Windows.Forms.Padding(0)
 $head=New-Object Windows.Forms.Label
 $head.Text=(($g+1).ToString('00')+'  '+$groups[$g][0]);$head.AutoSize=$false;$head.Width=169;$head.Height=26;$head.AutoEllipsis=$true;$head.Margin=New-Object Windows.Forms.Padding(0,0,0,8);$head.Font=New-Object Drawing.Font($form.Font,[Drawing.FontStyle]::Bold);$head.ForeColor=[Drawing.Color]::Gray
 $toolTips.SetToolTip($head,$head.Text)
 $column.Controls.Add($head);$heads+=$head;$columns+=$column
 for($j=1;$j-lt$groups[$g].Count;$j+=2){
  $node=$groups[$g][$j]
  $nodeView=New-Object Windows.Forms.Panel;$nodeView.Width=195;$nodeView.Height=38;$nodeView.Margin=New-Object Windows.Forms.Padding(0,0,0,10)
  $nodeTitle=New-Object Windows.Forms.Label;$nodeTitle.Text=$groups[$g][$j+1];$nodeTitle.Width=195;$nodeTitle.Height=20;$nodeTitle.AutoEllipsis=$true
  $toolTips.SetToolTip($nodeTitle,$nodeTitle.Text)
  $label=New-Object Windows.Forms.Label;$label.Text=Get-JobsSetupStatusText pending;$label.Width=195;$label.Height=18;$label.Top=20;$label.AutoSize=$false;$label.AutoEllipsis=$true;$label.ForeColor=[Drawing.Color]::Gray
  $versionLabel=New-Object Windows.Forms.Label;$versionLabel.Text='';$versionLabel.Width=195;$versionLabel.Height=28;$versionLabel.Top=38;$versionLabel.AutoEllipsis=$true;$versionLabel.Font=New-Object Drawing.Font('Microsoft YaHei UI',8);$versionLabel.ForeColor=[Drawing.Color]::DimGray;$versionLabel.Visible=$false
  $nodeView.Controls.Add($nodeTitle);$nodeView.Controls.Add($label);$nodeView.Controls.Add($versionLabel);$column.Controls.Add($nodeView)
  $labels[$node]=$label;$versionLabels[$node]=$versionLabel;$nodeTitles[$node]=$nodeTitle;$nodeViews[$node]=$nodeView
 }
 $top.Controls.Add($column,$g*2,0)
 if($g-lt4){$arrow=New-Object Windows.Forms.Label;$arrow.Text='>>>>>';$arrow.AutoSize=$false;$arrow.Dock='Fill';$arrow.Font=New-Object Drawing.Font('Consolas',9,[Drawing.FontStyle]::Bold);$arrow.ForeColor=[Drawing.Color]::Gray;$arrow.Margin=New-Object Windows.Forms.Padding(0,12,0,0);$top.Controls.Add($arrow,$g*2+1,0)}
}
# 标题和状态各占一行；状态固定宽度，圆点变化不会挤动其它节点。
$resizeTop={
 $width=[Math]::Max(80,[int](($top.ClientSize.Width-4*48)/5)-20)
 foreach($view in $nodeViews.Values){$view.Width=$width}
 foreach($label in $nodeTitles.Values){$label.Width=$width}
 foreach($label in $labels.Values){$label.Width=$width}
 foreach($label in $versionLabels.Values){$label.Width=$width}
 foreach($head in $heads){$head.Width=$width}
}
$top.Add_Resize($resizeTop)
$bottom=New-Object Windows.Forms.Panel;$bottom.Dock='Bottom';$bottom.Height=48
$status=New-Object Windows.Forms.Label;$status.AutoSize=$false;$status.Dock='Fill';$status.Text='下方为真实 CMD / PowerShell 交互控制台；点击终端后使用键盘。';$status.Padding=New-Object Windows.Forms.Padding(10)
$logButton=New-Object Windows.Forms.Button;$logButton.Text='打开完整日志';$logButton.Dock='Right';$logButton.Width=130
$logButton.Add_Click({if(Test-Path -LiteralPath $session){Start-Process explorer.exe -ArgumentList ('"'+$session+'"')}})
$bottom.Controls.Add($status);$bottom.Controls.Add($logButton);$form.Controls.Add($bottom)
$console=New-Object Windows.Forms.Panel;$console.Dock='Fill';$console.BackColor=[Drawing.Color]::Black
$fallback=New-Object Windows.Forms.RichTextBox;$fallback.Dock='Fill';$fallback.ReadOnly=$true;$fallback.BackColor=[Drawing.Color]::Black;$fallback.ForeColor=[Drawing.Color]::Gainsboro;$fallback.Font=New-Object Drawing.Font('Consolas',10)
$fallback.Text=if($Preview){'仅预览界面：不会启动控制台、安装 SDK 或写配置。'}else{'正在建立原生交互控制台。若系统阻止嵌入，会明确切换到独立终端，并在此同步完整工具输出。'}
$console.Controls.Add($fallback)
# 真实可拖动上下分隔，终端维持原生控件并在调整时同步尺寸。
$split=New-Object Windows.Forms.SplitContainer
$split.Dock='Fill';$split.Orientation=[Windows.Forms.Orientation]::Horizontal;$split.SplitterWidth=8
$split.Size=New-Object Drawing.Size($form.ClientSize.Width,($form.ClientSize.Height-$bottom.Height-$heading.Height))
$split.Panel1MinSize=64;$split.Panel2MinSize=180
$split.FixedPanel=[Windows.Forms.FixedPanel]::Panel1;$split.IsSplitterFixed=$false
$split.BackColor=[Drawing.Color]::DimGray;$split.Panel1.BackColor=$form.BackColor;$split.Panel1.AutoScroll=$true
$split.Panel1.Controls.Add($top);$split.Panel2.Controls.Add($console)
$form.Controls.Add($split);$form.Controls.Add($heading);$split.BringToFront()
$script:dividerManuallySized=$false
$fitMilestones={
 $heights=@(foreach($column in $columns){
  $height=$column.Padding.Vertical
  foreach($control in $column.Controls){$height+=$control.Height+$control.Margin.Vertical}
  $height
 })
 $top.Height=($heights|Measure-Object -Maximum).Maximum
 if(-not $script:dividerManuallySized){$split.SplitterDistance=Get-JobsSetupMilestoneHeight $heights $split.ClientSize.Height $split.Panel2MinSize $split.SplitterWidth}
}
$split.Add_SplitterMoving({$script:dividerManuallySized=$true})
$split.Add_Resize($fitMilestones)
$script:consoleHandle=[IntPtr]::Zero;$script:consoleStyle=0;$script:embedded=$false;$script:worker=$null;$script:done=$false;$script:processed=0;$script:rawTail=New-JobsSetupLogTailState -Path (Join-Path $session 'raw.log');$script:consoleParent=[IntPtr]::Zero;$script:embedAttempts=0
$states=@{}
$colors=@{pending=[Drawing.Color]::Gray;running=[Drawing.Color]::RoyalBlue;waiting=[Drawing.Color]::DarkOrange;done=[Drawing.Color]::ForestGreen;failed=[Drawing.Color]::Firebrick;skipped=[Drawing.Color]::Gray;attention=[Drawing.Color]::DarkOrange}
$refreshGroupHeads={
 for($g=0;$g-lt$groups.Count;$g++){
  $groupStates=@();for($k=1;$k-lt$groups[$g].Count;$k+=2){$node=$groups[$g][$k];$groupStates+=if($states.ContainsKey($node)){$states[$node]}else{'pending'}}
  $groupState=if('failed'-in$groupStates){'failed'}elseif('attention'-in$groupStates){'attention'}elseif('waiting'-in$groupStates){'waiting'}elseif('running'-in$groupStates){'running'}elseif(@($groupStates|Where-Object{$_-notin@('done','skipped')}).Count-eq0){'done'}else{'pending'}
  $heads[$g].ForeColor=$colors[$groupState]
 }
}
# 控制台尺寸跟随下半面板，保留原生 TTY 和 fzf。
$resize={if($script:embedded-and[JobsEmbeddedConsole]::IsWindow($script:consoleHandle)){[void][JobsEmbeddedConsole]::MoveWindow($script:consoleHandle,0,0,$console.ClientSize.Width,$console.ClientSize.Height,$true)}}
$console.Add_Resize($resize)
$split.Add_SplitterMoved($resize)
$script:runningDotFrame=0
$activityTimer=New-Object Windows.Forms.Timer;$activityTimer.Interval=350
$activityTimer.Add_Tick({
 $script:runningDotFrame=($script:runningDotFrame+1)%6
 foreach($node in @($states.Keys)){if($states[$node]-eq'running'){$labels[$node].Text=Get-JobsSetupStatusText running $script:runningDotFrame}}
})
$stopActivity={
 $activityTimer.Stop()
 foreach($node in @($states.Keys)){
  if($states[$node]-eq'running'){$states[$node]='attention';$labels[$node].Text=Get-JobsSetupStatusText attention;$labels[$node].ForeColor=$colors.attention}
 }
 & $refreshGroupHeads
}
$timer=New-Object Windows.Forms.Timer;$timer.Interval=200
$timer.Add_Tick({
 if($Preview){return}
 try{
  $hwndPath=Join-Path $session 'console-hwnd.txt'
  if(-not$script:embedded-and(Test-Path -LiteralPath $hwndPath)-and$script:embedAttempts-lt30){
   $script:embedAttempts++
   $handle=[IntPtr][long]([IO.File]::ReadAllText($hwndPath))
   # 必须在 reparent 前验证可见且 client rect 非零，消息专用 HWND 不进入嵌入。
   if([JobsEmbeddedConsole]::HasDrawableClient($handle)){
    $script:consoleHandle=$handle;$script:consoleStyle=[JobsEmbeddedConsole]::GetStyle($handle,-16)
    $script:consoleParent=[JobsEmbeddedConsole]::GetParent($handle)
    [void][JobsEmbeddedConsole]::SetStyle($handle,-16,[JobsEmbeddedConsole]::ChildStyle($script:consoleStyle))
    [void][JobsEmbeddedConsole]::SetParent($handle,$console.Handle)
    if([JobsEmbeddedConsole]::GetParent($handle)-eq$console.Handle){
     [void][JobsEmbeddedConsole]::MoveWindow($handle,0,0,$console.ClientSize.Width,$console.ClientSize.Height,$true)
     [void][JobsEmbeddedConsole]::ShowWindow($handle,5)
     if([JobsEmbeddedConsole]::HasDrawableClient($handle)){$script:embedded=$true;$fallback.Visible=$false;$status.Text='下方是真实原生 CMD：fzf、许可证及运行控制均可直接输入。'}
    }
    if(-not $script:embedded){[void][JobsEmbeddedConsole]::SetParent($handle,$script:consoleParent);[void][JobsEmbeddedConsole]::SetStyle($handle,-16,$script:consoleStyle);[void][JobsEmbeddedConsole]::ShowWindow($handle,5);$status.Text='系统未允许嵌入，交互终端在独立窗口；下方增量显示原始日志末尾，完整文件保留。'}
   }else{$fallback.Visible=$true;$status.Text='控制台 HWND 不可见或无客户区，保持独立终端；下方增量显示日志末尾，完整文件保留。'}
  }
  if(-not $script:embedded -and $script:embedAttempts -ge 30){$status.Text='本系统未提供可嵌入控制台，交互在独立 CMD；下方仅显示日志末尾约20万字符，完整文件保留。'}
  $events=Join-Path $session 'events.jsonl'
  if(Test-Path -LiteralPath $events){
   $lines=[IO.File]::ReadAllLines($events)
   while($script:processed-lt$lines.Count){
    $event=$lines[$script:processed]|ConvertFrom-Json
    $script:processed++
    if($event.node-eq'overall'){$status.Text=$event.detail;$script:done=$event.state-in@('done','failed')}
    elseif($labels.ContainsKey($event.node)){
     $states[$event.node]=$event.state;$label=$labels[$event.node]
     $toolTips.SetToolTip($label,[string]$event.detail)
     if($null-ne$event.PSObject.Properties['version']-and-not[string]::IsNullOrWhiteSpace([string]$event.version)){$versionLabel=$versionLabels[$event.node];$versionLabel.Text='版本：'+[string]$event.version;$versionLabel.Visible=$true;$nodeViews[$event.node].Height=66;$toolTips.SetToolTip($versionLabel,[string]$event.version);$toolTips.SetToolTip($label,[string]$event.version+"`r`n"+[string]$event.detail)}
     if($event.state-eq'skipped'-and$event.node-in$componentNodes){$versionLabels[$event.node].Text='版本：不适用';$versionLabels[$event.node].Visible=$true;$nodeViews[$event.node].Height=66;$toolTips.SetToolTip($versionLabels[$event.node],[string]$event.detail)}
     $label.Text=Get-JobsSetupStatusText $event.state $script:runningDotFrame;$label.ForeColor=$colors[$event.state]
     & $fitMilestones
     & $refreshGroupHeads
     $status.Text=$event.detail
    }
   }
  }
  if($script:worker -and $script:worker.HasExited -and -not $script:done){$status.Text='本次控制台已退出；请检查完整日志确认最后成功阶段。';$script:done=$true}
  if($script:done){& $stopActivity}
  if(-not$script:embedded){
   $chunk=Read-JobsSetupLogTail -State $script:rawTail
   if($chunk.Changed){
    if($chunk.Reset){$fallback.Clear()}
    if($chunk.Text.Length){$fallback.AppendText($chunk.Text)}
    if($fallback.TextLength-gt$script:rawTail.MaxDisplayChars){
     $trim=$fallback.TextLength-$script:rawTail.MaxDisplayChars
     $visible=$fallback.Text
     if($trim-gt0-and$trim-lt$visible.Length-and[char]::IsLowSurrogate($visible[$trim])-and[char]::IsHighSurrogate($visible[$trim-1])){$trim++}
     $fallback.Select(0,$trim);$fallback.SelectedText=''
    }
    $fallback.SelectionStart=$fallback.TextLength;$fallback.ScrollToCaret()
   }
  }
 }catch{# 写入中的最后一行或窗口创建尚未完成，下一轮读取同一游标。
 }
})
$form.Add_Shown({
 & $resizeTop
 & $fitMilestones
 $activityTimer.Start()
 if($Preview){$states['sdk.flutter']='running';$labels['sdk.flutter'].Text=Get-JobsSetupStatusText running;$labels['sdk.flutter'].ForeColor=$colors.running;return}
 try{
  $start=New-Object Diagnostics.ProcessStartInfo
  $conhost=Join-Path ([Environment]::GetFolderPath('System')) 'conhost.exe'
  $cmd=Join-Path ([Environment]::GetFolderPath('System')) 'cmd.exe'
  $command='/d /v:off /s /c ""%JOBS_SETUP_POWERSHELL%" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%JOBS_SETUP_WORKER%""'
  $start.FileName=$conhost;$start.Arguments='"'+$cmd+'" '+$command
  $start.UseShellExecute=$false;$start.CreateNoWindow=$false;$start.WorkingDirectory=$Target
  $start.EnvironmentVariables['JOBS_SETUP_POWERSHELL']=Join-Path $PSHOME 'powershell.exe'
  $start.EnvironmentVariables['JOBS_SETUP_WORKER']=Join-Path $PSScriptRoot 'ProjectSetupWorker.ps1'
  $start.EnvironmentVariables['JOBS_SETUP_TARGET']=$Target;$start.EnvironmentVariables['JOBS_SETUP_SESSION']=$session
  try{$script:worker=[Diagnostics.Process]::Start($start)}catch{$start.FileName=$cmd;$start.Arguments=$command;$script:worker=[Diagnostics.Process]::Start($start);$status.Text='conhost 不可用，使用独立 CMD 交互回退。'}
  $timer.Start()
 }catch{$status.Text='启动失败：'+$_.Exception.Message;$script:done=$true;& $stopActivity}
})
$form.Add_FormClosing({
 param($sender,$event)
 if($script:worker-and-not$script:worker.HasExited){
  $choice=if($script:done){[Windows.Forms.DialogResult]::Yes}else{[Windows.Forms.MessageBox]::Show('是：停止本次任务及子进程后关闭。否：转为独立终端继续运行。取消：返回仪表盘。','本次任务仍在进行',[Windows.Forms.MessageBoxButtons]::YesNoCancel)}
  if($choice-eq[Windows.Forms.DialogResult]::Cancel){$event.Cancel=$true;return}
  if($choice-eq[Windows.Forms.DialogResult]::No){if($script:embedded){[void][JobsEmbeddedConsole]::SetParent($script:consoleHandle,$script:consoleParent);[void][JobsEmbeddedConsole]::SetStyle($script:consoleHandle,-16,$script:consoleStyle);[void][JobsEmbeddedConsole]::ShowWindow($script:consoleHandle,5)}}
  else{& (Join-Path ([Environment]::GetFolderPath('System')) 'taskkill.exe') /PID $script:worker.Id /T /F | Out-Null;if($LASTEXITCODE-ne0){$event.Cancel=$true;[void][Windows.Forms.MessageBox]::Show('停止本次子进程树失败，仪表盘保留。请在原始终端检查 UAC / 安装器状态后重试。','停止失败');return}}
 }
 $timer.Stop();$activityTimer.Stop()
})
try{[void]$form.ShowDialog()}finally{$timer.Dispose();$activityTimer.Dispose();$toolTips.Dispose();$form.Dispose()}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

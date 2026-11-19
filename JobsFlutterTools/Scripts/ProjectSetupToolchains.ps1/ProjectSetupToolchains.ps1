# ProjectSetupToolchains.ps1 | 一键配置按平台复用的工具发现、准备与复检。
# Created by Jobs on 2026年11月4日，星期三.
# 仅由 ProjectSetup 加载；安装前明确选择，运行时 PATH 变化由上层 finally 恢复。


# JOBS_SOURCE_LAYOUT_ROOT_V1：只解析本文件逻辑目录，发布 flat 副本保持原资源基准。
$script:JobsLayoutProjectSetupToolchainsRoot = $(if ([IO.Path]::GetFileName($PSScriptRoot) -ceq 'ProjectSetupToolchains.ps1') { Split-Path -Parent $PSScriptRoot } else { $PSScriptRoot })

# JOBS_WINGET_NECESSARY_NATIVE_V1_BEGIN
# 按Windows原生argv规则保留参数边界，不通过命令字符串求值。
function ConvertTo-JobsWingetNativeArgument {
    param([AllowNull()][AllowEmptyString()][string]$Value)
    if ($null -eq $Value) { $Value = '' }
    if ($Value.IndexOf([char]0) -ge 0) { throw '参数不能包含空字符。' }
    $quoted = New-Object Text.StringBuilder
    [void]$quoted.Append('"')
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq [char]92) { $slashes++; continue }
        if ($character -eq [char]34) {
            [void]$quoted.Append([char]92, (2 * $slashes + 1))
            [void]$quoted.Append([char]34)
        } else {
            if ($slashes -gt 0) { [void]$quoted.Append([char]92, $slashes) }
            [void]$quoted.Append($character)
        }
        $slashes = 0
    }
    if ($slashes -gt 0) { [void]$quoted.Append([char]92, (2 * $slashes)) }
    [void]$quoted.Append('"')
    return $quoted.ToString()
}
# 隔离原生工具健康探针并限制单次时长，不改父进程环境。
function Invoke-JobsWingetNativeProbe {
    param([string]$Executable, [string[]]$NativeArguments, [string[]]$InputLines = @(), [switch]$Probe)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Executable
    $start.Arguments = (@($NativeArguments | ForEach-Object { ConvertTo-JobsWingetNativeArgument $_ }) -join ' ')
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = [bool]$Probe
    $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    if ($Probe) { $start.StandardErrorEncoding = New-Object Text.UTF8Encoding($false) }
    foreach ($key in @('FZF_DEFAULT_OPTS', 'FZF_DEFAULT_OPTS_FILE', 'FZF_DEFAULT_COMMAND')) { [void]$start.EnvironmentVariables.Remove($key) }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = if ($Probe) { $process.StandardError.ReadToEndAsync() } else { $null }
        $inputWriter = New-Object IO.StreamWriter($process.StandardInput.BaseStream, (New-Object Text.UTF8Encoding($false)))
        $inputWriter.NewLine = "`n"
        try { foreach ($line in $InputLines) { $inputWriter.WriteLine($line) } } finally { $inputWriter.Dispose() }
        if ($Probe) {
            if (-not $process.WaitForExit(10000)) {
                $process.Kill(); $process.WaitForExit()
                return [pscustomobject]@{ Code = 124; Lines = @(); Error = '原生工具健康探针超时（10 秒）。' }
            }
        } else { $process.WaitForExit() }
        $output = $outputTask.GetAwaiter().GetResult()
        $errorText = if ($errorTask) { $errorTask.GetAwaiter().GetResult() } else { '' }
        $lines = @()
        if ($output.Length -gt 0) { $lines = @($output.Replace("`r`n", "`n").TrimEnd([char]10) -split "`n") }
        return [pscustomobject]@{ Code = $process.ExitCode; Lines = $lines; Error = $errorText }
    } finally {
        try { if ($process.Id -gt 0 -and -not $process.HasExited) { $process.Kill(); $process.WaitForExit() } } catch { }
        $process.Dispose()
    }
}
# 只刷新当前进程的原生工具路径，不持久化环境变更。
function Update-JobsWingetNativePath {
    param([string]$ExecutableDirectory)
    $parts = New-Object 'Collections.Generic.List[string]'
    $separator = [IO.Path]::PathSeparator
    foreach ($value in @($ExecutableDirectory, [Environment]::GetEnvironmentVariable('Path', 'User'), [Environment]::GetEnvironmentVariable('Path', 'Machine'), $env:Path)) {
        foreach ($part in @(([string]$value) -split [regex]::Escape([string]$separator))) {
            if (-not [string]::IsNullOrWhiteSpace($part) -and -not $parts.Contains($part)) { $parts.Add($part) }
        }
    }
    $env:Path = $parts -join [string]$separator
}
# 只读发现当前用户已注册且能够运行的WinGet。
function Find-JobsNativeWinget {
    $command = Get-Command 'winget.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $candidates = @()
    if ($command) { $candidates += $command.Source }
    if ($env:LOCALAPPDATA) { $candidates += Join-Path $env:LOCALAPPDATA 'Microsoft/WindowsApps/winget.exe' }
    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if (-not [IO.File]::Exists($candidate)) { continue }
        try { $probe = Invoke-JobsWingetNativeProbe $candidate @('--version') -Probe; if ($probe.Code -eq 0) { return $candidate } } catch [Management.Automation.PipelineStoppedException] { throw } catch { }
    }
    return $null
}
# 仅必需安装分支准备当前用户App Installer，一次打开官方界面并等待复检。
function Get-JobsNativeRequiredWinget {
    $winget = Find-JobsNativeWinget
    if ($winget) { return $winget }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw '当前不是 Windows，未调用 App Installer 或安装 Windows 依赖。' }
    Write-JobsWingetNativeStatus '本次需要 Windows 原生 App Installer/winget；仅注册当前用户已有组件，不接受许可或修改系统策略。'
    $registration = Get-Command Add-AppxPackage -ErrorAction SilentlyContinue
    if ($registration -and $registration.Parameters.ContainsKey('RegisterByFamilyName')) {
        try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop } catch { Write-JobsWingetNativeStatus ('App Installer 注册未就绪：' + $_.Exception.Message) }
        $winget = Find-JobsNativeWinget
        if ($winget) { Update-JobsWingetNativePath ([IO.Path]::GetDirectoryName($winget)); return $winget }
    }
    Write-JobsWingetNativeStatus '官方 App Installer：https://apps.microsoft.com/detail/9NBLGGH4NNS1；将打开一次官方页面。请按系统要求完成安装/许可，本入口持续复检并续行，Ctrl+C 停止等待。'
    Start-Process -FilePath 'ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1' -ErrorAction Stop | Out-Null
    while ($true) {
        Update-JobsWingetNativePath
        $winget = Find-JobsNativeWinget
        if ($winget) { return $winget }
        Write-JobsWingetNativeStatus '等待官方 App Installer 安装和当前用户注册；不会重复打开窗口，Ctrl+C 取消。'
        Start-Sleep -Seconds 3
    }
}
# 将原生包管理诊断安全送往业务展示与纯文本日志。
function Write-JobsWingetNativeStatus {
    [CmdletBinding()]
    param([string]$Text)
    $plain=$Text -replace '\x1b\][^\x07]*(?:\x07|\x1b\\)', '' -replace '\x1b\[[0-?]*[ -/]*[@-~]', ''
    $plain=$plain -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@' -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]' -replace '(?im)((?:token|password|secret|authorization)\s*[:=]\s*)\S+', '$1[已省略]'
    foreach($name in @('Write-JobsFvmMessage','Write-JobsSetupMessage','Write-JobsWorkerMessage','Write-JobsStatus','Write-JobsLog')){
        $writer=Get-Command $name -CommandType Function -ErrorAction SilentlyContinue
        if($writer){&$writer $plain;return}
    }
    Write-Host $plain
}
# 捕获展示副本但保持原生stdin与许可交互；不传accept/disable，不自动接受许可或提升权限。
function Invoke-JobsNativeWinget {
    param([string]$Winget,[string[]]$Arguments)
    $text=New-Object Collections.Generic.List[string];$saved=$ErrorActionPreference;$failure=$null;$PSNativeCommandUseErrorActionPreference=$false
    try {
        $ErrorActionPreference='Continue';$global:LASTEXITCODE=-1
        &$Winget @Arguments 2>&1|ForEach-Object {$line=[string]$_;$text.Add($line);try{Write-JobsWingetNativeStatus $line -ErrorAction Stop}catch{$failure=$_.Exception;throw}}
        $code=$LASTEXITCODE
    }finally{$ErrorActionPreference=$saved}
    if($failure){throw $failure}
    return [pscustomobject]@{Code=$code;Text=($text-join"`n")}
}
# 只对必要工具的临时获取故障持续重试，取消和确定阻塞立即停止。
function Invoke-JobsNativeWingetRetry {
    param([string]$Winget,[string[]]$Arguments)
    $delay=1
    while($true){
        $result=Invoke-JobsNativeWinget $Winget $Arguments
        if($result.Code-in@(129,130,137,143,1223,1602,-1073741510,-2147023673)){throw(New-Object OperationCanceledException('本人已取消原生包管理操作。'))}
        if($result.Code-in@(3010,1641)){throw '包管理器要求重启，请本人处理后继续；不会自动重启。'}
        if($result.Code-eq0){return $result}
        $plain=$result.Text -replace '\x1b\][^\x07]*(?:\x07|\x1b\\)', '' -replace '\x1b\[[0-?]*[ -/]*[@-~]', ''
        $plain=$plain -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@' -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]' -replace '(?im)((?:token|password|secret|authorization)\s*[:=]\s*)\S+', '$1[已省略]'
        if($plain-match'(?i)permission|access.denied|no.space|disk.full|hash|checksum|certificate|unauthor|license|agreement|unsupported|not.supported|unknown.command|unrecognized|no.applicable|no.package|no.installed.package|not.found|already.installed|no.available.upgrade|requires?.*reboot|权限|拒绝|空间不足|许可|协议|不支持|未知命令|无法找到|找不到|没有找到|不存在|无适用|已安装|需要重启') {throw ('原生包管理遇到明确阻塞，退出码 '+$result.Code+'：'+$plain)}
        Write-JobsWingetNativeStatus ('包管理网络获取失败；'+$delay+'秒后沿当前流程重试，Ctrl+C停止。')
        Start-Sleep -Seconds $delay;$delay=[Math]::Min(30,$delay*2)
    }
}
# JOBS_WINGET_NECESSARY_NATIVE_V1_END

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
function Get-JobsSetupNodeConstraints {
    param([string]$Directory, $Manifest, [string]$Project)
    $constraints = @()
    if ($Manifest.PSObject.Properties['engines'] -and $Manifest.engines.PSObject.Properties['node']) {
        $constraints += [string]$Manifest.engines.node
    }
    foreach ($scope in @(@($Project,$Directory) | Where-Object {$_} | Select-Object -Unique)) {
        foreach ($name in @('.nvmrc','.node-version')) {
            $file = Join-Path $scope $name
            if ([IO.File]::Exists($file)) {
                Assert-JobsSetupFile $file
                $value = [IO.File]::ReadAllText($file).Trim()
                if ($value -notmatch '^v?[0-9]+(?:\.[0-9]+){0,2}$') { throw ($name+' 不是可核验的数字版本，请先将别名固定为项目所需版本。') }
                $constraints += $value.TrimStart('v')
            }
        }
    }
    return $constraints
}

function Get-JobsSetupWebNode {
    param([string]$Directory, [string[]]$NodeConstraints)
    $candidates = @()
    $existing = Find-JobsExecutable 'node.exe' @('node')
    if ($existing) { $candidates += $existing }
    $cache = Join-Path (Get-JobsInstallRoot) 'toolchains'
    $arch = if ($env:PROCESSOR_ARCHITECTURE -ceq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -ceq 'ARM64') {'arm64'} else {'x64'}
    if ([IO.Directory]::Exists($cache)) {
        foreach ($entry in @(Get-ChildItem -LiteralPath $cache -Directory | Where-Object {$_.Name -match ('^node-[0-9]+\.[0-9]+\.[0-9]+-'+$arch+'$')} | Sort-Object {[version](($_.Name -split '-')[1])} -Descending)) {
            $version = ($entry.Name -split '-')[1]
            $path = Join-Path $entry.FullName ('sdk/node-v'+$version+'-win-'+$arch+'/node.exe')
            if ([IO.File]::Exists($path)) { $candidates += $path }
        }
    }
    $failures = @()
    foreach ($node in @($candidates | Select-Object -Unique)) {
        try {
            $probe = Invoke-JobsSetupProcess $node @('--version') $Directory 30
            if (($probe.StdOut+$probe.StdErr).Trim() -notmatch '^v?([0-9]+\.[0-9]+\.[0-9]+)$') { throw 'Node.js 未返回有效版本。' }
            $nodeVersion = $Matches[1]
            if ($NodeConstraints.Count) {
                $npm = Join-Path (Split-Path -Parent $node) 'npm.cmd'
                if (-not [IO.File]::Exists($npm)) { $npm = Find-JobsExecutable 'npm.cmd' @('npm.bat','npm.exe','npm') }
                if (-not $npm) { throw '核对 engines.node 需要 Node 所带 npm/semver，请选择完整 Node 发行包。' }
                # 用 npm 自带 semver 解释原始范围，不自行删改 ^、|| 或比较表达式。
                $code = 'const p=require("path"),ranges=JSON.parse(process.argv[1]);let s;for(const b of [p.dirname(process.argv[2]),p.join(p.dirname(process.argv[2]),"node_modules/npm"),p.dirname(process.execPath),p.join(p.dirname(process.execPath),"node_modules/npm")]){try{s=require(require.resolve("semver",{paths:[b]}));break}catch(e){}}if(!s)throw Error("npm semver missing");if(!ranges.every(r=>s.validRange(r)&&s.satisfies(process.versions.node,r)))throw Error("Node version conflicts with project declarations");console.log("JOBS_NODE_ENGINE_OK")'
                $probe = Invoke-JobsSetupProcess $node @('-e',$code,(ConvertTo-Json -InputObject @($NodeConstraints) -Compress),$npm) $Directory 30
                if ($probe.StdOut -notmatch '(?m)^JOBS_NODE_ENGINE_OK\s*$') { throw 'Node.js 没有通过项目版本约束复检。' }
            }
            if ([IO.File]::Exists($node)) { $env:PATH=(Split-Path -Parent $node)+[IO.Path]::PathSeparator+$env:PATH }
            return [pscustomobject]@{Node=$node;Version=$nodeVersion}
        } catch { $failures += $_.Exception.Message }
    }
    throw ('Node.js 没有可用且符合项目约束的运行时：'+($failures -join '；'))
}

function Get-JobsSetupWebTools {
    param([string]$Directory, [string]$Manager, [string]$PinnedVersion, [string[]]$NodeConstraints)
    $node = Get-JobsSetupWebNode $Directory $NodeConstraints
    $tool = Find-JobsExecutable ($Manager+'.cmd') @(($Manager+'.bat'),($Manager+'.exe'),$Manager)
    if ($PinnedVersion) {
        $cached = Join-Path (Get-JobsInstallRoot) ('toolchains/js-'+$Manager+'-'+$PinnedVersion+'/'+$Manager+'.cmd')
        if ([IO.File]::Exists($cached)) { $tool=$cached; $env:PATH=(Split-Path -Parent $cached)+[IO.Path]::PathSeparator+$env:PATH }
    }
    if (-not $tool) { throw ('缺少项目包管理器 '+$Manager+'。') }
    $probe = Invoke-JobsSetupProcess $tool @('--version') $Directory 30
    $version = ($probe.StdOut+$probe.StdErr).Trim()
    if ($version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') { throw '包管理器未返回可核验的版本。' }
    if ($PinnedVersion -and $version -cne $PinnedVersion) { throw ('包管理器实际版本 '+$version+' 不符合项目固定版本 '+$PinnedVersion+'。') }
    return [pscustomobject]@{Node=$node.Node;NodeVersion=$node.Version;Tool=$tool;Version=$version}
}

function Install-JobsSetupWebNode {
    param([string]$Directory, [string[]]$Constraints)
    Write-JobsSetupMessage ('Node.js 来源：https://nodejs.org/dist/；项目版本要求：'+$(if($Constraints.Count){$Constraints -join ' 且 '}else{'工程未固定，须本人明确选择精确版本'}))
    $version = (Read-JobsSetupInput '输入所需 Node 精确版本 x.y.z（空输入取消；不自动采用 latest）' platform.tools).Trim().TrimStart('v')
    if ($version -cnotmatch '^[0-9]+\.[0-9]+\.[0-9]+$') { throw '未提供精确 Node 版本，已停止。' }
    $architecture = if ($env:PROCESSOR_ARCHITECTURE -ceq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -ceq 'ARM64') {'arm64'} else {'x64'}
    $cache = Join-Path (Get-JobsInstallRoot) ('toolchains/node-'+$version+'-'+$architecture)
    Assert-JobsSetupDirectory $cache
    $name = 'node-v'+$version+'-win-'+$architecture
    $bin = Join-Path $cache ('sdk/'+$name)
    Assert-JobsSetupDirectory $bin
    $healthy = $false
    if ([IO.File]::Exists((Join-Path $bin 'node.exe')) -and [IO.File]::Exists((Join-Path $bin 'npm.cmd'))) {
        try {
            $nodeProbe = Invoke-JobsSetupProcess (Join-Path $bin 'node.exe') @('--version') $Directory 30
            $npmProbe = Invoke-JobsSetupProcess (Join-Path $bin 'npm.cmd') @('--version') $Directory 30
            $healthy = ($nodeProbe.StdOut+$nodeProbe.StdErr).Trim() -ceq ('v'+$version) -and ($npmProbe.StdOut+$npmProbe.StdErr).Trim() -match '^\d+\.\d+\.\d+$'
        } catch { Write-JobsSetupMessage ('现有 Node 缓存需修复：'+$_.Exception.Message) }
    }
    if (-not $healthy) {
        [void][IO.Directory]::CreateDirectory($cache)
        $source = 'https://nodejs.org/dist/v'+$version+'/'
        $checksums = Join-Path $cache 'SHASUMS256.txt'
        [void](Receive-JobsSetupFile @($source+'SHASUMS256.txt') $checksums 60)
        $entries = [regex]::Matches([IO.File]::ReadAllText($checksums),'(?m)^([a-fA-F0-9]{64})\s+\*?'+[regex]::Escape($name+'.zip')+'\s*$')
        if ($entries.Count -ne 1) { throw '官方 Node 元数据没有唯一匹配的 Windows 归档。' }
        $zip = Join-Path $cache ($name+'.zip')
        Write-JobsSetupMessage ('安装对象：Node '+$version+'；来源：'+$source+$name+'.zip；位置：'+$cache)
        if (-not [IO.File]::Exists($zip) -or (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ine $entries[0].Groups[1].Value) {
            [void](Receive-JobsSetupFile @($source+$name+'.zip') $zip 900)
        }
        if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ine $entries[0].Groups[1].Value) { throw 'Node ZIP SHA-256 不符，未解压或执行。' }
        $stage = Join-Path $cache ('stage-'+[guid]::NewGuid().ToString('N'))
        Expand-JobsSetupZip $zip $stage
        $staged = Join-Path $stage $name
        foreach ($file in @('node.exe','npm.cmd')) { if (-not [IO.File]::Exists((Join-Path $staged $file))) { throw 'Node 发行包不完整，缺少 Node / npm。' } }
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $bin))
        if ([IO.Directory]::Exists($bin)) { [IO.Directory]::Move($bin,($bin+'.jobs-invalid-'+[guid]::NewGuid().ToString('N'))) }
        [IO.Directory]::Move($staged,$bin)
        [IO.Directory]::Delete($stage)
    }
    $env:PATH = $bin+[IO.Path]::PathSeparator+$env:PATH
    $nodeProbe = Invoke-JobsSetupProcess (Join-Path $bin 'node.exe') @('--version') $Directory 30
    $npmProbe = Invoke-JobsSetupProcess (Join-Path $bin 'npm.cmd') @('--version') $Directory 30
    if (($nodeProbe.StdOut+$nodeProbe.StdErr).Trim() -cne ('v'+$version) -or ($npmProbe.StdOut+$npmProbe.StdErr).Trim() -notmatch '^\d+\.\d+\.\d+$') { throw 'Node / npm 安装后精确版本与健康复检失败。' }
    [void](Get-JobsSetupWebNode $Directory $Constraints)
}

function Install-JobsSetupWebManager {
    param([string]$Directory, [string]$Manager, [string]$PinnedVersion)
    $version = $PinnedVersion
    if (-not $version) { $version = (Read-JobsSetupInput ('工程未固定 '+$Manager+'，输入精确版本 x.y.z（空输入取消）') platform.tools).Trim() }
    if ($version -cnotmatch '^[0-9]+\.[0-9]+\.[0-9]+$') { throw '未选择精确包管理器版本，已停止。' }
    $prefix = Join-Path (Get-JobsInstallRoot) ('toolchains/js-'+$Manager+'-'+$version)
    Assert-JobsSetupDirectory $prefix
    $cached = Join-Path $prefix ($Manager+'.cmd')
    if ([IO.File]::Exists($cached)) {
        try {
            $probe = Invoke-JobsSetupProcess $cached @('--version') $Directory 30
            if (($probe.StdOut+$probe.StdErr).Trim() -ceq $version) { $env:PATH=$prefix+[IO.Path]::PathSeparator+$env:PATH; return }
        } catch { Write-JobsSetupMessage ('现有包管理器缓存需修复：'+$_.Exception.Message) }
    }
    $npm = Find-JobsExecutable 'npm.cmd' @('npm.bat','npm.exe','npm')
    if (-not $npm) { throw '安装包管理器需要完整 Node 自带的 npm；请先选择安装/切换 Node。' }
    [void](Invoke-JobsSetupProcess $npm @('--version') $Directory 30)
    $package = if ($Manager -ceq 'yarn' -and ([version]$version).Major -ge 2) {'@yarnpkg/cli-dist'} else {$Manager}
    [void][IO.Directory]::CreateDirectory($prefix)
    $registry = Invoke-JobsSetupProcess $npm @('config','get','registry') $Directory 30
    Write-JobsSetupMessage ('安装对象：'+$package+'@'+$version+'；来源：'+$registry.StdOut.Trim()+'（当前 npm registry，沿用项目认证）；位置：'+$prefix)
    [void](Invoke-JobsSetupProcess $npm @('install','--global','--prefix',$prefix,'--no-audit','--no-fund','--ignore-scripts',($package+'@'+$version)) $Directory 900)
    $tool = Join-Path $prefix ($Manager+'.cmd')
    if (-not [IO.File]::Exists($tool)) { throw '所选包管理器安装后缺少命令入口。' }
    $env:PATH = $prefix+[IO.Path]::PathSeparator+$env:PATH
    $probe = Invoke-JobsSetupProcess $tool @('--version') $Directory 30
    if (($probe.StdOut+$probe.StdErr).Trim() -cne $version) { throw '所选包管理器安装后精确版本复检失败。' }
}

function Initialize-JobsSetupWebTools {
    param([string]$Directory, $Manifest, [string]$Manager, [string]$Project)
    $constraints = @(Get-JobsSetupNodeConstraints $Directory $Manifest $Project)
    $pinned = ''
    if ($Manifest.PSObject.Properties['packageManager']) {
        if ([string]$Manifest.packageManager -cnotmatch ('^'+$Manager+'@([0-9]+\.[0-9]+\.[0-9]+)(?:\+sha(?:224|256|384|512)\.[A-Za-z0-9+/=]+)?$')) { throw 'packageManager 须固定为可核验的精确版本。' }
        $pinned = $Matches[1]
    }
    try { return Get-JobsSetupWebTools $Directory $Manager $pinned $constraints }
    catch { Write-JobsSetupMessage ('Web 工具链未就绪：'+$_.Exception.Message) }
    $fzf = Get-JobsSetupFzf $Directory
    $choice = Select-JobsSetupChoice $fzf 'Web 工具链准备（仅用户缓存与本次进程）' @('安装/切换 Node 与项目包管理器','只安装/切换项目包管理器','已自行处理，重新检查')
    if ($choice.StartsWith('安装/切换 Node')) { Install-JobsSetupWebNode $Directory $constraints }
    [void](Get-JobsSetupWebNode $Directory $constraints)
    if (-not $choice.StartsWith('已自行')) { Install-JobsSetupWebManager $Directory $Manager $pinned }
    # 只在完整二次健康检查后，才允许后续 ci/install 修改工程依赖。
    return Get-JobsSetupWebTools $Directory $Manager $pinned $constraints
}

function Get-JobsSetupOhosWrapper {
    param([string]$Project)
    $directory = Join-Path $Project 'ohos'
    foreach ($relative in @('oh-package.json5','hvigor/hvigor-config.json5')) {
        $file = Join-Path $directory $relative
        Assert-JobsSetupFile $file
        if (-not [IO.File]::Exists($file)) { throw ('缺少鸿蒙工程声明：'+$file) }
    }
    $wrapper = $null
    foreach ($name in @('hvigorw.bat','hvigorw.cmd','hvigorw')) {
        $file = Join-Path $directory $name
        if ([IO.File]::Exists($file)) { Assert-JobsSetupFile $file; $wrapper = $file; break }
    }
    if (-not $wrapper) { throw '工程缺少自身 Hvigor wrapper，请恢复工程固定版本的 wrapper。' }
    return $wrapper
}

function Get-JobsSetupOhosTools {
    param([string]$Project)
    $directory = Join-Path $Project 'ohos'
    $wrapper = Get-JobsSetupOhosWrapper $Project
    $packager = Import-Module (Join-Path ${script:JobsLayoutProjectSetupToolchainsRoot} 'Actions/package/Scripts/Action.psm1') -PassThru -DisableNameChecking
    & $packager { Initialize-JobsPackagerHarmonyEnvironment }
    if (-not $env:DEVECO_SDK_HOME -or -not [IO.Directory]::Exists($env:DEVECO_SDK_HOME)) { throw '没有有效 HarmonyOS SDK 根目录。' }
    $versions = @()
    $tools = @{}
    foreach ($spec in @(@('Node','node.exe','--version'),@('npm','npm.cmd','--version'),@('ohpm','ohpm.bat','--version'),@('Java','java.exe','-version'))) {
        $tool = Find-JobsExecutable $spec[1] @($spec[1].Replace('.cmd','.bat'),$spec[1].Replace('.bat','.cmd'),($spec[1] -replace '\.(exe|cmd|bat)$',''))
        if (-not $tool) { throw ('缺少 DevEco 工具链组件：'+$spec[0]) }
        $probe = Invoke-JobsSetupProcess $tool @($spec[2]) $directory 30
        if (($probe.StdOut+$probe.StdErr) -notmatch '(?i)(?:version\s+["'']?|\bv?)([0-9]+(?:\.[0-9]+)+)') { throw ($spec[0]+' 未返回有效版本。') }
        $versions += $spec[0]+' '+$Matches[1]
        $tools[$spec[0]] = $tool
    }
    $probe = Invoke-JobsSetupProcess $wrapper @('--version') $directory 120
    if (($probe.StdOut+$probe.StdErr) -notmatch '\b[0-9]+(?:\.[0-9]+)+') { throw '工程 Hvigor wrapper 版本不可核验。' }
    $versions += 'Hvigor '+$Matches[0]
    $help = Invoke-JobsSetupProcess $wrapper @('--help') $directory 120
    if (($help.StdOut+$help.StdErr) -notmatch '(?i)(?:^|\s)--sync(?:\s|[=,]|$)') { throw '工程 Hvigor wrapper 不支持 --sync，请恢复匹配工程的固定版本。' }
    return [pscustomobject]@{Ohpm=$tools.ohpm;Wrapper=$wrapper;VersionText=($versions -join ' / ')}
}

function Initialize-JobsSetupOhos {
    param([string]$Project,[string]$Fzf)
    [void](Get-JobsSetupOhosWrapper $Project)
    try { $tools = Get-JobsSetupOhosTools $Project }
    catch {
        Write-JobsSetupMessage ('鸿蒙工具链未就绪：'+$_.Exception.Message)
        if (-not $Fzf) { $Fzf = Get-JobsSetupFzf $Project }
        $choice = Select-JobsSetupChoice $Fzf '准备工程匹配的 DevEco 与 HarmonyOS SDK' @('指定已有 DevEco / SDK 目录后复检','打开官方安装说明，完成后复检','停止本次配置')
        if ($choice.StartsWith('停止')) { throw '鸿蒙工具链未就绪，已停止。' }
        if ($choice.StartsWith('打开')) {
            Write-JobsSetupMessage '官方安装说明：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-software-install；须本人选择工程所需 SDK、接受许可并完成安装。'
            Start-Process 'https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-software-install'
            [void](Read-JobsSetupInput '完成 DevEco 与工程匹配 SDK 安装后回车；Ctrl+C 取消' platform.tools)
        }
        $toolHome = (Read-JobsSetupInput '输入 DevEco Studio / command-line-tools 根目录（空回车保留现有环境）' platform.tools).Trim().Trim('"')
        if ($toolHome) {
            Assert-JobsSetupDirectory $toolHome
            if (-not [IO.Directory]::Exists($toolHome)) { throw 'DevEco 目录不存在。' }
            $env:TOOL_HOME = $toolHome
            # 显式本次选择优先于旧的 DEVECO_STUDIO_HOME，结束后由调用者恢复。
            $env:DEVECO_STUDIO_HOME = $toolHome
            $jdk = Join-Path $toolHome 'jbr'
            if ([IO.File]::Exists((Join-Path $jdk 'bin/java.exe'))) { $env:JAVA_HOME = $jdk }
        }
        $sdk = (Read-JobsSetupInput '输入 HarmonyOS SDK 根目录（空回车使用现有环境或 DevEco/sdk）' platform.tools).Trim().Trim('"')
        if ($sdk) { Assert-JobsSetupDirectory $sdk; $env:DEVECO_SDK_HOME = $sdk }
        $tools = Get-JobsSetupOhosTools $Project
    }
    Set-JobsSetupProgress platform.tools done 'DevEco、SDK、Node、npm、OHPM、Java 与工程 Hvigor 已复检' -Version $tools.VersionText
    Set-JobsSetupProgress sdk.java done '使用鸿蒙工具链实际 Java，未使用无关 JDK 选择' -Version $tools.VersionText
    return $tools
}

function Get-JobsSetupWindowsDesktopTools {
    param([string]$Project)
    $issues = @(); $path = ''; $version = ''; $cmakeVersion = ''; $sdkVersion = ''
    $component = if ($env:PROCESSOR_ARCHITECTURE -ceq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -ceq 'ARM64') {'Microsoft.VisualStudio.Component.VC.Tools.ARM64'} else {'Microsoft.VisualStudio.Component.VC.Tools.x86.x64'}
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    if ([IO.File]::Exists($vswhere)) {
        try {
            $probe = Invoke-JobsSetupProcess $vswhere @('-latest','-products','*','-requires',$component,'-property','installationPath') $Project 30
            $path = $probe.StdOut.Trim()
            if (-not $path) {
                $issues += 'MSVC C++ 组件缺失'
                $existing = Invoke-JobsSetupProcess $vswhere @('-latest','-products','*','-property','installationPath') $Project 30
                $path = $existing.StdOut.Trim()
            }
            else {
                $probe = Invoke-JobsSetupProcess $vswhere @('-latest','-products','*','-requires',$component,'Microsoft.VisualStudio.Component.VC.CMake.Project','-property','installationPath') $Project 30
                if ($probe.StdOut.Trim() -cne $path) { $issues += 'VS CMake 组件未安装' }
                $probe = Invoke-JobsSetupProcess $vswhere @('-latest','-products','*','-requires',$component,'-property','installationVersion') $Project 30
                $version = $probe.StdOut.Trim()
            }
        } catch { $issues += ('Visual Studio 查询失败：'+$_.Exception.Message) }
    } else { $issues += 'Visual Studio Installer / vswhere 缺失' }
    if ($path) {
        $architecture = if ($component.EndsWith('ARM64')) {'arm64'} else {'x64'}
        $msvc = Join-Path $path 'VC/Tools/MSVC'
        $compilers = @()
        if ([IO.Directory]::Exists($msvc)) { $compilers = @(Get-ChildItem -LiteralPath $msvc -Directory | Where-Object { [IO.File]::Exists((Join-Path $_.FullName ('bin/Hostx64/'+$architecture+'/cl.exe'))) -or [IO.File]::Exists((Join-Path $_.FullName ('bin/Hostarm64/'+$architecture+'/cl.exe'))) }) }
        if (-not $compilers.Count) { $issues += '对应目标架构 cl.exe 缺失' }
        $cmake = Join-Path $path 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe'
        if (-not [IO.File]::Exists($cmake)) { $issues += 'VS cmake.exe 缺失' }
        else {
            try { $probe = Invoke-JobsSetupProcess $cmake @('--version') $Project 30; if ($probe.StdOut -notmatch 'cmake version\s+([^\s]+)') { throw '版本输出无效' }; $cmakeVersion=$Matches[1] }
            catch { $issues += ('CMake 健康检查失败：'+$_.Exception.Message) }
        }
    }
    $sdkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10'
    $includes = Join-Path $sdkRoot 'Include'
    if ([IO.Directory]::Exists($includes)) {
        $architecture = if ($component.EndsWith('ARM64')) {'arm64'} else {'x64'}
        foreach ($sdk in @(Get-ChildItem -LiteralPath $includes -Directory | Where-Object {$_.Name -match '^\d+\.\d+\.\d+\.\d+$'} | Sort-Object {[version]$_.Name} -Descending)) {
            $required = @(('Include/'+$sdk.Name+'/um/Windows.h'),('Include/'+$sdk.Name+'/shared/sdkddkver.h'),('Include/'+$sdk.Name+'/ucrt/stdio.h'),('Lib/'+$sdk.Name+'/um/'+$architecture+'/kernel32.lib'),('Lib/'+$sdk.Name+'/ucrt/'+$architecture+'/ucrt.lib'),('bin/'+$sdk.Name+'/'+$architecture+'/rc.exe'))
            if (-not @($required | Where-Object {-not [IO.File]::Exists((Join-Path $sdkRoot $_))}).Count) { $sdkVersion=$sdk.Name; break }
        }
    }
    if (-not $sdkVersion) { $issues += '完整 Windows SDK headers / libraries / rc.exe 缺失' }
    return [pscustomobject]@{Ready=($issues.Count -eq 0);Issues=$issues;Path=$path;Component=$component;VersionText=('VS '+$version+' / Windows SDK '+$sdkVersion+' / CMake '+$cmakeVersion)}
}
# 只为已选Windows桌面构建准备或修复原生工具，保留许可与权限交互。
function Install-JobsSetupWindowsDesktopTools {
    param([string]$Project,$Tools)
    $arguments = '--norestart --add Microsoft.VisualStudio.Workload.VCTools --add '+$Tools.Component+' --add Microsoft.VisualStudio.Component.VC.CMake.Project --add Microsoft.VisualStudio.Component.Windows11SDK.26100 --includeRecommended'
    Set-JobsSetupProgress platform.tools waiting '官方 Visual Studio 安装器可能请求 UAC，由本人确认；SDK 获取失败自动重试'
    $installer = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/setup.exe'
    if ($Tools.Path -and [IO.File]::Exists($installer)) {
        $file = $installer
        $parameters = @('modify','--installPath',$Tools.Path,'--norestart','--add','Microsoft.VisualStudio.Workload.VCTools','--add',$Tools.Component,'--add','Microsoft.VisualStudio.Component.VC.CMake.Project','--add','Microsoft.VisualStudio.Component.Windows11SDK.26100','--includeRecommended')
        Write-JobsSetupMessage ('修复来源：Microsoft Visual Studio Installer；目标实例：'+$Tools.Path+'；组件：VC、CMake、Windows SDK 26100')
    } else {
        $file = Get-JobsNativeRequiredWinget
        $parameters = @('install','--id','Microsoft.VisualStudio.2022.BuildTools','--exact','--source','winget','--scope','machine','--interactive','--override',('--wait '+$arguments))
        Write-JobsSetupMessage '安装来源：Microsoft Visual Studio Build Tools 2022 / WinGet 官方源；组件：VC、CMake、Windows SDK 26100；目标：系统 Visual Studio 实例。'
    }
    [void](Invoke-JobsSdkAcquire -Label 'Visual Studio C++ / Windows SDK 26100' -Operation {
        $result = Invoke-JobsSetupProcessOnce $file $parameters $Project 3600 -SdkAcquisitionAttempt -AllowInstallerExitCodes
        if ($result.ExitCode -in @(1602,1223,129,130,143,-1073741510)) { throw (New-Object OperationCanceledException('本人已取消安装或拒绝 UAC，Windows SDK 准备停止。')) }
        if ($result.ExitCode -in @(3010,1641)) { throw 'Windows SDK 安装需要重启；请本人处理重启后重新执行，不自动重启。' }
        if ($result.ExitCode -ne 0) { return $result }
        $ready = Get-JobsSetupWindowsDesktopTools $Project
        if (-not $ready.Ready) { throw ('安装器已返回但 Windows SDK / C++ 工具链未就绪，保留安装缓存继续获取：' + ($ready.Issues -join '；')) }
        return $result
    })
    $worker = Import-Module (Join-Path ${script:JobsLayoutProjectSetupToolchainsRoot} 'Actions/sdk-manage/Scripts/Action.psm1') -PassThru -DisableNameChecking
    & $worker { Update-JobsFvmSessionPath }
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

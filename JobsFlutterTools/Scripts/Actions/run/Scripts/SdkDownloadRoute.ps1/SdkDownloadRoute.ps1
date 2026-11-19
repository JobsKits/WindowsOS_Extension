# SDK 获取前的当前任务网络选路；仅供随包脚本载入，不修改系统或持久配置。
# Created by Jobs on 2026年11月4日，星期三.
param([string]$RunTool,[string]$RunDirectory,[string]$RunArgumentsBase64)
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
function script:ConvertTo-JobsSdkRouteArgument {
    param([AllowEmptyString()][string]$Value)
    if ($Value.IndexOf([char]0) -ge 0) { throw '网络参数含空字符。' }
    $quoted=New-Object Text.StringBuilder;[void]$quoted.Append('"');$slashes=0
    foreach($character in $Value.ToCharArray()){
        if($character-eq[char]92){$slashes++;continue}
        if($character-eq[char]34){[void]$quoted.Append([char]92,(2*$slashes+1));[void]$quoted.Append([char]34)}
        else{if($slashes){[void]$quoted.Append([char]92,$slashes)};[void]$quoted.Append($character)}
        $slashes=0
    }
    if($slashes){[void]$quoted.Append([char]92,(2*$slashes))};[void]$quoted.Append('"');return $quoted.ToString()
}
function script:Protect-JobsSdkRouteText {
    param([string]$Text)
    return $Text -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@','$1***@' -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*','$1?[已省略]' -replace '(?im)((?:password|secret|access[_-]?token|authorization)\s*[:=]\s*)[^\r\n]+','$1[已省略]'
}
function script:Write-JobsSdkRouteMessage {
    param([string]$Text)
    $safe=Protect-JobsSdkRouteText $Text
    if(Get-Command Write-JobsSdkRetryMessage -ErrorAction SilentlyContinue){Write-JobsSdkRetryMessage $safe}else{Write-Host $safe}
}
function script:Copy-JobsSdkRouteEnvironment {
    param($Environment)
    $copy=@{}
    foreach($key in $Environment.Keys){$copy[[string]$key]=[string]$Environment[$key]}
    return $copy
}
function script:Get-JobsSdkRouteEnvironment {
    param([Diagnostics.ProcessStartInfo]$Start)
    if($Start){
        if($null-eq$Start.PSObject.Properties['JobsSdkRouteOriginalEnvironment']){
            $snapshot=Copy-JobsSdkRouteEnvironment $Start.EnvironmentVariables
            Add-Member -InputObject $Start -NotePropertyName JobsSdkRouteOriginalEnvironment -NotePropertyValue $snapshot
        }
        return $Start.JobsSdkRouteOriginalEnvironment
    }
    return Copy-JobsSdkRouteEnvironment ([Environment]::GetEnvironmentVariables('Process'))
}
function script:Get-JobsSdkRouteHash {
    param([string]$Text)
    $hash=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant()}finally{$hash.Dispose()}
}
function script:Get-JobsSdkConfiguredProxies {
    # 只复用当前启用的系统代理（含企业LAN）；不猜端口、不扫描或启动代理进程。
    $values=@()
    if([Environment]::OSVersion.Platform-eq[PlatformID]::Win32NT){
        try{
            $settings=Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
            if($settings.ProxyEnable-eq1-and$settings.ProxyServer){
                foreach($part in ([string]$settings.ProxyServer -split ';')){
                    $address=($part -replace '^(?:https?|socks)=','').Trim()
                    if($address-match'^(?:[A-Za-z0-9._-]+|\[[a-fA-F0-9:]+\]):\d{1,5}$'){
                        $scheme=if($part.StartsWith('socks=')){'socks5h://'}else{'http://'}
                        $values+=$scheme+$address
                    }
                }
            }
        }catch{}
    }
    return @($values|Select-Object -Unique|Select-Object -First 2)
}
function script:Get-JobsSdkRoutePolicy {
    param([string]$Uri,[Collections.IDictionary]$Environment,[bool]$PublicObject=$false)
    $parsed=$null
    if(-not[Uri]::TryCreate($Uri,[UriKind]::Absolute,[ref]$parsed)-or$parsed.Scheme-cne'https'){return [pscustomobject]@{Supported=$false;Reason='非HTTPS制品，保留当前来源及既有传输配置'}}
    $explicitStorage=$Environment.Contains('FLUTTER_STORAGE_BASE_URL')
    $proxyKeys=@('HTTPS_PROXY','https_proxy','HTTP_PROXY','http_proxy','ALL_PROXY','all_proxy')
    $explicitProxy=@($proxyKeys|Where-Object{$Environment.Contains($_)}).Count-gt0
    $isStorage=$parsed.Host -in @('storage.googleapis.com','storage.flutter-io.cn')-and$parsed.AbsolutePath.Contains('/flutter_infra_release/')
    $kind=if($parsed.AbsolutePath-match'\.(zip|tar\.xz|tar\.gz|tgz)$'){'archive'}elseif($parsed.AbsolutePath-match'/releases_(windows|macos|linux)\.json$'){'release-metadata'}elseif($parsed.AbsolutePath-match'/info/refs$'-and$parsed.Query-ceq'?service=git-upload-pack'){'git'}else{'unsupported'}
    if($kind-ceq'unsupported'){return [pscustomobject]@{Supported=$false;Reason='未登记等价制品格式，保留原来源及代理'}}
    $urls=@($Uri)
    if($isStorage){
        if($explicitStorage){
            $base=[string]$Environment['FLUTTER_STORAGE_BASE_URL']
            if($base){
                $baseUri=$null
                if(-not[Uri]::TryCreate($base,[UriKind]::Absolute,[ref]$baseUri)-or$baseUri.Scheme-cne'https'){throw '显式 FLUTTER_STORAGE_BASE_URL 必须为HTTPS地址或空值；保留该配置，未自动改源。'}
                $urls=if($Uri.StartsWith($base.TrimEnd('/')+'/')){@($Uri)}else{@($base.TrimEnd('/')+$parsed.PathAndQuery)}
            }
        }elseif($PublicObject-and$parsed.AbsolutePath-match'^/flutter_infra_release/(?:flutter|releases)/'){
            $urls=@(('https://storage.googleapis.com'+$parsed.PathAndQuery),('https://storage.flutter-io.cn'+$parsed.PathAndQuery))
        }
    }
    $proxies=@([pscustomobject]@{Mode='direct';Url=''})
    if($explicitProxy){$proxies=@([pscustomobject]@{Mode='explicit';Url=''})}
    else{foreach($proxy in @(Get-JobsSdkConfiguredProxies)){$proxies+=[pscustomobject]@{Mode='configured-proxy';Url=$proxy}}}
    return [pscustomobject]@{Supported=$true;Kind=$kind;IsStorage=$isStorage;ExplicitStorage=$explicitStorage;ExplicitProxy=$explicitProxy;Urls=$urls;Proxies=$proxies;Original=$parsed}
}
function script:Invoke-JobsSdkRouteProbeBatch {
    param([object[]]$Requests,[Collections.IDictionary]$Environment,[string]$Directory)
    $curl=$null
    foreach($name in @('curl.exe','curl')){$command=Get-Command $name -CommandType Application -ErrorAction SilentlyContinue|Select-Object -First 1;if($command){$curl=$command.Source;break}}
    if(-not$curl){return @($Requests|ForEach-Object{[pscustomobject]@{Request=$_;ExitCode=127;Metrics='';Error='没有可执行curl，无法验证AUTO路线';Headers='';Body=[byte[]]@()}})}
    $running=@()
    try{
        foreach($request in $Requests){
            $id=[guid]::NewGuid().ToString('N');$body=Join-Path $Directory ($id+'.sample');$headers=Join-Path $Directory ($id+'.headers')
            $args=@('--silent','--show-error','--location','--max-redirs','3','--proto','=https','--proto-redir','=https','--connect-timeout','2','--max-time','6','--range','0-262143','--max-filesize','262144','--header','Accept-Encoding: identity','--output',$body,'--dump-header',$headers,'--write-out','%{http_code}|%{remote_ip}|%{time_namelookup}|%{time_connect}|%{time_appconnect}|%{time_starttransfer}|%{time_total}|%{size_download}|%{speed_download}|%{url_effective}|%{ssl_verify_result}')
            if($request.Proxy.Mode-ceq'direct'){$args+=@('--proxy','','--noproxy','*')}
            elseif($request.Proxy.Mode-in@('configured-proxy','native-wininet')){$args+=@('--proxy',$request.Proxy.Url)}
            if($request.Kind-ceq'git'){$args+=@('--header','Git-Protocol: version=2')}
            $args+=@('--url',$request.Uri)
            $start=New-Object Diagnostics.ProcessStartInfo;$start.FileName=$curl
            $start.Arguments=(@($args|ForEach-Object{ConvertTo-JobsSdkRouteArgument ([string]$_)})-join' ')
            $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
            $start.EnvironmentVariables.Clear();foreach($key in $Environment.Keys){$start.EnvironmentVariables[[string]$key]=[string]$Environment[$key]}
            $process=New-Object Diagnostics.Process;$process.StartInfo=$start
            [void]$process.Start()
            $running+=[pscustomobject]@{Request=$request;Process=$process;Output=$process.StandardOutput.ReadToEndAsync();Errors=$process.StandardError.ReadToEndAsync();Body=$body;Headers=$headers}
        }
        $watch=[Diagnostics.Stopwatch]::StartNew()
        while(@($running|Where-Object{-not$_.Process.HasExited}).Count-gt0-and$watch.Elapsed.TotalSeconds-lt8){Start-Sleep -Milliseconds 25}
        $results=@()
        foreach($item in $running){
            if(-not$item.Process.HasExited){$item.Process.Kill();[void]$item.Process.WaitForExit(1000)}
            $finished=[Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($item.Output,$item.Errors),1000)
            $results+=[pscustomobject]@{Request=$item.Request;ExitCode=$item.Process.ExitCode;Metrics=$(if($finished){$item.Output.GetAwaiter().GetResult()}else{''});Error=$(if($finished){$item.Errors.GetAwaiter().GetResult()}else{'探测进程输出未关闭'});Headers=$(if([IO.File]::Exists($item.Headers)){[IO.File]::ReadAllText($item.Headers)}else{''});Body=$(if([IO.File]::Exists($item.Body)){[IO.File]::ReadAllBytes($item.Body)}else{[byte[]]@()})}
        }
        return $results
    }finally{foreach($item in $running){if(-not$item.Process.HasExited){$item.Process.Kill()};$item.Process.Dispose()}}
}
function script:ConvertFrom-JobsSdkRouteProbe {
    param($Probe)
    $parts=@($Probe.Metrics.Trim()-split'\|');$reason='';$bytes=$Probe.Body.Length;$total=[long]0;$sampleEnd=[long]0
    $metrics=@();$culture=[Globalization.CultureInfo]::InvariantCulture
    if($parts.Count-ne11){$reason='未返回完整DNS/TLS/传输指标'}
    else{
        foreach($index in 2..8){$number=[double]0;if(-not[double]::TryParse($parts[$index],[Globalization.NumberStyles]::Float,$culture,[ref]$number)){$reason='传输指标无效';break};$metrics+=$number}
        if(-not$reason-and($parts[10]-cne'0'-or$metrics[2]-le0)){$reason='TLS证书或握手未验证'}
        $effective=$null
        if(-not$reason-and(-not[Uri]::TryCreate($parts[9],[UriKind]::Absolute,[ref]$effective)-or$effective.Scheme-cne'https'-or$effective.AbsolutePath-cne([Uri]$Probe.Request.Uri).AbsolutePath)){$reason='重定向制品路径不一致'}
        if(-not$reason-and($Probe.ExitCode-notin@(0,28)-or$bytes-lt32-or$bytes-gt262144-or[long]$metrics[5]-ne$bytes-or$metrics[4]-le0-or$metrics[6]-le0)){$reason='无有效传输字节或失败响应；不作为测速成功'}
        if(-not$reason-and$Probe.Request.Kind-notin@('git','object-metadata')){
            if($parts[0]-cne'206'){$reason='未返回206 Range响应'}
            $ranges=@([regex]::Matches($Probe.Headers,'(?im)^Content-Range:\s*bytes\s+0-(\d+)/(\d+)\s*$'))
            if(-not$reason-and$ranges.Count-ne1){$reason='缺少唯一有效Content-Range'}
            if(-not$reason){$sampleEnd=[long]$ranges[0].Groups[1].Value;$total=[long]$ranges[0].Groups[2].Value;if($total-le$sampleEnd-or$bytes-gt($sampleEnd+1)-or($Probe.ExitCode-eq0-and$bytes-ne($sampleEnd+1))){$reason='Range字节数或总长不一致'}}
        }
        $text=[Text.Encoding]::UTF8.GetString($Probe.Body)
        $objectSize=[long]0;$objectMD5=''
        if(-not$reason-and$Probe.Request.Kind-ceq'object-metadata'){
            try{
                $json=$text|ConvertFrom-Json -ErrorAction Stop
                if($parts[0]-notin@('200','206')-or-not[long]::TryParse([string]$json.size,[ref]$objectSize)-or$objectSize-le0){throw '对象元数据大小无效'}
                $md5=[Convert]::FromBase64String([string]$json.md5Hash);if($md5.Length-ne16){throw '对象MD5无效'}
                $objectMD5=[BitConverter]::ToString($md5).Replace('-','').ToLowerInvariant()
            }catch{$reason='官方对象metadata结构或size/md5Hash无效'}
        }
        if(-not$reason-and$Probe.Request.Kind-ceq'archive'){
            if($bytes-lt4096){$reason='制品样本小于4KiB，吞吐不足以判定'}
            elseif(([Uri]$Probe.Request.Uri).AbsolutePath-match'\.zip$'-and-not($Probe.Body[0]-eq80-and$Probe.Body[1]-eq75-and$Probe.Body[2]-eq3-and$Probe.Body[3]-eq4)){$reason='ZIP制品魔数不符，可能是错误页'}
            elseif(([Uri]$Probe.Request.Uri).AbsolutePath-match'\.(tar\.gz|tgz)$'-and[BitConverter]::ToString($Probe.Body,0,3)-cne'1F-8B-08'){$reason='GZip制品魔数不符'}
            elseif(([Uri]$Probe.Request.Uri).AbsolutePath-match'\.tar\.xz$'-and[BitConverter]::ToString($Probe.Body,0,6)-cne'FD-37-7A-58-5A-00'){$reason='XZ制品魔数不符'}
        }
        if(-not$reason-and$Probe.Request.Kind-ceq'release-metadata'-and($text-notmatch'"releases"\s*:\s*\['-or$text-notmatch'"base_url"\s*:')){$reason='Flutter发布元数据结构不符'}
        if(-not$reason-and$Probe.Request.Kind-ceq'git'-and($parts[0]-cne'200'-or$Probe.Headers-notmatch'(?im)^Content-Type:\s*application/x-git-upload-pack-advertisement'-or$text-notmatch'(?s)^[0-9a-f]{4}(?:# service=git-upload-pack|version 2)')){$reason='不是可核验的Git smart HTTP通告'}
    }
    if(-not(Get-Variable objectSize -ErrorAction SilentlyContinue)){$objectSize=[long]0;$objectMD5=''}
    $etag='';$etags=@([regex]::Matches($Probe.Headers,'(?im)^ETag:\s*([^\r\n]+)'));if($etags.Count){$etag=$etags[-1].Groups[1].Value.Trim().Trim('"').ToLowerInvariant()}
    return [pscustomobject]@{Valid=(-not$reason);Reason=$reason;Request=$Probe.Request;Body=$Probe.Body;Bytes=$bytes;Total=$total;ETag=$etag;ObjectSize=$objectSize;ObjectMD5=$objectMD5;Metrics=$metrics;Score=$(if(-not$reason){$metrics[3]+(8388608/[Math]::Max(1,$metrics[6]))}else{[double]::PositiveInfinity});Error=$Probe.Error}
}
function script:Get-JobsSdkRouteCacheKey {
    param([string]$Uri,[string]$Identity,[Collections.IDictionary]$Environment)
    $fields=@($Uri,$Identity)
    foreach($key in @('FLUTTER_STORAGE_BASE_URL','PUB_HOSTED_URL','FLUTTER_PREBUILT_ENGINE_VERSION','FLUTTER_REALM','HTTPS_PROXY','https_proxy','HTTP_PROXY','http_proxy','ALL_PROXY','all_proxy','NO_PROXY','no_proxy')){$fields+=($key+'='+$(if($Environment.Contains($key)){'set:'+ [string]$Environment[$key]}else{'unset'}))}
    return Get-JobsSdkRouteHash ($fields-join"`n")
}
function script:Clear-JobsSdkRouteCache {
    param([string]$Key)
    if(Get-Variable JobsFlutterSdkRouteCache -Scope Global -ErrorAction SilentlyContinue){$global:JobsFlutterSdkRouteCache.Remove($Key)}
}
function script:Get-JobsSdkRouteFailureKey {
    param([string]$Uri,[string]$ProxyMode,[string]$Proxy)
    return Get-JobsSdkRouteHash (([Uri]$Uri).GetLeftPart([UriPartial]::Path)+'|'+$ProxyMode+'|'+$Proxy)
}
function script:Reject-JobsSdkRoute {
    param($Route)
    if (-not $Route) { return }
    if($Route.PSObject.Properties['RelatedRoutes']){foreach($related in $Route.RelatedRoutes){Reject-JobsSdkRoute $related}}
    Clear-JobsSdkRouteCache $Route.Key
    if (-not $Route.Verified) { return }
    if (-not (Get-Variable JobsFlutterSdkRouteFailures -Scope Global -ErrorAction SilentlyContinue)) { $global:JobsFlutterSdkRouteFailures=@{} }
    $key=Get-JobsSdkRouteFailureKey $Route.Uri $Route.ProxyMode $Route.Proxy
    $count=1
    if ($global:JobsFlutterSdkRouteFailures.ContainsKey($key) -and $global:JobsFlutterSdkRouteFailures[$key].Expires -gt [DateTime]::UtcNow) { $count += $global:JobsFlutterSdkRouteFailures[$key].Count }
    $global:JobsFlutterSdkRouteFailures[$key]=[pscustomobject]@{Count=$count;Expires=[DateTime]::UtcNow.AddSeconds(120)}
    Write-JobsSdkRouteMessage ('真实SDK获取失败：该路线120秒内降权，优先尝试其它已验证且未越过显式约束的候选；源：'+$Route.Uri+'；路由：'+$Route.ProxyMode+' '+$Route.Proxy)
}
function script:Get-JobsFlutterSdkRoute {
    param([string]$Uri,[string]$Identity,[Collections.IDictionary]$Environment,[string]$ExpectedSha256='',[ValidateSet('managed','windows-native')][string]$Transport='managed',[bool]$PublicObject=$false)
    if(([Uri]$Uri).AbsolutePath-match'^/flutter_infra_release/releases/(?:releases_(?:windows|macos|linux)\.json|(?:stable|beta|dev|master)/[^/]+/[^/]+\.zip)$'){$PublicObject=$true}
    $policy=Get-JobsSdkRoutePolicy $Uri $Environment $PublicObject
    if(-not$policy.Supported){return [pscustomobject]@{Ready=$true;Uri=$Uri;ProxyMode='inherit';Proxy='';Environment=@{};Reason=$policy.Reason;Key='';Verified=$false}}
    $configuration=(@($policy.Proxies|ForEach-Object{$_.Mode+'='+$_.Url})-join';')
    if($Transport-ceq'windows-native'){$configuration+=(@($policy.Urls|ForEach-Object{$route=Get-JobsSdkNativeWindowsProxy $_;$route.Mode+'='+$route.Url})-join';')}
    $key=Get-JobsSdkRouteCacheKey $Uri ($Identity+'|'+$ExpectedSha256+'|'+$Transport+'|'+$configuration+'|public='+$PublicObject) $Environment
    if(-not(Get-Variable JobsFlutterSdkRouteCache -Scope Global -ErrorAction SilentlyContinue)){$global:JobsFlutterSdkRouteCache=@{}}
    if($global:JobsFlutterSdkRouteCache.ContainsKey($key)-and$global:JobsFlutterSdkRouteCache[$key].Expires-gt[DateTime]::UtcNow){return $global:JobsFlutterSdkRouteCache[$key]}
    $requests=@()
    foreach($url in $policy.Urls){
        $routes=if($Transport-ceq'windows-native'){@(Get-JobsSdkNativeWindowsProxy $url)}else{$policy.Proxies}
        if(@($routes|Where-Object{$_.Mode-ceq'native-unverified'}).Count){
            Write-JobsSdkRouteMessage '原生Windows SDK使用现有PAC/未解析WinINET通道，无法有界验证相同实际路线；保留原有来源和显式环境，不冒称curl测速已作用BITS。'
            return [pscustomobject]@{Ready=$true;Uri=$Uri;ProxyMode='inherit';Proxy='';Environment=@{};Reason='既有原生代理通道未能有界验证，保持原样';Key=$key;Verified=$false}
        }
        foreach($proxy in $routes){$requests+=[pscustomobject]@{Uri=$url;Proxy=$proxy;Kind=$policy.Kind}}
    }

    if($policy.IsStorage-and-not$policy.ExplicitStorage-and$policy.Kind-in@('archive','release-metadata')-and-not$ExpectedSha256){
        $segments=$policy.Original.AbsolutePath.TrimStart('/').Split([char[]]'/', 2, [StringSplitOptions]::None)
        $metadataUri='https://storage.googleapis.com/storage/v1/b/'+[Uri]::EscapeDataString($segments[0])+'/o/'+[Uri]::EscapeDataString($segments[1])+'?fields=size,md5Hash,contentType,generation'
        foreach($proxy in $policy.Proxies){$requests+=[pscustomobject]@{Uri=$metadataUri;Proxy=$proxy;Kind='object-metadata'}}
    }

    if($Transport-ceq'windows-native'){Write-JobsSdkRouteMessage '传输通道：原生PowerShell/BITS；仅按当前实际WinINET/绕过规则比较来源，不把新代理的curl测速冒称已套用。显式环境代理仍原样传入。'}
    Write-JobsSdkRouteMessage ('SDK网络预检：'+$Identity+'；源模式：'+$(if($policy.ExplicitStorage){'显式源（含空值），保留'}else{'AUTO'})+'；代理：'+$(if($policy.ExplicitProxy){'显式配置（含空值），保留'}else{'直连/当前已配置代理'})+'；候选 '+$requests.Count+'；并行小Range，最多256KiB/候选、连接2秒、单候选6秒。')
    $directory=Join-Path ([IO.Path]::GetTempPath()) ('JobsSdkRoute-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($directory)
    try{$probes=@(Invoke-JobsSdkRouteProbeBatch $requests $Environment $directory|ForEach-Object{ConvertFrom-JobsSdkRouteProbe $_})}finally{if([IO.Directory]::Exists($directory)){[IO.Directory]::Delete($directory,$true)}}
    $official=@($probes|Where-Object{$_.Valid-and$_.Request.Kind-ne'object-metadata'-and([Uri]$_.Request.Uri).Host-ceq'storage.googleapis.com'})
    $metadataReferences=@($probes|Where-Object{$_.Valid-and$_.Request.Kind-ceq'object-metadata'})
    foreach($probe in $probes){
        if($probe.Request.Kind-ceq'object-metadata'){continue}
        if($probe.Valid-and$policy.IsStorage-and-not$policy.ExplicitStorage-and([Uri]$probe.Request.Uri).Host-ceq'storage.flutter-io.cn'){
            $equivalent=$false
            foreach($reference in $official){
                $length=[Math]::Min($reference.Bytes,$probe.Bytes)
                if($reference.Total-eq$probe.Total-and$length-ge4096){
                    $match=$true;for($index=0;$index-lt$length;$index++){if($reference.Body[$index]-ne$probe.Body[$index]){$match=$false;break}}
                    if($match-and(-not$reference.ETag-or-not$probe.ETag-or$reference.ETag-ceq$probe.ETag)){$equivalent=$true;break}
                }
            }
            if(-not$equivalent-and-not$official.Count-and$probe.ETag){foreach($reference in $metadataReferences){if($reference.ObjectSize-eq$probe.Total-and$reference.ObjectMD5-ceq$probe.ETag){$equivalent=$true;break}}}
            if(-not$equivalent-and-not$official.Count-and$ExpectedSha256-cmatch'^[a-fA-F0-9]{64}$'-and$probe.Total-gt$probe.Bytes){$equivalent=$true}
            if(-not$equivalent-and-not$official.Count-and-not$metadataReferences.Count-and$probe.ETag-and$probe.Total-ge$probe.Bytes){
                $equivalent=$true
                Write-JobsSdkRouteMessage ('官方摘要/样本有界未取得；采用已授权CFUG精确目标路径的Range、总长、ETag和制品结构证据（不冒称已通过官方hash核验）：'+$probe.Request.Uri)
            }
            if(-not$equivalent){$probe.Valid=$false;$probe.Reason='镜像与已有官方证据不一致，或精确目标Range/总长/ETag证据不足'}
        }
        $metric=if($probe.Metrics.Count-eq7){'DNS {0:N0}ms / TLS {1:N0}ms / 首字节 {2:N0}ms / {3:N0}字节/s / 样本{4} / 总长{5}'-f($probe.Metrics[0]*1000),([Math]::Max(0,$probe.Metrics[2]-$probe.Metrics[1])*1000),($probe.Metrics[3]*1000),$probe.Metrics[6],$probe.Bytes,$probe.Total}else{'无可用传输指标'}
        Write-JobsSdkRouteMessage ('候选：'+$probe.Request.Uri+'；路由：'+$probe.Request.Proxy.Mode+' '+$probe.Request.Proxy.Url+'；'+$metric+'；'+$(if($probe.Valid){'验证可用'}else{'不可用：'+$probe.Reason+' '+$probe.Error}))
    }
    foreach($probe in $probes){
        $penalty=0
        if(Get-Variable JobsFlutterSdkRouteFailures -Scope Global -ErrorAction SilentlyContinue){
            $failureKey=Get-JobsSdkRouteFailureKey $probe.Request.Uri $probe.Request.Proxy.Mode $probe.Request.Proxy.Url
            if($global:JobsFlutterSdkRouteFailures.ContainsKey($failureKey)-and$global:JobsFlutterSdkRouteFailures[$failureKey].Expires-gt[DateTime]::UtcNow){$penalty=$global:JobsFlutterSdkRouteFailures[$failureKey].Count}
        }
        Add-Member -InputObject $probe -NotePropertyName FailurePenalty -NotePropertyValue $penalty
    }
    $valid=@($probes|Where-Object{$_.Valid-and$_.Request.Kind-ne'object-metadata'}|Sort-Object FailurePenalty,Score)
    if(-not$valid.Count){
        $result=[pscustomobject]@{Ready=$false;Uri=$Uri;ProxyMode='inherit';Proxy='';Environment=@{};Reason='全部候选未通过真实响应校验，持续获取循环将退避重测';Key=$key;Verified=$false;Expires=[DateTime]::UtcNow.AddSeconds(2)}
    }else{
        $best=$valid[0];$variables=@{}
        if($policy.IsStorage-and-not$policy.ExplicitStorage){$variables['FLUTTER_STORAGE_BASE_URL']=([Uri]$best.Request.Uri).GetLeftPart([UriPartial]::Authority)}
        if($Transport-ceq'managed'-and-not$policy.ExplicitProxy-and$best.Request.Proxy.Mode-ceq'configured-proxy'){$variables['HTTPS_PROXY']=$best.Request.Proxy.Url;$variables['HTTP_PROXY']=$best.Request.Proxy.Url;$variables['https_proxy']=$best.Request.Proxy.Url;$variables['http_proxy']=$best.Request.Proxy.Url}
        $result=[pscustomobject]@{Ready=$true;Uri=$best.Request.Uri;ProxyMode=$best.Request.Proxy.Mode;Proxy=$best.Request.Proxy.Url;Environment=$variables;AutoSource=(-not $policy.ExplicitStorage -and $policy.IsStorage);Total=$best.Total;ETag=$best.ETag;ExpectedMD5=$(if($policy.IsStorage-and$best.ETag-cmatch'^[a-f0-9]{32}$'){$best.ETag}else{''});Reason='精确目标Range/TLS/字节校验及可取得的元数据已对账，按真实首字节与吞吐估算选择当前最快可用候选；官方摘要是否取得见上方诊断';Key=$key;Verified=$true;Expires=[DateTime]::UtcNow.AddSeconds(300)}
        Write-JobsSdkRouteMessage ('SDK选路：'+$result.Uri+'；'+$result.ProxyMode+' '+$result.Proxy+'；原因：'+$result.Reason+'；仅本次请求/子进程生效，300秒内同任务复用；不修改PUB_HOSTED_URL、系统代理或Git配置。')
    }
    $global:JobsFlutterSdkRouteCache[$key]=$result
    return $result
}
function script:Get-JobsSdkNativeWindowsProxy {
    param([string]$Uri)
    if([Environment]::OSVersion.Platform-ne[PlatformID]::Win32NT){return [pscustomobject]@{Mode='direct';Url=''}}
    try{
        $settings=Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        if(($settings.PSObject.Properties['AutoConfigURL']-and$settings.AutoConfigURL)-or($settings.PSObject.Properties['AutoDetect']-and$settings.AutoDetect)){return [pscustomobject]@{Mode='native-unverified';Url=''}}
        if(-not$settings.ProxyEnable){return [pscustomobject]@{Mode='direct';Url=''}}
        $hostName=([Uri]$Uri).Host
        if($settings.PSObject.Properties['ProxyOverride']){
            foreach($pattern in ([string]$settings.ProxyOverride-split';')){
                if(($pattern-ceq'<local>'-and-not$hostName.Contains('.'))-or($pattern-and$pattern-cne'<local>'-and$hostName-like$pattern)){return [pscustomobject]@{Mode='direct';Url=''}}
            }
        }
        $server=[string]$settings.ProxyServer
        if($server.Contains('=')){
            $selected=@($server-split';'|Where-Object{$_-match'^https='}|Select-Object -First 1)
            if(-not$selected.Count){$selected=@($server-split';'|Where-Object{$_-match'^http='}|Select-Object -First 1)}
            if(-not$selected.Count){return [pscustomobject]@{Mode='native-unverified';Url=''}}
            $server=$selected[0]-replace'^https?=',''
        }
        if($server-match'^(?:[A-Za-z0-9._-]+|\[[a-fA-F0-9:]+\]):\d{1,5}$'){return [pscustomobject]@{Mode='native-wininet';Url=('http://'+$server)}}
    }catch{}
    return [pscustomobject]@{Mode='native-unverified';Url=''}
}
function script:Read-JobsSdkRouteLocalText {
    param([string]$Path)
    try{if([IO.File]::Exists($Path)-and(Get-Item -LiteralPath $Path -Force).Length-le2097152){return [IO.File]::ReadAllText($Path).Trim()}}catch{}
    return ''
}
function script:Read-JobsSdkReleaseManifest {
    param([Collections.IDictionary]$Environment)
    $cacheKey=Get-JobsSdkRouteCacheKey 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json' 'release-manifest' $Environment
    if(-not(Get-Variable JobsFlutterReleaseManifestCache -Scope Global -ErrorAction SilentlyContinue)){$global:JobsFlutterReleaseManifestCache=@{}}
    if($global:JobsFlutterReleaseManifestCache.ContainsKey($cacheKey)-and$global:JobsFlutterReleaseManifestCache[$cacheKey].Expires-gt[DateTime]::UtcNow){return $global:JobsFlutterReleaseManifestCache[$cacheKey].Data}
    $directory=Join-Path ([IO.Path]::GetTempPath()) ('JobsSdkManifest-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($directory)
    try{
        $path=Join-Path $directory 'releases.json'
        Receive-JobsSdkWebFile 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json' $path 60 -EnvironmentOverride $Environment
        $data=[IO.File]::ReadAllText($path)|ConvertFrom-Json -ErrorAction Stop
        $global:JobsFlutterReleaseManifestCache[$cacheKey]=[pscustomobject]@{Data=$data;Expires=[DateTime]::UtcNow.AddSeconds(300)}
        return $data
    }finally{if([IO.Directory]::Exists($directory)){[IO.Directory]::Delete($directory,$true)}}
}
function script:Get-JobsSdkRequestedRelease {
    param([string]$Requested,[Collections.IDictionary]$Environment)
    if($Environment.Contains('FLUTTER_PREBUILT_ENGINE_VERSION')-and$Environment['FLUTTER_PREBUILT_ENGINE_VERSION']){return $null}
    if($Environment.Contains('FLUTTER_REALM')-and$Environment['FLUTTER_REALM']){return $null}
    if($Environment.Contains('FLUTTER_STORAGE_BASE_URL')-and$Environment['FLUTTER_STORAGE_BASE_URL']-and([Uri]$Environment['FLUTTER_STORAGE_BASE_URL']).Host-notin@('storage.googleapis.com','storage.flutter-io.cn')){return $null}
    $manifest=Read-JobsSdkReleaseManifest $Environment
    $arch=if($Environment.Contains('PROCESSOR_ARCHITECTURE')-and$Environment['PROCESSOR_ARCHITECTURE']-ceq'ARM64'){'arm64'}else{'x64'}
    $channel=$Requested-in@('stable','beta','dev','master')
    $hash=if($channel-and$manifest.current_release.PSObject.Properties[$Requested]){[string]$manifest.current_release.$Requested}else{''}
    $release=@($manifest.releases|Where-Object{$(if($channel){$hash-and$_.hash-ceq$hash}else{$_.version-ceq$Requested})-and$(if($_.PSObject.Properties['dart_sdk_arch']){$_.dart_sdk_arch-ceq$arch}else{$arch-ceq'x64'})}|Select-Object -First 1)
    if($release.Count-ne1){Write-JobsSdkRouteMessage ('请求目标尚无同架构归档元数据：'+$Requested+' / '+$arch+'；不拿旧版本或其它架构代替，Git获取后再按真实engine分阶段预检。');return $null}
    $item=$release[0]
    if($item.archive-cnotmatch'^(stable|beta|dev|master)/windows/[^/]+\.zip$'-or$item.sha256-cnotmatch'^[a-fA-F0-9]{64}$'){throw 'SDK发布元数据缺少精确Windows制品或可信SHA，未拿旧SDK代替请求目标。'}
    if([string]$manifest.base_url-cnotin@('https://storage.googleapis.com/flutter_infra_release/releases','https://storage.flutter-io.cn/flutter_infra_release/releases')){throw '可信发布清单base_url不是标准公开release来源。'}
    return [pscustomobject]@{Uri=($manifest.base_url.TrimEnd('/')+'/'+$item.archive);ExpectedSha256=$item.sha256;Identity=('请求 '+$Requested+' → manifest精确Flutter '+$item.version+' / '+$arch+' / '+$item.archive);PublicObject=$true}
}
function script:Get-JobsSdkProcessRouteTarget {
    param([Diagnostics.ProcessStartInfo]$Start,[Collections.IDictionary]$Environment)
    $tool=$Start.FileName
    foreach($key in @('JOBS_SDK_ROUTE_TOOL','JOBS_FLUTTER_RUNNER_TOOL','JOBS_FLUTTER_EXECUTABLE','JOBS_FLUTTER_TOOL','JOBS_PACKAGER_PROBE_TOOL','JOBS_SETUP_TOOL','JOBS_FVM_EXECUTABLE')){if($Start.EnvironmentVariables.ContainsKey($key)){$tool=$Start.EnvironmentVariables[$key];break}}
    $leaf=[IO.Path]::GetFileName($tool)
    $arguments=$Start.Arguments
    $sdk='';$source=''
    $configuration=Get-JobsSdkProjectConfiguration $Start.WorkingDirectory
    if($configuration-and$configuration.PSObject.Properties['flutterUrl']){$source=[string]$configuration.flutterUrl}
    if($Environment.Contains('FVM_FLUTTER_URL')-and$Environment['FVM_FLUTTER_URL']){$source=$Environment['FVM_FLUTTER_URL']}
    if($leaf-match'^(flutter|dart)(?:\.(bat|cmd|exe))?$'){$source=''}
    if($leaf-match'^fvm(?:\.(bat|cmd|exe))?$'){
        $context=Get-JobsSdkFvmContext $tool $Start.WorkingDirectory $Environment
        if($context-and$context.PSObject.Properties['flutterUrl']){$source=[string]$context.flutterUrl}
        $version=''
        if($arguments-match'(?:^|[\s"])(?:install|use)[\s"]+([A-Za-z0-9._+-]+)'){$version=$Matches[1]}
        elseif($configuration-and$configuration.PSObject.Properties['flutter']){$version=[string]$configuration.flutter}
        if($arguments-match'(?:^|[\s"])install[\s"]+'-and$version-and$source-match'^https://'){
            $release=if($source-cin@('https://github.com/flutter/flutter.git','https://github.com/flutter/flutter')){Get-JobsSdkRequestedRelease $version $Environment}else{$null}
            if(-not$release-and$context-and$context.PSObject.Properties['versionsCachePath']){$release=Get-JobsSdkLandedBootstrapTarget (Join-Path $context.versionsCachePath $version) $Start.WorkingDirectory $Environment}
            return [pscustomobject]@{Uri=($source.TrimEnd('/')+'/info/refs?service=git-upload-pack');Identity=('FVM请求channel='+$version+'；精确新版本不以旧缓存代替');Transport='managed';Artifact=$release}
        }
        if($context-and$context.PSObject.Properties['versionsCachePath']-and$version){$sdk=Join-Path $context.versionsCachePath $version}
        if(-not$sdk-and[IO.Directory]::Exists((Join-Path $Start.WorkingDirectory '.fvm/flutter_sdk'))){$sdk=Join-Path $Start.WorkingDirectory '.fvm/flutter_sdk'}
        if((-not$sdk-or-not[IO.File]::Exists((Join-Path $sdk 'bin/internal/engine.version')))-and$source-match'^https://'){
            return [pscustomobject]@{Uri=($source.TrimEnd('/')+'/info/refs?service=git-upload-pack');Identity=('FVM实际Git来源 / '+$version);Transport='managed'}
        }
    }
    if($leaf-match'^fvm(?:\.(bat|cmd|exe))?$'-and$source-and$source-cnotin@('https://github.com/flutter/flutter.git','https://github.com/flutter/flutter')-and-not($Environment.Contains('FLUTTER_STORAGE_BASE_URL')-and$Environment['FLUTTER_STORAGE_BASE_URL'])){
        if($source-match'^https://'){return [pscustomobject]@{Uri=($source.TrimEnd('/')+'/info/refs?service=git-upload-pack');Identity='项目自定义/Harmony Git来源（不改源）';Transport='managed'}}
        return $null
    }
    if($leaf-match'^(flutter|dart)(?:\.(bat|cmd|exe))?$'){
        $sdk=Split-Path -Parent (Split-Path -Parent $tool)
        if($leaf-match'^dart'-and([IO.Path]::GetFileName((Split-Path -Parent $sdk)))-ceq'cache'){$sdk=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $sdk))}
    }
    if(-not$sdk-and$Start.EnvironmentVariables.ContainsKey('JOBS_SDK_ROUTE_ROOT')){$sdk=$Start.EnvironmentVariables['JOBS_SDK_ROUTE_ROOT']}
    if($sdk){
        $publicOrigin=$false;$localGit=Read-JobsSdkRouteLocalText (Join-Path $sdk '.git/config');if($localGit-match'(?ms)^\[remote \"?origin\"?\]\s*.*?^\s*url\s*=\s*(https://[^\r\n]+)'){$source=$Matches[1].Trim();$publicOrigin=$source-cin@('https://github.com/flutter/flutter.git','https://github.com/flutter/flutter')}
        if($source-and$source-cnotin@('https://github.com/flutter/flutter.git','https://github.com/flutter/flutter')-and-not($Environment.Contains('FLUTTER_STORAGE_BASE_URL')-and$Environment['FLUTTER_STORAGE_BASE_URL'])){
            if($source-match'^https://'){return [pscustomobject]@{Uri=($source.TrimEnd('/')+'/info/refs?service=git-upload-pack');Identity='实际SDK自定义/Harmony Git来源（不按项目声明覆盖）';Transport='managed'}}
            return $null
        }
        $engine=Read-JobsSdkRouteLocalText (Join-Path $sdk 'bin/internal/engine.version')
        if($Environment.Contains('FLUTTER_PREBUILT_ENGINE_VERSION')-and$Environment['FLUTTER_PREBUILT_ENGINE_VERSION']){$engine=$Environment['FLUTTER_PREBUILT_ENGINE_VERSION']}
        if($engine-cnotmatch'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'-or$engine-in@('.','..')){return $null}
        $version=if($configuration-and$configuration.PSObject.Properties['flutter']){'声明'+[string]$configuration.flutter}else{'本地身份待确认'}
        if($arguments-match'\bupgrade\b'){
            $gitConfig=Read-JobsSdkRouteLocalText (Join-Path $sdk '.git/config')
            if($gitConfig-match'(?ms)^\[remote \"?origin\"?\]\s*.*?^\s*url\s*=\s*(https://[^\r\n]+)'){
                $origin=$Matches[1].Trim();$channel='';$head=Read-JobsSdkRouteLocalText (Join-Path $sdk '.git/HEAD')
                if($head-match'^ref: refs/heads/(stable|beta|dev|master)$'){$channel=$Matches[1]}
                $release=if($channel-and$origin-cin@('https://github.com/flutter/flutter.git','https://github.com/flutter/flutter')){Get-JobsSdkRequestedRelease $channel $Environment}else{$null}
                if(-not$release){$release=Get-JobsSdkLandedBootstrapTarget $sdk $Start.WorkingDirectory $Environment}
                return [pscustomobject]@{Uri=($origin.TrimEnd('/')+'/info/refs?service=git-upload-pack');Identity=('请求升级channel='+$channel+'；Git源保持实际origin，新版本不以旧SDK metadata冒充');Transport='managed';Artifact=$release}
            }
            if($source-match'^https://'){return [pscustomobject]@{Uri=($source.TrimEnd('/')+'/info/refs?service=git-upload-pack');Identity='请求升级当前SDK；仅预检实际Git来源';Transport='managed'}}
            return $null
        }
        $arch=if($Environment.Contains('PROCESSOR_ARCHITECTURE')-and$Environment['PROCESSOR_ARCHITECTURE']-ceq'ARM64'){'arm64'}else{'x64'}
        $dartReady=[IO.File]::Exists((Join-Path $sdk 'bin/cache/dart-sdk/bin/dart.exe'))-and(Read-JobsSdkRouteLocalText (Join-Path $sdk 'bin/cache/engine-dart-sdk.stamp'))-ceq$engine
        $object='';$transport='managed'
        if(-not$dartReady){$object='dart-sdk-windows-'+$arch+'.zip';$transport='windows-native'}
        elseif($arguments-match'\bprecache\b'){
            $cacheSource=Read-JobsSdkRouteLocalText (Join-Path $sdk 'packages/flutter_tools/lib/src/flutter_cache.dart')
            if($arguments-match'--universal\b'-and$cacheSource.Contains("'sky_engine'")){
                # 只检查本次通用缓存；健康 SDK 不为菜单设备刷新强制联网。
                $ready=(Read-JobsSdkRouteLocalText (Join-Path $sdk 'bin/cache/flutter_sdk.stamp'))-ceq$engine
                foreach($relative in @('bin/cache/pkg/sky_engine','bin/cache/artifacts/engine/common/flutter_patched_sdk','bin/cache/artifacts/engine/common/flutter_patched_sdk_product',('bin/cache/artifacts/engine/windows-'+$arch))){
                    $ready=$ready-and[IO.Directory]::Exists((Join-Path $sdk $relative))
                }
                if($cacheSource.Contains("'flutter_gpu'")){$ready=$ready-and[IO.Directory]::Exists((Join-Path $sdk 'bin/cache/pkg/flutter_gpu'))}
                foreach($name in @('material_fonts','gradle_wrapper')){
                    $expected=Read-JobsSdkRouteLocalText (Join-Path $sdk ('bin/internal/'+$name+'.version'))
                    $ready=$ready-and[bool]$expected-and(Read-JobsSdkRouteLocalText (Join-Path $sdk ('bin/cache/'+$name+'.stamp')))-ceq$expected-and[IO.Directory]::Exists((Join-Path $sdk ('bin/cache/artifacts/'+$name)))
                }
                foreach($relative in @('bin/cache/artifacts/gradle_wrapper/gradlew','bin/cache/artifacts/gradle_wrapper/gradlew.bat','bin/cache/artifacts/gradle_wrapper/gradle/wrapper/gradle-wrapper.jar')){
                    $ready=$ready-and[IO.File]::Exists((Join-Path $sdk $relative))
                }
                if($cacheSource.Contains('class FontSubsetArtifacts')){
                    $ready=$ready-and(Read-JobsSdkRouteLocalText (Join-Path $sdk 'bin/cache/font-subset.stamp'))-ceq$engine-and[IO.File]::Exists((Join-Path $sdk ('bin/cache/artifacts/engine/windows-'+$arch+'/font-subset.exe')))
                }
                if($cacheSource.Contains('class FlutterEngineStamp')){
                    $ready=$ready-and(Read-JobsSdkRouteLocalText (Join-Path $sdk 'bin/cache/engine_stamp.stamp'))-ceq$engine-and[IO.File]::Exists((Join-Path $sdk 'bin/cache/engine_stamp.json'))
                }
                # Pub与宿主工具同属通用准备；缺失时不能以stamp冒充无需下载。
                foreach($relative in @('bin/cache/pkg/sky_engine/pubspec.yaml',('bin/cache/artifacts/engine/windows-'+$arch+'/flutter_tester.exe'))){
                    $ready=$ready-and[IO.File]::Exists((Join-Path $sdk $relative))
                }
                if($cacheSource.Contains("'flutter_gpu'")){$ready=$ready-and[IO.File]::Exists((Join-Path $sdk 'bin/cache/pkg/flutter_gpu/pubspec.yaml'))}
                try{
                    if($cacheSource.Contains('class FlutterEngineStamp')){
                        $info=(Read-JobsSdkRouteLocalText (Join-Path $sdk 'bin/cache/engine_stamp.json'))|ConvertFrom-Json
                        $ready=$ready-and$info.git_revision-ceq$engine
                    }
                    $configPath=Join-Path $sdk 'packages/flutter_tools/.dart_tool/package_config.json'
                    $config=(Read-JobsSdkRouteLocalText $configPath)|ConvertFrom-Json
                    $ready=$ready-and$config.configVersion-eq2-and@($config.packages).Count-gt0
                    $baseUri=[Uri]::new([IO.Path]::GetFullPath($configPath));$seen=@{}
                    foreach($package in @($config.packages)){
                        if(-not$package.name-or$seen.ContainsKey([string]$package.name)-or-not$package.rootUri-or[string]$package.rootUri-match'[\x00-\x20]'){$ready=$false;break}
                        $seen[[string]$package.name]=$true
                        $packageUri=[Uri]::new($baseUri,[string]$package.rootUri)
                        if(-not$packageUri.IsFile-or($packageUri.Host-and$packageUri.Host-ne'localhost')-or$packageUri.Query-or$packageUri.Fragment-or-not[IO.File]::Exists((Join-Path $packageUri.LocalPath 'pubspec.yaml'))){$ready=$false;break}
                    }
                }catch{$ready=$false}
                if($ready){return $null}
                $object='sky_engine.zip'
            }
            elseif($arguments-match'--universal\b'){$object='dart-sdk-windows-'+$arch+'.zip';$transport='windows-native'}
            elseif($arguments-match'--android\b'-and$cacheSource.Contains('android-arm-profile/windows-x64.zip')){$object='android-arm-profile/windows-x64.zip'}
            elseif($arguments-match'--web\b'-and$cacheSource.Contains('flutter-web-sdk.zip')){$object='flutter-web-sdk.zip'}
            elseif($arguments-match'--windows\b'-and$cacheSource.Contains('windows-$arch-debug/windows-$arch-flutter.zip')){$object='windows-'+$arch+'-debug/windows-'+$arch+'-flutter.zip'}
            elseif($arguments-notmatch'--(?:android|web|windows|ohos|universal)\b'-and$cacheSource.Contains('android-arm-profile/windows-x64.zip')){$object='android-arm-profile/windows-x64.zip'}
        }
        if($object-and$dartReady-and$arguments-match'\bprecache\b'){
            $stamp='';$payload=''
            if($arguments-match'--android\b'){$stamp='android-sdk';$payload='bin/cache/artifacts/engine/android-arm-profile/windows-x64/gen_snapshot.exe'}
            elseif($arguments-match'--windows\b'){$stamp='windows-sdk';$payload='bin/cache/artifacts/engine/windows-'+$arch+'/flutter_windows.dll'}
            elseif($arguments-match'--web\b'){$stamp='flutter_web_sdk';$payload='bin/cache/flutter_web_sdk/kernel/amd/dart_sdk.js'}
            if($stamp-and(Read-JobsSdkRouteLocalText (Join-Path $sdk ('bin/cache/'+$stamp+'.stamp')))-ceq$engine-and[IO.File]::Exists((Join-Path $sdk $payload))){return $null}
        }
        if($object){
            $base=if($Environment.Contains('FLUTTER_STORAGE_BASE_URL')-and$Environment['FLUTTER_STORAGE_BASE_URL']){[string]$Environment['FLUTTER_STORAGE_BASE_URL']}else{'https://storage.googleapis.com'}
            $realm=Read-JobsSdkRouteLocalText (Join-Path $sdk 'bin/cache/engine.realm')
            if($Environment.Contains('FLUTTER_REALM')){$realm=[string]$Environment['FLUTTER_REALM']}
            if($realm-and($realm-match'(^|/)\.\.(/|$)|[?#\x00-\x20]'-or$realm.StartsWith('/'))){throw '本地engine.realm格式无效，未改写或探测其它命名空间。'}
            if($realm){$base=$base.TrimEnd('/')+'/'+$realm.TrimEnd('/')}
            return [pscustomobject]@{Uri=($base.TrimEnd('/')+'/flutter_infra_release/flutter/'+$engine+'/'+$object);Identity=('Flutter '+$version+' / engine '+$engine+' / realm '+$realm+' / '+$object);Transport=$transport;PublicObject=($publicOrigin-and-not$realm-and-not($Environment.Contains('FLUTTER_PREBUILT_ENGINE_VERSION')-and$Environment['FLUTTER_PREBUILT_ENGINE_VERSION']))}
        }
        # SDK 已就绪、没有已确认的下载对象时，避免例行版本检查重复联网。
        return $null
    }
    if($leaf-match'^git(?:\.exe)?$'-and$arguments-match'\b(clone|fetch|ls-remote)\b'){
        $match=[regex]::Match($arguments,'https://[^\s"]+')
        if($match.Success){return [pscustomobject]@{Uri=($match.Value.TrimEnd('/')+'/info/refs?service=git-upload-pack');Identity='当前Git/Harmony来源（不改仓库URL）';Transport='managed'}}
    }
    return $null
}
function script:Get-JobsSdkLandedBootstrapTarget {
    param([string]$Sdk,[string]$Directory,[Collections.IDictionary]$Environment)
    $flutter=Join-Path $Sdk 'bin/flutter.bat'
    if(-not[IO.File]::Exists((Join-Path $Sdk 'bin/internal/engine.version'))){return $null}
    $start=New-JobsSdkToolStart $flutter @('--version','--machine') $Directory $Environment
    $target=Get-JobsSdkProcessRouteTarget $start $Environment
    if(-not$target-or$target.Transport-cne'windows-native'){return $null}
    Add-Member -InputObject $target -NotePropertyName ExpectedSha256 -NotePropertyValue '' -Force
    $target.Identity='请求channel暂无发布归档；只核验已落地源码的实际engine自举，不冒称这是尚未解析的新目标：'+$target.Identity
    return $target
}
function script:Initialize-JobsSdkProcessNetworkRoute {
    param([Diagnostics.ProcessStartInfo]$Start)
    $environment=Get-JobsSdkRouteEnvironment $Start
    $target=Get-JobsSdkProcessRouteTarget $Start $environment
    if(-not$target){return $null}
    $artifactRoute=$null
    if($target.PSObject.Properties['Artifact']-and$target.Artifact){
        $artifactRoute=Get-JobsFlutterSdkRoute $target.Artifact.Uri $target.Artifact.Identity $environment -ExpectedSha256 $target.Artifact.ExpectedSha256 -Transport windows-native -PublicObject ([bool]$target.Artifact.PublicObject)
        if(-not$artifactRoute.Ready){throw 'SDK请求目标制品预检暂未通过，外层持续获取循环将退避重测。'}
        foreach($key in $artifactRoute.Environment.Keys){$Start.EnvironmentVariables[$key]=[string]$artifactRoute.Environment[$key]}
    }
    $public=$target.PSObject.Properties['PublicObject']-and$target.PublicObject
    $route=Get-JobsFlutterSdkRoute $target.Uri $target.Identity $environment -Transport $target.Transport -PublicObject ([bool]$public)
    if($artifactRoute-and$route.Ready){
        if($artifactRoute.AutoSource){Add-Member -InputObject $route -NotePropertyName AutoSource -NotePropertyValue $true -Force}
        Add-Member -InputObject $route -NotePropertyName RelatedRoutes -NotePropertyValue @($artifactRoute) -Force}
    if(-not$route.Ready){throw 'SDK网络预检没有可用且通过校验的路线，保留原配置并退避重测。'}
    foreach($key in $route.Environment.Keys){$Start.EnvironmentVariables[$key]=[string]$route.Environment[$key]}
    return $route
}
function script:New-JobsSdkToolStart {
    param([string]$Tool,[string[]]$Arguments,[string]$Directory,[Collections.IDictionary]$Environment)
    if($Tool-match'["\x00-\x1f]'-or@($Arguments|Where-Object{$_-match'[\x00-\x1f]'}).Count){throw '工具路径或参数含控制字符。'}
    $start=New-Object Diagnostics.ProcessStartInfo;$start.FileName=$Tool
    $start.Arguments=(@($Arguments|ForEach-Object{ConvertTo-JobsSdkRouteArgument $_})-join' ')
    if($Environment){$start.EnvironmentVariables.Clear();foreach($key in $Environment.Keys){$start.EnvironmentVariables[[string]$key]=[string]$Environment[$key]}}
    if([Environment]::OSVersion.Platform-eq[PlatformID]::Win32NT-and[IO.Path]::GetExtension($Tool)-in@('.bat','.cmd')){
        if(@($Arguments|Where-Object{$_-match'["]'}).Count){throw 'SDK批处理参数不支持引号或百分号。'}
        $start.FileName=Join-Path ([Environment]::GetFolderPath('System')) 'cmd.exe'
        $start.EnvironmentVariables['JOBS_SDK_ROUTE_TOOL']=$Tool
        $items=@();for($i=0;$i-lt$Arguments.Count;$i++){$key='JOBS_SDK_ROUTE_ARG_'+$i;$start.EnvironmentVariables[$key]=$Arguments[$i];$items+=('"%'+$key+'%"')}
        $start.Arguments='/d /v:off /s /c ""%JOBS_SDK_ROUTE_TOOL%" '+($items-join' ')+'"'
    }
    $start.EnvironmentVariables['JOBS_SDK_ROUTE_TOOL']=$Tool
    $start.WorkingDirectory=$Directory;$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    return $start
}
function script:Initialize-JobsSdkFvmRuntime {
    param([string]$Tool,[string]$Directory,[Collections.IDictionary]$Environment)
    if([IO.Path]::GetFileName($Tool)-notmatch'^fvm(?:\.(bat|cmd|ps1|exe))?$'-or-not[IO.File]::Exists($Tool)){return}
    $stream=[IO.File]::OpenRead($Tool)
    try{$header=New-Object byte[] 4;$length=$stream.Read($header,0,4)}finally{$stream.Dispose()}
    if($length-ge2-and$header[0]-eq77-and$header[1]-eq90){return}
    $launcher=Read-JobsSdkRouteLocalText $Tool
    if($launcher-notmatch'(?im)^\s*@?(?:(?:call|&)\s+)?["'']?dart(?:\.(?:bat|cmd|exe|ps1))?["'']?\s'){return}
    $pathValue=if($Environment.Contains('PATH')){[string]$Environment['PATH']}else{''}
    $dart=''
    foreach($directoryPath in ($pathValue-split';')){
        if(-not$directoryPath){continue}
        foreach($name in @('dart.exe','dart.bat','dart.cmd','dart.ps1')){
            $candidate=Join-Path $directoryPath.Trim('"') $name
            if([IO.File]::Exists($candidate)){$dart=$candidate;break}
        }
        if($dart){break}
    }
    if(-not$dart-or[IO.Path]::GetExtension($dart)-ceq'.exe'){return}
    $sdk=Split-Path -Parent (Split-Path -Parent $dart)
    if(-not[IO.File]::Exists((Join-Path $sdk 'bin/internal/shared.bat'))-and-not[IO.File]::Exists((Join-Path $sdk 'bin/internal/shared.ps1'))){return}
    $engine=Read-JobsSdkRouteLocalText (Join-Path $sdk 'bin/internal/engine.version')
    if(-not$engine){$engine=Read-JobsSdkRouteLocalText (Join-Path $sdk 'bin/cache/engine.stamp')}
    if([IO.File]::Exists((Join-Path $sdk 'bin/cache/dart-sdk/bin/dart.exe'))-and$engine-and(Read-JobsSdkRouteLocalText (Join-Path $sdk 'bin/cache/engine-dart-sdk.stamp'))-ceq$engine){return}
    $flutter=Join-Path $sdk 'bin/flutter.bat'
    if(-not[IO.File]::Exists($flutter)){$flutter=Join-Path $sdk 'bin/flutter.exe'}
    if(-not[IO.File]::Exists($flutter)){throw 'FVM当前PATH Dart来自不完整Flutter SDK且无Flutter入口；未调用FVM元数据。'}
    Write-JobsSdkRouteMessage ('FVM文本启动器使用PATH中的Flutter Dart；先准备实际管理器运行时SDK：'+$sdk+'；该SDK与待安装项目版本分开。')
    $bootstrap=New-JobsSdkToolStart $flutter @('--version','--machine') $Directory $Environment
    $originalOutput=[Console]::Out;$captured=New-Object IO.StringWriter
    try{[Console]::SetOut($captured);[void](Invoke-JobsSdkAcquireProcess $bootstrap 120 -Sanitize -Label 'FVM元数据前的实际Dart运行时准备')}
    finally{[Console]::SetOut($originalOutput);$captured.Dispose()}
}
function script:Read-JobsSdkLocalToolMetadata {
    param([string]$Tool,[string[]]$Arguments,[string]$Directory,[Collections.IDictionary]$Environment)
    Initialize-JobsSdkFvmRuntime $Tool $Directory $Environment
    $start=New-JobsSdkToolStart $Tool $Arguments $Directory $Environment
    $process=New-Object Diagnostics.Process;$process.StartInfo=$start;$begun=$false
    try{
        [void]$process.Start();$begun=$true
        $output=$process.StandardOutput.ReadToEndAsync();$errors=$process.StandardError.ReadToEndAsync()
        if(-not$process.WaitForExit(5000)){return ''}
        if($process.ExitCode-in@(129,130,137,143,-1073741510)){throw (New-Object OperationCanceledException('FVM本地元数据命令已取消。'))}
        if(-not[Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($output,$errors),1000)-or$process.ExitCode-ne0){return ''}
        return $output.GetAwaiter().GetResult()
    }catch [OperationCanceledException]{throw}catch [Management.Automation.PipelineStoppedException]{throw}catch{return ''}finally{if($begun-and-not$process.HasExited){$process.Kill()};$process.Dispose()}
}
function script:Get-JobsSdkProjectConfiguration {
    param([string]$Directory)
    foreach($name in @('.fvmrc','.fvm/fvm_config.json')){
        $text=Read-JobsSdkRouteLocalText (Join-Path $Directory $name)
        if($text){try{return $text|ConvertFrom-Json -ErrorAction Stop}catch{return $null}}
    }
    return $null
}
function script:Get-JobsSdkFvmContext {
    param([string]$Tool,[string]$Directory,[Collections.IDictionary]$Environment)
    $text=Read-JobsSdkLocalToolMetadata $Tool @('api','context','--compress') $Directory $Environment
    try{return ($text|ConvertFrom-Json -ErrorAction Stop).context}catch{return $null}
}
function script:Invoke-JobsSdkRoutedCommand {
    param([string]$Tool,[string[]]$Arguments,[string]$Directory,[int]$TimeoutSeconds=1800)
    $environment=Get-JobsSdkRouteEnvironment
    $leaf=[IO.Path]::GetFileName($Tool)
    $parameters=@($Arguments)
    if($leaf-match'^fvm(?:\.(bat|cmd|exe))?$'-and$parameters.Count-gt1-and$parameters[0]-ceq'install'){
        $help=Read-JobsSdkLocalToolMetadata $Tool @('install','--help') $Directory $environment
        if($help-match'--\[no-\]setup|--no-setup'){
            if($parameters-notcontains'--no-setup'){$parameters+='--no-setup'}
            Write-JobsSdkRouteMessage 'FVM能力已确认：先 --no-setup 只获取Git SDK；Dart/引擎自举由后续独立阶段选路，不在Git测速结果下隐式拉制品。'
        }else{Write-JobsSdkRouteMessage '当前FVM未声明--no-setup，保留原参数；下载失败后按已落地SDK元数据重新预检，不硬加不支持的选项。'}
    }
    if($leaf-match'^fvm(?:\.(bat|cmd|exe))?$'-and$parameters.Count-gt1-and$parameters[0]-ceq'use'){
        $context=Get-JobsSdkFvmContext $Tool $Directory $environment
        if($context-and$context.PSObject.Properties['versionsCachePath']){
            $sdk=Join-Path $context.versionsCachePath $parameters[1]
            $flutter=Join-Path $sdk 'bin/flutter.bat'
            if([IO.File]::Exists($flutter)){$bootstrap=New-JobsSdkToolStart $flutter @('--version','--machine') $Directory $environment;[void](Invoke-JobsSdkAcquireProcess $bootstrap 120 -Sanitize -Label ('FVM目标SDK自举：'+$parameters[1]))}
        }
    }
    if($leaf-match'^flutter(?:\.(bat|cmd|exe))?$'-and$parameters.Count-and$parameters[0]-ceq'upgrade'){
        $bootstrap=New-JobsSdkToolStart $Tool @('--version','--machine') $Directory $environment
        [void](Invoke-JobsSdkAcquireProcess $bootstrap 120 -Sanitize -Label '升级前当前SDK自举；与所请求新版本分开核验')
    }
    $start=New-JobsSdkToolStart $Tool $parameters $Directory $environment
    $sdkAction=($leaf-match'^(flutter|dart)(?:\.(bat|cmd|exe))?$'-and$parameters.Count-gt0-and$parameters[0]-in@('--version','precache','upgrade'))-or($leaf-match'^fvm(?:\.(bat|cmd|exe))?$'-and$parameters.Count-gt0-and$parameters[0]-in@('install','flutter'))
    if($sdkAction){return Invoke-JobsSdkAcquireProcess $start $TimeoutSeconds -Sanitize -Label ('SDK获取：'+$leaf+' '+($parameters-join' '))}
    Initialize-JobsSdkCommandPrerequisites $Tool $parameters $Directory
    return Invoke-JobsSdkLiveProcess $start $TimeoutSeconds -Sanitize
}
function script:Receive-JobsSdkRoutedFile {
    param($Route,[string]$Destination,[int]$TimeoutSeconds,[Collections.IDictionary]$Environment)
    $curl=$null
    foreach($name in @('curl.exe','curl')){$command=Get-Command $name -CommandType Application -ErrorAction SilentlyContinue|Select-Object -First 1;if($command){$curl=$command.Source;break}}
    if(-not$curl){throw '已选择网络路线但没有可执行curl，不能用未套用路线的下载器冒充；请准备curl后继续。'}
    $metadataFile=$Destination+'.resume.json';$offset=[long]0
    if([IO.File]::Exists($Destination)){
        $canResume=$false
        if([IO.File]::Exists($metadataFile)){
            try{$metadata=[IO.File]::ReadAllText($metadataFile)|ConvertFrom-Json -ErrorAction Stop;$canResume=$metadata.Uri-ceq$Route.Uri-and$metadata.Validator-and$Route.ETag-and([string]$metadata.Validator).Trim('"')-ceq$Route.ETag}catch{}
        }
        if($canResume){$offset=(Get-Item -LiteralPath $Destination -Force).Length}
        else{Move-Item -LiteralPath $Destination -Destination ($Destination+'.previous-'+[guid]::NewGuid().ToString('N'))}
    }
    [IO.File]::WriteAllText($metadataFile,(@{Uri=$Route.Uri;Validator=$Route.ETag}|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
    $headers=$Destination+'.headers-'+[guid]::NewGuid().ToString('N')
    $args=@('--fail','--location','--max-redirs','5','--proto','=https','--proto-redir','=https','--connect-timeout','15','--speed-time','30','--speed-limit','1','--retry','0','--output',$Destination,'--dump-header',$headers)
    if($offset-gt0){$args+=@('--continue-at',[string]$offset,'--header',('If-Range: "'+$Route.ETag+'"'))}
    if($Route.ProxyMode-ceq'direct'){$args+=@('--proxy','','--noproxy','*')}
    elseif($Route.ProxyMode-in@('configured-proxy','native-wininet')){$args+=@('--proxy',$Route.Proxy)}
    $args+=@('--url',$Route.Uri)
    $start=New-JobsSdkToolStart $curl $args (Split-Path -Parent $Destination) $Environment
    foreach($key in $Route.Environment.Keys){$start.EnvironmentVariables[$key]=[string]$Route.Environment[$key]}
    try{
        $result=Invoke-JobsSdkLiveProcess $start ([Math]::Max(30,$TimeoutSeconds)) -Sanitize -Acquisition
        if($result.ExitCode-in@(129,130,137,143,-1073741510)){throw (New-Object Management.Automation.PipelineStoppedException)}
        if($result.ExitCode-ne0){
            if($result.ExitCode-eq33-and[IO.File]::Exists($Destination)){Move-Item -LiteralPath $Destination -Destination ($Destination+'.unresumable-'+[guid]::NewGuid().ToString('N'))}
            throw ('选定路线下载失败，退出码 '+$result.ExitCode+'；缓存保留，将失效路线重新预检。')
        }
        $length=if([IO.File]::Exists($Destination)){(Get-Item -LiteralPath $Destination -Force).Length}else{0}
        if($length-ne$Route.Total){throw ('制品实际长度与已验证对象不符：'+$length+'/'+$Route.Total)}
        if($Route.ExpectedMD5-and(Get-FileHash -LiteralPath $Destination -Algorithm MD5).Hash-ine$Route.ExpectedMD5){throw '制品完整MD5与官方对象/HTTP ETag证据不符，未作为下载成功。'}
        Write-JobsSdkRouteMessage ('选定路线下载完成：'+$length+'字节；'+$Route.Uri)
    }finally{if([IO.File]::Exists($headers)){[IO.File]::Delete($headers)}}
}
function script:Initialize-JobsSdkCommandPrerequisites {
    param([string]$Tool,[string[]]$Arguments,[string]$Directory,[string]$Platform='')
    if([IO.Path]::GetFileName($Tool)-notmatch'^(flutter|dart)(?:\.(bat|cmd|exe))?$'-or-not$Arguments.Count){return}
    if($Arguments[0]-in@('--version','precache','upgrade')){return}
    $environment=Get-JobsSdkRouteEnvironment
    $start=New-JobsSdkToolStart $Tool $Arguments $Directory $environment
    $target=Get-JobsSdkProcessRouteTarget $start $environment
    $sdk=Split-Path -Parent (Split-Path -Parent $Tool)
    if([IO.Path]::GetFileName($Tool)-match'^dart'-and([IO.Path]::GetFileName((Split-Path -Parent $sdk)))-ceq'cache'){$sdk=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $sdk))}
    $flutter=Join-Path $sdk 'bin/flutter.bat'
    if(-not[IO.File]::Exists($flutter)){$flutter=Join-Path $sdk 'bin/flutter.exe'}
    if(-not[IO.File]::Exists($flutter)){return}
    if($target-and$target.Transport-ceq'windows-native'){
        $bootstrap=New-JobsSdkToolStart $flutter @('--version','--machine') $Directory $environment
        [void](Invoke-JobsSdkAcquireProcess $bootstrap 120 -Sanitize -Label '业务前SDK自举；失败仅重做SDK获取')
    }
    $targetPlatform=$Platform
    if(-not$targetPlatform-and$Arguments[0]-ceq'build'-and$Arguments.Count-gt1){$targetPlatform=switch($Arguments[1]){'apk'{'android'}'appbundle'{'android'}'windows'{'windows'}'web'{'web'}'hap'{'ohos'}'app'{'ohos'}default{''}}}
    if(-not$targetPlatform){return}
    if($targetPlatform-in@('physical','emulator')){$targetPlatform='android'}
    if($targetPlatform-notin@('android','windows','web','ohos')){return}
    $cacheSource=Read-JobsSdkRouteLocalText (Join-Path $sdk 'packages/flutter_tools/lib/src/flutter_cache.dart')
    if(-not$cacheSource){return}
    if($targetPlatform-ceq'ohos'){
        $helpStart=New-JobsSdkToolStart $flutter @('precache','--help') $Directory $environment
        $help=Invoke-JobsSdkLiveProcess $helpStart 120 -Sanitize
        if($help.ExitCode-ne0-or($help.StdOut+$help.StdErr)-notmatch'--(?:\[no-\])?ohos\b'){throw '当前SDK未确认支持precache --ohos，未开始业务构建。'}
    }
    $precache=New-JobsSdkToolStart $flutter @('precache',('--'+$targetPlatform)) $Directory $environment
    [void](Invoke-JobsSdkAcquireProcess $precache 1800 -Sanitize -Label ('业务前SDK平台制品：'+$targetPlatform))
}
function script:Invoke-JobsSdkRouteEntry {
    param([string]$Tool,[string]$Directory,[string]$ArgumentsBase64)
    if(-not$Tool){return}
    # CLI桥接把预检与重试说明写stderr；stdout只保留SDK原始输出。
    function script:Write-JobsSdkRetryMessage {
        param([string]$Message)
        $safe=Protect-JobsSdkRouteText $Message
        [Console]::Error.WriteLine($safe)
        [IO.File]::AppendAllText((Get-JobsSdkRetryLog),$safe+[Environment]::NewLine,(New-Object Text.UTF8Encoding($false)))
    }
    $script:JobsSdkCliLiveProcess=${function:Invoke-JobsSdkLiveProcess}
    function script:Invoke-JobsSdkLiveProcess {
        param([Diagnostics.ProcessStartInfo]$Start,[int]$TimeoutSeconds=120,[switch]$Sanitize,[switch]$Acquisition)
        $result=& $script:JobsSdkCliLiveProcess $Start $TimeoutSeconds -Sanitize:$Sanitize -Acquisition:$Acquisition
        if($result.ExitCode-in@(129,130,137,143,-1073741510)){throw (New-Object OperationCanceledException('SDK进程已取消。'))}
        return $result
    }
    try{
        $arguments=@([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ArgumentsBase64))|ConvertFrom-Json -ErrorAction Stop)
        if(@($arguments|Where-Object{$_-isnot[string]}).Count){throw 'SDK argv必须是JSON字符串数组。'}
        $result=Invoke-JobsSdkRoutedCommand $Tool ([string[]]$arguments) $Directory 1800
        exit $result.ExitCode
    }catch [OperationCanceledException]{[Console]::Error.WriteLine('已取消SDK获取。');exit 130}
    catch{[Console]::Error.WriteLine((Protect-JobsSdkRouteText $_.Exception.Message));exit 1}
}

if($RunTool){. (Resolve-JobsScriptLayoutPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'SdkDownloadOutput.ps1'))}
Invoke-JobsSdkRouteEntry $RunTool $RunDirectory $RunArgumentsBase64

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

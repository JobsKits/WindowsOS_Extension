// Created by Jobs on 2026年10月18日，星期日.
// Git filters keep Typora's source token local and store a generated disclosure.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync, spawnSync } from 'node:child_process';

// >>> Jobs terminal style protection v1 >>>
// 仅监督独立 CLI；导入、预加载和纯文本环境保留原执行方式。
async function jobsTerminalStyleBootstrap(moduleURL) {
  const { fileURLToPath: jobsFileURLToPath } = await import('node:url');
  const jobsFS = await import('node:fs');
  const jobsEntry = process.argv[1];
  if (!jobsEntry) return;
  try {
    if (jobsFS.realpathSync(jobsFileURLToPath(moduleURL)) !== jobsFS.realpathSync(jobsEntry)) return;
  } catch {
    return;
  }
  if (process.env.JOBS_TERMINAL_NODE_REEXEC === jobsEntry) {
    delete process.env.JOBS_TERMINAL_NODE_REEXEC;
    return;
  }
  const jobsPreload = /^(?:-r(?:$|[^-])|--(?:require|import|loader|experimental-loader)(?:=|$))/;
  const jobsNodeOptions = process.env.NODE_OPTIONS || '';
  if (process.execArgv.some(value => jobsPreload.test(value)) ||
      /(?:^|[\s"'])(?:-r(?=$|[^-])|--(?:require|import|loader|experimental-loader)(?=$|[=\s"']))/.test(jobsNodeOptions)) return;
  if (!process.stdin.isTTY || !process.stdout.isTTY || !process.stderr.isTTY ||
      (process.platform !== 'win32' && !process.env.TERM) || process.env.TERM === 'dumb' ||
      Object.prototype.hasOwnProperty.call(process.env, 'NO_COLOR') || process.env.PLAIN_OUTPUT === '1' ||
      process.env.IS_SOURCETREE_RUNTIME === '1' || process.env.TMUX || process.env.STY ||
      Object.keys(process.env).some(key => /^SOURCE_?TREE/i.test(key))) return;

  const { spawn: jobsSpawn } = await import('node:child_process');
  const jobsPath = await import('node:path');
  const jobsOS = await import('node:os');
  const jobsEnvironment = { ...process.env, JOBS_TERMINAL_NODE_REEXEC: jobsEntry };
  const jobsArguments = [...process.execArgv, ...process.argv.slice(1)];
  let jobsTemporary = null;
  let jobsWindowsReceipt = null;
  let jobsCommand;
  let jobsCommandArguments;
  let jobsGuardianStarted = false;
  let jobsInterrupted = false;
  // 临时监督器已执行后，清理失败不能重跑一遍业务。
  const jobsCleanupTemporary = () => {
    if (!jobsTemporary) return;
    try {
      jobsFS.rmSync(jobsTemporary, { recursive: true, force: true });
    } catch (jobsCleanupError) {
      console.error(`[Jobs] 临时监督器清理失败：${jobsCleanupError.message}`);
    }
    jobsTemporary = null;
  };
  try {
    if (process.platform === 'win32') {
      // PowerShell 5 的旧原生参数转义会丢空值；原参数由 Node 桥按数组传递。
      const jobsBridge = [
        "const {spawn}=require('node:child_process');",
        "const signals=require('node:os').constants.signals;",
        "const command=JSON.parse(Buffer.from(process.env.JOBS_TERMINAL_NODE_COMMAND,'base64').toString('utf8'));",
        "require('node:fs').writeFileSync(process.env.JOBS_TERMINAL_NODE_RECEIPT,'started',{flag:'wx',mode:0o600});",
        "delete process.env.JOBS_TERMINAL_NODE_RECEIPT;",
        "delete process.env.JOBS_TERMINAL_NODE_COMMAND;delete process.env.JOBS_TERMINAL_NODE_BRIDGE;",
        "const child=spawn(command.program,command.arguments,{stdio:'inherit',env:process.env});",
        "const interrupt=()=>{};process.on('SIGINT',interrupt);",
        "child.once('error',error=>{console.error('[Jobs] '+error.message);process.exit(1);});",
        "child.once('close',(code,signal)=>{process.removeListener('SIGINT',interrupt);process.exit(code??(signals[signal]?128+signals[signal]:1));});"
      ].join('');
      jobsEnvironment.JOBS_TERMINAL_NODE_COMMAND = Buffer.from(JSON.stringify({
        program: process.execPath, arguments: jobsArguments
      }), 'utf8').toString('base64');
      jobsEnvironment.JOBS_TERMINAL_NODE_BRIDGE = Buffer.from(jobsBridge, 'utf8').toString('base64');
      jobsTemporary = jobsFS.mkdtempSync(jobsPath.join(jobsOS.tmpdir(), 'jobs-terminal-node-'));
      jobsWindowsReceipt = jobsPath.join(jobsTemporary, 'started');
      jobsEnvironment.JOBS_TERMINAL_NODE_RECEIPT = jobsWindowsReceipt;
      const jobsSupervisorPath = jobsPath.join(jobsTemporary, 'supervisor.ps1');
      const jobsWindowsSupervisor = [
        "$__jobsTerminalCommand = @($args)\n",
        "# BEGIN JOBS_TERMINAL_STYLE_V1 - session-only colors; no profile or registry changes.\n",
        "function New-JobsTerminalStyleState {\n",
        "    if ($PSVersionTable.PSVersion.Major -lt 5) { return @{ JobsTerminalPlainFallback = $true; Before = @{} } }\n",
        "    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $Host.Name -ne 'ConsoleHost') { return $null }\n",
        "    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected -or [Console]::IsErrorRedirected) { return $null }\n",
        "    if ((Test-Path Env:NO_COLOR) -or $env:TERM -ieq 'dumb' -or $env:PLAIN_OUTPUT -eq '1') { return $null }\n",
        "    foreach ($key in [Environment]::GetEnvironmentVariables().Keys) {\n",
        "        if ([string]$key -match '^(?i:SOURCE_?TREE)') { return $null }\n",
        "    }\n",
        "    if (-not ('Jobs.TerminalStyleV1.Native' -as [type])) {\n",
        "        try {\n",
        "        Add-Type -ErrorAction Stop -TypeDefinition @'\n",
        "using System;\n",
        "using System.Collections.Generic;\n",
        "using System.Diagnostics;\n",
        "using System.IO;\n",
        "using System.Runtime.InteropServices;\n",
        "using System.Text;\n",
        "using System.Text.RegularExpressions;\n",
        "namespace Jobs.TerminalStyleV1 {\n",
        "    public static class Native {\n",
        "        [StructLayout(LayoutKind.Explicit, Size=20, CharSet=CharSet.Unicode)]\n",
        "        public struct InputRecord {\n",
        "            [FieldOffset(0)] public ushort Kind;\n",
        "            [FieldOffset(4)] public int Down;\n",
        "            [FieldOffset(8)] public ushort Repeat;\n",
        "            [FieldOffset(10)] public ushort Key;\n",
        "            [FieldOffset(12)] public ushort Scan;\n",
        "            [FieldOffset(14)] public char Character;\n",
        "            [FieldOffset(16)] public uint Modifiers;\n",
        "        }\n",
        "        [DllImport(\"kernel32.dll\")] static extern IntPtr GetStdHandle(int n);\n",
        "        [DllImport(\"kernel32.dll\")] static extern IntPtr GetConsoleWindow();\n",
        "        [DllImport(\"kernel32.dll\")] static extern bool GetConsoleMode(IntPtr h, out uint mode);\n",
        "        [DllImport(\"kernel32.dll\")] static extern bool SetConsoleMode(IntPtr h, uint mode);\n",
        "        [DllImport(\"kernel32.dll\")] static extern uint WaitForSingleObject(IntPtr h, uint milliseconds);\n",
        "        [DllImport(\"kernel32.dll\")] static extern bool GetNumberOfConsoleInputEvents(IntPtr h, out uint count);\n",
        "        [DllImport(\"kernel32.dll\", CharSet=CharSet.Unicode, ExactSpelling=true)] static extern bool ReadConsoleInputW(IntPtr h, [Out] InputRecord[] records, uint count, out uint read);\n",
        "        [DllImport(\"kernel32.dll\", CharSet=CharSet.Unicode, ExactSpelling=true)] static extern bool WriteConsoleInputW(IntPtr h, InputRecord[] records, uint count, out uint written);\n",
        "        const string OwnerName = \"JOBS_TERMINAL_STYLE_WINDOWS_OWNER\";\n",
        "        static readonly string[] Keys = { \"10\", \"11\", \"4;0\", \"4;1\", \"4;2\", \"4;3\", \"4;4\", \"4;5\", \"4;6\", \"4;7\", \"4;8\", \"4;9\", \"4;10\", \"4;11\", \"4;12\", \"4;13\", \"4;14\", \"4;15\" };\n",
        "        static readonly string[] Hex = { \"000000\", \"ff5f56\", \"5fd787\", \"ffd75f\", \"5fafff\", \"d787ff\", \"5fd7ff\", \"eeeeee\", \"9e9e9e\", \"ff8787\", \"87ffaf\", \"ffff87\", \"87bfff\", \"ffafff\", \"afffff\", \"ffffff\" };\n",
        "        static readonly Regex Reply = new Regex(\"\\\\x1b\\\\](?<key>10|11|4;[0-9]{1,2});(?<rgb>rgb:[0-9a-f]{1,4}/[0-9a-f]{1,4}/[0-9a-f]{1,4})(?:\\\\x07|\\\\x1b\\\\\\\\)\", RegexOptions.IgnoreCase);\n",
        "        public sealed class State {\n",
        "            public IntPtr Input, Output;\n",
        "            public uint OutputMode;\n",
        "            public ConsoleColor Foreground, Background;\n",
        "            public Dictionary<string,string> Original, Applied;\n",
        "            public string Owner, PreviousOwner, Recovery;\n",
        "            public bool Active, ModeChanged, Fallback;\n",
        "            public Dictionary<string,string> EnvironmentBefore = new Dictionary<string,string>();\n",
        "        }\n",
        "        static string Escape(string key, string value) { return \"\\x1b]\" + key + \";\" + value + \"\\x07\"; }\n",
        "        static string Rgb(string hex) { return \"rgb:\" + hex.Substring(0,2) + \"/\" + hex.Substring(2,2) + \"/\" + hex.Substring(4,2); }\n",
        "        static string Normal(string rgb) {\n",
        "            string[] parts = rgb.Substring(4).Split('/');\n",
        "            for (int n=0; n<3; n++) {\n",
        "                int maximum = (1 << (4 * parts[n].Length)) - 1;\n",
        "                int value = Convert.ToInt32(parts[n],16);\n",
        "                parts[n] = ((value * 65535L + maximum/2) / maximum).ToString(\"x4\");\n",
        "            }\n",
        "            return String.Join(\"/\",parts);\n",
        "        }\n",
        "        // Preserve unrelated key/window records instead of consuming user input during color queries.\n",
        "        static Dictionary<string,string> Query(State state) {\n",
        "            uint pending;\n",
        "            if (!GetNumberOfConsoleInputEvents(state.Input,out pending) || pending != 0) { return null; }\n",
        "            StringBuilder commands = new StringBuilder();\n",
        "            foreach (string key in Keys) { commands.Append(Escape(key,\"?\")); }\n",
        "            Console.Write(commands.ToString());\n",
        "            List<InputRecord> records = new List<InputRecord>();\n",
        "            List<int> characterIndices = new List<int>();\n",
        "            StringBuilder text = new StringBuilder();\n",
        "            Dictionary<string,string> result = new Dictionary<string,string>();\n",
        "            Stopwatch timer = Stopwatch.StartNew();\n",
        "            try {\n",
        "                while (timer.ElapsedMilliseconds < 600) {\n",
        "                    if (result.Count == Keys.Length && GetNumberOfConsoleInputEvents(state.Input,out pending) && pending == 0) { break; }\n",
        "                    if (WaitForSingleObject(state.Input,20) != 0) { continue; }\n",
        "                    InputRecord[] item = new InputRecord[1]; uint read;\n",
        "                    if (!ReadConsoleInputW(state.Input,item,1,out read) || read != 1) { break; }\n",
        "                    int index = -1;\n",
        "                    if (item[0].Kind == 1 && item[0].Character != '\\0') {\n",
        "                        if (item[0].Down != 0) { index = text.Length; text.Append(item[0].Character); }\n",
        "                        else if (text.Length != 0 && text[text.Length-1] == item[0].Character) { index = text.Length-1; }\n",
        "                    }\n",
        "                    records.Add(item[0]); characterIndices.Add(index);\n",
        "                    foreach (Match match in Reply.Matches(text.ToString())) {\n",
        "                        string key = match.Groups[\"key\"].Value;\n",
        "                        if (Array.IndexOf(Keys,key) >= 0) { result[key] = match.Groups[\"rgb\"].Value; }\n",
        "                    }\n",
        "                }\n",
        "            } finally {\n",
        "                bool[] used = new bool[text.Length];\n",
        "                foreach (Match match in Reply.Matches(text.ToString())) {\n",
        "                    for (int n=match.Index; n<match.Index+match.Length; n++) { used[n] = true; }\n",
        "                }\n",
        "                List<InputRecord> replay = new List<InputRecord>();\n",
        "                for (int n=0; n<records.Count; n++) {\n",
        "                    int index = characterIndices[n];\n",
        "                    if (index < 0 || !used[index]) { replay.Add(records[n]); }\n",
        "                }\n",
        "                if (replay.Count != 0) {\n",
        "                    uint written;\n",
        "                    if (!WriteConsoleInputW(state.Input,replay.ToArray(),(uint)replay.Count,out written) || written != replay.Count) {\n",
        "                        Console.Error.WriteLine(\"[Jobs] Could not replay terminal input; color protection is unavailable.\");\n",
        "                        result.Clear();\n",
        "                    }\n",
        "                }\n",
        "            }\n",
        "            return result.Count == Keys.Length ? result : null;\n",
        "        }\n",
        "        static void Plain(State state) {\n",
        "            foreach (string key in new string[] { \"NO_COLOR\", \"PLAIN_OUTPUT\", \"FORCE_COLOR\", \"CLICOLOR\", \"ANSI_COLORS_DISABLED\" }) {\n",
        "                state.EnvironmentBefore[key] = Environment.GetEnvironmentVariable(key);\n",
        "                Environment.SetEnvironmentVariable(key, key == \"FORCE_COLOR\" || key == \"CLICOLOR\" ? \"0\" : \"1\");\n",
        "            }\n",
        "            state.Fallback = true;\n",
        "        }\n",
        "        public static void Enter(State state) {\n",
        "            try {\n",
        "                state.Input = GetStdHandle(-10); state.Output = GetStdHandle(-11);\n",
        "                uint inputMode;\n",
        "                if (!GetConsoleMode(state.Input,out inputMode) || !GetConsoleMode(state.Output,out state.OutputMode)) { Plain(state); return; }\n",
        "                IntPtr window = GetConsoleWindow();\n",
        "                if (window == IntPtr.Zero) { Plain(state); return; }\n",
        "                string identity = window.ToInt64().ToString(\"x\");\n",
        "                state.PreviousOwner = Environment.GetEnvironmentVariable(OwnerName);\n",
        "                if (!String.IsNullOrEmpty(state.PreviousOwner)) {\n",
        "                    string[] owner = state.PreviousOwner.Split(':');\n",
        "                    int pid; long started;\n",
        "                    if (owner.Length == 3 && owner[0] == identity && Int32.TryParse(owner[1],out pid) && Int64.TryParse(owner[2],out started)) {\n",
        "                        try { if (Process.GetProcessById(pid).StartTime.ToUniversalTime().Ticks == started) { return; } } catch {}\n",
        "                    }\n",
        "                }\n",
        "                state.Foreground = Console.ForegroundColor; state.Background = Console.BackgroundColor;\n",
        "                if ((state.OutputMode & 4) == 0) {\n",
        "                    if (!SetConsoleMode(state.Output,state.OutputMode | 4)) { Plain(state); return; }\n",
        "                    state.ModeChanged = true;\n",
        "                }\n",
        "                state.Original = Query(state);\n",
        "                if (state.Original == null) { Restore(state); Plain(state); return; }\n",
        "                state.Applied = new Dictionary<string,string>();\n",
        "                state.Applied[\"10\"] = \"rgb:ff/ff/ff\"; state.Applied[\"11\"] = \"rgb:00/00/00\";\n",
        "                for (int n=0; n<16; n++) { state.Applied[\"4;\"+n] = Rgb(Hex[n]); }\n",
        "                StringBuilder restore = new StringBuilder();\n",
        "                foreach (string key in Keys) { restore.Append(Escape(key,state.Original[key])); }\n",
        "                string encoded = Convert.ToBase64String(Encoding.UTF8.GetBytes(restore.ToString()));\n",
        "                state.Recovery = Path.Combine(Path.GetTempPath(),\"JobsTerminalStyle-\"+Process.GetCurrentProcess().Id+\"-\"+Guid.NewGuid().ToString(\"N\")+\".ps1\");\n",
        "                string manual = \"# Restore only the session colors saved by this Jobs script.\\r\\n\"+\n",
        "                    \"if ([Console]::IsOutputRedirected) { throw 'Run in the original console.' }\\r\\n\"+\n",
        "                    \"Add-Type -Namespace Jobs -Name RecoveryConsole -MemberDefinition '[System.Runtime.InteropServices.DllImport(\\\"kernel32.dll\\\")] public static extern System.IntPtr GetStdHandle(int n); [System.Runtime.InteropServices.DllImport(\\\"kernel32.dll\\\")] public static extern bool GetConsoleMode(System.IntPtr h, out uint m); [System.Runtime.InteropServices.DllImport(\\\"kernel32.dll\\\")] public static extern bool SetConsoleMode(System.IntPtr h, uint m);'\\r\\n\"+\n",
        "                    \"$h = [Jobs.RecoveryConsole]::GetStdHandle(-11); [uint32]$m = 0\\r\\n\"+\n",
        "                    \"if (-not [Jobs.RecoveryConsole]::GetConsoleMode($h, [ref]$m)) { throw 'Run in the original console.' }\\r\\n\"+\n",
        "                    \"try {\\r\\nif (-not [Jobs.RecoveryConsole]::SetConsoleMode($h, ($m -bor 4))) { throw 'Cannot enable terminal recovery.' }\\r\\n\"+\n",
        "                    \"[Console]::Write([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('\"+encoded+\"')))\\r\\n\"+\n",
        "                    \"[Console]::ForegroundColor = [ConsoleColor]\"+((int)state.Foreground)+\"\\r\\n\"+\n",
        "                    \"[Console]::BackgroundColor = [ConsoleColor]\"+((int)state.Background)+\"\\r\\n\"+\n",
        "                    \"[Console]::Write([string][char]27 + '[39;49m')\\r\\n\"+\n",
        "                    \"} finally { [void][Jobs.RecoveryConsole]::SetConsoleMode($h, $m) }\\r\\n\";\n",
        "                File.WriteAllText(state.Recovery,manual,new UTF8Encoding(false));\n",
        "                state.Owner = identity+\":\"+Process.GetCurrentProcess().Id+\":\"+Process.GetCurrentProcess().StartTime.ToUniversalTime().Ticks;\n",
        "                Environment.SetEnvironmentVariable(OwnerName,state.Owner);\n",
        "                state.Active = true;\n",
        "                foreach (string key in Keys) { Console.Write(Escape(key,state.Applied[key])); }\n",
        "                Console.ForegroundColor = ConsoleColor.White; Console.BackgroundColor = ConsoleColor.Black;\n",
        "                Dictionary<string,string> check = Query(state);\n",
        "                foreach (string key in Keys) {\n",
        "                    if (check == null || Normal(check[key]) != Normal(state.Applied[key])) { Restore(state); Plain(state); return; }\n",
        "                }\n",
        "            } catch (Exception error) {\n",
        "                Restore(state); Plain(state);\n",
        "                Console.Error.WriteLine(\"[Jobs] Terminal style unavailable: \" + error.Message);\n",
        "            }\n",
        "        }\n",
        "        public static void Restore(State state) {\n",
        "            if (state == null) { return; }\n",
        "            try {\n",
        "                if (state.Active) {\n",
        "                    Dictionary<string,string> current = Query(state);\n",
        "                    bool complete = current != null;\n",
        "                    if (current != null) {\n",
        "                        bool restoreForeground = Console.ForegroundColor == ConsoleColor.White && Normal(current[\"10\"]) == Normal(state.Applied[\"10\"]) && Normal(current[\"4;15\"]) == Normal(state.Applied[\"4;15\"]);\n",
        "                        bool restoreBackground = Console.BackgroundColor == ConsoleColor.Black && Normal(current[\"11\"]) == Normal(state.Applied[\"11\"]) && Normal(current[\"4;0\"]) == Normal(state.Applied[\"4;0\"]);\n",
        "                        foreach (string key in Keys) {\n",
        "                            if (Normal(current[key]) == Normal(state.Applied[key])) { Console.Write(Escape(key,state.Original[key])); }\n",
        "                            else if (Normal(current[key]) != Normal(state.Original[key])) {\n",
        "                                complete = false; Console.Error.WriteLine(\"[Jobs] Kept a concurrent color change: \" + key);\n",
        "                            }\n",
        "                        }\n",
        "                        if (restoreForeground) { Console.ForegroundColor = state.Foreground; Console.Write(\"\\x1b[39m\"); }\n",
        "                        if (restoreBackground) { Console.BackgroundColor = state.Background; Console.Write(\"\\x1b[49m\"); }\n",
        "                    }\n",
        "                    if (complete) {\n",
        "                        Dictionary<string,string> check = Query(state);\n",
        "                        foreach (string key in Keys) { if (check == null || Normal(check[key]) != Normal(state.Original[key])) { complete = false; } }\n",
        "                    }\n",
        "                    if (complete) { File.Delete(state.Recovery); }\n",
        "                    else { Console.Error.WriteLine(\"[Jobs] Color restore needs review. Manual recovery: powershell -NoProfile -File \\\"\"+state.Recovery+\"\\\"\"); }\n",
        "                }\n",
        "            } catch (Exception error) {\n",
        "                Console.Error.WriteLine(\"[Jobs] Color restore failed: \"+error.Message+\"; recovery: \"+state.Recovery);\n",
        "            } finally {\n",
        "                if (state.Owner != null && Environment.GetEnvironmentVariable(OwnerName) == state.Owner) { Environment.SetEnvironmentVariable(OwnerName,state.PreviousOwner); }\n",
        "                state.Active = false;\n",
        "                uint currentMode;\n",
        "                if (state.ModeChanged && GetConsoleMode(state.Output,out currentMode) && currentMode == (state.OutputMode | 4)) { SetConsoleMode(state.Output,state.OutputMode); }\n",
        "                state.ModeChanged = false;\n",
        "                if (state.Fallback) {\n",
        "                    foreach (KeyValuePair<string,string> pair in state.EnvironmentBefore) {\n",
        "                        string applied = pair.Key == \"FORCE_COLOR\" || pair.Key == \"CLICOLOR\" ? \"0\" : \"1\";\n",
        "                        if (Environment.GetEnvironmentVariable(pair.Key) == applied) { Environment.SetEnvironmentVariable(pair.Key,pair.Value); }\n",
        "                    }\n",
        "                    state.Fallback = false;\n",
        "                }\n",
        "            }\n",
        "        }\n",
        "    }\n",
        "}\n",
        "'@\n",
        "        } catch {\n",
        "            [Console]::Error.WriteLine('[Jobs] Terminal style setup failed; using plain output: ' + $_.Exception.Message)\n",
        "            return @{ JobsTerminalPlainFallback = $true; Before = @{} }\n",
        "        }\n",
        "    }\n",
        "    return New-Object Jobs.TerminalStyleV1.Native+State\n",
        "}\n",
        "# Guard setup is optional; failure keeps business behavior and the user's original terminal settings.\n",
        "function Start-JobsTerminalStyle {\n",
        "    param($State)\n",
        "    if ($State -is [Collections.IDictionary] -and $State.Contains('JobsTerminalPlainFallback')) {\n",
        "        foreach ($key in @('NO_COLOR', 'PLAIN_OUTPUT', 'FORCE_COLOR', 'CLICOLOR', 'ANSI_COLORS_DISABLED')) {\n",
        "            $State.Before[$key] = [Environment]::GetEnvironmentVariable($key)\n",
        "            [Environment]::SetEnvironmentVariable($key, $(if (@('FORCE_COLOR', 'CLICOLOR') -contains $key) { '0' } else { '1' }))\n",
        "        }\n",
        "        return\n",
        "    }\n",
        "    if ($null -ne $State) { [Jobs.TerminalStyleV1.Native]::Enter($State) }\n",
        "}\n",
        "# A finally block also runs for script exit and Ctrl+C; direct .NET calls avoid stopped pipelines.\n",
        "function Stop-JobsTerminalStyle {\n",
        "    param($State)\n",
        "    if ($State -is [Collections.IDictionary] -and $State.Contains('JobsTerminalPlainFallback')) {\n",
        "        foreach ($key in $State.Before.Keys) {\n",
        "            $applied = if (@('FORCE_COLOR', 'CLICOLOR') -contains $key) { '0' } else { '1' }\n",
        "            if ([Environment]::GetEnvironmentVariable($key) -ceq $applied) { [Environment]::SetEnvironmentVariable($key, $State.Before[$key]) }\n",
        "        }\n",
        "        return\n",
        "    }\n",
        "    if ($null -ne $State) { [Jobs.TerminalStyleV1.Native]::Restore($State) }\n",
        "}\n",
        "# END JOBS_TERMINAL_STYLE_V1\n",
        "\n",
        "$__jobsTerminalStyleState = $null\n",
        "$__jobsTerminalExitCode = 0\n",
        "try {\n",
        "    $__jobsTerminalStyleState = New-JobsTerminalStyleState\n",
        "    Start-JobsTerminalStyle $__jobsTerminalStyleState\n",
        "    if ($null -eq $__jobsTerminalCommand -or $__jobsTerminalCommand.Count -eq 0) { throw 'A program is required.' }\n",
        "    $__jobsTerminalProgram = $__jobsTerminalCommand[0]\n",
        "    $__jobsTerminalArguments = @()\n",
        "    if ($__jobsTerminalCommand.Count -gt 1) { $__jobsTerminalArguments = @($__jobsTerminalCommand[1..($__jobsTerminalCommand.Count-1)]) }\n",
        "    $LASTEXITCODE = 0\n",
        "    & $__jobsTerminalProgram @__jobsTerminalArguments\n",
        "    $__jobsTerminalCommandSucceeded = $?\n",
        "    $__jobsTerminalExitCode = $LASTEXITCODE\n",
        "    if (-not $__jobsTerminalCommandSucceeded -and $__jobsTerminalExitCode -eq 0) { $__jobsTerminalExitCode = 1 }\n",
        "} finally {\n",
        "    Stop-JobsTerminalStyle $__jobsTerminalStyleState\n",
        "}\n",
        "exit $__jobsTerminalExitCode\n",
      ].join('');
      jobsFS.writeFileSync(jobsSupervisorPath, jobsWindowsSupervisor, { mode: 0o600, flag: 'wx' });
      jobsCommand = process.env.SystemRoot
        ? jobsPath.join(process.env.SystemRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe')
        : 'powershell.exe';
      jobsCommandArguments = ['-NoProfile', '-File', jobsSupervisorPath, process.execPath, '-e',
        "eval(Buffer.from(process.env.JOBS_TERMINAL_NODE_BRIDGE,'base64').toString())"];
    } else {
      const jobsPOSIXSupervisor = [
        "# 临时保护当前终端配色，业务进程自行管理原有退出清理。\n",
        "jobs_terminal_style_run() {\n",
        "    # 无法可靠保存原色时，沿用脚本已有的纯文本约定。\n",
        "    jobs_terminal_style_plain() {\n",
        "        PLAIN_OUTPUT=1\n",
        "        NO_COLOR=1\n",
        "        FORCE_COLOR=0\n",
        "        CLICOLOR=0\n",
        "        ANSI_COLORS_DISABLED=1\n",
        "        npm_config_color=false\n",
        "        export PLAIN_OUTPUT NO_COLOR FORCE_COLOR CLICOLOR ANSI_COLORS_DISABLED npm_config_color\n",
        "        if \"$@\"; then\n",
        "            jobs_style_exit_status=0\n",
        "        else\n",
        "            jobs_style_exit_status=$?\n",
        "        fi\n",
        "        exit \"$jobs_style_exit_status\"\n",
        "    }\n",
        "    if [ ! -t 0 ] || [ ! -t 1 ] || [ -z \"${TERM:-}\" ] ||\n",
        "       [ \"${TERM:-}\" = dumb ] || [ \"${NO_COLOR+x}\" = x ] ||\n",
        "       [ \"${PLAIN_OUTPUT:-0}\" = 1 ] || [ \"${IS_SOURCETREE_RUNTIME:-0}\" = 1 ] ||\n",
        "       env | LC_ALL=C grep -qiE '^(SOURCETREE|SOURCE_TREE)'; then\n",
        "        if \"$@\"; then\n",
        "            jobs_style_exit_status=0\n",
        "        else\n",
        "            jobs_style_exit_status=$?\n",
        "        fi\n",
        "        exit \"$jobs_style_exit_status\"\n",
        "    fi\n",
        "    if [ -n \"${TMUX:-}${STY:-}\" ]; then\n",
        "        jobs_terminal_style_plain \"$@\"\n",
        "    fi\n",
        "    jobs_style_tty=$(tty 2>/dev/null) || jobs_terminal_style_plain \"$@\"\n",
        "    if ! ps -o pgid= -o tpgid= -p \"$$\" 2>/dev/null |\n",
        "         LC_ALL=C awk 'NF == 2 && $1 == $2 && $1 > 0 { foreground = 1 } END { exit !foreground }'; then\n",
        "        jobs_terminal_style_plain \"$@\"\n",
        "    fi\n",
        "    case ${JOBS_TERMINAL_STYLE_OWNER:-} in\n",
        "        ''|*[!0-9]*) ;;\n",
        "        *)\n",
        "            if [ \"${JOBS_TERMINAL_STYLE_TTY:-}\" = \"$jobs_style_tty\" ] &&\n",
        "               kill -0 \"$JOBS_TERMINAL_STYLE_OWNER\" 2>/dev/null; then\n",
        "                if \"$@\"; then\n",
        "                    jobs_style_exit_status=0\n",
        "                else\n",
        "                    jobs_style_exit_status=$?\n",
        "                fi\n",
        "                exit \"$jobs_style_exit_status\"\n",
        "            fi\n",
        "            ;;\n",
        "    esac\n",
        "    jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_terminal_style_plain \"$@\"\n",
        "    jobs_style_saved=''\n",
        "    jobs_style_saved_rows=''\n",
        "    jobs_style_original_rows=''\n",
        "    jobs_style_applied_rows=''\n",
        "    jobs_style_changed=0\n",
        "    jobs_style_applied_complete=0\n",
        "    jobs_style_query_active=0\n",
        "    jobs_style_recovery=''\n",
        "    jobs_style_exit_status=0\n",
        "    jobs_style_esc=$(printf '\\033')\n",
        "    jobs_style_bel=$(printf '\\007')\n",
        "    # 完整颜色帧有界重发；设置核验与退出恢复容忍帧外回车和明确方向键。\n",
        "    jobs_terminal_style_query() {\n",
        "        jobs_style_query_key=$1\n",
        "        jobs_style_reply=''\n",
        "        jobs_style_query_buffer=''\n",
        "        jobs_style_query_target_reply=''\n",
        "        jobs_style_query_target_normalized=''\n",
        "        jobs_style_query_target_rgb=''\n",
        "        jobs_style_query_st=\"${jobs_style_esc}\\\\\"\n",
        "        jobs_style_query_stale_count=0\n",
        "        jobs_style_query_phase=${2:-strict}\n",
        "        jobs_style_query_cr=$(printf '\\r')\n",
        "        jobs_style_query_lf=$(printf '\\n.')\n",
        "        jobs_style_query_lf=${jobs_style_query_lf%.}\n",
        "        jobs_style_query_failure='未收到目标颜色的完整答复（最多 3 次查询，每次约 2 秒）'\n",
        "        for jobs_style_query_round in 1 2 3; do\n",
        "            printf '\\033]%s;?\\007' \"$jobs_style_query_key\" > /dev/tty || {\n",
        "                jobs_style_query_failure='无法向原终端发送配色查询'\n",
        "                return 1\n",
        "            }\n",
        "            for jobs_style_attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do\n",
        "                # 哨兵保留末尾换行，不能把只有回车的键盘输入误当成无答复。\n",
        "                jobs_style_piece=$(dd bs=256 count=1 2>/dev/null < /dev/tty; printf '.')\n",
        "                jobs_style_piece=${jobs_style_piece%.}\n",
        "                jobs_style_query_buffer=$jobs_style_query_buffer$jobs_style_piece\n",
        "                while [ -n \"$jobs_style_query_buffer\" ]; do\n",
        "                    # 设置核验与退出恢复阶段允许帧外的明确控制键，普通文字仍然失败。\n",
        "                    if [ \"$jobs_style_query_phase\" = cleanup ] || [ \"$jobs_style_query_phase\" = applied ]; then\n",
        "                        jobs_style_query_control_sequence=''\n",
        "                        jobs_style_query_control_partial=0\n",
        "                        case $jobs_style_query_buffer in\n",
        "                            \"$jobs_style_query_cr\"*) jobs_style_query_control_sequence=$jobs_style_query_cr ;;\n",
        "                            \"$jobs_style_query_lf\"*) jobs_style_query_control_sequence=$jobs_style_query_lf ;;\n",
        "                        esac\n",
        "                        if [ -z \"$jobs_style_query_control_sequence\" ]; then\n",
        "                            for jobs_style_query_direction in A B C D; do\n",
        "                                for jobs_style_query_control_candidate in \\\n",
        "                                    \"${jobs_style_esc}[${jobs_style_query_direction}\" \\\n",
        "                                    \"${jobs_style_esc}O${jobs_style_query_direction}\" \\\n",
        "                                    \"${jobs_style_esc}[1;2${jobs_style_query_direction}\" \\\n",
        "                                    \"${jobs_style_esc}[1;3${jobs_style_query_direction}\" \\\n",
        "                                    \"${jobs_style_esc}[1;4${jobs_style_query_direction}\" \\\n",
        "                                    \"${jobs_style_esc}[1;5${jobs_style_query_direction}\" \\\n",
        "                                    \"${jobs_style_esc}[1;6${jobs_style_query_direction}\" \\\n",
        "                                    \"${jobs_style_esc}[1;7${jobs_style_query_direction}\" \\\n",
        "                                    \"${jobs_style_esc}[1;8${jobs_style_query_direction}\"; do\n",
        "                                    case $jobs_style_query_buffer in\n",
        "                                        \"$jobs_style_query_control_candidate\"*)\n",
        "                                            jobs_style_query_control_sequence=$jobs_style_query_control_candidate\n",
        "                                            break 2\n",
        "                                            ;;\n",
        "                                    esac\n",
        "                                    case $jobs_style_query_control_candidate in\n",
        "                                        \"$jobs_style_query_buffer\"*) jobs_style_query_control_partial=1 ;;\n",
        "                                    esac\n",
        "                                done\n",
        "                            done\n",
        "                        fi\n",
        "                        if [ -n \"$jobs_style_query_control_sequence\" ]; then\n",
        "                            jobs_style_phase_control_keys=$(( ${jobs_style_phase_control_keys:-0} + 1 ))\n",
        "                            if [ \"$jobs_style_phase_control_keys\" -gt 64 ]; then\n",
        "                                jobs_style_query_failure='本阶段已识别控制键超过 64 个，已停止自动恢复'\n",
        "                                return 1\n",
        "                            fi\n",
        "                            jobs_style_query_buffer=${jobs_style_query_buffer#\"$jobs_style_query_control_sequence\"}\n",
        "                            continue\n",
        "                        fi\n",
        "                        if [ \"$jobs_style_query_control_partial\" = 1 ]; then\n",
        "                            break\n",
        "                        fi\n",
        "                    fi\n",
        "                    case $jobs_style_query_buffer in\n",
        "                        \"$jobs_style_esc\"|\"$jobs_style_esc]\") break ;;\n",
        "                        \"$jobs_style_esc]\"*) ;;\n",
        "                        *) jobs_style_query_failure='收到非配色查询输入，已停止读取'; return 1 ;;\n",
        "                    esac\n",
        "                    jobs_style_query_head=''\n",
        "                    jobs_style_query_terminator=''\n",
        "                    case $jobs_style_query_buffer in\n",
        "                        *\"$jobs_style_bel\"*)\n",
        "                            jobs_style_query_head=${jobs_style_query_buffer%%\"$jobs_style_bel\"*}\n",
        "                            jobs_style_query_terminator=$jobs_style_bel\n",
        "                            ;;\n",
        "                    esac\n",
        "                    case $jobs_style_query_buffer in\n",
        "                        *\"$jobs_style_query_st\"*)\n",
        "                            jobs_style_query_st_head=${jobs_style_query_buffer%%\"$jobs_style_query_st\"*}\n",
        "                            if [ -z \"$jobs_style_query_terminator\" ] ||\n",
        "                               [ \"${#jobs_style_query_st_head}\" -lt \"${#jobs_style_query_head}\" ]; then\n",
        "                                jobs_style_query_head=$jobs_style_query_st_head\n",
        "                                jobs_style_query_terminator=$jobs_style_query_st\n",
        "                            fi\n",
        "                            ;;\n",
        "                    esac\n",
        "                    [ -n \"$jobs_style_query_terminator\" ] || break\n",
        "                    jobs_style_query_frame=$jobs_style_query_head$jobs_style_query_terminator\n",
        "                    jobs_style_query_buffer=${jobs_style_query_buffer#\"$jobs_style_query_frame\"}\n",
        "                    jobs_style_query_body=${jobs_style_query_head#\"$jobs_style_esc]\"}\n",
        "                    case $jobs_style_query_body in\n",
        "                        *';rgb:'*) ;;\n",
        "                        *) jobs_style_query_failure='配色答复格式或 RGB 数据无效'; return 1 ;;\n",
        "                    esac\n",
        "                    jobs_style_query_frame_key=${jobs_style_query_body%%';rgb:'*}\n",
        "                    case $jobs_style_query_frame_key in\n",
        "                        10|11|12|'4;'[0-9]|'4;1'[0-5]) ;;\n",
        "                        *) jobs_style_query_failure='收到不属于本次颜色协议的答复'; return 1 ;;\n",
        "                    esac\n",
        "                    jobs_style_query_frame_rgb=${jobs_style_query_body#\"$jobs_style_query_frame_key;rgb:\"}\n",
        "                    jobs_style_query_frame_normalized=$(printf '%s\\n' \"$jobs_style_query_frame_rgb\" | LC_ALL=C awk -F/ '\n",
        "                        BEGIN { valid = 1 }\n",
        "                        NR != 1 || NF != 3 { valid = 0; exit }\n",
        "                        {\n",
        "                            for (i = 1; i <= 3; i++) {\n",
        "                                h = tolower($i)\n",
        "                                if (length(h) < 1 || length(h) > 4 || h ~ /[^0-9a-f]/) {\n",
        "                                    valid = 0\n",
        "                                    exit\n",
        "                                }\n",
        "                                n = 0\n",
        "                                for (j = 1; j <= length(h); j++) n = n * 16 + index(\"0123456789abcdef\", substr(h, j, 1)) - 1\n",
        "                                value[i] = int(n * 65535 / (16 ^ length(h) - 1) + 0.5)\n",
        "                            }\n",
        "                        }\n",
        "                        END {\n",
        "                            if (!valid || NR != 1) exit 1\n",
        "                            printf \"%d/%d/%d\", value[1], value[2], value[3]\n",
        "                        }\n",
        "                    ')\n",
        "                    if [ -z \"$jobs_style_query_frame_normalized\" ]; then\n",
        "                        jobs_style_query_failure='配色答复格式或 RGB 数据无效'\n",
        "                        return 1\n",
        "                    fi\n",
        "                    if [ \"$jobs_style_query_frame_key\" = \"$jobs_style_query_key\" ]; then\n",
        "                        if [ -n \"$jobs_style_query_target_reply\" ] &&\n",
        "                           [ \"$jobs_style_query_target_normalized\" != \"$jobs_style_query_frame_normalized\" ]; then\n",
        "                            jobs_style_query_failure='同一颜色的重复答复不一致，已停止自动恢复'\n",
        "                            return 1\n",
        "                        fi\n",
        "                        jobs_style_query_target_reply=$jobs_style_query_frame\n",
        "                        jobs_style_query_target_normalized=$jobs_style_query_frame_normalized\n",
        "                        jobs_style_query_target_rgb=$jobs_style_query_frame_rgb\n",
        "                    else\n",
        "                        jobs_style_query_stale_count=$((jobs_style_query_stale_count + 1))\n",
        "                        if [ \"$jobs_style_query_stale_count\" -gt 128 ]; then\n",
        "                            jobs_style_query_failure='收到过多旧颜色答复，已停止读取'\n",
        "                            return 1\n",
        "                        fi\n",
        "                    fi\n",
        "                done\n",
        "                if [ -n \"$jobs_style_query_target_reply\" ] && [ -z \"$jobs_style_query_buffer\" ]; then\n",
        "                    jobs_style_reply=$jobs_style_query_target_reply\n",
        "                    jobs_style_normalized=$jobs_style_query_target_normalized\n",
        "                    jobs_style_rgb=$jobs_style_query_target_rgb\n",
        "                    return 0\n",
        "                fi\n",
        "            done\n",
        "            # 残缺帧不能通过重发拼成另一个答复，更不能被当成键盘空输入。\n",
        "            if [ -n \"$jobs_style_query_buffer\" ]; then\n",
        "                jobs_style_query_failure='配色答复帧不完整，已停止自动恢复'\n",
        "                return 1\n",
        "            fi\n",
        "        done\n",
        "        return 1\n",
        "    }\n",
        "    # 查询可用不代表终端允许改色，按目标值核对实际生效结果。\n",
        "    jobs_terminal_style_accepts_target() {\n",
        "        jobs_style_requested_hex=''\n",
        "        case $1 in\n",
        "            10|12) jobs_style_requested_hex=ffffff ;;\n",
        "            11) jobs_style_requested_hex=000000 ;;\n",
        "            '4;'*)\n",
        "                jobs_style_requested_index=0\n",
        "                for jobs_style_requested_color in 000000 ff5f56 5fd787 ffd75f 5fafff d787ff 5fd7ff eeeeee 9e9e9e ff8787 87ffaf ffff87 87bfff ffafff afffff ffffff; do\n",
        "                    if [ \"4;$jobs_style_requested_index\" = \"$1\" ]; then\n",
        "                        jobs_style_requested_hex=$jobs_style_requested_color\n",
        "                        break\n",
        "                    fi\n",
        "                    jobs_style_requested_index=$((jobs_style_requested_index + 1))\n",
        "                done\n",
        "                ;;\n",
        "        esac\n",
        "        [ -n \"$jobs_style_requested_hex\" ] || return 1\n",
        "        printf '%s|%s\\n' \"$jobs_style_normalized\" \"$jobs_style_requested_hex\" | LC_ALL=C awk -F'|' '\n",
        "            function hexbyte(h) {\n",
        "                return (index(\"0123456789abcdef\", substr(h, 1, 1)) - 1) * 16 + index(\"0123456789abcdef\", substr(h, 2, 1)) - 1\n",
        "            }\n",
        "            {\n",
        "                if (split($1, actual, \"/\") != 3 || length($2) != 6) exit 1\n",
        "                for (i = 1; i <= 3; i++) {\n",
        "                    difference = actual[i] - hexbyte(substr($2, i * 2 - 1, 2)) * 257\n",
        "                    if (difference < -255 || difference > 255) exit 1\n",
        "                }\n",
        "            }\n",
        "        '\n",
        "    }\n",
        "    # 核验中断时重新读取当前值，只撤回仍等于本轮目标值的颜色。\n",
        "    jobs_terminal_style_rollback() {\n",
        "        jobs_style_rollback_issue='无法读取或设置原终端输入模式'\n",
        "        jobs_style_rollback_safe=''\n",
        "        jobs_style_rollback_conflicts=''\n",
        "        jobs_style_phase_control_keys=0\n",
        "        jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_style_stty=''\n",
        "        if [ -n \"$jobs_style_stty\" ] && stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then\n",
        "            jobs_style_query_active=1\n",
        "            jobs_style_rollback_ok=1\n",
        "            while IFS='|' read -r jobs_style_key jobs_style_original_normalized jobs_style_original; do\n",
        "                [ -n \"$jobs_style_key\" ] || continue\n",
        "                if ! jobs_terminal_style_query \"$jobs_style_key\" cleanup; then\n",
        "                    jobs_style_rollback_ok=0\n",
        "                    jobs_style_rollback_issue=\"回退颜色项 $jobs_style_key：$jobs_style_query_failure\"\n",
        "                    break\n",
        "                fi\n",
        "                if [ \"$jobs_style_normalized\" = \"$jobs_style_original_normalized\" ]; then\n",
        "                    continue\n",
        "                elif jobs_terminal_style_accepts_target \"$jobs_style_key\"; then\n",
        "                    jobs_style_rollback_safe=$jobs_style_rollback_safe$jobs_style_original\n",
        "                else\n",
        "                    jobs_style_rollback_conflicts=\"$jobs_style_rollback_conflicts $jobs_style_key\"\n",
        "                fi\n",
        "            done <<JOBS_STYLE_ROLLBACK\n",
        "$jobs_style_original_rows\n",
        "JOBS_STYLE_ROLLBACK\n",
        "            stty \"$jobs_style_stty\" 2>/dev/null < /dev/tty || { jobs_style_rollback_ok=0; jobs_style_rollback_issue='无法恢复原终端输入模式'; }\n",
        "            jobs_style_query_active=0\n",
        "            if [ \"$jobs_style_rollback_ok\" = 1 ] && printf '%s\\033[0m' \"$jobs_style_rollback_safe\" > /dev/tty; then\n",
        "                if [ -z \"$jobs_style_rollback_conflicts\" ]; then\n",
        "                    rm -f \"$jobs_style_recovery\"\n",
        "                    rmdir \"${jobs_style_recovery%/*}\" 2>/dev/null || :\n",
        "                    return 0\n",
        "                fi\n",
        "                printf '检测到运行期间的配色变更，已保留这些项：%s\\n' \"$jobs_style_rollback_conflicts\" >&2\n",
        "                jobs_style_rollback_issue=\"核验中断后检测到其它配色变更：$jobs_style_rollback_conflicts\"\n",
        "            fi\n",
        "        fi\n",
        "        printf '终端配色未能安全自动恢复（%s）；确认覆盖当前配色后可运行：sh \"%s\"\\n' \"$jobs_style_rollback_issue\" \"$jobs_style_recovery\" >&2\n",
        "        return 1\n",
        "    }\n",
        "    # 检测到后续改色时只恢复仍由本次保护持有的项，保留独立恢复入口。\n",
        "    jobs_terminal_style_cleanup() {\n",
        "        jobs_style_result=$1\n",
        "        trap '' HUP INT TERM\n",
        "        if [ \"$jobs_style_query_active\" = 1 ]; then\n",
        "            stty \"$jobs_style_stty\" 2>/dev/null < /dev/tty || :\n",
        "            jobs_style_query_active=0\n",
        "        fi\n",
        "        if [ \"$jobs_style_changed\" = 1 ] && [ \"$jobs_style_applied_complete\" != 1 ]; then\n",
        "            if jobs_terminal_style_rollback; then\n",
        "                jobs_style_changed=0\n",
        "            else\n",
        "                [ \"$jobs_style_result\" -ne 0 ] || jobs_style_result=1\n",
        "            fi\n",
        "            if [ \"${2:-}\" = continue ]; then\n",
        "                jobs_style_cleanup_status=$jobs_style_result\n",
        "                return 0\n",
        "            fi\n",
        "            exit \"$jobs_style_result\"\n",
        "        fi\n",
        "        if [ \"$jobs_style_changed\" = 1 ]; then\n",
        "            jobs_style_cleanup_ok=0\n",
        "            jobs_style_cleanup_issue='无法读取或设置原终端输入模式，或临时配色未完成核验'\n",
        "            jobs_style_conflicts=''\n",
        "            jobs_style_restore_safe=''\n",
        "            jobs_style_phase_control_keys=0\n",
        "            if [ \"$jobs_style_applied_complete\" = 1 ]; then\n",
        "                jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_style_stty=''\n",
        "                if [ -n \"$jobs_style_stty\" ] && stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then\n",
        "                    jobs_style_query_active=1\n",
        "                    jobs_style_cleanup_ok=1\n",
        "                    while IFS='|' read -r jobs_style_key jobs_style_expected jobs_style_original; do\n",
        "                        [ -n \"$jobs_style_key\" ] || continue\n",
        "                        if ! jobs_terminal_style_query \"$jobs_style_key\" cleanup; then\n",
        "                            jobs_style_cleanup_ok=0\n",
        "                            jobs_style_cleanup_issue=\"颜色项 $jobs_style_key：$jobs_style_query_failure\"\n",
        "                            break\n",
        "                        fi\n",
        "                        if [ \"$jobs_style_normalized\" = \"$jobs_style_expected\" ]; then\n",
        "                            jobs_style_restore_safe=$jobs_style_restore_safe$jobs_style_original\n",
        "                        else\n",
        "                            jobs_style_conflicts=\"$jobs_style_conflicts $jobs_style_key\"\n",
        "                        fi\n",
        "                    done <<JOBS_STYLE_APPLIED\n",
        "$jobs_style_applied_rows\n",
        "JOBS_STYLE_APPLIED\n",
        "                    stty \"$jobs_style_stty\" 2>/dev/null < /dev/tty || { jobs_style_cleanup_ok=0; jobs_style_cleanup_issue='无法恢复原终端输入模式'; }\n",
        "                    jobs_style_query_active=0\n",
        "                fi\n",
        "            fi\n",
        "            if [ \"$jobs_style_cleanup_ok\" = 1 ] && printf '%s\\033[0m' \"$jobs_style_restore_safe\" > /dev/tty; then\n",
        "                if [ -z \"$jobs_style_conflicts\" ]; then\n",
        "                    rm -f \"$jobs_style_recovery\"\n",
        "                    rmdir \"${jobs_style_recovery%/*}\" 2>/dev/null || :\n",
        "                else\n",
        "                    printf '检测到运行期间的配色变更，已保留这些项：%s\\n' \"$jobs_style_conflicts\" >&2\n",
        "                    printf '确认要覆盖后续改色时才使用恢复入口：sh \"%s\"\\n' \"$jobs_style_recovery\" >&2\n",
        "                    [ \"$jobs_style_result\" -ne 0 ] || jobs_style_result=1\n",
        "                fi\n",
        "            else\n",
        "                printf '终端配色未能安全自动恢复（%s）；确认覆盖当前配色后可运行：sh \"%s\"\\n' \"$jobs_style_cleanup_issue\" \"$jobs_style_recovery\" >&2\n",
        "                [ \"$jobs_style_result\" -ne 0 ] || jobs_style_result=1\n",
        "            fi\n",
        "        fi\n",
        "        if [ \"${2:-}\" = continue ]; then\n",
        "            jobs_style_cleanup_status=$jobs_style_result\n",
        "            return 0\n",
        "        fi\n",
        "        exit \"$jobs_style_result\"\n",
        "    }\n",
        "    trap 'jobs_terminal_style_cleanup \"$jobs_style_exit_status\"' 0\n",
        "    trap 'jobs_style_exit_status=129; jobs_terminal_style_cleanup 129 continue; jobs_style_changed=0; exit 129' HUP\n",
        "    trap 'jobs_style_exit_status=130; jobs_terminal_style_cleanup 130 continue; jobs_style_changed=0; exit 130' INT\n",
        "    trap 'jobs_style_exit_status=143; jobs_terminal_style_cleanup 143 continue; jobs_style_changed=0; exit 143' TERM\n",
        "    if ! stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then\n",
        "        jobs_terminal_style_plain \"$@\"\n",
        "    fi\n",
        "    jobs_style_query_active=1\n",
        "    jobs_style_probe_ok=1\n",
        "    for jobs_style_key in 10 11 12 '4;0' '4;1' '4;2' '4;3' '4;4' '4;5' '4;6' '4;7' '4;8' '4;9' '4;10' '4;11' '4;12' '4;13' '4;14' '4;15'; do\n",
        "        if ! jobs_terminal_style_query \"$jobs_style_key\"; then\n",
        "            jobs_style_probe_ok=0\n",
        "            break\n",
        "        fi\n",
        "        jobs_style_saved=$jobs_style_saved$jobs_style_reply\n",
        "        jobs_style_original_rows=\"$jobs_style_original_rows$jobs_style_key|$jobs_style_normalized|$jobs_style_reply\n",
        "\"\n",
        "        jobs_style_saved_rows=\"$jobs_style_saved_rows$jobs_style_key|$jobs_style_reply\n",
        "\"\n",
        "    done\n",
        "    stty \"$jobs_style_stty\" 2>/dev/null < /dev/tty || { jobs_style_exit_status=1; exit 1; }\n",
        "    jobs_style_query_active=0\n",
        "    if [ \"$jobs_style_probe_ok\" != 1 ]; then\n",
        "        printf '%s\\n' '终端不支持完整配色保存，或启动时收到其它输入；保留原配色并使用纯文本。' >&2\n",
        "        jobs_terminal_style_plain \"$@\"\n",
        "    fi\n",
        "    jobs_style_recovery_dir=$(umask 077; mktemp -d \"${TMPDIR:-/tmp}/jobs-terminal-style.XXXXXX\") || jobs_terminal_style_plain \"$@\"\n",
        "    jobs_style_recovery=$jobs_style_recovery_dir/restore.sh\n",
        "    if ! (umask 077; {\n",
        "        printf '#!/bin/sh\\n'\n",
        "        printf '[ -t 0 ] && [ \"$(tty)\" = '\\''%s'\\'' ] || { printf '\\''请在原终端运行恢复入口。\\\\n'\\'' >&2; exit 1; }\\n' \"$jobs_style_tty\"\n",
        "        printf 'printf '\\''本操作会覆盖此终端当前配色。确认恢复脚本启动前的配色，请输入 YES：'\\'' >&2\\n'\n",
        "        printf 'IFS= read -r jobs_restore_choice\\n[ \"$jobs_restore_choice\" = YES ] || exit 1\\n'\n",
        "        printf 'printf '\\''%%s\\\\033[0m'\\'' '\\''%s'\\'' > /dev/tty\\n' \"$jobs_style_saved\"\n",
        "    } > \"$jobs_style_recovery\"); then\n",
        "        printf '%s\\n' '无法保存终端配色恢复入口；保留原配色并使用纯文本。' >&2\n",
        "        jobs_terminal_style_plain \"$@\"\n",
        "    fi\n",
        "    printf '正在准备本次终端临时配色；强退后恢复入口：sh \"%s\"\\n' \"$jobs_style_recovery\" >&2\n",
        "    jobs_style_changed=1\n",
        "    printf '\\033]10;#ffffff\\007\\033]11;#000000\\007\\033]12;#ffffff\\007' > /dev/tty\n",
        "    jobs_style_index=0\n",
        "    for jobs_style_color in 000000 ff5f56 5fd787 ffd75f 5fafff d787ff 5fd7ff eeeeee 9e9e9e ff8787 87ffaf ffff87 87bfff ffafff afffff ffffff; do\n",
        "        printf '\\033]4;%s;#%s\\007' \"$jobs_style_index\" \"$jobs_style_color\" > /dev/tty\n",
        "        jobs_style_index=$((jobs_style_index + 1))\n",
        "    done\n",
        "    printf '\\033[0m' > /dev/tty\n",
        "    jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || { jobs_style_exit_status=1; exit 1; }\n",
        "    stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty || { jobs_style_exit_status=1; exit 1; }\n",
        "    jobs_style_query_active=1\n",
        "    jobs_style_probe_ok=1\n",
        "    jobs_style_targets_ok=1\n",
        "    jobs_style_phase_control_keys=0\n",
        "    while IFS='|' read -r jobs_style_key jobs_style_original; do\n",
        "        [ -n \"$jobs_style_key\" ] || continue\n",
        "        if ! jobs_terminal_style_query \"$jobs_style_key\" applied; then\n",
        "            jobs_style_probe_ok=0\n",
        "            break\n",
        "        fi\n",
        "        jobs_style_applied_rows=\"$jobs_style_applied_rows$jobs_style_key|$jobs_style_normalized|$jobs_style_original\n",
        "\"\n",
        "        if ! jobs_terminal_style_accepts_target \"$jobs_style_key\"; then\n",
        "            jobs_style_targets_ok=0\n",
        "        fi\n",
        "    done <<JOBS_STYLE_ORIGINAL\n",
        "$jobs_style_saved_rows\n",
        "JOBS_STYLE_ORIGINAL\n",
        "    stty \"$jobs_style_stty\" 2>/dev/null < /dev/tty || { jobs_style_exit_status=1; exit 1; }\n",
        "    jobs_style_query_active=0\n",
        "    if [ \"$jobs_style_probe_ok\" != 1 ]; then\n",
        "        printf '临时配色核验失败（颜色项 %s：%s），正在核对原色恢复。\\n' \"$jobs_style_key\" \"$jobs_style_query_failure\" >&2\n",
        "        jobs_terminal_style_cleanup 0 continue\n",
        "        jobs_style_changed=0\n",
        "        if [ \"$jobs_style_cleanup_status\" != 0 ]; then\n",
        "            jobs_style_exit_status=1\n",
        "            exit 1\n",
        "        fi\n",
        "        trap 'jobs_style_exit_status=129; jobs_terminal_style_cleanup 129 continue; jobs_style_changed=0; exit 129' HUP\n",
        "        trap 'jobs_style_exit_status=130; jobs_terminal_style_cleanup 130 continue; jobs_style_changed=0; exit 130' INT\n",
        "        trap 'jobs_style_exit_status=143; jobs_terminal_style_cleanup 143 continue; jobs_style_changed=0; exit 143' TERM\n",
        "        printf '%s\\n' '已恢复原配色并使用纯文本。' >&2\n",
        "        jobs_terminal_style_plain \"$@\"\n",
        "    fi\n",
        "    if [ \"$jobs_style_targets_ok\" != 1 ]; then\n",
        "        jobs_terminal_style_cleanup 0 continue\n",
        "        jobs_style_changed=0\n",
        "        if [ \"$jobs_style_cleanup_status\" != 0 ]; then\n",
        "            jobs_style_exit_status=1\n",
        "            exit 1\n",
        "        fi\n",
        "        trap 'jobs_style_exit_status=129; jobs_terminal_style_cleanup 129 continue; jobs_style_changed=0; exit 129' HUP\n",
        "        trap 'jobs_style_exit_status=130; jobs_terminal_style_cleanup 130 continue; jobs_style_changed=0; exit 130' INT\n",
        "        trap 'jobs_style_exit_status=143; jobs_terminal_style_cleanup 143 continue; jobs_style_changed=0; exit 143' TERM\n",
        "        printf '%s\\n' '终端未接受本次配色，已恢复原配色并使用纯文本。' >&2\n",
        "        jobs_terminal_style_plain \"$@\"\n",
        "    fi\n",
        "    jobs_style_applied_complete=1\n",
        "    printf '%s\\n' '本次终端已临时使用黑底白字。' >&2\n",
        "    JOBS_TERMINAL_STYLE_TTY=$jobs_style_tty\n",
        "    JOBS_TERMINAL_STYLE_OWNER=$$\n",
        "    export JOBS_TERMINAL_STYLE_TTY JOBS_TERMINAL_STYLE_OWNER\n",
        "    if \"$@\"; then\n",
        "        jobs_style_exit_status=0\n",
        "    else\n",
        "        jobs_style_exit_status=$?\n",
        "    fi\n",
        "    exit \"$jobs_style_exit_status\"\n",
        "}\n",
      ].join('');
      jobsCommand = '/bin/sh';
      jobsCommandArguments = ['-c', jobsPOSIXSupervisor + '\njobs_terminal_style_run "$@"\n',
        'jobs-terminal-node', process.execPath, ...jobsArguments];
    }
    // Ctrl+C 同时送达前台进程组；父进程等监督器恢复配色后再结束。
    const jobsInterrupt = () => { jobsInterrupted = true; };
    process.on('SIGINT', jobsInterrupt);
    let jobsOutcome;
    try {
      jobsOutcome = await new Promise(resolve => {
        const jobsChild = jobsSpawn(jobsCommand, jobsCommandArguments, {
          stdio: 'inherit', env: jobsEnvironment, windowsHide: false
        });
        jobsChild.once('spawn', () => { jobsGuardianStarted = true; });
        jobsChild.once('error', error => resolve({ error }));
        jobsChild.once('close', (code, signal) => resolve({ code, signal }));
      });
    } finally {
      process.removeListener('SIGINT', jobsInterrupt);
    }
    if (jobsOutcome.error) throw jobsOutcome.error;
    if (jobsWindowsReceipt && !jobsFS.existsSync(jobsWindowsReceipt)) {
      jobsCleanupTemporary();
      if (jobsInterrupted || jobsOutcome.signal || [129, 130, 143].includes(jobsOutcome.code)) {
        const jobsSignalNumber = jobsOS.constants.signals[jobsOutcome.signal];
        process.exit(jobsInterrupted ? 130 : jobsOutcome.code ?? (jobsSignalNumber ? 128 + jobsSignalNumber : 1));
      }
      process.env.NO_COLOR = '1';
      process.env.PLAIN_OUTPUT = '1';
      console.error('[Jobs] PowerShell 监督器未能启动业务，保留原策略并使用纯文本。');
      return;
    }
    jobsCleanupTemporary();
    const jobsSignalNumber = jobsOS.constants.signals[jobsOutcome.signal];
    process.exit(jobsOutcome.code ?? (jobsSignalNumber ? 128 + jobsSignalNumber : 1));
  } catch (jobsError) {
    jobsCleanupTemporary();
    if (jobsGuardianStarted) {
      console.error(`[Jobs] 终端监督器失败，保留业务执行结果：${jobsError.message}`);
      process.exit(1);
    }
    process.env.NO_COLOR = '1';
    process.env.PLAIN_OUTPUT = '1';
    console.error(`[Jobs] 终端配色保护不可用，使用纯文本：${jobsError.message}`);
  }
}
await jobsTerminalStyleBootstrap(import.meta.url);
// <<< Jobs terminal style protection v1 <<<

export const START = '<!-- jobs-toc:start -->';
export const END = '<!-- jobs-toc:end -->';
const DRIVER = 'jobs-markdown-toc';
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SCRIPT = path.relative(ROOT, fileURLToPath(import.meta.url)).split(path.sep).join('/');
const MANIFEST = '.jobs-markdown-toc/manifest.json';
const HEADING_END = '</span><!-- jobs-toc:heading-end -->';
const KEYS = ['clean', 'smudge', 'required'].map(key => `filter.${DRIVER}.${key}`);

function linesOf(source) {
  return [...source.matchAll(/[^\n]*(?:\n|$)/g)]
    .filter(match => match[0].length)
    .map(match => ({ text: match[0].replace(/\r?\n$/, ''), start: match.index,
      end: match.index + match[0].replace(/\r?\n$/, '').length }));
}

// Only top-level prose is inspected; examples must never become live TOC markers.
function scan(source) {
  const events = [];
  const lines = linesOf(source);
  let fence = null;
  let comment = false;
  let rawTag = null;
  let frontmatter = false;
  let previous = null;
  for (let index = 0; index < lines.length; index++) {
    let line = lines[index];
    let text = line.text;
    if (index === 0 && text.startsWith('\uFEFF')) {
      text = text.slice(1);
      line = { ...line, start: line.start + 1 };
    }
    if (index === 0 && text === '---') {
      frontmatter = true;
      continue;
    }
    if (frontmatter) {
      if (/^(---|\.\.\.)\s*$/.test(text)) frontmatter = false;
      continue;
    }
    if (rawTag) {
      if (new RegExp(`</${rawTag}\\s*>`, 'i').test(text)) rawTag = null;
      continue;
    }
    const fenced = text.match(/^ {0,3}(`{3,}|~{3,})(.*)$/);
    if (fence) {
      if (fenced && fenced[1][0] === fence[0] && fenced[1].length >= fence.length && !fenced[2].trim()) fence = null;
      continue;
    }
    if (fenced && !(fenced[1][0] === '`' && fenced[2].includes('`'))) {
      fence = fenced[1];
      previous = null;
      continue;
    }
    if (/^(?: {4}|\t)/.test(text)) {
      previous = null;
      continue;
    }
    if (!comment && (text === START || text === END || /^ {0,3}\[toc\][ \t]*$/i.test(text))) {
      events.push({ ...line, kind: text === START ? 'start' : text === END ? 'end' : 'toc' });
      previous = null;
      continue;
    }
    const raw = text.match(/^ {0,3}<(pre|script|style|textarea)(?:\s|>)/i);
    if (raw && !comment) {
      if (!new RegExp(`</${raw[1]}\\s*>`, 'i').test(text)) rawTag = raw[1];
      previous = null;
      continue;
    }
    // Strip comments before looking for headings, including multi-line comments.
    let visible = '';
    while (text.length) {
      if (comment) {
        const close = text.indexOf('-->');
        if (close < 0) break;
        text = text.slice(close + 3);
        comment = false;
      } else {
        const open = text.indexOf('<!--');
        visible += open < 0 ? text : text.slice(0, open);
        if (open < 0) break;
        text = text.slice(open + 4);
        comment = true;
      }
    }
    const heading = visible.match(/^ {0,3}(#{1,6})(?:[ \t]+(.*)|[ \t]*)$/);
    if (heading) {
      events.push({ ...line, kind: 'heading', level: heading[1].length,
        raw: (heading[2] ?? '').replace(/[ \t]+#+[ \t]*$/, '').trim() });
      previous = null;
    } else if (previous && /^ {0,3}(=+|-+)[ \t]*$/.test(visible)) {
      events.push({ ...previous, kind: 'heading', level: visible.trim()[0] === '=' ? 1 : 2, raw: previous.raw });
      previous = null;
    } else {
      previous = visible.trim() && !/^ {0,3}(?:>|[-+*] |\d+[.)] )/.test(visible) &&
        (!/^ {0,3}</.test(visible) || /^ {0,3}<(?:span|a|strong|b|font)\b/.test(visible))
        ? { ...line, raw: visible.trim() } : null;
    }
  }
  return events;
}

function sourceForm(source) {
  const events = scan(source);
  const markers = events.filter(event => event.kind === 'start' || event.kind === 'end');
  if (!markers.length) return source;
  if (markers.length % 2 || markers.some((marker, index) => marker.kind !== (index % 2 ? 'end' : 'start'))) {
    throw new Error('目录标记不完整或重复；请保留成对的 jobs-toc:start / jobs-toc:end。');
  }
  const edits = [];
  let version2 = false;
  for (let index = 0; index < markers.length; index += 2) {
    let body = source.slice(markers[index].end, markers[index + 1].start).trim();
    let token = '[toc]';
    const metadata = body.match(/^<!-- jobs-toc:source (.+) -->\r?\n/);
    if (metadata) {
      const value = JSON.parse(metadata[1]);
      if (value.v !== 2 || !/^ {0,3}\[toc\][ \t]*$/i.test(value.token)) throw new Error('目录源标记无效。');
      token = value.token;
      body = body.slice(metadata[0].length);
      version2 = true;
    }
    if (!body.startsWith('<details>') || !body.endsWith('</details>')) throw new Error('生成目录块结构异常，已停止转换。');
    edits.push({ start: markers[index].start, end: markers[index + 1].end, text: token });
  }
  if (version2) {
    for (const heading of events.filter(event => event.kind === 'heading')) {
      const line = source.slice(heading.start, heading.end);
      const open = line.match(/<span id="jobs-toc-heading-\d+" data-jobs-toc="v2">/g) ?? [];
      const close = line.split(HEADING_END).length - 1;
      if (!open.length && !close) continue;
      if (open.length !== 1 || close !== 1) throw new Error('自动标题锚点不完整，已停止恢复。');
      edits.push({ start: heading.start, end: heading.end, text: line.replace(open[0], '').replace(HEADING_END, '') });
    }
  }
  return applyEdits(source, edits);
}

function applyEdits(source, edits) {
  for (const edit of edits.sort((a, b) => b.start - a.start)) source = source.slice(0, edit.start) + edit.text + source.slice(edit.end);
  return source;
}

function stripLinks(value) {
  // A link label can itself contain brackets, as in CDN[-] / GitHub[+].
  let result = '';
  for (let index = 0; index < value.length;) {
    const image = value[index] === '!' && value[index + 1] === '[';
    const start = index + (image ? 1 : 0);
    if (value[start] !== '[') { result += value[index++]; continue; }
    let depth = 1;
    let end = start + 1;
    for (; end < value.length && depth; end++) {
      if (value[end] === '\\') { end++; continue; }
      if (value[end] === '[') depth++;
      if (value[end] === ']') depth--;
    }
    if (depth || !['(', '['].includes(value[end])) { result += value[index++]; continue; }
    const opener = value[end];
    const closer = opener === '(' ? ')' : ']';
    let tail = end + 1;
    depth = 1;
    for (; tail < value.length && depth; tail++) {
      if (value[tail] === '\\') { tail++; continue; }
      if (value[tail] === opener) depth++;
      if (value[tail] === closer) depth--;
    }
    if (depth) { result += value[index++]; continue; }
    result += stripLinks(value.slice(start + 1, end - 1));
    index = tail;
  }
  return result;
}

function decodeEntities(value) {
  const entities = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: '\u00a0', copy: '©', reg: '®' };
  return value.replace(/&(#x[\da-f]+|#\d+|[a-z]+);/gi, (all, name) => {
    if (name[0] !== '#') return entities[name.toLowerCase()] ?? all;
    const code = name[1].toLowerCase() === 'x' ? parseInt(name.slice(2), 16) : Number(name.slice(1));
    return code > 0 && code <= 0x10ffff && !(code >= 0xd800 && code <= 0xdfff) ? String.fromCodePoint(code) : '\uFFFD';
  });
}

function inlineText(raw) {
  const protectedText = [];
  const protect = text => `\uE000${protectedText.push(text) - 1}\uE001`;
  return decodeEntities(stripLinks(raw
    .replace(/\\([!"#$%&'()*+,\-./:;<=>?@[\]\\^_`{|}~])/g, (_, text) => protect(text))
    .replace(/(`+)([\s\S]*?)\1/g, (_, ticks, text) => protect(text.replace(/\s+/g, ' ')))
    .replace(/<(https?:\/\/[^<>\s]+)>/g, '$1')
    .replace(/<[^>]*>/g, ''))
    .replace(/(\*\*|__|~~)(?=\S)([\s\S]*?\S)\1/g, '$2')
    .replace(/(?<![\p{L}\p{N}])([*_])(?=\S)(.*?\S)\1(?![\p{L}\p{N}])/gu, '$2')
    .replace(/\uE000(\d+)\uE001/g, (_, index) => protectedText[Number(index)])).trim();
}

function headingEntries(source) {
  const headings = scan(source).filter(event => event.kind === 'heading' && event.level >= 2);
  const explicit = headings.map(heading => [...heading.raw.matchAll(/<(span|a|strong|b)\b[^>]*\s(?:id|name)=(?:"([^"]+)"|'([^']+)'|([^\s>]+))[^>]*>([\s\S]*?)<\/\1>/gi)]
    .find(match => inlineText(match[5]).length));
  const ids = explicit.map(match => match ? decodeEntities(match[2] ?? match[3] ?? match[4]) : null);
  const documentIds = [...source.matchAll(/<[a-z][^>]*\s(?:id|name)=(?:"([^"]+)"|'([^']+)'|([^\s>]+))/gi)]
    .map(match => decodeEntities(match[1] ?? match[2] ?? match[3]));
  const edits = [];
  const entries = headings.map((heading, index) => {
    const raw = heading.raw.replace(/<a\b[^>]*href=["']#(?:前言|🔚)["'][^>]*>\s*(?:<b>)?\s*[🔼🔽]\s*(?:<\/b>)?\s*<\/a>/gu, '').trim();
    const title = inlineText(raw);
    let target = ids[index];
    if (!title) return null;
    if (!target || documentIds.filter(id => id === target).length !== 1) {
      target = `jobs-toc-heading-${index + 1}`;
      if (source.includes(`id="${target}"`) || source.includes(`id='${target}'`)) throw new Error(`保留锚点名称冲突：${target}`);
      const line = source.slice(heading.start, heading.end);
      const prefix = line.match(/^ {0,3}#{1,6}(?:[ \t]+|$)/)?.[0] ?? line.match(/^ {0,3}/)[0];
      const closing = /^ {0,3}#{1,6}/.test(line) ? line.match(/[ \t]+#+[ \t]*$/)?.[0] ?? '' : '';
      const end = line.length - closing.length;
      edits.push({ start: heading.start, end: heading.end, text: line.slice(0, prefix.length) +
        `<span id="${target}" data-jobs-toc="v2">` + line.slice(prefix.length, end) + HEADING_END + line.slice(end) });
    }
    return { level: heading.level, title, target };
  }).filter(Boolean);
  return { entries, edits };
}

export function smudgeMarkdown(source) {
  return sourceForm(source);
}

export function cleanMarkdown(source) {
  const local = sourceForm(source);
  const tokens = scan(local).filter(event => event.kind === 'toc');
  if (!tokens.length) return local;
  const eol = local.includes('\r\n') ? '\r\n' : '\n';
  const { entries, edits } = headingEntries(local);
  const stack = [];
  const links = entries.map(entry => {
    while (stack.length && stack.at(-1) >= entry.level) stack.pop();
    const indent = '  '.repeat(stack.length);
    stack.push(entry.level);
    const label = entry.title.replace(/([\\[\]`*_<>])/g, '\\$1');
    return `${indent}- [${label}](#${encodeURIComponent(entry.target)})`;
  });
  for (const token of tokens) {
    const original = local.slice(token.start, token.end);
    const block = [START, `<!-- jobs-toc:source ${JSON.stringify({ v: 2, token: original })} -->`, '<details>', '<summary>📚 目录（点击展开 / 收起）</summary>', '',
      ...(links.length ? links : ['暂无章节。']), '', '</details>', END].join(eol);
    edits.push({ start: token.start, end: token.end, text: block });
  }
  return applyEdits(local, edits);
}

export function inspectMarkdown(source) {
  const events = scan(sourceForm(source));
  return { tocCount: events.filter(event => event.kind === 'toc').length, headingCount: events.filter(event => event.kind === 'heading' && event.level >= 2).length };
}

export function checkMarkdown(source) {
  return scan(source).some(event => event.kind === 'start') && cleanMarkdown(source) === source;
}

function git(args, options = {}) {
  return execFileSync('git', args, { cwd: ROOT, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, stdio: ['pipe', 'pipe', 'pipe'], ...options });
}

function decode(bytes) {
  return new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes);
}

export function sameDirectory(left, right) {
  // Git and Node can spell the same Windows path with different casing.
  const first = fs.statSync(left, { bigint: true });
  const second = fs.statSync(right, { bigint: true });
  return first.isDirectory() && second.isDirectory() && first.dev === second.dev && first.ino === second.ino;
}

function managedFiles() {
  const file = path.join(ROOT, MANIFEST);
  if (!fs.existsSync(file) && SCRIPT === 'Scripts/MarkdownToc.mjs') return ['README.md'];
  const manifest = JSON.parse(decode(fs.readFileSync(file)));
  if (manifest.version !== 1 || !Array.isArray(manifest.files) || !manifest.files.length) throw new Error('目录清单缺失或无效。');
  const files = manifest.files;
  if (new Set(files).size !== files.length || files.some(value => typeof value !== 'string' ||
    path.posix.isAbsolute(value) || value.includes('\\') || value.split('/').some(part => !part || part === '.' || part === '..') || !/\.md$/i.test(value))) {
    throw new Error('目录清单路径重复、越界或不是 .md 文档。');
  }
  return files;
}

function readDocument(relative) {
  const pieces = relative.split('/');
  let current = ROOT;
  for (const piece of pieces) {
    current = path.join(current, piece);
    if (fs.lstatSync(current).isSymbolicLink()) throw new Error(`跳过符号链接：${relative}`);
  }
  const nearest = execFileSync('git', ['-C', path.dirname(current), 'rev-parse', '--show-toplevel'], { encoding: 'utf8' }).trim();
  if (!sameDirectory(nearest, ROOT)) throw new Error(`清单越过独立 Git 边界：${relative}`);
  return decode(fs.readFileSync(current));
}

function replaceDocuments(updates, touchUnchanged = false) {
  const written = [];
  try {
    for (const update of updates) {
      if (update.before === update.after && !touchUnchanged) continue;
      const file = path.join(ROOT, update.file);
      if (decode(fs.readFileSync(file)) !== update.before) throw new Error(`文档被并发修改：${update.file}`);
      const stat = fs.statSync(file);
      if (update.before === update.after) {
        // Installing a driver does not invalidate Git's stat cache by itself.
        // Touch only registered documents so the next ordinary add runs clean.
        fs.utimesSync(file, stat.atime, new Date(Math.max(Date.now(), stat.mtimeMs + 1)));
      } else fs.writeFileSync(file, update.after);
      written.push({ ...update, stat });
    }
  } catch (error) {
    for (const update of written.reverse()) {
      const file = path.join(ROOT, update.file);
      if (decode(fs.readFileSync(file)) === update.after) {
        if (update.before !== update.after) fs.writeFileSync(file, update.before);
        fs.utimesSync(file, update.stat.atime, update.stat.mtime);
      }
    }
    throw error;
  }
}

function requireRepository() {
  if (['GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR'].some(key => process.env[key])) {
    throw new Error('管理命令不接受 GIT_DIR / GIT_WORK_TREE / GIT_COMMON_DIR 定位覆盖；请在目标仓库正常环境运行。');
  }
  if (!sameDirectory(git(['rev-parse', '--show-toplevel']).trim(), ROOT)) {
    throw new Error('安装器必须位于目标仓库的 Scripts 目录，不能改写父仓配置。');
  }
}

function localValues(key) {
  const result = spawnSync('git', ['config', '--local', '--null', '--get-all', key], { cwd: ROOT, encoding: 'utf8' });
  if (result.status === 1) return [];
  if (result.status !== 0) throw new Error(result.stderr || '无法读取 Git 配置。');
  return result.stdout.split('\0').slice(0, -1);
}

function replaceLocal(key, values) {
  const result = spawnSync('git', ['config', '--local', '--unset-all', key], { cwd: ROOT, encoding: 'utf8' });
  if (result.status !== 0 && result.status !== 5) throw new Error(result.stderr || '无法移除 Git 配置。');
  for (const value of values) git(['config', '--local', '--add', key, value]);
}

function shellQuote(value) {
  return "'" + value.replaceAll("'", "'\\''") + "'";
}

function expectedConfiguration() {
  const node = shellQuote(process.execPath.replaceAll('\\', '/'));
  return { [KEYS[0]]: [`${node} ${shellQuote(SCRIPT)} clean`],
    [KEYS[1]]: [`${node} ${shellQuote(SCRIPT)} smudge`], [KEYS[2]]: ['true'] };
}

function statePath() {
  return path.resolve(ROOT, git(['rev-parse', '--git-path', 'jobs-markdown-toc.json']).trim());
}

function install() {
  requireRepository();
  const files = managedFiles();
  const attributes = git(['check-attr', '-z', '--stdin', 'filter'], { input: files.join('\0') + '\0' }).split('\0');
  for (let index = 0; index < files.length; index++) {
    if (attributes[index * 3 + 2] !== DRIVER) throw new Error(`有效 .gitattributes 未注册此过滤器：${files[index]}`);
  }
  const current = Object.fromEntries(KEYS.map(key => [key, localValues(key)]));
  const stateFile = statePath();
  const state = fs.existsSync(stateFile) ? JSON.parse(fs.readFileSync(stateFile, 'utf8')) : null;
  const processFilter = spawnSync('git', ['config', '--get', `filter.${DRIVER}.process`], { cwd: ROOT, encoding: 'utf8' });
  if (processFilter.status !== 1) throw new Error('发现同名 process 过滤器或配置读取失败，停止安装，避免绕过 clean / smudge。');
  const effective = spawnSync('git', ['config', '--get-regexp', `^filter\\.${DRIVER}\\.`], { cwd: ROOT, encoding: 'utf8' });
  if (!state && effective.status !== 1) throw new Error('存在同名过滤器配置或读取失败，保留原配置并停止安装。');
  if (state && (state.version !== 1 || JSON.stringify(current) !== JSON.stringify(state.installed))) {
    throw new Error('过滤器配置已被其他操作改动，保留现场并停止安装。');
  }
  const updates = files.map(file => {
    const before = readDocument(file);
    const after = smudgeMarkdown(before);
    if (!checkMarkdown(cleanMarkdown(after))) throw new Error(`文档没有有效 [toc]，未安装过滤器：${file}`);
    return { file, before, after };
  });
  const installed = expectedConfiguration();
  const next = { version: 1, previous: state?.previous ?? current, installed };
  // Keep the recovery record before touching config; only this driver's keys are changed.
  fs.writeFileSync(stateFile, JSON.stringify(next, null, 2) + '\n', { mode: 0o600 });
  try {
    for (const key of KEYS) replaceLocal(key, installed[key]);
    replaceDocuments(updates, true);
  } catch (error) {
    for (const key of KEYS) replaceLocal(key, current[key]);
    if (state) fs.writeFileSync(stateFile, JSON.stringify(state, null, 2) + '\n');
    else fs.unlinkSync(stateFile);
    throw error;
  }
  console.log(`已启用本仓 ${files.length} 份文档的过滤器：本地 [toc] → 暂存时生成折叠目录。未暂存、提交或推送。`);
}

function uninstall() {
  requireRepository();
  const file = statePath();
  if (!fs.existsSync(file)) throw new Error('没有本工具的安装记录，未修改任何配置。');
  const state = JSON.parse(fs.readFileSync(file, 'utf8'));
  const current = Object.fromEntries(KEYS.map(key => [key, localValues(key)]));
  if (state.version !== 1 || JSON.stringify(current) !== JSON.stringify(state.installed)) {
    throw new Error('过滤器配置已变化，停止卸载，避免覆盖其他操作。');
  }
  const updates = managedFiles().map(file => {
    const before = readDocument(file);
    return { file, before, after: cleanMarkdown(before) };
  });
  try {
    for (const key of KEYS) replaceLocal(key, state.previous[key]);
    replaceDocuments(updates);
  } catch (error) {
    for (const key of KEYS) replaceLocal(key, current[key]);
    throw error;
  }
  fs.unlinkSync(file);
  console.log('已恢复本工具安装前的本仓配置，清单文档保留折叠目录；后续需自行重新生成。未修改暂存区。');
}

function main(args) {
  const [mode, ...extra] = args;
  if (extra.length && (mode !== 'preview' || extra.length !== 1)) throw new Error('不支持额外参数；使用 help 查看入口。');
  if (mode === 'clean' || mode === 'smudge') {
    const bytes = fs.readFileSync(0);
    const source = decode(bytes);
    process.stdout.write(mode === 'clean' ? cleanMarkdown(source) : smudgeMarkdown(source));
  } else if (mode === 'install') {
    install();
  } else if (mode === 'uninstall') {
    uninstall();
  } else if (mode === 'check') {
    requireRepository();
    const errors = [];
    const files = managedFiles();
    for (const file of files) {
      try {
        if (!checkMarkdown(decode(git(['show', `:${file}`], { encoding: 'buffer' })))) errors.push(file);
      } catch (error) { errors.push(`${file}（未暂存、已删除或格式错误）`); }
    }
    if (errors.length) throw new Error(`暂存区目录缺失或过期；请整文件暂存对应文档：\n${errors.join('\n')}`);
    console.log(`暂存区 ${files.length} 份文档的目录与其正文一致。`);
  } else if (mode === 'verify') {
    requireRepository();
    const files = managedFiles();
    for (const file of files) {
      const source = readDocument(file);
      const generated = cleanMarkdown(source);
      if (!inspectMarkdown(source).tocCount || smudgeMarkdown(generated) !== smudgeMarkdown(source) || cleanMarkdown(generated) !== generated) {
        throw new Error(`文档转换往返验证失败：${file}`);
      }
    }
    console.log(`工作区 ${files.length} 份文档转换往返与幂等验证通过；未修改文件或暂存区。`);
  } else if (mode === 'status') {
    requireRepository();
    for (const key of KEYS) console.log(`${key} = ${localValues(key).join(', ') || '(未配置)'}`);
    console.log(`受控文档：${managedFiles().length} 份；清单：${MANIFEST}`);
  } else if (mode === 'preview') {
    const files = managedFiles();
    const file = extra[0] ?? (files.includes('README.md') ? 'README.md' : files[0]);
    if (!files.includes(file)) throw new Error('preview 只能读取已登记的相对文档路径。');
    process.stdout.write(cleanMarkdown(readDocument(file)));
  } else if (!mode || mode === 'help') {
    console.log(`用法：node ${SCRIPT} install | status | uninstall | check | verify | preview [相对文档路径]\nclean / smudge 仅供 Git 从标准输入调用；check 读取原始暂存区，verify 只读核对工作区，preview 不写文件。`);
  } else {
    throw new Error(`未知模式：${mode}`);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { main(process.argv.slice(2)); }
  catch (error) {
    console.error(`MarkdownToc：${error.message}`);
    process.exitCode = 1;
  }
}

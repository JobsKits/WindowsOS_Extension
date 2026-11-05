# SdkDownloadOutput.ps1 | SDK 初始化与下载的实时输出捕获。
# Created by Jobs on 2026年11月4日，星期三.
# 随独立业务包分发；展示原生命令输出，同时保留机器响应供原解析器使用。
function Invoke-JobsSdkLiveProcess {
    param([Diagnostics.ProcessStartInfo]$Start, [int]$TimeoutSeconds = 120, [switch]$Sanitize, [switch]$Acquisition)
    $route = $null
    if ($Acquisition) { Import-JobsSdkDownloadRoute; $route = Initialize-JobsSdkProcessNetworkRoute $Start }
    if (-not ('Jobs.SdkDownloadProcess' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
namespace Jobs {
    public sealed class SdkDownloadProcess : IDisposable {
        readonly Process process = new Process();
        readonly object gate = new object();
        readonly StringBuilder stdout = new StringBuilder(), stderr = new StringBuilder();
        readonly ManualResetEvent outDone = new ManualResetEvent(false), errDone = new ManualResetEvent(false);
        readonly bool sanitize;
        readonly string logFile;
        long lastOutput = DateTime.UtcNow.Ticks;
        public string OutputFailure { get; private set; }
        public SdkDownloadProcess(ProcessStartInfo start, bool safeOutput) : this(start, safeOutput, null) {}
        public SdkDownloadProcess(ProcessStartInfo start, bool safeOutput, string log) {
            sanitize = safeOutput; logFile = log;
            start.UseShellExecute = false; start.CreateNoWindow = true;
            start.RedirectStandardOutput = true; start.RedirectStandardError = true;
            process.StartInfo = start;
        }
        static string Safe(string text) {
            text = Regex.Replace(text, @"(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@", "$1***@");
            text = Regex.Replace(text, @"(?i)(https?://[^\s?#]+)[?#][^\s]*", "$1?[已省略]");
            text = Regex.Replace(text, @"(?im)(authorization\s*[:=]\s*)[^\r\n]+", "$1[已省略]");
            return Regex.Replace(text, @"(?im)((?:access[_-]?token|authorization|password|secret)\s*[:=]\s*)\S+", "$1[已省略]");
        }
        void Display(string text, bool error, StringBuilder pending) {
            TextWriter writer = error ? Console.Error : Console.Out;
            if (!sanitize) { writer.Write(text); return; }
            foreach (char value in text) {
                if (value == '\r' || value == '\n') {
                    writer.Write(Safe(pending.ToString())); writer.Write(value); pending.Length = 0;
                } else { pending.Append(value); }
            }
        }
        void Audit(string text, StringBuilder pending) {
            if (String.IsNullOrEmpty(logFile)) return;
            foreach (char value in text) {
                if (value == '\r' || value == '\n') {
                    File.AppendAllText(logFile, Safe(pending.ToString()) + value, new UTF8Encoding(false)); pending.Length = 0;
                } else { pending.Append(value); }
            }
        }
        void Pump(Stream stream, bool error) {
            try {
                StringBuilder pending = new StringBuilder(), auditPending = new StringBuilder();
                byte[] bytes = new byte[4096]; Encoding encoding = new UTF8Encoding(false);
                char[] chars = new char[encoding.GetMaxCharCount(bytes.Length)];
                Decoder decoder = encoding.GetDecoder(); int count;
                while ((count = stream.Read(bytes, 0, bytes.Length)) > 0) {
                    int length = decoder.GetChars(bytes, 0, count, chars, 0, false);
                    string text = new string(chars, 0, length);
                    lock (gate) {
                        (error ? stderr : stdout).Append(text);
                        Interlocked.Exchange(ref lastOutput, DateTime.UtcNow.Ticks);
                        Audit(text, auditPending);
                        Display(text, error, pending);
                    }
                }
                int remaining = decoder.GetChars(bytes, 0, 0, chars, 0, true);
                if (remaining > 0) {
                    string tail = new string(chars, 0, remaining);
                    lock (gate) { (error ? stderr : stdout).Append(tail); Display(tail, error, pending); }
                }
                if (sanitize && pending.Length > 0) { lock (gate) { (error ? Console.Error : Console.Out).Write(Safe(pending.ToString())); } }
                if (!String.IsNullOrEmpty(logFile) && auditPending.Length > 0) { lock (gate) { File.AppendAllText(logFile, Safe(auditPending.ToString()), new UTF8Encoding(false)); } }
            } catch (Exception exception) { OutputFailure = exception.Message; }
            finally { (error ? errDone : outDone).Set(); }
        }
        public void Start() {
            if (!process.Start()) throw new InvalidOperationException("Unable to start SDK tool");
            Thread output = new Thread(delegate() { Pump(process.StandardOutput.BaseStream, false); });
            Thread errors = new Thread(delegate() { Pump(process.StandardError.BaseStream, true); });
            output.IsBackground = true; errors.IsBackground = true; output.Start(); errors.Start();
        }
        public double IdleSeconds { get { return TimeSpan.FromTicks(DateTime.UtcNow.Ticks - Interlocked.Read(ref lastOutput)).TotalSeconds; } }
        public int Id { get { return process.Id; } }
        public bool HasExited { get { return process.HasExited; } }
        public int ExitCode { get { return process.ExitCode; } }
        public string StdOut { get { lock (gate) return stdout.ToString(); } }
        public string StdErr { get { lock (gate) return stderr.ToString(); } }
        public bool Drain(int milliseconds) {
            Stopwatch clock = Stopwatch.StartNew();
            if (!outDone.WaitOne(milliseconds)) return false;
            return errDone.WaitOne(Math.Max(0, milliseconds - (int)clock.ElapsedMilliseconds));
        }
        public void Dispose() { process.Dispose(); }
    }
}


'@
    }
    $logFile = if ($Acquisition) { Get-JobsSdkRetryLog } else { $null }
    $runner = New-Object Jobs.SdkDownloadProcess($Start, [bool]$Sanitize, $logFile)
    $begun = $false
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        $runner.Start()
        $begun = $true
        while (-not $runner.HasExited) {
            if (($Acquisition -and $runner.IdleSeconds -ge $TimeoutSeconds) -or (-not $Acquisition -and $watch.Elapsed.TotalSeconds -ge $TimeoutSeconds)) { throw 'SDK 工具超时，已请求停止本次进程树。' }
            Start-Sleep -Milliseconds 30
        }
        if (-not $runner.Drain(5000)) { throw 'SDK 工具输出管道未及时关闭。' }
        if ($runner.OutputFailure) { throw ('SDK 工具输出读取失败：' + $runner.OutputFailure) }
        $result = [pscustomobject]@{ ExitCode = $runner.ExitCode; StdOut = $runner.StdOut; StdErr = $runner.StdErr }
        if ($route -and $null -ne $route.PSObject.Properties['AutoSource']) { Add-Member -InputObject $result -NotePropertyName SdkRouteAutoSource -NotePropertyValue $route.AutoSource }
        if ($route -and ($result.ExitCode -ne 0 -or ($result.StdOut + $result.StdErr) -match '(?i)Failed to download|Error downloading|IO exception while downloading|Unable to download')) { Reject-JobsSdkRoute $route }
        return $result
    }
    catch { if ($route) { Reject-JobsSdkRoute $route }; throw }
    finally {
        if ($begun -and -not $runner.HasExited) {
            if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
                & (Join-Path ([Environment]::GetFolderPath('System')) 'taskkill.exe') /PID $runner.Id /T /F 2>&1 | Out-Null
            } else { [Diagnostics.Process]::GetProcessById($runner.Id).Kill() }
        }
        $runner.Dispose()
    }
}

# 无 curl 的终端也显示真实字节、速度与总量；不依赖宿主的进度条偏好。
function Receive-JobsSdkWebFileAttempt {
    param([string]$Uri, [string]$Destination, [int]$TimeoutSeconds = 300)
    $request = [Net.WebRequest]::Create($Uri)
    $request.Timeout = $TimeoutSeconds * 1000
    $request.ReadWriteTimeout = [Math]::Min(30000, $TimeoutSeconds * 1000)
    $request.UserAgent = 'JobsFlutterTools'
    $offset = [long]0
    $resumeFile = $Destination + '.resume.json'
    if ([IO.File]::Exists($Destination) -and [IO.File]::Exists($resumeFile)) {
        $resume = [IO.File]::ReadAllText($resumeFile) | ConvertFrom-Json
        if ($resume.Uri -ceq $Uri -and $resume.Validator) {
            $offset = (Get-Item -LiteralPath $Destination).Length
            if ($offset -gt 0) { $request.AddRange($offset); $request.Headers['If-Range'] = $resume.Validator }
        }
    }
    $response = $null; $input = $null; $output = $null
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $lastDisplay = -1.0; $received = [long]0
    try {
        Write-Host '下载进度：正在连接；已接收 0 字节。'
        $response = $request.GetResponse()
        $input = $response.GetResponseStream()
        $append = $offset -gt 0 -and [int]$response.StatusCode -eq 206
        if ($append -and $response.Headers['Content-Range'] -notmatch ('^bytes ' + $offset + '-')) { throw '响应续传位置不匹配。' }
        if (-not $append) { $offset = [long]0 }
        $validator = if ($response.Headers['ETag']) { $response.Headers['ETag'] } else { $response.Headers['Last-Modified'] }
        [IO.File]::WriteAllText($resumeFile, (@{Uri=$Uri;Validator=$validator}|ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
        $mode = if ($append) { [IO.FileMode]::Append } else { [IO.FileMode]::Create }
        $output = [IO.File]::Open($Destination, $mode, [IO.FileAccess]::Write)
        $buffer = New-Object byte[] 65536
        while (($count = $input.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $output.Write($buffer, 0, $count)
            $received += $count
            if ($watch.Elapsed.TotalSeconds - $lastDisplay -ge 1) {
                $speed = $received / [Math]::Max(0.001, $watch.Elapsed.TotalSeconds)
                $total = if ($response.ContentLength -gt 0) { ('{0}/{1} 字节（{2:P0}）' -f ($offset + $received), ($offset + $response.ContentLength), (($offset + $received) / [double]($offset + $response.ContentLength))) } else { ('{0} 字节（总量未知）' -f $received) }
                Write-Host ('下载进度：{0}；{1:N0} 字节/秒' -f $total, $speed)
                $lastDisplay = $watch.Elapsed.TotalSeconds
            }
        }
        $output.Flush()
        if ($response.ContentLength -ge 0 -and $received -ne $response.ContentLength) { throw 'SDK 下载字节数与响应总量不一致。' }
        Write-Host ('下载完成：{0} 字节；耗时 {1:N1} 秒。' -f ($offset + $received), $watch.Elapsed.TotalSeconds)
    }
    finally {
        if ($null -ne $output) { $output.Dispose() }
        if ($null -ne $input) { $input.Dispose() }
        if ($null -ne $response) { $response.Close() }
        $request.Abort()
    }
}

# 只包 SDK/工具链获取；业务构建、许可和配置写入不进入这个循环。
function Get-JobsSdkRetryLog {
    if (-not (Get-Variable JobsSdkRetryLog -Scope Script -ErrorAction SilentlyContinue)) {
        $script:JobsSdkRetryLog = Join-Path ([IO.Path]::GetTempPath()) ('JobsSdkAcquisition-' + $PID + '.log')
    }
    return $script:JobsSdkRetryLog
}
function Write-JobsSdkRetryMessage {
    param([string]$Message)
    $safe = $Message -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@'
    $safe = $safe -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]'
    $safe = $safe -replace '(?im)(authorization\s*[:=]\s*)[^\r\n]+', '$1[已省略]'
    $safe = $safe -replace '(?im)((?:access[_-]?token|password|secret)\s*[:=]\s*)\S+', '$1[已省略]'
    Write-Host $safe
    [IO.File]::AppendAllText((Get-JobsSdkRetryLog), $safe + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
}
function Invoke-JobsSdkAcquire {
    param([Parameter(Mandatory=$true)][scriptblock]$Operation, [string]$Label = 'SDK 环境', [ValidateRange(0,30)][int]$InitialDelaySeconds = 2)
    $attempt = [long]0
    while ($true) {
        $attempt++
        Write-JobsSdkRetryMessage ('准备 {0}；第 {1} 次；失败自动重试，Ctrl+C/停止结束；日志：{2}' -f $Label,$attempt,(Get-JobsSdkRetryLog))
        try {
            $result = & $Operation
            $detail = ''
            if ($null -ne $result) { foreach ($field in @('StdOut','StdErr')) { if ($null -ne $result.PSObject.Properties[$field]) { $detail += [string]$result.$field } } }
            if ($detail -match '(?i)Failed to find package|version.+(not found|does not exist)|licenses?.*(not accepted|not been accepted)') { throw ('SDK 前置条件无效：' + $detail) }
            if ($null -ne $result -and $null -ne $result.PSObject.Properties['ExitCode'] -and $result.ExitCode -eq 0 -and $detail -match '(?i)Failed to download|Could not (GET|HEAD|download)|IO exception while downloading|Error downloading|Unable to (download|resolve)|Failed to fetch|transfer closed|unexpected end of (file|archive)') { $failure=New-Object InvalidOperationException ('SDK 网络获取未完成：'+$detail);if($result.PSObject.Properties['SdkRouteAutoSource']){$failure.Data['JobsSdkAutoSource']=$result.SdkRouteAutoSource};throw $failure }
            if ($null -ne $result -and $null -ne $result.PSObject.Properties['ExitCode'] -and $result.ExitCode -ne 0) {
                if ($result.ExitCode -in @(129,130,137,143,-1073741510)) { throw (New-Object System.Management.Automation.PipelineStoppedException) }
                $detail = ''
                foreach ($field in @('StdOut','StdErr')) { if ($null -ne $result.PSObject.Properties[$field]) { $detail += [string]$result.$field } }
                $failure=New-Object InvalidOperationException ('SDK 获取失败，退出码 {0}：{1}' -f $result.ExitCode,$detail);if($result.PSObject.Properties['SdkRouteAutoSource']){$failure.Data['JobsSdkAutoSource']=$result.SdkRouteAutoSource};throw $failure
            }
            Write-JobsSdkRetryMessage ('{0} 获取成功；共 {1} 次。' -f $Label,$attempt)
            return $result
        }
        catch [System.Management.Automation.PipelineStoppedException] { throw }
        catch [System.OperationCanceledException] { throw }
        catch {
            $failure = $_.Exception
            $autoSource = [bool]$failure.Data['JobsSdkAutoSource']
            while ($null -ne $failure.InnerException) { $failure = $failure.InnerException }
            if ($failure -is [OperationCanceledException] -or $failure -is [Management.Automation.PipelineStoppedException]) { throw $failure }
            $classification = if ($autoSource) { $failure.Message -replace '404','upstream-unavailable' } else { $failure.Message }
            # 调用方的取消、路径/权限/磁盘/认证错误需要修正，不能伪装成传输故障。
            if ($failure -is [UnauthorizedAccessException] -or $failure -is [IO.DirectoryNotFoundException] -or
                $failure -is [Management.Automation.CommandNotFoundException] -or $failure -is [UriFormatException] -or $failure -is [ComponentModel.Win32Exception] -or
                $classification -match '(?i)FVM 缓存上下文无效|已取消|取消选择|(?:user|operation).*(?:cancelled|canceled)|UAC.*(?:denied|拒绝)|需要重启|requires? (?:a )?re(?:start|boot)|reboot required|restart required|Failed to find package|\(404\)|\b404\s+Not\s*Found|cannot find the (file|path)|找不到指定的(文件|路径)|No such file or directory|access denied|permission denied|no space left|disk.+full|unauthorized|forbidden|authentication failed|syntax error|invalid (argument|option)|unknown option|not recognized|不是内部或外部命令|许可证未接受|licenses?.*(not accepted|not been accepted)|(?:HTTP|status|状态码|response).{0,20}404|version.+(not found|does not exist)|repository.+not found|already exists|路径冲突') { throw }
            $delay = [int][Math]::Min(30, $InitialDelaySeconds * [Math]::Pow(2,[Math]::Min(5,$attempt - 1)))
            Write-JobsSdkRetryMessage ('{0} 第 {1} 次失败：{2}；{3} 秒后自动重试，Ctrl+C/停止结束。' -f $Label,$attempt,$failure.Message,$delay)
            if ($delay -gt 0) { Start-Sleep -Seconds $delay }
        }
    }
}
function Invoke-JobsSdkAcquireProcess {
    param([Diagnostics.ProcessStartInfo]$Start, [int]$TimeoutSeconds = 120, [switch]$Sanitize, [string]$Label = 'SDK 组件')
    return Invoke-JobsSdkAcquire -Label $Label -Operation {
        Invoke-JobsSdkLiveProcess $Start $TimeoutSeconds -Sanitize:$Sanitize -Acquisition
    }
}
function Receive-JobsSdkWebFile {
    param([string]$Uri, [string]$Destination, [int]$TimeoutSeconds = 300, [switch]$SingleAttempt, [string]$ExpectedSha256 = '', [Collections.IDictionary]$EnvironmentOverride)
    if ($ExpectedSha256 -and $ExpectedSha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'SDK 可信 SHA-256 格式无效。' }
    $operation = {
        Import-JobsSdkDownloadRoute
        $environment = if ($null -ne $EnvironmentOverride) { $EnvironmentOverride } else { Get-JobsSdkRouteEnvironment }
        $route = Get-JobsFlutterSdkRoute $Uri ('制品 '+([Uri]$Uri).AbsolutePath) $environment -ExpectedSha256 $ExpectedSha256
        if (-not $route.Ready) { throw 'SDK网络预检未得到已验证路线，保留配置并退避重测。' }
        try {
            if ($route.Verified) { Receive-JobsSdkRoutedFile $route $Destination $TimeoutSeconds $environment }
            else { Receive-JobsSdkWebFileAttempt $Uri $Destination $TimeoutSeconds }
            if ($ExpectedSha256 -and (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash -ine $ExpectedSha256) {
                $rejected = $Destination + '.invalid-' + [guid]::NewGuid().ToString('N')
                Move-Item -LiteralPath $Destination -Destination $rejected
                throw ('SDK 下载 SHA-256 不匹配，坏包保留后重新获取：' + $rejected)
            }
        } catch { Reject-JobsSdkRoute $route; throw }
    }
    if ($SingleAttempt) { & $operation; return }
    [void](Invoke-JobsSdkAcquire -Label ('SDK 文件：' + $Uri) -Operation $operation)
}

function ConvertFrom-JobsSdkMachineOutput {
    param([string]$Output)
    for ($index=0; $index -lt $Output.Length; $index++) {
        if ($Output[$index] -cne '{') { continue }
        try { $value = $Output.Substring($index).Trim() | ConvertFrom-Json -ErrorAction Stop }
        catch { continue }
        if ($null -ne $value -and $null -ne $value.PSObject.Properties['frameworkVersion']) { return $value }
    }
    throw 'Flutter --version --machine 没有返回有效版本 JSON。'
}

function Import-JobsSdkDownloadRoute {
    if (-not (Get-Command Get-JobsFlutterSdkRoute -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'SdkDownloadRoute.ps1/SdkDownloadRoute.ps1')
    }
}

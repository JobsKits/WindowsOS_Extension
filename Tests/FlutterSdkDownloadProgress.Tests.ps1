# FlutterSdkDownloadProgress.Tests.ps1 | SDK 实时进度隔离回归。
# Created by Jobs on 2026年11月4日，星期三.
# 使用假工具与回环 HTTP，不下载真实 SDK、不接触账户缓存或系统菜单。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$helper = Join-Path $root 'JobsFlutterTools/Scripts/SdkDownloadOutput.ps1'
. $helper
$engine = Join-Path $PSHOME $(if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { if ($PSVersionTable.PSVersion.Major -le 5) { 'powershell.exe' } else { 'pwsh.exe' } } else { 'pwsh' })
function New-ProgressStart([string]$Script, [string]$Mode) {
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $engine
    $start.Arguments = '-NoLogo -NoProfile -File "' + $Script + '" ' + $Mode
    $start.WorkingDirectory = Split-Path -Parent $Script
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        $native = Join-Path $start.WorkingDirectory 'fake.sh'
        $body = @'
echo $$ > pid
case "$1" in
  hang) exec /bin/sleep 60;;
  fail) printf 'failed-with-37' >&2; exit 37;;
  secret) printf 'https://user:password@example.invalid/pkg?token=query-secret\rauthorization: Bearer header-secret\naccess_token=body-secret' >&2; exit 0;;
  utf8) printf '\360\237\230'; /bin/sleep 0.2; printf '\200'; i=0; while [ "$i" -lt 4095 ]; do printf A; i=$((i+1)); done; exit 0;;
esac
printf '\r下载 25%%' >&2
while [ ! -f release ]; do /bin/sleep 0.05; done
printf yes > finished
printf '\r下载 100%%' >&2
printf '{"frameworkVersion":"3.47.2"}'
'@
        [IO.File]::WriteAllText($native, $body.Replace("`r`n", "`n"), (New-Object Text.UTF8Encoding($false)))
        $start.FileName = '/bin/sh'
        $start.Arguments = '"' + $native + '" ' + $Mode
    }
    return $start
}
$script:assertions = 0
function Assert-Progress([bool]$Condition, [string]$Message) {
    $script:assertions++
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
}
$Temporary = Join-Path ([IO.Path]::GetTempPath()) ('JobsSdkProgress-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($Temporary)
try {
    $fake = Join-Path $Temporary 'fake.ps1'
    $fakeBody = @'
param([string]$Mode)
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'pid'), [string]$PID)
if ($Mode -eq 'hang') { Start-Sleep -Seconds 60; exit 0 }
if ($Mode -eq 'fail') { [Console]::Error.Write('failed-with-37'); exit 37 }
if ($Mode -eq 'secret') { [Console]::Error.Write("https://user:password@example.invalid/pkg?token=query-secret`rauthorization: Bearer header-secret`naccess_token=body-secret"); exit 0 }
if ($Mode -eq 'utf8') {
    $stream = [Console]::OpenStandardOutput()
    $first = [byte[]]@(240,159,152)
    $stream.Write($first,0,$first.Length); $stream.Flush()
    Start-Sleep -Milliseconds 200
    $second = New-Object byte[] 4096
    $second[0] = 128
    for ($i=1;$i -lt $second.Length;$i++) { $second[$i] = 65 }
    $stream.Write($second,0,$second.Length); $stream.Flush()
    exit 0
}
[Console]::Error.Write("`r下载 25%")
for ($i=0; $i -lt 600 -and -not [IO.File]::Exists((Join-Path $PSScriptRoot 'release')); $i++) { Start-Sleep -Milliseconds 100 }
if (-not [IO.File]::Exists((Join-Path $PSScriptRoot 'release'))) { exit 9 }
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'finished'), 'yes')
[Console]::Error.Write("`r下载 100%")
[Console]::Write('{"frameworkVersion":"3.47.2"}')
'@
    [IO.File]::WriteAllText($fake, $fakeBody, (New-Object Text.UTF8Encoding($true)))
    Add-Type -TypeDefinition @'
using System;
using System.IO;
public sealed class JobsSdkProgressWriter : StringWriter {
    readonly string directory;
    public bool ObservedBeforeFinish { get; private set; }
    public JobsSdkProgressWriter(string path) { directory = path; }
    public override void Write(string value) {
        base.Write(value);
        if (ToString().Contains("下载 25%") && !File.Exists(Path.Combine(directory, "finished"))) {
            ObservedBeforeFinish = true;
            File.WriteAllText(Path.Combine(directory, "release"), "yes");
        }
    }
}
'@
    $originalOut = [Console]::Out
    $originalError = [Console]::Error
    $progressDisplay = New-Object JobsSdkProgressWriter($Temporary)
    $jsonDisplay = New-Object IO.StringWriter
    try {
        [Console]::SetError($progressDisplay)
        [Console]::SetOut($jsonDisplay)
        $result = Invoke-JobsSdkLiveProcess (New-ProgressStart $fake 'progress') 90
    } finally { [Console]::SetError($originalError); [Console]::SetOut($originalOut) }
    Assert-Progress ($progressDisplay.ToString().Contains("`r下载 25%")) 'CR 与无换行进度实时显示'
    Assert-Progress $progressDisplay.ObservedBeforeFinish '工具未结束、未换行时已经看到下载进度'
    Assert-Progress ($result.ExitCode -eq 0) '实时泵运行成功'
    Assert-Progress ($jsonDisplay.ToString() -ceq '{"frameworkVersion":"3.47.2"}') '显示JSON不混入额外文字'
    Assert-Progress ($result.StdOut -ceq '{"frameworkVersion":"3.47.2"}') '机器 JSON 返回值不混入展示文字'
    Assert-Progress ($result.StdErr -ceq "`r下载 25%`r下载 100%") '原生 CR 与两档进度完整捕获'
    $failed = Invoke-JobsSdkLiveProcess (New-ProgressStart $fake 'fail') 45
    Assert-Progress ($failed.ExitCode -eq 37 -and $failed.StdErr -ceq 'failed-with-37') '非零退出码及错误输出保留'
    $originalOut = [Console]::Out
    $unicodeDisplay = New-Object IO.StringWriter
    try { [Console]::SetOut($unicodeDisplay); $unicode = Invoke-JobsSdkLiveProcess (New-ProgressStart $fake 'utf8') 45 } finally { [Console]::SetOut($originalOut) }
    Assert-Progress ($unicode.StdOut -ceq ([char]::ConvertFromUtf32(128512) + ('A' * 4095))) '四字节 UTF8 跨块后接完整4096字节不丢失/溢出'
    $originalError = [Console]::Error
    $secretDisplay = New-Object IO.StringWriter
    try { [Console]::SetError($secretDisplay); $secret = Invoke-JobsSdkLiveProcess (New-ProgressStart $fake 'secret') 45 -Sanitize } finally { [Console]::SetError($originalError) }
    Assert-Progress ($secretDisplay.ToString() -notmatch 'password|query-secret|header-secret|body-secret') 'PubGet展示保留URL/认证字段脱敏'
    Assert-Progress ($secret.StdErr.Contains('header-secret')) '脱敏展示不改内部原始响应'
    Remove-Item -LiteralPath (Join-Path $Temporary 'pid')
    $blocked = $false
    try { [void](Invoke-JobsSdkLiveProcess (New-ProgressStart $fake 'hang') 10) } catch { $blocked = $_.Exception.Message.Contains('超时') }
    Assert-Progress $blocked '下载超时明确失败'
    $toolId = [int][IO.File]::ReadAllText((Join-Path $Temporary 'pid'))
    $gone = $false
    for ($i=0;$i -lt 40;$i++) {
        try { $process = [Diagnostics.Process]::GetProcessById($toolId); $gone = $process.HasExited; $process.Dispose() } catch { $gone = $true }
        if ($gone) { break }; Start-Sleep -Milliseconds 25
    }
    Assert-Progress $gone '超时停止本次工具，不留下假下载进程'

    # 回环响应分两段，确保未知宿主进度条偏好不会把下载静默化。
    Add-Type -TypeDefinition @'
using System;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
public sealed class JobsSdkLocalServer : IDisposable {
    readonly TcpListener listener = new TcpListener(IPAddress.Loopback, 0);
    public int Port { get { return ((IPEndPoint)listener.LocalEndpoint).Port; } }
    public JobsSdkLocalServer() {
        listener.Start();
        Thread thread = new Thread(delegate() {
            using (TcpClient client = listener.AcceptTcpClient()) using (NetworkStream stream = client.GetStream()) {
                byte[] request = new byte[4096]; stream.Read(request, 0, request.Length);
                byte[] header = Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nContent-Length: 65536\r\nConnection: close\r\n\r\n");
                stream.Write(header, 0, header.Length);
                byte[] body = new byte[65536]; for(int i=0;i<body.Length;i++) body[i] = 90;
                stream.Write(body, 0, 32768); stream.Flush(); Thread.Sleep(1100);
                stream.Write(body, 32768, 32768); stream.Flush();
            }
        }); thread.IsBackground = true; thread.Start();
    }
    public void Dispose() { listener.Stop(); }
}
'@
    $server = New-Object JobsSdkLocalServer
    $ProgressPreference = 'SilentlyContinue'
    try {
        $download = Join-Path $Temporary 'download.bin'
        $display = @(Receive-JobsSdkWebFile ('http://127.0.0.1:' + $server.Port + '/fixture') $download 10 6>&1 | ForEach-Object { [string]$_ }) -join "`n"
        $intermediate = @([regex]::Matches($display, '下载进度：([0-9]+)/65536') | Where-Object { [long]$_.Groups[1].Value -gt 0 -and [long]$_.Groups[1].Value -lt 65536 })
        Assert-Progress ($intermediate.Count -gt 0 -and $display.Contains('下载完成：65536')) '无curl路径显示实际中间字节与完成总量'
        Assert-Progress ([IO.File]::ReadAllText($download, [Text.Encoding]::ASCII) -ceq ('Z' * 65536) -and (Get-Item -LiteralPath $download).Length -eq 65536) '回环下载字节保持完整'
    } finally { $server.Dispose() }

    $copies = @('JobsFlutterSdkInspector/Scripts','JobsFlutterTools/Scripts/Actions/sdk-version/Scripts','JobsFlutterVersionMgr/Scripts','JobsFlutterRunner/Scripts','JobsFlutterPubGet/Scripts','JobsFlutterPackager/Scripts','JobsFlutterTools/Scripts/Actions/sdk-manage/Scripts','JobsFlutterTools/Scripts/Actions/run/Scripts','JobsFlutterTools/Scripts/Actions/pub-get/Scripts','JobsFlutterTools/Scripts/Actions/package/Scripts')
    $hash = (Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash
    foreach ($copy in $copies) { Assert-Progress ((Get-FileHash -LiteralPath (Join-Path $root ($copy + '/SdkDownloadOutput.ps1')) -Algorithm SHA256).Hash -ceq $hash) ('独立副本一致：' + $copy) }
    Write-Host ('PASS: FlutterSdkDownloadProgress.Tests.ps1 (' + $script:assertions + ' assertions)')
} finally {
    if ([IO.Directory]::Exists($Temporary)) { Remove-Item -LiteralPath $Temporary -Recurse -Force }
}

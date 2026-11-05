# SDK 获取隔离回归：假命令；不安装环境、不注册菜单。
param([switch]$CancelProbe,[string]$ProbePath)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $root 'JobsFlutterTools/Scripts/SdkDownloadOutput.ps1')
if ($CancelProbe) {
    [void](Invoke-JobsSdkAcquire -Operation {
        [IO.File]::AppendAllText($ProbePath,"attempt`n")
        [pscustomobject]@{ExitCode=130;StdOut='';StdErr=''}
    })
    [IO.File]::AppendAllText($ProbePath,"resumed`n")
    exit 1
}
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('JobsSdkRetry-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$script:JobsSdkRetryLog=Join-Path $temporary 'retry.log'
$script:assertions=0
function Assert-Retry([bool]$ok,[string]$message) { $script:assertions++; if(-not $ok){throw $message} }
try {
    $script:tries=0;$script:delays=@()
    function Start-Sleep {param([int]$Seconds,[int]$Milliseconds) if($PSBoundParameters.ContainsKey('Seconds')){$script:delays+= $Seconds}else{Microsoft.PowerShell.Utility\Start-Sleep -Milliseconds $Milliseconds}}
    $result=Invoke-JobsSdkAcquire -Label '12次前置失败夹具' -Operation {
        $script:tries++
        if($script:tries -le 12){return [pscustomobject]@{ExitCode=28;StdOut='';StdErr='connection reset'}}
        [pscustomobject]@{ExitCode=0;StdOut='{"frameworkVersion":"fixture"}';StdErr=''}
    }
    Assert-Retry ($script:tries -eq 13 -and $result.StdOut -ceq '{"frameworkVersion":"fixture"}') '不得设置重试次数上限，成功响应保持纯JSON'
    Assert-Retry ($script:delays.Count -eq 12 -and ($script:delays|Measure-Object -Maximum).Maximum -eq 30) '退避间隔封顶30秒'
    $log=[IO.File]::ReadAllText($script:JobsSdkRetryLog)
    Assert-Retry ($log.Contains('第 1 次失败') -and $log.Contains('第 12 次失败') -and $log.Contains('共 13 次')) '每次失败与成功追加同一日志'
    $script:tries=0;$blocked=$false
    try { [void](Invoke-JobsSdkAcquire -Operation {$script:tries++;throw (New-Object UnauthorizedAccessException('access denied'))}) } catch {$blocked=$_.Exception.Message -match 'access denied'}
    Assert-Retry ($blocked -and $script:tries -eq 1) '权限故障保留诊断，不伪装成网络重试'
    $script:tries=0
    [void](Invoke-JobsSdkAcquire -Operation {
        $script:tries++
        [pscustomobject]@{ExitCode=0;StdOut='';StdErr=$(if($script:tries -lt 3){'Failed to download any source lists'}else{''})}
    })
    Assert-Retry ($script:tries -eq 3) '原生工具退出0但明确下载失败时不能误报成功'
    $script:tries=0;$blocked=$false
    try {[void](Invoke-JobsSdkAcquire -Operation {$script:tries++;throw (New-Object OperationCanceledException('fixture cancellation'))})}catch [OperationCanceledException]{$blocked=$true}
    Assert-Retry ($blocked -and $script:tries -eq 1) 'Task/Operation cancellation不被重试'
    $probe=Join-Path $temporary 'cancelled'
    $engine=Join-Path $PSHOME $(if([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT){if($PSVersionTable.PSVersion.Major -le 5){'powershell.exe'}else{'pwsh.exe'}}else{'pwsh'})
    & $engine -NoLogo -NoProfile -File $PSCommandPath -CancelProbe -ProbePath $probe | Out-Null
    Assert-Retry ([IO.File]::ReadAllText($probe) -ceq "attempt`n") '原生130为取消，不能重新开始或执行下游'
    Remove-Item Function:Start-Sleep
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){
        $tool=Join-Path $temporary 'fake.sh'
        $body=@'
for i in 1 2 3 4 5 6; do printf 'progress\r' >&2; /bin/sleep 0.25; done
printf '{"sdk":"ready"}'
'@
        [IO.File]::WriteAllText($tool,$body.Replace("`r`n","`n"), (New-Object Text.UTF8Encoding($false)))
        $start=New-Object Diagnostics.ProcessStartInfo;$start.FileName='/bin/sh';$start.Arguments='"'+$tool+'"';$start.WorkingDirectory=$temporary
        $actual=Invoke-JobsSdkAcquireProcess $start 1 -Label '持续进度夹具'
        Assert-Retry ($actual.ExitCode -eq 0 -and $actual.StdOut -ceq '{"sdk":"ready"}') '有进度超过当次超时仍保持传输'
    }
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
public sealed class JobsResumeFixture : IDisposable {
    readonly TcpListener listener = new TcpListener(IPAddress.Loopback, 0);
    public bool SawRange { get; private set; }
    public int Port { get { return ((IPEndPoint)listener.LocalEndpoint).Port; } }
    public JobsResumeFixture() : this(false) {}
    public JobsResumeFixture(bool corrupt) {
        listener.Start();
        Thread thread = new Thread(delegate() {
            for (int attempt = 0; attempt < 2; attempt++) {
                using (TcpClient client = listener.AcceptTcpClient()) using (NetworkStream stream = client.GetStream()) {
                    StreamReader reader = new StreamReader(stream, Encoding.ASCII, false, 4096, true);
                    string headers = "", line;
                    while (!String.IsNullOrEmpty(line = reader.ReadLine())) headers += line + "\n";
                    bool range = headers.Contains("Range: bytes=32768-") && headers.Contains("If-Range: \"fixture\"");
                    SawRange = SawRange || range;
                    string header = attempt == 0 ? "HTTP/1.1 200 OK\r\nContent-Length: 65536\r\n" : "HTTP/1.1 206 Partial Content\r\nContent-Length: 32768\r\nContent-Range: bytes 32768-65535/65536\r\n";
                    if(corrupt) header = "HTTP/1.1 200 OK\r\nContent-Length: 65536\r\n";
                    byte[] bytes = Encoding.ASCII.GetBytes(header + "ETag: \"fixture\"\r\nConnection: close\r\n\r\n");
                    stream.Write(bytes, 0, bytes.Length);
                    bytes = new byte[corrupt ? 65536 : 32768]; for(int i=0; i<bytes.Length; i++) bytes[i] = (byte)((corrupt && attempt == 0) ? 65 : 90);
                    stream.Write(bytes, 0, bytes.Length); stream.Flush();
                }
            }
        }); thread.IsBackground = true; thread.Start();
    }
    public void Dispose() { listener.Stop(); }
}
'@
    $server=New-Object JobsResumeFixture
    try {
        $archive=Join-Path $temporary 'sdk.zip'
        Receive-JobsSdkWebFile ('http://127.0.0.1:'+$server.Port+'/fixture') $archive 5
        Assert-Retry ($server.SawRange -and (Get-Item -LiteralPath $archive).Length -eq 65536) '断流后自动重试并带If-Range续传保留的字节'
        Assert-Retry ([IO.File]::ReadAllText($archive) -ceq ('Z'*65536)) '续传内容完整，不混入重复字节'
    }finally{$server.Dispose()}
    $server=New-Object JobsResumeFixture($true)
    try {
        $archive=Join-Path $temporary 'checksum-sdk.zip'
        $expectedFile=Join-Path $temporary 'expected'
        [IO.File]::WriteAllText($expectedFile,('Z'*65536),(New-Object Text.UTF8Encoding($false)))
        $expected=(Get-FileHash -LiteralPath $expectedFile -Algorithm SHA256).Hash
        Receive-JobsSdkWebFile ('http://127.0.0.1:'+$server.Port+'/fixture') $archive 5 -ExpectedSha256 $expected
        Assert-Retry ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ceq $expected) '完整下载却摘要失败时自动重取，正确后才成功'
        Assert-Retry (@(Get-ChildItem -LiteralPath $temporary -Filter 'checksum-sdk.zip.invalid-*').Count -eq 1) '坏包独立保留，不污染续传缓存'
    }finally{$server.Dispose()}
    # 官方 Windows SDK 安装命令幂等重试，退出0仍须检查真实组件。
    . (Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetupToolchains.ps1')
    $savedProgramFiles=${env:ProgramFiles(x86)}
    ${env:ProgramFiles(x86)}=$temporary
    $installer=Join-Path $temporary 'Microsoft Visual Studio/Installer/setup.exe'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $installer))
    [IO.File]::WriteAllText($installer,'fake installer; never executed')
    $script:installCalls=0;$script:readyCalls=0;$script:installMode='retry'
    function Set-JobsSetupProgress {param($Node,$State,$Message)}
    function Write-JobsSetupMessage {param($Message)}
    function Invoke-JobsSetupProcessOnce {
        param($File,$Arguments,$Directory,$TimeoutSeconds,[switch]$SdkAcquisitionAttempt,[switch]$AllowInstallerExitCodes)
        $script:installCalls++
        Assert-Retry ($SdkAcquisitionAttempt -and $AllowInstallerExitCodes -and $Arguments -contains 'Microsoft.VisualStudio.Component.Windows11SDK.26100') 'SDK安装使用可取消的获取内核，精确保留WindowsSDK组件'
        $code=if($script:installMode -eq 'cancel'){1223}elseif($script:installMode -eq 'reboot'){3010}elseif($script:installCalls -eq 1){28}else{0}
        [pscustomobject]@{ExitCode=$code;StdOut='';StdErr=$(if($code-eq28){'connection reset'}else{''})}
    }
    function Get-JobsSetupWindowsDesktopTools {
        param($Project)
        $script:readyCalls++
        [pscustomobject]@{Ready=($script:readyCalls -ge 2);Issues=@('missing Windows SDK files')}
    }
    function Import-Module {param($Name,[switch]$PassThru,[switch]$DisableNameChecking) New-Module -ScriptBlock {function Update-JobsFvmSessionPath {}}}
    function Start-Sleep {param([int]$Seconds)}
    $tools=[pscustomobject]@{Path='fixture VS instance';Component='Microsoft.VisualStudio.Component.VC.Tools.x86.x64'}
    try {
        Install-JobsSetupWindowsDesktopTools $temporary $tools
        Assert-Retry ($script:installCalls -eq 3 -and $script:readyCalls -eq 2) 'WindowsSDK下载失败和退出0未就绪均持续获取，准备成功才停止'
        $script:installCalls=0;$script:installMode='cancel';$blocked=$false
        try{Install-JobsSetupWindowsDesktopTools $temporary $tools}catch [OperationCanceledException]{$blocked=$true}
        Assert-Retry ($blocked -and $script:installCalls -eq 1) '本人拒绝UAC/取消安装后不再拉取'
        $script:installCalls=0;$script:installMode='reboot';$blocked=$false
        try{Install-JobsSetupWindowsDesktopTools $temporary $tools}catch{$blocked=$_.Exception.Message -match '需要重启'}
        Assert-Retry ($blocked -and $script:installCalls -eq 1) '重启要求单独报告，不自动重启、不重复安装'
    }finally{
        ${env:ProgramFiles(x86)}=$savedProgramFiles
        Remove-Item Function:Start-Sleep,Function:Import-Module
    }
    $fvm=Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/Actions/sdk-manage/Scripts/Action.psm1') -PassThru -DisableNameChecking
    try {
        $count=& $fvm {
            param($Temporary)
            $script:FixtureSdkRoot=$Temporary;$script:FixtureInstalls=0
            function script:Start-Sleep {param($Seconds)}
            function script:Invoke-JobsFvmToolOnce {
                param($File,$Arguments,$Directory,$TimeoutSeconds,[switch]$LiveCapture,[switch]$Acquisition)
                if($Arguments -contains '--help'){return [pscustomobject]@{ExitCode=0;StdOut='--[no-]setup (defaults to on)';StdErr=''}}
                if($Arguments[0] -ceq 'api'){return [pscustomobject]@{ExitCode=0;StdOut=(@{context=@{versionsCachePath=(Join-Path $script:FixtureSdkRoot 'versions')}}|ConvertTo-Json -Depth 4);StdErr=''}}
                $script:FixtureInstalls++
                if($script:FixtureInstalls -eq 2){$bin=Join-Path $script:FixtureSdkRoot 'versions/3.38.4/bin';[void][IO.Directory]::CreateDirectory($bin);[IO.File]::WriteAllText((Join-Path $bin 'flutter.bat'),'fake SDK payload')}
                [pscustomobject]@{ExitCode=0;StdOut='';StdErr=''}
            }
            [void](Invoke-JobsFvmTool 'fake-fvm' @('install','3.38.4','--skip-pub-get') $Temporary)
            $script:FixtureInstalls
        } $temporary
        Assert-Retry ($count -eq 2) 'FVM退出0但bin/flutter缺失仍持续获取，就绪后才继续绑定'
    }finally{Remove-Module $fvm}
    $machine=ConvertFrom-JobsSdkMachineOutput "Building {fixture}`n{`"frameworkVersion`":`"3.38.4`"}"
    Assert-Retry ($machine.frameworkVersion -ceq '3.38.4') 'SDK自举杂散输出不污染末尾机器版本响应'
    $hash=(Get-FileHash -LiteralPath (Join-Path $root 'JobsFlutterTools/Scripts/SdkDownloadOutput.ps1') -Algorithm SHA256).Hash
    foreach($copy in @(Get-ChildItem -LiteralPath $root -Filter SdkDownloadOutput.ps1 -Recurse -File)) {
        Assert-Retry ((Get-FileHash -LiteralPath $copy.FullName -Algorithm SHA256).Hash -ceq $hash) ('helper副本一致：'+$copy.FullName)
    }
    foreach($relative in @('JobsFlutterDoctor/Scripts/Action.psm1','JobsFlutterCodegen/Scripts/Action.psm1','JobsFlutterRunner/Scripts/Action.psm1','JobsFlutterTools/Scripts/ProjectSetup.psm1')){
        $text=[IO.File]::ReadAllText((Join-Path $root $relative))
        Assert-Retry ($text.Contains('Invoke-JobsSdkAcquire')) ('获取入口已接入：'+$relative)
    }
    Write-Host ('PASS: SdkAcquisitionRetry.Tests.ps1 ('+$script:assertions+' assertions)')
}finally{Remove-Item -LiteralPath $temporary -Recurse -Force}

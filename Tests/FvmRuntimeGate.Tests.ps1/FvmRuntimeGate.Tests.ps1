# 文本FVM必须先准备其实际PATH Dart；全部SDK进程与网络均为假件。
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $root 'JobsFlutterTools/Scripts/SdkDownloadRoute.ps1/SdkDownloadRoute.ps1')
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('JobsFvmRuntimeGate-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$script:checks=0;$script:acquired=0;$script:cancel=$false;$script:metadataStarted=$false
function Assert-Gate([bool]$Ok,[string]$Text){$script:checks++;if(-not$Ok){throw $Text}}
function script:Write-JobsSdkRouteMessage {param($Text)}
function script:Invoke-JobsSdkAcquireProcess {
    param($Start,$TimeoutSeconds,[switch]$Sanitize,$Label)
    $script:acquired++;$script:manager=$Start.EnvironmentVariables['JOBS_SDK_ROUTE_TOOL']
    if($script:cancel){throw (New-Object OperationCanceledException('fixture cancel before FVM metadata'))}
    [IO.File]::WriteAllText((Join-Path $script:sdk 'bin/cache/dart-sdk/bin/dart.exe'),'ready')
    [IO.File]::WriteAllText((Join-Path $script:sdk 'bin/cache/engine-dart-sdk.stamp'),('a'*40))
    [Console]::Write('{"bootstrap":"private"}')
    return [pscustomobject]@{ExitCode=0;StdOut='';StdErr=''}
}
try {
    $script:sdk=Join-Path $temporary 'actual-manager-sdk';$project=Join-Path $temporary 'project';[void][IO.Directory]::CreateDirectory($project)
    [IO.File]::WriteAllText((Join-Path $project '.fvmrc'),'{"flutter":"99.0.0","flutterUrl":"https://private.invalid/project.git"}')
    foreach($relative in @('bin/flutter.bat','bin/dart.bat','bin/internal/shared.bat','bin/internal/engine.version','bin/cache/dart-sdk/bin/keep')){
        $path=Join-Path $sdk $relative;[void][IO.Directory]::CreateDirectory((Split-Path -Parent $path));[IO.File]::WriteAllText($path,$(if($relative.EndsWith('engine.version')){('a'*40)}else{'fixture'}))
    }
    $launcher=Join-Path $temporary 'fvm.bat';[IO.File]::WriteAllText($launcher,"@echo off`r`ndart `"snapshot`" %*`r`n")
    $environment=@{PATH=(Join-Path $sdk 'bin')}
    $old=[Console]::Out;$capture=New-Object IO.StringWriter
    try{[Console]::SetOut($capture);Initialize-JobsSdkFvmRuntime $launcher $project $environment}finally{[Console]::SetOut($old)}
    Assert-Gate ($script:acquired-eq1-and$script:manager-ceq(Join-Path $sdk 'bin/flutter.bat')) '准备实际管理器SDK，不按项目99.0.0绑定误认运行时'
    Assert-Gate ($capture.ToString()-ceq'') '运行时bootstrap JSON不污染之后FVM机器响应'
    Initialize-JobsSdkFvmRuntime $launcher $project $environment
    Assert-Gate ($script:acquired-eq1) '健康原生Dart/stamp不重复网络准备'
    $native=Join-Path $temporary 'native/fvm.exe';[void][IO.Directory]::CreateDirectory((Split-Path -Parent $native));[IO.File]::WriteAllBytes($native,[byte[]]@(77,90,0,0))
    Remove-Item -LiteralPath (Join-Path $sdk 'bin/cache/dart-sdk/bin/dart.exe')
    Initialize-JobsSdkFvmRuntime $native $project $environment
    Assert-Gate ($script:acquired-eq1) 'AOT原生FVM不强制启动PATH Flutter'
    $independent=Join-Path $temporary 'independent';[void][IO.Directory]::CreateDirectory($independent);[IO.File]::WriteAllText((Join-Path $independent 'dart.exe'),'native')
    Initialize-JobsSdkFvmRuntime $launcher $project @{PATH=$independent}
    Assert-Gate ($script:acquired-eq1) '独立Dart不强制关联Flutter'
    $absolute=Join-Path $temporary 'absolute/fvm.cmd';[void][IO.Directory]::CreateDirectory((Split-Path -Parent $absolute));[IO.File]::WriteAllText($absolute,'"C:\independent\dart.exe" snapshot %*')
    Initialize-JobsSdkFvmRuntime $absolute $project $environment
    Assert-Gate ($script:acquired-eq1) '固定独立运行时启动器不猜PATH Flutter'
    $psLauncher=Join-Path $temporary 'ps/fvm.ps1';[void][IO.Directory]::CreateDirectory((Split-Path -Parent $psLauncher));[IO.File]::WriteAllText($psLauncher,"& dart 'snapshot' @args")
    Initialize-JobsSdkFvmRuntime $psLauncher $project $environment
    Assert-Gate ($script:acquired-eq2) 'PowerShell文本FVM同样先准备其PATH Flutter Dart'
    [IO.File]::WriteAllText((Join-Path $sdk 'bin/cache/engine-dart-sdk.stamp'),('b'*40))
    Initialize-JobsSdkFvmRuntime $launcher $project $environment
    Assert-Gate ($script:acquired-eq3) '原生Dart存在但engine stamp过期仍先补齐实际运行时'
    $metadataCancelled=$false
    $hostTool=Join-Path $PSHOME $(if([Environment]::OSVersion.Platform-eq[PlatformID]::Win32NT){if($PSVersionTable.PSVersion.Major-le5){'powershell.exe'}else{'pwsh.exe'}}else{'pwsh'})
    try{[void](Read-JobsSdkLocalToolMetadata $hostTool @('-NoLogo','-NoProfile','-Command','exit 130') $project (Get-JobsSdkRouteEnvironment))}catch [OperationCanceledException]{$metadataCancelled=$true}
    Assert-Gate $metadataCancelled '本地元数据子进程原生130取消码不能被catch吞掉或继续其它阶段'
    Remove-Item -LiteralPath (Join-Path $sdk 'bin/cache/dart-sdk/bin/dart.exe')
    $script:cancel=$true;$cancelled=$false
    function script:New-JobsSdkToolStart {param($Tool,$Arguments,$Directory,$Environment)if([IO.Path]::GetFileName($Tool)-like'fvm*'){$script:metadataStarted=$true};$s=New-Object Diagnostics.ProcessStartInfo;$s.EnvironmentVariables['JOBS_SDK_ROUTE_TOOL']=$Tool;return $s}
    try{[void](Read-JobsSdkLocalToolMetadata $launcher @('api','context','--compress') $project $environment)}catch [OperationCanceledException]{$cancelled=$true}
    Assert-Gate ($cancelled-and-not$script:metadataStarted) '元数据前取消必须抛出，不能调用FVM/API或吞中断'
    Write-Host ('PASS: FvmRuntimeGate.Tests.ps1 ('+$script:checks+' assertions; no FVM/SDK/network)')
}finally{Remove-Item -LiteralPath $temporary -Recurse -Force}

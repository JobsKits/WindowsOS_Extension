# Windows网络选路分发、独立包、CLI及精确版本安装隔离回归。
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$genesis=Split-Path -Parent (Split-Path -Parent $root)
$script:checks=0
function Assert-Integration([bool]$Ok,[string]$Text){$script:checks++;if(-not$Ok){throw $Text}}
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('JobsSdkRouteIntegration-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
try {
    $canonical=Join-Path $root 'JobsFlutterTools/Scripts'
    $directories=@()
    foreach($area in @($root,(Join-Path $genesis 'JobsCommand@Flutter/WindowsOS'),(Join-Path $genesis 'SourceTree.command/WindowsOS'))){
        if(Test-Path -LiteralPath $area){$directories+=@(Get-ChildItem -LiteralPath $area -Filter SdkDownloadOutput.ps1 -File -Recurse|ForEach-Object{$_.Directory.FullName})}
    }
    foreach($directory in $directories){
        foreach($relative in @('SdkDownloadOutput.ps1','SdkDownloadRoute.ps1/SdkDownloadRoute.ps1','SdkDownloadRoute.ps1/README.md')){
            Assert-Integration ((Get-FileHash -LiteralPath (Join-Path $canonical $relative)).Hash-ceq(Get-FileHash -LiteralPath (Join-Path $directory $relative)).Hash) ('随包网络公共行为不一致：'+$directory+'/'+$relative)
        }
    }
    Assert-Integration ($directories.Count-ge34) '三个仓的独立随包SDK网络资源全部纳入'
    foreach($name in @('JobsFlutterRunner','JobsFlutterTools')){
        $module=Import-Module (Join-Path $root ($name+'/Scripts/PackageInstaller.psm1')) -Force -PassThru -DisableNameChecking
        $release=New-JobsPackageRelease -PackagePath (Join-Path $root $name) -Destination (Join-Path $temporary $name)
        Assert-Integration ([IO.File]::Exists((Join-Path $release 'Scripts/SdkDownloadRoute.ps1/SdkDownloadRoute.ps1'))-and[IO.File]::Exists((Join-Path $release 'Scripts/SdkDownloadRoute.ps1/README.md'))) 'release必须携带网络核心和同名说明'
        if($name-ceq'JobsFlutterTools'){Assert-Integration ([IO.File]::Exists((Join-Path $release 'Scripts/Actions/run/Scripts/SdkDownloadRoute.ps1/SdkDownloadRoute.ps1'))) '聚合子菜单运行资源也可独立解析'}
        Remove-Module $module
    }
    $libraryPath=Join-Path $genesis 'JobsCommand@Flutter/WindowsOS/Scripts/FlutterTools.psm1'
    $library=Import-Module $libraryPath -Force -PassThru -DisableNameChecking
    $installed=& $library {
        param($Destination)
        Import-JobsSdkDownloadRoute
        $script:FixtureArchitecture=if($env:PROCESSOR_ARCHITECTURE-ceq'ARM64'){'arm64'}else{'x64'}
        $script:FixtureArchive='new-'+$script:FixtureArchitecture+'.zip'
        $script:FixtureSha256=if($script:FixtureArchitecture-ceq'arm64'){'c'*64}else{'b'*64}
        $script:FixtureArchiveRequests=New-Object 'Collections.Generic.List[string]'
        function script:Receive-JobsSdkWebFile {
            param($Uri,$Destination,$TimeoutSeconds,$ExpectedSha256)
            if($Uri.EndsWith('releases_windows.json')){
                $releases=@()
                foreach($architecture in @('x64','arm64')){
                    $releases+=[ordered]@{hash='old';channel='stable';version='3.20.0';dart_sdk_arch=$architecture;archive=('stable/windows/old-'+$architecture+'.zip');sha256=('a'*64)}
                    $releases+=[ordered]@{hash='new';channel='stable';version='3.99.0';dart_sdk_arch=$architecture;archive=('stable/windows/new-'+$architecture+'.zip');sha256=$(if($architecture-ceq'arm64'){'c'*64}else{'b'*64})}
                }
                $metadata=[ordered]@{base_url='https://storage.googleapis.com/flutter_infra_release/releases';current_release=@{stable='new'};releases=$releases}
                [IO.File]::WriteAllText($Destination,($metadata|ConvertTo-Json -Depth 6))
            }else{
                if(-not$Uri.EndsWith('/'+$script:FixtureArchive)-or$ExpectedSha256-cne$script:FixtureSha256){throw 'requested stable并未使用当前架构的current_release归档和对应SHA'}
                $script:FixtureArchiveRequests.Add($Uri)
                [IO.File]::WriteAllText($Destination,'fake archive')
            }
        }
        function script:Expand-Archive {param($LiteralPath,$DestinationPath)$path=Join-Path $DestinationPath 'flutter/bin/flutter.bat';[void][IO.Directory]::CreateDirectory((Split-Path -Parent $path));[IO.File]::WriteAllText($path,'fixture')}
        $result=Install-JobsFlutterSdk $Destination stable
        if($script:FixtureArchiveRequests.Count-ne1){throw 'SDK安装必须只获取一次当前架构的精确归档'}
        return $result
    } (Join-Path $temporary 'install')
    Assert-Integration ([IO.File]::Exists((Join-Path $installed 'bin/flutter.bat'))) 'JobsCommand稳定版获取使用精确新归档且只在完整后发布'
    Remove-Module $library
    if([Environment]::OSVersion.Platform-ne[PlatformID]::Win32NT){
        $fake=Join-Path $temporary 'flutter.exe'
        [IO.File]::WriteAllText($fake,"#!/bin/sh`nprintf '{`"sdk`":`"fixture`"}'`n",(New-Object Text.UTF8Encoding($false)))
        & /bin/chmod u+x $fake
        $argv=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('["--version","--machine"]'))
        $start=New-Object Diagnostics.ProcessStartInfo;$start.FileName=Join-Path $PSHOME 'pwsh'
        $start.ArgumentList.Add('-NoLogo');$start.ArgumentList.Add('-NoProfile');$start.ArgumentList.Add('-File');$start.ArgumentList.Add((Join-Path $canonical 'SdkDownloadRoute.ps1/SdkDownloadRoute.ps1'));$start.ArgumentList.Add('-RunTool');$start.ArgumentList.Add($fake);$start.ArgumentList.Add('-RunDirectory');$start.ArgumentList.Add($temporary);$start.ArgumentList.Add('-RunArgumentsBase64');$start.ArgumentList.Add($argv)
        $start.UseShellExecute=$false;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
        $process=New-Object Diagnostics.Process;$process.StartInfo=$start;[void]$process.Start();$output=$process.StandardOutput.ReadToEndAsync();$errors=$process.StandardError.ReadToEndAsync()
        if(-not$process.WaitForExit(15000)){$process.Kill();throw 'CLI隔离夹具超时'}
        $stdout=$output.GetAwaiter().GetResult();$stderr=$errors.GetAwaiter().GetResult()
        Assert-Integration ($process.ExitCode-eq0-and$stdout-ceq'{"sdk":"fixture"}') ('CLI不得污染machine stdout：'+$stdout+' / '+$stderr)
        Assert-Integration ($stderr.Contains('第 1 次')-and$stderr.Contains('获取成功')) 'CLI选路/重试诊断单独写stderr'
        $process.Dispose()
        [IO.File]::WriteAllText($fake,"#!/bin/sh`nexit 130`n",(New-Object Text.UTF8Encoding($false)))
        $cancel=New-Object Diagnostics.Process;$cancel.StartInfo=$start;[void]$cancel.Start()
        $cancelOut=$cancel.StandardOutput.ReadToEndAsync();$cancelError=$cancel.StandardError.ReadToEndAsync()
        if(-not$cancel.WaitForExit(15000)){$cancel.Kill();throw '取消CLI夹具超时'}
        Assert-Integration ($cancel.ExitCode-eq130-and$cancelOut.GetAwaiter().GetResult()-ceq''-and$cancelError.GetAwaiter().GetResult().Contains('已取消')) '原生130终止CLI，不能重新开始或污染machine stdout'
        $cancel.Dispose()
    }
    Write-Host ('PASS: SdkNetworkIntegration.Tests.ps1 ('+$script:checks+' assertions; no SDK/network/registry)')
} finally {if([IO.Directory]::Exists($temporary)){Remove-Item -LiteralPath $temporary -Recurse -Force}}

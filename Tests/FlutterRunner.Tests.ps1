# FlutterRunner.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年10月20日，星期二.
# 临时文件 / 假 Flutter；不注册菜单、不启动真实设备、不访问项目。
[CmdletBinding()]
param([switch]$Native)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$package = Join-Path $root 'JobsFlutterRunner'
$action = Import-Module (Join-Path $package 'Scripts/Action.psm1') -PassThru -DisableNameChecking
$installer = Import-Module (Join-Path $package 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
$script:assertions = 0
function Assert-Runner { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw ('FAIL: ' + $Message) }; $script:assertions++ }
function Assert-RunnerThrows { param([scriptblock]$Body, [string]$Message); $threw = $false; try { & $Body | Out-Null } catch { $threw = $true }; Assert-Runner $threw $Message }
$temporaryBase = [IO.Path]::GetTempPath()
if ([IO.Directory]::Exists('/private/tmp')) { $temporaryBase = '/private/tmp' }
$temporary = Join-Path $temporaryBase ('JobsFlutterRun-' + [guid]::NewGuid().ToString('N'))
$savedLocal = $env:LOCALAPPDATA
try {
    [void][IO.Directory]::CreateDirectory($temporary)
    $env:LOCALAPPDATA = Join-Path $temporary 'Local'
    $fixtures = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Fixtures/FlutterRunnerPubspec.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($fixture in $fixtures) {
        $result = & $action { param($Text) Test-JobsFlutterPubspec $Text } $fixture.Text
        Assert-Runner ($result -eq $fixture.Expected) ('精确识别：' + $fixture.Name)
    }
    $project = Join-Path $temporary 'Project 中文 & 100%'
    [void][IO.Directory]::CreateDirectory((Join-Path $project 'android'))
    [void][IO.Directory]::CreateDirectory((Join-Path $project 'web'))
    [IO.File]::WriteAllText((Join-Path $project 'pubspec.yaml'), "dependencies:`n  flutter:`n    sdk: flutter`n")
    & $action { param($Path) Assert-JobsFlutterProject $Path } $project
    Assert-RunnerThrows { & $action { param($Path) Assert-JobsFlutterProject $Path } $temporary } '不向下扫描子项目'
    Assert-RunnerThrows { & $action { param($Path) Assert-JobsFlutterProject $Path } (Join-Path $project 'android') } '不沿用父工程'
    [IO.File]::WriteAllText((Join-Path $project '.fvmrc'), '{"flutter":"3.0.0"}')
    Assert-RunnerThrows { & $action { param($Path) Get-JobsRunnerFlutter $Path } $project } 'FVM 已声明但本地 SDK 缺失时不改用全局 Flutter'
    $boundSdk = Join-Path $project '.fvm/flutter_sdk/bin'
    [void][IO.Directory]::CreateDirectory($boundSdk)
    [IO.File]::WriteAllText((Join-Path $boundSdk 'flutter.bat'), '@echo fixture')
    Assert-Runner ((& $action { param($Path) Get-JobsRunnerFlutter $Path } $project) -eq (Join-Path $boundSdk 'flutter.bat')) '优先采用项目绑定的 Flutter'
    $devices = @(& $action { ConvertFrom-JobsRunnerList '[{"id":"android-1","name":"Pixel","targetPlatform":"android"},{"id":"win","name":"Windows","targetPlatform":"windows-x64"},{"id":"chrome","name":"Chrome","targetPlatform":"web-javascript"},{"id":"ios","name":"iPhone","targetPlatform":"ios"}]' })
    Assert-Runner ($devices.Count -eq 4) '正确枚举 JSON 顶层数组'
    $supported = @(& $action { param($Devices, $Project) Get-JobsRunnerSupportedDevices $Devices $Project } $devices $project)
    Assert-Runner ($supported.Count -eq 2 -and $supported[0].id -eq 'android-1' -and $supported[1].id -eq 'chrome') '按项目平台目录过滤 Windows / iOS 不兼容设备'
    Assert-Runner (@(& $action { ConvertFrom-JobsRunnerList '[]' }).Count -eq 0) '无设备返回真实空列表'
    Assert-Runner (@(& $action { ConvertFrom-JobsRunnerList "Preparing Flutter`n[]" }).Count -eq 0) '准备信息后仍支持空列表'
    Assert-RunnerThrows { & $action { ConvertFrom-JobsRunnerList '[{"name":"missing id"}]' } } '无效设备响应停止'
    Assert-RunnerThrows { & $action { ConvertFrom-JobsRunnerList 'not JSON' } } '损坏 JSON 不能当空列表成功'
    $dataRoot = & $action { param($Path) Get-JobsRunnerProjectRoot $Path } $project
    Assert-Runner (-not (Test-Path -LiteralPath $dataRoot)) '查询项目数据位置不创建文件'
    $session = Join-Path $dataRoot 'session'
    [void][IO.Directory]::CreateDirectory($session)
    $statePath = Join-Path $session 'state.json'
    $ownProcess = Get-Process -Id $PID
    $state = @{ Status = 'Running'; WorkerPid = $PID; WorkerStartUtc = $ownProcess.StartTime.ToUniversalTime().ToString('o'); Session = $session }
    [IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json))
    Assert-Runner ($null -ne (& $action { param($Path) Get-JobsRunnerSession $Path } $dataRoot)) 'PID 与开始时间均匹配才允许重连'
    $state.WorkerStartUtc = [DateTime]::UtcNow.AddDays(-1).ToString('o')
    [IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json))
    Assert-Runner ($null -eq (& $action { param($Path) Get-JobsRunnerSession $Path } $dataRoot)) 'PID 复用不能误认成运行会话'
    & $action { param($Path) Send-JobsRunnerControl $Path 'reload'; Send-JobsRunnerControl $Path 'restart'; Send-JobsRunnerControl $Path 'stop' } $session
    $controls = @(Get-ChildItem -LiteralPath $session -Filter 'control-*.json')
    Assert-Runner ($controls.Count -eq 3 -and @(Get-ChildItem -LiteralPath $session -Filter '*.tmp').Count -eq 0) '控制请求独立原子写入，没有半写临时文件'
    $commands = @($controls | ForEach-Object { (Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json).Command } | Sort-Object)
    Assert-Runner (($commands -join ',') -ceq 'reload,restart,stop') 'r / R / s 映射为独立命令'
    $manifest = Get-Content -LiteralPath (Join-Path $package 'Extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $release = Join-Path $temporary 'release'
    & $installer { param($Path, $Destination) New-JobsPackageRelease -PackagePath $Path -Destination $Destination } $package $release | Out-Null
    foreach ($name in @('ContextMenu.cpp', 'FlutterProject.h', 'ContextMenu.def', 'RunnerHost.cs', 'Build.ps1', 'OpenCmd.ps1')) {
        Assert-Runner (Test-Path -LiteralPath (Join-Path $release ('Scripts/' + $name)) -PathType Leaf) ('独立 release 包含：' + $name)
    }
    $plan = @(& $installer { param($Manifest, $Release) Get-JobsPackageRegistryPlan -Manifest $Manifest -ReleasePath $Release -PowerShellPath 'powershell.exe' } $manifest $release)
    Assert-Runner ($plan.Count -eq 4) '三个动态上下文 + 一个本包 CLSID'
    Assert-Runner (@($plan | Where-Object { $_.Key -match '\\shell\\' }).Count -eq 0) '注册计划没有全目录可见的静态 verb'
    Assert-Runner ($plan[3].InProcServer -eq (Join-Path $release 'bin/JobsFlutterContextMenu.dll')) 'CLSID 绑定本次独立 release 的原生 DLL'
    $disabled = @(& $installer { param($Manifest, $Release) Get-JobsPackageRegistryPlan -Manifest $Manifest -ReleasePath $Release -PowerShellPath 'powershell.exe' -Enabled $false } $manifest $release)
    Assert-Runner (@($disabled | Where-Object Enabled).Count -eq 0) '卸载包括菜单与 COM CLSID'
    if ($Native -and [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        & (Join-Path $package 'Scripts/Build.ps1') -OutputRoot (Join-Path $release 'bin')
        Add-Type -Path (Join-Path $PSScriptRoot 'FlutterRunnerMenuProbe.cs')
        $library = Join-Path $release 'bin/JobsFlutterContextMenu.dll'
        Assert-Runner ([JobsFlutterRunnerTests.MenuProbe]::Count($library, $project, 0) -eq 1) '原生 COM 在 Flutter 工程背景插入一项'
        Assert-Runner ([JobsFlutterRunnerTests.MenuProbe]::Count($library, $project, 1) -eq 1) '原生 COM 在所选 Flutter 文件夹插入一项'
        Assert-Runner ([JobsFlutterRunnerTests.MenuProbe]::Count($library, $temporary, 0) -eq 0) '原生 COM 在普通背景真实插入零项'
        Assert-Runner ([JobsFlutterRunnerTests.MenuProbe]::Count($library, $temporary, 1) -eq 0) '原生 COM 在普通文件夹真实插入零项'
        Assert-Runner ([JobsFlutterRunnerTests.MenuProbe]::Count($library, $project, 2) -eq 0) '原生 COM 多选不显示'
        $fake = Join-Path $temporary 'FakeFlutter.cs'
        $fakeSource = @'
using System;
using System.IO;
using System.Threading;
class FakeFlutter {
    static void Main() {
        Console.WriteLine("[{\"event\":\"app.start\",\"params\":{\"appId\":\"fake-app\"}}]");
        Console.WriteLine("[{\"event\":\"app.started\",\"params\":{\"appId\":\"fake-app\"}}]");
        Console.Out.Flush();
        string line;
        while ((line = Console.ReadLine()) != null) {
            File.AppendAllText(Path.Combine(Environment.CurrentDirectory, "commands.log"), line + Environment.NewLine);
            if (line.Contains("app.stop")) return;
            Console.WriteLine("[{\"event\":\"app.log\",\"params\":{\"log\":\"control received\"}}]");
            Console.Out.Flush();
        }
    }
}
'@
        [IO.File]::WriteAllText($fake, $fakeSource)
        $csc = Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
        $fakeExe = Join-Path $temporary 'FakeFlutter.exe'
        & $csc /nologo /target:exe ('/out:' + $fakeExe) $fake
        if ($LASTEXITCODE -ne 0) { throw '假 Flutter 编译失败。' }
        $nativeRoot = Join-Path $temporary 'Native'
        $nativeSession = Join-Path $nativeRoot 'session'
        [void][IO.Directory]::CreateDirectory($nativeSession)
        $request = Join-Path $nativeSession 'request.json'
        [IO.File]::WriteAllText($request, (@{ Project = $project; Flutter = $fakeExe; Device = 'fake-device' } | ConvertTo-Json))
        $hostExe = Join-Path $release 'bin/JobsFlutterRunnerHost.exe'
        $starter = Start-Process -FilePath $hostExe -ArgumentList @('start', ('"' + $request + '"')) -PassThru -Wait
        Assert-Runner ($starter.ExitCode -eq 0) '前台启动进程正常退出'
        $clock = [Diagnostics.Stopwatch]::StartNew()
        do {
            Start-Sleep -Milliseconds 100
            $nativeStatePath = Join-Path $nativeSession 'state.json'
            $nativeState = $null
            if (Test-Path -LiteralPath $nativeStatePath) { $nativeState = Get-Content -LiteralPath $nativeStatePath -Raw -Encoding UTF8 | ConvertFrom-Json }
        } while (($null -eq $nativeState -or $nativeState.Status -eq 'Starting') -and $clock.Elapsed.TotalSeconds -lt 15)
        Assert-Runner ($nativeState.Status -eq 'Running') '启动者退出后独立监督进程与 Flutter 继续运行'
        & $action { param($Path) Send-JobsRunnerControl $Path reload; Send-JobsRunnerControl $Path restart } $nativeSession
        Start-Sleep -Milliseconds 500
        & $action { param($Path) Send-JobsRunnerControl $Path stop } $nativeSession
        $clock.Restart()
        do {
            Start-Sleep -Milliseconds 100
            $nativeState = Get-Content -LiteralPath $nativeStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        } while ($nativeState.Status -notin @('Stopped', 'Failed') -and $clock.Elapsed.TotalSeconds -lt 15)
        Assert-Runner ($nativeState.Status -eq 'Stopped') 's 通过 app.stop 结束本次会话'
        $requests = Get-Content -LiteralPath (Join-Path $project 'commands.log') -Raw -Encoding UTF8
        Assert-Runner ($requests.Contains('"fullRestart":false') -and $requests.Contains('"fullRestart":true') -and $requests.Contains('app.stop')) 'machine 控制实际到达假 Flutter'
    } else { Write-Host 'SKIP: MSVC/.NET 编译、Win32 detached / Job 与真实菜单需要 Windows。可在 Windows 使用 -Native。' }
    Write-Host ('PASS: FlutterRunner.Tests.ps1 (' + $script:assertions + ' assertions)')
} finally {
    $env:LOCALAPPDATA = $savedLocal
    Remove-Module $action
    Remove-Module $installer
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}

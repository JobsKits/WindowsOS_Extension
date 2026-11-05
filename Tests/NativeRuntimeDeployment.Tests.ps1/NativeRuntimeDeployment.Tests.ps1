# NativeRuntimeDeployment.Tests.ps1 | Jobs Windows 原生运行产物部署边界
# Created by Jobs on 2026年11月2日，星期一.
# 只运行临时假构建；不调用 MSVC、不登记系统菜单、不启动后台宿主。
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempBase = [IO.Path]::GetTempPath()
if ($tempBase.StartsWith('/var/') -and (Test-Path ('/private' + $tempBase))) { $tempBase = '/private' + $tempBase }
$temp = Join-Path $tempBase ('JobsNativeRuntime 中文 ' + [guid]::NewGuid().ToString('N'))
$oldLocal = $env:LOCALAPPDATA
$script:assertions = 0
$modules = @()
function Assert-Runtime { param([bool]$Value, [string]$Message) if (-not $Value) { throw ('FAIL: ' + $Message) }; $script:assertions++ }
function Write-Fixture { param([string]$Path, [string]$Text) [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path)); [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($true))) }
try {
    $env:LOCALAPPDATA = Join-Path $temp 'LocalData'
    foreach ($name in @('JobsFlutterRunner', 'JobsFlutterTools')) {
        $package = Join-Path $temp ('Sources/' + $name)
        $manifest = Get-Content -LiteralPath (Join-Path $root ($name + '/Extension.json')) -Raw | ConvertFrom-Json
        Write-Fixture (Join-Path $package 'Extension.json') ($manifest | ConvertTo-Json -Depth 8)
        Write-Fixture (Join-Path $package 'Scripts/PackageInstaller.psm1') (Get-Content -LiteralPath (Join-Path $root ($name + '/Scripts/PackageInstaller.psm1')) -Raw)
        if ($name -eq 'JobsFlutterTools') {
            Write-Fixture (Join-Path $package 'Scripts/FeatureActions.psm1') (Get-Content -LiteralPath (Join-Path $root 'JobsFlutterTools/Scripts/FeatureActions.psm1') -Raw)
        }
        $module = Import-Module (Join-Path $package 'Scripts/PackageInstaller.psm1') -PassThru -Force -DisableNameChecking
        $modules += $module
        foreach ($route in @('installed', 'build')) {
            $release = Join-Path $temp ('Runtime/' + $name + '/' + $route)
            Write-Fixture (Join-Path $release 'Extension.json') ($manifest | ConvertTo-Json -Depth 8)
            foreach ($file in @('Invoke.ps1', 'Common.psm1', 'Action.psm1')) { Write-Fixture (Join-Path $release ('Scripts/' + $file)) '# fixture runtime' }
            $dll = 'JobsFlutterContextMenu.dll'
            if ($name -eq 'JobsFlutterTools') { $dll = 'JobsFlutterToolsContextMenu.dll' }
            $fakeBuild = @'
param($SourceRoot, $OutputRoot)
[void][IO.Directory]::CreateDirectory($OutputRoot)
[IO.File]::WriteAllText((Join-Path $OutputRoot '__DLL__'), 'runtime-dll')
[IO.File]::WriteAllText((Join-Path $OutputRoot 'JobsFlutterRunnerHost.exe'), 'runtime-host')
[IO.File]::WriteAllText((Join-Path $OutputRoot 'native.obj'), 'intermediate')
[IO.File]::WriteAllText((Join-Path $OutputRoot 'native.rsp'), 'compiler-response')
'@
            Write-Fixture (Join-Path $release 'Scripts/Build.ps1') ($fakeBuild.Replace('__DLL__', $dll))
            & $module { param($Path, $Release, $Route) Build-JobsPackageNativeRelease -PackagePath $Path -ReleasePath $Release -DeploymentMode $Route } $package $release $route
            $buildPath = & $module { $script:LastBuildPath }
            $runtimePaths = @(('bin/' + $dll), 'bin/JobsFlutterRunnerHost.exe')
            if ($name -eq 'JobsFlutterTools') { $runtimePaths += 'Scripts/Actions/run/bin/JobsFlutterRunnerHost.exe' }
            foreach ($relative in $runtimePaths) {
                Assert-Runtime (Test-Path -LiteralPath (Join-Path $release $relative) -PathType Leaf) ($name + '/' + $route + ' 运行产物就位：' + $relative)
            }
            if ($route -eq 'installed') {
                Assert-Runtime (-not (Test-Path -LiteralPath (Join-Path $release 'bin/native.obj'))) ($name + ' installed 不携带编译中间文件')
                $stateRoot = Join-Path $env:LOCALAPPDATA ('Jobs/WindowsExtension/extensions/' + $manifest.Id)
                Write-Fixture (Join-Path $stateRoot 'settings.json') (ConvertTo-Json -InputObject @{ Version = 2; Id = $manifest.Id; Enabled = $true; ReleasePath = $release })
                $hashes = @{}
                foreach ($relative in $runtimePaths) { $hashes[$relative] = (Get-FileHash -LiteralPath (Join-Path $release $relative)).Hash }
                & $module { param($Path, $Build) Clear-JobsPackageBuildArtifacts -PackagePath $Path -BuildPath $Build } $package $buildPath
                Assert-Runtime (-not (Test-Path -LiteralPath $buildPath)) ($name + ' 自动清除本轮 GUID 工作区')
                foreach ($relative in $runtimePaths) {
                    Assert-Runtime ((Get-FileHash -LiteralPath (Join-Path $release $relative)).Hash -eq $hashes[$relative]) ($name + ' 自动清理保留运行产物：' + $relative)
                }
                & $module { param($Path, $Release) Build-JobsPackageNativeRelease -PackagePath $Path -ReleasePath $Release -DeploymentMode installed } $package $release
                & $module { param($Path) Clear-JobsPackageBuildArtifacts -PackagePath $Path } $package
                foreach ($relative in $runtimePaths) {
                    Assert-Runtime ((Get-FileHash -LiteralPath (Join-Path $release $relative)).Hash -eq $hashes[$relative]) ($name + ' 独立清理保留运行产物：' + $relative)
                }
                # 有 DLL 而缺 EXE 时不能假绿；正在使用的旧宿主保持原样。
                Write-Fixture (Join-Path $release 'Scripts/Build.ps1') (($fakeBuild.Replace('__DLL__', $dll)) -replace "(?m)^.*JobsFlutterRunnerHost.exe.*(?:\r?\n|$)", '')
                $rejected = $false
                try { & $module { param($Path, $Release) Build-JobsPackageNativeRelease -PackagePath $Path -ReleasePath $Release -DeploymentMode installed } $package $release } catch { $rejected = $true }
                Assert-Runtime $rejected ($name + ' 缺失后台宿主时阻断部署')
                Assert-Runtime ((Get-FileHash -LiteralPath (Join-Path $release 'bin/JobsFlutterRunnerHost.exe')).Hash -eq $hashes['bin/JobsFlutterRunnerHost.exe']) ($name + ' 构建失败不覆盖旧运行宿主')
            }
        }
    }
    # 执行联合包真实 C# 构建尾段，仅把 csc 换成临时假编译器；检查 OutputRoot 写入边界。
    $buildText = Get-Content -LiteralPath (Join-Path $root 'JobsFlutterTools/Scripts/Build.ps1') -Raw
    $tailStart = $buildText.IndexOf("`n", $buildText.IndexOf('$csc = '))
    $tail = $buildText.Substring($tailStart + 1)
    $compiler = Join-Path $temp 'FakeCsc.ps1'
    Write-Fixture $compiler @'
foreach ($argument in $args) {
    if ([string]$argument -like '/out:*') { [IO.File]::WriteAllText(([string]$argument).Substring(5), 'compiled-host') }
}
$global:LASTEXITCODE = 0
'@
    $isolatedBuildRoot = Join-Path $temp 'CompilerWorkspace'
    $output = Join-Path $isolatedBuildRoot ([guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($output)
    & { param($Compiler, $OutputPath, $Body) $csc = $Compiler; $output = $OutputPath; $scripts = 'unused-source'; & ([scriptblock]::Create($Body)) } $compiler $output $tail
    Assert-Runtime (Test-Path -LiteralPath (Join-Path $output 'JobsFlutterRunnerHost.exe')) '联合包真实构建尾段将 EXE 写在指定 OutputRoot'
    Assert-Runtime (@(Get-ChildItem -LiteralPath $isolatedBuildRoot -Force).Count -eq 1) '联合包构建不向 GUID 工作区以外写 Scripts 或运行副本'
} finally {
    foreach ($module in $modules) { Remove-Module $module -ErrorAction SilentlyContinue }
    $env:LOCALAPPDATA = $oldLocal
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
Write-Host ('PASS: NativeRuntimeDeployment.Tests.ps1 (' + $script:assertions + ' assertions)')

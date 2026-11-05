# DeploymentRoutes.Tests.ps1 | Jobs Windows 两种部署路线与清理边界
# Created by Jobs on 2026年11月2日，星期一.
# 全部文件位于临时目录；系统登记、通知和快捷方式通过临时模块内假实现阻断。
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempBase = [IO.Path]::GetTempPath()
if ($tempBase.StartsWith('/var/') -and (Test-Path ('/private' + $tempBase))) { $tempBase = '/private' + $tempBase }
$temp = Join-Path $tempBase ('JobsRoutes 中文 ' + [guid]::NewGuid().ToString('N'))
$oldLocal = $env:LOCALAPPDATA
$script:assertions = 0
function Assert-Route { param([bool]$Value, [string]$Message) if (-not $Value) { throw ('FAIL: ' + $Message) }; $script:assertions++ }
function Write-Fixture { param([string]$Path, [string]$Text) [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path)); [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($true))) }
function Assert-Rejected { param([scriptblock]$Action, [string]$Message) $rejected = $false; try { & $Action } catch { $rejected = $true }; Assert-Route $rejected $Message }
try {
    $env:LOCALAPPDATA = Join-Path $temp 'LocalData'
    $package = Join-Path $temp 'Source/JobsFixture'
    Write-Fixture (Join-Path $package 'Extension.json') '{"Id":"fixture-route","Name":"JobsFixture","Label":"测试","Description":"隔离","DirectoryOnly":false,"Console":false}'
    foreach ($name in @('Invoke.ps1', 'Action.psm1', 'Manage.ps1')) { Write-Fixture (Join-Path $package ('Scripts/' + $name)) '# isolated' }
    Copy-Item -LiteralPath (Join-Path $root 'Infrastructure/Common.psm1') -Destination (Join-Path $package 'Scripts/Common.psm1')
    Write-Fixture (Join-Path $package 'Scripts/Build.ps1') @'
param($SourceRoot, $OutputRoot)
[void][IO.Directory]::CreateDirectory($OutputRoot)
[IO.File]::WriteAllText((Join-Path $OutputRoot 'JobsFileVolumesContextMenu.dll'), 'runtime-dll')
[IO.File]::WriteAllText((Join-Path $OutputRoot 'fixture.obj'), 'intermediate')
[IO.File]::WriteAllText((Join-Path $OutputRoot 'native.rsp'), 'compiler-arguments')
'@
    $installerText = Get-Content -LiteralPath (Join-Path $root 'JobsFileVolumes/Scripts/PackageInstaller.psm1') -Raw
    $installerText = $installerText.Replace("if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT)", 'if ($false)').Replace("if (`$PSVersionTable.PSEdition -ne 'Desktop' -or `$PSVersionTable.PSVersion -lt [version]'5.1')", 'if ($false)')
    Write-Fixture (Join-Path $package 'Scripts/PackageInstaller.psm1') $installerText
    $module = Import-Module (Join-Path $package 'Scripts/PackageInstaller.psm1') -PassThru -Force -DisableNameChecking
    & $module {
        # 注册表、Shell 和开始菜单均为隔离替身；构建只写假 DLL。
        function script:Get-JobsPackageRegistrySnapshot { param($Plan, $RegistryRoot) return @{} }
        function script:Set-JobsPackageRegistry { param($Plan, $RegistryRoot) }
        function script:Restore-JobsPackageRegistrySnapshot { param($Snapshot, $RegistryRoot) }
        function script:Set-JobsPackageUninstallShortcut { param($Manifest, $ReleasePath, $Mode) }
        function script:Send-JobsPackageShellChange { }
    }
    $installed = & $module { param($Path) Invoke-JobsPackageChange -PackagePath $Path -Mode Install -DeploymentMode installed } $package
    Assert-Route ($installed.ReleasePath.StartsWith($env:LOCALAPPDATA)) '默认安装沿用当前用户 LocalAppData'
    $runtime = Import-Module (Join-Path $installed.ReleasePath 'Scripts/Common.psm1') -PassThru -Force -DisableNameChecking
    $boundRoot = & $runtime { Get-JobsInstallRoot }
    Assert-Route ($boundRoot -eq $installed.Root) '运行脚本从自身部署绑定找到状态根，无 GUI 环境变量'
    $outer = Join-Path $temp 'nested-flutter-release'
    Write-Fixture (Join-Path $outer 'deployment.json') (ConvertTo-Json -InputObject @{ Version = 1; Id = 'flutter-tools'; Root = $installed.Root })
    Write-Fixture (Join-Path $outer 'Scripts/Actions/run/Extension.json') '{"Id":"flutter-run"}'
    [void][IO.Directory]::CreateDirectory((Join-Path $outer 'Scripts/Actions/run/Scripts'))
    Copy-Item -LiteralPath (Join-Path $root 'JobsFlutterTools/Scripts/Actions/run/Scripts/Common.psm1') -Destination (Join-Path $outer 'Scripts/Actions/run/Scripts/Common.psm1') -ErrorAction Stop
    $nestedRuntime = Import-Module (Join-Path $outer 'Scripts/Actions/run/Scripts/Common.psm1') -PassThru -Force -DisableNameChecking
    Assert-Route ((& $nestedRuntime { Get-JobsInstallRoot }) -eq (Join-Path $installed.Root 'actions/flutter-run')) '统一 Flutter 内嵌动作随外层当前路线定位'

    # 对真实构建包装执行假 Build.ps1，核对中间文件与运行 DLL 分离。
    & $module { param($Path, $Release) Build-JobsPackageNativeRelease -PackagePath $Path -ReleasePath $Release -DeploymentMode installed } $package $installed.ReleasePath
    $firstBuild = & $module { $script:LastBuildPath }
    & $module { param($Path, $Release) Build-JobsPackageNativeRelease -PackagePath $Path -ReleasePath $Release -DeploymentMode installed } $package $installed.ReleasePath
    $secondBuild = & $module { $script:LastBuildPath }
    Assert-Route (Test-Path -LiteralPath (Join-Path $installed.ReleasePath 'bin/JobsFileVolumesContextMenu.dll')) '部署 DLL 存于运行 release/bin'
    Assert-Route (-not (Test-Path -LiteralPath (Join-Path $installed.ReleasePath 'bin/fixture.obj'))) '编译中间文件不混入运行 bin'
    $dllHash = (Get-FileHash (Join-Path $installed.ReleasePath 'bin/JobsFileVolumesContextMenu.dll')).Hash
    Clear-JobsPackageBuildArtifacts -PackagePath $package -BuildPath $secondBuild
    Assert-Route (-not (Test-Path $secondBuild) -and (Test-Path $firstBuild)) '自动清理只删除本次 GUID 工作区，历史构建保留'
    Assert-Route ((Get-FileHash (Join-Path $installed.ReleasePath 'bin/JobsFileVolumesContextMenu.dll')).Hash -eq $dllHash) '自动清理不改变已安装 DLL'
    Assert-Rejected { Clear-JobsPackageBuildArtifacts -PackagePath $package -BuildPath $installed.ReleasePath } '清理拒绝运行 release 路径'
    $build = & $module { param($Path) Invoke-JobsPackageChange -PackagePath $Path -Mode Install -DeploymentMode build } $package
    Assert-Route ($build.ReleasePath.StartsWith((Join-Path $package 'work/WindowsExtension'))) '临时路线只使用本包 work 运行目录'
    $buildRuntime = Import-Module (Join-Path $build.ReleasePath 'Scripts/Common.psm1') -PassThru -Force -DisableNameChecking
    Assert-Route ((& $buildRuntime { Get-JobsInstallRoot }) -eq $build.Root) 'Explorer 启动临时路线时独立找到 build 状态'
    $oldInstalled = Get-JobsPackageState -PackagePath $package -DeploymentMode installed
    Assert-Route (-not $oldInstalled.Enabled) '切换路线后原路线不再误报已启用'
    $beforeDefault = [IO.File]::ReadAllBytes((Join-Path $installed.Root 'settings.json'))
    & $module {
        param($FailPath)
        $script:TestFailPath = $FailPath
        $script:TestFailOnce = $true
        $script:RealSettingsWriter = ${function:Set-JobsPackageSettingsFile}
        function script:Set-JobsPackageSettingsFile {
            param($Path, [byte[]]$Bytes)
            if ($script:TestFailOnce -and $Path -eq $script:TestFailPath) { $script:TestFailOnce = $false; throw 'isolated-settings-failure' }
            & $script:RealSettingsWriter $Path $Bytes
        }
    } (Join-Path $installed.Root 'settings.json')
    Assert-Rejected { & $module { param($Path) Invoke-JobsPackageChange -PackagePath $Path -Mode Install -DeploymentMode installed } $package } '新路线提交失败返回失败'
    Assert-Route ((Get-JobsPackageState -PackagePath $package -DeploymentMode build).Enabled) '提交失败完整恢复原 build 路线启用状态'
    Assert-Route ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $installed.Root 'settings.json'))) -ceq [Convert]::ToBase64String($beforeDefault)) '提交失败逐字恢复 installed 原状态'

    Assert-Rejected { Clear-JobsPackageBuildArtifacts -PackagePath $package } '没有默认位置正常安装时禁止独立清理'
    $uninstall = & $module { param($Path) Invoke-JobsPackageChange -PackagePath $Path -Mode Uninstall -DeploymentMode installed } $package
    Assert-Route ((Get-JobsPackageState -PackagePath $package -DeploymentMode build).Enabled) '卸载未启用路线不会移除另一条生效路线'
    $installed = & $module { param($Path) Invoke-JobsPackageChange -PackagePath $Path -Mode Install -DeploymentMode installed } $package
    $buildRoot = Join-Path $package 'work/JobsExtensionBuild'
    $ownerPath = Join-Path $buildRoot 'build-owner.json'
    $ownerBytes = [IO.File]::ReadAllBytes($ownerPath)
    Write-Fixture $ownerPath '{"Id":"another-feature","PackagePath":"unknown"}'
    Assert-Rejected { Clear-JobsPackageBuildArtifacts -PackagePath $package } '归属标记不匹配时禁止删除工作区'
    [IO.File]::WriteAllBytes($ownerPath, $ownerBytes)
    $lock = [IO.File]::Open((Join-Path $env:LOCALAPPDATA 'Jobs/WindowsExtension/manage.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try { Assert-Rejected { Clear-JobsPackageBuildArtifacts -PackagePath $package } '另一个事务持锁时清理拒绝执行' } finally { $lock.Dispose() }
    $link = Join-Path $buildRoot 'external-link'
    $outside = Join-Path $temp 'outside/sentinel'
    Write-Fixture $outside 'preserve'
    $linked = $false
    try { [void](New-Item -ItemType SymbolicLink -Path $link -Target (Split-Path -Parent $outside) -ErrorAction Stop); $linked = $true } catch { Write-Host 'SKIP: 创建测试链接需要权限。' }
    if ($linked) {
        Assert-Rejected { Clear-JobsPackageBuildArtifacts -PackagePath $package } '子项为链接时禁止递归删除'
        Assert-Route ([IO.File]::ReadAllText($outside) -ceq 'preserve') '拒绝清理后外部目标保持原样'
        Remove-Item -LiteralPath $link -Force
    }
    Clear-JobsPackageBuildArtifacts -PackagePath $package
    Assert-Route (-not (Test-Path (Join-Path $package 'work/JobsExtensionBuild'))) '独立清理删除专用编译工作区'
    Assert-Route (Test-Path (Join-Path $build.ReleasePath 'Scripts/Invoke.ps1')) '独立清理保留临时路线既有 release 与脚本'
    Assert-Route (Test-Path (Join-Path $installed.Root 'settings.json')) '清理保留已安装状态配置'
    Assert-Route (Test-Path (Join-Path $package 'Scripts/Build.ps1')) '清理保留源码与安装管理入口'
    $worker = Join-Path $root 'Scripts/ManagementWorker.ps1'
    $fake = @'
function Invoke-JobsPackageChange {
    param($PackagePath, $Mode, $DeploymentMode)
    Add-Content -LiteralPath (Join-Path $PackagePath 'called') -Value ($Mode + ':' + $DeploymentMode)
    $stop = Join-Path $PackagePath 'stop-target'
    if (Test-Path $stop) { [IO.File]::WriteAllText(([IO.File]::ReadAllText($stop)), 'requested') }
    [Threading.Thread]::Sleep(80)
    [IO.File]::WriteAllText((Join-Path $PackagePath 'transaction-finished'), 'committed')
    if (Test-Path (Join-Path $PackagePath 'fail')) { throw 'isolated-failure' }
    [pscustomobject]@{ BuildPath = (Join-Path $PackagePath 'fake-build') }
}
function Clear-JobsPackageBuildArtifacts {
    param($PackagePath, $BuildPath)
    if (Test-Path (Join-Path $PackagePath 'cleanup-fail')) { throw 'isolated-cleanup-refused' }
    [IO.File]::WriteAllText((Join-Path $PackagePath 'cleaned'), [string]$BuildPath)
}
Export-ModuleMember -Function Invoke-JobsPackageChange, Clear-JobsPackageBuildArtifacts
'@
    $plan = @()
    foreach ($id in @('worker-one', 'worker-two')) {
        $path = Join-Path $temp $id
        Write-Fixture (Join-Path $path 'Extension.json') ('{"Id":"' + $id + '"}')
        Write-Fixture (Join-Path $path 'Scripts/PackageInstaller.psm1') $fake
        $plan += [pscustomobject]@{ Id = $id; Label = $id; PackagePath = $path; Mode = 'Install'; DisplayMode = 'Install'; FeatureIds = @($id) }
    }
    function Invoke-IsolatedWorker {
        param([string]$Route, [bool]$Cleanup, [string]$StopPath)
        $requestPath = Join-Path $temp ('request-' + [guid]::NewGuid().ToString('N') + '.json')
        Write-Fixture $requestPath (ConvertTo-Json -InputObject @{ Plan = $plan; DeploymentMode = $Route; AutoCleanup = $Cleanup; StopRequestPath = $StopPath } -Depth 8)
        $lines = @(& (Get-Process -Id $PID).Path -NoLogo -NoProfile -NonInteractive -File $worker -RequestPath $requestPath 2>&1)
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = (($lines | ForEach-Object { [string]$_ }) -join "`n") }
    }
    $run = Invoke-IsolatedWorker build $true ''
    Assert-Route ($run.ExitCode -eq 0 -and (Get-Content (Join-Path $temp 'worker-one/called') -Raw).Contains('Install:build')) 'worker 显式把 build 路线传至安装器'
    Assert-Route (-not (Test-Path (Join-Path $temp 'worker-one/cleaned'))) 'build 路线即使收到清理标志也不清理'
    $run = Invoke-IsolatedWorker installed $true ''
    Assert-Route ($run.ExitCode -eq 0 -and (Test-Path (Join-Path $temp 'worker-one/cleaned'))) 'installed 成功后才清理本轮 BuildPath'
    Write-Fixture (Join-Path $temp 'worker-one/cleanup-fail') 'locked'
    $run = Invoke-IsolatedWorker installed $true ''
    Assert-Route ($run.ExitCode -eq 0 -and $run.Text.Contains('安装成功，清理失败') -and -not $run.Text.Contains('"State":"Failed"')) '自动清理安全拒绝不把已成功安装标为失败'
    Assert-Route ($run.Text.Contains('"State":"Succeeded"')) '自动清理拒绝后安装仍发出成功事件'
    $plan[0].Mode = 'Cleanup'; $plan[1].Mode = 'Cleanup'
    $run = Invoke-IsolatedWorker installed $false ''
    Assert-Route ($run.ExitCode -ne 0 -and $run.Text.Contains('"State":"Failed"')) '独立清理失败仍按清理失败报告'
    $plan[0].Mode = 'Install'; $plan[1].Mode = 'Install'
    Remove-Item (Join-Path $temp 'worker-one/cleanup-fail')

    Remove-Item (Join-Path $temp 'worker-one/cleaned')
    Write-Fixture (Join-Path $temp 'worker-one/fail') 'fail'
    $run = Invoke-IsolatedWorker installed $true ''
    Assert-Route ($run.ExitCode -ne 0 -and -not (Test-Path (Join-Path $temp 'worker-one/cleaned'))) '安装失败保留本轮构建产物'
    Assert-Route ($run.Text.Contains('isolated-failure') -and $run.Text.Contains('worker-two')) '单包失败仍继续后续包'
    Remove-Item (Join-Path $temp 'worker-one/fail')
    Remove-Item (Join-Path $temp 'worker-two/called')
    $stopPath = Join-Path $temp 'stop-after-current'
    Write-Fixture (Join-Path $temp 'worker-one/stop-target') $stopPath
    $run = Invoke-IsolatedWorker installed $false $stopPath
    Assert-Route ($run.ExitCode -eq 0 -and $run.Text.Contains('"State":"Stopped"') -and $run.Text.Contains('"State":"Skipped"')) '停止不是失败，余项明确发出未执行事件'
    Assert-Route (Test-Path (Join-Path $temp 'worker-one/transaction-finished')) '停止请求保留当前事务至结束'
    Assert-Route (-not (Test-Path (Join-Path $temp 'worker-two/called'))) '停止后不再调用下一包'
    Remove-Item (Join-Path $temp 'worker-one/called')
    $run = Invoke-IsolatedWorker installed $false $stopPath
    Assert-Route (-not (Test-Path (Join-Path $temp 'worker-one/called'))) '启动前已有停止请求时所有项目均不执行'
    Remove-Item $stopPath
    $plan[0].Mode = 'Cleanup'; $plan[1].Mode = 'Cleanup'
    $run = Invoke-IsolatedWorker installed $false ''
    Assert-Route ($run.ExitCode -eq 0 -and -not (Test-Path (Join-Path $temp 'worker-one/called'))) '独立清理不调用安装器事务'
    $panel = Import-Module (Join-Path $root 'Scripts/Installer.psm1') -PassThru -Force -DisableNameChecking
    $progress = & $panel { Get-JobsManagementProgress ([pscustomobject]@{ FeatureStates = @{ first = 'Succeeded'; second = 'Skipped'; third = 'Skipped' } }) }
    Assert-Route ($progress.Finished -eq 1 -and $progress.Percent -eq '33.3') '未执行项目不计失败或完成百分比'
    $stopState = [pscustomobject]@{ Running = $true; Operation = 'Install'; StopRequested = $false; StopRequestPath = (Join-Path $temp 'panel-stop'); ConfirmButton = [pscustomobject]@{ Enabled = $true; Text = '停止安装' } }
    & $panel {
        param($State)
        function script:Add-JobsManagementLog { param($State, $Text) }
        function script:Update-JobsManagementProgress { param($State) }
        Request-JobsManagementStop $State
    } $stopState
    Assert-Route ($stopState.StopRequested -and -not $stopState.ConfirmButton.Enabled -and (Test-Path $stopState.StopRequestPath)) 'GUI 停止只写请求文件并等待，不结束进程'

} finally {
    $env:LOCALAPPDATA = $oldLocal
    foreach ($name in @('module', 'runtime', 'buildRuntime', 'nestedRuntime', 'panel')) { $value = Get-Variable $name -ValueOnly -ErrorAction SilentlyContinue; if ($null -ne $value) { Remove-Module $value -ErrorAction SilentlyContinue } }
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
Write-Host ('PASS: DeploymentRoutes.Tests.ps1 (' + $script:assertions + ' assertions)')

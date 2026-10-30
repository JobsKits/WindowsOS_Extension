# FlutterHarmonyPackage.Tests.ps1 | 双产物鸿蒙快捷入口的隔离回归
# Created by Jobs on 2026年10月28日，星期三.
# 所有工程、日志和 worker 均为临时夹具，不构建真实工程、不写注册表。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$count = 0
function Assert-Harmony($Condition, $Message) {
    if (-not $Condition) { throw $Message }
    $script:count++
}
function Assert-HarmonyThrows([scriptblock]$Body, $Message) {
    $failed = $false
    try { & $Body | Out-Null } catch { $failed = $true }
    Assert-Harmony $failed $Message
}
function Assert-HarmonyAdaptationError([scriptblock]$Body, $Message) {
    $failure = $null
    try { & $Body | Out-Null } catch { $failure = $_.Exception.Message }
    Assert-Harmony ($null -ne $failure -and $failure.Contains('请先完成当前 Flutter 项目的鸿蒙平台适配') -and $failure.Contains('本次未启动构建')) $Message
}
# 仅删除夹具创建的目录链接，避免 5.1 Provider 询问或递归进入目标。
function Remove-HarmonyFixtureDirectoryLink {
    param([string]$Path)
    if ([string]::IsNullOrEmpty($Path)) { return }
    try { $attributes = [IO.File]::GetAttributes($Path) }
    catch [IO.FileNotFoundException] { return }
    catch [IO.DirectoryNotFoundException] { return }
    if (($attributes -band [IO.FileAttributes]::Directory) -eq 0 -or ($attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { throw '夹具链接路径已改变，保留现场。' }
    [IO.Directory]::Delete($Path, $false)
}
$base = [IO.Path]::GetTempPath()
if ([IO.Directory]::Exists('/private/tmp')) { $base = '/private/tmp' }
$temporary = Join-Path $base ('JobsHarmonyPackage-' + [guid]::NewGuid().ToString('N'))
$names = @('LOCALAPPDATA', 'BUILD_MODE', 'FLAVOR', 'OHOS_BUILD_TARGET', 'FLUTTER_OHOS_SDK')
$saved = @{}
foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$moduleLink = $null; $buildLink = $null
try {
    $env:LOCALAPPDATA = Join-Path $temporary 'Local'
    $project = Join-Path $temporary '工程 中文 & 100%'
    [void][IO.Directory]::CreateDirectory((Join-Path $project 'lib'))
    [IO.File]::WriteAllText((Join-Path $project 'pubspec.yaml'), "dependencies:`n  flutter:`n    sdk: flutter`n")
    $original = Join-Path $root 'JobsFlutterPackager/Scripts/Action.psm1'
    $bundled = Join-Path $root 'JobsFlutterTools/Scripts/Actions/package/Scripts/Action.psm1'
    $helperPattern = '(?s)function Invoke-JobsFlutterHarmonyAction \{.*?\n\}'
    $originalHelper = [regex]::Match([IO.File]::ReadAllText($original), $helperPattern).Value
    $bundledHelper = [regex]::Match([IO.File]::ReadAllText($bundled), $helperPattern).Value
    Assert-Harmony ($originalHelper.Length -gt 0 -and $originalHelper -ceq $bundledHelper) '独立打包内核与聚合副本的双产物快捷入口保持一致'
    $worker = Import-Module $bundled -PassThru -DisableNameChecking -Force
    & $worker {
        $script:Calls = @()
        $script:Answer = ''
        $script:ShouldFail = $false
        function script:Read-Host { param($Prompt) $script:Answer }
        function script:Select-JobsPackagerChoice { throw '快捷入口不能再弹平台/包型选择器' }
        function script:Invoke-JobsPackagerHarmonyBuild {
            param($Project, $Type, $Mode, $Flavor, $FlutterSdk)
            $script:Calls += [pscustomobject]@{ Project = $Project; Type = $Type; Mode = $Mode; Flavor = $Flavor; FlutterSdk = $FlutterSdk }
            if ($script:ShouldFail) { throw 'fixture APP build failed, exit 37' }
        }
    }
    Assert-HarmonyAdaptationError { & $worker { param($Path) Invoke-JobsFlutterHarmonyAction $Path } $project } '普通 Flutter 工程明确提示先适配，不开始鸿蒙打包'
    Assert-Harmony (@(& $worker { $script:Calls }).Count -eq 0) '缺 ohos 平台不调用构建'
    Assert-Harmony (-not [IO.Directory]::Exists((Join-Path $env:LOCALAPPDATA 'Jobs/WindowsExtension'))) '缺 ohos 时不创建日志或写入工程'
    $native = [IO.File]::ReadAllText((Join-Path $root 'JobsFlutterTools/Scripts/ContextMenu.cpp'))
    $query = [regex]::Match($native, '(?s)HRESULT STDMETHODCALLTYPE QueryContextMenu\(.*?HRESULT STDMETHODCALLTYPE InvokeCommand').Value
    $invoke = [regex]::Match($native, '(?s)HRESULT STDMETHODCALLTYPE InvokeCommand\(.*?HRESULT STDMETHODCALLTYPE GetCommandString').Value
    Assert-Harmony (-not $query.Contains('IsHarmonyProject')) '菜单生成不因尚无 ohos 平台隐藏已选鸿蒙动作'
    Assert-Harmony ($invoke.Contains('IsActionAvailable(index, IsHarmonyProject(target))') -and $invoke.Contains('MessageBoxW') -and $invoke.Contains('本次未启动构建')) '原生点击仍拒绝未适配项目并显示明确错误'
    $realRouter = Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/Action.psm1') -PassThru -DisableNameChecking -Force
    Assert-HarmonyAdaptationError { & $realRouter { param($Path) Invoke-JobsFeature -Target $Path -Action 'build-harmony' } $project } '直接调用聚合分发器同样拒绝未适配项目并给出说明'
    Assert-Harmony (@(& $worker { $script:Calls }).Count -eq 0) '聚合分发未适配项目不调用构建工具'
    [void][IO.Directory]::CreateDirectory((Join-Path $project 'ohos'))
    [IO.File]::WriteAllText((Join-Path $project 'ohos/build-profile.json5'), '{}')
    Assert-HarmonyAdaptationError { & $worker { param($Path) Invoke-JobsFlutterHarmonyAction $Path } $project } '缺任一鸿蒙配置文件都提示先适配并停止'
    [IO.File]::WriteAllText((Join-Path $project 'ohos/oh-package.json5'), '{}')
    Assert-HarmonyThrows { & $worker { param($Path) Invoke-JobsFlutterHarmonyAction $Path } $project } '缺项目 FVM 时不会使用全局或显式覆盖 SDK'
    [void][IO.Directory]::CreateDirectory((Join-Path $project '.fvm/flutter_sdk/bin'))
    [IO.File]::WriteAllText((Join-Path $project '.fvm/flutter_sdk/bin/flutter.bat'), 'fixture only')
    & $worker { $script:Answer = 'cancel' }
    & $worker { param($Path) Invoke-JobsFlutterHarmonyAction $Path } $project
    Assert-Harmony (@(& $worker { $script:Calls }).Count -eq 0) '非空输入取消，不开始构建'
    Assert-Harmony (-not [IO.Directory]::Exists((Join-Path $env:LOCALAPPDATA 'Jobs/WindowsExtension'))) '确认前不创建业务日志'
    & $worker { $script:Answer = $null }
    & $worker { param($Path) Invoke-JobsFlutterHarmonyAction $Path } $project
    Assert-Harmony (@(& $worker { $script:Calls }).Count -eq 0) '输入结束取消，不把 EOF 当作确认'
    $env:BUILD_MODE = 'debug'
    $env:OHOS_BUILD_TARGET = 'hap'
    $env:FLAVOR = 'production'
    $env:FLUTTER_OHOS_SDK = 'must-not-use-global-override'
    & $worker { $script:Answer = '' }
    & $worker { param($Path) Invoke-JobsFlutterHarmonyAction $Path } $project
    $calls = @(& $worker { $script:Calls })
    Assert-Harmony ($calls.Count -eq 1 -and $calls[0].Project -ceq $project -and $calls[0].Type -ceq 'all' -and $calls[0].Mode -ceq 'release' -and $calls[0].Flavor -ceq '' -and $calls[0].FlutterSdk -ceq '') '快捷入口固定 all/release/无 flavor，忽略单产物与调试环境变量'
    Assert-Harmony ($env:BUILD_MODE -ceq 'debug' -and $env:OHOS_BUILD_TARGET -ceq 'hap' -and $env:FLAVOR -ceq 'production') '固定参数不修改调用者环境变量'
    & $worker { $script:ShouldFail = $true }
    Assert-HarmonyThrows { & $worker { param($Path) Invoke-JobsFlutterHarmonyAction $Path } $project } '任一构建失败向外传播，不能报告整体成功'
    $log = & $worker { $script:PackagerLog }
    Assert-Harmony (-not ([IO.File]::ReadAllText($log).Contains('打包完成'))) '失败日志没有整体成功信息'

    $external = Join-Path $temporary 'External artifacts'
    [void][IO.Directory]::CreateDirectory((Join-Path $external 'build/default/outputs/default'))
    [IO.File]::WriteAllText((Join-Path $external 'build/default/outputs/default/external.hap'), 'external only')
    $linkKind = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'Junction' } else { 'SymbolicLink' }
    $moduleLink = Join-Path $project 'ohos/linked-module'
    New-Item -ItemType $linkKind -Path $moduleLink -Target $external | Out-Null
    Assert-HarmonyThrows { & $worker { param($Path) Get-JobsPackagerHarmonyArtifacts -Project $Path -Type 'hap' } $project } '模块目录链接中的外部包不能算作工程产物'
    Remove-HarmonyFixtureDirectoryLink $moduleLink
    Assert-Harmony (-not [IO.Directory]::Exists($moduleLink) -and [IO.File]::ReadAllText((Join-Path $external 'build/default/outputs/default/external.hap')) -ceq 'external only') '删除模块目录链接仅移除链接，外部产物完整保留'
    [void][IO.Directory]::CreateDirectory((Join-Path $external 'ohos'))
    [IO.File]::WriteAllText((Join-Path $external 'ohos/external.hap'), 'external only')
    $buildLink = Join-Path $project 'build'
    New-Item -ItemType $linkKind -Path $buildLink -Target $external | Out-Null
    Assert-HarmonyThrows { & $worker { param($Path) Get-JobsPackagerHarmonyArtifacts -Project $Path -Type 'hap' } $project } 'build/ohos 祖先目录链接不能越界采集外部包'
    Remove-HarmonyFixtureDirectoryLink $buildLink
    Assert-Harmony (-not [IO.Directory]::Exists($buildLink) -and [IO.File]::ReadAllText((Join-Path $external 'ohos/external.hap')) -ceq 'external only' -and [IO.File]::ReadAllText((Join-Path $external 'build/default/outputs/default/external.hap')) -ceq 'external only') '删除 build 链接不触及外部目录及两处产物'

    # 运行真实聚合调度，只替换临时包中的最终构建 worker，验证无需全局 SDK/兄弟包。
    $dispatch = Join-Path $temporary 'Dispatch'
    $scripts = Join-Path $dispatch 'Scripts'
    $packageScripts = Join-Path $scripts 'Actions/package/Scripts'
    [void][IO.Directory]::CreateDirectory($packageScripts)
    foreach ($name in @('Action.psm1', 'Common.psm1')) { Copy-Item -LiteralPath (Join-Path $root ('JobsFlutterTools/Scripts/' + $name)) -Destination $scripts }
    Copy-Item -LiteralPath (Join-Path $root 'JobsFlutterTools/Extension.json') -Destination $dispatch
    $stub = @'
function Invoke-JobsFlutterHarmonyAction {
    param($Target)
    [IO.File]::WriteAllText((Join-Path $Target 'dispatched.txt'), $Target)
}
Export-ModuleMember -Function Invoke-JobsFlutterHarmonyAction
'@
    [IO.File]::WriteAllText((Join-Path $packageScripts 'Action.psm1'), $stub)
    $router = Import-Module (Join-Path $scripts 'Action.psm1') -PassThru -DisableNameChecking -Force
    & $router { param($Path) Invoke-JobsFeature -Target $Path -Action 'build-harmony' } $project
    Assert-Harmony ([IO.File]::ReadAllText((Join-Path $project 'dispatched.txt')) -ceq $project) '聚合 build-harmony 正确传递精确工程，直接进入同包双产物 worker'
} finally {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
    foreach ($loaded in @(Get-Module | Where-Object { $_.Path -and $_.Path.StartsWith($temporary, [StringComparison]::OrdinalIgnoreCase) })) { Remove-Module $loaded }
    foreach ($link in @($moduleLink, $buildLink)) { Remove-HarmonyFixtureDirectoryLink $link }
    if ([IO.Directory]::Exists($temporary)) { [IO.Directory]::Delete($temporary, $true) }
}
Write-Host "PASS: FlutterHarmonyPackage.Tests.ps1 ($count assertions; isolated workers, no SDK or registry writes)"

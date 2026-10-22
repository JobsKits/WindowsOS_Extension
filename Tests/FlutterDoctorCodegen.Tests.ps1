# FlutterDoctorCodegen.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年10月22日，星期四.
# 仅临时项目、假工具及内存调用记录；不注册、不运行真实 Flutter。
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$script:assertions = 0
function Assert-Flutter { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw ('FAIL: ' + $Message) }; $script:assertions++ }
function Assert-FlutterThrows { param([scriptblock]$Body, [string]$Message); $failed = $false; try { & $Body | Out-Null } catch { $failed = $true }; Assert-Flutter $failed $Message }
$tempBase = [IO.Path]::GetTempPath()
if ([IO.Directory]::Exists('/private/tmp')) { $tempBase = '/private/tmp' }
$temporary = Join-Path $tempBase ('JobsDoctorCodegen-' + [guid]::NewGuid().ToString('N'))
$savedLocal = $env:LOCALAPPDATA
$modules = @()
try {
    [void][IO.Directory]::CreateDirectory($temporary)
    $env:LOCALAPPDATA = Join-Path $temporary 'Local'
    $project = Join-Path $temporary "Project 中文 & 100% ! [test] '"
    [void][IO.Directory]::CreateDirectory($project)
    $pubspec = Join-Path $project 'pubspec.yaml'
    $plain = "name: fixture`ndependencies:`n  flutter:`n    sdk: flutter`n"
    [IO.File]::WriteAllText($pubspec, $plain)
    foreach ($kind in @('Doctor', 'Codegen')) {
        $package = Join-Path $root ('JobsFlutter' + $kind)
        $action = Import-Module (Join-Path $package 'Scripts/Action.psm1') -PassThru -DisableNameChecking
        $modules += $action
        $fixtures = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Fixtures/FlutterRunnerPubspec.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($fixture in $fixtures) {
            Assert-Flutter ((& $action { param($Text) Test-JobsFlutterPubspec $Text } $fixture.Text) -eq $fixture.Expected) ($kind + ' 精确根项目：' + $fixture.Name)
        }
        Assert-FlutterThrows { & $action { param($Path) Assert-JobsFlutterProject $Path } $temporary } ($kind + ' 不向下扫描子工程')
        [IO.File]::WriteAllText((Join-Path $project '.fvmrc'), '{"flutter":"3.0.0"}')
        Assert-FlutterThrows { & $action { param($Path) Get-JobsFlutterSdk $Path } $project } ($kind + ' FVM 缺本地 SDK 不回退系统')
        [void][IO.Directory]::CreateDirectory((Join-Path $project '.fvm/flutter_sdk/bin'))
        foreach ($name in @('flutter.bat', 'dart.bat')) { [IO.File]::WriteAllText((Join-Path $project ('.fvm/flutter_sdk/bin/' + $name)), '@echo fake') }
        $sdk = & $action { param($Path) Get-JobsFlutterSdk $Path } $project
        Assert-Flutter ($sdk.Flutter -eq (Join-Path $project '.fvm/flutter_sdk/bin/flutter.bat') -and $sdk.Dart -eq (Join-Path $project '.fvm/flutter_sdk/bin/dart.bat')) ($kind + ' Flutter 与 Dart 同源')
        Remove-Item -LiteralPath (Join-Path $project '.fvmrc') -Force
        Remove-Item -LiteralPath (Join-Path $project '.fvm') -Recurse -Force
        $arguments = @('run', 'pigeon', '--input', "pigeons/消息 & 100%! [x] '.dart")
        $start = & $action { param($Path, $Arguments) New-JobsFlutterToolStartInfo 'C:\SDK & 100%!\dart.bat' $Arguments $Path } $project $arguments
        Assert-Flutter ($start.Arguments.Contains('/v:off') -and -not $start.Arguments.Contains('消息')) ($kind + ' CMD 使用固定命令与延迟展开关闭')
        Assert-Flutter ($start.EnvironmentVariables['JOBS_FLUTTER_ARG_3'] -ceq $arguments[3]) ($kind + ' 特殊参数经环境变量原样传递')
        Assert-FlutterThrows { & $action { New-JobsFlutterToolStartInfo 'bad"tool.bat' @('run') 'C:\' } } ($kind + ' 拒绝引号注入工具路径')
        Assert-FlutterThrows { & $action { New-JobsFlutterToolStartInfo 'tool.bat' @("bad`nline") 'C:\' } } ($kind + ' 拒绝控制字符参数')
        $installer = Import-Module (Join-Path $package 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
        $modules += $installer
        $release = Join-Path $temporary ('release-' + $kind)
        & $installer { param($Path, $Destination) New-JobsPackageRelease $Path $Destination } $package $release | Out-Null
        foreach ($name in @('ContextMenu.cpp', 'FlutterProject.h', 'ContextMenu.def', 'OpenCmd.ps1', 'Build.ps1', 'Check.ps1')) {
            Assert-Flutter (Test-Path -LiteralPath (Join-Path $release ('Scripts/' + $name)) -PathType Leaf) ($kind + ' 独立 release 包含 ' + $name)
        }
        $manifest = Get-Content -LiteralPath (Join-Path $package 'Extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $plan = @(& $installer { param($Manifest, $Release) Get-JobsPackageRegistryPlan $Manifest $Release 'powershell.exe' } $manifest $release)
        Assert-Flutter ($plan.Count -eq 4 -and @($plan | Where-Object { $_.Key -match '\\shell\\' }).Count -eq 0) ($kind + ' 仅原生动态菜单与独立 CLSID')
        Assert-Flutter ($plan[3].InProcServer -eq (Join-Path $release ('bin/JobsFlutter' + $kind + 'ContextMenu.dll'))) ($kind + ' COM 使用自身 DLL')
        $cpp = Get-Content -LiteralPath (Join-Path $package 'Scripts/ContextMenu.cpp') -Raw -Encoding UTF8
        Assert-Flutter ($cpp.Contains('L"' + $manifest.Label + '"') -and $cpp.Contains('DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0) == 1')) ($kind + ' 菜单标签与单选门禁')
        $check = Get-Content -LiteralPath (Join-Path $package 'Scripts/Check.ps1') -Raw -Encoding UTF8
        Assert-Flutter ($check -notmatch 'Invoke-JobsFlutterTool|Invoke-JobsFeature') ($kind + ' Check 不执行 SDK 或业务动作')
        & $action {
            function script:Write-JobsLog { param($Message) }
            function script:Get-JobsFlutterSdk { param($Project) [pscustomobject]@{ Flutter = 'fake-flutter'; Dart = 'fake-dart' } }
            function script:Invoke-JobsFlutterTool { param($Executable, $Arguments, $Project, $TimeoutSeconds); $script:Calls += [pscustomobject]@{ Executable = $Executable; Arguments = @($Arguments) } }
            $script:Calls = @()
        }
    }
    $codegenAnswers = $modules[2]
    Assert-FlutterThrows { & $codegenAnswers { ConvertFrom-JobsCodegenDeleteAnswer $null } } '冲突确认 EOF 必须停止，不继续 pub get'
    Assert-Flutter (-not (& $codegenAnswers { ConvertFrom-JobsCodegenDeleteAnswer '' })) '冲突确认回车不追加删除参数'
    Assert-Flutter (-not (& $codegenAnswers { ConvertFrom-JobsCodegenDeleteAnswer 'yes' })) '小写 yes 不能启用冲突删除'
    Assert-Flutter (& $codegenAnswers { ConvertFrom-JobsCodegenDeleteAnswer 'YES' }) '精确大写 YES 启用冲突删除'
    $doctor = $modules[0]
    $codegen = $modules[2]
    & $doctor { param($Path) Invoke-JobsFlutterDoctorAction $Path } $project
    $calls = @(& $doctor { $script:Calls })
    Assert-Flutter ($calls.Count -eq 2 -and ($calls[0].Arguments -join ' ') -ceq '--version' -and ($calls[1].Arguments -join ' ') -ceq 'doctor -v') '体检仅执行版本与 doctor'
    Assert-Flutter (@(& $codegen { param($Path) Get-JobsCodegenPlan $Path } $project).Count -eq 0) '普通工程没有可用生成器'
    [void][IO.Directory]::CreateDirectory((Join-Path $project 'protos'))
    [IO.File]::WriteAllText((Join-Path $project 'protos/a.proto'), 'syntax = "proto3";')
    [void][IO.Directory]::CreateDirectory((Join-Path $project 'pigeons'))
    [IO.File]::WriteAllText((Join-Path $project 'pigeons/messages.dart'), '@ConfigurePigeon(PigeonOptions(dartOut: "lib/messages.dart"))')
    Assert-Flutter (@(& $codegen { param($Path) Get-JobsCodegenPlan $Path } $project).Count -eq 0) '只有 protos/pigeons 目录不启动生成器'
    $all = $plain + @'
dev_dependencies:
  build_runner: any
  flutter_launcher_icons: any
  flutter_native_splash: any
  ffigen: any
  pigeon: any
  protobuf: any
  grpc: any
flutter:
  generate: true
flutter_launcher_icons:
  android: true
flutter_native_splash:
  color: '#ffffff'
ffigen:
  output: lib/ffi.dart
'@
    [IO.File]::WriteAllText($pubspec, $all)
    [IO.File]::WriteAllText((Join-Path $project 'l10n.yaml'), 'arb-dir: lib/l10n')
    $plan = @(& $codegen { param($Path) Get-JobsCodegenPlan $Path } $project)
    Assert-Flutter ($plan.Count -eq 7) '依赖和明确配置启用七类生成器'
    Assert-Flutter (($plan | Where-Object Name -eq 'protobuf').Arguments[0] -ceq '--dart_out=grpc:lib/generated') 'grpc 仅直接声明才启用'
    Assert-Flutter (($plan | Where-Object Name -eq 'pigeon').Arguments -notcontains '--dart_out') 'Pigeon 遵从已有输出配置，不猜文件'
    Assert-Flutter (($plan | Where-Object Name -eq 'build_runner').Arguments -notcontains '--delete-conflicting-outputs') '默认计划没有冲突删除参数'
    [IO.File]::WriteAllText((Join-Path $project 'ffigen.yaml'), 'output: lib/ffi.dart')
    $plan = @(& $codegen { param($Path) Get-JobsCodegenPlan $Path } $project)
    Assert-Flutter ((($plan | Where-Object Name -eq 'ffigen').Arguments -join ' ') -ceq 'run ffigen --config ffigen.yaml') '外置 ffigen 配置明确传参'
    [IO.File]::WriteAllText((Join-Path $project 'pigeons/messages.dart'), '@pigeon.ConfigurePigeon(PigeonOptions(dartOut: "lib/messages.dart"))')
    Assert-Flutter (@(& $codegen { param($Path) Get-JobsCodegenPlan $Path } $project).Count -eq 7) 'Pigeon 导入别名 annotation 同样作为显式配置'
    [IO.File]::WriteAllText((Join-Path $project 'pigeons/messages.dart'), '// @ConfigurePigeon(PigeonOptions())')
    Assert-Flutter (@(& $codegen { param($Path) Get-JobsCodegenPlan $Path } $project).Count -eq 6) '注释中的 Pigeon 配置不启用生成'
    [IO.File]::WriteAllText($pubspec, $plain + "dev_dependencies:`n  build_runner: any`n  build_runner: any`n")
    Assert-FlutterThrows { & $codegen { param($Path) Get-JobsCodegenPlan $Path } $project } '重复依赖键拒绝猜测'
    [IO.File]::WriteAllText($pubspec, "dependencies: {flutter: {sdk: flutter}}`ndev_dependencies: {build_runner: any, flutter_launcher_icons: any}`n")
    Assert-Flutter (@(& $codegen { param($Path) Get-JobsCodegenPlan $Path } $project).Count -eq 1) 'flow 依赖可识别，icons 缺配置跳过'
    & $codegen {
        function script:Read-JobsCodegenConsent { return $false }
        $script:Calls = @()
    }
    & $codegen { param($Path) Invoke-JobsFlutterCodegenAction $Path } $project
    Assert-Flutter (@(& $codegen { $script:Calls }).Count -eq 0) '取消发生在 pub get 之前'
    & $codegen { function script:Read-JobsCodegenConsent { return $true }; function script:Read-JobsCodegenDeleteConsent { return $false } }
    & $codegen { param($Path) Invoke-JobsFlutterCodegenAction $Path } $project
    $calls = @(& $codegen { $script:Calls })
    Assert-Flutter ($calls.Count -eq 2 -and ($calls[0].Arguments -join ' ') -ceq 'pub get') '确认后先获取依赖再生成'
    Assert-Flutter ($calls[1].Arguments -notcontains '--delete-conflicting-outputs') '未明确同意不追加冲突删除参数'
    & $codegen { function script:Read-JobsCodegenDeleteConsent { return $true }; $script:Calls = @() }
    & $codegen { param($Path) Invoke-JobsFlutterCodegenAction $Path } $project
    $calls = @(& $codegen { $script:Calls })
    Assert-Flutter ($calls[1].Arguments -contains '--delete-conflicting-outputs') '明确 YES 才追加冲突删除参数'
    & $codegen { function script:Invoke-JobsFlutterTool { param($Executable, $Arguments, $Project); $script:Calls += 'failure'; throw 'fake pub get failed' }; $script:Calls = @() }
    Assert-FlutterThrows { & $codegen { param($Path) Invoke-JobsFlutterCodegenAction $Path } $project } '获取依赖失败向上抛出错误'
    Assert-Flutter (@(& $codegen { $script:Calls }).Count -eq 1) '首步失败立即停止，不能误报后续成功'
    $actual = Import-Module (Join-Path $root 'JobsFlutterDoctor/Scripts/Action.psm1') -Force -PassThru -DisableNameChecking
    $modules += $actual
    & $actual { function script:Write-JobsLog { param($Message) } }
    $fakeTool = Join-Path $temporary 'FakeTool.ps1'
    [IO.File]::WriteAllText($fakeTool, "Write-Output 'fake stdout'`n[Console]::Error.WriteLine('fake stderr')`nexit 7`n")
    $powerShell = (Get-Process -Id $PID).Path
    Assert-FlutterThrows { & $actual { param($Exe, $Script, $Project) Invoke-JobsFlutterTool $Exe @('-NoProfile', '-File', $Script) $Project 30 } $powerShell $fakeTool $project } '假子进程 stdout/stderr 正常收集且非零退出传播'
    [IO.File]::WriteAllText($fakeTool, "Write-Output '[!] Android toolchain missing'`nWrite-Output 'Doctor found issues in 1 category.'`nexit 0`n")
    Assert-FlutterThrows { & $actual { param($Exe, $Script, $Project) Invoke-JobsFlutterTool $Exe @('-NoProfile', '-File', $Script) $Project 30 -Doctor } $powerShell $fakeTool $project } 'doctor exit 0 但诊断有问题仍失败'
    & $actual { param($Exe, $Script, $Project) Invoke-JobsFlutterTool $Exe @('-NoProfile', '-File', $Script) $Project 30 } $powerShell $fakeTool $project
    Assert-Flutter $true 'doctor 判定不误作用于其它子命令'
    $before = [IO.File]::ReadAllText($pubspec)
    $beforeFiles = @(Get-ChildItem -LiteralPath $env:LOCALAPPDATA -File -Recurse -ErrorAction SilentlyContinue).Count
    & (Join-Path $root 'JobsFlutterCodegen/Scripts/Check.ps1') -Target $project
    Assert-Flutter ([IO.File]::ReadAllText($pubspec) -ceq $before) '真实 Check 入口只读配置'
    Assert-Flutter (@(Get-ChildItem -LiteralPath $env:LOCALAPPDATA -File -Recurse -ErrorAction SilentlyContinue).Count -eq $beforeFiles) 'Check 缺配置诊断也不创建日志文件'
    Write-Host ('PASS: FlutterDoctorCodegen.Tests.ps1 (' + $script:assertions + ' assertions)')
} finally {
    foreach ($module in $modules) { Remove-Module $module -ErrorAction SilentlyContinue }
    $env:LOCALAPPDATA = $savedLocal
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}

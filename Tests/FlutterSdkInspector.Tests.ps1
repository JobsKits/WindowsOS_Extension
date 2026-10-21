# FlutterSdkInspector.Tests.ps1
# WindowsOS@Extension
# Created by Jobs on 2026年10月21日，星期三.
# 隔离夹具覆盖只读查询；不运行真实 Flutter、不安装菜单、不写注册表或联网。

[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:assertions = 0

function Assert-Inspector {
    param([bool]$Condition, [string]$Message)
    $script:assertions++
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
}
function Assert-InspectorThrows {
    param([scriptblock]$Action, [string]$Message)
    $thrown = $false
    try { & $Action | Out-Null } catch { $thrown = $true }
    Assert-Inspector $thrown $Message
}
function Write-InspectorFixture {
    param([string]$Path, [string]$Content)
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    [IO.File]::WriteAllText($Path, $Content, (New-Object Text.UTF8Encoding($false)))
}
function Get-InspectorSnapshot {
    param([string]$Path)
    return (@(Get-ChildItem -LiteralPath $Path -Recurse -File -Force | Sort-Object FullName | ForEach-Object {
        $_.FullName.Substring($Path.Length) + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }) -join "`n")
}
function New-InspectorTestSymbolicLink {
    param([string]$Path, [string]$Target, [switch]$Directory)
    # 字面路径 API 保留 [] 等特殊字符，兼容 Windows PowerShell 5.1。
    $linkType = [IO.File]
    if ($Directory) { $linkType = [IO.Directory] }
    $create = $linkType.GetMethod('CreateSymbolicLink', [type[]]@([string], [string]))
    if ($null -ne $create) {
        [void]$create.Invoke($null, [object[]]@($Path, $Target))
    }
    elseif ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        if (-not ('Jobs.InspectorTestSymbolicLink' -as [type])) {
            Add-Type -TypeDefinition @'
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace Jobs {
    public static class InspectorTestSymbolicLink {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.U1)]
        private static extern bool CreateSymbolicLinkW(string linkPath, string targetPath, uint flags);
        public static void Create(string linkPath, string targetPath, bool directory) {
            uint flags = directory ? 1u : 0u;
            if (CreateSymbolicLinkW(linkPath, targetPath, flags | 2u)) return;
            int error = Marshal.GetLastWin32Error();
            if (error == 87) {
                if (CreateSymbolicLinkW(linkPath, targetPath, flags)) return;
                error = Marshal.GetLastWin32Error();
            }
            throw new Win32Exception(error);
        }
    }
}
'@
        }
        [Jobs.InspectorTestSymbolicLink]::Create($Path, $Target, $Directory.IsPresent)
    }
    else {
        throw '当前运行时不提供符号链接 API，无法建立真实测试夹具。'
    }
    if (([IO.File]::GetAttributes($Path) -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
        throw ('符号链接夹具未正确创建：' + $Path)
    }
}
function Invoke-InspectorFixture {
    param([string]$Directory, [AllowNull()][string]$SystemFlutter, [string]$MachineOutput)
    return (& $module {
        param($Project, $Candidate, $Output)
        $script:CapturedMessages = New-Object 'System.Collections.Generic.List[string]'
        $script:CapturedCalls = New-Object 'System.Collections.Generic.List[object]'
        $script:SystemCandidate = $Candidate
        $script:FixtureMachineOutput = $Output
        function script:Write-JobsSdkMessage { param([string]$Message) $script:CapturedMessages.Add($Message) }
        function script:Find-JobsExecutable { param($Name, $Candidates) return $script:SystemCandidate }
        function script:Invoke-JobsFlutterMachine {
            param($FlutterBat, $Directory, $TimeoutSeconds)
            $script:CapturedCalls.Add([pscustomobject]@{ Flutter = $FlutterBat; Directory = $Directory })
            return $script:FixtureMachineOutput
        }
        Invoke-JobsSdkInspect -Directory $Project
        return [pscustomobject]@{ Messages = $script:CapturedMessages.ToArray(); Calls = $script:CapturedCalls.ToArray() }
    } $Directory $SystemFlutter $MachineOutput)
}

$root = Split-Path -Parent $PSScriptRoot
$testParent = [IO.Path]::GetTempPath()
if ([IO.Directory]::Exists('/private/tmp')) { $testParent = '/private/tmp' }
$temporary = Join-Path $testParent ("JobsSdkInspector [中文] '& 100% " + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$savedLocal = $env:LOCALAPPDATA
$savedUser = $env:USERPROFILE
$module = $null
try {
    $env:LOCALAPPDATA = Join-Path $temporary 'UserData'
    $env:USERPROFILE = Join-Path $temporary 'UserProfile'
    [void][IO.Directory]::CreateDirectory($env:USERPROFILE)
    $standalone = Join-Path $temporary 'JobsFlutterSdkInspector'
    Copy-Item -LiteralPath (Join-Path $root 'JobsFlutterSdkInspector') -Destination $standalone -Recurse
    $actionPath = Join-Path $standalone 'Scripts/Action.psm1'
    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($actionPath, [ref]$tokens, [ref]$parseErrors)
    Assert-Inspector (@($parseErrors).Count -eq 0) '独立 Action 模块语法正确'
    $module = Import-Module $actionPath -PassThru -DisableNameChecking

    $pubspecCases = @(
        @{ Name = 'block Flutter'; Text = "name: app`ndependencies:`n  flutter:`n    sdk: flutter`n"; Good = $true },
        @{ Name = 'flow Flutter'; Text = 'dependencies: {flutter: {sdk: flutter}}'; Good = $true },
        @{ Name = '引用键及注释'; Text = "'dependencies':`n  'flutter':`n    'sdk': 'flutter' # comment"; Good = $true },
        @{ Name = '根键大小写'; Text = 'DEPENDENCIES: {flutter: {sdk: flutter}}'; Good = $false },
        @{ Name = '纯 Dart'; Text = "name: dart_only`nenvironment: {sdk: ^3.0.0}"; Good = $false },
        @{ Name = '注释伪装'; Text = "# dependencies:`n#   flutter:`n#     sdk: flutter"; Good = $false },
        @{ Name = '描述伪装'; Text = "description: |`n  dependencies:`n    flutter:`n      sdk: flutter"; Good = $false },
        @{ Name = '只有 flutter_test'; Text = "dev_dependencies:`n  flutter_test:`n    sdk: flutter"; Good = $false },
        @{ Name = '重复根键'; Text = "dependencies: {flutter: {sdk: flutter}}`ndependencies: {flutter: {sdk: flutter}}"; Good = $false },
        @{ Name = '重复 flow flutter'; Text = 'dependencies: {flutter: {sdk: flutter}, flutter: {sdk: other}}'; Good = $false },
        @{ Name = '错误 sdk'; Text = 'dependencies: {flutter: {sdk: other}}'; Good = $false },
        @{ Name = '嵌套 sdk 伪装'; Text = "dependencies:`n  flutter:`n    nested:`n      sdk: flutter"; Good = $false },
        @{ Name = 'Tab 缩进'; Text = "dependencies:`n`tflutter: {sdk: flutter}"; Good = $false }
    )
    foreach ($case in $pubspecCases) {
        $actual = & $module { param($Text) Test-JobsFlutterPubspec $Text } $case.Text
        Assert-Inspector ($actual -eq $case.Good) ('项目门禁：' + $case.Name)
    }
    $constraints = & $module { Get-JobsEnvironmentConstraints "environment:`n  sdk: '>=3.0.0 <4.0.0'`n  flutter: ^3.22.0" }
    Assert-Inspector ($constraints.Sdk -ceq '>=3.0.0 <4.0.0' -and $constraints.Flutter -ceq '^3.22.0') 'block 约束按字段读取'
    $constraints = & $module { Get-JobsEnvironmentConstraints 'environment: {sdk: ^3.0.0, flutter: ^3.22.0}' }
    Assert-Inspector ($constraints.Sdk -ceq '^3.0.0' -and $constraints.Flutter -ceq '^3.22.0') 'flow 约束按字段读取'
    foreach ($text in @(
        'name: fixture',
        "environment: {sdk: ^3.0.0}`nenvironment: {sdk: ^4.0.0}",
        'environment: {sdk: ^3.0.0',
        "environment:`n  sdk: ^3.0.0`n  sdk: ^4.0.0",
        "environment:`n  flutter: ^3.22.0`n  flutter: ^3.24.0",
        "environment:`n  sdk: ^3.0.0`n  'sdk': ^4.0.0",
        'environment: {sdk: ^3.0.0, sdk: ^4.0.0}',
        'environment: {flutter: ^3.22.0, flutter: ^3.24.0}'
    )) {
        $actual = & $module { param($Text) Get-JobsEnvironmentConstraints $Text } $text
        Assert-Inspector ($null -eq $actual) '缺失、损坏或重复的环境约束返回未知'
    }

    $machine = & $module { ConvertFrom-JobsFlutterMachineOutput "startup`n{`"frameworkVersion`":`"3.22.0`",`"dartSdkVersion`":`"3.4.0`"}`nfinished" }
    Assert-Inspector ($machine.frameworkVersion -ceq '3.22.0' -and $machine.dartSdkVersion -ceq '3.4.0') '版本 JSON 可剥离前后普通输出'
    foreach ($text in @('{"dartSdkVersion":"3.4.0"}', '{"frameworkVersion":"invalid"}', 'plain text only')) {
        Assert-InspectorThrows { & $module { param($Text) ConvertFrom-JobsFlutterMachineOutput $Text } $text } '缺失或非法版本输出被拒绝'
    }
    $missingField = & $module { Get-JobsMachineField ([pscustomobject]@{frameworkVersion='3.22.0'}) 'channel' }
    Assert-Inspector ($missingField -ceq '') '缺少可选版本字段时返回空串'

    # Dart Pub 的 0.x caret 上界为下一次版本：https://dart.dev/tools/pub/dependencies#caret-syntax。
    $versionCases = @(
        @{ Constraint = '^3.2.0'; Actual = '3.2.0'; Expected = '满足' },
        @{ Constraint = '^3.2.0'; Actual = '3.99.0'; Expected = '满足' },
        @{ Constraint = '^3.2.0'; Actual = '4.0.0'; Expected = '不满足' },
        @{ Constraint = '>=3.2.0 <4.0.0'; Actual = '3.2.0'; Expected = '满足' },
        @{ Constraint = '>=3.2.0 <4.0.0'; Actual = '4.0.0'; Expected = '不满足' },
        @{ Constraint = '>3.2.0'; Actual = '3.2.0'; Expected = '不满足' },
        @{ Constraint = '<=3.2.0'; Actual = '3.2.0'; Expected = '满足' },
        @{ Constraint = '^0.2.3'; Actual = '0.2.2'; Expected = '不满足' },
        @{ Constraint = '^0.2.3'; Actual = '0.2.3'; Expected = '满足' },
        @{ Constraint = '^0.2.3'; Actual = '0.2.99'; Expected = '满足' },
        @{ Constraint = '^0.2.3'; Actual = '0.3.0'; Expected = '不满足' },
        @{ Constraint = '^0.2.3'; Actual = '0.9.0'; Expected = '不满足' },
        @{ Constraint = '^0.0.3'; Actual = '0.0.99'; Expected = '满足' },
        @{ Constraint = '^0.0.3'; Actual = '0.1.0'; Expected = '不满足' },
        @{ Constraint = '^3.2.0'; Actual = '3.3.0-beta.1'; Expected = '未知' },
        @{ Constraint = '^3.2.0-beta.1'; Actual = '3.3.0'; Expected = '未知' },
        @{ Constraint = '>=3.0.0 || <2.0.0'; Actual = '3.3.0'; Expected = '未知' },
        @{ Constraint = '*'; Actual = '3.3.0'; Expected = '无约束' }
    )
    foreach ($case in $versionCases) {
        $actual = & $module { param($Constraint, $Actual) Test-JobsVersionConstraint -Name fixture -Constraint $Constraint -ActualText $Actual } $case.Constraint $case.Actual
        Assert-Inspector ($actual.Outcome -ceq $case.Expected) ('版本范围：' + $case.Constraint + ' / ' + $case.Actual)
    }

    $configProject = Join-Path $temporary 'Config project'
    [void][IO.Directory]::CreateDirectory($configProject)
    & $module { function script:Write-JobsSdkMessage { param([string]$Message) } }
    $pinned = & $module { param($Path) Get-JobsProjectFvmPinned $Path } $configProject
    Assert-Inspector ($null -eq $pinned) '没有 FVM 配置时返回空'
    Write-InspectorFixture (Join-Path $configProject '.fvm/fvm_config.json') '{"flutterSdkVersion":"3.19.0"}'
    $pinned = & $module { param($Path) Get-JobsProjectFvmPinned $Path } $configProject
    Assert-Inspector ($pinned -ceq '3.19.0') '兼容旧 FVM 版本字段'
    Write-InspectorFixture (Join-Path $configProject '.fvmrc') '{"flutter":"3.22.0"}'
    $pinned = & $module { param($Path) Get-JobsProjectFvmPinned $Path } $configProject
    Assert-Inspector ($pinned -ceq '3.22.0') '新版 .fvmrc 优先'
    foreach ($text in @('[]', '{bad-json')) {
        Write-InspectorFixture (Join-Path $configProject '.fvmrc') $text
        Assert-InspectorThrows { & $module { param($Path) Get-JobsProjectFvmPinned $Path } $configProject } '拒绝数组及损坏的 FVM 配置'
    }

    $systemSdk = Join-Path $temporary 'System SDK/bin/flutter.bat'
    Write-InspectorFixture $systemSdk 'fixture only; never executed'
    $machineOutput = '{"frameworkVersion":"3.22.0","dartSdkVersion":"3.4.0","channel":"stable"}'
    $project = Join-Path $temporary "Flutter project [中文] '& 100%"
    $goodPubspec = "name: fixture`nenvironment:`n  sdk: '>=3.0.0 <4.0.0'`n  flutter: ^3.22.0`ndependencies:`n  flutter:`n    sdk: flutter`n"
    Write-InspectorFixture (Join-Path $project 'pubspec.yaml') $goodPubspec
    Write-InspectorFixture (Join-Path $project 'lib/main.dart') 'fixture remains byte-identical'
    $before = Get-InspectorSnapshot $project
    $result = Invoke-InspectorFixture $project $systemSdk $machineOutput
    Assert-Inspector ($result.Calls.Count -eq 1 -and $result.Calls[0].Flutter -ceq $systemSdk) '没有项目 SDK 时只查询系统 SDK 一次'
    Assert-Inspector ($result.Calls[0].Directory -ceq $project) '特殊路径原样传到查询函数'
    Assert-Inspector (($result.Messages -join "`n").Contains('系统 Flutter SDK')) '查询结果说明系统 SDK 来源'
    Assert-Inspector ((Get-InspectorSnapshot $project) -ceq $before) '系统查询后项目文件清单和 SHA 不变'

    Write-InspectorFixture (Join-Path $project '.fvmrc') '{"flutter":"3.19.0"}'
    $before = Get-InspectorSnapshot $project
    $result = Invoke-InspectorFixture $project $systemSdk $machineOutput
    Assert-Inspector ($result.Calls[0].Flutter -ceq $systemSdk) 'FVM 已配置但 SDK 未链接时回退系统 SDK'
    Assert-Inspector (($result.Messages -join "`n").Contains('尚未链接或不可用')) '未链接时明确提醒配置与实际来源的差异'
    Assert-Inspector ((Get-InspectorSnapshot $project) -ceq $before) 'FVM 回退不修改配置及项目文件'

    $fvmFlutter = Join-Path (Join-Path $project '.fvm\flutter_sdk') 'bin\flutter.bat'
    Write-InspectorFixture $fvmFlutter 'fixture only; never executed'
    $before = Get-InspectorSnapshot $project
    $result = Invoke-InspectorFixture $project $systemSdk $machineOutput
    Assert-Inspector ($result.Calls[0].Flutter -ceq $fvmFlutter) '项目 FVM SDK 优先于系统候选'
    Assert-Inspector (($result.Messages -join "`n").Contains('FVM 项目 SDK')) '查询结果说明项目 SDK 来源'
    Assert-Inspector ((Get-InspectorSnapshot $project) -ceq $before) '项目 SDK 查询后文件清单和 SHA 不变'

    $missingSdkProject = Join-Path $temporary 'No SDK project'
    Write-InspectorFixture (Join-Path $missingSdkProject 'pubspec.yaml') $goodPubspec
    $before = Get-InspectorSnapshot $missingSdkProject
    Assert-InspectorThrows { Invoke-InspectorFixture $missingSdkProject $null $machineOutput } '找不到 SDK 时停止'
    Assert-Inspector ((& $module { $script:CapturedCalls.Count }) -eq 0) '缺少 SDK 不执行版本查询'
    Assert-Inspector ((Get-InspectorSnapshot $missingSdkProject) -ceq $before) '缺少 SDK 不修改项目'
    $badProject = Join-Path $temporary 'Pure Dart project'
    Write-InspectorFixture (Join-Path $badProject 'pubspec.yaml') 'name: only_dart'
    $before = Get-InspectorSnapshot $badProject
    Assert-InspectorThrows { Invoke-InspectorFixture $badProject $systemSdk $machineOutput } '非法项目在 SDK 查询前停止'
    Assert-Inspector ((& $module { $script:CapturedCalls.Count }) -eq 0) '项目校验失败不执行版本查询'
    Assert-Inspector ((Get-InspectorSnapshot $badProject) -ceq $before) '项目校验失败后文件不变'

    $directory = & $module { param($Path) Assert-JobsSdkDirectory $Path } $project
    Assert-Inspector ($directory -ceq $project) '普通绝对项目目录可查询'
    Assert-InspectorThrows { & $module { Assert-JobsSdkDirectory 'relative-project' } } '拒绝相对目录'
    # 所有链接目标都在本次临时目录内，不通过 PowerShell 路径模式解析目标。
    $linkedProject = Join-Path $temporary 'Linked project'
    New-InspectorTestSymbolicLink -Path $linkedProject -Target $project -Directory
    Assert-InspectorThrows { & $module { param($Path) Assert-JobsSdkDirectory $Path } $linkedProject } '拒绝链接项目目录'
    $linkedConfig = Join-Path $temporary 'linked-config.json'
    New-InspectorTestSymbolicLink -Path $linkedConfig -Target (Join-Path $project '.fvmrc')
    Assert-InspectorThrows { & $module { param($Path) Assert-JobsSdkPlainFile $Path } $linkedConfig } '拒绝链接配置文件'
    Write-Host ('PASS: FlutterSdkInspector.Tests.ps1 (' + $script:assertions + ' assertions; fixtures only)')
}
finally {
    if ($null -ne $module) { Remove-Module $module }
    $env:LOCALAPPDATA = $savedLocal
    $env:USERPROFILE = $savedUser
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}

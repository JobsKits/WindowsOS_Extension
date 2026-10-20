# FlutterDependencyExtractor.Tests.ps1 | 临时夹具与参数边界
# Created by Jobs on 2026年10月19日，星期一.
# 不运行菜单安装器、不写注册表、不联网、不修改真实 Flutter 项目。
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:assertions = 0
function Assert-Extractor {
    param([bool]$Condition, [string]$Message)
    $script:assertions++
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
}
function Assert-ExtractorThrows {
    param([scriptblock]$Action, [string]$Message)
    $threw = $false
    try { & $Action | Out-Null } catch { $threw = $true }
    Assert-Extractor $threw $Message
}
$root = Split-Path -Parent $PSScriptRoot
$testParent = [IO.Path]::GetTempPath()
if ([IO.Directory]::Exists('/private/tmp')) { $testParent = '/private/tmp' }
$temporary = Join-Path $testParent ("Jobs Extract [中文] & 100% ! ' " + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$savedLocal = $env:LOCALAPPDATA
$module = $null
try {
    $env:LOCALAPPDATA = Join-Path $temporary 'State'
    $standalone = Join-Path $temporary 'JobsFlutterDependencyExtractor'
    Copy-Item -LiteralPath (Join-Path $root 'JobsFlutterDependencyExtractor') -Destination $standalone -Recurse
    $module = Import-Module (Join-Path $standalone 'Scripts/Action.psm1') -PassThru -DisableNameChecking
    $project = Join-Path $temporary "Flutter 工程 & 100% ! '"
    [void][IO.Directory]::CreateDirectory($project)
    $good = "name: app`ndependencies:`n  flutter:`n    sdk: flutter`n"
    $cases = @(
        @{ Text = $good; Good = $true },
        @{ Text = 'dependencies: {flutter: {sdk: flutter}}'; Good = $true },
        @{ Text = "'dependencies':`n  'flutter':`n    'sdk': 'flutter' # 尾注释"; Good = $true },
        @{ Text = "dev_dependencies:`n  flutter_test:`n    sdk: flutter"; Good = $false },
        @{ Text = "description: |`n  dependencies:`n    flutter:`n      sdk: flutter"; Good = $false },
        @{ Text = "# dependencies:`n#   flutter:`n#     sdk: flutter"; Good = $false },
        @{ Text = "dependencies:`n  flutter:`n    path: ../flutter`n  other:`n    sdk: flutter"; Good = $false },
        @{ Text = "dependencies:`n  flutter:`n    nested:`n      sdk: flutter"; Good = $false },
        @{ Text = 'dependencies: {flutter: {sdk: flutter}, flutter: {sdk: other}}'; Good = $false },
        @{ Text = "dependencies:`n  flutter: *alias"; Good = $false }
    )
    foreach ($case in $cases) {
        Assert-Extractor ((& $module { param($Text) Test-JobsFlutterPubspec $Text } $case.Text) -eq $case.Good) 'Flutter 根清单真实声明和伪装区分'
    }
    [IO.File]::WriteAllText((Join-Path $project 'pubspec.yaml'), $good)
    & $module { param($Path) Assert-JobsFlutterProject $Path } $project
    Assert-ExtractorThrows { & $module { param($Path) Assert-JobsFlutterProject $Path } $temporary } '不沿父子目录猜测 Flutter 项目'
    Assert-ExtractorThrows { & $module { Assert-JobsExtractorDirectory 'relative' } } '项目必须绝对路径'
    Assert-Extractor ((& $module { param($Default) ConvertFrom-JobsExtractorPathInput '' $Default } $temporary) -eq $temporary) '空行精确采用传入的系统桌面默认值'
    Assert-Extractor ((& $module { param($Path) ConvertFrom-JobsExtractorPathInput ('"' + $Path + '"') 'unused' } $project) -eq $project) '双引号拖入路径'
    Assert-Extractor ((& $module { param($Path) ConvertFrom-JobsExtractorPathInput ("& '" + $Path.Replace("'", "''") + "'") 'unused' } $project) -eq $project) '单引号拖入只解外层表示，保留单引号'
    Assert-ExtractorThrows { & $module { ConvertFrom-JobsExtractorPathInput 'Get-ChildItem; whoami' 'unused' } } '命令文本不能作为输出路径执行'
    Assert-ExtractorThrows { & $module { ConvertFrom-JobsExtractorPathInput "`n" 'unused' } } '控制字符拒绝'
    $safe = & $module { ConvertTo-JobsExtractorSafeMessage 'https://user:pass@example.invalid/pkg?token=SECRET password=HIDDEN' }
    Assert-Extractor ($safe -notmatch 'user:pass|SECRET|HIDDEN') '终端与日志地址凭据脱敏'
    # SDK 原生路径发现兼容项目 FVM 和 package_config 指向的 IDE SDK。
    $sdk = Join-Path $temporary 'IDE Flutter SDK'
    [void][IO.Directory]::CreateDirectory((Join-Path $sdk 'packages/flutter'))
    [void][IO.Directory]::CreateDirectory((Join-Path $project '.dart_tool'))
    $sdkUri = (New-Object Uri ((Join-Path $sdk 'packages/flutter') + [IO.Path]::DirectorySeparatorChar)).AbsoluteUri
    @{ configVersion = 2; packages = @(@{ name = 'flutter'; rootUri = $sdkUri }) } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $project '.dart_tool/package_config.json') -Encoding UTF8
    $candidates = @(& $module { param($Path) Get-JobsExtractorDartCandidates $Path } $project)
    Assert-Extractor ($candidates[0] -ceq (Join-Path $project '.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dart.exe')) '项目 FVM SDK 先于全局 SDK'
    Assert-Extractor ((Join-Path $sdk 'bin/cache/dart-sdk/bin/dart.exe') -in $candidates) 'IDE 独立 SDK 可由包配置定位'
    $brokenDart = Join-Path $temporary 'broken-dart.exe'
    $healthyDart = Join-Path $temporary 'healthy-dart.exe'
    $spoof = Join-Path $temporary 'renamed-script.exe'
    [IO.File]::WriteAllText($spoof, '@echo off')
    Assert-Extractor (-not (& $module { param($Path) Test-JobsExtractorNativeExecutable $Path } $spoof)) '重命名脚本不能冒充原生 PE 程序'
    $pe = New-Object byte[] 128
    $pe[0] = 0x4D; $pe[1] = 0x5A; $pe[0x3C] = 0x40
    $pe[0x40] = 0x50; $pe[0x41] = 0x45; $pe[0x44] = 0x64; $pe[0x45] = 0x86
    [IO.File]::WriteAllBytes($brokenDart, $pe)
    [IO.File]::WriteAllBytes($healthyDart, $pe)
    Assert-Extractor (& $module { param($Path) Test-JobsExtractorNativeExecutable $Path } $healthyDart) 'PE 签名和机器类型通过后才允许版本体检'
    $chosen = & $module {
        param($Project, $Broken, $Healthy)
        $script:ProbeCandidates = @($Broken, $Healthy)
        function script:Get-JobsExtractorDartCandidates { param($Directory) return $script:ProbeCandidates }
        function script:Invoke-JobsProcess {
            param($FilePath, $Arguments, $WorkingDirectory, $TimeoutSeconds)
            if ($Arguments.Count -ne 1 -or $Arguments[0] -cne '--version') { throw '体检只允许 --version' }
            if ($FilePath -eq $script:ProbeCandidates[0]) { return [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = 'broken' } }
            return [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = 'Dart SDK version: 3.9.0 (stable)' }
        }
        Find-JobsExtractorDart $Project
    } $project $brokenDart $healthyDart
    Assert-Extractor ($chosen -ceq $healthyDart) '损坏工具跳过，复用下一个健康原生 Dart'
    & $module { $script:ProbeCandidates = @() }
    Assert-ExtractorThrows { & $module { param($Path) Find-JobsExtractorDart $Path } $project } '缺健康 Dart 明确停止不安装'
    # 取消是行为边界，不能创建日志、探测工具或写项目。
    $canceled = & $module {
        param($Path)
        function script:Show-JobsExtractorIntro { return $false }
        function script:Find-JobsExtractorDart { throw '取消后不应探测 Dart' }
        Invoke-JobsFlutterDependencyAction $Path
    } $project
    Assert-Extractor (-not (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Jobs'))) '首屏取消不创建业务状态'
    # 无解析记录先停止，不弹出目标路径输入或调用提取引擎。
    & $module {
        function script:Show-JobsExtractorIntro { return $true }
        function script:Read-Host { param($Prompt) throw '缺记录时不应请求输出目录' }
    }
    Assert-ExtractorThrows { & $module { param($Path) Invoke-JobsFlutterDependencyAction $Path } $project } '缺少 lock/config 时停止'
    [IO.File]::WriteAllText((Join-Path $project 'pubspec.lock'), "packages: {}`n")
    [void][IO.Directory]::CreateDirectory((Join-Path $project '.dart_tool'))
    [IO.File]::WriteAllText((Join-Path $project '.dart_tool/package_config.json'), '{"configVersion":2,"packages":[]}')
    $recorded = & $module {
        param($Project, $Destination)
        function script:Get-JobsExtractorDesktop { return $script:TestDestination }
        function script:Read-Host { param($Prompt) return '' }
        function script:Find-JobsExtractorDart { param($Directory) return 'dart-native.exe' }
        function script:Invoke-JobsProcess {
            param($FilePath, $Arguments, $WorkingDirectory, $TimeoutSeconds)
            $script:Captured = [pscustomobject]@{ File = $FilePath; Arguments = @($Arguments); WorkingDirectory = $WorkingDirectory }
            return [pscustomobject]@{ ExitCode = 0; StdOut = 'fixture complete'; StdErr = '' }
        }
        $script:TestDestination = $Destination
        Invoke-JobsFlutterDependencyAction $Project
        return $script:Captured
    } $project $temporary
    Assert-Extractor ($recorded.File -ceq 'dart-native.exe') '引擎用原生 Dart 调用'
    Assert-Extractor ($recorded.Arguments.Count -eq 5 -and $recorded.Arguments[1] -ceq '--project' -and $recorded.Arguments[2] -ceq $project -and $recorded.Arguments[3] -ceq '--destination' -and $recorded.Arguments[4] -ceq $temporary) '项目与输出各自原样作为独立 argv，默认桌面生效'
    Assert-Extractor ($recorded.WorkingDirectory -ceq $project) '提取引擎工作目录精确到所选项目'
    & $module {
        function script:Invoke-JobsProcess {
            param($FilePath, $Arguments, $WorkingDirectory, $TimeoutSeconds)
            return [pscustomobject]@{ ExitCode = 4; StdOut = ''; StdErr = 'fixture failure' }
        }
    }
    Assert-ExtractorThrows { & $module { param($Path) Invoke-JobsFlutterDependencyAction $Path } $project } '引擎非零退出不能报告成功'
    # 独立安装 release 必须携带真正的 Dart 源码，而非只复制 PowerShell 入口。
    $installer = Import-Module (Join-Path $standalone 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
    $release = Join-Path $temporary 'release'
    & $installer { param($Path, $Destination) New-JobsPackageRelease -PackagePath $Path -Destination $Destination } $standalone $release | Out-Null
    $engine = Join-Path $release 'Scripts/ExtractFlutterDependencies.dart'
    Assert-Extractor (Test-Path -LiteralPath $engine -PathType Leaf) '独立 release 含 Dart 引擎'
    Assert-Extractor ((Get-FileHash -LiteralPath $engine).Hash -ceq (Get-FileHash -LiteralPath (Join-Path $standalone 'Scripts/ExtractFlutterDependencies.dart')).Hash) '部署引擎逐字节一致'
    # 使用真实原生进程回传参数，验证 Common argv 遇中文、空格、引号和 Shell 符号仍是数据。
    $argvScript = Join-Path $temporary 'argv.ps1'
    $argvSource = @'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
[Console]::Write((ConvertTo-Json -InputObject @($args) -Compress))
'@
    [IO.File]::WriteAllText($argvScript, $argvSource, (New-Object Text.UTF8Encoding($true)))
    $shell = Join-Path $PSHOME 'pwsh'
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { $shell = Join-Path $PSHOME 'powershell.exe' }
    $common = Import-Module (Join-Path $standalone 'Scripts/Common.psm1') -PassThru -DisableNameChecking
    $special = @($project, (Join-Path $temporary 'a"b'), '--destination', (Join-Path $temporary '$(whoami); & %PATH% !'))
    $native = & $common { param($Shell, $Script, $Values, $Directory) Invoke-JobsProcess -FilePath $Shell -Arguments (@('-NoLogo', '-NoProfile', '-File', $Script) + $Values) -WorkingDirectory $Directory } $shell $argvScript $special $temporary
    Assert-Extractor ($native.ExitCode -eq 0) '真实原生进程回传成功'
    $decoded = $native.StdOut | ConvertFrom-Json
    $actual = @($decoded)
    Assert-Extractor ($actual.Count -eq $special.Count) '原生参数数量保持'
    for ($i = 0; $i -lt $special.Count; $i++) { Assert-Extractor ($actual[$i] -ceq $special[$i]) '特殊字符未经 Shell 展开'
    }
    Write-Host ('PASS: FlutterDependencyExtractor.Tests.ps1 (' + $script:assertions + ' assertions)')
} finally {
    if ($null -ne $module) { Remove-Module $module }
    foreach ($loaded in @(Get-Module | Where-Object { $_.Path -and $_.Path.StartsWith($temporary, [StringComparison]::OrdinalIgnoreCase) })) { Remove-Module $loaded }
    $env:LOCALAPPDATA = $savedLocal
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}

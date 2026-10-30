# FlutterDependencyImporter.Tests.ps1 | 导出目录识别、预览和精确确认
# Created by Jobs on 2026年10月28日，星期三.
# 只使用临时目录和假 Dart；不注册菜单、不联网、不改用户工程或 SDK。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$count = 0
function Assert($Value, [string]$Message) { $script:count++; if (-not $Value) { throw $Message } }
function Assert-Throws([scriptblock]$Body, [string]$Message) {
    $failed = $false
    try { & $Body | Out-Null } catch { $failed = $true }
    Assert $failed $Message
}
$temporaryBase = [IO.Path]::GetTempPath()
if ([Environment]::OSVersion.Platform -eq [PlatformID]::Unix -and [IO.Directory]::Exists('/private/tmp')) { $temporaryBase = '/private/tmp' }
$temporary = Join-Path $temporaryBase ('jobs-flutter-import-' + [guid]::NewGuid().ToString('N'))
$savedLocal = $env:LOCALAPPDATA
$module = $null
try {
    [void][IO.Directory]::CreateDirectory($temporary)
    $env:LOCALAPPDATA = Join-Path $temporary 'state'
    $worker = Join-Path $root 'JobsFlutterTools/Scripts/Actions/import-dependencies'
    $module = Import-Module (Join-Path $worker 'Scripts/Action.psm1') -PassThru -DisableNameChecking
    $project = Join-Path $temporary '目标 工程'
    $source = Join-Path $temporary '依赖 $(whoami); & %PATH% !'
    foreach ($directory in @($project, (Join-Path $source 'packages'))) { [void][IO.Directory]::CreateDirectory($directory) }
    [IO.File]::WriteAllText((Join-Path $project 'pubspec.yaml'), "name: demo`ndependencies:`n  flutter:`n    sdk: flutter`n")
    foreach ($name in @('pubspec.yaml', 'pubspec.lock')) { [IO.File]::WriteAllText((Join-Path $source $name), '') }
    $complete = '{"formatVersion":1,"status":"complete","packages":[]}'
    [IO.File]::WriteAllText((Join-Path $source 'manifest.json'), $complete)
    foreach ($text in @($source, ('"' + $source + '"'), ("& '" + $source + "'"))) {
        Assert ((& $module { param($Text) ConvertFrom-JobsImporterPathInput $Text } $text) -ceq $source) '拖入引号及 Shell 符号按路径原样读取'
    }
    # 真实导出目录后粘入 ASCII / NBSP / 窄不换行空格，不能破坏目录识别。
    foreach ($padding in @(' ', [string][char]0x00A0, [string][char]0x202F)) {
        foreach ($text in @(($padding + $source + $padding), ($padding + '"' + $source + '"' + $padding))) {
            $resolved = & $module { param($Text) ConvertFrom-JobsImporterPathInput $Text } $text
            Assert ($resolved -ceq $source) '路径或外层双引号之外的 Unicode 空白被去除'
            $recognized = & $module { param($Path) Assert-JobsImporterSource $Path; return $true } $resolved
            Assert $recognized '去除输入外侧空白后真实存在的导出目录可识别'
        }
    }
    # 引号内部的边界字符属于文件名；尤其 NBSP 是合法文件名字符，不能再次 Trim。
    $literalBoundarySource = Join-Path $temporary (' 名称边界保留' + [char]0x00A0)
    # 5.1 的 FileSystem Provider 会裁剪目标尾部空白；用字面文件 API 保留真实目录名。
    [void][IO.Directory]::CreateDirectory((Join-Path $literalBoundarySource 'packages'))
    foreach ($name in @('pubspec.yaml', 'pubspec.lock', 'manifest.json')) {
        [IO.File]::Copy((Join-Path $source $name), (Join-Path $literalBoundarySource $name))
    }
    foreach ($text in @(('"' + $literalBoundarySource + '"'), ("'" + $literalBoundarySource + "'"))) {
        $resolved = & $module { param($Text) ConvertFrom-JobsImporterPathInput $Text } $text
        Assert ($resolved -ceq $literalBoundarySource) '引号内真实文件名前导空格及末尾 NBSP 保持原字节'
        $recognized = & $module { param($Path) Assert-JobsImporterSource $Path; return $true } $resolved
        Assert $recognized '保留真实文件名边界后仍识别对应导出目录'
    }
    $literalDirectory = & $module { param($Path) Assert-JobsImporterDirectory $Path } $literalBoundarySource
    Assert ($literalDirectory -ceq $literalBoundarySource) '目录存在性与逐层链接检查同样保持真实边界字符'
    $withDot = '"' + $literalBoundarySource + [IO.Path]::DirectorySeparatorChar + '."'
    Assert ((& $module { param($Text) ConvertFrom-JobsImporterPathInput $Text } $withDot) -ceq $literalBoundarySource) '正规化点路径不裁剪原目录末尾 NBSP'
    $filesystemRoot = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($temporary))
    Assert ((& $module { param($Text) ConvertFrom-JobsImporterPathInput $Text } ('"' + $filesystemRoot + '"')) -ceq $filesystemRoot) '盘符或文件系统根保留必要的末尾分隔符'
    $sourceLink = Join-Path $temporary 'linked-export'
    $linkKind = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'Junction' } else { 'SymbolicLink' }
    New-Item -ItemType $linkKind -Path $sourceLink -Target $source | Out-Null
    try {
        Assert-Throws { & $module { param($Path) Assert-JobsImporterSource $Path } $sourceLink } '字面目录寻址仍拒绝导出目录本身的链接'
        Assert-Throws { & $module { param($Path) Assert-JobsImporterDirectory $Path } (Join-Path $sourceLink 'packages') } '逐层检查仍拒绝链接祖先，不越界到目标子目录'
    } finally { [IO.Directory]::Delete($sourceLink, $false) }
    Assert-Throws { & $module { ConvertFrom-JobsImporterPathInput 'relative/packages' } } '相对路径不是依赖导出目录'
    Assert-Throws { & $module { ConvertFrom-JobsImporterPathInput '' } } '路径解析器不使用默认目录误导入'
    & $module { param($Source) Assert-JobsImporterSource $Source } $source
    foreach ($manifest in @('{', '{"formatVersion":2,"status":"complete","packages":[]}', '{"formatVersion":1,"status":"partial","packages":[]}', '{"formatVersion":1,"status":"complete","packages":{}}')) {
        [IO.File]::WriteAllText((Join-Path $source 'manifest.json'), $manifest)
        Assert-Throws { & $module { param($Source) Assert-JobsImporterSource $Source } $source } '不完整或畸形导出清单拒绝'
    }
    [IO.File]::WriteAllText((Join-Path $source 'manifest.json'), $complete)
    Assert-Throws { & $module { param($Project) Assert-JobsImporterSource $Project } $project } '普通 Flutter 工程不能冒充导出目录'
    & $module {
        $script:Responses = New-Object 'Collections.Generic.Queue[object]'
        $script:Calls = New-Object 'Collections.Generic.List[object]'
        $script:ValidationExit = 0
        $script:WriteExit = 0
        $script:DartProbes = 0
        function script:Read-Host {
            param($Prompt)
            if ($script:Responses.Count -eq 0) { throw ('不应出现额外询问：' + $Prompt) }
            return $script:Responses.Dequeue()
        }
        function script:Read-JobsImporterSourceInput { param($Prompt) return Read-Host $Prompt }
        function script:Find-JobsImporterDart {
            param($Directory)
            $script:DartProbes++
            return 'fixture-native-dart.exe'
        }
        function script:Invoke-JobsProcess {
            param($FilePath, $Arguments, $WorkingDirectory, $TimeoutSeconds)
            $script:Calls.Add([pscustomobject]@{ File = $FilePath; Arguments = @($Arguments); Directory = $WorkingDirectory })
            $code = if ($Arguments -contains '--validate-only') { $script:ValidationExit } else { $script:WriteExit }
            return [pscustomobject]@{ ExitCode = $code; StdOut = 'fixture plan/result'; StdErr = '' }
        }
    }
    & $module {
        param($Project)
        $script:Responses.Enqueue('')
        $script:Responses.Enqueue('   ')
        $script:Responses.Enqueue($null)
        Invoke-JobsFlutterDependencyImport $Project
    } $project
    Assert ((& $module { $script:DartProbes }) -eq 0 -and -not [IO.Directory]::Exists($env:LOCALAPPDATA)) '连续空白后 EOF 退出，不探测 SDK 或创建业务状态'
    & $module {
        param($Source)
        $script:Responses.Enqueue('')
        $script:Responses.Enqueue("`t  ")
        $script:Responses.Enqueue($Source)
        $script:ValidationExit = 3
    } $source
    Assert-Throws { & $module { param($Project) Invoke-JobsFlutterDependencyImport $Project } $project } '核心识别失败直接停止，不要求确认或执行写入'
    $calls = @(& $module { $script:Calls.ToArray() })
    Assert ($calls.Count -eq 1 -and $calls[0].Arguments[-1] -ceq '--validate-only') '多次空白后有效目录进入预检，第一次核心调用仅校验'
    foreach ($cancel in @('', 'yes', 'YES ', 'cancel')) {
        & $module {
            param($Source, $Cancel)
            $script:Calls.Clear()
            $script:ValidationExit = 0
            $script:Responses.Enqueue($Source)
            $script:Responses.Enqueue($Cancel)
        } $source $cancel
        & $module { param($Project) Invoke-JobsFlutterDependencyImport $Project } $project
        $calls = @(& $module { $script:Calls.ToArray() })
        Assert ($calls.Count -eq 1 -and $calls[0].Arguments[-1] -ceq '--validate-only') '非精确 YES 只校验，不执行导入'
    }
    & $module {
        param($Source)
        $script:Calls.Clear()
        $script:Responses.Enqueue(('"' + $Source + '"'))
        $script:Responses.Enqueue('YES')
    } $source
    & $module { param($Project) Invoke-JobsFeature -Target $Project } $project
    $calls = @(& $module { $script:Calls.ToArray() })
    Assert ($calls.Count -eq 2) '精确 YES 后仅再调用一次实际导入'
    Assert ($calls[0].Arguments.Count -eq 6 -and $calls[0].Arguments[-1] -ceq '--validate-only') '预览参数只增加 validate-only'
    Assert ($calls[1].Arguments.Count -eq 5 -and $calls[1].Arguments[1] -ceq '--project' -and $calls[1].Arguments[2] -ceq $project -and $calls[1].Arguments[3] -ceq '--source' -and $calls[1].Arguments[4] -ceq $source) '特殊路径独立 argv 原样传给写入核心'
    Assert ($calls[1].File -ceq 'fixture-native-dart.exe' -and $calls[1].Directory -ceq $project) '只用所选项目 Dart 与工作目录'
    # 私库入口复用相同路径 / 确认门禁，预检和写入都必须向核心透传私库类型。
    foreach ($answer in @('', 'YES')) {
        & $module {
            param($Source, $Answer)
            $script:Calls.Clear()
            $script:Responses.Enqueue(('"' + $Source + '"'))
            $script:Responses.Enqueue($Answer)
        } $literalBoundarySource $answer
        & $module { param($Project) Invoke-JobsFeature -Target $Project -PrivateOnly } $project
        $privateCalls = @(& $module { $script:Calls.ToArray() })
        $expectedCalls = if ($answer -ceq 'YES') { 2 } else { 1 }
        Assert ($privateCalls.Count -eq $expectedCalls) '私库入口仍只在精确 YES 后执行第二次写入调用'
        foreach ($call in $privateCalls) {
            Assert (@($call.Arguments | Where-Object { $_ -ceq '--private-only' }).Count -eq 1 -and $call.Arguments[4] -ceq $literalBoundarySource) '私库预检和写入各传一次类型开关，NBSP 来源路径保持原字节'
        }
        Assert ($privateCalls[0].Arguments[-1] -ceq '--validate-only') '私库首次核心调用始终只预检'
    }
    & $module {
        param($Source)
        $script:Calls.Clear()
        $script:Responses.Enqueue(('"' + $Source + '"'))
        $script:Responses.Enqueue('YES')
    } $literalBoundarySource
    & $module { param($Project) Invoke-JobsFlutterDependencyImport $Project } $project
    $literalCalls = @(& $module { $script:Calls.ToArray() })
    Assert ($literalCalls.Count -eq 2 -and $literalCalls[0].Arguments[4] -ceq $literalBoundarySource -and $literalCalls[1].Arguments[4] -ceq $literalBoundarySource) '真实 NBSP 目录完整通过识别、预览、YES 并原样传入核心 argv'
    & $module {
        param($Source)
        $script:Calls.Clear()
        $script:WriteExit = 7
        $script:Responses.Enqueue($Source)
        $script:Responses.Enqueue('YES')
    } $source
    Assert-Throws { & $module { param($Project) Invoke-JobsFlutterDependencyImport $Project } $project } '实际导入失败不能报告成功'
    Assert (-not [IO.File]::Exists((Join-Path $project 'pubspec_overrides.yaml')) -and -not [IO.Directory]::Exists((Join-Path $project 'vendor'))) 'wrapper 取消和假核心不写项目'
    foreach ($name in @('ImportFlutterDependencies.dart', 'ExtractFlutterDependencies.dart')) {
        Assert ([IO.File]::Exists((Join-Path $worker ('Scripts/' + $name)))) ('worker 随包包含 ' + $name)
    }
    # 从真实 release 的聚合入口进入，避免只测 worker 而漏掉父调度器门禁。
    $package = Join-Path $root 'JobsFlutterTools'
    $installer = Import-Module (Join-Path $package 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
    $release = Join-Path $temporary 'standalone-release'
    & $installer { param($Package, $Release) New-JobsPackageRelease -PackagePath $Package -Destination $Release } $package $release | Out-Null
    foreach ($name in @('Action.psm1', 'Common.psm1', 'ExtractFlutterDependencies.dart', 'ImportFlutterDependencies.dart')) {
        $relative = 'Scripts/Actions/import-dependencies/Scripts/' + $name
        Assert ((Get-FileHash -LiteralPath (Join-Path $release $relative)).Hash -ceq (Get-FileHash -LiteralPath (Join-Path $package $relative)).Hash) ('聚合 release 内置真实导入资源：' + $name)
    }
    $releaseWorker = Import-Module (Join-Path $release 'Scripts/Actions/import-dependencies/Scripts/Action.psm1') -PassThru -DisableNameChecking
    & $releaseWorker {
        param($Source)
        $script:Responses = New-Object 'Collections.Generic.Queue[object]'
        $script:Responses.Enqueue(('"' + $Source + '"'))
        $script:Responses.Enqueue('YES')
        $script:DispatchCalls = New-Object 'Collections.Generic.List[object]'
        function script:Read-Host { param($Prompt) return $script:Responses.Dequeue() }
        function script:Read-JobsImporterSourceInput { param($Prompt) return Read-Host $Prompt }
        function script:Find-JobsImporterDart { param($Directory) return 'release-native-dart.exe' }
        function script:Invoke-JobsProcess {
            param($FilePath, $Arguments, $WorkingDirectory, $TimeoutSeconds)
            $script:DispatchCalls.Add([pscustomobject]@{ File = $FilePath; Arguments = @($Arguments); Directory = $WorkingDirectory })
            return [pscustomobject]@{ ExitCode = 0; StdOut = 'release fixture plan/result'; StdErr = '' }
        }
    } $source
    [IO.File]::WriteAllText((Join-Path $project '.fvmrc'), '{"flutter":"3.38.5"}')
    $dartPath = Join-Path $project '.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dart.exe'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $dartPath))
    [IO.File]::WriteAllText($dartPath, 'fixture only')
    [IO.File]::WriteAllText((Join-Path $project '.fvm/flutter_sdk/bin/flutter.bat'), 'fixture only')
    Assert (-not [IO.Directory]::Exists((Join-Path $project 'lib'))) '聚合调用夹具是有效 pubspec 且没有 lib/ 的 Flutter 项目'
    $dispatch = Import-Module (Join-Path $release 'Scripts/Action.psm1') -PassThru -DisableNameChecking
    # 同进程复测两个动作时，子 worker 的同名导出不能替换本夹具保存的聚合入口。
    $dispatchEntry = $dispatch.ExportedFunctions['Invoke-JobsFeature'].ScriptBlock
    & $dispatchEntry -Target $project -Action 'import-dependencies'
    $calls = @(& $releaseWorker { $script:DispatchCalls.ToArray() })
    Assert ($calls.Count -eq 2 -and $calls[0].Arguments[-1] -ceq '--validate-only' -and $calls[1].Arguments.Count -eq 5) '真实聚合入口到 release worker 完整执行路径输入、预览、YES 和写入调用'
    Assert ($calls[1].Arguments[2] -ceq $project -and $calls[1].Arguments[4] -ceq $source -and $calls[1].Directory -ceq $project) '聚合调度保留选中工程与拖入特殊来源路径'
    Assert ($calls[1].Arguments[0] -ceq (Join-Path $release 'Scripts/Actions/import-dependencies/Scripts/ImportFlutterDependencies.dart')) '执行的是完整 release 内的导入核心'
    & $releaseWorker {
        param($Source)
        $script:DispatchCalls.Clear()
        $script:Responses.Enqueue(('"' + $Source + '"'))
        $script:Responses.Enqueue('YES')
    } $literalBoundarySource
    & $dispatchEntry -Target $project -Action 'import-private-dependencies'
    $privateReleaseCalls = @(& $releaseWorker { $script:DispatchCalls.ToArray() })
    Assert ($privateReleaseCalls.Count -eq 2) '新增私库动作通过真实聚合 release 进入现有导入 worker'
    foreach ($call in $privateReleaseCalls) {
        Assert ($call.Arguments -ccontains '--private-only' -and $call.Arguments[4] -ceq $literalBoundarySource -and $call.Directory -ceq $project) '聚合私库调度完整保留类型、NBSP 来源与所选工程'
    }
    # 子进程真正关闭 stdin，验证 EOF 不会被误当空行忙循环；不用 mock 代替输入结束。
    $eofProbe = Join-Path $temporary 'source-eof-probe.ps1'
    $probeBody = @'
param([string]$Worker, [string]$Project, [string]$State)
$ErrorActionPreference = 'Stop'
$OutputEncoding = New-Object Text.UTF8Encoding($false)
[Console]::OutputEncoding = $OutputEncoding
$env:LOCALAPPDATA = $State
$module = Import-Module $Worker -PassThru -DisableNameChecking
# 5.1 重定向宿主以信息流输出 Write-Host；显式渲染文本以验证真实重问次数。
& $module { param($Path) Invoke-JobsFlutterDependencyImport $Path } $Project 6>&1 | ForEach-Object {
    if ($_ -is [Management.Automation.InformationRecord]) { [Console]::Out.WriteLine($_.ToString()) }
    else { $_ }
}
'@
    [IO.File]::WriteAllText($eofProbe, $probeBody, (New-Object Text.UTF8Encoding($true)))
    $probeIndex = 0
    foreach ($inputText in @('', "`n  `t`n`n")) {
        $probeState = Join-Path $temporary ('eof-state-' + $probeIndex)
        $start = New-Object Diagnostics.ProcessStartInfo
        $start.FileName = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $start.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -InputFormat Text -OutputFormat Text -File "' + $eofProbe + '" -Worker "' + (Join-Path $worker 'Scripts/Action.psm1') + '" -Project "' + $project + '" -State "' + $probeState + '"'
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardInput = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
        $start.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
        $process = [Diagnostics.Process]::Start($start)
        try {
            $outputTask = $process.StandardOutput.ReadToEndAsync()
            $errorTask = $process.StandardError.ReadToEndAsync()
            $process.StandardInput.Write($inputText)
            $process.StandardInput.Close()
            $finished = $process.WaitForExit(10000)
            if (-not $finished) { $process.Kill() }
            Assert $finished '空白后真实 stdin EOF 在限时内退出，没有忙循环'
            $output = $outputTask.GetAwaiter().GetResult()
            $errorOutput = $errorTask.GetAwaiter().GetResult()
            Assert ($process.ExitCode -eq 0) ('真实 stdin EOF 正常结束：' + $errorOutput)
            Assert (-not [IO.Directory]::Exists($probeState) -and -not [IO.Directory]::Exists((Join-Path $project 'vendor'))) '真实 EOF 不创建业务状态或项目依赖'
            if ($inputText.Length -gt 0) {
                Assert ([regex]::Matches($output, '尚未输入依赖目录').Count -eq 3) ('三个真实空行分别重新提示后才在 EOF 退出；输出：' + $output + '；错误：' + $errorOutput)
            }
        } finally { $process.Dispose() }
        $probeIndex++
    }
    Write-Host ('PASS: FlutterDependencyImporter.Tests.ps1 (' + $count + ' assertions; temporary fixtures only)')
} finally {
    if ($null -ne $module) { Remove-Module $module }
    foreach ($loaded in @(Get-Module | Where-Object { $_.Path -and $_.Path.StartsWith($temporary, [StringComparison]::OrdinalIgnoreCase) })) { Remove-Module $loaded }
    $env:LOCALAPPDATA = $savedLocal
    if ([IO.Directory]::Exists($temporary)) { [IO.Directory]::Delete($temporary, $true) }
}

# Worker.Tests.ps1
# WindowsOS@Extension
# Created by Jobs on 2026年10月18日，星期日.

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $project 'JobsCodeGraphUpdater/Scripts/Common.psm1') -Force -DisableNameChecking
$worker = Join-Path $project 'JobsCodeGraphUpdater/Scripts/Action.psm1'
foreach ($name in @('JobsFlutterPubGet', 'JobsCodeGraphUpdater', 'JobsGitEmptyCommitPusher')) {
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $project ($name + '/Scripts/Action.psm1')), [ref]$tokens, [ref]$errors)
    if ($errors) { throw ($errors | Out-String) }
    foreach ($definition in $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
        if ($definition.Name -ne 'Invoke-JobsFeature') { . ([scriptblock]::Create($definition.Extent.Text)) }
    }
}

$script:assertions = 0
function Assert-True {
    param([bool]$Condition, [string]$Because)
    $script:assertions++
    if (-not $Condition) { throw "断言失败：$Because" }
}
function Assert-Throws {
    param([scriptblock]$Action, [string]$Because)
    $script:assertions++
    $thrown = $false
    try { & $Action | Out-Null } catch { $thrown = $true }
    if (-not $thrown) { throw "应阻止该操作：$Because" }
}
function Write-JobsLog { param([string]$Message) }
function Get-JobsInstallRoot { return $script:root }
function Invoke-TestGit {
    param([string[]]$Arguments)
    $result = Invoke-JobsProcess -FilePath $script:git -Arguments $Arguments -WorkingDirectory $script:repository
    if ($result.ExitCode -ne 0) { throw "临时 Git 准备失败：$($result.StdErr)" }
    return $result.StdOut.Trim()
}

$temporary = [IO.Path]::GetTempPath()
if ([IO.Directory]::Exists('/private/tmp')) { $temporary = '/private/tmp' }
$script:root = Join-Path $temporary ("JobsWorker [中文] '& %PATH% ! " + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($script:root)
try {
    $bytes = [IO.File]::ReadAllBytes($worker)
    Assert-True ($bytes.Length -gt 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) '独立业务模块中文源码采用 UTF-8 BOM'
    Assert-True (Test-JobsSamePath $script:root ($script:root + [IO.Path]::DirectorySeparatorChar)) '目录末尾分隔符归一'
    Assert-True (-not (Test-JobsSamePath 'relative-path' $script:root)) 'JSON 项目身份必须为绝对路径'
    Assert-True (-not (Test-JobsSamePath '' $script:root)) 'JSON 项目身份不能为空'
    Assert-True ((Assert-JobsOrdinaryDirectory $script:root) -eq $script:root) '特殊字符原样作为路径处理'
    Assert-Throws { Assert-JobsOrdinaryDirectory 'relative-path' } '目标必须绝对目录'
    Assert-Throws { Invoke-JobsFlutterProcess 'C:\sdk"\flutter.bat' @('--version') $script:root } '拒绝非法双引号工具路径'
    Assert-Throws { Invoke-JobsFlutterProcess 'C:\flutter\flutter.bat' @('pub', 'get & whoami') $script:root } 'Flutter 仅接受固定命令参数'
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        $fakeFlutter = Join-Path $script:root 'flutter.bat'
        $capturedDirectory = Join-Path $script:root 'flutter-working-directory.txt'
        [IO.File]::WriteAllText($fakeFlutter, "@echo off`r`n> `"%JOBS_FLUTTER_TEST_OUTPUT%`" <nul set /p `"=%CD%`"`r`nexit /b 0`r`n", [Text.Encoding]::ASCII)
        $savedOutput = [Environment]::GetEnvironmentVariable('JOBS_FLUTTER_TEST_OUTPUT', 'Process')
        try {
            $env:JOBS_FLUTTER_TEST_OUTPUT = $capturedDirectory
            Invoke-JobsFlutterProcess $fakeFlutter @('--version') $script:root 10
            Assert-True ([IO.File]::ReadAllText($capturedDirectory) -eq $script:root) 'cmd 工具和工作目录中的中文、百分号、叹号、单引号、& 不展开或注入'
        } finally { [Environment]::SetEnvironmentVariable('JOBS_FLUTTER_TEST_OUTPUT', $savedOutput, 'Process') }
    }

    $package = Join-Path $script:root 'fake-package'
    [void][IO.Directory]::CreateDirectory($package)
    @{ name = '@colbymchenry/codegraph'; version = '1.6.2'; bin = @{ codegraph = '../outside.js' } } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $package 'package.json') -Encoding UTF8
    Assert-Throws { Get-JobsPackageEntry $package '@colbymchenry/codegraph' 'codegraph' } 'npm bin 不得越过包目录'
    @{ name = '@colbymchenry/codegraph'; version = '99.0.0'; bin = @{ codegraph = 'entry.js' } } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $package 'package.json') -Encoding UTF8
    Assert-True ($null -eq (Get-JobsPackageEntry $package '@colbymchenry/codegraph' 'codegraph')) '未知 CodeGraph 版本不可执行'

    $prefix = Join-Path $script:root 'tools-codegraph'
    $mainPackage = Join-Path $prefix 'node_modules/@colbymchenry/codegraph'
    $nestedBundle = Join-Path $mainPackage 'node_modules/@colbymchenry/codegraph-win32-x64'
    [void][IO.Directory]::CreateDirectory((Join-Path $nestedBundle 'lib/dist/bin'))
    @{ name = '@colbymchenry/codegraph'; version = '1.6.2'; bin = @{ codegraph = 'npm-shim.js' } } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $mainPackage 'package.json') -Encoding UTF8
    @{ name = '@colbymchenry/codegraph-win32-x64'; version = '1.6.2' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $nestedBundle 'package.json') -Encoding UTF8
    [IO.File]::WriteAllText((Join-Path $mainPackage 'npm-shim.js'), '')
    [IO.File]::WriteAllText((Join-Path $nestedBundle 'node.exe'), '')
    [IO.File]::WriteAllText((Join-Path $nestedBundle 'lib/dist/bin/codegraph.js'), '')
    $script:CodeGraphPlatform = 'win32-x64'
    $resolved = Get-JobsCodeGraphCommand 'unused-node' $prefix
    Assert-True ($resolved.SchemaNode -eq (Join-Path $nestedBundle 'node.exe')) '复用 npm global 常见的包内嵌套 platform runtime'
    $siblingBundle = Join-Path ([IO.Path]::GetDirectoryName($mainPackage)) 'codegraph-win32-x64'
    Move-Item -LiteralPath $nestedBundle -Destination $siblingBundle
    $resolved = Get-JobsCodeGraphCommand 'unused-node' $prefix
    Assert-True ($resolved.SchemaNode -eq (Join-Path $siblingBundle 'node.exe')) '复用本地 npm prefix 的同级 platform runtime'

    $graphFunctions = @{}
    foreach ($name in @('Assert-JobsCodeGraphHost', 'Get-JobsCodeGraphNodeTools', 'Get-JobsCodeGraphWinget',
        'Get-JobsCodeGraphCommand', 'Assert-JobsCodeGraphRuntime', 'Invoke-JobsCheckedProcess',
        'Repair-JobsCodeGraphNodeTools', 'Update-JobsCodeGraphSessionPath', 'Get-JobsGraphStatus',
        'Find-JobsExecutable', 'Get-JobsPackageEntry', 'Read-Host')) {
        $definition = Get-Command $name
        $graphFunctions[$name] = if ($definition.CommandType -eq 'Function') { $definition.ScriptBlock } else { $null }
    }
    $graphEnvironment = @{}
    foreach ($name in @('CODEGRAPH_DIR', 'CODEGRAPH_TELEMETRY', 'DO_NOT_TRACK', 'CODEGRAPH_NO_DOWNLOAD',
        'CODEGRAPH_NO_WATCH', 'CODEGRAPH_NO_DAEMON', 'NO_COLOR', 'FORCE_COLOR', 'NODE_OPTIONS', 'NODE_PATH',
        'npm_config_global', 'npm_config_omit', 'npm_config_include', 'npm_config_platform', 'npm_config_arch')) {
        $graphEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
    try {
        function Reset-GraphFixture {
            $script:healthLayers = @()
            $script:graphCalls = @()
            $script:resolveCount = 0
            $script:runtimeChecks = 0
            $script:nodeRepairs = 0
            $script:statusChecks = 0
            $script:runtimeFailure = ''
            $script:repairFailure = $false
            $script:graphConfirm = ''
            $script:availableNodeVersions = "Version`n-------`n26.1.0`n24.9.0`n24.18.0`n22.0.0"
            $script:healthNodeVersion = 'v24.18.0'
            $script:healthNodeDigest = '2f17a0f8d518e491c5a0c490b2c1991828dd87d173994ba40996e1da59d4e368'
            $script:healthNpmRoot = $script:root
            $script:existingGraphCommand = @{ Executable = 'bundled-node.exe'; Prefix = @('--liftoff-only', 'codegraph.js'); SchemaNode = 'bundled-node.exe' }
            $script:nodeTools = $null
        }
        function Assert-JobsCodeGraphHost { $script:healthLayers += 'PowerShell/.NET'; $script:CodeGraphPlatform = 'win32-x64' }
        function Get-JobsCodeGraphNodeTools { param($Directory) $script:healthLayers += 'Node/npm'; return $script:nodeTools }
        function Get-JobsCodeGraphWinget { param($Directory) $script:healthLayers += 'WinGet'; return $null }
        function Get-JobsCodeGraphCommand {
            param($Node, $Prefix)
            $script:resolveCount++
            if ($script:resolveCount -eq 1) { return $script:existingGraphCommand }
            return @{ Executable = 'repaired-node.exe'; Prefix = @('--liftoff-only', 'repaired-codegraph.js'); SchemaNode = 'repaired-node.exe' }
        }
        function Assert-JobsCodeGraphRuntime {
            param($Command, $Directory)
            $script:runtimeChecks++
            if ($script:runtimeFailure -eq 'always' -or ($script:runtimeFailure -eq 'first' -and $script:runtimeChecks -eq 1)) { throw 'simulated unhealthy runtime' }
        }
        function Invoke-JobsCheckedProcess {
            param($Executable, $Arguments, $Directory, $TimeoutSeconds = 30, [switch]$Quiet)
            $script:graphCalls += [pscustomobject]@{ Executable = $Executable; Arguments = $Arguments; Directory = $Directory }
            $output = ''
            if ($Arguments[0] -eq 'show' -and '--versions' -in $Arguments) { $output = $script:availableNodeVersions }
            if ($Arguments[0] -eq '--version') { $output = $script:healthNodeVersion }
            if ($Arguments[0] -eq '-e') { $output = $script:healthNodeDigest }
            if ($Arguments[0] -eq 'npm.js') {
                if ($Arguments[1] -eq '--version') { $output = '11.0.0' }
                if ($Arguments[1] -eq 'config') { $output = $script:root }
                if ($Arguments[1] -eq 'root') { $output = $script:healthNpmRoot }
            }
            return [pscustomobject]@{ ExitCode = 0; StdOut = $output; StdErr = '' }
        }
        function Repair-JobsCodeGraphNodeTools {
            param($Winget, $Directory)
            $script:nodeRepairs++
            if ($script:repairFailure) { throw 'simulated node repair failure' }
            return @{ Node = 'node.exe'; NpmEntry = 'npm.js' }
        }
        function Update-JobsCodeGraphSessionPath { }
        function Get-JobsGraphStatus { param($Command, $Directory, [switch]$Complete) $script:statusChecks++ }
        function Read-Host { param($Prompt) return $script:graphConfirm }

        Reset-GraphFixture
        Invoke-JobsCodeGraphAction $script:root 6>$null
        Assert-True (($script:healthLayers -join ',') -eq 'PowerShell/.NET,Node/npm,WinGet') '健康 CLI 分支也体检每一层已有安装上游'
        Assert-True ($script:nodeRepairs -eq 0 -and $script:graphCalls.Count -eq 1) '健康随包运行时不强装缺失 Node/npm 或 WinGet'
        Assert-True ($script:graphCalls[0].Arguments[-3] -eq 'init' -and $script:graphCalls[0].Arguments[-1] -eq $script:root) '首次建图精确使用 init --yes 及目标绝对路径'

        Reset-GraphFixture
        $script:existingGraphCommand = $null
        $script:nodeTools = @{ Node = 'node.exe'; NpmEntry = 'npm.js' }
        Invoke-JobsCodeGraphAction $script:root 6>$null
        Assert-True ($script:nodeRepairs -eq 0 -and $script:runtimeChecks -eq 1 -and $script:graphCalls.Count -eq 3) '缺 CLI 复用健康上游，只安装一次并复检'
        Assert-True ($script:graphCalls[0].Arguments[1] -eq 'ping' -and '--registry=https://registry.npmjs.org/' -in $script:graphCalls[0].Arguments) '安装前核验官方 npm 源连通性'
        Assert-True ('--ignore-scripts' -in $script:graphCalls[1].Arguments -and '@colbymchenry/codegraph@1.6.2' -in $script:graphCalls[1].Arguments) '私有安装锁定官方包版本并禁止生命周期脚本'
        Assert-True ('--global=false' -in $script:graphCalls[1].Arguments -and $env:npm_config_arch -eq 'x64' -and $env:npm_config_platform -eq 'win32' -and $env:npm_config_include -eq 'optional') '私有安装固定范围与平台，不继承漏装 optional 的配置'
        Assert-True ('--os=win32' -in $script:graphCalls[1].Arguments -and '--cpu=x64' -in $script:graphCalls[1].Arguments -and $script:graphCalls[1].Directory -ne $script:root) 'npm 在私有目录运行并显式固定 optional 平台，隔离项目 npmrc'

        Reset-GraphFixture
        $script:runtimeFailure = 'first'
        Invoke-JobsCodeGraphAction $script:root 6>$null
        Assert-True ($script:nodeRepairs -eq 1 -and $script:runtimeChecks -eq 2 -and $script:resolveCount -eq 2) '损坏 CLI 向上修复必需层后仅修复一次并复检'

        Reset-GraphFixture
        $script:existingGraphCommand = $null
        $script:repairFailure = $true
        Assert-Throws { Invoke-JobsCodeGraphAction $script:root 6>$null } '上游修复失败立即停止'
        Assert-True ($script:graphCalls.Count -eq 0 -and $script:nodeRepairs -eq 1) '上游失败不执行 npm 安装或目标建图'

        Reset-GraphFixture
        $script:runtimeFailure = 'always'
        Assert-Throws { Invoke-JobsCodeGraphAction $script:root 6>$null } 'CLI 修复后二次体检仍失败时停止'
        Assert-True ($script:runtimeChecks -eq 2 -and $script:graphCalls.Count -eq 2) 'CLI 只修复一次且失败不建图'

        Reset-GraphFixture
        $existingGraph = Join-Path $script:root '.codegraph'
        [void][IO.Directory]::CreateDirectory($existingGraph)
        try {
            Invoke-JobsCodeGraphAction $script:root 6>$null
            Assert-True ($script:graphCalls[0].Arguments[-2] -eq 'sync' -and $script:graphCalls[0].Arguments[-1] -eq $script:root) '已有地图同步精确目标'
            Assert-True ($script:statusChecks -eq 2) '已有地图写前核对身份，写后核对完成状态'
        } finally { [IO.Directory]::Delete($existingGraph) }

        Reset-GraphFixture
        $script:nodeTools = @{ Node = 'node.exe'; NpmEntry = 'npm.js' }
        [void](& $graphFunctions['Repair-JobsCodeGraphNodeTools'] 'winget.exe' $script:root 6>$null)
        $installArguments = $script:graphCalls[2].Arguments
        $versionPosition = [Array]::IndexOf($installArguments, '--version')
        Assert-True ($installArguments[0] -eq 'install' -and $installArguments[$versionPosition + 1] -eq '24.18.0' -and '--force' -in $installArguments) 'WinGet 只强制重跑官方源最高精确 24.x，忽略26.x且不按字典序误选24.9'

        Reset-GraphFixture
        $script:availableNodeVersions = "Version`n26.1.0"
        Assert-Throws { & $graphFunctions['Repair-JobsCodeGraphNodeTools'] 'winget.exe' $script:root 6>$null } '官方源没有兼容24.x时停止'
        Assert-True ($script:graphCalls.Count -eq 1) '无兼容版本不调用安装器'

        Reset-GraphFixture
        $script:graphConfirm = $null
        Assert-Throws { & $graphFunctions['Repair-JobsCodeGraphNodeTools'] 'winget.exe' $script:root 6>$null } '非交互EOF不默认为安装确认'
        Assert-True ($script:graphCalls.Count -eq 2) '无确认时仅查询来源而不安装'

        function Find-JobsExecutable { param($Name, $Candidates) return (Join-Path $script:root 'node.exe') }
        function Get-JobsPackageEntry { param($PackageDirectory, $PackageName, $CommandName) return 'npm.js' }
        Reset-GraphFixture
        Assert-True ($null -ne (& $graphFunctions['Get-JobsCodeGraphNodeTools'] $script:root 6>$null)) 'Node24标准库、npm入口与配置体检通过'
        $script:healthNodeVersion = 'v22.20.0'
        Assert-True ($null -ne (& $graphFunctions['Get-JobsCodeGraphNodeTools'] $script:root 6>$null)) '健康Node22符合官方兼容范围并复用'
        $script:healthNodeVersion = 'v25.0.0'
        Assert-True ($null -eq (& $graphFunctions['Get-JobsCodeGraphNodeTools'] $script:root 6>$null)) 'Node25不能误判为兼容安装工具链'
        $script:healthNodeVersion = 'v24.18.0'
        $script:healthNodeDigest = 'wrong'
        Assert-True ($null -eq (& $graphFunctions['Get-JobsCodeGraphNodeTools'] $script:root 6>$null)) 'Node标准库退出0但摘要结果错误仍不健康'
        $script:healthNodeDigest = '2f17a0f8d518e491c5a0c490b2c1991828dd87d173994ba40996e1da59d4e368'
        $script:healthNpmRoot = 'relative-root'
        Assert-True ($null -eq (& $graphFunctions['Get-JobsCodeGraphNodeTools'] $script:root 6>$null)) 'npm全局包配置异常时阻止安装路径'
    } finally {
        foreach ($name in $graphFunctions.Keys) {
            if ($graphFunctions[$name]) { Set-Item -LiteralPath ('Function:' + $name) -Value $graphFunctions[$name] }
            else { Remove-Item -LiteralPath ('Function:' + $name) -ErrorAction SilentlyContinue }
        }
        foreach ($name in $graphEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $graphEnvironment[$name], 'Process') }
        Remove-Item -LiteralPath Function:Reset-GraphFixture -ErrorAction SilentlyContinue
    }

    $gitCommand = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($gitCommand) {
        $script:git = $gitCommand.Source
        $script:repository = Join-Path $script:root 'repository'
        [void][IO.Directory]::CreateDirectory($script:repository)
        [void](Invoke-TestGit @('init', '-b', 'main'))
        [void](Invoke-TestGit @('config', 'user.name', 'Jobs Worker Tests'))
        [void](Invoke-TestGit @('config', 'user.email', 'worker-tests@example.invalid'))
        [void](Invoke-TestGit @('config', 'commit.gpgSign', 'false'))
        [void](Invoke-TestGit @('-c', 'core.hooksPath=', 'commit', '--allow-empty', '-m', 'seed'))
        Assert-Throws { Get-JobsGitPushPlan $script:git $script:repository } '没有 upstream 不推送'
        [void](Invoke-TestGit @('remote', 'add', 'origin', 'https://example.invalid/repository.git'))
        [void](Invoke-TestGit @('config', 'branch.main.remote', 'origin'))
        [void](Invoke-TestGit @('config', 'branch.main.merge', 'refs/heads/main'))
        [void](Invoke-TestGit @('update-ref', 'refs/remotes/origin/main', 'HEAD'))
        $plan = Get-JobsGitPushPlan $script:git $script:repository
        Assert-True ($plan.Branch -eq 'main' -and $plan.Remote -eq 'origin' -and $plan.Ref -eq 'refs/heads/main') '只映射当前已有 upstream 分支'
        [void](Assert-JobsGitIndexEmpty $script:git $script:repository)
        [IO.File]::WriteAllText((Join-Path $script:repository 'staged.txt'), 'preserve')
        [void](Invoke-TestGit @('add', '--', 'staged.txt'))
        Assert-Throws { Assert-JobsGitIndexEmpty $script:git $script:repository } '暂存区非空时阻止空白提交'
        Assert-True ((Invoke-TestGit @('diff', '--cached', '--name-only')) -eq 'staged.txt') '检查不改变暂存内容'
        [void](Invoke-TestGit @('config', 'branch.main.pushRemote', 'other'))
        Assert-Throws { Get-JobsGitPushPlan $script:git $script:repository } 'pushRemote 冲突时停止'
        [void](Invoke-TestGit @('config', '--unset', 'branch.main.pushRemote'))
        [void](Invoke-TestGit @('config', 'remote.origin.mirror', 'true'))
        Assert-Throws { Get-JobsGitPushPlan $script:git $script:repository } 'mirror 配置不能进入推送'
        [void](Invoke-TestGit @('config', '--unset', 'remote.origin.mirror'))
        [void](Invoke-TestGit @('config', '--add', 'remote.origin.pushurl', 'https://example.invalid/first.git'))
        [void](Invoke-TestGit @('config', '--add', 'remote.origin.pushurl', 'https://example.invalid/second.git'))
        Assert-Throws { Get-JobsGitPushPlan $script:git $script:repository } '多个 pushurl 时停止'
        [void](Invoke-TestGit @('config', '--unset-all', 'remote.origin.pushurl'))
        [void](Invoke-TestGit @('checkout', '--detach'))
        Assert-Throws { Get-JobsGitPushPlan $script:git $script:repository } '游离 HEAD 时停止'
    } else { Write-Host '跳过临时 Git 测试：缺少 git。' }

    $node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($node) {
        $sqlite = Invoke-JobsProcess -FilePath $node.Source -Arguments @('-e', 'require("node:sqlite")') -WorkingDirectory $script:root
        if ($sqlite.ExitCode -eq 0) {
            $target = Join-Path $script:root 'graph-target'
            $graph = Join-Path $target '.codegraph'
            [void][IO.Directory]::CreateDirectory($graph)
            $database = Join-Path $graph 'codegraph.db'
            $create = 'const {DatabaseSync}=require("node:sqlite");const db=new DatabaseSync(process.argv[1]);db.exec("CREATE TABLE nodes(id TEXT)");db.close();'
            [void](Invoke-JobsCheckedProcess $node.Source @('-e', $create, $database) $script:root -Quiet)
            $fakeCli = Join-Path $script:root 'status.js'
            $status = @{ initialized = $true; version = '1.6.2'; projectPath = $target; indexPath = $graph; lastIndexed = '2026-10-18T00:00:00.000Z'; pendingChanges = @{ added = 0; modified = 0; removed = 0 }; index = @{ state = 'complete'; pendingRefs = 0 } }
            [IO.File]::WriteAllText($fakeCli, 'console.log(JSON.stringify(' + ($status | ConvertTo-Json -Depth 5 -Compress) + '));')
            $command = @{ Executable = $node.Source; Prefix = @($fakeCli); SchemaNode = $node.Source }
            $before = (Get-FileHash -LiteralPath $database -Algorithm SHA256).Hash
            Get-JobsGraphStatus $command $target -Complete
            Assert-True ((Get-FileHash -LiteralPath $database -Algorithm SHA256).Hash -eq $before) '节点表健康检查只读且不修改数据库'
            $status.projectPath = $script:root
            [IO.File]::WriteAllText($fakeCli, 'console.log(JSON.stringify(' + ($status | ConvertTo-Json -Depth 5 -Compress) + '));')
            Assert-Throws { Get-JobsGraphStatus $command $target } '状态不得回退父项目'
            [IO.File]::WriteAllText($fakeCli, 'console.log("invalid JSON");')
            Assert-Throws { Get-JobsGraphStatus $command $target } '无效状态 JSON 停止'
            $drop = 'const {DatabaseSync}=require("node:sqlite");const db=new DatabaseSync(process.argv[1]);db.exec("DROP TABLE nodes");db.close();'
            [void](Invoke-JobsCheckedProcess $node.Source @('-e', $drop, $database) $script:root -Quiet)
            $marker = Join-Path $script:root 'status-was-called'
            [IO.File]::WriteAllText($fakeCli, 'require("fs").writeFileSync(' + (ConvertTo-Json $marker -Compress) + ',"called");')
            Assert-Throws { Get-JobsGraphStatus $command $target 6>$null } '存在 SQLite header 但缺 nodes 表时停止'
            Assert-True (-not [IO.File]::Exists($marker)) '损坏 schema 在运行 status 前被拦截'
        } else { Write-Host '跳过 SQLite 集成测试：Node 不支持 node:sqlite。' }
    } else { Write-Host '跳过 SQLite 集成测试：缺少 Node。' }
    $savedFunctions = @{}
    foreach ($name in @('Find-JobsExecutable', 'Get-JobsGitPushPlan', 'Assert-JobsGitIndexEmpty', 'Invoke-JobsCheckedProcess', 'Read-Host')) {
        $command = Get-Command $name
        $savedFunctions[$name] = if ($command.CommandType -eq 'Function') { $command.ScriptBlock } else { $null }
    }
    $savedEnvironment = @{}
    foreach ($name in @('GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR', 'GIT_INDEX_FILE', 'GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_NAMESPACE')) {
        $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
    try {
        function Find-JobsExecutable { param([string]$Name, [string[]]$Candidates) return 'mock-git.exe' }
        function Assert-JobsGitIndexEmpty { param([string]$Git, [string]$Directory) }
        function Read-Host { param([string]$Prompt) return 'YES' }
        function Get-JobsGitPushPlan {
            param([string]$Git, [string]$Directory)
            return @{ Branch = 'main'; Remote = 'origin'; Ref = 'refs/heads/main'; Url = 'https://example.invalid/captured.git' }
        }
        $script:capturedCommit = '1111111111111111111111111111111111111111'
        $script:pushedArguments = @()
        function Invoke-JobsCheckedProcess {
            param([string]$Executable, [string[]]$Arguments, [string]$Directory, [int]$TimeoutSeconds = 30, [switch]$Quiet)
            $output = ''
            if ($Arguments[0] -eq 'rev-parse') {
                switch ($Arguments[1]) {
                    '--is-inside-work-tree' { $output = 'true' }
                    '--git-path' { $output = Join-Path $script:root ('mock-state-' + $Arguments[2]) }
                    'HEAD^{tree}' { $output = 'unchanged-tree' }
                    'HEAD' { $output = $script:capturedCommit }
                }
            }
            if ($Arguments[0] -eq 'push') { $script:pushedArguments = $Arguments }
            return [pscustomobject]@{ ExitCode = 0; StdOut = $output; StdErr = '' }
        }
        Invoke-JobsGitAction $script:root 6>$null
        Assert-True ($script:pushedArguments[-1] -eq ($script:capturedCommit + ':refs/heads/main')) '推送固定已核验 Commit，后续 HEAD 变化不会带走新提交'
        Assert-True ($script:pushedArguments[-2] -eq 'https://example.invalid/captured.git') '推送使用确认时捕获的唯一 URL'
        Assert-True ('--no-follow-tags' -in $script:pushedArguments -and '--recurse-submodules=no' -in $script:pushedArguments) '单分支推送不附带 tags 或子仓推送'
    } finally {
        foreach ($name in $savedFunctions.Keys) {
            if ($savedFunctions[$name]) { Set-Item -LiteralPath ('Function:' + $name) -Value $savedFunctions[$name] }
            else { Remove-Item -LiteralPath ('Function:' + $name) -ErrorAction SilentlyContinue }
        }
        foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process') }
    }
    Write-Host ("独立终端功能验证通过：{0} 项断言。仅使用临时仓库；未访问网络或执行业务安装、建图、提交、推送。" -f $script:assertions)
} finally {
    Remove-Item -LiteralPath $script:root -Recurse -Force -ErrorAction SilentlyContinue
}

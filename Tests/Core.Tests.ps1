# Core.Tests.ps1
# Windows@Extension
# Created by Jobs on 2026年10月18日，星期日.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$project = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $project 'JobsPathCopier/Scripts/Common.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $project 'Scripts/Catalog.psm1') -Force -DisableNameChecking
$tokens = $null
$errors = $null
$gitAction = [Management.Automation.Language.Parser]::ParseFile((Join-Path $project 'JobsGitRemoteOpener/Scripts/Action.psm1'), [ref]$tokens, [ref]$errors)
if ($errors) { throw ($errors | Out-String) }
foreach ($definition in $gitAction.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in @('Get-JobsGitRemote', 'ConvertTo-JobsWebUrl') }, $false)) {
    . ([scriptblock]::Create($definition.Extent.Text))
}

$script:assertions = 0
function Assert-Equal {
    param($Actual, $Expected, [string]$Because)
    $script:assertions++
    if ($Actual -cne $Expected) {
        throw ('断言失败：' + $Because + [Environment]::NewLine + '实际：' + $Actual + [Environment]::NewLine + '预期：' + $Expected)
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Because)
    $script:assertions++
    if (-not $Condition) {
        throw ('断言失败：' + $Because)
    }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Because)
    $script:assertions++
    $thrown = $false
    try {
        & $Action | Out-Null
    }
    catch {
        $thrown = $true
    }
    if (-not $thrown) {
        throw ('预期阻止该操作：' + $Because)
    }
}

function Invoke-TestGit {
    param([string[]]$GitArguments)
    $result = Invoke-JobsProcess -FilePath $script:git -Arguments $GitArguments
    if ($result.ExitCode -ne 0) {
        throw ('临时 Git 测试准备失败：' + $result.StdErr)
    }
    return $result.StdOut.Trim()
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("Jobs WindowsExtension [中文] ' & " + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$savedLocalData = [Environment]::GetEnvironmentVariable('LOCALAPPDATA')
try {
    $features = @(Get-JobsFeaturePackages -Root $project)
    Assert-Equal $features.Count 10 '10 项菜单功能均可独立选择'
    Assert-Equal (@($features.Id | Sort-Object -Unique).Count) 10 '功能标识唯一'
    Assert-True (@($features | Where-Object { $_.DirectoryOnly }).Count -ge 3) '写操作只显示在文件夹上'

    $quoteCases = @(
        @('', '""'),
        @('hello', '"hello"'),
        @('C:\', '"C:\\"'),
        @('C:\directory with spaces\', '"C:\directory with spaces\\"'),
        @('a"b', '"a\"b"'),
        @('a\"b', '"a\\\"b"'),
        @('中文 & $(echo forbidden); %PATH%', '"中文 & $(echo forbidden); %PATH%"')
    )
    foreach ($quoteCase in $quoteCases) {
        Assert-Equal (Quote-JobsArgument -Value $quoteCase[0]) $quoteCase[1] 'Win32 argv 引号与反斜杠'
    }
    Assert-Throws { Quote-JobsArgument -Value ('a' + [char]0 + 'b') } '拒绝 NUL 字符'

    $file = Join-Path $testRoot 'test [1] 中文.txt'
    [IO.File]::WriteAllText($file, 'test')
    $fullRoot = (Get-Item -LiteralPath $testRoot).FullName
    Assert-Equal (Resolve-JobsTarget -Target ($testRoot + '|JobsPathEnd')) $fullRoot '仅去除结尾路径哨兵'
    Assert-Equal (Resolve-JobsTarget -Target $file) (Get-Item -LiteralPath $file).FullName '特殊字符采用 LiteralPath'
    Assert-Equal (Get-JobsDirectory -Target $file) $fullRoot '文件目标使用父目录'
    Assert-Equal (Get-JobsDirectory -Target $testRoot) $fullRoot '目录目标保持自身'
    $volumeRoot = [IO.Path]::GetPathRoot($fullRoot)
    Assert-Equal (Resolve-JobsTarget -Target ($volumeRoot + '|JobsPathEnd')) (Get-Item -LiteralPath $volumeRoot).FullName '盘符根目录及尾部反斜杠保持完整'
    Assert-Equal (Get-JobsDirectory -Target $volumeRoot) (Get-Item -LiteralPath $volumeRoot).FullName '根目录不能退到空父目录'
    Assert-Throws { Resolve-JobsTarget -Target (Join-Path $testRoot 'missing') } '不存在路径停止'
    Assert-Throws { Resolve-JobsTarget -Target ($testRoot + '|JobsPathEnd/extra') } '中间哨兵不被删除'
    if ([IO.Path]::DirectorySeparatorChar -ne [char]92) {
        $literalSentinel = Join-Path $testRoot 'literal|JobsPathEnd-child'
        [void][IO.Directory]::CreateDirectory($literalSentinel)
        Assert-Equal (Resolve-JobsTarget -Target $literalSentinel) $literalSentinel '名称中包含哨兵片段时不改变路径'
    }

    $urlCases = @(
        @('https://github.com/JobsKits/Repo.git', 'https://github.com/JobsKits/Repo'),
        @('https://user:secret@example.com:8443/team/Repo.git', 'https://example.com:8443/team/Repo'),
        @('https://token@example.com:443/team/Repo.git?secret=hidden#private', 'https://example.com:443/team/Repo'),
        @('http://git.example.com:8080/group/Repo.git/', 'http://git.example.com:8080/group/Repo'),
        @('ssh://git@git.example.com:2222/group/Repo.git', 'https://git.example.com/group/Repo'),
        @('git@gitee.com:JobsGo/Repo.git', 'https://gitee.com/JobsGo/Repo'),
        @('git://example.com:9418/group/Repo.git', 'https://example.com/group/Repo'),
        @('git@[2001:db8::1]:group/Repo.git', 'https://[2001:db8::1]/group/Repo'),
        @('git@ssh.dev.azure.com:v3/Jobs/Project/Repo', 'https://dev.azure.com/Jobs/Project/_git/Repo'),
        @('ssh://git@ssh.dev.azure.com:22/v3/Jobs/Project/Repo.git', 'https://dev.azure.com/Jobs/Project/_git/Repo'),
        @('Jobs@vs-ssh.visualstudio.com:v3/Jobs/Project/Repo', 'https://dev.azure.com/Jobs/Project/_git/Repo'),
        @('git@example.com:group/Repo.git?secret=hidden', 'https://example.com/group/Repo')
    )
    foreach ($urlCase in $urlCases) {
        Assert-Equal (ConvertTo-JobsWebUrl -Remote $urlCase[0]) $urlCase[1] '仓库协议转网页并清除凭据'
    }
    foreach ($invalidRemote in @('file:///tmp/repo', 'ext::some-command', 'C:\repo', '/tmp/repo', '../repo', 'ftp://example.com/repo', 'javascript:alert(1)', 'https:example.com/repo', 'git@example.com:', 'https://example.com/')) {
        Assert-Throws { ConvertTo-JobsWebUrl -Remote $invalidRemote } '本地路径及不支持协议不能交给浏览器'
    }

    $powerShell = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    Assert-Equal (Find-JobsExecutable -Name '__jobs_missing_executable__' -Candidates @($powerShell)) $powerShell '程序候选采用真实可执行文件'
    function global:JobsTestFakeApplication { 'not an application' }
    Set-Alias -Name JobsTestFakeAlias -Value $powerShell -Scope Global
    Assert-True ($null -eq (Find-JobsExecutable -Name 'JobsTestFakeApplication')) '不执行同名函数'
    Assert-True ($null -eq (Find-JobsExecutable -Name 'JobsTestFakeAlias')) '不执行同名别名'

    $argumentProbe = Join-Path $testRoot 'probe arguments.ps1'
    [IO.File]::WriteAllText($argumentProbe, '[Console]::Write((ConvertTo-Json -InputObject @($args) -Compress))', (New-Object Text.UTF8Encoding($true)))
    $probeArguments = @('simple', '', 'C:\', 'path with spaces\', 'a"b', 'a\"b', "中文 ' & ; `$() %PATH%", "line1`nline2")
    $roundTrip = Invoke-JobsProcess -FilePath $powerShell -Arguments (@('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $argumentProbe) + $probeArguments) -WorkingDirectory $testRoot
    Assert-Equal $roundTrip.ExitCode 0 '原生子进程正常返回'
    $decoded = $roundTrip.StdOut | ConvertFrom-Json
    $received = @($decoded)
    Assert-Equal $received.Count $probeArguments.Count '参数数量不被 Shell 元字符改变'
    for ($index = 0; $index -lt $probeArguments.Count; $index++) {
        Assert-Equal $received[$index] $probeArguments[$index] '特殊参数真实子进程往返保持一致'
    }

    $streamProbe = Join-Path $testRoot 'probe streams.ps1'
    [IO.File]::WriteAllText($streamProbe, "[Console]::Out.Write(('O' * 262144)); [Console]::Error.Write(('E' * 262144)); exit 7")
    $streams = Invoke-JobsProcess -FilePath $powerShell -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $streamProbe)
    Assert-Equal $streams.ExitCode 7 '非零退出码保留'
    Assert-Equal $streams.StdOut.Length 262144 '大量标准输出不死锁'
    Assert-Equal $streams.StdErr.Length 262144 '大量标准错误不死锁'

    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    Assert-Throws { Invoke-JobsProcess -FilePath $powerShell -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 15') -TimeoutSeconds 1 } '超时停止本次子进程'
    Assert-True ($stopwatch.Elapsed.TotalSeconds -lt 12) '超时后能够按时返回'

    $childProbe = Join-Path $testRoot 'probe descendant.ps1'
    $parentProbe = Join-Path $testRoot 'probe parent.ps1'
    $childHeartbeat = Join-Path $testRoot 'child heartbeat.txt'
    $childPidFile = Join-Path $testRoot 'child pid.txt'
    [IO.File]::WriteAllText($childProbe, 'while ($true) { [IO.File]::AppendAllText($args[0], "."); Start-Sleep -Milliseconds 100 }')
    $parentSource = @'
$start = New-Object Diagnostics.ProcessStartInfo
$start.FileName = $args[0]
$start.Arguments = $args[1]
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$child = [Diagnostics.Process]::Start($start)
[IO.File]::WriteAllText($args[2], $child.Id.ToString())
Start-Sleep -Seconds 30
'@
    [IO.File]::WriteAllText($parentProbe, $parentSource)
    $childArguments = (@('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $childProbe, $childHeartbeat) | ForEach-Object { Quote-JobsArgument $_ }) -join ' '
    try {
        Assert-Throws { Invoke-JobsProcess -FilePath $powerShell -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $parentProbe, $powerShell, $childArguments, $childPidFile) -TimeoutSeconds 3 } '超时停止本次父进程及派生子进程'
        Assert-True ([IO.File]::Exists($childPidFile) -and [IO.File]::Exists($childHeartbeat)) '测试父进程实际派生了持续运行的子进程'
        $heartbeatLength = [IO.File]::ReadAllText($childHeartbeat).Length
        Start-Sleep -Milliseconds 700
        Assert-Equal ([IO.File]::ReadAllText($childHeartbeat).Length) $heartbeatLength '父进程超时后派生子进程不再执行工作'
    }
    finally {
        if ([IO.File]::Exists($childPidFile)) {
            $testChildId = [int][IO.File]::ReadAllText($childPidFile)
            $testChild = $null
            try {
                $testChild = [Diagnostics.Process]::GetProcessById($testChildId)
                if (-not $testChild.HasExited) {
                    $testChild.Kill()
                }
            }
            catch {
                # 正常清理路径中，测试子进程已由超时处理结束。
            }
            finally {
                if ($null -ne $testChild) { $testChild.Dispose() }
            }
        }
    }

    $script:git = Find-JobsExecutable -Name 'git'
    Assert-True (-not [string]::IsNullOrWhiteSpace($script:git)) 'Git 集成测试需要 Git'
    $repository = Join-Path $testRoot 'repository [git] 中文'
    [void](Invoke-TestGit @('init', '-q', $repository))
    [void](Invoke-TestGit @('-C', $repository, '-c', 'user.name=Jobs Test', '-c', 'user.email=jobs-test@example.invalid', 'commit', '--allow-empty', '-m', 'test seed'))
    $branchName = Invoke-TestGit @('-C', $repository, 'symbolic-ref', '--short', 'HEAD')
    [void](Invoke-TestGit @('-C', $repository, 'remote', 'add', 'origin', 'git@example.com:team/origin.git'))
    Assert-Equal (Get-JobsGitRemote -Directory $repository) 'git@example.com:team/origin.git' '默认使用 origin 原始地址'
    [void](Invoke-TestGit @('-C', $repository, 'config', 'url.https://mirror.example.invalid/.insteadOf', 'git@example.com:'))
    Assert-Equal (Invoke-TestGit @('-C', $repository, 'remote', 'get-url', 'origin')) 'https://mirror.example.invalid/team/origin.git' '测试配置实际触发了 Git insteadOf 地址重写'
    Assert-Equal (Get-JobsGitRemote -Directory $repository) 'git@example.com:team/origin.git' '复制保留配置原始 scp 地址而不应用 insteadOf'
    [void](Invoke-TestGit @('-C', $repository, 'config', '--add', 'remote.origin.url', 'https://example.com/team/fallback.git'))
    Assert-Equal (Get-JobsGitRemote -Directory $repository) 'git@example.com:team/origin.git' '多条 URL 明确采用第一条配置原值'
    $nestedDirectory = Join-Path $repository 'nested'
    [void][IO.Directory]::CreateDirectory($nestedDirectory)
    Assert-Equal (Get-JobsGitRemote -Directory $nestedDirectory) 'git@example.com:team/origin.git' '工作树内子目录自动定位仓库'
    [void](Invoke-TestGit @('-C', $repository, 'remote', 'add', 'upstream', 'https://example.com/team/upstream.git'))
    [void](Invoke-TestGit @('-C', $repository, 'config', ('branch.' + $branchName + '.remote'), 'upstream'))
    Assert-Equal (Get-JobsGitRemote -Directory $repository) 'https://example.com/team/upstream.git' '当前分支远端优先于 origin'
    [void](Invoke-TestGit @('-C', $repository, 'config', '--unset', ('branch.' + $branchName + '.remote')))
    $worktree = Join-Path $testRoot 'linked worktree [中文]'
    [void](Invoke-TestGit @('-C', $repository, 'worktree', 'add', '--detach', $worktree))
    Assert-True (Test-Path -LiteralPath (Join-Path $worktree '.git') -PathType Leaf) 'worktree 使用 .git 指针文件'
    Assert-Equal (Get-JobsGitRemote -Directory $worktree) 'git@example.com:team/origin.git' '工作树指针由 Git 自行解析'
    [void](Invoke-TestGit @('-C', $repository, 'remote', 'remove', 'origin'))
    Assert-Equal (Get-JobsGitRemote -Directory $repository) 'https://example.com/team/upstream.git' '无 origin 时采用唯一远端'
    [void](Invoke-TestGit @('-C', $repository, 'remote', 'add', 'another', 'https://example.com/team/another.git'))
    Assert-Throws { Get-JobsGitRemote -Directory $repository } '多个远端无 origin 且无分支配置时停止'
    [void](Invoke-TestGit @('-C', $repository, 'remote', 'remove', 'upstream'))
    [void](Invoke-TestGit @('-C', $repository, 'remote', 'remove', 'another'))
    Assert-Throws { Get-JobsGitRemote -Directory $repository } '无远端时停止'
    Assert-Throws { Get-JobsGitRemote -Directory $testRoot } '非 Git 工作树时停止'
    $bare = Join-Path $testRoot 'bare.git'
    [void](Invoke-TestGit @('init', '--bare', '-q', $bare))
    Assert-Throws { Get-JobsGitRemote -Directory $bare } '裸仓库没有工作树不提供菜单动作'

    $submoduleSource = Join-Path $testRoot 'submodule source'
    [void](Invoke-TestGit @('init', '-q', $submoduleSource))
    [void](Invoke-TestGit @('-C', $submoduleSource, '-c', 'user.name=Jobs Test', '-c', 'user.email=jobs-test@example.invalid', '-c', 'commit.gpgsign=false', 'commit', '--allow-empty', '-m', 'submodule seed'))
    [void](Invoke-TestGit @('-C', $repository, '-c', 'protocol.file.allow=always', 'submodule', 'add', $submoduleSource, 'dependencies/source'))
    $submodule = Join-Path (Join-Path $repository 'dependencies') 'source'
    [void](Invoke-TestGit @('-C', $submodule, 'remote', 'set-url', 'origin', 'git@example.com:team/submodule.git'))
    Assert-True (Test-Path -LiteralPath (Join-Path $submodule '.git') -PathType Leaf) '子模块使用 .git 指针文件'
    Assert-Equal (Get-JobsGitRemote -Directory $submodule) 'git@example.com:team/submodule.git' '子模块读取自身远端而非父仓远端'

    [Environment]::SetEnvironmentVariable('LOCALAPPDATA', (Join-Path $testRoot 'local app data'))
    Assert-Equal (Get-JobsInstallRoot) (Join-Path (Join-Path (Join-Path $testRoot 'local app data') 'Jobs/WindowsExtension/extensions') 'copy-path') '安装目录限定当前用户与本功能'
    Write-JobsLog -Message '测试状态；https://user:password@example.invalid/private；C:\secret\private'
    $log = Get-ChildItem -LiteralPath (Join-Path (Get-JobsInstallRoot) 'logs') -File | Select-Object -First 1
    $logContent = [IO.File]::ReadAllText($log.FullName)
    Assert-True (-not $logContent.Contains('password') -and -not $logContent.Contains('C:\secret')) '日志不保留误传凭据或路径'

    Write-Host ('通过：' + $script:assertions + ' 项核心断言（参数、路径、协议、子进程、真实 Git/worktree、日志）。')
}
finally {
    [Environment]::SetEnvironmentVariable('LOCALAPPDATA', $savedLocalData)
    Remove-Item -LiteralPath 'Function:\JobsTestFakeApplication' -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath 'Alias:\JobsTestFakeAlias' -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

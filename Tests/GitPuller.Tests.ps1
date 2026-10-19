# GitPuller.Tests.ps1 | 隔离裸远端与真实工作树回归
# Created by Jobs on 2026年10月19日，星期一.
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:assertions = 0
$root = Split-Path -Parent $PSScriptRoot
$base = [IO.Path]::GetTempPath()
if ([IO.Directory]::Exists('/private/tmp')) { $base = '/private/tmp' }
$temporary = Join-Path $base ("JobsGitPull [中文] '& " + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$savedLocal = $env:LOCALAPPDATA
$savedGlobal = $env:GIT_CONFIG_GLOBAL
$savedSystem = $env:GIT_CONFIG_NOSYSTEM
$module = $null
$savedGitEnvironment = @{}
foreach ($name in @('GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR', 'GIT_INDEX_FILE', 'GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_NAMESPACE')) {
    $savedGitEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue
}

function Assert-Pull {
    param([bool]$Condition, [string]$Message)
    $script:assertions++
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
}
function Write-Fixture {
    param([string]$Directory, [string]$Name, [string]$Content)
    $path = Join-Path $Directory $Name
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
    [IO.File]::WriteAllText($path, $Content, (New-Object Text.UTF8Encoding($false)))
}
function Git-Fixture {
    param([string]$Directory, [string[]]$Arguments)
    $result = Invoke-JobsProcess -FilePath $script:git -Arguments (@('-c', 'core.hooksPath=') + $Arguments) -WorkingDirectory $Directory -TimeoutSeconds 30
    if ($result.ExitCode -ne 0) { throw ('Fixture Git failed: ' + $Arguments[0] + ' / ' + $result.StdErr) }
    return $result.StdOut.TrimEnd("`r", "`n")
}
function Initialize-FixtureIdentity {
    param([string]$Directory)
    [void](Git-Fixture $Directory @('config', 'user.name', 'Jobs Pull Tests'))
    [void](Git-Fixture $Directory @('config', 'user.email', 'pull-tests@example.invalid'))
    [void](Git-Fixture $Directory @('config', 'commit.gpgSign', 'false'))
    [void](Git-Fixture $Directory @('config', 'core.autocrlf', 'false'))
}
function New-PullFixture {
    param([string]$Name)
    $directory = Join-Path $temporary $Name
    [void][IO.Directory]::CreateDirectory($directory)
    $remote = Join-Path $directory '远端 bare.git'
    $publisher = Join-Path $directory 'publisher'
    $worker = Join-Path $directory "worker [中文] '&"
    [void](Git-Fixture $directory @('init', '--bare', '-b', 'main', $remote))
    [void](Git-Fixture $directory @('clone', $remote, $publisher))
    Initialize-FixtureIdentity $publisher
    Write-Fixture $publisher 'a.txt' "base a`n"
    Write-Fixture $publisher 'b.txt' "base b`n"
    Write-Fixture $publisher '.gitignore' "ignored.txt`nignored-dir/`n"
    [void](Git-Fixture $publisher @('add', '.'))
    [void](Git-Fixture $publisher @('commit', '-m', 'seed'))
    [void](Git-Fixture $publisher @('push', '-u', 'origin', 'main'))
    [void](Git-Fixture $directory @('clone', $remote, $worker))
    Initialize-FixtureIdentity $worker
    return @{ Root = $directory; Remote = $remote; Publisher = $publisher; Worker = $worker; Head = (Git-Fixture $worker @('rev-parse', 'HEAD')) }
}
function Publish-Fixture {
    param([hashtable]$Fixture, [string]$Name, [string]$Content)
    Write-Fixture $Fixture.Publisher $Name $Content
    [void](Git-Fixture $Fixture.Publisher @('add', '--', $Name))
    [void](Git-Fixture $Fixture.Publisher @('commit', '-m', 'remote update'))
    [void](Git-Fixture $Fixture.Publisher @('push'))
    return Git-Fixture $Fixture.Publisher @('rev-parse', 'HEAD')
}
function Invoke-PullFixture {
    param([string]$Directory, [AllowNull()][object[]]$Answers = @(), [switch]$ExpectFailure)
    & $module {
        param($Items)
        $script:Answers = New-Object 'System.Collections.Generic.Queue[object]'
        foreach ($item in $Items) { $script:Answers.Enqueue($item) }
        $script:Prompts = @()
        $script:Messages = @()
        function script:Read-JobsPullInput { param($Prompt) $script:Prompts += $Prompt; if ($script:Answers.Count -eq 0) { throw ('Unexpected prompt: ' + $Prompt) }; $answer = $script:Answers.Dequeue(); if ($answer -is [scriptblock]) { return & $answer $Prompt }; return $answer }
        function script:Write-JobsPullMessage { param($Message) $script:Messages += $Message }
        function script:Write-JobsLog { param($Message) }
    } $Answers
    $failed = $false
    try { & $module { param($Path) Invoke-JobsFeature -Target $Path } $Directory }
    catch {
        $failed = $true
        if (-not $ExpectFailure) { throw }
    }
    if ($ExpectFailure) { Assert-Pull $failed '预期失败确实停止' }
    return & $module { [pscustomobject]@{ Prompts = @($script:Prompts); Messages = @($script:Messages); Remaining = $script:Answers.Count } }
}

try {
    $env:LOCALAPPDATA = Join-Path $temporary 'user-data'
    $env:GIT_CONFIG_GLOBAL = Join-Path $temporary 'empty.gitconfig'
    $env:GIT_CONFIG_NOSYSTEM = '1'
    Write-Fixture $temporary 'empty.gitconfig' ''
    $standalone = Join-Path $temporary 'JobsGitPuller'
    Copy-Item -LiteralPath (Join-Path $root 'JobsGitPuller') -Destination $standalone -Recurse
    Import-Module (Join-Path $standalone 'Scripts/Common.psm1') -DisableNameChecking
    $script:git = (Get-Command git -CommandType Application | Select-Object -First 1).Source
    $module = Import-Module (Join-Path $standalone 'Scripts/Action.psm1') -PassThru -DisableNameChecking

    $ordinary = Join-Path $temporary 'ordinary'
    [void][IO.Directory]::CreateDirectory($ordinary)
    $result = Invoke-PullFixture $ordinary
    Assert-Pull ($result.Messages.Count -eq 0 -and $result.Prompts.Count -eq 0) '非 Git 目录静默且无确认'

    $f = New-PullFixture 'clean'
    $latest = Publish-Fixture $f 'b.txt' "remote b`n"
    $result = Invoke-PullFixture $f.Worker
    Assert-Pull ((Git-Fixture $f.Worker @('rev-parse', 'HEAD')) -eq $latest) '干净仓库快进到最新'
    Assert-Pull ($result.Prompts.Count -eq 0) '干净仓库不要求确认'

    $f = New-PullFixture 'cancel'
    Write-Fixture $f.Worker 'a.txt' "local a`n"
    [void](Publish-Fixture $f 'b.txt' "remote b`n")
    foreach ($answer in @('no', ' ', $null)) {
        $result = Invoke-PullFixture $f.Worker @(,$answer)
        Assert-Pull ((Git-Fixture $f.Worker @('rev-parse', 'HEAD')) -eq $f.Head) '非空输入或 EOF 取消不改 HEAD'
        Assert-Pull ((Git-Fixture $f.Worker @('rev-parse', 'origin/main')) -eq $f.Head) '取消不 fetch'
    }

    $f = New-PullFixture 'preserve-index'
    Write-Fixture $f.Worker 'b.txt' "existing stash`n"
    [void](Git-Fixture $f.Worker @('stash', 'push', '-m', 'existing user stash'))
    $existingStash = Git-Fixture $f.Worker @('rev-parse', 'refs/stash')
    Write-Fixture $f.Worker 'a.txt' "staged a`n"
    [void](Git-Fixture $f.Worker @('add', 'a.txt'))
    Write-Fixture $f.Worker 'a.txt' "unstaged a`n"
    $untracked = "新文件 [x] '&.txt"
    Write-Fixture $f.Worker $untracked "untracked data`n"
    $status = Git-Fixture $f.Worker @('status', '--porcelain=v1')
    $latest = Publish-Fixture $f 'b.txt' "remote b`n"
    $result = Invoke-PullFixture $f.Worker @('')
    Assert-Pull ((Git-Fixture $f.Worker @('rev-parse', 'HEAD')) -eq $latest) '有本地修改也快进远端'
    Assert-Pull ((Git-Fixture $f.Worker @('status', '--porcelain=v1')) -ceq $status) '暂存和未暂存边界与未跟踪列表保留'
    Assert-Pull ((Git-Fixture $f.Worker @('show', ':a.txt')) -eq 'staged a') '原暂存 blob 保留'
    Assert-Pull ([IO.File]::ReadAllText((Join-Path $f.Worker 'a.txt')) -eq "unstaged a`n") '原工作文件保留'
    Assert-Pull ((Git-Fixture $f.Worker @('rev-parse', 'stash@{1}')) -eq $existingStash) '用户已有 stash 没有 pop/drop'
    Assert-Pull ((Git-Fixture $f.Worker @('for-each-ref', '--format=%(refname)', 'refs/jobs-git-puller/')) -match '/worktree') '快照恢复锚点保留'

    $f = New-PullFixture 'rollback'
    Write-Fixture $f.Worker 'a.txt' "staged conflict`n"
    [void](Git-Fixture $f.Worker @('add', 'a.txt'))
    Write-Fixture $f.Worker 'a.txt' "unstaged conflict`n"
    Write-Fixture $f.Worker $untracked "untracked conflict`n"
    $status = Git-Fixture $f.Worker @('status', '--porcelain=v1')
    [void](Publish-Fixture $f 'a.txt' "remote conflict`n")
    $result = Invoke-PullFixture $f.Worker @('', '1')
    Assert-Pull ((Git-Fixture $f.Worker @('rev-parse', 'HEAD')) -eq $f.Head) '选项 1 恢复拉取前 HEAD'
    Assert-Pull ((Git-Fixture $f.Worker @('status', '--porcelain=v1')) -ceq $status) '选项 1 恢复 index/worktree/untracked'
    Assert-Pull ((Git-Fixture $f.Worker @('show', ':a.txt')) -eq 'staged conflict') '回滚保留独立暂存版本'
    Assert-Pull ([IO.File]::ReadAllText((Join-Path $f.Worker $untracked)) -eq "untracked conflict`n") '回滚恢复特殊路径文件'

    $f = New-PullFixture 'discard'
    Write-Fixture $f.Worker 'a.txt' "local conflict`n"
    Write-Fixture $f.Worker $untracked "discard me`n"
    Write-Fixture $f.Worker 'ignored.txt' 'keep ignored'
    $latest = Publish-Fixture $f 'a.txt' "remote conflict`n"
    $result = Invoke-PullFixture $f.Worker @('', '2', 'YES')
    Assert-Pull ((Git-Fixture $f.Worker @('rev-parse', 'HEAD')) -eq $latest) '选项 2 放弃改动后整合最新'
    Assert-Pull (-not [IO.File]::Exists((Join-Path $f.Worker $untracked))) '只删除明确确认的快照未跟踪文件'
    Assert-Pull ([IO.File]::ReadAllText((Join-Path $f.Worker 'ignored.txt')) -eq 'keep ignored') '忽略文件保留'

    $f = New-PullFixture 'discard-and-conflict-again'
    Write-Fixture $f.Worker 'a.txt' "committed local`n"
    [void](Git-Fixture $f.Worker @('add', '.'))
    [void](Git-Fixture $f.Worker @('commit', '-m', 'keep local history'))
    $localHead = Git-Fixture $f.Worker @('rev-parse', 'HEAD')
    Write-Fixture $f.Worker 'b.txt' "discard dirty b`n"
    Write-Fixture $f.Worker $untracked "discard dirty untracked`n"
    [void](Publish-Fixture $f 'a.txt' "committed remote`n")
    $result = Invoke-PullFixture $f.Worker @('', '2', 'YES', '1')
    Assert-Pull ((Git-Fixture $f.Worker @('rev-parse', 'HEAD')) -eq $localHead) '再次冲突恢复时保留本地已提交历史'
    Assert-Pull ([IO.File]::ReadAllText((Join-Path $f.Worker 'b.txt')) -eq "base b`n") '已确认放弃的旧改动不复活'
    Assert-Pull (-not [IO.File]::Exists((Join-Path $f.Worker $untracked))) '已确认放弃的未跟踪文件不复活'

    $f = New-PullFixture 'commit-empty-and-conflict-again'
    Write-Fixture $f.Worker 'a.txt' "local commit content`n"
    Write-Fixture $f.Worker $untracked "commit untracked`n"
    [void](Publish-Fixture $f 'a.txt' "remote commit conflict`n")
    $result = Invoke-PullFixture $f.Worker @('', '3', '', '1')
    $commit = Git-Fixture $f.Worker @('rev-parse', 'HEAD')
    Assert-Pull ($commit -ne $f.Head) '选项 3 确实创建提交'
    Assert-Pull ((Git-Fixture $f.Worker @('rev-parse', 'HEAD^')) -eq $f.Head) '再冲突后选 1 保留刚创建的本地提交'
    Assert-Pull ((Git-Fixture $f.Worker @('log', '-1', '--format=%B')) -eq '') '空消息直接回车可以 commit'
    Assert-Pull ((Git-Fixture $f.Worker @('show', ('HEAD:' + $untracked))) -eq 'commit untracked') '提交包含原未跟踪文件'
    Assert-Pull ((Git-Fixture $f.Worker @('status', '--porcelain=v1')) -eq '') '提交后的回滚基线干净'

    $f = New-PullFixture 'fetch-error'
    Write-Fixture $f.Worker 'a.txt' 'keep on fetch failure'
    [void](Git-Fixture $f.Worker @('remote', 'set-url', 'origin', (Join-Path $f.Root 'missing.git')))
    $result = Invoke-PullFixture $f.Worker @('') -ExpectFailure
    Assert-Pull ($result.Prompts.Count -eq 1) '网络/远端失败不进入冲突三选项'
    Assert-Pull ([IO.File]::ReadAllText((Join-Path $f.Worker 'a.txt')) -eq 'keep on fetch failure') '网络失败不触碰本地修改'
    Assert-Pull ((Git-Fixture $f.Worker @('for-each-ref', '--format=%(refname)', 'refs/jobs-git-puller/')) -eq '') '网络失败不提前移动本地内容进 stash'

    $f = New-PullFixture 'ignored-collision'
    Write-Fixture $f.Worker 'ignored.txt' 'private ignored content'
    Write-Fixture $f.Publisher 'ignored.txt' 'remote tracked'
    [void](Git-Fixture $f.Publisher @('add', '-f', 'ignored.txt'))
    [void](Git-Fixture $f.Publisher @('commit', '-m', 'add formerly ignored path'))
    [void](Git-Fixture $f.Publisher @('push'))
    $result = Invoke-PullFixture $f.Worker @() -ExpectFailure
    Assert-Pull ($result.Prompts.Count -eq 0) '忽略文件覆盖拒绝属于普通失败'
    Assert-Pull ([IO.File]::ReadAllText((Join-Path $f.Worker 'ignored.txt')) -eq 'private ignored content') 'merge 不覆盖忽略文件'
    Assert-Pull ((Git-Fixture $f.Worker @('rev-parse', 'HEAD')) -eq $f.Head) '普通失败恢复 HEAD'

    $f = New-PullFixture 'snapshot-error'
    Write-Fixture $f.Worker 'intent.txt' 'intent-to-add'
    [void](Git-Fixture $f.Worker @('add', '-N', 'intent.txt'))
    $status = Git-Fixture $f.Worker @('status', '--porcelain=v1')
    [void](Publish-Fixture $f 'b.txt' 'remote b')
    $result = Invoke-PullFixture $f.Worker @('') -ExpectFailure
    Assert-Pull ($result.Prompts.Count -eq 1) '快照失败不进入冲突三选项'
    Assert-Pull ((Git-Fixture $f.Worker @('status', '--porcelain=v1')) -eq $status) '快照失败保留 intent-to-add 与原文件'
    Assert-Pull ((Git-Fixture $f.Worker @('rev-parse', 'HEAD')) -eq $f.Head) '快照失败不合并'

    $f = New-PullFixture 'nested-protection'
    $nested = Join-Path $f.Worker 'nested'
    [void][IO.Directory]::CreateDirectory($nested)
    [void](Git-Fixture $nested @('init', '-b', 'main'))
    Write-Fixture $nested 'private.txt' 'private nested'
    [void](Publish-Fixture $f 'nested/new.txt' 'remote would enter nested repository')
    $result = Invoke-PullFixture $f.Worker @() -ExpectFailure
    Assert-Pull ($result.Prompts.Count -eq 0) '嵌套 Git 在快照与确认之前拒绝'
    Assert-Pull (-not [IO.File]::Exists((Join-Path $nested 'new.txt'))) 'upstream 不写入嵌套仓库'
    Assert-Pull ([IO.File]::ReadAllText((Join-Path $nested 'private.txt')) -eq 'private nested') '嵌套仓库原文件保留'


    $f = New-PullFixture 'merge-options'
    Write-Fixture $f.Worker 'b.txt' "local committed b`n"
    [void](Git-Fixture $f.Worker @('add', 'b.txt'))
    [void](Git-Fixture $f.Worker @('commit', '-m', 'local independent commit'))
    [void](Git-Fixture $f.Worker @('config', 'branch.main.mergeOptions', '--no-commit --squash'))
    [void](Git-Fixture $f.Worker @('config', 'merge.autoStash', 'true'))
    $latest = Publish-Fixture $f 'a.txt' "remote independent a`n"
    $result = Invoke-PullFixture $f.Worker
    Assert-Pull ((Git-Fixture $f.Worker @('rev-parse', 'HEAD^2')) -eq $latest) '覆盖 mergeOptions no-commit/squash，确实整合远端历史'
    Assert-Pull ((Git-Fixture $f.Worker @('status', '--porcelain=v1')) -eq '') '合并提交后无遗留 merge 状态'

    $f = New-PullFixture 'external-edit-confirmation'
    Write-Fixture $f.Worker 'a.txt' 'original dirty'
    $editedPath = Join-Path $f.Worker 'a.txt'
    $edit = { param($Prompt) [IO.File]::WriteAllText($editedPath, 'external edit while confirming'); return '' }.GetNewClosure()
    $result = Invoke-PullFixture $f.Worker @($edit) -ExpectFailure
    Assert-Pull ([IO.File]::ReadAllText($editedPath) -eq 'external edit while confirming') '初次确认期间同状态字母的内容变更也被识别并保留'
    Assert-Pull ((Git-Fixture $f.Worker @('for-each-ref', '--format=%(refname)', 'refs/jobs-git-puller/')) -eq '') '交互期间外部编辑不创建快照'

    $f = New-PullFixture 'external-edit-conflict-menu'
    Write-Fixture $f.Worker 'a.txt' 'original local conflict'
    [void](Publish-Fixture $f 'a.txt' 'remote conflicting a')
    $editedPath = Join-Path $f.Worker 'a.txt'
    $edit = { param($Prompt) [IO.File]::WriteAllText($editedPath, 'external edit at conflict menu'); return '1' }.GetNewClosure()
    $result = Invoke-PullFixture $f.Worker @('', $edit) -ExpectFailure
    Assert-Pull ([IO.File]::ReadAllText($editedPath) -eq 'external edit at conflict menu') '冲突菜单期间外部编辑后拒绝自动 reset'

    $f = New-PullFixture 'external-edit-yes-cancel'
    Write-Fixture $f.Worker 'a.txt' 'local conflicting a'
    [void](Publish-Fixture $f 'a.txt' 'remote conflicting a')
    $editedPath = Join-Path $f.Worker 'a.txt'
    $edit = { param($Prompt) [IO.File]::WriteAllText($editedPath, 'external edit before cancelling YES'); return 'no' }.GetNewClosure()
    $result = Invoke-PullFixture $f.Worker @('', '2', $edit) -ExpectFailure
    Assert-Pull ([IO.File]::ReadAllText($editedPath) -eq 'external edit before cancelling YES') '取消 YES 仍复检外部编辑，不重置现场'

    $f = New-PullFixture 'external-edit-commit-message'
    Write-Fixture $f.Worker 'a.txt' 'local conflicting a'
    [void](Publish-Fixture $f 'a.txt' 'remote conflicting a')
    $editedPath = Join-Path $f.Worker 'a.txt'
    $edit = { param($Prompt) [IO.File]::WriteAllText($editedPath, 'external edit during commit input'); return '' }.GetNewClosure()
    $result = Invoke-PullFixture $f.Worker @('', '3', $edit) -ExpectFailure
    Assert-Pull ([IO.File]::ReadAllText($editedPath) -eq 'external edit during commit input') 'Commit 输入期间的外部编辑保留'
    Assert-Pull ((Git-Fixture $f.Worker @('rev-parse', 'HEAD')) -eq $f.Head) 'Commit 输入被外部编辑打断后不提交'

    $f = New-PullFixture 'index-flags'
    foreach ($flag in @('--assume-unchanged', '--skip-worktree')) {
        [void](Git-Fixture $f.Worker @('update-index', $flag, 'a.txt'))
        $result = Invoke-PullFixture $f.Worker @() -ExpectFailure
        Assert-Pull ($result.Prompts.Count -eq 0) '隐藏的 index 文件标记在快照前停止'
        [void](Git-Fixture $f.Worker @('update-index', '--no-assume-unchanged', '--no-skip-worktree', 'a.txt'))
    }
    [void](Git-Fixture $f.Worker @('config', 'core.sparseCheckout', 'true'))
    $result = Invoke-PullFixture $f.Worker @() -ExpectFailure
    Assert-Pull ($result.Prompts.Count -eq 0) '稀疏检出在快照前停止'

    $f = New-PullFixture 'dirty-submodule'
    [void](Git-Fixture $f.Worker @('-c', 'protocol.file.allow=always', 'submodule', 'add', $f.Remote, 'module'))
    [void](Git-Fixture $f.Worker @('commit', '-m', 'add local submodule'))
    $nested = Join-Path $f.Worker 'module'
    Write-Fixture $nested 'a.txt' 'dirty child content'
    $result = Invoke-PullFixture $f.Worker @() -ExpectFailure
    Assert-Pull ($result.Prompts.Count -eq 0) 'dirty 子模块在快照前拒绝，不忽略用户改动'
    Assert-Pull ([IO.File]::ReadAllText((Join-Path $nested 'a.txt')) -eq 'dirty child content') '子模块改动保留'

    $f = New-PullFixture 'shared-worktree-lock'
    $linked = Join-Path $f.Root 'linked'
    [void](Git-Fixture $f.Worker @('worktree', 'add', '-b', 'linked', $linked))
    [void](Git-Fixture $linked @('branch', '--set-upstream-to=origin/main'))
    $common = Git-Fixture $linked @('rev-parse', '--git-common-dir')
    if (-not [IO.Path]::IsPathRooted($common)) { $common = Join-Path $linked $common }
    $heldLock = [IO.File]::Open((Join-Path $common 'jobs-git-puller.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $result = Invoke-PullFixture $linked @() -ExpectFailure
        Assert-Pull ($result.Prompts.Count -eq 0) 'linked worktree 共用 common-dir 锁'
    } finally { $heldLock.Dispose() }

    $f = New-PullFixture 'committed-conflict-no-empty-tree'
    Write-Fixture $f.Worker 'a.txt' 'already committed local'
    [void](Git-Fixture $f.Worker @('add', 'a.txt'))
    [void](Git-Fixture $f.Worker @('commit', '-m', 'local history'))
    $localHead = Git-Fixture $f.Worker @('rev-parse', 'HEAD')
    [void](Publish-Fixture $f 'a.txt' 'committed remote conflict')
    $result = Invoke-PullFixture $f.Worker @('3')
    Assert-Pull ((Git-Fixture $f.Worker @('rev-parse', 'HEAD')) -eq $localHead) '只有已提交历史冲突时不制造空树提交'
    Assert-Pull ($result.Prompts.Count -eq 1) '无可提交内容不提示输入 Commit 信息'

    $f = New-PullFixture 'fetch-head-race'
    $latest = Publish-Fixture $f 'b.txt' 'latest despite foreign FETCH_HEAD'
    $fetchHeadPath = Join-Path $f.Worker '.git/FETCH_HEAD'
    & $module {
        param($FetchHead, $OldHead)
        $script:RealPullGit = (Get-Command Invoke-JobsPullGit).ScriptBlock
        $script:ForeignFetchHeadPath = $FetchHead
        $script:ForeignFetchHead = $OldHead
        function script:Invoke-JobsPullGit {
            param([string]$Git, [string]$Directory, [string[]]$Arguments, [switch]$AllowFailure, [switch]$Display, [int]$TimeoutSeconds = 60)
            $result = & $script:RealPullGit @PSBoundParameters
            if ($Arguments[0] -eq 'fetch') { [IO.File]::WriteAllText($script:ForeignFetchHeadPath, ($script:ForeignFetchHead + "`t`tforeign fetch`n")) }
            return $result
        }
    } $fetchHeadPath $f.Head
    try {
        $result = Invoke-PullFixture $f.Worker
        Assert-Pull ((Git-Fixture $f.Worker @('rev-parse', 'HEAD')) -eq $latest) '外部更新 FETCH_HEAD 不改变本次私有来源引用'
    } finally {
        & $module { Set-Item -LiteralPath Function:script:Invoke-JobsPullGit -Value $script:RealPullGit }
    }

    Write-Host ('PASS: GitPuller.Tests.ps1 (' + $script:assertions + ' assertions; temporary bare remotes only)')
} finally {
    if ($null -ne $module) { Remove-Module $module }
    $env:LOCALAPPDATA = $savedLocal
    $env:GIT_CONFIG_GLOBAL = $savedGlobal
    $env:GIT_CONFIG_NOSYSTEM = $savedSystem
    foreach ($name in $savedGitEnvironment.Keys) { if ($null -eq $savedGitEnvironment[$name]) { Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable($name, $savedGitEnvironment[$name], 'Process') } }
    Remove-Item -LiteralPath $temporary -Recurse -Force
}

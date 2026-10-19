# Action.psm1
# JobsGitPuller
# Created by Jobs on 2026年10月19日，星期一.
<#
仅整合当前分支唯一 upstream；普通目录静默返回，不递归子模块。
有改动时空行确认；快照保留 HEAD、index 与包含未跟踪文件的 stash 对象。
冲突三选一：恢复、精确 YES 后放弃本轮改动、输入可为空的消息提交后重试。
所有快照引用与恢复记录保留；不 pop/drop stash，不清理忽略文件或嵌套仓库。
#>

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking

function Write-JobsPullMessage {
    param([string]$Message)
    $safe = $Message -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@'
    $safe = $safe -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]'
    $safe = $safe -replace '(?im)((?:authorization|access[_-]?token|password|secret)\s*[:=]\s*)[^\r\n]+', '$1[已省略]'
    Write-Host $safe
    Write-JobsLog $safe
}

function Read-JobsPullInput {
    param([string]$Prompt)
    Write-Host ($Prompt + '：') -NoNewline
    return [Console]::ReadLine()
}

function Assert-JobsOrdinaryDirectory {
    param([string]$Path)
    if (-not [IO.Path]::IsPathRooted($Path) -or -not [IO.Directory]::Exists($Path)) { throw '目标必须为已存在的绝对目录。' }
    $item = New-Object IO.DirectoryInfo ([IO.Path]::GetFullPath($Path))
    $current = $item
    while ($null -ne $current) {
        if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw '不处理符号链接、目录联接或重解析目录。' }
        $current = $current.Parent
    }
    return $item.FullName
}

function Invoke-JobsPullGit {
    param([string]$Git, [string]$Directory, [string[]]$Arguments, [switch]$AllowFailure, [switch]$Display, [int]$TimeoutSeconds = 60)
    $result = Invoke-JobsProcess -FilePath $Git -Arguments (@('-c', 'submodule.recurse=false', '-c', 'merge.autoStash=false') + $Arguments) -WorkingDirectory $Directory -TimeoutSeconds $TimeoutSeconds
    if ($Display -or ($result.ExitCode -ne 0 -and -not $AllowFailure)) {
        if ($result.StdOut) { Write-JobsPullMessage $result.StdOut.TrimEnd() }
        if ($result.StdErr) { Write-JobsPullMessage $result.StdErr.TrimEnd() }
    }
    if ($result.ExitCode -ne 0 -and -not $AllowFailure) { throw ('Git 操作失败，退出码 ' + $result.ExitCode + '：' + $Arguments[0]) }
    return $result
}

function Get-JobsPullValue {
    param([string]$Git, [string]$Directory, [string[]]$Arguments)
    return (Invoke-JobsPullGit $Git $Directory $Arguments).StdOut.TrimEnd("`r", "`n")
}

function Get-JobsPullPlan {
    param([string]$Git, [string]$Directory)
    $branch = Get-JobsPullValue $Git $Directory @('symbolic-ref', '--quiet', '--short', 'HEAD')
    $remote = Get-JobsPullValue $Git $Directory @('config', '--get-all', ('branch.' + $branch + '.remote'))
    $ref = Get-JobsPullValue $Git $Directory @('config', '--get-all', ('branch.' + $branch + '.merge'))
    if (-not $branch -or $remote -eq '.' -or $remote -match '[\r\n]' -or $ref -notmatch '^refs/heads/[^\r\n]+$') {
        throw '需要正常的本地分支及唯一远端 upstream；不猜测 origin 或默认分支。'
    }
    $url = Get-JobsPullValue $Git $Directory @('remote', 'get-url', '--all', '--', $remote)
    if (-not $url -or $url -match '[\r\n]') { throw 'upstream 远端必须只有一个明确的拉取地址。' }
    return @{ Branch = $branch; Remote = $remote; Ref = $ref; Url = $url }
}

function Assert-JobsPullReady {
    param([string]$Git, [string]$Directory)
    foreach ($state in @('MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD', 'rebase-merge', 'rebase-apply', 'sequencer', 'BISECT_START', 'index.lock')) {
        $path = Get-JobsPullValue $Git $Directory @('rev-parse', '--git-path', $state)
        if (-not [IO.Path]::IsPathRooted($path)) { $path = Join-Path $Directory $path }
        if (Test-Path -LiteralPath $path) { throw ('仓库正在执行其它 Git 操作：' + $state + '；请先自行完成。') }
    }
    $sparse = Invoke-JobsPullGit $Git $Directory @('config', '--bool', 'core.sparseCheckout') -AllowFailure
    if ($sparse.ExitCode -gt 1 -or $sparse.StdOut.Trim() -eq 'true') { throw '稀疏检出暂不支持自动快照，已停止。' }
    foreach ($entry in ((Invoke-JobsPullGit $Git $Directory @('ls-files', '-v', '-z')).StdOut -split "`0")) {
        if ($entry -cmatch '^[a-zS] ') { throw '存在 assume-unchanged 或 skip-worktree，已停止。' }
    }
    $gitlinks = @{}
    foreach ($entry in ((Invoke-JobsPullGit $Git $Directory @('ls-files', '--stage', '-z')).StdOut -split "`0")) {
        if ($entry -match '^160000 [0-9a-f]+ [0-3]\t([\s\S]+)$') { $gitlinks[$Matches[1]] = $true }
    }
    foreach ($entry in ((Invoke-JobsPullGit $Git $Directory @('status', '--porcelain=v1', '-z', '--untracked-files=all', '--ignore-submodules=none')).StdOut -split "`0")) {
        if ($entry.Length -gt 3 -and $gitlinks.ContainsKey($entry.Substring(3))) { throw '子模块有未提交改动或指针变化；请先在子仓自行处理。' }
    }
    foreach ($relative in ((Invoke-JobsPullGit $Git $Directory @('ls-files', '--others', '--exclude-standard', '-z')).StdOut -split "`0")) {
        if (-not $relative) { continue }
        $path = Join-Path $Directory $relative
        if (-not (Test-Path -LiteralPath $path)) { throw '未跟踪路径变化，已停止。' }
        $item = Get-Item -LiteralPath $path -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw '未跟踪符号链接暂不支持自动快照，已停止。' }
        if ($item.PSIsContainer -and (Test-Path -LiteralPath (Join-Path $path '.git'))) { throw '存在未跟踪嵌套 Git；请先自行处理，不会清理该目录。' }
    }
    [void](Get-JobsPullValue $Git $Directory @('rev-parse', '--verify', 'HEAD'))
    if ((Invoke-JobsPullGit $Git $Directory @('ls-files', '--unmerged', '-z')).StdOut) { throw '已有未解决冲突，已停止。' }
}

function Get-JobsPullStatus {
    param([string]$Git, [string]$Directory)
    # 子仓内容和检出位置留给子仓自行处理，父仓已暂存 gitlink 仍保留在 index 快照中。
    return (Invoke-JobsPullGit $Git $Directory @('status', '--porcelain=v1', '--untracked-files=all', '--ignore-submodules=all')).StdOut
}


function Get-JobsPullToken {
    param([string]$Git, [string]$Directory)
    $parts = @(
        (Get-JobsPullValue $Git $Directory @('symbolic-ref', '--quiet', 'HEAD')),
        (Get-JobsPullValue $Git $Directory @('rev-parse', 'HEAD')),
        (Invoke-JobsPullGit $Git $Directory @('status', '--porcelain=v1', '-z', '--untracked-files=all', '--ignore-submodules=none')).StdOut,
        (Invoke-JobsPullGit $Git $Directory @('ls-files', '--stage', '-z')).StdOut,
        (Invoke-JobsPullGit $Git $Directory @('ls-files', '-v', '-z')).StdOut,
        (Invoke-JobsPullGit $Git $Directory @('diff', '--no-ext-diff', '--no-textconv', '--binary', '--no-renames', 'HEAD')).StdOut,
        (Invoke-JobsPullGit $Git $Directory @('diff', '--cached', '--no-ext-diff', '--no-textconv', '--binary', '--no-renames')).StdOut
    )
    foreach ($relative in ((Invoke-JobsPullGit $Git $Directory @('ls-files', '--others', '--exclude-standard', '-z')).StdOut -split "`0")) {
        if (-not $relative) { continue }
        $parts += $relative
        $parts += Get-JobsPullValue $Git $Directory @('hash-object', '--no-filters', '--', (Join-Path $Directory $relative))
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($parts -join "`0")))) }
    finally { $sha.Dispose() }
}

function Assert-JobsPullToken {
    param([string]$Git, [string]$Directory, [string]$Token)
    if ((Get-JobsPullToken $Git $Directory) -cne $Token) { throw '等待输入期间仓库被其它操作修改；保留当前现场，不自动恢复或重置。' }
}

function Get-JobsPullUntracked {
    param([string]$Git, [string]$Directory, [string]$Snapshot)
    $files = @()
    if ($Snapshot) {
        $third = Invoke-JobsPullGit $Git $Directory @('rev-parse', '--verify', ($Snapshot + '^3')) -AllowFailure
        if ($third.ExitCode -eq 0) {
            $tree = (Invoke-JobsPullGit $Git $Directory @('ls-tree', '-r', '-z', ($Snapshot + '^3'))).StdOut
            foreach ($entry in ($tree -split "`0")) {
                if (-not $entry) { continue }
                if ($entry -notmatch '^([0-9]{6}) blob ([0-9a-f]+)\t([\s\S]+)$') { throw '无法解析未跟踪文件快照，已保留恢复引用。' }
                if ($Matches[1] -ne '100644' -and $Matches[1] -ne '100755') { throw '未跟踪符号链接暂不支持自动恢复；快照已保留。' }
                $files += [pscustomobject]@{ Path = $Matches[3]; Blob = $Matches[2] }
            }
        }
    }
    return $files
}

function New-JobsPullSnapshot {
    param([string]$Git, [string]$Directory, [string]$Branch)
    $head = Get-JobsPullValue $Git $Directory @('rev-parse', '--verify', 'HEAD')
    $id = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N')
    $anchor = 'refs/jobs-git-puller/' + $id
    $metadata = Get-JobsPullValue $Git $Directory @('rev-parse', '--git-path', ('jobs-git-puller/' + $id))
    if (-not [IO.Path]::IsPathRooted($metadata)) { $metadata = Join-Path $Directory $metadata }
    [void][IO.Directory]::CreateDirectory($metadata)
    [void](Invoke-JobsPullGit $Git $Directory @('update-ref', ($anchor + '/head'), $head))
    $index = Get-JobsPullValue $Git $Directory @('rev-parse', '--git-path', 'index')
    if (-not [IO.Path]::IsPathRooted($index)) { $index = Join-Path $Directory $index }
    if ([IO.File]::Exists($index)) { [IO.File]::Copy($index, (Join-Path $metadata 'index.before'), $false) }
    $session = @{ Head = $head; ExpectedHead = $head; Branch = $Branch; Snapshot = ''; Anchor = $anchor; Metadata = $metadata; Untracked = @(); Applied = $false }
    $before = Invoke-JobsPullGit $Git $Directory @('rev-parse', '--verify', 'refs/stash') -AllowFailure
    $status = Get-JobsPullStatus $Git $Directory
    if ($status) {
        $saved = Invoke-JobsPullGit $Git $Directory @('stash', 'push', '--include-untracked', '--message', ('JobsGitPuller ' + $id)) -AllowFailure -Display
        $after = Invoke-JobsPullGit $Git $Directory @('rev-parse', '--verify', 'refs/stash') -AllowFailure
        if ($after.ExitCode -eq 0 -and $after.StdOut -cne $before.StdOut) {
            $candidate = $after.StdOut.Trim()
            $parent = Get-JobsPullValue $Git $Directory @('rev-parse', ($candidate + '^1'))
            $subject = Get-JobsPullValue $Git $Directory @('show', '-s', '--format=%s', $candidate)
            if ($parent -cne $head -or -not $subject.EndsWith(('JobsGitPuller ' + $id), [StringComparison]::Ordinal)) { throw 'stash 身份与本次快照不符；停止并保留现场，不认领其它会话的 stash。' }
            $session.Snapshot = $candidate
            [void](Invoke-JobsPullGit $Git $Directory @('update-ref', ($anchor + '/worktree'), $session.Snapshot))
        }
        $session | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $metadata 'recovery.json') -Encoding UTF8
        Write-JobsPullMessage ('恢复锚点：' + $anchor + '；记录：' + $metadata)
        if ($saved.ExitCode -ne 0) { throw '快照未完整成功；未开始合并。现场和已生成恢复锚点保留，请核对 recovery.json。' }
        $session.Untracked = @(Get-JobsPullUntracked $Git $Directory $session.Snapshot)
        if (Get-JobsPullStatus $Git $Directory) { throw '快照后仍有未提交或未跟踪内容；未开始合并，恢复锚点保留。' }
    }
    $session | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $metadata 'recovery.json') -Encoding UTF8
    Write-JobsPullMessage ('本轮恢复锚点：' + $anchor)
    return $session
}

function Assert-JobsPullIdentity {
    param([string]$Git, [string]$Directory, [hashtable]$Session)
    $branch = Get-JobsPullValue $Git $Directory @('symbolic-ref', '--quiet', '--short', 'HEAD')
    $head = Get-JobsPullValue $Git $Directory @('rev-parse', 'HEAD')
    if ($branch -cne $Session.Branch -or $head -cne $Session.ExpectedHead) { throw '分支或 HEAD 被其它操作改变；不自动重置，恢复锚点保留。' }
}

function Remove-JobsPullSnapshotFiles {
    param([string]$Git, [string]$Directory, [hashtable]$Session)
    $remove = @()
    foreach ($entry in $Session.Untracked) {
        $path = Join-Path $Directory $entry.Path
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $parent = [IO.Path]::GetDirectoryName($path)
        [void](Assert-JobsOrdinaryDirectory $parent)
        while ($parent -and $parent -ne $Directory) {
            if (Test-Path -LiteralPath (Join-Path $parent '.git')) { throw '未跟踪路径现在属于嵌套 Git；不清理，恢复锚点保留。' }
            $parent = [IO.Path]::GetDirectoryName($parent)
        }
        $item = Get-Item -LiteralPath $path -Force
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw '未跟踪路径类型改变；不清理，恢复锚点保留。' }
        $tracked = Invoke-JobsPullGit $Git $Directory @('ls-files', '--error-unmatch', '--', (':(top,literal)' + $entry.Path)) -AllowFailure
        if ($tracked.ExitCode -eq 0) { continue }
        $blob = Get-JobsPullValue $Git $Directory @('hash-object', ('--path=' + $entry.Path), '--', $path)
        if ($blob -cne $entry.Blob) { throw ('未跟踪文件在操作期间改变，停止自动清理：' + $entry.Path) }
        $remove += $path
    }
    # 先逐个核验，再只移除快照内相同内容的文件；不用 clean 或递归目录删除。
    foreach ($path in $remove) { Remove-Item -LiteralPath $path -Force }
}

function Restore-JobsPullSnapshot {
    param([string]$Git, [string]$Directory, [hashtable]$Session)
    Assert-JobsPullIdentity $Git $Directory $Session
    Remove-JobsPullSnapshotFiles $Git $Directory $Session
    [void](Invoke-JobsPullGit $Git $Directory @('reset', '--hard', '--no-recurse-submodules', $Session.Head) -Display)
    $Session.ExpectedHead = $Session.Head
    # reset 可能把本轮新增 tracked 路径变回 untracked，再核验一次精确清理。
    Remove-JobsPullSnapshotFiles $Git $Directory $Session
    if ($Session.Snapshot) { [void](Invoke-JobsPullGit $Git $Directory @('stash', 'apply', '--index', $Session.Snapshot) -Display) }
    $Session.Applied = $true
    Write-JobsPullMessage ('已恢复本轮拉取前的 HEAD、暂存区与工作文件：' + $Session.Head)
}

function Assert-JobsPullMergePaths {
    param([string]$Git, [string]$Directory, [string]$Head, [string]$Fetched)
    $changes = (Invoke-JobsPullGit $Git $Directory @('diff', '--name-only', '-z', $Head, $Fetched)).StdOut
    $gitlinks = @{}
    foreach ($entry in ((Invoke-JobsPullGit $Git $Directory @('ls-files', '--stage', '-z')).StdOut -split "`0")) {
        if ($entry -match '^160000 [0-9a-f]+ [0-3]\t([\s\S]+)$') { $gitlinks[$Matches[1]] = $true }
    }
    foreach ($relative in ($changes -split "`0")) {
        if (-not $relative -or $gitlinks.ContainsKey($relative)) { continue }
        $path = Join-Path $Directory $relative
        $current = $path
        while ($current -and $current -ne $Directory) {
            if (Test-Path -LiteralPath $current) {
                $item = Get-Item -LiteralPath $current -Force
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ('上游路径穿过符号链接，不自动合并：' + $relative) }
                if ($item.PSIsContainer -and (Test-Path -LiteralPath (Join-Path $current '.git'))) { throw ('上游路径进入嵌套 Git，不自动合并：' + $relative) }
            }
            $current = [IO.Path]::GetDirectoryName($current)
        }
    }
}

function Receive-JobsPullUpstream {
    param([string]$Git, [string]$Directory, [hashtable]$Plan)
    $fresh = Get-JobsPullPlan $Git $Directory
    foreach ($key in @('Branch', 'Remote', 'Ref', 'Url')) {
        if ($fresh[$key] -cne $Plan[$key]) { throw 'upstream 或分支配置改变，已停止。' }
    }
    Write-JobsPullMessage ('拉取来源：' + $Plan.Remote + '；' + $Plan.Url + '；分支：' + $Plan.Ref)
    $targetRef = 'refs/jobs-git-puller/' + [guid]::NewGuid().ToString('N') + '/upstream'
    [void](Invoke-JobsPullGit $Git $Directory @('fetch', '--no-tags', '--recurse-submodules=no', '--', $Plan.Remote, ($Plan.Ref + ':' + $targetRef)) -TimeoutSeconds 180 -Display)
    return Get-JobsPullValue $Git $Directory @('rev-parse', '--verify', ($targetRef + '^{commit}'))
}

function Test-JobsPullConflict {
    param([string]$Git, [string]$Directory, [object]$Result, [switch]$Applying)
    $details = $Result.StdOut + $Result.StdErr
    if ($details -match '(?i)permission denied|no space left|read-only file system|cannot create|unable to create|could not write|failed to write|unpack failed') { return $false }
    if ((Invoke-JobsPullGit $Git $Directory @('ls-files', '--unmerged', '-z')).StdOut) { return $true }
    # --index 以及 untracked 恢复冲突可能没有 unmerged index 条目。
    return $Applying -and ($details -match '(?im)^CONFLICT(?:\s|:)|^error: conflicts in index|^error: patch failed:|^error: .+: patch does not apply|^[^\r\n]+ already exists, no checkout\r?$')
}

function New-JobsPullLocalCommit {
    param([string]$Git, [string]$Directory, [hashtable]$Session, [AllowEmptyString()][string]$Message)
    $paths = @('.')
    foreach ($entry in ((Invoke-JobsPullGit $Git $Directory @('ls-files', '--stage', '-z')).StdOut -split "`0")) {
        if ($entry -match '^160000 [0-9a-f]+ [0-3]\t([\s\S]+)$') { $paths += ':(top,exclude,literal)' + $Matches[1] }
    }
    [void](Invoke-JobsPullGit $Git $Directory (@('add', '-u', '--') + $paths))
    foreach ($entry in $Session.Untracked) {
        [void](Invoke-JobsPullGit $Git $Directory @('add', '--', (':(top,literal)' + $entry.Path)))
    }
    $messagePath = Join-Path $Session.Metadata 'commit-message.txt'
    [IO.File]::WriteAllText($messagePath, $Message, (New-Object Text.UTF8Encoding($false)))
    [void](Invoke-JobsPullGit $Git $Directory @('commit', '--allow-empty-message', '--file', $messagePath) -Display -TimeoutSeconds 180)
}

function Invoke-JobsGitAction {
    param([string]$Directory)
    $names = @('GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR', 'GIT_INDEX_FILE', 'GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_NAMESPACE', 'LC_ALL', 'GIT_TERMINAL_PROMPT', 'GIT_MERGE_AUTOEDIT')
    $environment = @{}
    $lock = $null
    try {
        foreach ($name in $names) { $environment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process'); Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue }
        $env:LC_ALL = 'C'
        $env:GIT_TERMINAL_PROMPT = '0'
        $env:GIT_MERGE_AUTOEDIT = 'no'
        $git = Find-JobsExecutable -Name 'git.exe' -Candidates @('git')
        if (-not $git) { throw '需要 Git for Windows；请先安装 Git，再运行本功能。' }
        $probe = Invoke-JobsPullGit $git $Directory @('rev-parse', '--is-inside-work-tree') -AllowFailure
        if ($probe.ExitCode -ne 0 -or $probe.StdOut.Trim() -ne 'true') { return }
        $Directory = Assert-JobsOrdinaryDirectory (Get-JobsPullValue $git $Directory @('rev-parse', '--show-toplevel'))
        $common = Get-JobsPullValue $git $Directory @('rev-parse', '--git-common-dir')
        if (-not [IO.Path]::IsPathRooted($common)) { $common = Join-Path $Directory $common }
        $lockPath = Join-Path $common 'jobs-git-puller.lock'
        try { $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
        catch { throw '此工作树已有 Git 拉取窗口运行；请先完成那个窗口。' }
        Assert-JobsPullReady $git $Directory
        $plan = Get-JobsPullPlan $git $Directory
        $head = Get-JobsPullValue $git $Directory @('rev-parse', 'HEAD')
        $status = Get-JobsPullStatus $git $Directory
        $token = Get-JobsPullToken $git $Directory
        Write-JobsPullMessage ('工作目录：' + $Directory + '；当前分支：' + $plan.Branch)
        Write-JobsPullMessage '将 fetch 并 merge 当前分支 upstream；保留本地已提交历史。不要同时编辑或运行其它 Git 操作。'
        if ($status) {
            Write-JobsPullMessage ('有未提交内容：' + [Environment]::NewLine + $status)
            $answer = Read-JobsPullInput '直接回车确认保护改动并继续；任何字符取消'
            Assert-JobsPullToken $git $Directory $token
            if ($null -eq $answer -or $answer -cne '') { return }
        }
        # fetch 不修改 index/worktree，先确认网络可用，失败不触碰本地改动。
        $fetched = Receive-JobsPullUpstream $git $Directory $plan
        Assert-JobsPullToken $git $Directory $token
        Assert-JobsPullReady $git $Directory
        $session = New-JobsPullSnapshot $git $Directory $plan.Branch
        while ($true) {
            Assert-JobsPullIdentity $git $Directory $session
            try {
                Assert-JobsPullMergePaths $git $Directory $session.Head $fetched
                $merged = Invoke-JobsPullGit $git $Directory @('merge', '--commit', '--no-squash', '--no-edit', '--no-autostash', '--no-overwrite-ignore', $fetched) -AllowFailure -Display -TimeoutSeconds 180
                $session.ExpectedHead = Get-JobsPullValue $git $Directory @('rev-parse', 'HEAD')
                $conflict = $false
                if ($merged.ExitCode -ne 0) { $conflict = Test-JobsPullConflict $git $Directory $merged }
                else {
                    [void](Invoke-JobsPullGit $git $Directory @('merge-base', '--is-ancestor', $fetched, 'HEAD'))
                    $mergeState = Invoke-JobsPullGit $git $Directory @('rev-parse', '--verify', 'MERGE_HEAD') -AllowFailure
                    if ($mergeState.ExitCode -eq 0) { throw '合并未完成提交，停止并恢复本轮基线。' }
                }
                if ($merged.ExitCode -eq 0 -and $session.Snapshot) {
                    $applied = Invoke-JobsPullGit $git $Directory @('stash', 'apply', '--index', $session.Snapshot) -AllowFailure -Display
                    $session.Applied = $applied.ExitCode -eq 0
                    if ($applied.ExitCode -ne 0) {
                        $conflict = Test-JobsPullConflict $git $Directory $applied -Applying
                        if (-not $conflict) { throw '恢复本地改动失败，按普通错误处理。' }
                    }
                }
                if (-not $conflict) {
                    if ($merged.ExitCode -ne 0) { throw '合并因非冲突原因失败；不会进入放弃改动菜单。' }
                    Write-JobsPullMessage ('已整合 upstream ' + $plan.Remote + '/' + $plan.Ref + '；提交：' + $session.ExpectedHead)
                    Write-JobsPullMessage ('本地改动已恢复；恢复锚点继续保留：' + $session.Anchor)
                    return
                }
            } catch {
                Write-JobsPullMessage ('操作失败，尝试恢复本轮基线；锚点：' + $session.Anchor)
                Restore-JobsPullSnapshot $git $Directory $session
                throw
            }
            Write-JobsPullMessage '出现代码、暂存区或未跟踪路径冲突。提交本地改动仍可能再次产生代码冲突。'
            Write-JobsPullMessage '1：恢复本轮拉取前状态并退出；2：放弃本轮未提交内容后重试；3：恢复后提交，再重试。'
            $conflictToken = Get-JobsPullToken $git $Directory
            $choice = Read-JobsPullInput '输入 1 / 2 / 3；空行或输入结束按 1 恢复'
            Assert-JobsPullToken $git $Directory $conflictToken
            if ($null -eq $choice -or $choice -eq '' -or $choice -eq '1') { Restore-JobsPullSnapshot $git $Directory $session; return }
            if ($choice -notin @('2', '3')) { Write-JobsPullMessage '无效选项，按 1 恢复并退出。'; Restore-JobsPullSnapshot $git $Directory $session; return }
            if ($choice -eq '2') {
                $answer = Read-JobsPullInput '将丢弃本轮已跟踪改动和快照内未跟踪文件；精确输入 YES 继续'
                Assert-JobsPullToken $git $Directory $conflictToken
                if ($answer -cne 'YES') { Restore-JobsPullSnapshot $git $Directory $session; return }
            }
            Restore-JobsPullSnapshot $git $Directory $session
            if ($choice -eq '2') {
                Remove-JobsPullSnapshotFiles $git $Directory $session
                [void](Invoke-JobsPullGit $git $Directory @('reset', '--hard', '--no-recurse-submodules', $session.Head) -Display)
            } else {
                if (-not (Get-JobsPullStatus $git $Directory)) { Write-JobsPullMessage '没有可提交的本地改动；已恢复本轮基线，请人工解决已提交历史冲突。'; return }
                $commitToken = Get-JobsPullToken $git $Directory
                $message = Read-JobsPullInput '输入 Commit 信息；直接回车以空消息提交；输入结束取消'
                Assert-JobsPullToken $git $Directory $commitToken
                if ($null -eq $message) { return }
                New-JobsPullLocalCommit $git $Directory $session $message
            }
            # 已确认的放弃或提交成为下一轮基线；最初快照仍可人工恢复。
            $session = New-JobsPullSnapshot $git $Directory $plan.Branch
            try { $fetched = Receive-JobsPullUpstream $git $Directory $plan }
            catch { Restore-JobsPullSnapshot $git $Directory $session; throw }
        }
    } finally {
        if ($null -ne $lock) { $lock.Dispose() }
        foreach ($name in $names) { if ($null -eq $environment[$name]) { Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable($name, $environment[$name], 'Process') } }
    }
}

function Invoke-JobsFeature {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Target)
    $directory = Assert-JobsOrdinaryDirectory (Resolve-JobsTarget -Target $Target)
    Invoke-JobsGitAction -Directory $directory
}

Export-ModuleMember -Function Invoke-JobsFeature

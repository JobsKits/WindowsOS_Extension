# Action.psm1
# JobsGitEmptyCommitPusher
# Created by Jobs on 2026年10月18日，星期日.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking

function Write-JobsWorkerMessage {
    param([string]$Message)
    $safe = $Message -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@'
    $safe = $safe -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]'
    $safe = $safe -replace '(?im)(authorization\s*[:=]\s*)[^\r\n]+', '$1[已省略]'
    $safe = $safe -replace '(?im)((?:access[_-]?token|authorization|password|secret)\s*[:=]\s*)\S+', '$1[已省略]'
    Write-Host $safe
    Write-JobsLog $safe
}

function Assert-JobsOrdinaryDirectory {
    param([string]$Path)
    if (-not [IO.Path]::IsPathRooted($Path) -or -not [IO.Directory]::Exists($Path)) {
        throw "目标必须是已存在的绝对目录：$Path"
    }
    $directory = New-Object IO.DirectoryInfo ([IO.Path]::GetFullPath($Path))
    $current = $directory
    while ($null -ne $current) {
        if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "不处理符号链接、目录联接或其它重解析目录：$($current.FullName)"
        }
        $current = $current.Parent
    }
    return $directory.FullName
}

function Invoke-JobsCheckedProcess {
    param([string]$Executable, [string[]]$Arguments, [string]$Directory,
        [int]$TimeoutSeconds = 30, [switch]$Quiet)
    Write-JobsLog ("执行：{0} {1}" -f $Executable, (($Arguments | ForEach-Object { Quote-JobsArgument $_ }) -join ' '))
    $result = Invoke-JobsProcess -FilePath $Executable -Arguments $Arguments -WorkingDirectory $Directory -TimeoutSeconds $TimeoutSeconds
    if (-not $Quiet) {
        if ($result.StdOut) { Write-JobsWorkerMessage $result.StdOut.TrimEnd() }
        if ($result.StdErr) { Write-JobsWorkerMessage $result.StdErr.TrimEnd() }
    }
    if ($result.ExitCode -ne 0) {
        if ($Quiet -and $result.StdErr) { Write-JobsWorkerMessage $result.StdErr.TrimEnd() }
        throw "命令失败（退出码 $($result.ExitCode)）：$Executable"
    }
    return $result
}

function Get-JobsGitConfig {
    param([string]$Git, [string]$Directory, [string]$Key)
    $result = Invoke-JobsProcess -FilePath $Git -Arguments @('config', '--get-all', $Key) -WorkingDirectory $Directory
    if ($result.ExitCode -eq 1 -and -not $result.StdOut -and -not $result.StdErr) { return @() }
    if ($result.ExitCode -ne 0) { throw "Git 配置读取失败：$Key" }
    return @($result.StdOut.TrimEnd("`r", "`n") -split '\r?\n')
}

function Assert-JobsGitIndexEmpty {
    param([string]$Git, [string]$Directory)
    $result = Invoke-JobsProcess -FilePath $Git -Arguments @('diff', '--cached', '--quiet', '--exit-code') -WorkingDirectory $Directory
    if ($result.ExitCode -eq 1) { throw '暂存区非空，禁止创建空白 Commit；请先自行处理暂存内容。' }
    if ($result.ExitCode -ne 0) { throw '无法核对 Git 暂存区，已停止。' }
}

function Get-JobsGitPushPlan {
    param([string]$Git, [string]$Directory)
    $branch = (Invoke-JobsCheckedProcess $Git @('symbolic-ref', '--quiet', '--short', 'HEAD') $Directory -Quiet).StdOut.Trim()
    if (-not $branch) { throw '当前为游离 HEAD，禁止提交和推送。' }
    $remotes = @(Get-JobsGitConfig $Git $Directory "branch.$branch.remote")
    $merges = @(Get-JobsGitConfig $Git $Directory "branch.$branch.merge")
    if ($remotes.Count -ne 1 -or $merges.Count -ne 1 -or $remotes[0] -eq '.' -or $merges[0] -notmatch '^refs/heads/.+') {
        throw '当前分支必须已有唯一的远端 upstream 分支。'
    }
    $remote = $remotes[0]
    $remoteRef = $merges[0]
    [void](Invoke-JobsCheckedProcess $Git @('rev-parse', '--verify', '@{upstream}') $Directory -Quiet)
    foreach ($key in @("branch.$branch.pushRemote", 'remote.pushDefault')) {
        $values = @(Get-JobsGitConfig $Git $Directory $key)
        if ($values.Count -gt 1 -or ($values.Count -eq 1 -and $values[0] -ne $remote)) { throw "推送配置与 upstream 不一致：$key" }
    }
    $mirror = @(Get-JobsGitConfig $Git $Directory "remote.$remote.mirror")
    if (@($mirror | Where-Object { $_ -ne 'false' }).Count -gt 0) { throw '拒绝 mirror 推送配置。' }
    if (@(Get-JobsGitConfig $Git $Directory "remote.$remote.push").Count -gt 0) { throw '存在自定义 remote.push 映射，请先消除推送歧义。' }
    if (@(Get-JobsGitConfig $Git $Directory 'push.pushOption').Count -gt 0) { throw '存在额外 pushOption，请先确认并清理该推送歧义。' }
    $urls = (Invoke-JobsCheckedProcess $Git @('remote', 'get-url', '--push', '--all', '--', $remote) $Directory -Quiet).StdOut.TrimEnd("`r", "`n") -split '\r?\n'
    if ($urls.Count -ne 1 -or -not $urls[0]) { throw '推送必须只有一个已配置地址。' }
    return @{ Branch = $branch; Remote = $remote; Ref = $remoteRef; Url = $urls[0] }
}

function Invoke-JobsGitAction {
    param([string]$Directory)
    # 清除会把操作重定向至其它工作树或索引的环境变量，仅影响本次工作进程。
    foreach ($name in @('GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR', 'GIT_INDEX_FILE', 'GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_NAMESPACE')) {
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }
    $git = Find-JobsExecutable -Name 'git.exe' -Candidates @()
    if (-not $git) {
        Start-Process -FilePath 'https://git-scm.com/download/win'
        throw '缺少 Git，已打开官方下载页。'
    }
    [void](Invoke-JobsCheckedProcess $git @('--version') $Directory)
    if ((Invoke-JobsCheckedProcess $git @('rev-parse', '--is-inside-work-tree') $Directory -Quiet).StdOut.Trim() -ne 'true') { throw '目标不在 Git 工作树中。' }
    foreach ($state in @('MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD', 'rebase-merge', 'rebase-apply', 'sequencer')) {
        $statePath = (Invoke-JobsCheckedProcess $git @('rev-parse', '--git-path', $state) $Directory -Quiet).StdOut.Trim()
        if (-not [IO.Path]::IsPathRooted($statePath)) { $statePath = Join-Path $Directory $statePath }
        if (Test-Path -LiteralPath $statePath) { throw "仓库正在合并、变基或拣选：$state；请先自行完成。" }
    }
    Assert-JobsGitIndexEmpty $git $Directory
    $plan = Get-JobsGitPushPlan $git $Directory
    $displayUrl = $plan.Url -replace '(?i)(https?://)[^/@]+@', '$1***@'
    Write-JobsWorkerMessage "工作目录：$Directory"
    Write-JobsWorkerMessage "当前分支：$($plan.Branch)"
    Write-JobsWorkerMessage "推送远端：$($plan.Remote)；来源/目标：$displayUrl"
    Write-JobsWorkerMessage "唯一目标：HEAD -> $($plan.Ref)"
    Write-JobsWorkerMessage '将创建一个空白 Commit 并推送；不会暂存文件。推送失败时本地 Commit 会保留。'
    if ((Read-Host '精确输入 YES 确认；其它输入取消') -cne 'YES') { throw '已取消。' }
    [void](Assert-JobsOrdinaryDirectory $Directory)
    $freshPlan = Get-JobsGitPushPlan $git $Directory
    foreach ($key in @('Branch', 'Remote', 'Ref', 'Url')) {
        if ($freshPlan[$key] -cne $plan[$key]) { throw '确认后分支或推送配置已变化，已停止。' }
    }
    Assert-JobsGitIndexEmpty $git $Directory
    $tree = (Invoke-JobsCheckedProcess $git @('rev-parse', 'HEAD^{tree}') $Directory -Quiet).StdOut.Trim()
    $message = 'Jobs: empty commit ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    [void](Invoke-JobsCheckedProcess $git @('commit', '--allow-empty', '--only', '-m', $message) $Directory 120)
    $commit = (Invoke-JobsCheckedProcess $git @('rev-parse', 'HEAD') $Directory -Quiet).StdOut.Trim()
    $newTree = (Invoke-JobsCheckedProcess $git @('rev-parse', 'HEAD^{tree}') $Directory -Quiet).StdOut.Trim()
    if ($newTree -ne $tree) { throw "提交树发生变化，已停止推送；保留本地 Commit $commit 供检查。" }
    $afterCommit = Get-JobsGitPushPlan $git $Directory
    foreach ($key in @('Branch', 'Remote', 'Ref', 'Url')) {
        if ($afterCommit[$key] -cne $plan[$key]) { throw "提交后推送配置已变化；保留本地 Commit $commit，不推送。" }
    }
    try {
        [void](Invoke-JobsCheckedProcess $git @('push', '--porcelain', '--no-follow-tags', '--recurse-submodules=no', '--', $plan.Url, ($commit + ':' + $plan.Ref)) $Directory 180)
    } catch {
        Write-JobsWorkerMessage "推送失败；本地 Commit $commit 已保留。请检查网络、权限或远端进度，再手动处理。"
        throw
    }
    Write-JobsWorkerMessage "空白 Commit $commit 已推送至 $($plan.Remote)/$($plan.Ref)。"
}

function Invoke-JobsFeature {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Target)

    $directory = Assert-JobsOrdinaryDirectory -Path (Resolve-JobsTarget -Target $Target)
    Invoke-JobsGitAction -Directory $directory
}

Export-ModuleMember -Function Invoke-JobsFeature

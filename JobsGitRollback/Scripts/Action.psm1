# Action.psm1 | JobsGitRollback
# Created by Jobs on 2026年10月26日，星期一.
# 仅回退所选目录的最近 Git 工作树；不递归重置子仓，不联网、不推送。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking

# 展示与日志使用脱敏副本，不改写业务参数。
function Write-JobsRollbackMessage {
    param([string]$Message)
    $safe = $Message -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@' -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]'
    Write-Host $safe
    Write-JobsLog $safe
}
# 元数据与工作树都拒绝链接，避免回退越过用户所选边界。
function Assert-JobsRollbackPlainPath {
    param([string]$Path, [bool]$Directory)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ([bool]$item.PSIsContainer -ne $Directory) { throw '路径类型不符。' }
    $current = $item
    while ($null -ne $current) {
        if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw '不处理链接、目录联接或重解析路径。' }
        if ($current -is [IO.DirectoryInfo]) { $current = $current.Parent } else { $current = $current.Directory }
    }
    return $item.FullName
}
# 限量读取单行 UTF8 元数据，不把任意目录当成 Git。
function Read-JobsRollbackMetadata {
    param([string]$Path)
    [void](Assert-JobsRollbackPlainPath $Path $false)
    if ((Get-Item -LiteralPath $Path -Force).Length -gt 8192) { throw 'Git 元数据超过支持大小。' }
    $text = (New-Object Text.UTF8Encoding($false, $true)).GetString([IO.File]::ReadAllBytes($Path)).TrimEnd("`r", "`n")
    if (-not $text -or $text -match '[\r\n\x00]') { throw 'Git 元数据格式无效。' }
    return $text
}
# 元数据只接受确定的本地绝对路径或相对路径，拒绝 UNC 和驱动器相对写法。
function Resolve-JobsRollbackMetadataPath {
    param([string]$Base, [string]$Value)
    if (-not $Value -or $Value -match '^[\\/]{2}' -or $Value -match '^[A-Za-z]:($|[^\\/])') { throw '不支持网络或驱动器相对 Git 元数据路径。' }
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT -and $Value -match '^[\\/]') { throw 'Git 元数据必须使用明确驱动器。' }
    if (-not [IO.Path]::IsPathRooted($Value)) { $Value = Join-Path $Base $Value }
    return [IO.Path]::GetFullPath($Value)
}
# 支持普通 gitdir、子模块 gitfile 和 worktree commondir。
function Test-JobsRollbackMetadata {
    param([string]$Directory)
    try {
        [void](Assert-JobsRollbackPlainPath $Directory $true)
        $head = Read-JobsRollbackMetadata (Join-Path $Directory 'HEAD')
        if ($head -notmatch '^(ref: refs/[^\s~^:?*\[\\]+|[0-9a-fA-F]{40}|[0-9a-fA-F]{64})$' -or $head -match '\.\.|@\{' -or $head.EndsWith('/') -or $head.EndsWith('.')) { return $false }
        $common = $Directory
        $commonFile = Join-Path $Directory 'commondir'
        if (Test-Path -LiteralPath $commonFile) {
            $common = Read-JobsRollbackMetadata $commonFile
            $common = Resolve-JobsRollbackMetadataPath $Directory $common
        }
        [void](Assert-JobsRollbackPlainPath $common $true)
        [void](Assert-JobsRollbackPlainPath (Join-Path $common 'objects') $true)
        $references = Join-Path $common 'refs'
        if (-not (Test-Path -LiteralPath $references -PathType Container)) { $references = Join-Path $common 'reftable' }
        [void](Assert-JobsRollbackPlainPath $references $true)
        [void](Assert-JobsRollbackPlainPath (Join-Path $common 'config') $false)
        return $true
    } catch { return $false }
}
# 最近内层 .git 一旦出现必须有效；无效时禁止继续向上误操作父仓。
function Get-JobsRollbackBoundary {
    param([string]$Target)
    if (-not [IO.Path]::IsPathRooted($Target) -or $Target -match '^[\\/]{2}') { throw '目标必须为本地绝对目录，不支持网络共享。' }
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT -and $Target -notmatch '^[A-Za-z]:[\\/]') { throw '目标必须包含明确的本地驱动器。' }
    $directory = Assert-JobsRollbackPlainPath $Target $true
    $scan = New-Object IO.DirectoryInfo $directory
    while ($null -ne $scan) {
        if ($scan.Name -ieq '.git' -or (Test-JobsRollbackMetadata $scan.FullName)) { throw 'Git 元数据内部和裸仓不提供回退。' }
        $marker = Join-Path $scan.FullName '.git'
        if (Test-Path -LiteralPath $marker) {
            $item = Get-Item -LiteralPath $marker -Force
            if ($item.PSIsContainer) { $metadata = Assert-JobsRollbackPlainPath $marker $true }
            else {
                $text = Read-JobsRollbackMetadata $marker
                if (-not $text.StartsWith('gitdir: ', [StringComparison]::Ordinal) -or $text.Length -le 8) { throw '内层 .git 文件无效；不回退父仓。' }
                $metadata = $text.Substring(8)
                $metadata = Resolve-JobsRollbackMetadataPath $scan.FullName $metadata
            }
            if (-not (Test-JobsRollbackMetadata $metadata)) { throw '最近工作树的 Git 元数据无效；不回退父仓。' }
            return [pscustomobject]@{ Root = $scan.FullName; Metadata = $metadata }
        }
        $scan = $scan.Parent
    }
    throw '目标不在有效 Git 工作树内。'
}
# Git 只接收数组参数，仓库覆盖环境仅从本次子进程移除。
function Invoke-JobsRollbackGit {
    param([string]$Git, [string]$Directory, [string[]]$Arguments, [switch]$AllowFailure)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Git
    $all = @('--no-optional-locks', '-c', 'submodule.recurse=false', '-c', 'diff.autoRefreshIndex=false', '-C', $Directory) + $Arguments
    $start.Arguments = (@($all | ForEach-Object { Quote-JobsArgument $_ }) -join ' ')
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $start.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    foreach ($name in @('GIT_DIR','GIT_WORK_TREE','GIT_COMMON_DIR','GIT_INDEX_FILE','GIT_OBJECT_DIRECTORY','GIT_ALTERNATE_OBJECT_DIRECTORIES','GIT_NAMESPACE','GIT_CONFIG_PARAMETERS','GIT_CONFIG_COUNT','GIT_CEILING_DIRECTORIES','GIT_DISCOVERY_ACROSS_FILESYSTEM')) { $start.EnvironmentVariables.Remove($name) }
    $process = [Diagnostics.Process]::Start($start)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        # reset 写工作树时等待原始结果，不能用读取超时强杀慢盘上的写操作。
        if ($Arguments.Count -gt 0 -and $Arguments[0] -ceq 'reset') { $process.WaitForExit() }
        elseif (-not $process.WaitForExit(30000)) { $process.Kill(); throw 'Git 只读检查超时；未开始本轮回退，请保留现场检查。' }
        $result = [pscustomobject]@{ ExitCode = $process.ExitCode; StdOut = $stdout.GetAwaiter().GetResult(); StdErr = $stderr.GetAwaiter().GetResult() }
        if ($result.ExitCode -ne 0 -and -not $AllowFailure) { throw ('Git 操作失败：' + $Arguments[0] + '；' + $result.StdErr.Trim()) }
        return $result
    } finally { $process.Dispose() }
}
# 将只读 Git 输出保留原始路径字符。
function Get-JobsRollbackValue {
    param($Context, [string[]]$Arguments)
    return (Invoke-JobsRollbackGit $Context.Git $Context.Root $Arguments).StdOut.TrimEnd("`r", "`n")
}
# 游离 HEAD 记录为空身份；显式历史回退仍可用，远端模式另行拒绝。
function Get-JobsRollbackBranch {
    param($Context)
    $result = Invoke-JobsRollbackGit $Context.Git $Context.Root @('symbolic-ref','--quiet','HEAD') -AllowFailure
    if ($result.ExitCode -eq 1) { return '' }
    if ($result.ExitCode -ne 0) { throw '无法读取当前分支身份。' }
    return $result.StdOut.TrimEnd("`r", "`n")
}
# 冲突、未完成事务和索引锁必须先由用户处理。
function Assert-JobsRollbackReady {
    param($Context)
    foreach ($marker in @('MERGE_HEAD','CHERRY_PICK_HEAD','REVERT_HEAD','BISECT_LOG','BISECT_START','rebase-merge','rebase-apply','sequencer','index.lock')) {
        if (Test-Path -LiteralPath (Join-Path $Context.Metadata $marker)) { throw ('存在未完成 Git 操作或锁：' + $marker) }
    }
    if (Get-JobsRollbackValue $Context @('ls-files','--unmerged')) { throw '存在未解决冲突。' }
}
# Windows 路径按文件系统大小写规则比较，引用和提交仍用精确比较。
function Test-JobsRollbackSamePath {
    param([string]$Left, [string]$Right)
    $comparison=[StringComparison]::Ordinal
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { $comparison=[StringComparison]::OrdinalIgnoreCase }
    return [string]::Equals([IO.Path]::GetFullPath($Left),[IO.Path]::GetFullPath($Right),$comparison)
}
# 交互期间身份、分支和 HEAD 改变时停止，避免作用于新现场。
function Assert-JobsRollbackContext {
    param($Context)
    $boundary = Get-JobsRollbackBoundary $Context.Selected
    $root = Get-JobsRollbackValue $Context @('rev-parse','--show-toplevel')
    $metadata = Get-JobsRollbackValue $Context @('rev-parse','--absolute-git-dir')
    $branch = Get-JobsRollbackBranch $Context
    $head = Get-JobsRollbackValue $Context @('rev-parse','--verify','HEAD^{commit}')
    if (-not (Test-JobsRollbackSamePath $root $Context.Root) -or -not (Test-JobsRollbackSamePath $metadata $Context.Metadata) -or -not (Test-JobsRollbackSamePath $boundary.Root $Context.Root) -or $branch -cne $Context.Branch -or $head -cne $Context.Head) { throw '选择或确认期间仓库、分支或 HEAD 已变化；未执行回退。' }
    Assert-JobsRollbackReady $Context
}
# fzf 单选区分选中、返回、取消；左键在无匹配时也优先作为返回。
function Select-JobsRollbackEntry {
    param([string]$Title, [string[]]$Entries, [switch]$Back)
    if (@($Entries).Count -eq 0) { throw ('没有可选择的记录：' + $Title) }
    $fzf = Find-JobsExecutable -Name 'fzf.exe' -Candidates @('fzf')
    if (-not $fzf) { throw '缺少 fzf；请先安装或修复 fzf 后重试，本功能不会自动安装或改为编号菜单。' }
    $health = Invoke-JobsProcess -FilePath $fzf -Arguments @('--version') -TimeoutSeconds 10
    $help = Invoke-JobsProcess -FilePath $fzf -Arguments @('--help') -TimeoutSeconds 10
    if ($health.ExitCode -ne 0 -or $help.ExitCode -ne 0 -or $help.StdOut -notmatch '--expect') { throw 'fzf 版本或所需选项不可用，请修复后重试。' }
    $options = @('--no-sort','--reverse','--no-multi','--prompt',($Title + '：'))
    if ($Back) { $options += @('--expect=left','--header','回车选择，← 返回上一层，Esc 取消') }
    else { $options += @('--header','回车选择，Esc 取消') }
    $previous = $ErrorActionPreference
    $oldOptions = [Environment]::GetEnvironmentVariable('FZF_DEFAULT_OPTS')
    $oldFile = [Environment]::GetEnvironmentVariable('FZF_DEFAULT_OPTS_FILE')
    $hadOptions = Test-Path Env:FZF_DEFAULT_OPTS
    $hadFile = Test-Path Env:FZF_DEFAULT_OPTS_FILE
    $previousOutputEncoding = $OutputEncoding
    $previousConsoleEncoding = [Console]::OutputEncoding
    try {
        $env:FZF_DEFAULT_OPTS = ''
        $env:FZF_DEFAULT_OPTS_FILE = ''
        # Windows PowerShell 5.1 的默认 ASCII 管道会损坏中文模式和提交信息。
        $OutputEncoding = New-Object Text.UTF8Encoding($false)
        [Console]::OutputEncoding = $OutputEncoding
        $ErrorActionPreference = 'Continue'
        $lines = @($Entries | & $fzf @options)
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
        $OutputEncoding = $previousOutputEncoding
        [Console]::OutputEncoding = $previousConsoleEncoding
        if ($hadOptions) { [Environment]::SetEnvironmentVariable('FZF_DEFAULT_OPTS', $oldOptions) }
        else { Remove-Item Env:FZF_DEFAULT_OPTS -ErrorAction SilentlyContinue }
        if ($hadFile) { [Environment]::SetEnvironmentVariable('FZF_DEFAULT_OPTS_FILE', $oldFile) }
        else { Remove-Item Env:FZF_DEFAULT_OPTS_FILE -ErrorAction SilentlyContinue }
    }
    return ConvertFrom-JobsRollbackSelection -Lines $lines -ExitCode $code -Entries $Entries -Back:$Back
}
# 单独解析选择结果，任何列表外返回都不能进入业务。
function ConvertFrom-JobsRollbackSelection {
    param([string[]]$Lines, [int]$ExitCode, [string[]]$Entries, [switch]$Back)
    if ($Back -and @($Lines).Count -gt 0 -and $Lines[0] -ceq 'left') { return @{ Action='Back'; Value='' } }
    if ($ExitCode -in @(1,130)) { return @{ Action='Cancel'; Value='' } }
    if ($ExitCode -ne 0) { throw ('fzf 选择失败，退出码：' + $ExitCode) }
    if ($Back -and @($Lines).Count -gt 0) { $Lines = @($Lines | Select-Object -Skip 1) }
    if (@($Lines).Count -eq 0 -or (@($Lines).Count -eq 1 -and -not $Lines[0])) { return @{ Action='Cancel'; Value='' } }
    if (@($Lines).Count -ne 1 -or $Lines[0] -cnotin $Entries) { throw 'fzf 返回列表外内容；未执行回退。' }
    return @{ Action='Selected'; Value=$Lines[0] }
}
# 收集当前分支各远端本地快照及真实 upstream，不联网刷新。
function Get-JobsRollbackRemoteTarget {
    param($Context)
    if (-not $Context.Branch) { throw '游离 HEAD 没有明确分支，不能回退到远端；可选择历史提交、tag 或 reflog。' }
    $branch = Get-JobsRollbackValue $Context @('symbolic-ref','--quiet','--short','HEAD')
    $refs = @()
    $upstream = Invoke-JobsRollbackGit $Context.Git $Context.Root @('rev-parse','--symbolic-full-name','@{upstream}') -AllowFailure
    if ($upstream.ExitCode -eq 0 -and $upstream.StdOut.Trim().StartsWith('refs/remotes/')) { $refs += $upstream.StdOut.Trim() }
    foreach ($remote in ((Get-JobsRollbackValue $Context @('remote')) -split '\r?\n')) {
        if ($remote) { $refs += 'refs/remotes/' + $remote + '/' + $branch }
    }
    $snapshots = @{}
    $entries = @()
    foreach ($ref in @($refs | Select-Object -Unique)) {
        $valid = Invoke-JobsRollbackGit $Context.Git $Context.Root @('show-ref','--verify','--hash',$ref) -AllowFailure
        if ($valid.ExitCode -ne 0) { continue }
        $commit = Get-JobsRollbackValue $Context @('rev-parse','--verify',($ref + '^{commit}'))
        $entry = $ref + ' [' + $commit + ']'
        $entries += $entry
        $snapshots[$entry] = @{ Ref=$ref; Commit=$commit }
    }
    if ($entries.Count -eq 0) { throw '没有当前分支可用的本地远端跟踪快照；可选择历史提交回退。' }
    if ($entries.Count -gt 1) {
        $choice = Select-JobsRollbackEntry '选择本地远端快照（不联网）' $entries -Back
        if ($choice.Action -cne 'Selected') { return $choice }
        $target = $snapshots[$choice.Value]
    } else { $target = $snapshots[$entries[0]] }
    $now = Get-JobsRollbackValue $Context @('rev-parse','--verify',($target.Ref + '^{commit}'))
    if ($now -cne $target.Commit) { throw '选择期间远端跟踪快照已变化；没有回退。' }
    return @{ Action='Selected'; Value=$target.Commit; Description=$target.Ref }
}
# 真实索引差异决定回退后提示，空提交不会虚报文件变更。
function Write-JobsRollbackStaged {
    param($Context)
    $result = Invoke-JobsRollbackGit $Context.Git $Context.Root @('diff','--cached','--quiet','--ignore-submodules=none') -AllowFailure
    if ($result.ExitCode -eq 0) { Write-JobsRollbackMessage '暂存区相对当前 HEAD 没有文件差异；空提交或内容抵消时属于正常结果。' }
    elseif ($result.ExitCode -eq 1) { Write-JobsRollbackMessage ('待提交差异：' + (Get-JobsRollbackValue $Context @('diff','--cached','--shortstat','--ignore-submodules=none'))) }
    else { throw '无法核对暂存区，请保留现场检查。' }
}
# soft 只接受起始 HEAD 的祖先，不改现有索引和工作树内容。
function Invoke-JobsRollbackSoft {
    param($Context, [string]$Commit, [string]$Description)
    Assert-JobsRollbackContext $Context
    $ancestor = Invoke-JobsRollbackGit $Context.Git $Context.Root @('merge-base','--is-ancestor',$Commit,$Context.Head) -AllowFailure
    if ($ancestor.ExitCode -ne 0) { throw '目标不是当前 HEAD 的祖先，本地可能落后或分叉；未执行回退。' }
    if ($Commit -ceq $Context.Head) { Write-JobsRollbackMessage 'HEAD 已与目标相同，本次没有撤回提交。'; Write-JobsRollbackStaged $Context; return }
    Write-JobsRollbackMessage ('soft 本地回退到 ' + $Description + ' [' + $Commit + ']；保留工作区和索引，其它远端可能已经包含这些提交。')
    Assert-JobsRollbackContext $Context
    [void](Invoke-JobsRollbackGit $Context.Git $Context.Root @('reset','--soft',$Commit))
    Write-JobsRollbackMessage 'soft 回退完成。'
    Write-JobsRollbackStaged $Context
}
# 摘要保护确认期间的索引、已跟踪变化和未跟踪状态。
function Get-JobsRollbackHardState {
    param($Context)
    $index = Get-JobsRollbackValue $Context @('rev-parse','--git-path','index')
    if (-not [IO.Path]::IsPathRooted($index)) { $index = Join-Path $Context.Root $index }
    $digest = 'missing'
    if ([IO.File]::Exists($index)) { $digest = (Get-FileHash -LiteralPath $index -Algorithm SHA256).Hash }
    $data = $digest + "`0" + (Get-JobsRollbackValue $Context @('diff','--no-ext-diff','--no-textconv','--binary','--ignore-submodules=all')) + "`0" + (Get-JobsRollbackValue $Context @('status','--porcelain=v1','-z','--untracked-files=all','--ignore-submodules=none'))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($data))) }
    finally { $sha.Dispose() }
}
# 仅精确 YES 才 reset；固定提交号并再次核对现场，不递归子模块。
function Invoke-JobsRollbackHard {
    param($Context, [string]$Commit, [string]$Description)
    Assert-JobsRollbackContext $Context
    $fixed = Get-JobsRollbackValue $Context @('rev-parse','--verify',($Commit + '^{commit}'))
    $before = Get-JobsRollbackHardState $Context
    Write-JobsRollbackMessage ('仓库：' + $Context.Root + '；hard 回退到 ' + $Description + ' [' + $fixed + ']。已跟踪修改会丢失；阻挡目标检出的未跟踪路径也可能被 Git 删除。子模块工作树不递归重置。')
    $answer = Read-JobsRollbackInput '输入 YES 执行；回车、其它输入或输入结束取消'
    if ($answer -cne 'YES') { Write-JobsRollbackMessage '已取消 hard 回退。'; return }
    Assert-JobsRollbackContext $Context
    if ((Get-JobsRollbackHardState $Context) -cne $before) { throw '确认期间索引或工作区已变化；未执行 hard 回退。' }
    Assert-JobsRollbackContext $Context
    [void](Invoke-JobsRollbackGit $Context.Git $Context.Root @('reset','--hard','--no-recurse-submodules',$fixed))
    Write-JobsRollbackMessage ('hard 回退完成：' + $fixed)
}
# 读取终端确认；不使用 eval 或脚本拼接解释用户输入。
function Read-JobsRollbackInput {
    param([string]$Prompt)
    Write-Host ($Prompt + '：') -NoNewline
    return [Console]::ReadLine()
}
# 六种模式与目标选择组成明确的两级循环，返回重新进入真实上层。
function Invoke-JobsRollbackMenu {
    param($Context)
    $modes = @('soft 回退到 upstream','选择提交 soft 回退','hard 回退到 upstream','选择提交 hard 回退','选择 tag hard 回退','选择 reflog hard 回退')
    while ($true) {
        $mode = Select-JobsRollbackEntry '选择回退模式' $modes
        if ($mode.Action -cne 'Selected') { Write-JobsRollbackMessage '已取消回退。'; return }
        if ($mode.Value -in @('soft 回退到 upstream','hard 回退到 upstream')) { $target = Get-JobsRollbackRemoteTarget $Context }
        else {
            if ($mode.Value -eq '选择 tag hard 回退') { $records = @((Get-JobsRollbackValue $Context @('tag','--sort=-creatordate')) -split '\r?\n' | Where-Object { $_ }) }
            elseif ($mode.Value -eq '选择 reflog hard 回退') { $records = @((Get-JobsRollbackValue $Context @('reflog','--format=%H %gd %gs','--max-count=200')) -split '\r?\n' | Where-Object { $_ }) }
            else { $records = @((Get-JobsRollbackValue $Context @('log','--all','--format=%H %s','--max-count=200')) -split '\r?\n' | Where-Object { $_ }) }
            $target = Select-JobsRollbackEntry '选择回退后保留的目标' $records -Back
            if ($target.Action -ceq 'Selected') {
                $description = $target.Value
                if ($mode.Value -eq '选择 tag hard 回退') { $commit = Get-JobsRollbackValue $Context @('rev-parse','--verify',('refs/tags/' + $target.Value + '^{commit}')) }
                else { $commit = $target.Value.Split(' ')[0] }
                $target = @{ Action='Selected'; Value=$commit; Description=$description }
            }
        }
        if ($target.Action -ceq 'Back') { continue }
        if ($target.Action -cne 'Selected') { Write-JobsRollbackMessage '已取消回退。'; return }
        if ($mode.Value -in @('soft 回退到 upstream','选择提交 soft 回退')) { Invoke-JobsRollbackSoft $Context $target.Value $target.Description }
        else { Invoke-JobsRollbackHard $Context $target.Value $target.Description }
        return
    }
}
# 首屏先说明和回车；之后才写日志及进入依赖检查和回退流程。
function Invoke-JobsFeature {
    param([Parameter(Mandatory = $true)][string]$Target)
    Write-Host 'Jobs | Git 提交回退（识别子Git）' -ForegroundColor Red
    Write-Host '仅处理目标所属最近工作树，支持子模块 / 嵌套仓库 / worktree；不递归重置子仓。'
    Write-Host 'soft 保留索引与工作区；hard 丢弃已跟踪变化，需另输入 YES。只读本地快照，不 fetch、不推送。'
    Write-Host ('日志：' + (Join-Path (Get-JobsInstallRoot) 'logs') + '；Ctrl+C 随时取消。')
    if ([Console]::IsInputRedirected) { throw '需要独立交互终端，没有确认不能执行。' }
    if ($null -eq (Read-JobsRollbackInput '按回车继续，Ctrl+C 取消')) { throw '输入结束，未执行。' }
    $boundary = Get-JobsRollbackBoundary $Target
    $git = Find-JobsExecutable 'git.exe' @('git')
    if (-not $git) { throw 'Git 不可用；请先安装或修复 Git 后重试。' }
    $context = @{ Git=$git; Root=$boundary.Root; Metadata=$boundary.Metadata; Selected=[IO.Path]::GetFullPath($Target) }
    $inside = Get-JobsRollbackValue $context @('rev-parse','--is-inside-work-tree')
    if ($inside -cne 'true') { throw '目标不在 Git 工作树中。' }
    $context.Branch = Get-JobsRollbackBranch $context
    $context.Head = Get-JobsRollbackValue $context @('rev-parse','--verify','HEAD^{commit}')
    Assert-JobsRollbackContext $context
    Write-JobsRollbackMessage ('当前 Git 仓库：' + $context.Root)
    Invoke-JobsRollbackMenu $context
}
Export-ModuleMember -Function Invoke-JobsFeature

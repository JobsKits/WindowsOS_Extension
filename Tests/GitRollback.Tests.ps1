# GitRollback.Tests.ps1 | 临时 Git 工作树隔离回归
# Created by Jobs on 2026年10月26日，星期一.
[CmdletBinding()]
param([string]$FzfProbeExecutable)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$base = [IO.Path]::GetTempPath()
if ([IO.Directory]::Exists('/private/tmp')) { $base = '/private/tmp' }
$temp = Join-Path $base ('JobsRollback 中文 & ' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$savedLocal = $env:LOCALAPPDATA
$savedGlobal = $env:GIT_CONFIG_GLOBAL
$savedSystem = $env:GIT_CONFIG_NOSYSTEM
$env:LOCALAPPDATA = Join-Path $temp 'AppData'
$env:GIT_CONFIG_GLOBAL = Join-Path $temp 'global.gitconfig'
$env:GIT_CONFIG_NOSYSTEM = '1'
[IO.File]::WriteAllText($env:GIT_CONFIG_GLOBAL, '')
Import-Module (Join-Path $root 'Infrastructure/Common.psm1') -DisableNameChecking
$git = Find-JobsExecutable 'git.exe' @('git')
if (-not $git) { throw 'Test requires Git.' }
$module = Import-Module (Join-Path $root 'JobsGitRollback/Scripts/Action.psm1') -PassThru -DisableNameChecking
$script:assertions = 0
function Assert-Rollback { param([bool]$Condition,[string]$Message) $script:assertions++; if (-not $Condition) { throw ('FAIL: ' + $Message) } }
function Run-Git {
    param([string]$Directory,[string[]]$Arguments)
    $result = Invoke-JobsProcess -FilePath $git -Arguments (@('-c','core.hooksPath=','-C',$Directory) + $Arguments) -TimeoutSeconds 30
    if ($result.ExitCode -ne 0) { throw ('Fixture Git failed: ' + $Arguments[0] + ' ' + $result.StdErr) }
    return $result.StdOut.TrimEnd("`r", "`n")
}
function New-Fixture {
    param([string]$Name)
    $directory = Join-Path $temp $Name
    [void][IO.Directory]::CreateDirectory($directory)
    [void](Run-Git $directory @('init','-b','main'))
    [void](Run-Git $directory @('config','user.name','Jobs Test'))
    [void](Run-Git $directory @('config','user.email','jobs@example.invalid'))
    [void](Run-Git $directory @('config','commit.gpgSign','false'))
    [void](Run-Git $directory @('config','core.autocrlf','false'))
    [IO.File]::WriteAllText((Join-Path $directory 'a.txt'), 'base')
    [void](Run-Git $directory @('add','.'))
    [void](Run-Git $directory @('commit','-m','base'))
    $baseCommit = Run-Git $directory @('rev-parse','HEAD')
    [IO.File]::WriteAllText((Join-Path $directory 'a.txt'), 'second')
    [void](Run-Git $directory @('commit','-am','second'))
    return @{ Root=$directory; Base=$baseCommit; Head=(Run-Git $directory @('rev-parse','HEAD')) }
}
function New-Context {
    param([string]$Directory)
    & $module {
        param($Directory,$Git)
        $boundary = Get-JobsRollbackBoundary $Directory
        $context = @{Git=$Git;Root=$boundary.Root;Metadata=$boundary.Metadata;Selected=$Directory}
        $context.Branch = Get-JobsRollbackBranch $context
        $context.Head = Get-JobsRollbackValue $context @('rev-parse','--verify','HEAD^{commit}')
        Assert-JobsRollbackContext $context
        return $context
    } $Directory $git
}
function Expect-Throw {
    param([scriptblock]$Action,[string]$Message)
    $didThrow=$false
    try { & $Action | Out-Null } catch { $didThrow=$true }
    Assert-Rollback $didThrow $Message
}
try {
    $f = New-Fixture 'normal'
    $nested = Join-Path $f.Root 'inside 中文'
    [void][IO.Directory]::CreateDirectory($nested)
    $context=New-Context $nested
    Assert-Rollback ($context.Root -ceq $f.Root) '普通内部目录解析最近工作树'
    $inner = New-Fixture 'normal/inner'
    Assert-Rollback ((New-Context $inner.Root).Root -ceq $inner.Root) '独立嵌套仓库使用自身'
    $broken=Join-Path $f.Root 'broken'
    [void][IO.Directory]::CreateDirectory($broken)
    [IO.File]::WriteAllText((Join-Path $broken '.git'),'malformed')
    Expect-Throw { New-Context $broken } '畸形内层 gitfile 不回落父仓'
    Expect-Throw { New-Context (Join-Path $f.Root '.git/objects') } 'Git 元数据内部拒绝'
    Expect-Throw { New-Context $temp } '普通非Git目录拒绝'
    $bare=Join-Path $temp 'bare'
    [void](Run-Git $temp @('init','--bare',$bare))
    Expect-Throw { New-Context $bare } '裸仓拒绝'
    $worktree=Join-Path $temp 'linked worktree'
    [void](Run-Git $f.Root @('worktree','add','-b','linked',$worktree))
    Assert-Rollback ((New-Context $worktree).Root -ceq $worktree) 'worktree gitfile和commondir识别'
    [void](Run-Git $f.Root @('-c','protocol.file.allow=always','submodule','add',$inner.Root,'module'))
    $sub=Join-Path $f.Root 'module'
    Assert-Rollback ((New-Context $sub).Root -ceq $sub) '真实子模块gitfile不指向父仓'
    $symlink=Join-Path $temp 'link'
    try {
        New-Item -ItemType SymbolicLink -Path $symlink -Target $f.Root -ErrorAction Stop | Out-Null
        Expect-Throw { New-Context $symlink } '链接目录拒绝'
    } catch { Write-Host 'SKIP symbolic link fixture creation (host privilege)' }
    $s=New-Fixture 'soft'
    [IO.File]::WriteAllText((Join-Path $s.Root 'a.txt'),'staged')
    [void](Run-Git $s.Root @('add','a.txt'))
    [IO.File]::WriteAllText((Join-Path $s.Root 'a.txt'),'unstaged')
    $index=Join-Path $s.Root '.git/index'
    $indexBefore=(Get-FileHash -LiteralPath $index).Hash
    $ctx=New-Context $s.Root
    & $module { param($C,$Commit) Invoke-JobsRollbackSoft $C $Commit 'base' } $ctx $s.Base
    Assert-Rollback ((Run-Git $s.Root @('rev-parse','HEAD')) -ceq $s.Base) 'soft移动HEAD到祖先'
    Assert-Rollback ((Get-FileHash -LiteralPath $index).Hash -ceq $indexBefore) 'soft索引字节保持'
    Assert-Rollback ([IO.File]::ReadAllText((Join-Path $s.Root 'a.txt')) -ceq 'unstaged') 'soft工作树内容保持'
    $softNow=New-Context $s.Root
    Expect-Throw { & $module {param($C,$Commit) Invoke-JobsRollbackSoft $C $Commit 'descendant'} $softNow $s.Head } 'soft拒绝非祖先目标'
    $h=New-Fixture 'hard'
    [IO.File]::WriteAllText((Join-Path $h.Root 'a.txt'),'dirty')
    $ctx=New-Context $h.Root
    & $module { function script:Read-JobsRollbackInput { param($Prompt) return '' } }
    & $module { param($C,$Commit) Invoke-JobsRollbackHard $C $Commit 'base' } $ctx $h.Base
    Assert-Rollback ((Run-Git $h.Root @('rev-parse','HEAD')) -ceq $h.Head) 'hard回车取消不移动HEAD'
    Assert-Rollback ([IO.File]::ReadAllText((Join-Path $h.Root 'a.txt')) -ceq 'dirty') 'hard取消保留修改'
    & $module { function script:Read-JobsRollbackInput { param($Prompt) return 'yes' } }
    & $module { param($C,$Commit) Invoke-JobsRollbackHard $C $Commit 'base' } $ctx $h.Base
    Assert-Rollback ((Run-Git $h.Root @('rev-parse','HEAD')) -ceq $h.Head) 'hard小写yes取消'
    & $module { param($Path) $script:mutatePath=$Path; function script:Read-JobsRollbackInput { param($Prompt) [IO.File]::WriteAllText($script:mutatePath,'concurrent'); return 'YES' } } (Join-Path $h.Root 'a.txt')
    Expect-Throw { & $module { param($C,$Commit) Invoke-JobsRollbackHard $C $Commit 'base' } $ctx $h.Base } 'hard确认期间工作树变化停止'
    Assert-Rollback ((Run-Git $h.Root @('rev-parse','HEAD')) -ceq $h.Head) '变化停止保留HEAD'
    & $module { function script:Read-JobsRollbackInput { param($Prompt) return 'YES' } }
    & $module { param($C,$Commit) Invoke-JobsRollbackHard $C $Commit 'base' } $ctx $h.Base
    Assert-Rollback ((Run-Git $h.Root @('rev-parse','HEAD')) -ceq $h.Base) 'hard YES移动HEAD'
    Assert-Rollback ([IO.File]::ReadAllText((Join-Path $h.Root 'a.txt')) -ceq 'base') 'hard检出固定提交'
    $r=New-Fixture 'ready'
    $ctx=New-Context $r.Root
    [IO.File]::WriteAllText((Join-Path $r.Root '.git/MERGE_HEAD'),$r.Base)
    Expect-Throw { & $module { param($C,$Commit) Invoke-JobsRollbackSoft $C $Commit 'base' } $ctx $r.Base } '未完成merge停止'
    [IO.File]::Delete((Join-Path $r.Root '.git/MERGE_HEAD'))
    [void](Run-Git $r.Root @('checkout','--detach'))
    $detached=New-Context $r.Root
    Assert-Rollback ($detached.Branch -ceq '') '游离HEAD记录空身份'
    Expect-Throw { & $module { param($C) Get-JobsRollbackRemoteTarget $C } $detached } '游离HEAD远端模式停止'
    & $module { param($C,$Commit) Invoke-JobsRollbackSoft $C $Commit 'detached base' } $detached $r.Base
    Assert-Rollback ((Run-Git $r.Root @('rev-parse','HEAD')) -ceq $r.Base) '游离HEAD显式历史soft仍保持祖先限制'
    $r=New-Fixture 'branch-change'
    $ctx=New-Context $r.Root
    [void](Run-Git $r.Root @('checkout','-b','other'))
    Expect-Throw { & $module { param($C,$Commit) Invoke-JobsRollbackSoft $C $Commit 'base' } $ctx $r.Base } '选择期间切分支停止'
    $e=New-Fixture 'environment'
    $envBefore=[Environment]::GetEnvironmentVariable('GIT_DIR')
    try {
        $env:GIT_DIR=Join-Path $h.Root '.git'
        $ctx=New-Context $e.Root
        Assert-Rollback ($ctx.Head -ceq $e.Head) '子进程清理GIT_DIR覆盖'
        Assert-Rollback ($env:GIT_DIR -ceq (Join-Path $h.Root '.git')) '父环境GIT_DIR保持'
    } finally {
        if ([string]::IsNullOrEmpty($envBefore)) { Remove-Item Env:GIT_DIR -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable('GIT_DIR',$envBefore) }
    }
    # 全局 recurse=true 也不能让当前父仓 hard 影响子仓工作树。
    [void](Run-Git $f.Root @('add','.gitmodules','module'))
    [void](Run-Git $f.Root @('commit','-m','record submodule'))
    [void](Run-Git $f.Root @('config','submodule.recurse','true'))
    [void](Run-Git $sub @('checkout','--detach',$inner.Base))
    [IO.File]::WriteAllText((Join-Path $sub 'a.txt'),'child dirty')
    $parentContext=New-Context $f.Root
    $childHead=Run-Git $sub @('rev-parse','HEAD')
    & $module {param($C) Invoke-JobsRollbackHard $C $C.Head 'same parent'} $parentContext
    Assert-Rollback ((Run-Git $sub @('rev-parse','HEAD')) -ceq $childHead) 'hard不递归移动子仓HEAD'
    Assert-Rollback ([IO.File]::ReadAllText((Join-Path $sub 'a.txt')) -ceq 'child dirty') 'hard不递归丢弃子仓修改'
    $m=New-Fixture 'multi-remote'
    [void](Run-Git $m.Root @('remote','add','origin','https://example.invalid/jobs'))
    [void](Run-Git $m.Root @('remote','add','gitee','https://example.invalid/jobs-mirror'))
    [void](Run-Git $m.Root @('update-ref','refs/remotes/origin/main',$m.Base))
    [void](Run-Git $m.Root @('update-ref','refs/remotes/gitee/main',$m.Head))
    $ctx=New-Context $m.Root
    & $module {
        $script:chosen=0
        function script:Select-JobsRollbackEntry {
            param($Title,$Entries,[switch]$Back)
            $script:chosen++
            if ($Entries.Count -ne 2 -or -not $Back) { throw 'Remote selector lost candidates or back.' }
            return @{Action='Selected';Value=($Entries | Where-Object { $_ -like 'refs/remotes/origin/*' })}
        }
    }
    $chosen=& $module {param($C) Get-JobsRollbackRemoteTarget $C} $ctx
    Assert-Rollback ($chosen.Value -ceq $m.Base -and $chosen.Description -ceq 'refs/remotes/origin/main') '多远端目标是明确选定本地快照'
    & $module {
        param($Git,$Directory,$Commit)
        $script:changeGit=$Git;$script:changeDirectory=$Directory;$script:changeCommit=$Commit
        function script:Select-JobsRollbackEntry {
            param($Title,$Entries,[switch]$Back)
            $entry=@($Entries | Where-Object { $_ -like 'refs/remotes/origin/*' })[0]
            [void](Invoke-JobsRollbackGit $script:changeGit $script:changeDirectory @('update-ref','refs/remotes/origin/main',$script:changeCommit))
            return @{Action='Selected';Value=$entry}
        }
    } $git $m.Root $m.Head
    Expect-Throw { & $module {param($C) Get-JobsRollbackRemoteTarget $C} $ctx } '多远端选择期间快照变化停止'
    & $module {
        function script:Select-JobsRollbackEntry {param($Title,$Entries,[switch]$Back) return @{Action='Back';Value=''} }
    }
    $back=& $module {param($C) Get-JobsRollbackRemoteTarget $C} $ctx
    Assert-Rollback ($back.Action -ceq 'Back') '远端目标层左键返回模式层'
    # 模式到目标的返回用真实业务调度循环验证，不在返回后隐式执行 reset。
    & $module {
        $script:step=0;$script:resets=0
        function script:Select-JobsRollbackEntry {
            param($Title,$Entries,[switch]$Back)
            $script:step++
            if ($script:step -eq 1) { return @{Action='Selected';Value='选择提交 hard 回退'} }
            if ($script:step -eq 2) { if(-not $Back){throw 'Missing back layer'}; return @{Action='Back';Value=''} }
            return @{Action='Cancel';Value=''}
        }
        function script:Invoke-JobsRollbackHard {param($Context,$Commit,$Description) $script:resets++}
        Invoke-JobsRollbackMenu $args[0]
        if($script:step -ne 3 -or $script:resets -ne 0){throw 'Back/cancel dispatched reset.'}
    } $ctx
    Assert-Rollback $true '目标返回模式再取消无业务动作'
    foreach($case in @(
        @{Lines=@('left');Code=1;Back=$true;Expected='Back'},
        @{Lines=@('left','x');Code=0;Back=$true;Expected='Back'},
        @{Lines=@('','x');Code=0;Back=$true;Expected='Selected'},
        @{Lines=@('x');Code=0;Back=$false;Expected='Selected'},
        @{Lines=@();Code=130;Back=$true;Expected='Cancel'},
        @{Lines=@();Code=1;Back=$false;Expected='Cancel'})) {
        $choice=& $module {param($Case) ConvertFrom-JobsRollbackSelection -Lines $Case.Lines -ExitCode $Case.Code -Entries @('x') -Back:$Case.Back} $case
        Assert-Rollback ($choice.Action -ceq $case.Expected) ('fzf结果解析 '+$case.Expected)
    }
    Expect-Throw { & $module { ConvertFrom-JobsRollbackSelection -Lines @('evil') -ExitCode 0 -Entries @('x') } } '选择器列表外结果停止'
    Expect-Throw { & $module { ConvertFrom-JobsRollbackSelection -Lines @() -ExitCode 2 -Entries @('x') } } '选择器异常失败传播'
    if ($FzfProbeExecutable) {
        & $module {
            param($Executable)
            $script:encodingProbe=$Executable
            function script:Find-JobsExecutable { param($Name,$Candidates) return $script:encodingProbe }
            # 恢复真实生产选择函数，前面的菜单调度夹具曾临时替换它。
            $parseTokens=$null;$parseErrors=$null
            $ast=[Management.Automation.Language.Parser]::ParseFile($ExecutionContext.SessionState.Module.Path,[ref]$parseTokens,[ref]$parseErrors)
            if($parseErrors.Count){throw 'Production selector parse failed.'}
            $definition=$ast.Find({param($Node) $Node -is [Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -ceq 'Select-JobsRollbackEntry'},$false)
            Set-Item Function:script:Select-JobsRollbackEntry ([scriptblock]::Create($definition.Body.Extent.Text.Substring(1,$definition.Body.Extent.Text.Length-2)))
            $script:OutputEncoding=[Text.Encoding]::ASCII
            $consoleBefore=[Console]::OutputEncoding
            [Console]::OutputEncoding=[Text.Encoding]::ASCII
            try {
                $result=Select-JobsRollbackEntry '中文编码' @('选择提交 soft 回退','hard 回退到 upstream') -Back
                if($result.Value -cne '选择提交 soft 回退'){throw 'Native pipe corrupted Chinese mode.'}
                if($OutputEncoding.CodePage -ne 20127 -or [Console]::OutputEncoding.CodePage -ne 20127){throw 'Original ASCII encoding not restored.'}
            } finally { [Console]::OutputEncoding=$consoleBefore }
        } ([IO.Path]::GetFullPath($FzfProbeExecutable))
        Assert-Rollback $true '初始ASCII原生管道仍完整往返中文并恢复编码'
    } else { Write-Host 'SKIP optional native encoding shim: compile GitRollbackFzfProbe.cpp and pass -FzfProbeExecutable.' }
    Write-Host ('PASS GitRollback: ' + $script:assertions + ' assertions; temporary repositories only.')
} finally {
    Remove-Module $module
    [Environment]::SetEnvironmentVariable('LOCALAPPDATA',$savedLocal)
    [Environment]::SetEnvironmentVariable('GIT_CONFIG_GLOBAL',$savedGlobal)
    [Environment]::SetEnvironmentVariable('GIT_CONFIG_NOSYSTEM',$savedSystem)
    Remove-Item -LiteralPath $temp -Recurse -Force
}

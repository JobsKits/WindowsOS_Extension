#requires -Version 5.1
# CleanTests.ps1 | JobsDiskSpaceInfo 隔离清理验证
# Created by Jobs on 2026年11月15日，星期日.
# 仅在本轮临时目录创建并清理夹具，不运行真实用户清理、COM菜单或注册。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$checks = 0
$testTemporaryBase = [IO.Path]::GetTempPath()
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -and [IO.Directory]::Exists('/private/tmp')) { $testTemporaryBase = '/private/tmp' }
$temporary = Join-Path $testTemporaryBase ('JobsCleanTests-' + [guid]::NewGuid().ToString('N'))
# 记录可核对的隔离断言。
function Assert-CleanTest {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
    $script:checks++
}
# 创建当前夹具所需的文件，不接触测试目录以外路径。
function Write-CleanFixture {
    param([string]$Path, [string]$Text = 'fixture')
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    [IO.File]::WriteAllText($Path, $Text)
}
# 复核受控失败确实阻止业务。
function Assert-CleanThrows {
    param([scriptblock]$Body, [string]$Message)
    $thrown = $false
    try { & $Body | Out-Null } catch { $thrown = $true }
    Assert-CleanTest $thrown $Message
}
try {
    [void][IO.Directory]::CreateDirectory($temporary)
    $scriptPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Scripts/Clean.ps1/Clean.ps1'
    . $scriptPath
    Assert-CleanTest ($null -eq $script:CleanLog) '载入函数不初始化日志、不执行Main'
    # 提示是纯展示：按能力分段着色，所有输入与删除业务继续由原函数决定。
    $promptEsc = [string][char]27
    $promptQuestion = '是否继续清理以上失败项？'
    $promptEnter = '回车 = 继续'
    $promptText = '输入任意字符后回车 = 停止'
    $promptPlain = $promptQuestion + '[' + $promptEnter + ' / ' + $promptText + ']：'
    $promptStyled = Format-CleanPrompt $promptQuestion $promptEnter $promptText -Ansi $true
    $promptExpected = $promptEsc + '[1;36m' + $promptQuestion + $promptEsc + '[0m[' + $promptEsc + '[1;32m' + $promptEnter + $promptEsc + '[0m / ' + $promptEsc + '[1;31m' + $promptText + $promptEsc + '[0m]：'
    Assert-CleanTest ($promptStyled -ceq $promptExpected) '询问正文青粗体、仅回车绿粗体、非空红粗体，分隔符前均复位'
    Assert-CleanTest ((Format-CleanPrompt $promptQuestion $promptEnter $promptText) -ceq $promptPlain) '纯文本降级保留完整操作说明且没有ANSI'
    Assert-CleanTest ((Format-CleanPrompt '仅有询问？' -Ansi $true) -ceq ($promptEsc + '[1;36m仅有询问？' + $promptEsc + '[0m')) '无回车或非空选项的询问也青色粗体且末尾复位'
    $promptCapabilities = @{ HostName = 'ConsoleHost'; InputRedirected = $false; OutputRedirected = $false; ErrorRedirected = $false; NoColorPresent = $false; PlainOutput = ''; Term = 'xterm-256color'; VirtualTerminal = $true; SourceTree = $false }
    Assert-CleanTest (Test-CleanPromptAnsi $promptCapabilities) '已知交互VT宿主允许ANSI询问'
    foreach ($override in @(@{ HostName = 'UnknownHost' }, @{ InputRedirected = $true }, @{ OutputRedirected = $true }, @{ ErrorRedirected = $true },
                            @{ NoColorPresent = $true; NoColorValue = '' }, @{ PlainOutput = '1' }, @{ Term = 'dumb' }, @{ VirtualTerminal = $false }, @{ VirtualTerminal = $null }, @{ SourceTree = $true })) {
        $capability = $promptCapabilities.Clone()
        foreach ($key in $override.Keys) { $capability[$key] = $override[$key] }
        Assert-CleanTest (-not (Test-CleanPromptAnsi $capability)) 'NO_COLOR含空值、非TTY、未知宿主或VT能力及纯文本入口均不添加ANSI'
    }
    $promptCapabilityOriginal = (Get-Item Function:Test-CleanPromptAnsi).ScriptBlock
    $promptInvokeOriginal = (Get-Item Function:Invoke-CleanPlan).ScriptBlock
    $script:promptWrites = New-Object 'Collections.Generic.List[object]'
    $script:CleanLog = Join-Path $temporary 'prompt-pure-text.log'
    try {
        function Write-Host {
            param([object]$Object, [switch]$NoNewline, [ConsoleColor]$ForegroundColor)
            $script:promptWrites.Add([pscustomobject]@{ Text = [string]$Object; NoNewline = [bool]$NoNewline })
        }
        function Test-CleanPromptAnsi { param($Capabilities) return $true }
        Show-CleanDevelopmentConfirmation
        $developmentPrompt = $script:promptWrites[$script:promptWrites.Count - 1]
        Assert-CleanTest ($developmentPrompt.NoNewline -and $developmentPrompt.Text.StartsWith($promptEsc + '[1;36m确认仅执行以上开发范围' + $promptEsc + '[0m：')) '开发最终确认使用共同样式，原无换行输入位置保留'
        Assert-CleanTest ((Invoke-CleanDevelopmentStage $null -ReadAnswer { 'skip' }) -eq 0) '初始开发询问展示变化不改变非空跳过行为'
        Assert-CleanTest (@($script:promptWrites | Where-Object { $_.Text.StartsWith($promptEsc + '[1;36m是否进入开发分组？' + $promptEsc + '[0m') -and $_.NoNewline }).Count -eq 1) '初始开发询问同样有青色正文与操作选项'
        Assert-CleanTest ((Read-CleanChoice '仅有询问？' @('取消', '执行') -ReadKey { [ConsoleKey]::Escape }) -eq 0) '无选项问句展示变化不改变原菜单取消'
        Assert-CleanTest (@($script:promptWrites | Where-Object { $_.Text -ceq ($promptEsc + '[1;36m仅有询问？' + $promptEsc + '[0m') }).Count -eq 1) '原生菜单标题复用无选项青色粗体询问'
        function Invoke-CleanPlan {
            param($Plan, $Context, $FailedEntries)
            foreach ($entry in $Plan.Entries) { $FailedEntries.Add($entry) }
            return 1
        }
        $promptPlan = [pscustomobject]@{ Kind = 'cache'; Project = ''; Entries = @([pscustomobject]@{ Path = (Join-Path $temporary 'prompt-only-fixture') }) }
        $promptOutcome = Invoke-CleanRegularPlan $promptPlan $null -ReadAnswer { 'stop' }
        Assert-CleanTest ($promptOutcome.Stopped -and $promptOutcome.Failed -eq 1) '失败重试问句展示变化不改变非空停止语义'
        Assert-CleanTest (@($script:promptWrites | Where-Object { $_.Text -ceq $promptExpected -and $_.NoNewline }).Count -eq 1) '真实重试分支使用分段提示且不额外换行'
        function Test-CleanPromptAnsi { param($Capabilities) return $false }
        Write-CleanPrompt $promptQuestion $promptEnter $promptText -NoNewline
        Assert-CleanTest ($script:promptWrites[$script:promptWrites.Count - 1].Text -ceq $promptPlain) '能力不足时实际输出路径原地纯文本降级'
        $promptLog = [IO.File]::ReadAllText($script:CleanLog)
        Assert-CleanTest ($promptLog.Contains($promptPlain) -and -not $promptLog.Contains($promptEsc)) '各类询问落盘保留纯文本，不写入终端控制码'
    } finally {
        Remove-Item Function:Write-Host
        Set-Item Function:Test-CleanPromptAnsi $promptCapabilityOriginal
        Set-Item Function:Invoke-CleanPlan $promptInvokeOriginal
        $script:CleanLog = $null
    }
    $profile = Join-Path $temporary 'user'
    $context = [pscustomobject]@{ Profile = $profile; Local = (Join-Path $profile 'Local'); Roaming = (Join-Path $profile 'Roaming'); Now = [DateTime]::UtcNow }
    [void][IO.Directory]::CreateDirectory($context.Local)
    [void][IO.Directory]::CreateDirectory($context.Roaming)
    Assert-CleanThrows { Assert-CleanPath $temporary $profile } '根外路径拒绝'
    Assert-CleanThrows { Get-CleanLocalPath '' } '空路径拒绝'
    $old = Join-Path $context.Local 'Temp/old/item.txt'
    $recent = Join-Path $context.Local 'Temp/recent.txt'
    $devCache = Join-Path $context.Local 'pip/Cache/wheel.bin'
    $protectedTemp = Join-Path $context.Local 'Temp/checkout/build/unselected.aab'
    Write-CleanFixture $old
    Write-CleanFixture $recent
    Write-CleanFixture $devCache
    Write-CleanFixture $protectedTemp
    [IO.Directory]::SetLastWriteTimeUtc((Join-Path $context.Local 'Temp/checkout'), $context.Now.AddDays(-10))
    [IO.Directory]::SetLastWriteTimeUtc([IO.Path]::GetDirectoryName($old), $context.Now.AddDays(-10))
    $plan = Get-CleanPlan $context 'cache'
    Assert-CleanTest ($plan.Entries.Count -eq 1 -and $plan.Entries[0].Path -eq [IO.Path]::GetDirectoryName($old)) '常规只包含7天以上Temp项目'
    Assert-CleanTest ([IO.File]::Exists($old) -and [IO.File]::Exists($recent)) '预览不删除'
    Assert-CleanTest (-not [IO.Directory]::Exists((Join-Path $context.Local 'Jobs'))) '预览不创建状态或日志'
    $dev = Get-CleanPlan $context 'dev-caches'
    Assert-CleanTest ($dev.Entries.Count -eq 1 -and $dev.Entries[0].Path -eq $devCache) '开发缓存独立分组'
    Assert-CleanTest (@($plan.Entries | Where-Object Path -eq $devCache).Count -eq 0) '后续常规不越过跳过分组'
    $changed = Get-CleanPlan $context 'cache'
    Write-CleanFixture $old 'changed content'
    Assert-CleanThrows { Invoke-CleanPlan $changed $context } '确认后内容变化阻止整组执行'
    Assert-CleanTest ([IO.File]::Exists($old)) '变化后原件保留'
    $plan = Get-CleanPlan $context 'cache'
    $failed = Invoke-CleanPlan $plan $context
    Assert-CleanTest ($failed -eq 0 -and -not [IO.File]::Exists($old) -and [IO.File]::Exists($recent)) '隔离缓存仅删除确认候选'
    Assert-CleanTest ([IO.File]::Exists($devCache)) '常规清理后未选开发缓存保留'
    Assert-CleanTest ([IO.File]::Exists($protectedTemp)) 'Temp中的工程build也保留，不能绕过分组未选项'
    # 任意命名目录按内容识别环境，不能依赖本机路径或Jobs前缀。
    $guardProfile = Join-Path $temporary ('random-user-' + [guid]::NewGuid().ToString('N'))
    $guardContext = [pscustomobject]@{ Profile = $guardProfile; Local = (Join-Path $guardProfile 'Local'); Roaming = (Join-Path $guardProfile 'Roaming'); Now = [DateTime]::UtcNow }
    $guardFiles = @()
    foreach ($marker in @('go.mod', 'go.work', 'package.json', 'Cargo.toml', 'pyvenv.cfg', 'pyproject.toml', 'package.xml', 'SDKSettings.plist', 'pubspec.yaml', 'CMakeLists.txt')) {
        $candidateRoot = Join-Path $guardContext.Local ('Temp/' + [guid]::NewGuid().ToString('N'))
        $markerFile = Join-Path $candidateRoot ('nested/' + $marker)
        Write-CleanFixture $markerFile
        [IO.Directory]::SetLastWriteTimeUtc($candidateRoot, $guardContext.Now.AddDays(-10))
        $guardFiles += $markerFile
    }
    $ordinaryCache = Join-Path $guardContext.Local 'Temp/ordinary-cache.tmp'
    Write-CleanFixture $ordinaryCache
    [IO.File]::SetLastWriteTimeUtc($ordinaryCache, $guardContext.Now.AddDays(-10))
    $readOnlyRoot = Join-Path $guardContext.Local ('Temp/' + [guid]::NewGuid().ToString('N'))
    $readOnlyFile = Join-Path $readOnlyRoot 'nested/read-only.dat'
    Write-CleanFixture $readOnlyFile
    [IO.File]::SetAttributes($readOnlyFile, [IO.FileAttributes]::ReadOnly)
    [IO.Directory]::SetLastWriteTimeUtc($readOnlyRoot, $guardContext.Now.AddDays(-10))
    $guardPlan = Get-CleanPlan $guardContext 'cache'
    Assert-CleanTest ($guardPlan.Entries.Count -eq 1 -and $guardPlan.Entries[0].Path -eq $ordinaryCache) '随机目录名的源码、SDK、语言环境及只读候选整项保留，普通过期缓存仍可选'
    Assert-CleanTest (@($guardPlan.Notes | Where-Object { $_ -like '*标记*' }).Count -eq $guardFiles.Count) '通用标记逐项说明保留原因，不按用户或环境目录名称识别'
    Assert-CleanTest (@($guardPlan.Notes | Where-Object { $_ -like '*只读*' }).Count -eq 1) '只读内容在计划阶段排除而非等待删除报错'
    $guardFailed = Invoke-CleanPlan $guardPlan $guardContext
    Assert-CleanTest ($guardFailed -eq 0 -and -not [IO.File]::Exists($ordinaryCache)) '明确确认的普通缓存可执行清理'
    foreach ($guardFile in $guardFiles) { Assert-CleanTest ([IO.File]::Exists($guardFile)) '源码或SDK标记及所在随机环境目录未被清理' }
    Assert-CleanTest ([IO.File]::Exists($readOnlyFile)) '普通缓存清理不改变或删除只读环境内容'
    [IO.File]::SetAttributes($readOnlyFile, [IO.FileAttributes]::Normal)
    $scanOriginal = (Get-Item Function:New-CleanScanBudget).ScriptBlock
    $overBudgetRoot = Join-Path $guardContext.Local ('Temp/' + [guid]::NewGuid().ToString('N'))
    foreach ($index in 1..5) { Write-CleanFixture (Join-Path $overBudgetRoot ('entry-' + $index + '.tmp')) }
    [IO.Directory]::SetLastWriteTimeUtc($overBudgetRoot, $guardContext.Now.AddDays(-10))
    try {
        function New-CleanScanBudget { return @{ Nodes = 0; MaximumNodes = 3; MaximumDepth = 64; Timer = [Diagnostics.Stopwatch]::StartNew(); MaximumMilliseconds = 5000 } }
        $budgetPlan = Get-CleanPlan $guardContext 'cache'
        Assert-CleanTest (@($budgetPlan.Entries | Where-Object Path -eq $overBudgetRoot).Count -eq 0 -and @($budgetPlan.Notes | Where-Object { $_ -like '*扫描超出预算*' }).Count -gt 0) '条目扫描预算超限时不生成不完整候选'
        Assert-CleanThrows { Get-CleanStamp $overBudgetRoot } '独立执行复检同样执行条目预算'
        Assert-CleanTest ([IO.File]::Exists((Join-Path $overBudgetRoot 'entry-5.tmp'))) '超限保留源候选，不修改权限或删除子项'
        function New-CleanScanBudget { return @{ Nodes = 0; MaximumNodes = 10000; MaximumDepth = 1; Timer = [Diagnostics.Stopwatch]::StartNew(); MaximumMilliseconds = 5000 } }
        Assert-CleanThrows { Get-CleanStamp $readOnlyRoot } '深度预算超限整项保留'
        function New-CleanScanBudget { return @{ Nodes = 0; MaximumNodes = 10000; MaximumDepth = 64; Timer = [pscustomobject]@{ ElapsedMilliseconds = 6000 }; MaximumMilliseconds = 5000 } }
        Assert-CleanThrows { Get-CleanStamp $overBudgetRoot } '时间预算超限整项保留'
    } finally { Set-Item Function:New-CleanScanBudget $scanOriginal }
    $lateMarkerRoot = Join-Path $guardContext.Local ('Temp/' + [guid]::NewGuid().ToString('N'))
    Write-CleanFixture (Join-Path $lateMarkerRoot 'cache.bin')
    [IO.Directory]::SetLastWriteTimeUtc($lateMarkerRoot, $guardContext.Now.AddDays(-10))
    $lateMarkerPlan = Get-CleanPlan $guardContext 'cache'
    Write-CleanFixture (Join-Path $lateMarkerRoot 'go.mod')
    Assert-CleanThrows { Invoke-CleanPlan $lateMarkerPlan $guardContext } '确认后新增源码标记时停止整组执行'
    Assert-CleanTest ([IO.File]::Exists((Join-Path $lateMarkerRoot 'cache.bin'))) '并发新增标记后保留原缓存实体'
    $history = Join-Path $context.Roaming 'Microsoft/Windows/PowerShell/PSReadLine/ConsoleHost_history.txt'
    Write-CleanFixture $history 'Get-Example -Value fixture'
    $historyPlan = Get-CleanPlan $context 'history'
    Assert-CleanTest ($historyPlan.Entries.Count -eq 1 -and $historyPlan.Entries[0].Backup) '仅标准PSReadLine文件需要备份'
    $failed = Invoke-CleanPlan $historyPlan $context
    Assert-CleanTest ($failed -eq 0 -and -not [IO.File]::Exists($history)) '隔离历史完成移除'
    $receipts = @(Get-ChildItem -LiteralPath (Join-Path $context.Local 'Jobs/WindowsExtension/extensions/disk-space-info/clean-backups') -Recurse -Filter '*.restore.json')
    Assert-CleanTest ($receipts.Count -eq 1) '备份附恢复映射'
    $receipt = [IO.File]::ReadAllText($receipts[0].FullName) | ConvertFrom-Json
    Assert-CleanTest ($receipt.OriginalPath -eq $history -and [IO.File]::ReadAllText($receipt.BackupPath) -eq 'Get-Example -Value fixture') '备份内容与恢复原路径一致'
    Write-CleanFixture $history 'preserve after failed backup'
    $historyPlan = Get-CleanPlan $context 'history'
    $copyOriginal = (Get-Item Function:Copy-CleanTree).ScriptBlock
    function Copy-CleanTree { param($Source, $Destination) throw 'fixture: backup failed' }
    $failed = Invoke-CleanPlan $historyPlan $context
    Assert-CleanTest ($failed -eq 1 -and [IO.File]::Exists($history)) '备份失败不删除原件且汇总失败'
    Set-Item Function:Copy-CleanTree $copyOriginal
    $avdRoot = Join-Path $profile '.android/avd'
    $orphan = Join-Path $avdRoot 'gone.ini'
    $valid = Join-Path $avdRoot 'valid.ini'
    Write-CleanFixture $orphan ('path=' + (Join-Path $avdRoot 'gone.avd'))
    Write-CleanFixture $valid ('path=' + (Join-Path $avdRoot 'valid.avd'))
    Write-CleanFixture (Join-Path $avdRoot 'valid.avd/config.ini') 'normal device'
    Write-CleanFixture (Join-Path $avdRoot 'external.ini') ('path=' + (Join-Path $temporary 'external.avd'))
    $avdPlan = Get-CleanPlan $context 'avd'
    Assert-CleanTest ($avdPlan.Entries.Count -eq 1 -and $avdPlan.Entries[0].Path -eq $orphan) '仅默认设备集精确实体缺失登记'
    [void][IO.Directory]::CreateDirectory((Join-Path $avdRoot 'gone.avd'))
    Assert-CleanThrows { Invoke-CleanEntry $avdPlan.Entries[0] (Join-Path $context.Local 'backup') } '执行前目标恢复阻止登记移除'
    Assert-CleanTest ([IO.File]::Exists($orphan) -and [IO.File]::Exists($valid)) '恢复设备与正常设备登记保留'
    $project = Join-Path $profile 'project 中文 & space'
    Write-CleanFixture (Join-Path $project 'pubspec.yaml') "name: example`nflutter:`n  sdk: flutter"
    [void][IO.Directory]::CreateDirectory((Join-Path $project 'lib'))
    $release = Join-Path $project 'build/windows/x64/runner/Release/example.exe'
    Write-CleanFixture $release
    Write-CleanFixture (Join-Path $project 'node_modules/preserve.txt')
    Write-CleanFixture (Join-Path $project '.gradle/preserve.txt')
    Write-CleanFixture (Join-Path $project 'build/source.txt')
    $buildPlan = Get-CleanPlan $context 'build-apps' $project
    Assert-CleanTest ($buildPlan.Entries.Count -eq 1 -and $buildPlan.Entries[0].Path -eq [IO.Path]::GetDirectoryName($release) -and $buildPlan.Entries[0].Backup) '构建App只限显式工程标准runner配置输出'
    Assert-CleanTest ([IO.File]::Exists((Join-Path $project 'build/source.txt'))) '不扫任意build、依赖或SDK'
    Assert-CleanThrows { Get-CleanPlan $context 'build-apps' $profile } '非Flutter根工程拒绝'
    $apk = Join-Path $project 'build/app/outputs/apk/release/example.apk'
    $aab = Join-Path $project 'build/app/outputs/bundle/release/example.aab'
    $keep = Join-Path $project 'build/app/outputs/apk/metadata.json'
    Write-CleanFixture $apk
    Write-CleanFixture $aab
    Write-CleanFixture $keep
    $archivePlan = Get-CleanPlan $context 'archives' $project
    Assert-CleanTest ($archivePlan.Entries.Count -eq 2 -and @($archivePlan.Entries | Where-Object { -not $_.Backup }).Count -eq 0) '发行包逐文件列出且要求备份'
    $one = @(ConvertFrom-CleanFzfSelection $archivePlan @("1`tignored display"))
    Assert-CleanTest ($one.Count -eq 1) 'fzf单选准确映射'
    $all = @(ConvertFrom-CleanFzfSelection $archivePlan @("__ALL__`t清理当前组全部"))
    Assert-CleanTest ($all.Count -eq 2) '全组操作行映射当前完整候选'
    Assert-CleanTest (@(ConvertFrom-CleanFzfSelection $archivePlan @()).Count -eq 0) '空选不取当前项或隐式全选'
    Assert-CleanThrows { ConvertFrom-CleanFzfSelection $archivePlan @("999`tinvalid") } '未知ID拒绝'
    Assert-CleanTest (@(ConvertFrom-CleanFzfSelection $archivePlan @("__ALL__`t全选", "__SKIP__`t跳过")).Count -eq 0) '同时选中全选与跳过时跳过优先，无清理候选'
    Assert-CleanTest (@(ConvertFrom-CleanFzfSelection $archivePlan @('__EMPTY__', "0`t高亮项")).Count -eq 0) '空选标记忽略fzf隐式当前高亮项'
    Assert-CleanThrows { ConvertFrom-CleanFzfSelection $archivePlan @("__ALL__`t全选", "999`tinvalid") } '全选不能掩盖伪造候选ID'
    $pickerStartOriginal = (Get-Item Function:New-CleanFzfStartInfo).ScriptBlock
    $pickerFixture = Join-Path $temporary 'picker-fixture.ps1'
    [IO.File]::WriteAllText($pickerFixture, '[IO.File]::WriteAllText($env:JOBS_TEST_PICKER_ROWS, [Console]::In.ReadToEnd()); [Console]::Out.Write($env:JOBS_TEST_PICKER_OUTPUT); exit ([int]$env:JOBS_TEST_PICKER_EXIT)', (New-Object Text.UTF8Encoding($false)))
    $script:pickerHost = (Get-Process -Id $PID).Path
    $script:pickerRowsPath = Join-Path $temporary 'picker-rows.txt'
    $script:pickerFile = $pickerFixture
    try {
        function New-CleanFzfStartInfo {
            param($Fzf, $Options)
            $script:pickerOptions = @($Options)
            $start = New-Object Diagnostics.ProcessStartInfo
            $start.FileName = $script:pickerHost
            $start.Arguments = '-NoLogo -NoProfile -NonInteractive -File "' + $script:pickerFile + '"'
            $start.UseShellExecute = $false
            $start.RedirectStandardInput = $true
            $start.RedirectStandardOutput = $true
            $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
            $start.EnvironmentVariables['JOBS_TEST_PICKER_ROWS'] = $script:pickerRowsPath
            $start.EnvironmentVariables['JOBS_TEST_PICKER_OUTPUT'] = $script:pickerOutput
            $start.EnvironmentVariables['JOBS_TEST_PICKER_EXIT'] = [string]$script:pickerExit
            return $start
        }
        foreach ($testSelection in @('__ALL__', '__SKIP__', '__EMPTY__', '', "__ALL__`n__SKIP__")) {
            $script:pickerExit = 0; $script:pickerOutput = $testSelection
            $pickerSelected = @(Select-CleanGroupEntries $archivePlan 'fixture-fzf' -UserCache)
            $expected = $(if ($testSelection -ceq '__ALL__') { $archivePlan.Entries.Count } else { 0 })
            Assert-CleanTest ($pickerSelected.Count -eq $expected) '真实子进程选择结果区分全选、跳过、空选与冲突，不执行业务'
            $pickerRows = [IO.File]::ReadAllLines($script:pickerRowsPath)
            Assert-CleanTest ($pickerRows[0].StartsWith("__ALL__`t") -and $pickerRows[1].StartsWith("__SKIP__`t") -and $pickerRows.Count -eq ($archivePlan.Entries.Count + 2)) '首行全选、次行跳过，控制行不占真实候选编号'
            Assert-CleanTest (@($script:pickerOptions | Where-Object { $_ -like '--bind=*enter:toggle,space:accept-non-empty*' }).Count -eq 1) '缓存原生确认：无勾选取当前行，有勾选仅提交原集合，无匹配等待'
        }
        $script:pickerExit = 0; $script:pickerOutput = "0`t当前候选"
        Assert-CleanTest (@(Select-CleanGroupEntries $archivePlan 'fixture-fzf').Count -eq 1) '开发组选中的当前候选准确映射'
        Assert-CleanTest (@($script:pickerOptions | Where-Object { $_ -like '--bind=*enter:toggle,space:accept-non-empty*' }).Count -eq 1) '开发组与缓存组使用同一原生确认动作'
        $script:pickerExit = 130; $script:pickerOutput = '__ALL__'
        Assert-CleanTest (@(Select-CleanGroupEntries $archivePlan 'fixture-fzf' -UserCache).Count -eq 0) '中断状态即使带全选输出也不返回候选'
        $script:pickerExit = 2
        Assert-CleanThrows { Select-CleanGroupEntries $archivePlan 'fixture-fzf' -UserCache } '选择器失败不放行全选输出'
    } finally { Set-Item Function:New-CleanFzfStartInfo $pickerStartOriginal }
    $environmentBefore = @{}
    foreach ($key in @('FZF_DEFAULT_OPTS', 'FZF_DEFAULT_OPTS_FILE')) { $environmentBefore[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
    try {
        [Environment]::SetEnvironmentVariable('FZF_DEFAULT_OPTS', '--filter=unexpected --select-1 --query=bad', 'Process')
        [Environment]::SetEnvironmentVariable('FZF_DEFAULT_OPTS_FILE', 'C:\unexpected-options-file', 'Process')
        $info = New-CleanFzfStartInfo 'fixture-fzf' @('--multi', '--no-sort')
        Assert-CleanTest (-not $info.EnvironmentVariables.ContainsKey('FZF_DEFAULT_OPTS') -and -not $info.EnvironmentVariables.ContainsKey('FZF_DEFAULT_OPTS_FILE')) '有害fzf默认参数仅从子进程移除'
        Assert-CleanTest ([Environment]::GetEnvironmentVariable('FZF_DEFAULT_OPTS', 'Process') -ceq '--filter=unexpected --select-1 --query=bad') '父进程有值状态原样保留'
        Remove-Item Env:FZF_DEFAULT_OPTS -ErrorAction SilentlyContinue
        $info = New-CleanFzfStartInfo 'fixture-fzf' @('--multi')
        Assert-CleanTest (-not [Environment]::GetEnvironmentVariables().Contains('FZF_DEFAULT_OPTS')) '父进程未设置状态不被创建'
        [Environment]::SetEnvironmentVariable('FZF_DEFAULT_OPTS', '', 'Process')
        $emptyExists = [Environment]::GetEnvironmentVariables().Contains('FZF_DEFAULT_OPTS')
        $emptyValue = [Environment]::GetEnvironmentVariable('FZF_DEFAULT_OPTS', 'Process')
        $info = New-CleanFzfStartInfo 'fixture-fzf' @('--multi')
        Assert-CleanTest ($emptyExists -eq [Environment]::GetEnvironmentVariables().Contains('FZF_DEFAULT_OPTS') -and $emptyValue -ceq [Environment]::GetEnvironmentVariable('FZF_DEFAULT_OPTS', 'Process')) '宿主实际空值语义原样保留'
    } finally {
        foreach ($key in $environmentBefore.Keys) {
            if ($null -eq $environmentBefore[$key]) { Remove-Item ('Env:' + $key) -ErrorAction SilentlyContinue }
            else { [Environment]::SetEnvironmentVariable($key, $environmentBefore[$key], 'Process') }
        }
    }
    Assert-CleanTest ((Invoke-CleanDevelopmentStage $context -ReadAnswer { $null }) -eq -1) 'EOF取消整轮而非继续legacy'
    Assert-CleanTest ((Invoke-CleanDevelopmentStage $context -ReadAnswer { 'skip' }) -eq 0) '非空输入跳过开发阶段'
    $stageOriginals = @{}
    foreach ($name in @('Read-CleanChoice', 'Get-CleanPlan', 'Select-CleanGroupEntries', 'Initialize-CleanLog', 'Invoke-CleanPlan', 'Test-CleanFzf', 'Invoke-CleanDevelopmentStage', 'Show-CleanIntro', 'Invoke-CleanRegularPlan')) {
        $stageOriginals[$name] = (Get-Item ('Function:' + $name)).ScriptBlock
    }
    try {
        # 全部开发业务均拦截，只验证输入与编排，不依赖已安装 fzf 或真实用户目录。
        function Get-Command {
            param($Name, $CommandType, $ErrorAction)
            if ($Name -contains 'fzf.exe') { return [pscustomobject]@{ Source = 'fixture-fzf' } }
            Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
        }
        function Test-CleanFzf { param($Executable) return $true }
        function Read-CleanChoice {
            param($Title, $Choices, [switch]$Dangerous)
            $script:stageChoiceCalls++
            if ($script:stageChoiceCalls -eq 1) { return 1 }
            return 0
        }
        function Get-CleanPlan {
            param($Context, $Kind, $Project)
            return [pscustomobject]@{ Kind = $Kind; Project = ''; Notes = @(); Entries = @([pscustomobject]@{ Path = (Join-Path $temporary 'development-fixture') }) }
        }
        function Select-CleanGroupEntries { param($Plan, $Executable) return $Plan.Entries }
        function Initialize-CleanLog { param($Context) $script:stageLogCalls++ }
        function Invoke-CleanPlan {
            param($Plan, $Context)
            $script:stageExecuteCalls++
            if ($script:stageCancel) { throw (New-Object OperationCanceledException('fixture: development cancelled')) }
            return $script:stageExecuteResult
        }
        foreach ($finalAnswer in @('', 'cancel', ' ', $null)) {
            $script:stageChoiceCalls = 0; $script:stageLogCalls = 0; $script:stageExecuteCalls = 0
            $script:stageCancel = $false; $script:stageExecuteResult = 0
            $script:stageAnswers = New-Object 'Collections.Generic.Queue[object]'
            $script:stageAnswers.Enqueue(''); $script:stageAnswers.Enqueue($finalAnswer)
            $stageResult = Invoke-CleanDevelopmentStage $context -ReadAnswer { return $script:stageAnswers.Dequeue() }
            if ($null -eq $finalAnswer) {
                Assert-CleanTest ($stageResult -eq -1 -and $script:stageExecuteCalls -eq 0 -and $script:stageLogCalls -eq 0) '开发最终确认EOF取消整轮，不执行或初始化业务日志'
            } elseif ($finalAnswer -ceq '') {
                Assert-CleanTest ($stageResult -eq 0 -and $script:stageExecuteCalls -eq 1 -and $script:stageLogCalls -eq 1) '开发最终确认只按回车执行所选清单'
            } else {
                Assert-CleanTest ($stageResult -eq 0 -and $script:stageExecuteCalls -eq 0 -and $script:stageChoiceCalls -eq 1) '开发最终确认非空或空格取消整个阶段并返回常规'
            }
        }
        $script:stageChoiceCalls = 0; $script:stageExecuteCalls = 0
        $script:stageExecuteResult = 2
        $stageResult = Invoke-CleanDevelopmentStage $context -ReadAnswer { return '' }
        Assert-CleanTest ($stageResult -eq 2 -and $script:stageExecuteCalls -eq 1 -and $script:stageChoiceCalls -eq 1) '开发执行失败立即结束阶段并返回未完成数量'
        $script:stageChoiceCalls = 0; $script:stageCancel = $true
        Assert-CleanThrows { Invoke-CleanDevelopmentStage $context -ReadAnswer { return '' } } '开发阶段取消异常不会被组内错误处理吞掉'
        function Invoke-CleanDevelopmentStage {
            param($Context)
            switch ($script:developmentBehavior) {
                'error' { throw 'fixture: development initialization failed' }
                'cancel' { throw (New-Object OperationCanceledException('fixture: cancelled')) }
                'eof' { return -1 }
                'failed' { return 2 }
                default { return 0 }
            }
        }
        function Show-CleanIntro { $script:regularIntroCalls++ }
        function Read-CleanChoice { param($Title, $Choices, [switch]$Dangerous) return $script:regularChoices.Dequeue() }
        function Invoke-CleanRegularPlan {
            param($Plan, $Context)
            $script:regularExecuteCalls++
            return [pscustomobject]@{ Failed = 0; Stopped = $false }
        }
        foreach ($behavior in @('failed', 'error', 'success', 'eof', 'cancel')) {
            $script:developmentBehavior = $behavior
            $script:regularChoices = New-Object 'Collections.Generic.Queue[int]'
            foreach ($choice in @(1, 1, 0)) { $script:regularChoices.Enqueue($choice) }
            $script:regularIntroCalls = 0; $script:regularExecuteCalls = 0
            $script:CleanLog = Join-Path $temporary 'phase-flow.log'
            $errorText = ''
            try { Invoke-CleanInteractiveStages $context } catch { $errorText = $_.Exception.Message }
            if ($behavior -in @('eof', 'cancel')) {
                Assert-CleanTest ($errorText -ne '' -and $script:regularIntroCalls -eq 0 -and $script:regularExecuteCalls -eq 0) '开发EOF或取消立即停止，常规未进入'
            } else {
                Assert-CleanTest ($script:regularIntroCalls -eq 1 -and $script:regularExecuteCalls -eq 1) '开发成功、普通失败或初始化异常后均进入并执行常规确认清单'
                if ($behavior -eq 'success') { Assert-CleanTest ($errorText -eq '') '两个阶段完成后不虚报失败' }
                else { Assert-CleanTest ($errorText.Contains('存在未完成清理')) '常规成功仍保留此前开发未完成结果' }
            }
        }
        $interruptProbe = [PowerShell]::Create()
        $interruptState = [pscustomobject]@{ Regular = $false; Continued = $false }
        try {
            [void]$interruptProbe.AddScript({
                param($Source, $Probe)
                . $Source
                $script:InterruptState = $Probe
                function Invoke-CleanDevelopmentStage { param($Context) throw (New-Object Management.Automation.PipelineStoppedException) }
                function Show-CleanIntro { $script:InterruptState.Regular = $true }
                Invoke-CleanInteractiveStages ([pscustomobject]@{})
                $script:InterruptState.Continued = $true
            }).AddArgument($scriptPath).AddArgument($interruptState)
            try { [void]$interruptProbe.Invoke() } catch [Management.Automation.PipelineStoppedException] { }
            Assert-CleanTest (-not $interruptState.Regular -and -not $interruptState.Continued -and $interruptProbe.InvocationStateInfo.State -ne 'Completed') 'Ctrl+C管道取消在独立runspace中传播，不进入常规或吞成成功'
        } finally { $interruptProbe.Dispose() }
    } finally {
        foreach ($name in $stageOriginals.Keys) { Set-Item ('Function:' + $name) $stageOriginals[$name] }
        Remove-Item Function:Get-Command
        $script:CleanLog = $null
    }
    $selected = [pscustomobject]@{ Kind = $archivePlan.Kind; Project = $archivePlan.Project; Entries = $one; SelectedOnly = $true }
    $failed = Invoke-CleanPlan $selected $context
    Assert-CleanTest ($failed -eq 0 -and [IO.File]::Exists($keep)) '分组仅处理选中文件并保留元数据'
    Assert-CleanTest (@($archivePlan.Entries | Where-Object { [IO.File]::Exists($_.Path) }).Count -eq 1) '未选归档保留'
    $keyQueue = New-Object 'Collections.Generic.Queue[ConsoleKey]'
    $keyQueue.Enqueue([ConsoleKey]::DownArrow); $keyQueue.Enqueue([ConsoleKey]::Enter); $keyQueue.Enqueue([ConsoleKey]::Escape)
    $choice = Read-CleanChoice 'fixture danger' @('cancel', 'delete') -Dangerous -ReadKey { $keyQueue.Dequeue() }
    Assert-CleanTest ($choice -eq 0 -and $keyQueue.Count -eq 0) '危险选项普通回车不执行，Esc取消'
    $keyQueue.Enqueue([ConsoleKey]::DownArrow); $keyQueue.Enqueue([ConsoleKey]::Spacebar)
    Assert-CleanTest ((Read-CleanChoice 'fixture danger' @('cancel', 'delete') -Dangerous -ReadKey { $keyQueue.Dequeue() }) -eq 1) '危险操作只在选中后空格确认'
    $stageFile = Join-Path $context.Local 'Temp/stage.txt'
    Write-CleanFixture $stageFile
    [IO.File]::SetLastWriteTimeUtc($stageFile, $context.Now.AddDays(-10))
    $stagePlan = Get-CleanPlan $context 'cache'
    $removeOriginal = (Get-Item Function:Remove-CleanTree).ScriptBlock
    function Remove-CleanTree { param($Path) throw 'fixture: delete failed' }
    $script:CleanLog = Join-Path $temporary 'failure-output.log'
    $failureOutput = @(Invoke-CleanPlan $stagePlan $context 6>&1)
    $failed = $failureOutput[-1]
    Assert-CleanTest ($failed -eq 1 -and [IO.File]::Exists($stageFile)) '暂存后失败恢复准确源位置'
    $failureDisplay = ($failureOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    $failureLog = [IO.File]::ReadAllText($script:CleanLog)
    Assert-CleanTest ($failureDisplay.Contains('fixture: delete failed') -and $failureDisplay.Contains($stageFile) -and $failureLog.Contains('fixture: delete failed') -and $failureLog.Contains($stageFile)) '删除失败具体原因与目标路径同时输出到终端信息流和日志'
    $script:CleanLog = $null
    Set-Item Function:Remove-CleanTree $removeOriginal
    # 失败重试只处理原确认范围；独立假用户避免已有夹具混入候选。
    $retryProfile = Join-Path $temporary 'retry-user'
    $retryContext = [pscustomobject]@{ Profile = $retryProfile; Local = (Join-Path $retryProfile 'Local'); Roaming = (Join-Path $retryProfile 'Roaming'); Now = [DateTime]::UtcNow }
    [void][IO.Directory]::CreateDirectory($retryContext.Roaming)
    $retryA = Join-Path $retryContext.Local 'Temp/a-success.txt'
    $retryB = Join-Path $retryContext.Local 'Temp/b-fail-once.txt'
    $retryC = Join-Path $retryContext.Local 'Temp/c-fail-twice.txt'
    foreach ($path in @($retryA, $retryB, $retryC)) { Write-CleanFixture $path; [IO.File]::SetLastWriteTimeUtc($path, $retryContext.Now.AddDays(-10)) }
    $retryPlan = Get-CleanPlan $retryContext 'cache'
    $entryOriginal = (Get-Item Function:Invoke-CleanEntry).ScriptBlock
    $script:retryEntryCalls = @{}
    $script:retryFailBudgets = @{ $retryA = 0; $retryB = 1; $retryC = 2 }
    $script:retryCancel = $false
    function Invoke-CleanEntry {
        param($Entry, $BackupRoot)
        $script:retryEntryCalls[$Entry.Path] = 1 + [int]$script:retryEntryCalls[$Entry.Path]
        if ($script:retryCancel) { throw (New-Object OperationCanceledException('fixture: cancelled')) }
        if ($script:retryEntryCalls[$Entry.Path] -le [int]$script:retryFailBudgets[$Entry.Path]) { throw 'fixture: temporarily locked' }
        & $entryOriginal $Entry $BackupRoot
    }
    $script:CleanLog = $null
    Initialize-CleanLog $retryContext
    $script:retryPrompts = 0
    $late = Join-Path $retryContext.Local 'Temp/late-unconfirmed.txt'
    $outcome = Invoke-CleanRegularPlan $retryPlan $retryContext -ReadAnswer {
        $script:retryPrompts++
        if ($script:retryPrompts -eq 1) { Write-CleanFixture $late; [IO.File]::SetLastWriteTimeUtc($late, $retryContext.Now.AddDays(-10)) }
        return ''
    }
    Assert-CleanTest ($outcome.Failed -eq 0 -and -not $outcome.Stopped -and $script:retryPrompts -eq 2) '连续失败后回车继续，最终恢复成功'
    Assert-CleanTest ($script:retryEntryCalls[$retryA] -eq 1 -and $script:retryEntryCalls[$retryB] -eq 2 -and $script:retryEntryCalls[$retryC] -eq 3) '每轮成功立即出队，只重试仍失败项目'
    Assert-CleanTest ([IO.File]::Exists($late) -and -not $script:retryEntryCalls.ContainsKey($late)) '重试期间新候选不加入授权清单'
    $retryLog = [IO.File]::ReadAllText($script:CleanLog)
    Assert-CleanTest ($retryLog.Contains('第 1 轮') -and $retryLog.Contains('第 3 轮') -and $retryLog.Contains('用户临时文件') -and -not $retryLog.Contains([string][char]27)) '轮次、类别和结果追加同一纯文本日志'
    foreach ($stopAnswer in @('n', ' ', $null)) {
        $retryPlan = Get-CleanPlan $retryContext 'cache'
        $script:retryFailBudgets[$late] = 100
        $before = [int]$script:retryEntryCalls[$late]
        $outcome = Invoke-CleanRegularPlan $retryPlan $retryContext -ReadAnswer { return $stopAnswer }
        Assert-CleanTest ($outcome.Failed -eq 1 -and $outcome.Stopped -and [IO.File]::Exists($late) -and $script:retryEntryCalls[$late] -eq $before + 1) '非空、空格或EOF停止，不额外清理'
    }
    $retryPlan = Get-CleanPlan $retryContext 'cache'
    $script:retryPrompts = 0
    $outcome = Invoke-CleanRegularPlan $retryPlan $retryContext -ReadAnswer {
        $script:retryPrompts++
        if ($script:retryPrompts -lt 3) { return '' }
        return 'stop'
    }
    Assert-CleanTest ($outcome.Failed -eq 1 -and $outcome.Stopped -and $script:retryPrompts -eq 3) '永久失败每轮重新询问，停止后保留失败结果'
    $retryPlan = Get-CleanPlan $retryContext 'cache'
    $script:retryPrompts = 0
    $before = [int]$script:retryEntryCalls[$late]
    $outcome = Invoke-CleanRegularPlan $retryPlan $retryContext -ReadAnswer {
        $script:retryPrompts++
        if ($script:retryPrompts -eq 1) { Write-CleanFixture $late 'concurrently changed'; return '' }
        return 'stop'
    }
    Assert-CleanTest ($outcome.Failed -eq 1 -and $script:retryEntryCalls[$late] -eq $before + 1 -and [IO.File]::ReadAllText($late) -eq 'concurrently changed') '重试保留原快照，变化项目不绕过复检'
    $script:retryCancel = $true
    $script:retryPrompts = 0
    [IO.File]::SetLastWriteTimeUtc($late, $retryContext.Now.AddDays(-10))
    $retryPlan = Get-CleanPlan $retryContext 'cache'
    Assert-CleanTest ($retryPlan.Entries.Count -eq 1) '取消夹具存在明确候选'
    Assert-CleanThrows { Invoke-CleanRegularPlan $retryPlan $retryContext -ReadAnswer { $script:retryPrompts++; return '' } } '取消异常立即传播'
    Assert-CleanTest ($script:retryPrompts -eq 0 -and [IO.File]::Exists($late)) '取消不吞掉、不提示重试、不继续清理'
    Set-Item Function:Invoke-CleanEntry $entryOriginal
    $script:CleanLog = $null
    $outside = Join-Path $temporary 'outside/preserve.txt'
    Write-CleanFixture $outside
    $link = Join-Path $context.Local 'pip/Cache/link'
    $linked = $false
    try { [void](New-Item -ItemType SymbolicLink -Path $link -Target ([IO.Path]::GetDirectoryName($outside)) -ErrorAction Stop); $linked = $true } catch { Write-Host 'SKIP: 当前用户不能创建符号链接，链接夹具另验。' }
    if ($linked) {
        $linkPlan = Get-CleanPlan $context 'dev-caches'
        Assert-CleanTest (@($linkPlan.Entries | Where-Object Path -eq $link).Count -eq 0 -and $linkPlan.Notes.Count -gt 0) '重解析候选排除并记录'
        Assert-CleanThrows { Assert-CleanPath (Join-Path $link 'preserve.txt') $profile } '重解析父链拒绝'
        Assert-CleanTest ([IO.File]::ReadAllText($outside) -eq 'fixture') '链接外部目标原样保留'
        if ([IO.Directory]::Exists($link)) { [IO.Directory]::Delete($link) }
    }
    $package = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $installer = Import-Module (Join-Path $package 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
    $release = Join-Path $temporary 'standalone-release'
    & $installer { param($Source, $Destination) New-JobsPackageRelease $Source $Destination } $package $release | Out-Null
    Assert-CleanTest ([IO.File]::ReadAllText((Join-Path $release 'Scripts/Clean.ps1/Clean.ps1')) -ceq [IO.File]::ReadAllText($scriptPath)) '独立发布携带完整相同Clean无需外仓'
    Assert-CleanTest ([IO.File]::Exists((Join-Path $release 'Scripts/Clean.ps1/README.md'))) '独立发布携带就近说明'
    Remove-Module $installer
    Write-Host ('PASS: CleanTests (' + $checks + ' assertions)')
} finally {
    # 本轮唯一创建的临时根；先移除可能的链接夹具，再清理测试数据。
    if ([IO.Directory]::Exists($temporary)) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}

# ManagementExecution.Tests.ps1 | GUI 后台安装事务与输出回归
# Created by Jobs on 2026年10月28日，星期三.
# 只执行临时目录中的假安装器；不访问用户状态或注册表，不构建真实扩展。
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Write-Host 'CHECKPOINT: entering management execution suite'
$root = Split-Path -Parent $PSScriptRoot
$panel = Import-Module (Join-Path $root 'Scripts/Installer.psm1') -PassThru -Force -DisableNameChecking
Initialize-JobsManagementProcess
Write-Host 'CHECKPOINT: management process type initialized'
$script:Assertions = 0
function Assert-Management {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
    $script:Assertions++
}
$temp = Join-Path ([IO.Path]::GetTempPath()) ('Jobs Management 中文 ' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
function Write-TestFile {
    param([string]$Path, [string]$Text)
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($true)))
}
function New-TestOperation {
    param([string]$Id, [string]$Mode = 'Install')
    [pscustomobject]@{ Id = $Id; Label = $Id; PackagePath = (Join-Path $temp $Id); Mode = $Mode; DisplayMode = $Mode; FeatureIds = @($Id) }
}
function Invoke-TestWorker {
    param([object[]]$Plan)
    $request = Join-Path $temp ([guid]::NewGuid().ToString('N') + '.json')
    Write-TestFile $request (ConvertTo-Json -InputObject @{ Plan = @($Plan) } -Depth 8)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = (Get-Process -Id $PID).Path
    $start.Arguments = '-NoLogo -NoProfile -NonInteractive -File "' + (Join-Path $root 'Scripts/ManagementWorker.ps1') + '" -RequestPath "' + $request + '"'
    $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $start.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    $pump = New-Object JobsManagement.OutputPump
    $chunks = @()
    $live = $false
    $stderrLive = $false
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        $pump.Start($start)
        do {
            while ($null -ne ($chunk = $pump.Take())) {
                $chunks += $chunk
                if ($chunk.Text.Contains('正在编译42%') -and -not $pump.Process.HasExited) { $live = $true }
                if ($chunk.Text.Contains('标准错误中文') -and -not $pump.Process.HasExited) { $stderrLive = $true }
            }
            if ($clock.ElapsedMilliseconds -gt 20000) { $pump.Process.Kill(); throw '假后台超时。' }
            [void]$pump.Process.WaitForExit(25)
        } until ($pump.Process.HasExited -and $pump.Drained -and $pump.Lines.IsEmpty)
        $events = @($chunks | Where-Object { $_.IsEvent } | ForEach-Object { $_.Text.Substring(16) | ConvertFrom-Json })
        return [pscustomobject]@{ ExitCode = $pump.Process.ExitCode; Chunks = $chunks; Events = $events; Live = $live; StderrLive = $stderrLive; Text = (($chunks | ForEach-Object { $_.Text }) -join '') }
    } finally { $pump.Dispose() }
}
try {
    # 真实 Timer 回调从模块外执行，覆盖动态闭包对私有函数的寻址，不需要图形桌面。
    $timerPump = [pscustomobject]@{ Process=[pscustomobject]@{HasExited=$false} }
    $timerPump | Add-Member ScriptMethod Take { return $null }
    $timerState = [pscustomobject]@{
        Running=$true; Pump=$timerPump; FeatureStates=@{alpha='Pending'}; Operation='Install'
        RunClocks=@{Install=(New-Object Diagnostics.Stopwatch)}
        Progress=[pscustomobject]@{Value=0;Maximum=1}; StatusLabel=[pscustomobject]@{Text=''}
    }
    $timerCallback = & $panel { param($State) New-JobsManagementTimerCallback $State } $timerState
    & $timerCallback
    Assert-Management ($timerState.StatusLabel.Text.Contains('安装用时') -and $timerState.StatusLabel.Text.Contains('0 / 1')) '真实 Timer 闭包在模块外仍能读取输出并调用私有进度函数'
    $module = @'
function Invoke-JobsPackageChange {
    param([string]$PackagePath, [string]$Mode, [string[]]$ActionIds)
    [Console]::Out.Write('正在编译42%'); [Console]::Out.Flush()
    [Console]::Error.Write('标准错误中文'); [Console]::Error.Flush()
    Start-Sleep -Milliseconds 700
    Write-Host '实时宿主日志'
    Add-Content -LiteralPath (Join-Path $PackagePath 'called.txt') -Value ($Mode + ':' + ($ActionIds -join ',')) -Encoding UTF8
    if ((Split-Path -Leaf $PackagePath) -eq 'beta') { throw '隔离安装失败' }
    [pscustomobject]@{ Backup = (Join-Path $PackagePath 'fake-backup') }
}
Export-ModuleMember -Function Invoke-JobsPackageChange
'@
    foreach ($id in @('alpha', 'beta', 'gamma')) {
        Write-TestFile (Join-Path $temp ($id + '/Scripts/PackageInstaller.psm1')) $module
        Write-TestFile (Join-Path $temp ($id + '/Extension.json')) (ConvertTo-Json -InputObject @{ Id = $id })
    }
    $operation = New-TestOperation 'alpha'
    $operation | Add-Member -NotePropertyName ActionIds -NotePropertyValue @('single-action')
    Write-Host 'CHECKPOINT: starting isolated workers'
    $success = Invoke-TestWorker @($operation)
    Assert-Management ($success.ExitCode -eq 0) '成功事务返回零'
    Assert-Management ($success.Live -and $success.StderrLive) '未换行中文 stdout 与 stderr 在进程结束前分别可见'
    Assert-Management ($success.Text.Contains('实时宿主日志') -and $success.Text.Contains('fake-backup')) '宿主与备份日志进入同一输出'
    Assert-Management (($success.Events.State -join ',') -eq 'Running,Succeeded,Finished') '成功状态有明确开始完成与会话结束'
    Assert-Management ((Get-Content (Join-Path $temp 'alpha/called.txt') -Raw).Contains('Install:single-action')) '单元素动作数组完整传入假安装器'
    $failed = Invoke-TestWorker @((New-TestOperation 'alpha' 'Uninstall'), (New-TestOperation 'beta'), (New-TestOperation 'gamma'))
    Assert-Management ($failed.ExitCode -ne 0) '失败事务返回非零'
    Assert-Management (($failed.Events.State -join ',') -eq 'Running,Succeeded,Running,Failed,Running,Succeeded,Finished') '单包失败保留前项并继续后续包，最后汇总失败'
    Assert-Management ([IO.File]::Exists((Join-Path $temp 'gamma/called.txt'))) '前项失败后仍执行其它所选假安装器'
    Assert-Management ($failed.Text.Contains('隔离安装失败')) '失败原因保留在实时输出'
    Assert-Management (@($failed.Events | Where-Object { $_.State -eq 'Failed' })[0].FeatureIds[0] -eq 'beta') '失败精确映射到本包叶 ID'
    $missing = Invoke-TestWorker @((New-TestOperation 'missing-source'), (New-TestOperation 'gamma' 'Uninstall'))
    Assert-Management ($missing.ExitCode -ne 0) '所选包缺失源码时汇总失败'
    Assert-Management (($missing.Events.State -join ',') -eq 'Running,Failed,Running,Succeeded,Finished') '缺失所选包仅标记自身，后续卸载仍执行'
    Assert-Management ((Get-Content (Join-Path $temp 'gamma/called.txt') -Raw).Contains('Uninstall:')) '卸载入口不要求存在构建脚本'
    $betaCalls = Get-Content (Join-Path $temp 'beta/called.txt') -Raw
    Write-TestFile (Join-Path $temp 'beta/Extension.json') '{"Id":"wrong-owner"}'
    $identity = Invoke-TestWorker @((New-TestOperation 'beta'), (New-TestOperation 'gamma'))
    Assert-Management (($identity.Events.State -join ',') -eq 'Running,Failed,Running,Succeeded,Finished') '身份不一致的包在导入前失败，但其它包继续'
    Assert-Management ((Get-Content (Join-Path $temp 'beta/called.txt') -Raw) -ceq $betaCalls) '身份错误时不调用该包安装器'
    $empty = Invoke-TestWorker @()
    Assert-Management ($empty.ExitCode -ne 0 -and $empty.Events.Count -eq 0) '全局计划为空时立即停止，不开始任何包'
    Write-Host 'CHECKPOINT: isolated workers completed, checking launchers'
    foreach ($folder in Get-ChildItem $root -Directory | Where-Object { $_.Name -like 'Jobs*' -and (Test-Path (Join-Path $_.FullName 'Scripts/Manage.ps1')) }) {
        $vbs = Get-Content -LiteralPath (Join-Path $folder.FullName 'Manage.vbs') -Raw
        $cmd = Get-Content -LiteralPath (Join-Path $folder.FullName 'Manage.cmd') -Raw
        $code = @($cmd -split '\r?\n' | Where-Object { $_ -notmatch '^\s*(rem\b|::)' }) -join "`n"
        Assert-Management ($vbs.Contains('shell.Run command, 0, False') -and $vbs.Contains('-WindowStyle Hidden')) ('无控制台入口：' + $folder.Name)
        Assert-Management ($cmd.Contains('wscript.exe') -and $cmd -notmatch '\bpause\b') ('CMD 兼容入口仅转交隐藏 GUI：' + $folder.Name)
        Assert-Management ($code -match '(?im)^exit /b %errorlevel%\s*$' -and $code -notmatch '(?i)taskkill|start\s+/wait|powershell|Read-Host') ('CMD 唤起后立即结束脚本，不关闭已有会话或承担后台任务：' + $folder.Name)
    }
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        Add-Type -AssemblyName System.Windows.Forms
        # 事件异常直接令夹具失败，不能弹默认错误对话框卡住原生回归。
        [Windows.Forms.Application]::SetUnhandledExceptionMode([Windows.Forms.UnhandledExceptionMode]::ThrowException)
        # 真实 CMD / WScript 链只启动临时假界面进程，验证启动脚本不会等待其任务结束。
        Write-Host 'CHECKPOINT: starting real CMD and WScript fixture'
        $launcherRoot = Join-Path $temp 'CMD 启动 中文'
        $fakeManager = @'
$directory = Split-Path -Parent $PSScriptRoot
[IO.File]::WriteAllText((Join-Path $directory 'started'), 'ready')
$deadline = [DateTime]::UtcNow.AddSeconds(15)
while (-not [IO.File]::Exists((Join-Path $directory 'release')) -and [DateTime]::UtcNow -lt $deadline) {
    [Threading.Thread]::Sleep(25)
}
[IO.File]::WriteAllText((Join-Path $directory 'finished'), 'done')
'@
        Write-TestFile (Join-Path $launcherRoot 'Scripts/Manage.ps1') $fakeManager
        Copy-Item -LiteralPath (Join-Path $root 'Infrastructure/Manage.cmd') -Destination (Join-Path $launcherRoot 'Manage.cmd')
        Copy-Item -LiteralPath (Join-Path $root 'Infrastructure/Manage.vbs') -Destination (Join-Path $launcherRoot 'Manage.vbs')
        $launchStart = New-Object Diagnostics.ProcessStartInfo
        $launchStart.FileName = Join-Path $env:SystemRoot 'System32/cmd.exe'
        $launchStart.Arguments = '/d /c ""' + (Join-Path $launcherRoot 'Manage.cmd') + '""'
        $launchStart.UseShellExecute = $false
        $launchStart.CreateNoWindow = $true
        $launch = [Diagnostics.Process]::Start($launchStart)
        try {
            if (-not $launch.WaitForExit(10000)) { $launch.Kill(); throw 'CMD 轻量启动器未及时退出。' }
            Assert-Management ($launch.ExitCode -eq 0) '原 CMD 成功唤起 WScript 后结束'
            $deadline = [DateTime]::UtcNow.AddSeconds(10)
            while (-not (Test-Path -LiteralPath (Join-Path $launcherRoot 'started')) -and [DateTime]::UtcNow -lt $deadline) { [Threading.Thread]::Sleep(25) }
            Assert-Management (Test-Path -LiteralPath (Join-Path $launcherRoot 'started')) '中文空格目录经原 CMD 和 VBS 启动隐藏假界面'
            Assert-Management (-not (Test-Path -LiteralPath (Join-Path $launcherRoot 'finished'))) 'CMD 结束时隐藏界面仍在运行，任务不依附启动窗口'
        } finally {
            [IO.File]::WriteAllText((Join-Path $launcherRoot 'release'), 'finish')
            $deadline = [DateTime]::UtcNow.AddSeconds(10)
            while (-not (Test-Path -LiteralPath (Join-Path $launcherRoot 'finished')) -and [DateTime]::UtcNow -lt $deadline) { [Threading.Thread]::Sleep(25) }
            $launch.Dispose()
        }
        Write-Host 'CHECKPOINT: CMD and WScript fixture completed, creating form'
        $features = @([pscustomobject]@{ Id = 'alpha'; Label = '假安装功能'; Description = '隔离测试'; Group = '测试' })
        $plan = @($operation)
        $factory = { param($Choice) $plan }.GetNewClosure()
        $state = & $panel { param($Features, $BuildPlan, $Worker) New-JobsFeatureSelectionForm -Packages $Features -Selected @('alpha') -BuildPlan $BuildPlan -WorkerPath $Worker } $features $factory (Join-Path $root 'Scripts/ManagementWorker.ps1')
        try {
            Assert-Management ($state.LogView.ReadOnly -and $state.LogView.ShortcutsEnabled) 'GUI 日志只读且允许键盘复制'
            Assert-Management (-not $state.Form.TopMost) '任务面板是普通窗口，不在其它应用之上置顶'
            Write-Host 'CHECKPOINT: starting form background transaction'
            Start-JobsManagementRun $state ([pscustomobject]@{ Features = @('alpha'); Mode = 'Install' })
            Assert-Management ($state.Running -and -not $state.CancelButton.Enabled -and -not $state.Checks[0].Enabled) '执行时禁用选择与关闭，保留事务生命周期'
            Write-Host 'CHECKPOINT: pumping form events and output'
            $clock = [Diagnostics.Stopwatch]::StartNew()
            while ($state.Running -and $clock.ElapsedMilliseconds -lt 20000) {
                [Windows.Forms.Application]::DoEvents()
                [Threading.Thread]::Sleep(25)
                Read-JobsManagementOutput $state
            }
            Assert-Management (-not $state.Running -and $state.FeatureStates['alpha'] -eq 'Succeeded') 'GUI 完成后显示叶项成功并保留面板'
            Assert-Management ($state.LogView.Text.Contains('正在编译42%') -and $state.CancelButton.Enabled) 'GUI 内可读执行日志并恢复关闭'
        } finally {
            $state.Timer.Dispose(); $state.LogView.Font.Dispose(); $state.Form.Dispose(); $state.ToolTip.Dispose(); $state.Font.Dispose()
        }
    } else { Write-Host 'SKIP: WinForms 实际控件需要 Windows；假后台与无换行双流已验证。' }
} finally { Remove-Item -LiteralPath $temp -Recurse -Force }
Write-Host ('PASS: ManagementExecution.Tests.ps1 (' + $script:Assertions + ' assertions)')

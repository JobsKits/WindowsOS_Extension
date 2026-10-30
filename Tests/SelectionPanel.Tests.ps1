# SelectionPanel.Tests.ps1 | WindowsOS@Extension 安装选择面板回归
# Created by Jobs on 2026年10月20日，星期二.
# 只检查选择、布局和编排计划；不显示模态窗口，不安装扩展或写入注册表。
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:Assertions = 0
$root = Split-Path -Parent $PSScriptRoot
$installer = Import-Module (Join-Path $root 'Scripts/Installer.psm1') -PassThru -Force -DisableNameChecking
Import-Module (Join-Path $root 'Scripts/Catalog.psm1') -Force -DisableNameChecking

function Assert-Selection {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
    $script:Assertions++
}

function Assert-SelectionThrows {
    param([scriptblock]$Body, [string]$Message)
    $threw = $false
    try { & $Body | Out-Null } catch { $threw = $true }
    Assert-Selection $threw $Message
}

$packages = @(Get-JobsFeaturePackages -Root $root)
$normal = Get-JobsFeatureSelectionLayout -ItemCount $packages.Count -WorkingWidth 1280 -WorkingHeight 900
Assert-Selection ($normal.Columns -ge 1 -and $normal.Columns -le 3 -and $normal.Rows * $normal.Columns -ge $packages.Count) '普通工作区完整覆盖当前全部功能'
Assert-Selection ($normal.ClientWidth -le 1280 -and $normal.ClientHeight -le 900) '普通布局不超过工作区'
Assert-Selection ($normal.RowHeight -eq 34) '默认行高保留完整点击区域'
$short = Get-JobsFeatureSelectionLayout -ItemCount $packages.Count -WorkingWidth 1280 -WorkingHeight 540
Assert-Selection ($short.Columns -in @(2, 3)) '矮屏使用多列固定布局'
Assert-Selection ($short.Rows -eq [int][Math]::Ceiling($packages.Count / [double]$short.Columns)) '列数覆盖每项功能且不丢失末项'
Assert-Selection ($short.ClientWidth -le 1280 -and $short.ClientHeight -le 496) '矮屏布局仍保留系统标题栏和边框空间'
Assert-Selection ($short.RowHeight -eq 34) '当前全部功能在短屏保留行高'
$evenShort = Get-JobsFeatureSelectionLayout -ItemCount 16 -WorkingWidth 1280 -WorkingHeight 540
Assert-Selection ($evenShort.Columns -eq 2 -and $evenShort.Rows -eq 8 -and $evenShort.ClientHeight -le 460) '原有16项短屏布局保持两列'
$eighteen = Get-JobsFeatureSelectionLayout -ItemCount 18 -WorkingWidth 1280 -WorkingHeight 540
Assert-Selection ($eighteen.Columns -eq 2 -and $eighteen.Rows -eq 9 -and $eighteen.ClientHeight -le 496) '18项短屏扩展窗口后保持两列'
$nineteen = Get-JobsFeatureSelectionLayout -ItemCount 19 -WorkingWidth 1280 -WorkingHeight 540
Assert-Selection ($nineteen.Columns -eq 3 -and $nineteen.Rows -eq 7 -and $nineteen.ClientWidth -le 1232) '19项短屏使用三列且保留左右边框'
$twentyOne = Get-JobsFeatureSelectionLayout -ItemCount 21 -WorkingWidth 1280 -WorkingHeight 540
Assert-Selection ($twentyOne.Columns -eq 3 -and $twentyOne.Rows -eq 7 -and $twentyOne.ClientHeight -le 496) '含鸿蒙的21项短屏保持三列完整点击区域'
$many = Get-JobsFeatureSelectionLayout -ItemCount 40 -WorkingWidth 1280 -WorkingHeight 540
Assert-Selection ($many.ClientHeight -le 496 -and $many.FooterHeight -ge 90) '更多子功能使用内容区滚动回退并保留固定按钮'
$scaled = Get-JobsFeatureSelectionLayout -ItemCount $packages.Count -WorkingWidth 2560 -WorkingHeight 1440 -RowHeight 51 -Scale 1.5
Assert-Selection ($scaled.RowHeight -ge 51) '高 DPI 下点击区域随比例放大'
Assert-Selection ($scaled.ClientWidth -le 2560 -and $scaled.ClientHeight -le 1440) '高 DPI 布局仍在工作区内'
Assert-SelectionThrows { Get-JobsFeatureSelectionLayout -ItemCount $packages.Count -WorkingWidth 260 -WorkingHeight 180 } '过小工作区明确拒绝截断面板'

# 真实完成状态驱动百分比，计时格式独立于 Windows 控件与后台安装器。
$progressChecks = & $installer {
    $states = @{}
    foreach ($index in 1..81) { $states[[string]$index] = 'Pending' }
    foreach ($index in 1..11) { $states[[string]$index] = 'Succeeded' }
    $states['12'] = 'Failed'
    $states['13'] = 'Running'
    $states['14'] = 'Skipped'
    $state = [pscustomobject]@{
        FeatureStates = $states; Operation = 'Install'
        Progress = [pscustomobject]@{ Value = 0; Maximum = 81 }
        StatusLabel = [pscustomobject]@{ Text = '' }
        RunClocks = @{
            Install = [pscustomobject]@{ Elapsed = [TimeSpan]::FromSeconds(83) }
            Uninstall = [pscustomobject]@{ Elapsed = [TimeSpan]::FromSeconds(7) }
        }
    }
    Update-JobsManagementProgress $state
    $installText = $state.StatusLabel.Text
    $processed = $state.Progress.Value
    $state.Operation = 'Uninstall'
    $state.RunClocks.Uninstall.Elapsed = [TimeSpan]::FromSeconds(8)
    Update-JobsManagementProgress $state
    $uninstallText = $state.StatusLabel.Text
    $state.FeatureStates = @{}
    $empty = Get-JobsManagementProgress $state
    [pscustomobject]@{
        InstallText = $installText; UninstallText = $uninstallText; Processed = $processed; Empty = $empty
        Times = @(0, 59, 60, 3599, 3600, 90061, 360001 | ForEach-Object { Format-JobsManagementElapsedTime ([TimeSpan]::FromSeconds($_)) })
    }
}
Assert-Selection ($progressChecks.Processed -eq 12 -and $progressChecks.InstallText.Contains('12 / 81 项（14.8%，按完成项计数）')) '失败项计入已处理，运行中与未执行项不计入，百分比显示一位小数'
Assert-Selection ($progressChecks.InstallText.Contains('安装 / 更新中') -and $progressChecks.InstallText.Contains('安装用时 00:01:23')) '安装进度与独立累计耗时同时显示'
Assert-Selection ($progressChecks.UninstallText.Contains('卸载中') -and $progressChecks.UninstallText.Contains('卸载用时 00:00:08')) '切到卸载选择独立时钟，没有新完成项时耗时仍可刷新'
Assert-Selection ($progressChecks.Empty.Total -eq 0 -and $progressChecks.Empty.Finished -eq 0 -and $progressChecks.Empty.Percent -ceq '0.0') '空计划安全显示零百分比'
Assert-Selection (($progressChecks.Times -join ',') -ceq '00:00:00,00:00:59,00:01:00,00:59:59,01:00:00,25:01:01,100:00:01') '时分秒向下取整且小时累计不按天回卷'

$lifecycleChecks = & $installer {
    # 只替换日志与计时器外设，不加载 WinForms、不启动安装进程。
    function Add-JobsManagementLog { param($State, [string]$Text) $State.LastLog = $Text }
    function New-ClockTestState {
        $timer = [pscustomobject]@{ Stopped = $false }
        $timer | Add-Member ScriptMethod Stop { $this.Stopped = $true }
        [pscustomobject]@{
            RunClocks = @{ Install = (New-Object Diagnostics.Stopwatch); Uninstall = (New-Object Diagnostics.Stopwatch) }
            Timer = $timer; Started = $false; Running = $false
            FeatureStates = @{}; Progress = [pscustomobject]@{ Value = 0; Maximum = 1; Style = 'Continuous' }
            StatusLabel = [pscustomobject]@{ Text = '' }; Pump = $null; RequestPath = $null; Operation = 'Install'
            CancelButton = [pscustomobject]@{ Enabled = $false; Text = '取消' }; Form = [pscustomobject]@{ CancelButton = $null }
            LogPath = 'unused-fixture.log'; LastLog = ''; BuildPlan = $null; ClockWasRunning = $false
        }
    }
    $state = New-ClockTestState
    $state.FeatureStates = @{ alpha = 'Succeeded'; beta = 'Failed' }
    $state.Progress.Maximum = 2
    $state.Running = $true
    $state.RunClocks.Install.Start()
    $state.RunClocks.Uninstall.Start()
    Complete-JobsManagementRun $state $false '隔离失败结果。'
    $frozenTicks = $state.RunClocks.Install.ElapsedTicks
    [Threading.Thread]::Sleep(10)
    $finished = -not $state.RunClocks.Install.IsRunning -and $state.RunClocks.Install.ElapsedTicks -eq $frozenTicks -and $state.Timer.Stopped -and -not $state.Running
    $otherClockRunning = $state.RunClocks.Uninstall.IsRunning
    $state.RunClocks.Uninstall.Stop()
    $completionText = $state.StatusLabel.Text
    $finalLogged = $state.LastLog.Contains($completionText)
    $failure = New-ClockTestState
    $failure.BuildPlan = {
        param($Choice)
        $failure.ClockWasRunning = $failure.RunClocks.Install.IsRunning -and -not $failure.RunClocks.Uninstall.IsRunning
        throw '隔离计划失败'
    }.GetNewClosure()
    Start-JobsManagementRun $failure ([pscustomobject]@{ Mode = 'Install' })
    $empty = New-ClockTestState
    $empty.BuildPlan = { param($Choice) @() }
    Start-JobsManagementRun $empty ([pscustomobject]@{ Mode = 'Install' })
    $uninstall = New-ClockTestState
    $uninstall.RunClocks.Install.Start()
    [Threading.Thread]::Sleep(10)
    $uninstall.RunClocks.Install.Stop()
    $installTicks = $uninstall.RunClocks.Install.ElapsedTicks
    $uninstall.BuildPlan = {
        param($Choice)
        $uninstall.ClockWasRunning = $uninstall.RunClocks.Uninstall.IsRunning -and -not $uninstall.RunClocks.Install.IsRunning
        throw '隔离卸载计划失败'
    }.GetNewClosure()
    Start-JobsManagementRun $uninstall ([pscustomobject]@{ Mode = 'Uninstall' })
    [pscustomobject]@{
        Finished = $finished; CompletionText = $completionText; FinalLogged = $finalLogged
        Failed = $failure.ClockWasRunning -and -not $failure.RunClocks.Install.IsRunning -and $failure.StatusLabel.Text.Contains('隔离计划失败') -and $failure.StatusLabel.Text.Contains('安装总用时')
        Empty = -not $empty.RunClocks.Install.IsRunning -and -not $empty.Started -and $empty.StatusLabel.Text.Contains('没有需要处理')
        StopsOnlyActive = $otherClockRunning
        IndependentUninstall = $uninstall.ClockWasRunning -and -not $uninstall.RunClocks.Uninstall.IsRunning -and $uninstall.RunClocks.Install.ElapsedTicks -eq $installTicks -and $uninstall.StatusLabel.Text.Contains('卸载总用时')
    }
}
Assert-Selection $lifecycleChecks.Finished '事务结束停止计时器并冻结耗时'
Assert-Selection ($lifecycleChecks.CompletionText.Contains('100.0%') -and $lifecycleChecks.CompletionText.Contains('总用时') -and $lifecycleChecks.CompletionText.Contains('隔离失败结果')) '包含失败的完整批次保留结果、百分比与最终耗时'
Assert-Selection $lifecycleChecks.FinalLogged '最终耗时与百分比进入可复制会话日志'
Assert-Selection $lifecycleChecks.Failed '计时覆盖建立计划，计划失败也停止并显示最终耗时'
Assert-Selection $lifecycleChecks.Empty '没有操作计划时停止计时且不锁定面板'
Assert-Selection $lifecycleChecks.StopsOnlyActive '安装结束只停止安装时钟，不修改卸载时钟'
Assert-Selection $lifecycleChecks.IndependentUninstall '卸载单独重置与停止自己的时钟，不覆盖已冻结的安装时长'

# 真实字体先在 Windows 测量；此处用像素宽度覆盖高 DPI、减列及超长标题换行。
foreach ($scale in @(1.0, 1.25, 1.5, 2.0)) {
    $metrics = @{
        MinimumPanelWidth = [int][Math]::Ceiling(540 * $scale)
        MinimumCheckWidth = [int][Math]::Ceiling(330 * $scale)
        StatusWidth = [int][Math]::Ceiling(120 * $scale)
        GroupControlsWidth = [int][Math]::Ceiling(280 * $scale)
        Scale = $scale
    }
    $wide = Get-JobsFeatureContentLayout -WorkingWidth ([int](2560 * $scale)) -PreferredColumns 3 @metrics
    Assert-Selection ($wide.Columns -eq 3) ('宽屏容纳三列完整标题：DPI比例 ' + $scale)
    Assert-Selection ($wide.PanelWidth -ge $metrics.MinimumPanelWidth -and -not $wide.Wrapped) ('宽屏按字体测量宽度保留完整单行：' + $scale)
    Assert-Selection ($wide.CheckWidth -ge $metrics.MinimumCheckWidth -and $wide.StatusWidth -ge $metrics.StatusWidth) ('标题和状态各自拥有独立空间：' + $scale)
    Assert-Selection ($wide.CheckWidth + $wide.StatusWidth -le $wide.PanelWidth) ('标题与状态不能横向重叠：' + $scale)
    Assert-Selection ($wide.ClientWidth -le 2560 * $scale - [Math]::Ceiling(48 * $scale)) ('宽屏保留系统边框余量：' + $scale)

    $compact = Get-JobsFeatureContentLayout -WorkingWidth ([int](1280 * $scale)) -PreferredColumns 3 @metrics
    Assert-Selection ($compact.Columns -ge 1 -and $compact.Columns -lt 3) ('空间不足时减少列数，保留文字宽度：' + $scale)
    Assert-Selection ($compact.PanelWidth -ge $metrics.GroupControlsWidth) ('组选择和完整计数仍在分组内：' + $scale)
    Assert-Selection ($compact.CheckWidth + $compact.StatusWidth -le $compact.PanelWidth) ('减列后标题状态区域不重叠：' + $scale)
    Assert-Selection ($compact.ClientWidth -le 1280 * $scale - [Math]::Ceiling(48 * $scale)) ('减列后窗口仍在工作区：' + $scale)

    $long = Get-JobsFeatureContentLayout -WorkingWidth ([int](660 * $scale)) -PreferredColumns 3 -MinimumPanelWidth ([int](1200 * $scale)) -MinimumCheckWidth ([int](120 * $scale)) -StatusWidth $metrics.StatusWidth -GroupControlsWidth $metrics.GroupControlsWidth -Scale $scale
    Assert-Selection ($long.Columns -eq 1 -and $long.Wrapped) ('超长功能在窄屏退为单列换行：' + $scale)
    Assert-Selection ($long.CheckWidth -ge 120 * $scale -and $long.CheckWidth -lt 1000 * $scale) ('窄屏换行保留可读正文宽度：' + $scale)
    Assert-Selection ($long.PanelWidth -ge $metrics.GroupControlsWidth -and $long.CheckWidth + $long.StatusWidth -le $long.PanelWidth) ('超长标题不挤压计数或状态：' + $scale)
    Assert-Selection ($long.ClientWidth -le 660 * $scale - [Math]::Ceiling(48 * $scale)) ('长标题不把窗口撑出工作区：' + $scale)

    $single = Get-JobsFeatureContentLayout -WorkingWidth ([int](1024 * $scale)) -PreferredColumns 1 @metrics
    Assert-Selection ($single.Columns -eq 1 -and $single.CheckWidth -ge $metrics.MinimumCheckWidth) ('单功能范围也保留完整正文宽度：' + $scale)
    Assert-Selection ($single.PanelWidth -ge $metrics.GroupControlsWidth -and $single.ClientWidth -le 1024 * $scale - [Math]::Ceiling(48 * $scale)) ('单功能范围完整计数且不越界：' + $scale)
}

# 日志拖动上下限按 DPI 和实际工具栏 / 操作区测量，极端位置不能遮住按钮。
foreach ($scale in @(1.0, 1.25, 1.5, 2.0)) {
    $geometry = @{
        Height = [int](600 * $scale); FooterHeight = [int](110 * $scale)
        ToolbarHeight = [int](45 * $scale); RowHeight = [int](34 * $scale)
        SplitterWidth = [int](7 * $scale); Scale = $scale
    }
    $maximum = & $installer { param($Values) Get-JobsManagementLogLayout @Values -LogHeight 100000 } $geometry
    $minimum = & $installer { param($Values) Get-JobsManagementLogLayout @Values -LogHeight 0 } $geometry
    Assert-Selection ($maximum.Distance -eq $geometry.FooterHeight + $geometry.RowHeight) ('向上拖至极限仍保留操作栏和一行功能：' + $scale)
    Assert-Selection ($minimum.LogHeight -eq $geometry.ToolbarHeight + [Math]::Ceiling(60 * $scale)) ('向下拖至极限保留工具栏和可读日志：' + $scale)
    Assert-Selection ($maximum.Distance + $maximum.LogHeight + $geometry.SplitterWidth -eq $geometry.Height) ('拖动后两区尺寸完整覆盖容器：' + $scale)
    $normalLogHeight = [int](180 * $scale)
    $normalLog = & $installer { param($Values, $Height) Get-JobsManagementLogLayout @Values -LogHeight $Height } $geometry $normalLogHeight
    Assert-Selection ($normalLog.LogHeight -eq $normalLogHeight) ('有效用户拖动位置不会被进度刷新重置：' + $scale)
    $geometry.FooterHeight += [int](50 * $scale)
    $updated = & $installer { param($Values, $Height) Get-JobsManagementLogLayout @Values -LogHeight $Height } $geometry $maximum.LogHeight
    Assert-Selection ($updated.Distance -eq $geometry.FooterHeight + $geometry.RowHeight -and $updated.LogHeight -lt $maximum.LogHeight) ('长进度说明扩高操作栏后自动收紧日志上限：' + $scale)
}
Assert-SelectionThrows { & $installer { Get-JobsManagementLogLayout -Height 120 -FooterHeight 100 -ToolbarHeight 45 -RowHeight 34 -SplitterWidth 7 -LogHeight 180 } } '不可显示操作栏的尺寸明确拒绝'

$fixtures = @(
    [pscustomobject]@{ Id = 'alpha'; Label = '甲功能'; Description = '甲功能说明'; PackagePath = 'alpha' },
    [pscustomobject]@{ Id = 'beta'; Label = '乙功能'; Description = '乙功能说明'; PackagePath = 'beta' },
    [pscustomobject]@{ Id = 'gamma'; Label = '丙功能'; Description = '丙功能说明'; PackagePath = 'gamma' }
)
$install = @(Get-JobsPackageOperationPlan -Packages $fixtures -Selected @('beta') -Installed @('alpha', 'beta') -Mode Install)
Assert-Selection ($install.Count -eq 1 -and $install[0].Id -eq 'beta' -and $install[0].Mode -eq 'Install') '安装只处理勾选项，保留未选的已安装功能'
Assert-Selection (@(Get-JobsPackageOperationPlan -Packages $fixtures -Selected @() -Installed @('alpha') -Mode Install).Count -eq 0) '空选安装计划不会隐式卸载已有功能'
$configure = @(Get-JobsPackageOperationPlan -Packages $fixtures -Selected @('beta') -Installed @('alpha', 'beta') -Mode Configure)
Assert-Selection (@($configure | Where-Object { $_.Id -eq 'alpha' -and $_.Mode -eq 'Uninstall' }).Count -eq 1) '配置模式保留取消勾选即卸载的语义'
Assert-Selection (@($configure | Where-Object { $_.Id -eq 'beta' -and $_.Mode -eq 'Install' }).Count -eq 1) '配置模式安装仍然勾选的功能'
$emptyConfigure = @(Get-JobsPackageOperationPlan -Packages $fixtures -Selected @() -Installed @('alpha', 'beta') -Mode Configure)
Assert-Selection ($emptyConfigure.Count -eq 2 -and @($emptyConfigure | Where-Object { $_.Mode -ne 'Uninstall' }).Count -eq 0) '配置模式允许保存空选以卸载现有功能'
$uninstall = @(Get-JobsPackageOperationPlan -Packages $fixtures -Selected @('alpha', 'gamma') -Installed @('alpha', 'beta') -Mode Uninstall)
Assert-Selection ($uninstall.Count -eq 1 -and $uninstall[0].Id -eq 'alpha' -and $uninstall[0].Mode -eq 'Uninstall') '卸载只处理选中且已安装的功能'
Assert-SelectionThrows { Get-JobsPackageOperationPlan -Packages $fixtures -Selected @('unknown') -Installed @() -Mode Install } '未知功能标识不会进入安装计划'

foreach ($entry in @(
    @{ Name = '【Windows】🧩管理资源管理器扩展.cmd'; Mode = 'Manage' }
)) {
    $entryPath = Join-Path $root $entry.Name
    Assert-Selection (Test-Path -LiteralPath $entryPath -PathType Leaf) ('根目录保留独立入口：' + $entry.Mode)
    $bytes = [IO.File]::ReadAllBytes($entryPath)
    Assert-Selection (@($bytes | Where-Object { $_ -gt 127 }).Count -eq 0) ('CMD 正文使用 ASCII：' + $entry.Mode)
    $source = [Text.Encoding]::ASCII.GetString($bytes)
    Assert-Selection ($source -notmatch '(?<!\r)\n' -and $source.Contains("`r`n")) ('CMD 使用 CRLF：' + $entry.Mode)
    Assert-Selection ($source -match 'wscript\.exe' -and $source -match '%~dpn0\.vbs' -and $source -notmatch '\bpause\b' -and $source -notmatch '-Mode\s+(Install|Uninstall)' ) ('入口按自身位置直启正确模式：' + $entry.Mode)
}

if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
    function New-SelectionTestState {
        param([object[]]$Items, [string[]]$Selected, [string]$Mode, [string[]]$Installed = @())
        & $installer {
            param($Packages, $Choice, $PanelMode, $InstalledIds)
            New-JobsFeatureSelectionForm -Packages $Packages -Selected $Choice -Installed $InstalledIds -Mode $PanelMode
        } $Items $Selected $Mode $Installed
    }

    function Invoke-SelectionTestClick {
        param($Button)
        # 未显示窗口的 PerformClick 会受 CanSelect 限制；直接触发 Click 测实际事件处理器。
        $flags = [Reflection.BindingFlags]::Instance -bor [Reflection.BindingFlags]::NonPublic
        $method = $Button.GetType().GetMethod('OnClick', $flags)
        [void]$method.Invoke($Button, (,[EventArgs]::Empty))
    }

    function Get-SelectionBoundsInForm {
        param($Control, $Form)
        $left = $Control.Left
        $top = $Control.Top
        $parent = $Control.Parent
        while ($null -ne $parent -and -not [object]::ReferenceEquals($parent, $Form)) {
            $left += $parent.Left
            $top += $parent.Top
            $parent = $parent.Parent
        }
        return New-Object Drawing.Rectangle($left, $top, $Control.Width, $Control.Height)
    }

    function Assert-SelectionTextFits {
        param($Control, [string]$Context, [switch]$SingleLine)
        $proposed = New-Object Drawing.Size($Control.Width, 0)
        if ($SingleLine) { $proposed = [Drawing.Size]::Empty }
        $natural = $Control.GetPreferredSize($proposed)
        Assert-Selection ($natural.Height -le $Control.Height + 1) ($Context + ' 完整文字高度可见：' + $Control.Text)
        if ($SingleLine) {
            Assert-Selection ($natural.Width -le $Control.Width + 1) ($Context + ' 完整文字宽度可见：' + $Control.Text)
        }
        Assert-Selection (-not $Control.AutoEllipsis) ($Context + ' 不用省略号替代完整文字')
    }

    function Assert-SelectionTextLayout {
        param($State, [string]$Context)
        $State.Form.PerformLayout()
        $State.Header.PerformLayout()
        $State.LogToolbar.PerformLayout()
        Assert-SelectionTextFits $State.HeaderLabel ($Context + ' 页眉')
        if ($null -ne $State.OperationBox) {
            $headerBounds = Get-SelectionBoundsInForm $State.HeaderLabel $State.Form
            $operationBounds = Get-SelectionBoundsInForm $State.OperationBox $State.Form
            Assert-Selection (-not $headerBounds.IntersectsWith($operationBounds)) ($Context + ' 操作选择框不遮住页眉文字')
            Assert-Selection ($State.Header.ClientRectangle.Contains($State.OperationBox.Bounds)) ($Context + ' 操作选择框完整位于页眉面板')
        }
        foreach ($group in $State.Groups) {
            $original = $group.Counter.Text
            try {
                foreach ($count in 0..$group.Checks.Count) {
                    $group.Counter.Text = '已选 {0} / {1}' -f $count, $group.Checks.Count
                    Assert-SelectionTextFits $group.Counter ($Context + ' 组计数') -SingleLine
                }
            } finally { $group.Counter.Text = $original }
            Assert-Selection ($group.Counter.Left -ge $group.None.Right) ($Context + ' 组计数不覆盖全不选按钮')
            Assert-Selection ($group.Counter.Right -le $group.Box.ClientSize.Width) ($Context + ' 组计数完整位于分组内')
            foreach ($check in $group.Checks) {
                Assert-SelectionTextFits $check ($Context + ' 功能标题')
                $featureStatus = $State.FeatureLabels[[string]$check.Tag]
                Assert-SelectionTextFits $featureStatus ($Context + ' 逐项状态')
                Assert-Selection ($check.Right -le $featureStatus.Left) ($Context + ' 功能标题不覆盖逐项状态')
                Assert-Selection ($check.Bottom -le $group.Box.ClientSize.Height -and $featureStatus.Bottom -le $group.Box.ClientSize.Height) ($Context + ' 换行后的整行仍位于分组内')
            }
        }
        $previousControls = @()
        foreach ($control in $State.LogToolbar.Controls) {
            $needed = $control.GetPreferredSize([Drawing.Size]::Empty)
            Assert-Selection ($control.Width + 1 -ge $needed.Width -and $control.Height + 1 -ge $needed.Height) ($Context + ' 日志工具完整显示：' + $control.Text)
            Assert-Selection ($State.LogToolbar.ClientRectangle.Contains($control.Bounds)) ($Context + ' 日志工具栏控件未越界')
            foreach ($previous in $previousControls) {
                Assert-Selection (-not $control.Bounds.IntersectsWith($previous.Bounds)) ($Context + ' 换行后的日志工具栏控件不重叠')
            }
            $previousControls += $control
        }
        $originalOperation = $State.Operation
        $originalStates = $State.FeatureStates
        $originalLabels = @{}
        foreach ($key in $State.FeatureLabels.Keys) { $originalLabels[$key] = $State.FeatureLabels[$key].Text }
        try {
            $State.FeatureStates = @{}
            foreach ($check in $State.Checks) { $State.FeatureStates[[string]$check.Tag] = 'Pending' }
            $State.Progress.Maximum = [Math]::Max(1, $State.Checks.Count)
            foreach ($operation in @('Install', 'Uninstall')) {
                $State.Operation = $operation
                foreach ($featureState in @('Pending', 'Running', 'Succeeded', 'Failed', 'Skipped')) {
                    Set-JobsManagementFeatureState -State $State -FeatureIds @($State.FeatureStates.Keys) -Status $featureState -Message '仅测文字尺寸，不执行后台操作'
                    foreach ($label in $State.FeatureLabels.Values) {
                        Assert-SelectionTextFits $label ($Context + ' ' + $operation + ' ' + $featureState + ' 逐项状态') -SingleLine
                        if ($featureState -eq 'Succeeded') {
                            $expected = '✅ 安装成功'
                            if ($operation -eq 'Uninstall') { $expected = '已完成' }
                            Assert-Selection ($label.Text -ceq $expected -and $label.ForeColor.ToArgb() -eq [Drawing.Color]::ForestGreen.ToArgb()) ($Context + ' 成功文案和绿色按安装/卸载分别显示')
                        }
                    }
                }
            }
        } finally {
            $State.Operation = $originalOperation
            $State.FeatureStates = $originalStates
            foreach ($key in $originalLabels.Keys) { $State.FeatureLabels[$key].Text = $originalLabels[$key] }
        }
        foreach ($message in @(
            ('已选 {0} / {0} 项；关闭或取消窗口不执行操作。' -f $State.Checks.Count),
            ('安装 / 更新中；已处理 {0} / {0} 项（100.0%，按完成项计数）；安装用时 100:59:59' -f $State.Checks.Count),
            ('全部处理完成；可选择复制日志，或关闭面板。退出码：0。已处理 {0} / {0} 项（100.0%，按完成项计数）；安装总用时 100:59:59' -f $State.Checks.Count),
            ('卸载中；已处理 {0} / {0} 项（100.0%，按完成项计数）；卸载用时 100:59:59' -f $State.Checks.Count),
            ('全部处理完成；可选择复制日志，或关闭面板。退出码：0。已处理 {0} / {0} 项（100.0%，按完成项计数）；卸载总用时 100:59:59' -f $State.Checks.Count),
            '操作正在执行，请等待事务完成后关闭；下方日志可随时复制。',
            '安装 / 更新已完成：所有选中功能成功。日志和结果保留在本面板。',
            '执行失败：成功的功能已保留，未执行的功能未更改；请查看下方日志。'
        )) {
            Set-JobsFeatureStatusText -State $State -Text $message
            Assert-SelectionTextFits $State.StatusLabel ($Context + ' 操作进度与结果')
            Assert-Selection ($State.StatusLabel.Bottom -le $State.Progress.Top) ($Context + ' 完整进度说明不覆盖进度条')
            Assert-Selection ($State.Progress.Bottom -le $State.ConfirmButton.Top) ($Context + ' 进度条不覆盖操作按钮')
            Assert-Selection ($State.Footer.ClientRectangle.Contains($State.ConfirmButton.Bounds)) ($Context + ' 变长说明后操作按钮仍完整位于底栏')
            $footerButtons = @($State.SelectAllButton, $State.ClearButton, $State.ConfirmButton, $State.CancelButton)
            foreach ($button in $footerButtons) {
                Assert-SelectionTextFits $button ($Context + ' 全局操作按钮') -SingleLine
                Assert-Selection ($State.Footer.ClientRectangle.Contains($button.Bounds)) ($Context + ' 全局操作按钮完整位于底栏：' + $button.Text)
                Assert-Selection ($State.Progress.Bottom -le $button.Top) ($Context + ' 全局操作按钮不覆盖进度条：' + $button.Text)
            }
            for ($left = 0; $left -lt $footerButtons.Count; $left++) {
                for ($right = $left + 1; $right -lt $footerButtons.Count; $right++) {
                    Assert-Selection (-not $footerButtons[$left].Bounds.IntersectsWith($footerButtons[$right].Bounds)) ($Context + ' 全局操作按钮不重叠')
                }
            }
        }
    }

    $state = New-SelectionTestState -Items $packages -Selected @($packages[1].Id) -Mode Install
    try {
        Assert-Selection (@($state.Checks).Count -eq $packages.Count) '面板为每项功能提供独立复选框'
        Assert-SelectionTextLayout $state '全部功能'

        Assert-Selection ($state.LogSplit.Orientation -eq [Windows.Forms.Orientation]::Horizontal -and -not $state.LogSplit.IsSplitterFixed) '日志区使用允许上下拖动的原生水平分隔条'
        $initialDistance = $state.LogSplit.SplitterDistance
        $state.LogSplit.SplitterDistance = $state.LogSplit.Panel1MinSize
        $state.Form.PerformLayout()
        Assert-Selection ($state.LogSplit.Panel2.Height -ge $state.LogSplit.Panel2MinSize -and $state.ContentPanel.Height -ge $state.Layout.RowHeight) '日志放大后仍保留功能行与日志最小高度'
        $footerBounds = Get-SelectionBoundsInForm $state.Footer $state.Form
        $logBounds = Get-SelectionBoundsInForm $state.LogView $state.Form
        Assert-Selection (-not $footerBounds.IntersectsWith($logBounds)) '放大日志不会遮住操作按钮'
        $state.LogSplit.SplitterDistance = $state.LogSplit.Height - $state.LogSplit.SplitterWidth - $state.LogSplit.Panel2MinSize
        $state.Form.PerformLayout()
        Assert-Selection ($state.LogView.Height -ge [int](60 * $state.Scale)) '缩小日志后仍保留可读正文'
        $state.LogSplit.SplitterDistance = $initialDistance
        $state.Form.PerformLayout()
        Assert-Selection ([object]::ReferenceEquals($state.LogView.ContextMenuStrip, $state.LogMenu) -and $state.LogMenu.Items.Contains($state.SelectLogItem)) '日志右键菜单包含全选'
        Assert-Selection ($state.LogView.ReadOnly -and $state.LogView.ShortcutsEnabled -and $state.SelectLogItem.ShortcutKeys -eq ([Windows.Forms.Keys]::Control -bor [Windows.Forms.Keys]::A)) '只读日志保留全选与复制快捷键'
        $flags = [Reflection.BindingFlags]::Instance -bor [Reflection.BindingFlags]::NonPublic
        $savedLog = $state.LogView.Text
        try {
            $state.LogView.Text = "第一行`r`n第二行"
            $state.LogView.Select(2, 0)
            Invoke-SelectionTestClick $state.SelectLogItem
            Assert-Selection ($state.LogView.SelectionStart -eq 0 -and $state.LogView.SelectionLength -eq $state.LogView.TextLength) '右键全选实际选中全部日志文本'
            $state.LogView.Select(1, 0)
            # 5.1 数组子表达式会保留 PSObject 包装；反射参数直接传 CLR 对象。
            $key = New-Object Windows.Forms.KeyEventArgs(([Windows.Forms.Keys]::Control -bor [Windows.Forms.Keys]::A))
            [void]$state.LogView.GetType().GetMethod('OnKeyDown', $flags).Invoke($state.LogView, (,$key.PSObject.BaseObject))
            Assert-Selection ($state.LogView.SelectionLength -eq $state.LogView.TextLength -and $key.SuppressKeyPress) 'Ctrl+A 由日志控件处理并全选'
            $originalSelection = $state.LogView.SelectedText
            Add-JobsManagementLog $state '后台继续输出'
            Assert-Selection ($state.LogView.SelectedText -ceq $originalSelection) '后台追加日志不破坏用户已全选的文本'
            $opening = New-Object ComponentModel.CancelEventArgs
            [void]$state.LogMenu.GetType().GetMethod('OnOpening', $flags).Invoke($state.LogMenu, (,$opening.PSObject.BaseObject))
            Assert-Selection ($state.CopySelectionItem.Enabled -and $state.SelectLogItem.Enabled) '有文本选择时复制与全选菜单可用'
            $state.LogView.Clear()
            [void]$state.LogMenu.GetType().GetMethod('OnOpening', $flags).Invoke($state.LogMenu, (,$opening.PSObject.BaseObject))
            Assert-Selection (-not $state.CopySelectionItem.Enabled -and -not $state.SelectLogItem.Enabled) '空日志菜单禁用复制与全选'
        } finally { $state.LogView.Text = $savedLog }

        Assert-Selection (-not $state.Form.AutoScroll -and $state.ContentPanel.AutoScroll -and -not $state.Form.MaximizeBox) '只滚动分组内容，操作区固定可见'
        Assert-Selection ($state.Form.FormBorderStyle -in @([Windows.Forms.FormBorderStyle]::FixedDialog, [Windows.Forms.FormBorderStyle]::FixedSingle)) '窗口按内容定尺寸并保持固定边框'
        for ($i = 0; $i -lt $packages.Count; $i++) {
            Assert-Selection ($state.Checks[$i].Text -eq $packages[$i].Label) ('功能标题不混入长说明：' + $packages[$i].Id)
            Assert-Selection ($state.ToolTip.GetToolTip($state.Checks[$i]).Contains($packages[$i].Description)) ('悬停保留功能说明：' + $packages[$i].Id)
            Assert-Selection ($state.Checks[$i].Bottom -le $state.Checks[$i].Parent.Height -and $state.Checks[$i].Right -le $state.Checks[$i].Parent.Width) ('每项功能均在可滚动分组内完整显示：' + $packages[$i].Id)
        }
        Assert-Selection ($state.ConfirmButton.Enabled -and [object]::ReferenceEquals($state.Form.AcceptButton, $state.ConfirmButton)) '已有选择时安装按钮和回车均可确认'
        Invoke-SelectionTestClick $state.SelectAllButton
        Assert-Selection (@($state.Checks | Where-Object { $_.Checked }).Count -eq $packages.Count) '全选勾选所有功能'
        Assert-Selection ($null -eq $state.Form.Tag -and -not $state.Form.IsDisposed) '全选不会提前返回安装结果或关闭窗口'
        Invoke-SelectionTestClick $state.ClearButton
        Assert-Selection (@($state.Checks | Where-Object { $_.Checked }).Count -eq 0) '全不选清空所有功能'
        Assert-Selection (-not $state.ConfirmButton.Enabled -and $null -eq $state.Form.AcceptButton) '空选同时禁用安装和默认回车按钮'
        Invoke-SelectionTestClick $state.ConfirmButton
        Assert-Selection ($null -eq $state.Form.Tag -and -not $state.Form.IsDisposed) '空选即使触发确认事件也不会执行或关闭窗口'
        $state.Checks[2].Checked = $true
        Assert-Selection ($state.ConfirmButton.Enabled -and [object]::ReferenceEquals($state.Form.AcceptButton, $state.ConfirmButton)) '重新勾选立即恢复按钮和回车确认'
        Invoke-SelectionTestClick $state.ConfirmButton
        Assert-Selection ($null -ne $state.Form.Tag -and @($state.Form.Tag.Features).Count -eq 1 -and $state.Form.Tag.Features[0] -eq $packages[2].Id) '只有明确确认才返回当前选择'
        Assert-Selection ($state.Form.DialogResult -eq [Windows.Forms.DialogResult]::OK) '确认结果为 OK'
    } finally {
        $state.Form.Dispose()
        $state.ToolTip.Dispose()
        $state.Font.Dispose()
    }

    $selectableFeatures = @(Get-JobsSelectableFeatures -Packages $packages)
    $state = New-SelectionTestState -Items $selectableFeatures -Selected @() -Mode Manage
    try {
        Assert-Selection (@($state.Checks).Count -eq $selectableFeatures.Count) '真实可选叶子清单含全部 Flutter 子功能，不能只检查安装包数量'
        Assert-SelectionTextLayout $state ('真实可选叶子 ' + $selectableFeatures.Count)
    } finally {
        $state.LogView.Font.Dispose()
        $state.Form.Dispose()
        $state.ToolTip.Dispose()
        $state.Font.Dispose()
    }

    $state = New-SelectionTestState -Items $fixtures -Selected @() -Mode Uninstall
    try {
        Assert-Selection (-not $state.ConfirmButton.Enabled -and $null -eq $state.Form.AcceptButton) '卸载模式也禁止空选和回车绕过'
        $state.Checks[0].Checked = $true
        Assert-Selection $state.ConfirmButton.Enabled '卸载勾选后才允许确认'
        Assert-Selection ([object]::ReferenceEquals($state.Form.CancelButton, $state.CancelButton)) 'Escape 关联取消按钮'
        Invoke-SelectionTestClick $state.CancelButton
        Assert-Selection ($null -eq $state.Form.Tag -and $state.Form.DialogResult -eq [Windows.Forms.DialogResult]::Cancel) '取消不返回功能或操作结果'
    } finally {
        $state.Form.Dispose()
        $state.ToolTip.Dispose()
        $state.Font.Dispose()
    }

    $state = New-SelectionTestState -Items $fixtures -Selected @() -Mode Manage -Installed @('alpha', 'beta')
    try {
        Assert-Selection ($state.Operation -eq 'Install' -and -not $state.ConfirmButton.Enabled) '管理面板初始空选，不隐式安装'
        $state.Checks[2].Checked = $true
        $state.OperationBox.SelectedIndex = 1
        Assert-Selection ($state.Operation -eq 'Uninstall' -and -not $state.ConfirmButton.Enabled) '切换卸载清除上一操作的勾选'
        Assert-Selection ($state.Checks[0].Enabled -and -not $state.Checks[2].Enabled) '卸载时只有已安装功能可选'
        Invoke-SelectionTestClick $state.SelectAllButton
        Assert-Selection (@($state.Checks | Where-Object { $_.Checked }).Count -eq 2) '卸载全选不会勾选未安装项'
        $state.OperationBox.SelectedIndex = 0
        Assert-Selection (@($state.Checks | Where-Object { $_.Checked }).Count -eq 0 -and $state.Checks[2].Enabled) '切回安装清空选择并恢复全部可选功能'
        $state.Checks[2].Checked = $true
        Invoke-SelectionTestClick $state.ConfirmButton
        Assert-Selection ($state.Form.Tag.Mode -eq 'Install' -and @($state.Form.Tag.Features).Count -eq 1 -and $state.Form.Tag.Features[0] -eq 'gamma') '同一面板返回明确操作和实际勾选对象'
    } finally {
        $state.Form.Dispose()
        $state.ToolTip.Dispose()
        $state.Font.Dispose()
    }

    $longFixtures = @(
        [pscustomobject]@{ Id = 'long-title'; Label = '安装 / 切换 Flutter@OpenHarmony SDK，并检查当前工程中全部已安装与正在安装的第三方依赖'; Description = '长标题换行验证'; PackagePath = 'long-title'; Group = '长标题与多位数计数' },
        [pscustomobject]@{ Id = 'normal-title'; Label = '普通功能'; Description = '普通功能说明'; PackagePath = 'normal-title'; Group = '长标题与多位数计数' }
    )
    foreach ($scopeSize in @(1, 2, 3)) {
        $items = @($fixtures | Select-Object -First $scopeSize)
        if ($scopeSize -eq 2) { $items = $longFixtures }
        $state = New-SelectionTestState -Items $items -Selected @() -Mode Manage
        try {
            Assert-SelectionTextLayout $state ('单功能范围 ' + $scopeSize)
            $state.OperationBox.SelectedIndex = 1
            Assert-SelectionTextLayout $state ('卸载范围 ' + $scopeSize)
        } finally {
            $state.LogView.Font.Dispose()
            $state.Form.Dispose()
            $state.ToolTip.Dispose()
            $state.Font.Dispose()
        }
    }

    $state = New-SelectionTestState -Items $fixtures -Selected @() -Mode Configure
    try {
        Assert-Selection ($state.ConfirmButton.Enabled -and [object]::ReferenceEquals($state.Form.AcceptButton, $state.ConfirmButton)) '配置模式可以明确保存空选'
        Invoke-SelectionTestClick $state.ConfirmButton
        Assert-Selection ($null -ne $state.Form.Tag -and @($state.Form.Tag.Features).Count -eq 0) '配置空选与取消保持不同结果'
    } finally {
        $state.Form.Dispose()
        $state.ToolTip.Dispose()
        $state.Font.Dispose()
    }
} else {
    Write-Host 'SKIP: WinForms 控件交互需要 Windows；布局、入口和操作计划已跨平台验证。'
}

Write-Host ('PASS: SelectionPanel.Tests.ps1 (' + $script:Assertions + ' assertions)')

# Installer.psm1 | WindowsOS@Extension 组合选择面板
# Created by Jobs on 2026年10月18日，星期日.
# 面板内后台执行安装事务，实时显示逐项状态和可复制日志；预览、取消不部署。
Set-StrictMode -Version 2.0

function Get-JobsFeatureSelectionLayout {
    param(
        [ValidateRange(1, 1000)][int]$ItemCount,
        [int]$WorkingWidth,
        [int]$WorkingHeight,
        [ValidateRange(1, 1000)][int]$RowHeight = 34,
        [ValidateRange(0.5, 4.0)][double]$Scale = 1
    )
    $maxHeight = $WorkingHeight - [int][Math]::Ceiling(80 * $Scale)
    $maxExpandedHeight = $WorkingHeight - [int][Math]::Ceiling(44 * $Scale)
    $columns = 0
    $width = 0
    $rows = 0
    $height = 0
    $header = 0
    $footer = 0
    foreach ($candidateColumns in @(1, 2, 3)) {
        $candidateHeader = [int][Math]::Ceiling(118 * $Scale)
        $candidateFooter = [int][Math]::Ceiling(104 * $Scale)
        $candidateRows = [int][Math]::Ceiling($ItemCount / [double]$candidateColumns)
        $candidateHeight = $candidateRows * $RowHeight + $candidateHeader + $candidateFooter
        $limit = $maxHeight
        if ($candidateColumns -gt 1 -and $candidateHeight -gt $maxHeight) {
            $candidateHeader = [int][Math]::Ceiling(96 * $Scale)
            $candidateFooter = [int][Math]::Ceiling(92 * $Scale)
            $candidateHeight = $candidateRows * $RowHeight + $candidateHeader + $candidateFooter
            if ($candidateHeight -gt $maxHeight) { $limit = $maxExpandedHeight }
        }
        $preferredWidth = 680
        $minimumWidth = 500
        if ($candidateColumns -eq 2) { $preferredWidth = 1020; $minimumWidth = 720 }
        if ($candidateColumns -eq 3) { $preferredWidth = 1320; $minimumWidth = 1080 }
        $candidateWidth = [int][Math]::Min([Math]::Ceiling($preferredWidth * $Scale), $WorkingWidth - [Math]::Ceiling(48 * $Scale))
        if ($candidateHeight -gt $limit -or $candidateWidth -lt $minimumWidth * $Scale) { continue }
        $columns = $candidateColumns
        $rows = $candidateRows
        $height = $candidateHeight
        $width = $candidateWidth
        $header = $candidateHeader
        $footer = $candidateFooter
        break
    }
    if ($columns -eq 0) {
        if ($WorkingWidth -lt 500 * $Scale -or $WorkingHeight -lt 360 * $Scale) {
            throw '当前桌面工作区过小，无法显示固定操作按钮；请降低显示缩放或提高屏幕分辨率后重试。'
        }
        $columns = 1
        if ($WorkingWidth -ge 900 * $Scale) { $columns = 2 }
        $rows = [int][Math]::Ceiling($ItemCount / [double]$columns)
        $width = [int][Math]::Min(1020 * $Scale, $WorkingWidth - 48 * $Scale)
        $height = $maxHeight
        $header = [int][Math]::Ceiling(118 * $Scale)
        $footer = [int][Math]::Ceiling(104 * $Scale)
    }
    return [pscustomobject]@{
        Columns = $columns; Rows = $rows; ClientWidth = $width; ClientHeight = $height
        RowHeight = $RowHeight; HeaderHeight = $header; FooterHeight = $footer
    }
}

function Get-JobsFeatureContentLayout {
    param(
        [int]$WorkingWidth,
        [ValidateRange(1, 3)][int]$PreferredColumns = 1,
        [int]$MinimumPanelWidth = 500,
        [int]$MinimumCheckWidth = 120,
        [int]$StatusWidth = 120,
        [int]$GroupControlsWidth = 260,
        [ValidateRange(0.5, 4.0)][double]$Scale = 1
    )
    $padding = [int][Math]::Ceiling(20 * $Scale)
    $gap = [int][Math]::Ceiling(8 * $Scale)
    $scrollbar = [int][Math]::Ceiling(24 * $Scale)
    $rowPadding = [int][Math]::Ceiling(28 * $Scale)
    $availableWidth = $WorkingWidth - [int][Math]::Ceiling(48 * $Scale)
    $requiredPanel = [Math]::Max($MinimumPanelWidth, [Math]::Max($GroupControlsWidth, $MinimumCheckWidth + $StatusWidth + $rowPadding))
    for ($columns = $PreferredColumns; $columns -ge 1; $columns--) {
        $preferredWidth = @(0, 680, 1020, 1320)[$columns] * $Scale
        $requiredWidth = $columns * ($requiredPanel + $gap) + 2 * $padding + $scrollbar
        $width = [int][Math]::Min($availableWidth, [Math]::Max($preferredWidth, $requiredWidth))
        $panelWidth = [int][Math]::Floor(($width - 2 * $padding - $scrollbar) / [double]$columns) - $gap
        if ($panelWidth -ge $requiredPanel) {
            return [pscustomobject]@{ Columns = $columns; ClientWidth = $width; PanelWidth = $panelWidth; CheckWidth = $panelWidth - $StatusWidth - $rowPadding; StatusWidth = $StatusWidth; Wrapped = $false }
        }
    }
    $panelWidth = $availableWidth - 2 * $padding - $scrollbar - $gap
    if ($panelWidth -lt [Math]::Max($GroupControlsWidth, $MinimumCheckWidth + $StatusWidth + $rowPadding)) {
        throw '当前工作区太窄，无法完整显示选择按钮、计数和状态；请降低缩放或提高分辨率。'
    }
    return [pscustomobject]@{ Columns = 1; ClientWidth = $availableWidth; PanelWidth = $panelWidth; CheckWidth = $panelWidth - $StatusWidth - $rowPadding; StatusWidth = $StatusWidth; Wrapped = $true }
}

# 留出固定操作按钮、至少一行功能和可读日志，再约束拖动范围。
function Get-JobsManagementLogLayout {
    param(
        [int]$Height,
        [int]$FooterHeight,
        [int]$ToolbarHeight,
        [int]$RowHeight,
        [int]$SplitterWidth,
        [int]$LogHeight,
        [ValidateRange(0.5, 4.0)][double]$Scale = 1
    )
    $upperMinimum = $FooterHeight + $RowHeight
    $lowerMinimum = $ToolbarHeight + [int][Math]::Ceiling(60 * $Scale)
    $available = $Height - $SplitterWidth
    if ($upperMinimum + $lowerMinimum -gt $available) {
        throw '当前窗口高度不足以同时显示操作按钮和日志，请提高分辨率或降低缩放。'
    }
    $lowerHeight = [int][Math]::Min($available - $upperMinimum, [Math]::Max($lowerMinimum, $LogHeight))
    return [pscustomobject]@{
        UpperMinimum = $upperMinimum; LowerMinimum = $lowerMinimum
        Distance = $available - $lowerHeight; LogHeight = $lowerHeight
    }
}

function Set-JobsManagementLogLayout {
    param($State)
    if ($null -eq $State.PSObject.Properties['LogSplit']) { return }
    $split = $State.LogSplit
    $layout = Get-JobsManagementLogLayout -Height $split.ClientSize.Height -FooterHeight $State.Footer.Height -ToolbarHeight $State.LogToolbar.Height -RowHeight $State.Layout.RowHeight -SplitterWidth $split.SplitterWidth -LogHeight $split.Panel2.Height -Scale $State.Scale
    $split.SuspendLayout()
    try {
        $split.Panel1MinSize = 0
        $split.Panel2MinSize = 0
        $split.SplitterDistance = $layout.Distance
        $split.Panel1MinSize = $layout.UpperMinimum
        $split.Panel2MinSize = $layout.LowerMinimum
    } finally { $split.ResumeLayout() }
}

function Measure-JobsFeatureText {
    param([string]$Text, [object]$Font, [int]$Width = 0)
    $flags = [Windows.Forms.TextFormatFlags]::NoPrefix -bor [Windows.Forms.TextFormatFlags]::TextBoxControl
    if ($Width -gt 0) {
        $flags = $flags -bor [Windows.Forms.TextFormatFlags]::WordBreak
        $size = New-Object Drawing.Size($Width, [int]::MaxValue)
    } else {
        $flags = $flags -bor [Windows.Forms.TextFormatFlags]::SingleLine
        $size = New-Object Drawing.Size([int]::MaxValue, [int]::MaxValue)
    }
    return [Windows.Forms.TextRenderer]::MeasureText($Text, $Font, $size, $flags)
}

# 动态状态按当前宽度换行，操作按钮始终位于完整说明下方。
function Set-JobsFeatureStatusText {
    param([object]$State, [string]$Text)
    $State.StatusLabel.Text = $Text
    if ($null -eq $State.PSObject.Properties['Padding']) { return }
    $padding = [int]$State.Padding
    $scale = [double]$State.Scale
    $width = $State.Form.ClientSize.Width - 2 * $padding
    $preferred = $State.StatusLabel.GetPreferredSize((New-Object Drawing.Size($width, 0)))
    $height = [int][Math]::Max(26 * $scale, $preferred.Height)
    $State.StatusLabel.SetBounds($padding, ([int](10 * $scale)), $width, $height)
    $State.Progress.SetBounds($padding, ($State.StatusLabel.Bottom + [int](5 * $scale)), $width, ([int](6 * $scale)))
    $buttonsTop = $State.Progress.Bottom + [int](6 * $scale)
    $gap = [int](10 * $scale)
    $buttons = @($State.SelectAllButton, $State.ClearButton, $State.ConfirmButton, $State.CancelButton)
    foreach ($button in $buttons) { $button.Top = $buttonsTop }
    $State.SelectAllButton.Left = $padding
    $State.ClearButton.Left = $State.SelectAllButton.Right + $gap
    $State.CancelButton.Left = $State.Form.ClientSize.Width - $padding - $State.CancelButton.Width
    $State.ConfirmButton.Left = $State.CancelButton.Left - $gap - $State.ConfirmButton.Width
    if ($State.ClearButton.Right + $gap -gt $State.ConfirmButton.Left) {
        $State.ConfirmButton.Top = $State.ClearButton.Bottom + $gap
        $State.CancelButton.Top = $State.ConfirmButton.Top
    }
    $State.Footer.Height = $State.CancelButton.Bottom + [int](20 * $scale)
    $State.Layout.FooterHeight = $State.Footer.Height
    Set-JobsManagementLogLayout $State
}

# 完成项包含成功与失败；未执行项不计进度，避免把异常结束显示为全部完成。
function Get-JobsManagementProgress {
    param($State)
    $finished = @($State.FeatureStates.Values | Where-Object { $_ -eq 'Succeeded' -or $_ -eq 'Failed' }).Count
    $total = $State.FeatureStates.Count
    $percent = 0.0
    if ($total -gt 0) { $percent = 100.0 * $finished / $total }
    return [pscustomobject]@{ Finished = $finished; Total = $total; Percent = $percent.ToString('F1', [Globalization.CultureInfo]::InvariantCulture) }
}

# 小时累计不按天回卷，计时来源由 Stopwatch 保持单调。
function Format-JobsManagementElapsedTime {
    param([TimeSpan]$Elapsed)
    $seconds = [long][Math]::Floor([Math]::Max(0, $Elapsed.TotalSeconds))
    return '{0:00}:{1:00}:{2:00}' -f [long][Math]::Floor($seconds / 3600.0), [long][Math]::Floor(($seconds % 3600) / 60.0), ($seconds % 60)
}

# 安装和卸载各自保有计时状态，切换操作只选择对应时钟。
function Get-JobsManagementClock {
    param($State)
    if ($State.Operation -eq 'Uninstall') { return $State.RunClocks.Uninstall }
    return $State.RunClocks.Install
}

# 无新输出时也刷新耗时，只在显示值变化时重排底栏。
function Update-JobsManagementProgress {
    param($State)
    $progress = Get-JobsManagementProgress $State
    $State.Progress.Value = [Math]::Min($progress.Finished, $State.Progress.Maximum)
    $action = '安装 / 更新'
    $clockLabel = '安装用时'
    if ($State.Operation -eq 'Uninstall') { $action = '卸载'; $clockLabel = '卸载用时' }
    $clock = Get-JobsManagementClock $State
    $text = '{0}中；已处理 {1} / {2} 项（{3}%，按完成项计数）；{4} {5}' -f $action, $progress.Finished, $progress.Total, $progress.Percent, $clockLabel, (Format-JobsManagementElapsedTime $clock.Elapsed)
    if ($State.StatusLabel.Text -cne $text) { Set-JobsFeatureStatusText $State $text }
}

function New-JobsFeatureSelectionForm {
    param(
        [object[]]$Packages,
        [string[]]$Selected,
        [string[]]$Installed = @(),
        [ValidateSet('Manage', 'Install', 'Configure', 'Uninstall')][string]$Mode = 'Manage',
        [switch]$Preview,
        [scriptblock]$BuildPlan,
        [string]$WorkerPath
    )
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $features = @($Packages)
    if ($features.Count -eq 0) { throw '没有可供选择的功能包。' }
    $form = New-Object System.Windows.Forms.Form
    $font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
    $toolTip = New-Object System.Windows.Forms.ToolTip
    try {
        $form.Font = $font
        # 所有尺寸使用同一桌面坐标系，避免高 DPI 下窗口再次自动缩放。
        $form.AutoScaleMode = 'None'
        $area = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position).WorkingArea
        $form.StartPosition = 'Manual'
        $form.Location = $area.Location
        $graphics = $form.CreateGraphics()
        try { $scale = $graphics.DpiY / 96.0 } finally { $graphics.Dispose() }
        $rowHeight = [int][Math]::Ceiling(34 * $scale)
        $layout = Get-JobsFeatureSelectionLayout -ItemCount $features.Count -WorkingWidth $area.Width -WorkingHeight $area.Height -RowHeight $rowHeight -Scale $scale
        $form.Text = 'Jobs Windows · 安装资源管理器扩展'
        $action = '安装'
        $description = '勾选需要安装的子功能；已启用的兄弟动作与其它未选功能保留。'
        if ($Mode -eq 'Manage') {
            $form.Text = 'Jobs Windows · 管理资源管理器扩展'
            $action = '安装 / 更新'
            $description = '选择操作并勾选一个或多个功能；未选功能保留。卸载只处理已安装项。'
        } elseif ($Mode -eq 'Configure') {
            $form.Text = 'Jobs Windows · 配置资源管理器扩展'
            $action = '保存配置'
            $description = '勾选安装，取消勾选卸载；全不选后保存将关闭全部已安装功能。'
        } elseif ($Mode -eq 'Uninstall') {
            $form.Text = 'Jobs Windows · 卸载资源管理器扩展'
            $action = '卸载'
            $description = '只卸载勾选的已安装功能；未勾选项、日志、备份和工具依赖保留。'
        }
        if ($Preview) {
            $form.Text += '（仅预览）'
            $action = '返回选择'
            $description = '仅预览功能选择；确认后在底部显示选择，不安装、不卸载、不写入状态或注册表。'
        }
        $allButtonWidth = [int][Math]::Max(74 * $scale, (Measure-JobsFeatureText '全选' $font).Width + 16 * $scale)
        $noneButtonWidth = [int][Math]::Max(80 * $scale, (Measure-JobsFeatureText '全不选' $font).Width + 16 * $scale)
        $counterWidth = 0
        $statusWidth = 0
        $titleWidth = 0
        $groupTitleWidth = 0
        $groupTotals = @{}
        foreach ($feature in $features) {
            $groupName = '其它右键功能'
            if ($null -ne $feature.PSObject.Properties['Group']) { $groupName = [string]$feature.Group }
            if (-not $groupTotals.ContainsKey($groupName)) { $groupTotals[$groupName] = 0 }
            $groupTotals[$groupName]++
            $titleWidth = [Math]::Max($titleWidth, (Measure-JobsFeatureText $feature.Label $font).Width + 26 * $scale)
            $groupTitleWidth = [Math]::Max($groupTitleWidth, (Measure-JobsFeatureText $groupName $font).Width + 20 * $scale)
        }
        foreach ($total in $groupTotals.Values) {
            foreach ($count in 0..$total) { $counterWidth = [Math]::Max($counterWidth, (Measure-JobsFeatureText ('已选 {0} / {1}' -f $count, $total) $font).Width + 4 * $scale) }
        }
        foreach ($text in @('未安装', '已安装', '等待中', '正在安装 / 更新…', '正在卸载…', '✅ 安装成功', '已完成', '失败，见日志', '未执行')) {
            $statusWidth = [Math]::Max($statusWidth, (Measure-JobsFeatureText $text $font).Width + 10 * $scale)
        }
        $statusWidth = [int][Math]::Max(90 * $scale, $statusWidth)
        $groupControlsWidth = [int][Math]::Ceiling($allButtonWidth + $noneButtonWidth + $counterWidth + 32 * $scale)
        $minimumPanelWidth = [int][Math]::Ceiling([Math]::Max($groupTitleWidth, [Math]::Max($groupControlsWidth, $titleWidth + $statusWidth + 28 * $scale)))
        $contentLayout = Get-JobsFeatureContentLayout -WorkingWidth $area.Width -PreferredColumns $layout.Columns -MinimumPanelWidth $minimumPanelWidth -MinimumCheckWidth ([int](120 * $scale)) -StatusWidth $statusWidth -GroupControlsWidth $groupControlsWidth -Scale $scale
        $layout.Columns = $contentLayout.Columns
        $layout.Rows = [int][Math]::Ceiling($features.Count / [double]$layout.Columns)
        $layout.ClientWidth = $contentLayout.ClientWidth
        $layout.ClientHeight = [int][Math]::Min($area.Height - 60 * $scale, [Math]::Max($layout.ClientHeight, 560 * $scale))
        if ($layout.ClientHeight -lt 400 * $scale) { throw '当前工作区太矮，无法同时显示选择、操作按钮和实时日志；请提高分辨率或降低缩放。' }
        $form.ClientSize = New-Object System.Drawing.Size($layout.ClientWidth, $layout.ClientHeight)
        $form.FormBorderStyle = 'FixedDialog'
        $form.MaximizeBox = $false
        $form.MinimizeBox = $false
        $form.StartPosition = 'Manual'
        $form.Location = New-Object System.Drawing.Point(
            ([int]($area.Left + ($area.Width - $form.Width) / 2)),
            ([int]($area.Top + ($area.Height - $form.Height) / 2)))
        $padding = [int][Math]::Ceiling(20 * $scale)
        $header = New-Object System.Windows.Forms.Panel
        $header.Dock = 'Top'
        $headerLabel = New-Object System.Windows.Forms.Label
        $headerLabel.Font = $font
        $headerLabel.AutoEllipsis = $false
        $headerLabel.Text = "资源管理器右键扩展 · $action`r`n$description`r`n悬停查看功能说明；Windows 11：右键 → 显示更多选项。"

        if ($Mode -eq 'Manage') {
            $headerLabel.Text = "资源管理器扩展 · 管理`r`n勾选功能后确认；未选项保留。悬停可查看当前安装状态。"
        }
        $headerTextWidth = $layout.ClientWidth - 2 * $padding
        $headerTextHeight = $headerLabel.GetPreferredSize((New-Object Drawing.Size($headerTextWidth, 0))).Height
        $headerLabel.SetBounds($padding, $padding, $headerTextWidth, $headerTextHeight)
        $header.Controls.Add($headerLabel)
        $header.Height = $headerLabel.Bottom + [int](14 * $scale)
        $operationBox = $null
        if ($Mode -eq 'Manage') {
            $operationBox = New-Object System.Windows.Forms.ComboBox
            $operationBox.Font = $font
            $operationBox.DropDownStyle = 'DropDownList'
            $operationBox.SetBounds($padding, ($headerLabel.Bottom + [int](8 * $scale)), ([int](230 * $scale)), ([int](28 * $scale)))
            [void]$operationBox.Items.AddRange(@('安装 / 更新所选功能', '卸载所选功能'))
            $operationBox.SelectedIndex = 0
            $header.Controls.Add($operationBox)
            $header.Height = $operationBox.Bottom + [int](14 * $scale)
        }
        $layout.HeaderHeight = $header.Height
        $grid = New-Object System.Windows.Forms.FlowLayoutPanel
        $grid.Dock = 'Fill'
        $grid.Padding = New-Object System.Windows.Forms.Padding($padding, 0, $padding, 0)
        $grid.AutoScroll = $true
        $grid.WrapContents = $true
        $grid.FlowDirection = 'LeftToRight'
        $groupStates = @()
        $groupNames = @()
        foreach ($feature in $features) {
            $groupName = '其它右键功能'
            if ($null -ne $feature.PSObject.Properties['Group']) { $groupName = [string]$feature.Group }
            if ($groupName -cnotin $groupNames) { $groupNames += $groupName }
        }
        $panelWidth = $contentLayout.PanelWidth
        $groupForId = @{}
        foreach ($groupName in $groupNames) {
            $items = @($features | Where-Object {
                $name = '其它右键功能'
                if ($null -ne $_.PSObject.Properties['Group']) { $name = [string]$_.Group }
                $name -ceq $groupName
            })
            $box = New-Object System.Windows.Forms.GroupBox
            $box.Font = $font
            $box.Text = $groupName
            $box.Size = New-Object System.Drawing.Size($panelWidth, ([int](76 * $scale) + $items.Count * $rowHeight))
            $box.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 10)
            $all = New-Object System.Windows.Forms.Button
            $all.Font = $font
            $all.Text = '全选'
            $all.SetBounds(([int](8 * $scale)), ([int](24 * $scale)), $allButtonWidth, ([int](30 * $scale)))
            $none = New-Object System.Windows.Forms.Button
            $none.Font = $font
            $none.Text = '全不选'
            $none.SetBounds(($all.Right + [int](6 * $scale)), ([int](24 * $scale)), $noneButtonWidth, ([int](30 * $scale)))
            $counter = New-Object System.Windows.Forms.Label
            $counter.Font = $font
            $counter.AutoEllipsis = $false
            $counterHeight = [int][Math]::Max(24 * $scale, (Measure-JobsFeatureText ('已选 {0} / {0}' -f $items.Count) $font).Height)
            $counter.SetBounds(($none.Right + [int](6 * $scale)), ([int](29 * $scale)), $counterWidth, $counterHeight)
            $box.Controls.AddRange(@($all, $none, $counter))
            $group = [pscustomobject]@{ Name = $groupName; Box = $box; Checks = @(); All = $all; None = $none; Counter = $counter; RowHeight = $rowHeight }
            foreach ($item in $items) { $groupForId[$item.Id] = $group }
            $groupStates += $group
            $grid.Controls.Add($box)
        }
        $checks = @()
        $featureLabels = @{}
        for ($index = 0; $index -lt $features.Count; $index++) {
            $feature = $features[$index]
            $check = New-Object System.Windows.Forms.CheckBox
            $check.Font = $font
            $check.Text = $feature.Label
            $check.Tag = $feature.Id
            $check.AutoEllipsis = $false
            $check.Margin = New-Object System.Windows.Forms.Padding(4, 0, 4, 0)
            $check.Checked = $feature.Id -in $Selected
            $installationStatus = '未安装'
            if ($feature.Id -in $Installed) { $installationStatus = '已安装' }
            $toolTip.SetToolTip($check, ($feature.Label + "`r`n" + $installationStatus + "`r`n" + $feature.Description))
            $group = $groupForId[$feature.Id]
            $check.SetBounds(([int](8 * $scale)), 0, $contentLayout.CheckWidth, $rowHeight)
            $featureStatus = New-Object System.Windows.Forms.LinkLabel
            $featureStatus.Font = $font
            $featureStatus.Text = $installationStatus
            $featureStatus.Tag = [string]$feature.Id
            $featureStatus.LinkArea = New-Object Windows.Forms.LinkArea(0, 0)
            $featureStatus.LinkColor = [Drawing.Color]::Firebrick
            $featureStatus.ActiveLinkColor = [Drawing.Color]::Firebrick
            $featureStatus.VisitedLinkColor = [Drawing.Color]::Firebrick
            $featureStatus.LinkBehavior = 'HoverUnderline'
            $featureStatus.AutoEllipsis = $false
            $featureStatus.TextAlign = 'MiddleRight'
            $featureStatus.SetBounds(($panelWidth - $statusWidth - [int](8 * $scale)), 0, $statusWidth, $rowHeight)
            $preferredHeight = $check.GetPreferredSize((New-Object Drawing.Size($check.Width, 0))).Height
            $wrappedHeight = (Measure-JobsFeatureText $check.Text $font ([Math]::Max(1, $check.Width - [int](26 * $scale)))).Height + [int](8 * $scale)
            $group.RowHeight = [int][Math]::Max($group.RowHeight, [Math]::Max($preferredHeight, $wrappedHeight))
            $group.Box.Controls.Add($featureStatus)
            $featureLabels[$feature.Id] = $featureStatus
            $check.TabIndex = $index
            $group.Box.Controls.Add($check)
            $group.Checks += $check
            $checks += $check
        }
        foreach ($group in $groupStates) {
            $top = [int][Math]::Max(66 * $scale, [Math]::Max($group.All.Bottom, $group.Counter.Bottom) + 8 * $scale)
            foreach ($check in $group.Checks) {
                $check.Top = $top
                $check.Height = $group.RowHeight
                $featureLabels[[string]$check.Tag].Top = $top
                $featureLabels[[string]$check.Tag].Height = $group.RowHeight
                $top += $group.RowHeight
            }
            $group.Box.Height = $top + [int](10 * $scale)
        }

        $footer = New-Object System.Windows.Forms.Panel
        $footer.Dock = 'Bottom'
        $footer.Height = $layout.FooterHeight
        $status = New-Object System.Windows.Forms.Label
        $status.Font = $font
        $status.AutoEllipsis = $false
        $status.Location = New-Object System.Drawing.Point($padding, ([int](10 * $scale)))
        $status.Size = New-Object System.Drawing.Size(($layout.ClientWidth - 2 * $padding), ([int](26 * $scale)))
        $footer.Controls.Add($status)
        $buttons = @()
        foreach ($text in @('全选', '全不选', $action, '取消')) {
            $button = New-Object System.Windows.Forms.Button
            $button.Font = $font
            $button.Text = $text
            $button.Size = New-Object System.Drawing.Size(([int](104 * $scale)), ([int](34 * $scale)))
            $buttons += $button
            $footer.Controls.Add($button)
        }
        $buttons[0].Location = New-Object System.Drawing.Point($padding, ([int](46 * $scale)))
        $buttons[1].Location = New-Object System.Drawing.Point(($padding + [int](114 * $scale)), ([int](46 * $scale)))
        $buttons[2].Location = New-Object System.Drawing.Point(($layout.ClientWidth - $padding - [int](218 * $scale)), ([int](46 * $scale)))
        $buttons[3].Location = New-Object System.Drawing.Point(($layout.ClientWidth - $padding - [int](104 * $scale)), ([int](46 * $scale)))
        $progress = New-Object System.Windows.Forms.ProgressBar
        $progress.SetBounds($padding, ([int](36 * $scale)), ($layout.ClientWidth - 2 * $padding), ([int](6 * $scale)))
        $footer.Controls.Add($progress)
        $logPanel = New-Object System.Windows.Forms.Panel
        $logPanel.Dock = 'Fill'
        $logPanel.Height = [int][Math]::Min(180 * $scale, [Math]::Max(100 * $scale, $layout.ClientHeight * 0.25))
        $logToolbar = New-Object System.Windows.Forms.FlowLayoutPanel
        $logToolbar.Font = $font
        $logToolbar.Dock = 'Top'
        $logToolbar.AutoSize = $true
        $logToolbar.AutoSizeMode = 'GrowAndShrink'
        $logToolbar.WrapContents = $true
        $logToolbar.MaximumSize = New-Object Drawing.Size($layout.ClientWidth, 0)
        $logTitle = New-Object System.Windows.Forms.Label
        $logTitle.Font = $font
        $logTitle.Text = '实时日志（拖动上方分隔条调节高度）'
        $logTitle.AutoSize = $true
        $logTitle.TextAlign = 'MiddleLeft'
        $copyLog = New-Object System.Windows.Forms.Button
        $copyLog.Font = $font
        $copyLog.Text = '复制全部日志'
        $copyLog.AutoSize = $true
        $followLog = New-Object System.Windows.Forms.CheckBox
        $followLog.Font = $font
        $followLog.Text = '自动滚动'
        $followLog.Checked = $true
        $followLog.AutoSize = $true
        $logToolbar.Controls.AddRange(@($logTitle, $copyLog, $followLog))
        $logToolbar.Size = $logToolbar.GetPreferredSize((New-Object Drawing.Size($layout.ClientWidth, 0)))
        $logPanel.Height = [int][Math]::Max($logPanel.Height, $logToolbar.Height + 80 * $scale)
        $logView = New-Object System.Windows.Forms.RichTextBox
        $logView.Dock = 'Fill'
        $logView.ReadOnly = $true
        $logView.WordWrap = $false
        $logView.DetectUrls = $false
        $logView.BackColor = [Drawing.Color]::FromArgb(24, 28, 34)
        $logView.ForeColor = [Drawing.Color]::Gainsboro
        $logView.Font = New-Object Drawing.Font('Consolas', 9)
        $logView.ScrollBars = 'Both'
        $logView.ShortcutsEnabled = $true
        $logView.HideSelection = $false
        $logMenu = New-Object System.Windows.Forms.ContextMenuStrip
        $copySelection = New-Object System.Windows.Forms.ToolStripMenuItem('复制')
        $copySelection.ShortcutKeys = [Windows.Forms.Keys]::Control -bor [Windows.Forms.Keys]::C
        $selectLog = New-Object System.Windows.Forms.ToolStripMenuItem('全选')
        $selectLog.ShortcutKeys = [Windows.Forms.Keys]::Control -bor [Windows.Forms.Keys]::A
        [void]$logMenu.Items.Add($copySelection)
        [void]$logMenu.Items.Add($selectLog)
        $logView.ContextMenuStrip = $logMenu
        $logPanel.Controls.Add($logView)
        $logPanel.Controls.Add($logToolbar)
        $buttons[3].DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $form.CancelButton = $buttons[3]
        $logSplit = New-Object System.Windows.Forms.SplitContainer
        $logSplit.Size = New-Object Drawing.Size($layout.ClientWidth, ($layout.ClientHeight - $header.Height))
        $logSplit.Orientation = 'Horizontal'
        $logSplit.Dock = 'Fill'
        $logSplit.FixedPanel = 'Panel2'
        $logSplit.SplitterWidth = [int][Math]::Max(7, [Math]::Ceiling(7 * $scale))
        $logSplit.IsSplitterFixed = $false
        $logSplit.AccessibleName = '功能与日志分隔条'
        $logSplit.AccessibleDescription = '上下拖动调节日志高度'
        $initialLogLayout = Get-JobsManagementLogLayout -Height $logSplit.Height -FooterHeight $footer.Height -ToolbarHeight $logToolbar.Height -RowHeight $rowHeight -SplitterWidth $logSplit.SplitterWidth -LogHeight $logPanel.Height -Scale $scale
        $logSplit.SplitterDistance = $initialLogLayout.Distance
        $logSplit.Panel1MinSize = $initialLogLayout.UpperMinimum
        $logSplit.Panel2MinSize = $initialLogLayout.LowerMinimum
        $logSplit.Panel1.Controls.Add($grid)
        $logSplit.Panel1.Controls.Add($footer)
        $logSplit.Panel2.Controls.Add($logPanel)
        $toolTip.SetToolTip($logSplit, '上下拖动分隔条调节日志高度')
        $form.Controls.Add($logSplit)
        $form.Controls.Add($header)
        $state = [pscustomobject]@{
            Form = $form; Checks = $checks; ConfirmButton = $buttons[2]
            SelectAllButton = $buttons[0]; ClearButton = $buttons[1]; CancelButton = $buttons[3]
            StatusLabel = $status; Layout = $layout; Mode = $Mode; ToolTip = $toolTip; Font = $font
            Groups = $groupStates; ContentPanel = $grid; Footer = $footer
            Header = $header; HeaderLabel = $headerLabel; LogToolbar = $logToolbar; Padding = $padding; Scale = $scale
            BuildPlan = $BuildPlan; WorkerPath = $WorkerPath; Running = $false; Started = $false
            FeatureLabels = $featureLabels; FeatureStates = @{}; Progress = $progress
            LogView = $logView; FollowLog = $followLog; CopyLogButton = $copyLog
            LogSplit = $logSplit; LogMenu = $logMenu; CopySelectionItem = $copySelection; SelectLogItem = $selectLog
            LogPath = (Join-Path ([IO.Path]::GetTempPath()) ('JobsExtensionManager-' + [guid]::NewGuid().ToString('N') + '.log'))
            Pump = $null; Timer = (New-Object Windows.Forms.Timer); RequestPath = $null
            RunClocks = @{ Install = (New-Object Diagnostics.Stopwatch); Uninstall = (New-Object Diagnostics.Stopwatch) }
            Preview = [bool]$Preview; OperationBox = $operationBox; Operation = $(if ($Mode -eq 'Manage') { 'Install' } else { $Mode }); Installed = @($Installed)
        }
        # 闭包保留表单状态，事件不依赖已返回的构造函数局部作用域。
        $refresh = {
            if ($state.Running -or $state.Started) { return }
            $count = @($state.Checks | Where-Object { $_.Checked }).Count
            Set-JobsFeatureStatusText $state ('已选 {0} / {1} 项；关闭或取消窗口不执行操作。' -f $count, $state.Checks.Count)
            $state.ConfirmButton.Enabled = $count -gt 0 -or $state.Mode -eq 'Configure'
            $state.Form.AcceptButton = $null
            if ($state.ConfirmButton.Enabled) { $state.Form.AcceptButton = $state.ConfirmButton }
            foreach ($group in $state.Groups) {
                $groupCount = @($group.Checks | Where-Object { $_.Checked }).Count
                $group.Counter.Text = '已选 {0} / {1}' -f $groupCount, $group.Checks.Count
                $group.All.Enabled = $groupCount -lt $group.Checks.Count
                $group.None.Enabled = $groupCount -gt 0
            }
        }.GetNewClosure()
        foreach ($check in $checks) { $check.Add_CheckedChanged($refresh) }
        foreach ($group in $groupStates) {
            $localGroup = $group
            $group.All.Add_Click({ foreach ($check in $localGroup.Checks) { if ($check.Enabled) { $check.Checked = $true } } }.GetNewClosure())
            $group.None.Add_Click({ foreach ($check in $localGroup.Checks) { $check.Checked = $false } }.GetNewClosure())
        }
        $buttons[0].Add_Click({ foreach ($check in $state.Checks) { if ($check.Enabled) { $check.Checked = $true } } }.GetNewClosure())
        $buttons[1].Add_Click({ foreach ($check in $state.Checks) { $check.Checked = $false } }.GetNewClosure())
        $buttons[2].Add_Click({
            $ids = @($state.Checks | Where-Object { $_.Checked } | ForEach-Object { [string]$_.Tag })
            # 即使事件被程序直接调用，也不能绕过空选门禁。
            if ($ids.Count -eq 0 -and $state.Mode -ne 'Configure') { return }
            $choice = [pscustomobject]@{ Features = $ids; Mode = $state.Operation }
            if ($state.BuildPlan -and $state.Preview) {
                Add-JobsManagementLog $state ('仅预览：' + (ConvertTo-Json -InputObject $choice -Compress -Depth 3))
                Set-JobsFeatureStatusText $state '仅预览：选择已显示在下方日志，未执行安装或卸载。'
                return
            }
            if ($state.BuildPlan -and -not $state.Preview) {
                try { Start-JobsManagementRun $state $choice }
                catch { Add-JobsManagementLog $state ('无法建立操作计划：' + $_.Exception.Message) }
                return
            }
            $state.Form.Tag = $choice
            $state.Form.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $state.Form.Close()
        }.GetNewClosure())
        if ($operationBox) {
            $operationBox.Add_SelectedIndexChanged({
                $state.Operation = 'Install'
                $state.ConfirmButton.Text = '安装 / 更新'
                if ($state.OperationBox.SelectedIndex -eq 1) {
                    $state.Operation = 'Uninstall'
                    $state.ConfirmButton.Text = '卸载所选'
                }
                if ($state.Preview) { $state.ConfirmButton.Text = '返回选择' }
                foreach ($check in $state.Checks) {
                    $check.Checked = $false
                    $check.Enabled = $state.Operation -ne 'Uninstall' -or [string]$check.Tag -in $state.Installed
                }
                & $refresh
            }.GetNewClosure())
        }
        $state.Timer.Interval = 100
        $state.Timer.Add_Tick((New-JobsManagementTimerCallback $state))
        $form.Add_FormClosing({
            param($sender, $eventArgs)
            if ($state.Running) {
                $eventArgs.Cancel = $true
                Set-JobsFeatureStatusText $state '操作正在执行，请等待事务完成后关闭；下方日志可随时复制。'
            }
        }.GetNewClosure())
        $copySelection.Add_Click({ $state.LogView.Copy() }.GetNewClosure())
        $selectLog.Add_Click({
            [void]$state.LogView.Focus()
            $state.LogView.SelectAll()
        }.GetNewClosure())
        $logMenu.Add_Opening({
            $state.CopySelectionItem.Enabled = $state.LogView.SelectionLength -gt 0
            $state.SelectLogItem.Enabled = $state.LogView.TextLength -gt 0
        }.GetNewClosure())
        $logView.Add_KeyDown({
            param($sender, $eventArgs)
            if ($eventArgs.Control -and -not $eventArgs.Alt -and $eventArgs.KeyCode -eq [Windows.Forms.Keys]::A) {
                $sender.SelectAll()
                $eventArgs.Handled = $true
                $eventArgs.SuppressKeyPress = $true
            }
        }.GetNewClosure())
        $copyLog.Add_Click({
            try { [Windows.Forms.Clipboard]::SetText([IO.File]::ReadAllText($state.LogPath)) }
            catch { Set-JobsFeatureStatusText $state ('复制日志失败：' + $_.Exception.Message) }
        }.GetNewClosure())
        foreach ($label in $state.FeatureLabels.Values) {
            $label.Add_LinkClicked({
                param($sender, $eventArgs)
                $id = [string]$sender.Tag
                if (-not $state.FeatureStates.ContainsKey($id) -or $state.FeatureStates[$id] -ne 'Failed') { return }
                try { Open-JobsManagementLog -LogPath $state.LogPath }
                catch { Set-JobsFeatureStatusText $state ('打开完整日志失败：' + $_.Exception.Message) }
            }.GetNewClosure())
        }
        Add-JobsManagementLog $state '勾选功能并点击安装 / 更新或卸载，任务将在本面板执行；取消、关闭或空选不执行。'
        Add-JobsManagementLog $state '影响范围：当前用户的菜单、运行文件和功能配置；安装会构建与注册所选包，卸载保留程序、日志、备份和工具。'
        Add-JobsManagementLog $state ('来源：' + $WorkerPath + '；日志：' + $state.LogPath)
        & $refresh
        return $state
    } catch {
        $form.Dispose()
        $toolTip.Dispose()
        $font.Dispose()
        throw
    }
}

# 捕获原模块的函数体；GetNewClosure 的动态模块不能按名称访问私有进度函数。
function New-JobsManagementTimerCallback {
    param($State)
    $readOutput = ${function:Read-JobsManagementOutput}
    $updateProgress = ${function:Update-JobsManagementProgress}
    return {
        if ($State.Running) { & $readOutput $State }
        if ($State.Running) { & $updateProgress $State }
    }.GetNewClosure()
}

# 只展示 Catalog 传入的 Id/Label/Group 并返回选择；业务门禁写在对应包，不写进 UI 文案或点击回调。
function Show-JobsFeatureSelection {
    param(
        [object[]]$Packages,
        [string[]]$Selected,
        [string[]]$Installed = @(),
        [ValidateSet('Manage', 'Install', 'Configure', 'Uninstall')][string]$Mode = 'Manage',
        [switch]$Preview,
        [scriptblock]$BuildPlan,
        [string]$WorkerPath
    )
    $state = New-JobsFeatureSelectionForm -Packages $Packages -Selected $Selected -Installed $Installed -Mode $Mode -Preview:$Preview -BuildPlan $BuildPlan -WorkerPath $WorkerPath
    try {
        if ($state.Form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
        return $state.Form.Tag
    } finally {
        $state.Timer.Dispose()
        $state.LogView.Font.Dispose()
        $state.LogMenu.Dispose()
        $state.Form.Dispose()
        $state.ToolTip.Dispose()
        $state.Font.Dispose()
    }
}

# Process 事件只在 .NET 线程里入队，UI 线程定时取走，避免 PowerShell 回调跨 runspace 崩溃。
function Initialize-JobsManagementProcess {
    if ('JobsManagement.OutputPump' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO;
using System.Threading;
namespace JobsManagement {
    public sealed class OutputChunk {
        public string Text;
        public bool IsEvent;
        public OutputChunk(string text, bool isEvent) { Text = text; IsEvent = isEvent; }
    }
    public sealed class OutputPump : IDisposable {
        private const string Marker = "@@JOBS-MANAGER@@";
        public readonly ConcurrentQueue<OutputChunk> Lines = new ConcurrentQueue<OutputChunk>();
        public Process Process { get; private set; }
        private int closed;
        public bool Drained { get { return Volatile.Read(ref closed) == 2; } }
        private void Read(StreamReader reader, bool events) {
            char[] buffer = new char[1024];
            string pending = "";
            bool atLineStart = true;
            try {
                int count;
                while ((count = reader.Read(buffer, 0, buffer.Length)) > 0) {
                    pending += new string(buffer, 0, count);
                    while (pending.Length > 0) {
                        int newline = pending.IndexOf('\n');
                        bool marker = events && atLineStart && pending.StartsWith(Marker, StringComparison.Ordinal);
                        if (events && atLineStart && Marker.StartsWith(pending, StringComparison.Ordinal)) break;
                        if (marker && newline < 0) break;
                        if (newline >= 0) {
                            string line = pending.Substring(0, newline + 1);
                            Lines.Enqueue(new OutputChunk(marker ? line.TrimEnd('\r', '\n') : line, marker));
                            pending = pending.Substring(newline + 1);
                            atLineStart = true;
                        } else {
                            Lines.Enqueue(new OutputChunk(pending, false));
                            pending = "";
                            atLineStart = false;
                        }
                    }
                }
                if (pending.Length > 0) Lines.Enqueue(new OutputChunk(pending, events && atLineStart && pending.StartsWith(Marker, StringComparison.Ordinal)));
            } catch (Exception error) {
                Lines.Enqueue(new OutputChunk("\n读取后台输出失败：" + error.Message + "\n", false));
            } finally { Interlocked.Increment(ref closed); }
        }
        public void Start(ProcessStartInfo info) {
            info.UseShellExecute = false;
            info.CreateNoWindow = true;
            info.RedirectStandardOutput = true;
            info.RedirectStandardError = true;
            Process = new Process { StartInfo = info };
            if (!Process.Start()) throw new InvalidOperationException("无法启动后台管理进程。");
            Thread output = new Thread(() => Read(Process.StandardOutput, true));
            Thread error = new Thread(() => Read(Process.StandardError, false));
            output.IsBackground = true;
            error.IsBackground = true;
            output.Start();
            error.Start();
        }
        public OutputChunk Take() { OutputChunk chunk; return Lines.TryDequeue(out chunk) ? chunk : null; }
        public void Dispose() { if (Process != null) Process.Dispose(); }
    }
}
'@
}

function Add-JobsManagementLog {
    param($State, [string]$Text, [switch]$NoNewline)
    # 环形显示控制内存，完整输出追加到本次独立日志文件。
    $ending = [Environment]::NewLine
    if ($NoNewline) { $ending = '' }
    $clean = [regex]::Replace($Text, "\x1b\[[0-?]*[ -/]*[@-~]", '')
    [IO.File]::AppendAllText($State.LogPath, $clean + $ending, (New-Object Text.UTF8Encoding($false)))
    $view = $State.LogView
    $start = $view.SelectionStart
    $length = $view.SelectionLength
    if ($view.TextLength -gt 1000000 -and $length -eq 0) { $view.Text = $view.Text.Substring($view.TextLength - 700000) }
    $view.AppendText($clean + $ending)
    if ($State.FollowLog.Checked -and $length -eq 0) {
        $view.SelectionStart = $view.TextLength
        $view.ScrollToCaret()
    } else {
        $view.SelectionStart = [Math]::Min($start, $view.TextLength)
        $view.SelectionLength = [Math]::Min($length, $view.TextLength - $view.SelectionStart)
    }
}

# 路径与日志正文都只作为数据；新终端仅用 LiteralPath 读取完整会话文件。
function New-JobsManagementLogStartInfo {
    param([Parameter(Mandatory = $true)][string]$LogPath)
    if ([string]::IsNullOrWhiteSpace($LogPath) -or $LogPath -match '[\x00\r\n]') { throw '会话日志路径无效。' }
    $item = Get-Item -LiteralPath $LogPath -Force -ErrorAction Stop
    if ($item.PSIsContainer) { throw ('会话日志不是文件：' + $LogPath) }
    $stream = [IO.File]::Open($item.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    $stream.Dispose()
    $encodedPath = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($item.FullName))
    $command = @'
$logPath = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('__JOBS_LOG_PATH__'))
try {
    Write-Host ('完整会话日志：' + $logPath) -ForegroundColor Cyan
    Get-Content -LiteralPath $logPath -Encoding UTF8 -ReadCount 256 -ErrorAction Stop
} catch {
    Write-Host ('读取会话日志失败：' + $_.Exception.Message) -ForegroundColor Red
}
'@
    $command = $command.Replace('__JOBS_LOG_PATH__', $encodedPath)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = Join-Path $PSHOME 'powershell.exe'
    $start.Arguments = '-NoLogo -NoProfile -NoExit -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $start.UseShellExecute = $true
    $start.WindowStyle = 'Normal'
    return $start
}

# 启动独立日志终端，不等待其退出或改变当前后台事务。
function Open-JobsManagementLog {
    param([Parameter(Mandatory = $true)][string]$LogPath)
    $start = New-JobsManagementLogStartInfo -LogPath $LogPath
    $process = [Diagnostics.Process]::Start($start)
    if ($null -eq $process) { throw '系统未能启动日志终端。' }
    $process.Dispose()
}

function Set-JobsManagementFeatureState {
    param($State, [string[]]$FeatureIds, [string]$Status, [string]$Message)
    foreach ($id in $FeatureIds) {
        if (-not $State.FeatureStates.ContainsKey($id)) { continue }
        $State.FeatureStates[$id] = $Status
        $label = $State.FeatureLabels[$id]
        $label.ForeColor = [Drawing.SystemColors]::ControlText
        $label.Links.Clear()
        $label.Cursor = [Windows.Forms.Cursors]::Default
        $label.Text = switch ($Status) {
            'Pending' { '等待中' }
            'Running' { if ($State.Operation -eq 'Uninstall') { '正在卸载…' } else { '正在安装 / 更新…' } }
            'Succeeded' {
                $label.ForeColor = [Drawing.Color]::ForestGreen
                if ($State.Operation -eq 'Uninstall') { '已完成' } else { '✅ 安装成功' }
            }
            'Failed' { $label.ForeColor = [Drawing.Color]::Firebrick; '失败，见日志' }
            'Skipped' { '未执行' }
        }
        $label.LinkArea = New-Object Windows.Forms.LinkArea(0, 0)
        $tip = $Message
        if ($Status -eq 'Failed') {
            [void]$label.Links.Add(0, $label.Text.Length)
            $label.Cursor = [Windows.Forms.Cursors]::Hand
            $tip += "`r`n点击在新 PowerShell 窗口读取本次完整会话日志；当前任务继续运行。`r`n" + $State.LogPath
        }
        $State.ToolTip.SetToolTip($label, $tip)
    }
    Update-JobsManagementProgress $State
}

function Complete-JobsManagementRun {
    param($State, [bool]$Success, [string]$Message)
    $clock = Get-JobsManagementClock $State
    $clock.Stop()
    $State.Timer.Stop()
    $State.Running = $false
    $State.Progress.Style = 'Continuous'
    foreach ($id in @($State.FeatureStates.Keys)) {
        if ($State.FeatureStates[$id] -eq 'Running' -or $State.FeatureStates[$id] -eq 'Pending') {
            $status = 'Skipped'
            if ($State.FeatureStates[$id] -eq 'Running') { $status = 'Failed' }
            Set-JobsManagementFeatureState $State @($id) $status $Message
        }
    }
    $progress = Get-JobsManagementProgress $State
    $clockLabel = '安装总用时'
    if ($State.Operation -eq 'Uninstall') { $clockLabel = '卸载总用时' }
    $messageWithProgress = '{0} 已处理 {1} / {2} 项（{3}%，按完成项计数）；{4} {5}' -f $Message, $progress.Finished, $progress.Total, $progress.Percent, $clockLabel, (Format-JobsManagementElapsedTime $clock.Elapsed)
    Set-JobsFeatureStatusText $State $messageWithProgress
    if ($null -ne $State.Pump) { $State.Pump.Dispose(); $State.Pump = $null }
    if ($State.RequestPath -and [IO.File]::Exists($State.RequestPath)) { [IO.File]::Delete($State.RequestPath) }
    $State.CancelButton.Enabled = $true
    $State.CancelButton.Text = '关闭'
    $State.Form.CancelButton = $State.CancelButton
    Add-JobsManagementLog $State ($messageWithProgress + ' 日志：' + $State.LogPath)
}

function Read-JobsManagementOutput {
    param($State)
    try {
        # 单次限量以便大量编译输出时仍及时响应复制和拖动。
        for ($index = 0; $index -lt 300; $index++) {
            $chunk = $State.Pump.Take()
            if ($null -eq $chunk) { break }
            $line = $chunk.Text
            if ($chunk.IsEvent -and $line.StartsWith('@@JOBS-MANAGER@@')) {
                try {
                    $event = $line.Substring(16) | ConvertFrom-Json
                    if ($event.State -ne 'Finished') { Set-JobsManagementFeatureState $State @($event.FeatureIds) $event.State $event.Message }
                    Add-JobsManagementLog $State $event.Message
                } catch { Add-JobsManagementLog $State $line }
            } else { Add-JobsManagementLog $State $line -NoNewline }
        }
        if ($State.Pump.Process.HasExited -and $State.Pump.Drained -and $State.Pump.Lines.IsEmpty) {
            $success = $State.Pump.Process.ExitCode -eq 0 -and @($State.FeatureStates.Values | Where-Object { $_ -ne 'Succeeded' }).Count -eq 0
            $message = '部分功能处理失败；其它所选功能已继续处理。点击失败状态查看完整会话日志。'
            if ($success) { $message = '全部处理完成；可选择复制日志，或关闭面板。' }
            $message += ' 退出码：' + $State.Pump.Process.ExitCode + '。'
            Complete-JobsManagementRun $State $success $message
        }
    } catch {
        # 日志/面板错误也保持进程生命周期，不能在事务仍运行时放开关闭。
        Set-JobsFeatureStatusText $State ('读取日志失败：' + $_.Exception.Message)
        if ($State.Pump.Process.HasExited) { Complete-JobsManagementRun $State $false $State.StatusLabel.Text }
    }
}

function Start-JobsManagementRun {
    param($State, $Choice)
    if ($State.Running -or $State.Started) { return }
    $State.Operation = $Choice.Mode
    $clock = Get-JobsManagementClock $State
    $clock.Restart()
    try { $plan = @(& $State.BuildPlan $Choice) }
    catch { Complete-JobsManagementRun $State $false ('无法建立操作计划：' + $_.Exception.Message); return }
    if ($plan.Count -eq 0) {
        $clock.Stop()
        Add-JobsManagementLog $State '没有需要处理的功能；未更改任何配置。'
        $clockLabel = '安装总用时'
        if ($State.Operation -eq 'Uninstall') { $clockLabel = '卸载总用时' }
        Set-JobsFeatureStatusText $State ('没有需要处理的功能；' + $clockLabel + ' ' + (Format-JobsManagementElapsedTime $clock.Elapsed))
        return
    }
    $State.Started = $true
    $State.Running = $true
    $State.CancelButton.Enabled = $false
    $State.Form.CancelButton = $null
    $State.Form.AcceptButton = $null
    $State.ConfirmButton.Enabled = $false
    $State.SelectAllButton.Enabled = $false
    $State.ClearButton.Enabled = $false
    if ($State.OperationBox) { $State.OperationBox.Enabled = $false }
    foreach ($check in $State.Checks) { $check.Enabled = $false }
    foreach ($group in $State.Groups) { $group.All.Enabled = $false; $group.None.Enabled = $false }
    foreach ($operation in $plan) {
        foreach ($id in @($operation.FeatureIds)) { $State.FeatureStates[$id] = 'Pending' }
    }
    $State.Progress.Maximum = [Math]::Max(1, $State.FeatureStates.Count)
    Set-JobsManagementFeatureState $State @($State.FeatureStates.Keys) Pending '等待处理。'
    Add-JobsManagementLog $State ('开始执行：' + $Choice.Mode + '；进程输出将在此实时显示。')
    try {
        Initialize-JobsManagementProcess
        $State.RequestPath = Join-Path ([IO.Path]::GetTempPath()) ('JobsExtensionPlan-' + [guid]::NewGuid().ToString('N') + '.json')
        $request = [ordered]@{ Plan = @($plan) }
        [IO.File]::WriteAllText($State.RequestPath, (ConvertTo-Json -InputObject $request -Depth 8), (New-Object Text.UTF8Encoding($false)))
        $start = New-Object Diagnostics.ProcessStartInfo
        $start.FileName = Join-Path $PSHOME 'powershell.exe'
        # -File 参数只包含两个本地文件路径，拒绝命令行引号/换行，避免解释用户选择为代码。
        if (($State.WorkerPath + $State.RequestPath) -match '["\r\n]') { throw '后台脚本路径包含不支持的字符。' }
        $start.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $State.WorkerPath + '" -RequestPath "' + $State.RequestPath + '"'
        $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
        $start.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
        $start.EnvironmentVariables['JOBS_MANAGEMENT_GUI'] = '1'
        $State.Pump = New-Object JobsManagement.OutputPump
        $State.Pump.Start($start)
        $State.Timer.Start()
    } catch { Complete-JobsManagementRun $State $false ('无法开始执行：' + $_.Exception.Message) }
}

function Invoke-JobsManagementNativeProcess {
    param([Diagnostics.ProcessStartInfo]$StartInfo, [int]$TimeoutMilliseconds = 120000)
    Initialize-JobsManagementProcess
    $pump = New-Object JobsManagement.OutputPump
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        $pump.Start($StartInfo)
        do {
            while ($null -ne ($chunk = $pump.Take())) { [Console]::Out.Write($chunk.Text); [Console]::Out.Flush() }
            if ($clock.ElapsedMilliseconds -gt $TimeoutMilliseconds) {
                if (-not $pump.Process.HasExited) { $pump.Process.Kill() }
                throw '原生菜单编译超时。'
            }
            [void]$pump.Process.WaitForExit(50)
        } until ($pump.Process.HasExited -and $pump.Drained -and $pump.Lines.IsEmpty)
        return $pump.Process.ExitCode
    } finally { $pump.Dispose() }
}

Export-ModuleMember -Function Open-JobsManagementLog, Show-JobsFeatureSelection, Get-JobsFeatureSelectionLayout, Get-JobsFeatureContentLayout, Set-JobsFeatureStatusText, Initialize-JobsManagementProcess, Start-JobsManagementRun, Read-JobsManagementOutput, Add-JobsManagementLog, Set-JobsManagementFeatureState, Complete-JobsManagementRun, Invoke-JobsManagementNativeProcess

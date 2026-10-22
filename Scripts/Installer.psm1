# Installer.psm1 | WindowsOS@Extension 组合选择面板
# Created by Jobs on 2026年10月18日，星期日.
# 只展示包清单和返回选择；预览、取消均不触碰安装状态或注册表。
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
        throw '当前桌面工作区过小，无法完整显示功能与按钮；请降低显示缩放或提高屏幕分辨率后重试。'
    }
    return [pscustomobject]@{
        Columns = $columns; Rows = $rows; ClientWidth = $width; ClientHeight = $height
        RowHeight = $RowHeight; HeaderHeight = $header; FooterHeight = $footer
    }
}

function New-JobsFeatureSelectionForm {
    param(
        [object[]]$Packages,
        [string[]]$Selected,
        [ValidateSet('Install', 'Configure', 'Uninstall')][string]$Mode = 'Install',
        [switch]$Preview
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
        $description = '勾选需要安装或更新的功能，未勾选的已安装功能继续保留。'
        if ($Mode -eq 'Configure') {
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
            $description = '仅预览功能选择：返回后退出，不安装、不卸载、不写入状态或注册表。'
        }
        $form.ClientSize = New-Object System.Drawing.Size($layout.ClientWidth, $layout.ClientHeight)
        $form.FormBorderStyle = 'FixedDialog'
        $form.MaximizeBox = $false
        $form.MinimizeBox = $false
        $form.StartPosition = 'Manual'
        $form.Location = New-Object System.Drawing.Point(
            ([int]($area.Left + ($area.Width - $form.Width) / 2)),
            ([int]($area.Top + ($area.Height - $form.Height) / 2)))
        $padding = [int][Math]::Ceiling(20 * $scale)
        $header = New-Object System.Windows.Forms.Label
        $header.Dock = 'Top'
        $header.Height = $layout.HeaderHeight
        $header.Padding = New-Object System.Windows.Forms.Padding($padding)
        $header.Text = "资源管理器右键扩展 · $action`r`n$description`r`n悬停查看功能说明；Windows 11：右键 → 显示更多选项。"

        $grid = New-Object System.Windows.Forms.TableLayoutPanel
        $grid.Dock = 'Fill'
        $grid.Padding = New-Object System.Windows.Forms.Padding($padding, 0, $padding, 0)
        $grid.AutoScroll = $false
        $grid.ColumnCount = $layout.Columns
        $grid.RowCount = $layout.Rows
        for ($column = 0; $column -lt $layout.Columns; $column++) {
            [void]$grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', (100.0 / $layout.Columns))))
        }
        for ($row = 0; $row -lt $layout.Rows; $row++) {
            [void]$grid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', $rowHeight)))
        }
        $checks = @()
        for ($index = 0; $index -lt $features.Count; $index++) {
            $feature = $features[$index]
            $check = New-Object System.Windows.Forms.CheckBox
            $check.Text = $feature.Label
            $check.Tag = $feature.Id
            $check.Dock = 'Fill'
            $check.AutoEllipsis = $true
            $check.Margin = New-Object System.Windows.Forms.Padding(4, 0, 4, 0)
            $check.Checked = $feature.Id -in $Selected
            $toolTip.SetToolTip($check, ($feature.Label + "`r`n" + $feature.Description))
            $column = [int][Math]::Floor($index / [double]$layout.Rows)
            $row = $index % $layout.Rows
            $check.TabIndex = $index
            $grid.Controls.Add($check, $column, $row)
            $checks += $check
        }

        $footer = New-Object System.Windows.Forms.Panel
        $footer.Dock = 'Bottom'
        $footer.Height = $layout.FooterHeight
        $status = New-Object System.Windows.Forms.Label
        $status.Location = New-Object System.Drawing.Point($padding, ([int](10 * $scale)))
        $status.Size = New-Object System.Drawing.Size(($layout.ClientWidth - 2 * $padding), ([int](26 * $scale)))
        $footer.Controls.Add($status)
        $buttons = @()
        foreach ($text in @('全选', '全不选', $action, '取消')) {
            $button = New-Object System.Windows.Forms.Button
            $button.Text = $text
            $button.Size = New-Object System.Drawing.Size(([int](104 * $scale)), ([int](34 * $scale)))
            $buttons += $button
            $footer.Controls.Add($button)
        }
        $buttons[0].Location = New-Object System.Drawing.Point($padding, ([int](46 * $scale)))
        $buttons[1].Location = New-Object System.Drawing.Point(($padding + [int](114 * $scale)), ([int](46 * $scale)))
        $buttons[2].Location = New-Object System.Drawing.Point(($layout.ClientWidth - $padding - [int](218 * $scale)), ([int](46 * $scale)))
        $buttons[3].Location = New-Object System.Drawing.Point(($layout.ClientWidth - $padding - [int](104 * $scale)), ([int](46 * $scale)))
        $buttons[3].DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $form.CancelButton = $buttons[3]
        $form.Controls.Add($grid)
        $form.Controls.Add($header)
        $form.Controls.Add($footer)
        $state = [pscustomobject]@{
            Form = $form; Checks = $checks; ConfirmButton = $buttons[2]
            SelectAllButton = $buttons[0]; ClearButton = $buttons[1]; CancelButton = $buttons[3]
            StatusLabel = $status; Layout = $layout; Mode = $Mode; ToolTip = $toolTip; Font = $font
        }
        # 闭包保留表单状态，事件不依赖已返回的构造函数局部作用域。
        $refresh = {
            $count = @($state.Checks | Where-Object { $_.Checked }).Count
            $state.StatusLabel.Text = '已选 {0} / {1} 项；关闭或取消窗口不执行操作。' -f $count, $state.Checks.Count
            $state.ConfirmButton.Enabled = $count -gt 0 -or $state.Mode -eq 'Configure'
            $state.Form.AcceptButton = $null
            if ($state.ConfirmButton.Enabled) { $state.Form.AcceptButton = $state.ConfirmButton }
        }.GetNewClosure()
        foreach ($check in $checks) { $check.Add_CheckedChanged($refresh) }
        $buttons[0].Add_Click({ foreach ($check in $state.Checks) { $check.Checked = $true } }.GetNewClosure())
        $buttons[1].Add_Click({ foreach ($check in $state.Checks) { $check.Checked = $false } }.GetNewClosure())
        $buttons[2].Add_Click({
            $ids = @($state.Checks | Where-Object { $_.Checked } | ForEach-Object { [string]$_.Tag })
            # 即使事件被程序直接调用，也不能绕过空选门禁。
            if ($ids.Count -eq 0 -and $state.Mode -ne 'Configure') { return }
            $state.Form.Tag = [pscustomobject]@{ Features = $ids }
            $state.Form.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $state.Form.Close()
        }.GetNewClosure())
        & $refresh
        return $state
    } catch {
        $form.Dispose()
        $toolTip.Dispose()
        $font.Dispose()
        throw
    }
}

function Show-JobsFeatureSelection {
    param(
        [object[]]$Packages,
        [string[]]$Selected,
        [ValidateSet('Install', 'Configure', 'Uninstall')][string]$Mode = 'Install',
        [switch]$Preview
    )
    $state = New-JobsFeatureSelectionForm -Packages $Packages -Selected $Selected -Mode $Mode -Preview:$Preview
    try {
        if ($state.Form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
        return $state.Form.Tag
    } finally {
        $state.Form.Dispose()
        $state.ToolTip.Dispose()
        $state.Font.Dispose()
    }
}

Export-ModuleMember -Function Show-JobsFeatureSelection, Get-JobsFeatureSelectionLayout

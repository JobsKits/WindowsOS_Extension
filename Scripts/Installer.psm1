# Installer.psm1 | Windows@Extension 组合选择面板
# Created by Jobs on 2026年10月18日，星期日.
# 这里只展示包清单，不承载任何右键业务或注册表写入。
Set-StrictMode -Version 2.0

function Show-JobsFeatureSelection {
    param([object[]]$Packages, [string[]]$Selected, [switch]$Uninstall)
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Jobs Windows 独立扩展 · 组合安装'
    if ($Uninstall) { $form.Text = 'Jobs Windows 独立扩展 · 选择卸载' }
    $form.Size = New-Object System.Drawing.Size(760, 560)
    $form.MinimumSize = New-Object System.Drawing.Size(620, 420)
    $form.StartPosition = 'CenterScreen'
    $form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
    $label = New-Object System.Windows.Forms.Label
    $label.Dock = 'Top'
    $label.Height = 76
    $label.Padding = New-Object System.Windows.Forms.Padding(14)
    $label.Text = "每项对应一个独立工程。勾选安装，取消勾选卸载该项；保存后逐包执行。`r`nWindows 11：右键 → 显示更多选项。取消窗口不修改任何包。"
    if ($Uninstall) { $label.Text = "只卸载勾选的独立扩展，未勾选项继续保留。`r`n每包单独备份、单独事务；执行失败会停止并列出结果。" }
    $list = New-Object System.Windows.Forms.CheckedListBox
    $list.Dock = 'Fill'
    $list.CheckOnClick = $true
    $list.HorizontalScrollbar = $true
    $list.IntegralHeight = $false
    $features = @($Packages)
    foreach ($feature in $features) {
        [void]$list.Items.Add(($feature.Label + '  —  ' + $feature.Description), ($feature.Id -in $Selected))
    }
    $buttons = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttons.Dock = 'Bottom'
    $buttons.Height = 58
    $buttons.Padding = New-Object System.Windows.Forms.Padding(10)
    foreach ($text in @('全选', '全不选', '保存', '取消')) {
        $button = New-Object System.Windows.Forms.Button
        $button.Text = $text
        $button.Width = 110
        $button.Height = 32
        switch ($text) {
            '全选' { $button.Add_Click({ for ($i = 0; $i -lt $list.Items.Count; $i++) { $list.SetItemChecked($i, $true) } }) }
            '全不选' { $button.Add_Click({ for ($i = 0; $i -lt $list.Items.Count; $i++) { $list.SetItemChecked($i, $false) } }) }
            '保存' { $button.DialogResult = [System.Windows.Forms.DialogResult]::OK; $form.AcceptButton = $button }
            '取消' { $button.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $form.CancelButton = $button }
        }
        $buttons.Controls.Add($button)
    }
    $form.Controls.Add($list)
    $form.Controls.Add($label)
    $form.Controls.Add($buttons)
    try {
        if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
        $ids = @($list.CheckedIndices | ForEach-Object { $features[$_].Id })
        return [pscustomobject]@{ Features = $ids }
    } finally { $form.Dispose() }
}


Export-ModuleMember -Function Show-JobsFeatureSelection

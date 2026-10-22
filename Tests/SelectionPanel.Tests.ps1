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
Assert-SelectionThrows { Get-JobsFeatureSelectionLayout -ItemCount 28 -WorkingWidth 1280 -WorkingHeight 540 } '三列仍无法容纳时明确停止'
$scaled = Get-JobsFeatureSelectionLayout -ItemCount $packages.Count -WorkingWidth 2560 -WorkingHeight 1440 -RowHeight 51 -Scale 1.5
Assert-Selection ($scaled.RowHeight -ge 51) '高 DPI 下点击区域随比例放大'
Assert-Selection ($scaled.ClientWidth -le 2560 -and $scaled.ClientHeight -le 1440) '高 DPI 布局仍在工作区内'
Assert-SelectionThrows { Get-JobsFeatureSelectionLayout -ItemCount $packages.Count -WorkingWidth 260 -WorkingHeight 180 } '过小工作区明确拒绝截断面板'

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
    @{ Name = '【Windows】🧩安装资源管理器扩展.cmd'; Mode = 'Install' },
    @{ Name = '【Windows】🧩卸载资源管理器扩展.cmd'; Mode = 'Uninstall' }
)) {
    $entryPath = Join-Path $root $entry.Name
    Assert-Selection (Test-Path -LiteralPath $entryPath -PathType Leaf) ('根目录保留独立入口：' + $entry.Mode)
    $bytes = [IO.File]::ReadAllBytes($entryPath)
    Assert-Selection (@($bytes | Where-Object { $_ -gt 127 }).Count -eq 0) ('CMD 正文使用 ASCII：' + $entry.Mode)
    $source = [Text.Encoding]::ASCII.GetString($bytes)
    Assert-Selection ($source -notmatch '(?<!\r)\n' -and $source.Contains("`r`n")) ('CMD 使用 CRLF：' + $entry.Mode)
    Assert-Selection ($source -match '%~dp0Scripts[\\/]Manage\.ps1' -and $source -match ('-Mode\s+' + $entry.Mode + '(?:\s|$)')) ('入口按自身位置直启正确模式：' + $entry.Mode)
}

if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
    function New-SelectionTestState {
        param([object[]]$Items, [string[]]$Selected, [string]$Mode)
        & $installer {
            param($Packages, $Choice, $PanelMode)
            New-JobsFeatureSelectionForm -Packages $Packages -Selected $Choice -Mode $PanelMode
        } $Items $Selected $Mode
    }

    function Invoke-SelectionTestClick {
        param($Button)
        # 未显示窗口的 PerformClick 会受 CanSelect 限制；直接触发 Click 测实际事件处理器。
        $flags = [Reflection.BindingFlags]::Instance -bor [Reflection.BindingFlags]::NonPublic
        $method = $Button.GetType().GetMethod('OnClick', $flags)
        [void]$method.Invoke($Button, @([EventArgs]::Empty))
    }

    $state = New-SelectionTestState -Items $packages -Selected @($packages[1].Id) -Mode Install
    try {
        Assert-Selection (@($state.Checks).Count -eq $packages.Count) '面板为每项功能提供独立复选框'
        Assert-Selection (-not $state.Form.AutoScroll -and -not $state.Form.MaximizeBox) '内容固定显示且不依赖滚动或最大化'
        Assert-Selection ($state.Form.FormBorderStyle -in @([Windows.Forms.FormBorderStyle]::FixedDialog, [Windows.Forms.FormBorderStyle]::FixedSingle)) '窗口按内容定尺寸并保持固定边框'
        for ($i = 0; $i -lt $packages.Count; $i++) {
            Assert-Selection ($state.Checks[$i].Text -eq $packages[$i].Label) ('功能标题不混入长说明：' + $packages[$i].Id)
            Assert-Selection ($state.ToolTip.GetToolTip($state.Checks[$i]).Contains($packages[$i].Description)) ('悬停保留功能说明：' + $packages[$i].Id)
            Assert-Selection ($state.Checks[$i].Bottom -le $state.Form.ClientSize.Height -and $state.Checks[$i].Right -le $state.Form.ClientSize.Width) ('每项功能均位于窗口内：' + $packages[$i].Id)
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

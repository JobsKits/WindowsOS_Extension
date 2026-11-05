# PanelPreferences.Tests.ps1 | 安装面板偏好、语言和副本回归
# Created by Jobs on 2026年11月4日，星期三.
# 只写临时偏好；不安装、注册扩展、修改系统主题或重启资源管理器。
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$module = Import-Module (Join-Path $root 'Scripts/Installer.psm1') -PassThru -Force -DisableNameChecking
Import-Module (Join-Path $root 'Scripts/Catalog.psm1') -Force -DisableNameChecking
$script:assertions = 0
$temp = Join-Path ([IO.Path]::GetTempPath()) ('JobsPanel 中文 ' + [guid]::NewGuid().ToString('N'))
$path = Join-Path $temp 'preferences.json'
function Assert-Panel {
    param([bool]$Value, [string]$Message)
    if (-not $Value) { throw ('FAIL: ' + $Message) }
    $script:assertions++
}
try {
    $defaults = Read-JobsPanelPreferences -Path $path
    Assert-Panel ($defaults.Theme -ceq 'system' -and $defaults.Language -ceq 'system') '缺失设置默认双跟随系统'
    Assert-Panel (-not [IO.Directory]::Exists($temp)) '读取默认值不创建偏好目录'
    foreach ($theme in @('system', 'dark', 'light')) {
        foreach ($language in @('system', 'zh-Hans', 'zh-Hant', 'en')) {
            Save-JobsPanelPreferences $theme $language -Path $path
            $saved = Read-JobsPanelPreferences -Path $path
            Assert-Panel ($saved.Theme -ceq $theme -and $saved.Language -ceq $language) '所有主题语言组合原子保存并读回'
        }
    }
    Assert-Panel (@(Get-ChildItem -LiteralPath $temp -Filter '*.tmp').Count -eq 0) '成功保存无遗留临时文件'
    $before = [IO.File]::ReadAllBytes($path)
    $rejected = $false
    try { Save-JobsPanelPreferences 'blue' 'en' -Path $path } catch { $rejected = $true }
    Assert-Panel ($rejected -and [Convert]::ToBase64String($before) -ceq [Convert]::ToBase64String([IO.File]::ReadAllBytes($path))) '无效枚举拒绝且旧文件逐字保留'
    [IO.File]::WriteAllText($path, '{"Theme":"unknown","Language":"fr"}')
    $unknown = Read-JobsPanelPreferences -Path $path
    Assert-Panel ($unknown.Theme -ceq 'system' -and $unknown.Language -ceq 'system') '未知枚举回退系统'
    [IO.File]::WriteAllText($path, '{broken json')
    $broken = Read-JobsPanelPreferences -Path $path
    Assert-Panel ($broken.Theme -ceq 'system' -and $broken.Language -ceq 'system' -and $broken.Error.Length -gt 0) '坏设置回退系统并保留诊断'
    Assert-Panel ([IO.File]::ReadAllText($path) -ceq '{broken json') '坏设置不会自动被覆盖'
    foreach ($culture in @('zh-TW', 'zh-HK', 'zh-MO', 'zh-Hant', 'zh-Hant-CN')) { Assert-Panel ((Resolve-JobsPanelLanguage -SystemLanguage $culture) -ceq 'zh-Hant') '繁体UI语言映射' }
    foreach ($culture in @('zh', 'zh-CN', 'zh-SG', 'zh-Hans', 'zh-Hans-HK')) { Assert-Panel ((Resolve-JobsPanelLanguage -SystemLanguage $culture) -ceq 'zh-Hans') '简体及显式Hans映射' }
    foreach ($culture in @('en-US', 'fr-FR', 'ja-JP', 'de-DE')) { Assert-Panel ((Resolve-JobsPanelLanguage -SystemLanguage $culture) -ceq 'en') '未支持系统语言英文回退' }
    Assert-Panel ((Resolve-JobsPanelLanguage -Preference 'zh-Hant' -SystemLanguage en-US) -ceq 'zh-Hant') '显式语言覆盖系统'
    Assert-Panel ((Resolve-JobsPanelTheme -SystemDark $true) -ceq 'dark' -and (Resolve-JobsPanelTheme -SystemDark $false) -ceq 'light') '系统亮暗两种变化'
    Assert-Panel ((Resolve-JobsPanelTheme -Preference light -SystemDark $true) -ceq 'light') '显式主题覆盖系统'
    $packages = @(Get-JobsFeaturePackages -Root $root)
    $features = @(Get-JobsSelectableFeatures -Packages $packages)
    $texts = @($packages | ForEach-Object { $_.Label; $_.Description }) + @($features | ForEach-Object { $_.Label; if ($null -ne $_.PSObject.Properties['Group']) { $_.Group } })
    foreach ($text in $texts) {
        $english = Get-JobsPanelText $text en
        Assert-Panel ($english -notmatch '[\u3400-\u9fff]') ('当前清单英文资源齐全：' + $text)
        Assert-Panel ((Get-JobsPanelText $text zh-Hans) -ceq $text) '简体文本保持原样'
    }
    Assert-Panel ((Get-JobsPanelText '安装 / 更新' zh-Hant) -ceq '安裝 / 更新') '繁体切换使用内置资源'
    $count = '已选 12 / 81 项；关闭或取消窗口不执行操作。'
    Assert-Panel ((Get-JobsPanelText $count en) -ceq 'Selected 12 / 81. Closing or cancelling makes no changes.') '动态选中数量可翻译'
    $progress = '安装 / 更新中；已处理 12 / 81 项（14.8%，按完成项计数）；安装用时 100:01:23'
    Assert-Panel ((Get-JobsPanelText $progress en) -ceq 'Install / update in progress; completed 12 / 81 (14.8% by completed items); Install time 100:01:23') '动态进度保留数量百分比及累计小时'
    $sourcePath = 'C:\安装\已完成\卸载\日志.txt'
    Assert-Panel ((Get-JobsPanelText ('读取日志失败：' + $sourcePath) en) -ceq ('Could not read the log: ' + $sourcePath)) '诊断中的中文路径完整保留'
    Assert-Panel ((Get-JobsPanelText $sourcePath en) -ceq $sourcePath) '未知路径不参与词语替换'
    foreach ($language in @('en', 'zh-Hant', 'zh-Hans', 'en', 'zh-Hant')) { Assert-Panel ((Get-JobsPanelText $count $language).Contains('12')) '重复切换从原文重算数值不丢失' }
    $tooltipChecks = & $module {
        $tip = [pscustomobject]@{ Text = '' }
        $tip | Add-Member ScriptMethod SetToolTip { param($Control, $Text) $this.Text = $Text }
        $state = [pscustomobject]@{ Language = 'en'; FeatureStates = @{ fixture = 'Failed' }; FeatureLabels = @{ fixture = [pscustomobject]@{} }; ToolTip = $tip; LogPath = 'C:\安装\已完成\日志.txt' }
        $message = "原始卸载错误`r`nC:\安装\已完成\原始.log"
        Set-JobsPanelFeatureToolTip $state fixture $message
        $english = $tip.Text
        $state.Language = 'zh-Hant'
        Set-JobsPanelFeatureToolTip $state fixture $message
        [pscustomobject]@{ English = $english; Traditional = $tip.Text; Message = $message; Path = $state.LogPath }
    }
    Assert-Panel ($tooltipChecks.English.StartsWith($tooltipChecks.Message) -and $tooltipChecks.Traditional.StartsWith($tooltipChecks.Message)) '失败消息包含中文路径和换行也逐字保留'
    Assert-Panel ($tooltipChecks.English.EndsWith($tooltipChecks.Path) -and $tooltipChecks.Traditional.EndsWith($tooltipChecks.Path)) '失败日志定位路径逐字保留'
    Assert-Panel ($tooltipChecks.English.Contains('Click to read the full session log') -and $tooltipChecks.Traditional.Contains('點擊在新 PowerShell 窗口讀取')) '同一失败项固定提示跟随英文和繁体切换'
    # 几何模型不依赖WinForms，覆盖中英宽度、缩放、窄窗与右上角重定位。
    foreach ($scale in @(1.0, 1.5, 2.0)) {
        foreach ($english in @($false, $true)) {
            $titleWidth = 240; $themeWidth = 32; $languageWidth = 32
            if ($english) { $titleWidth = 300; $themeWidth = 58; $languageWidth = 80 }
            $arguments = @{ Padding = [int](20 * $scale); Scale = $scale; TitleWidth = [int]($titleWidth * $scale); TitleHeight = [int](24 * $scale); ThemeLabelWidth = [int]($themeWidth * $scale); LanguageLabelWidth = [int]($languageWidth * $scale); ChoiceWidth = [int](140 * $scale); ControlHeight = [int](28 * $scale) }
            foreach ($baseWidth in @(480, 680, 1280, 1600)) {
                $width = [int]($baseWidth * $scale)
                $layout = Get-JobsPanelHeaderLayout -Width $width @arguments
                Assert-Panel ($layout.PreferenceLeft + $layout.PreferenceWidth -eq $width - $arguments.Padding) '工具组始终按内容右边距对齐'
                Assert-Panel ($layout.PreferenceLeft -ge $arguments.Padding -and $layout.PreferenceTop -ge $arguments.Padding) '窄窗与高DPI的工具组仍在内容范围'
                Assert-Panel ($layout.ThemeChoiceLeft + $arguments.ChoiceWidth -le $layout.PreferenceWidth -and $layout.LanguageChoiceLeft + $arguments.ChoiceWidth -le $layout.PreferenceWidth) '两组标签下拉都在工具容器内'
                Assert-Panel ($layout.DetailsTop -ge $layout.PreferenceTop + $layout.PreferenceHeight -and $layout.DetailsTop -ge $layout.TitleTop + $arguments.TitleHeight) '正文不与标题或工具组重叠'
                if ($layout.Inline) {
                    Assert-Panel ($layout.PreferenceTop -eq $arguments.Padding -and $layout.TitleTop -lt $arguments.Padding + $arguments.ControlHeight) '常规宽屏工具组与标题共用顶行'
                    Assert-Panel ($arguments.Padding + $layout.TitleWidth -lt $layout.PreferenceLeft) '同排标题与工具组留出间距'
                    Assert-Panel ($layout.DetailsTop -le $arguments.Padding + $arguments.ControlHeight + [int][Math]::Ceiling(8 * $scale)) '同排不额外预留整行空白'
                } else {
                    Assert-Panel ($layout.PreferenceTop -ge $layout.TitleTop + $arguments.TitleHeight + [int][Math]::Ceiling(8 * $scale)) '窄窗换行保留完整标题'
                }
                if ($layout.Stacked) {
                    Assert-Panel ($layout.LanguageTop -ge $arguments.ControlHeight + [int][Math]::Ceiling(8 * $scale)) '极窄窗口两组选择上下排无重叠'
                    Assert-Panel ($layout.ThemeChoiceLeft -eq $layout.LanguageChoiceLeft) '上下两行下拉保持同一右边界'
                }
                if ($baseWidth -ge 1280) { Assert-Panel $layout.Inline '宽屏中英及高DPI都共用顶行' }
            }
            $normal = Get-JobsPanelHeaderLayout -Width ([int](1280 * $scale)) @arguments
            $expanded = Get-JobsPanelHeaderLayout -Width ([int](1600 * $scale)) @arguments
            Assert-Panel ($expanded.PreferenceLeft - $normal.PreferenceLeft -eq [int](320 * $scale)) '窗口变宽只平移工具组至新右上角'
        }
    }
    foreach ($scale in @(1.0, 1.5, 2.0)) {
        foreach ($english in @($false, $true)) {
            $routeWidth = 220; $autoWidth = 220; $buttonWidth = 150
            if ($english) { $routeWidth = 330; $autoWidth = 320; $buttonWidth = 180 }
            $metrics = @{ Scale = $scale; RouteWidth = [int]($routeWidth * $scale); RouteHeight = [int](26 * $scale); AutoCleanupWidth = [int]($autoWidth * $scale); AutoCleanupHeight = [int](30 * $scale); CleanupButtonWidth = [int]($buttonWidth * $scale); CleanupButtonHeight = [int](32 * $scale) }
            foreach ($width in @([int](540 * $scale), [int](980 * $scale), [int](1240 * $scale))) {
                $row = Get-JobsPanelDeploymentRowLayout -AvailableWidth $width -CleanupVisible $true @metrics
                $routeCenter = $row.RouteTop + $metrics.RouteHeight / 2.0
                $autoCenter = $row.AutoCleanupTop + $metrics.AutoCleanupHeight / 2.0
                $buttonCenter = $row.CleanupButtonTop + $metrics.CleanupButtonHeight / 2.0
                Assert-Panel ([Math]::Abs($routeCenter - $autoCenter) -le 1 -and [Math]::Abs($routeCenter - $buttonCenter) -le 1) '三语宽度与DPI下部署行控件共用中心线'
                Assert-Panel ($row.CleanupLeft -ge $row.RouteWidth + [int][Math]::Ceiling(12 * $scale)) '位置下拉和清理选项之间保持间隔'
                Assert-Panel ($row.CleanupButtonLeft -ge $metrics.AutoCleanupWidth + [int][Math]::Ceiling(12 * $scale)) '自动清理文案与独立按钮之间保持间隔'
                Assert-Panel ($row.CleanupLeft + $row.CleanupWidth -eq $row.ContentWidth) '清理按钮贴部署行内容右边界'
                Assert-Panel ($row.RouteWidth -ge $metrics.RouteWidth -and $row.RowHeight -eq $metrics.CleanupButtonHeight) '窄窗不压缩文案宽度也不把控件拆成两行'
                if ($width -ge [int](980 * $scale)) { Assert-Panel (-not $row.ScrollRequired -and $row.ContentWidth -eq $width) '常规宽屏中英控件完整同排且无横向滚动' }
                else { Assert-Panel ($row.ScrollRequired -and $row.ContentWidth -gt $width) '窄窗完整同排并由水平滚动承接溢出' }
                $build = Get-JobsPanelDeploymentRowLayout -AvailableWidth $width -CleanupVisible $false @metrics
                Assert-Panel ($build.CleanupWidth -eq 0 -and $build.ContentWidth -eq [Math]::Max($width, $metrics.RouteWidth) -and $build.RowHeight -eq $metrics.RouteHeight) '构建目录隐藏清理控件后下拉独占本行，无多余行高'
            }
        }
    }
    $main = Join-Path $root 'Scripts/Installer.psm1'
    $hash = (Get-FileHash -LiteralPath $main).Hash
    $copies = @((Join-Path $root 'Scripts/SelectionPanel.psm1'), (Join-Path $root 'Infrastructure/SelectionPanel.psm1')) + @(Get-ChildItem -LiteralPath $root -Directory -Filter 'Jobs*' | ForEach-Object { Join-Path $_.FullName 'Scripts/SelectionPanel.psm1' } | Where-Object { Test-Path -LiteralPath $_ })
    foreach ($copy in $copies) {
        Assert-Panel ((Get-FileHash -LiteralPath $copy).Hash -ceq $hash) '总面板、模板与独立包同字节'
        $bytes = [IO.File]::ReadAllBytes($copy)
        Assert-Panel ($bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) 'PowerShell5.1中文保留UTF8 BOM'
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($copy, [ref]$null, [ref]$errors)
        Assert-Panel (@($errors).Count -eq 0) '所有面板副本语法通过'
    }
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        Save-JobsPanelPreferences light zh-Hans -Path $path
        $fixture = @([pscustomobject]@{ Id = 'fixture'; Label = '📋 复制绝对路径'; Description = '复制文件或文件夹的绝对路径。'; Group = '本功能' })
        $state = & $module { param($Items, $Path) New-JobsFeatureSelectionForm -Packages $Items -Selected @('fixture') -Installed @() -Mode Manage -PreferencesPath $Path } $fixture $path
        try {
            $originalForm = $state.Form
            $state.LogView.Text = "日志原文`r`nC:\安装\日志.txt"
            $state.LogView.Select(1, 3)
            $savedLog = $state.LogView.Text
            $state.Running = $true
            $state.FeatureStates['fixture'] = 'Running'
            foreach ($theme in @('dark', 'light')) {
                foreach ($language in @('en', 'zh-Hant', 'zh-Hans')) {
                    $state.Preferences.Theme = $theme; $state.Preferences.Language = $language
                    Update-JobsPanelPresentation $state -Force
                    Assert-Panel (-not $state.HeaderLabel.Bounds.IntersectsWith($state.PreferencePanel.Bounds) -and -not $state.HeaderDetailsLabel.Bounds.IntersectsWith($state.PreferencePanel.Bounds)) '三语工具组不遮挡页眉标题和正文'
                    Assert-Panel ($state.PreferencePanel.Right -eq $state.Form.ClientSize.Width - $state.Padding) '三语工具组右边距一致'
                    Assert-Panel ($state.ThemeBox.Height -eq $state.LanguageBox.Height -and $state.ThemeLabel.Height -eq $state.ThemeBox.Height -and $state.LanguageLabel.Height -eq $state.LanguageBox.Height) '主题语言标签与下拉同高并垂直居中'
                    $routeCenter = $state.RouteBox.Top + $state.RouteBox.Height / 2.0
                    $autoCenter = $state.CleanupPanel.Top + $state.AutoCleanup.Top + $state.AutoCleanup.Height / 2.0
                    $buttonCenter = $state.CleanupPanel.Top + $state.CleanupButton.Top + $state.CleanupButton.Height / 2.0
                    Assert-Panel ([Math]::Abs($routeCenter - $autoCenter) -le 1 -and [Math]::Abs($routeCenter - $buttonCenter) -le 1) '原生三语位置自动清理与独立按钮同排垂直居中'
                    Assert-Panel ([object]::ReferenceEquals($state.RouteBox.Parent, $state.DeploymentRow) -and [object]::ReferenceEquals($state.CleanupPanel.Parent, $state.DeploymentRow)) '位置和清理控件共用同一部署行'
                    Assert-Panel ($state.CleanupPanel.Left -ge $state.RouteBox.Right + [int](12 * $state.Scale)) '原生位置下拉不覆盖清理控件'
                    Assert-Panel ($state.AutoCleanup.Right + [int](12 * $state.Scale) -le $state.CleanupButton.Left) '原生自动清理文案不覆盖按钮'
                    Assert-Panel ($state.DeploymentRow.AutoScroll -and $state.DeploymentRow.AutoScrollMinSize.Width -ge $state.CleanupPanel.Right) '窄窗可水平访问完整部署行'
                    Assert-Panel ([object]::ReferenceEquals($state.Form, $originalForm) -and $state.Running -and $state.Checks[0].Checked -and $state.FeatureStates.fixture -eq 'Running') '活动任务换肤换语保留窗口事务与勾选'
                    Assert-Panel ($state.LogView.Text -ceq $savedLog -and $state.LogView.SelectionStart -eq 1 -and $state.LogView.SelectionLength -eq 3) '旧日志文本与选择保持'
                    $state.LogView.SelectAll()
                    Assert-Panel ($state.LogView.SelectionColor.ToArgb() -eq $state.LogView.ForeColor.ToArgb()) '旧日志随主题重着色'
                    $state.LogView.Select(1, 3)
                    foreach ($button in @($state.ConfirmButton, $state.CancelButton, $state.SelectAllButton, $state.ClearButton)) {
                        Assert-Panel ($button.GetPreferredSize((New-Object Drawing.Size(0, 0))).Width -le $button.Width) '三语底部按钮完整显示'
                    }
                }
            }
            $savedSize = $state.Form.ClientSize
            foreach ($width in @([int](680 * $state.Scale), [int](1280 * $state.Scale), [int](1600 * $state.Scale))) {
                $state.Form.ClientSize = New-Object Drawing.Size($width, $savedSize.Height)
                $state.Form.PerformLayout()
                Assert-Panel ($state.PreferencePanel.Right -eq $state.Form.ClientSize.Width - $state.Padding) 'ClientSize变化自动重定位右上工具组'
                Assert-Panel (-not $state.HeaderLabel.Bounds.IntersectsWith($state.PreferencePanel.Bounds)) '调整宽度后标题与工具组不重叠'
                Assert-Panel ($state.Running -and $state.Checks[0].Checked -and $state.LogView.Text -ceq $savedLog) '调整宽度保留活动任务勾选和日志'
            }
            $state.Form.ClientSize = $savedSize
            $rawMessage = "外部卸载错误`r`nC:\安装\已完成\原始.log"
            Set-JobsManagementFeatureState $state @('fixture') Failed $rawMessage
            foreach ($language in @('en', 'zh-Hant')) {
                $state.Preferences.Language = $language
                Update-JobsPanelPresentation $state -Force
                $tip = $state.ToolTip.GetToolTip($state.FeatureLabels.fixture)
                Assert-Panel ($tip.StartsWith($rawMessage) -and $tip.EndsWith($state.LogPath)) '运行中失败行切语言保留原始诊断和路径'
                $hint = Get-JobsPanelText '点击在新 PowerShell 窗口读取本次完整会话日志；当前任务继续运行。' $language
                Assert-Panel ($tip.Contains($hint) -and $state.FeatureLabels.fixture.Links.Count -eq 1) '失败链接提示即时换语并保持可点击'
            }
            $state.Running = $false
        } finally { $state.Form.Dispose(); $state.LogView.Font.Dispose(); $state.Font.Dispose(); $state.ToolTip.Dispose(); $state.Timer.Dispose() }
    } else { Write-Host 'SKIP: WinForms原生主题、三语布局和系统跟随交互需在Windows运行；跨平台偏好、资源和语法已覆盖。' }
} finally {
    if ([IO.Directory]::Exists($temp)) { [IO.Directory]::Delete($temp, $true) }
}
Write-Host ('PASS: PanelPreferences.Tests.ps1 (' + $script:assertions + ' assertions)')

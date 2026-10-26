# FlutterFeatureSelection.Tests.ps1 | 子菜单选择、兼容和部分卸载
# Created by Jobs on 2026年10月24日，星期六.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$count = 0
function Assert($value, $message) { $script:count++; if (-not $value) { throw $message } }
function Assert-Throws([scriptblock]$Body, [string]$Message) {
    $failed = $false
    try { & $Body | Out-Null } catch { $failed = $true }
    Assert $failed $Message
}
Import-Module (Join-Path $root 'Scripts/Catalog.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/FeatureActions.psm1') -Force -DisableNameChecking
$packages = @(Get-JobsFeaturePackages -Root $root)
$features = @(Get-JobsSelectableFeatures -Packages $packages)
$actions = @(Get-JobsFlutterActionCatalog)
Assert ($actions.Count -eq 14) '列出全部现有 Windows Flutter 叶动作'
Assert ($features.Count -eq $packages.Count + 13) '总面板展开单包而不重复显示包级复选框'
Assert (@($features | Where-Object { $_.Id -ceq 'flutter-tools' }).Count -eq 0) '只有可实际执行的子功能可选'
$header = [IO.File]::ReadAllText((Join-Path $root 'JobsFlutterTools/Scripts/FlutterToolsMenu.h'))
$matches = [regex]::Matches($header, '\{L"([a-z-]+)", L"([^"]+)"\}')
Assert ($matches.Count -eq $actions.Count) '选择目录与原生动作数量相同'
for ($i = 0; $i -lt $actions.Count; $i++) {
    Assert ($matches[$i].Groups[1].Value -ceq $actions[$i].Id -and $matches[$i].Groups[2].Value -ceq $actions[$i].Label) ('动作标识和标签同源核对：' + $actions[$i].Id)
    $plan = @(Get-JobsPackageOperationPlan -Packages $packages -Selected @('flutter-' + $actions[$i].Id) -Installed @('flutter-tools') -Mode Install)
    Assert ($plan.Count -eq 1 -and $plan[0].Id -ceq 'flutter-tools' -and @($plan[0].ActionIds).Count -eq 1 -and $plan[0].ActionIds[0] -ceq $actions[$i].Id) '逐项安装精确替换旧全开状态'
}
$legacy = @(Expand-JobsFeatureSelection -Packages $packages -Selected @('flutter-tools'))
Assert ($legacy.Count -eq 14) '旧总体功能标识保持全选兼容'
$plan = @(Get-JobsPackageOperationPlan -Packages $packages -Selected @('flutter-run') -Installed @('flutter-run', 'flutter-codegen') -Mode Uninstall)
Assert ($plan.Count -eq 1 -and $plan[0].Mode -ceq 'Install' -and @($plan[0].ActionIds).Count -eq 1 -and $plan[0].ActionIds[0] -ceq 'codegen') '部分卸载仅保留其它叶功能'
$plan = @(Get-JobsPackageOperationPlan -Packages $packages -Selected @('flutter-run') -Installed @('flutter-run') -Mode Uninstall)
Assert ($plan.Count -eq 1 -and $plan[0].Mode -ceq 'Uninstall') '移除最后一项时卸载整个菜单包'
Assert (@(Get-JobsPackageOperationPlan -Packages $packages -Selected @() -Installed @('flutter-run') -Mode Install).Count -eq 0) '安装不选整个Flutter组时保留已安装组'
$plan = @(Get-JobsPackageOperationPlan -Packages $packages -Selected @() -Installed @('flutter-run') -Mode Configure)
Assert ($plan.Count -eq 1 -and $plan[0].Mode -ceq 'Uninstall') '配置全不选可关闭Flutter组'
Assert-Throws { Expand-JobsFeatureSelection -Packages $packages -Selected @('flutter-unknown') } '未知叶动作拒绝进入计划'
Assert (@(Get-JobsFlutterStateActionIds -Settings ([pscustomobject]@{ Version = 2 })).Count -eq 14) '旧设置缺ActionIds保持全开'
Assert (@(Get-JobsFlutterStateActionIds -Settings ([pscustomobject]@{ ActionIds = @('codegen') }))[0] -ceq 'codegen') '单项数组只启用该动作'
Assert (@(Get-JobsFlutterStateActionIds -Settings ([pscustomobject]@{ ActionIds = @() })).Count -eq 0) '空数组不复活任何动作'
Assert-Throws { Get-JobsFlutterStateActionIds -Settings ([pscustomobject]@{ ActionIds = 'run' }) } '标量配置拒绝'
Assert-Throws { Get-JobsFlutterStateActionIds -Settings ([pscustomobject]@{ ActionIds = @('run', 'run') }) } '重复配置拒绝'
Assert-Throws { Get-JobsFlutterStateActionIds -Settings ([pscustomobject]@{ ActionIds = @('unknown') }) } '未知配置拒绝'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('jobs-flutter-selection-' + [guid]::NewGuid().ToString('N'))
try {
    [void][IO.Directory]::CreateDirectory((Join-Path $fixture 'Scripts'))
    $stub = @'
function Invoke-JobsPackageChange {
    param([string]$PackagePath, [string]$Mode, [string[]]$ActionIds)
    if ($Mode -cne 'Install' -or @($ActionIds).Count -ne 2 -or ($ActionIds -join ',') -cne 'run,codegen') { throw 'leaf choices were lost in lifecycle dispatch' }
}
Export-ModuleMember -Function Invoke-JobsPackageChange
'@
    [IO.File]::WriteAllText((Join-Path $fixture 'Scripts/PackageInstaller.psm1'), $stub)
    $result = Invoke-JobsPackageOperations -Plan @([pscustomobject]@{ Id = 'flutter-tools'; PackagePath = $fixture; Mode = 'Install'; ActionIds = @('run', 'codegen') })
    Assert ($result.Success -and $result.Completed[0] -ceq 'Install:flutter-tools') '两项选择经真实编排调用只进入一次包生命周期且保持数组'
} finally {
    foreach ($loaded in @(Get-Module | Where-Object { $_.Path -and $_.Path.StartsWith($fixture, [StringComparison]::OrdinalIgnoreCase) })) { Remove-Module $loaded }
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
    $ui = Import-Module (Join-Path $root 'Scripts/Installer.psm1') -PassThru -DisableNameChecking
    $state = & $ui { param($Items) New-JobsFeatureSelectionForm -Packages $Items -Selected @() -Mode Install } $features
    try {
        Assert (@($state.Checks).Count -eq $features.Count -and $state.Groups.Count -eq 4) '真实面板包含全部叶功能及用途分组'
        Assert ($state.ContentPanel.AutoScroll -and $state.Footer.Dock -eq [Windows.Forms.DockStyle]::Bottom) '仅内容区滚动且操作区固定'
        $group = @($state.Groups | Where-Object { $_.Name -ceq 'Flutter 项目体检' })[0]
        $click = $group.All.GetType().GetMethod('OnClick', [Reflection.BindingFlags]'Instance,NonPublic')
        [void]$click.Invoke($group.All, @([EventArgs]::Empty))
        Assert (@($state.Checks | Where-Object Checked).Count -eq 2 -and $group.Counter.Text -eq '已选 2 / 2') '组内全选只勾选本组且更新计数'
        [void]$click.Invoke($group.None, @([EventArgs]::Empty))
        Assert (@($state.Checks | Where-Object Checked).Count -eq 0 -and -not $state.ConfirmButton.Enabled -and $null -eq $state.Form.AcceptButton) '组内全不选恢复空选门禁'
    } finally { $state.Form.Dispose(); $state.ToolTip.Dispose(); $state.Font.Dispose() }
}
Write-Host ('PASS: FlutterFeatureSelection.Tests.ps1 (' + $count + ' assertions; no registry writes)')

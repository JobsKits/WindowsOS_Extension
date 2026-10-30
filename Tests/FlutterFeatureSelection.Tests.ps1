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
Assert ($actions.Count -eq 36) '列出全部现有 Windows Flutter 叶动作'
$stableOrder = 'run,pub-get,android-dependencies,ohos-dependencies,native-dependencies,flutter-precache,web-dependencies,extract,import-dependencies,export-gradle-dependencies,import-gradle-dependencies,export-ohos-dependencies,import-ohos-dependencies,export-native-dependencies,import-native-dependencies,export-precache-dependencies,import-precache-dependencies,export-web-dependencies,import-web-dependencies,sdk-version,sdk-manage,ohos-sdk-manage,java-manage,gradle-download,project-setup,package,build-harmony,codegen,native-doctor,harmony-doctor,maintenance,repair-android,repair-imports,repair-namespace,export-private-dependencies,import-private-dependencies'
Assert (($actions.Id -join ',') -ceq $stableOrder) '重分组不改原34个ID与偏移保持顺序，新私库动作追加'
$groupContract = [ordered]@{
    '📥 拉取Flutter项目工程相关依赖' = @('pub-get','android-dependencies','ohos-dependencies','web-dependencies')
    '🧩 提取Flutter项目工程依赖' = @('extract','export-gradle-dependencies','export-ohos-dependencies','export-native-dependencies','export-precache-dependencies','export-web-dependencies','export-private-dependencies')
    '📤 导入Flutter项目工程依赖' = @('import-dependencies','import-gradle-dependencies','import-ohos-dependencies','import-native-dependencies','import-precache-dependencies','import-web-dependencies','import-private-dependencies')
    '🔀 安装/切换Flutter运行环境' = @('sdk-manage','ohos-sdk-manage','java-manage')
    '🧱 Flutter 资源与构建依赖' = @('native-dependencies','flutter-precache','gradle-download')
    '🏥 Flutter项目体检' = @('sdk-version','native-doctor','harmony-doctor')
}
foreach ($group in $groupContract.Keys) {
    $actualIds = @($actions | Where-Object { $_.Group -ceq $group } | ForEach-Object Id)
    Assert (($actualIds -join ',') -ceq ($groupContract[$group] -join ',')) ('精确父分组及完整叶集合：' + $group)
}
Assert (@($actions | Where-Object { $_.Id -ceq 'native-dependencies' })[0].Group -ceq '🧱 Flutter 资源与构建依赖') '组合操作归入资源与构建依赖组'
Assert (@($actions | Where-Object { $_.Id -ceq 'native-dependencies' })[0].Label -ceq '🧱 准备原生库与构建依赖（组合操作）') '组合操作在菜单与管理面板醒目标识'
$exactLabels = @{
    'sdk-manage' = '🔀 安装/切换Flutter SDK'
    'ohos-sdk-manage' = '🕊️ 安装/切换Flutter@OpenHarmony SDK'
    'java-manage' = '☕ 安装/切换Java SDK'
    'flutter-precache' = '🗃️ 下载Flutter平台资源'
    'sdk-version' = '🔎 查看当前Flutter项目工程的SDK版本'
}
foreach ($id in $exactLabels.Keys) { Assert (@($actions | Where-Object { $_.Id -ceq $id })[0].Label -ceq $exactLabels[$id]) ('精确叶显示名：' + $id) }
Assert ($features.Count -eq $packages.Count + 35) '总面板展开单包而不重复显示包级复选框'
Assert (@($features | Where-Object { $_.Id -ceq 'flutter-tools' }).Count -eq 0) '只有可实际执行的子功能可选'
$header = [IO.File]::ReadAllText((Join-Path $root 'JobsFlutterTools/Scripts/FlutterToolsMenu.h'))
$entryBlock = [regex]::Match($header, '(?s)static const Entry Entries\[\]\s*=\s*\{(.*?)\n\};').Groups[1].Value
$matches = [regex]::Matches($entryBlock, '\{L"([a-z-]+)", L"([^"]+)"\}')
Assert ($matches.Count -eq $actions.Count) '选择目录与原生动作数量相同'
for ($i = 0; $i -lt $actions.Count; $i++) {
    Assert ($matches[$i].Groups[1].Value -ceq $actions[$i].Id -and $matches[$i].Groups[2].Value -ceq $actions[$i].Label) ('动作标识和标签同源核对：' + $actions[$i].Id)
    $plan = @(Get-JobsPackageOperationPlan -Packages $packages -Selected @('flutter-' + $actions[$i].Id) -Installed @() -Mode Install)
    Assert ($plan.Count -eq 1 -and $plan[0].Id -ceq 'flutter-tools' -and @($plan[0].ActionIds).Count -eq 1 -and $plan[0].ActionIds[0] -ceq $actions[$i].Id) '首次逐项安装只启用所选动作'
}
$dependencyActions = @('android-dependencies','ohos-dependencies','native-dependencies','flutter-precache','web-dependencies')
foreach ($id in $dependencyActions) {
    Assert (@($actions | Where-Object { $_.Id -ceq $id }).Count -eq 1) ('每类依赖各有单独菜单动作：' + $id)
    $plan = @(Get-JobsPackageOperationPlan -Packages $packages -Selected @('flutter-' + $id) -Installed @('flutter-run', ('flutter-' + $id)) -Mode Uninstall)
    Assert ($plan.Count -eq 1 -and $plan[0].Mode -ceq 'Install' -and ($plan[0].ActionIds -join ',') -ceq 'run') ('独立卸载依赖叶保留运行：' + $id)
}
foreach ($id in @('pods-dependencies','spm-dependencies')) {
    Assert (@($actions | Where-Object { $_.Id -ceq $id }).Count -eq 0) ('Windows 不增加 Apple 专属依赖入口：' + $id)
    Assert-Throws { Expand-JobsFeatureSelection -Packages $packages -Selected @('flutter-' + $id) } '不支持的平台叶不能进入安装计划'
}
Assert (@($actions | Where-Object { $_.Id -ceq 'pub-get' })[0].Label -ceq '📥 拉取 Flutter Pub 依赖') 'Pub 依赖与平台原生依赖明确区分'
Assert (@($actions | Where-Object { $_.Id -ceq 'gradle-download' })[0].Label -ceq '📚 下载Gradled分发与构建插件') 'Gradle 入口明确分发与构建插件范围'
$combined = @(Get-JobsPackageOperationPlan -Packages $packages -Selected @('flutter-codegen') -Installed @('flutter-run') -Mode Install)
Assert ($combined.Count -eq 1 -and ($combined[0].ActionIds -join ',') -ceq 'run,codegen') '安装一个动作不会关闭已启用的兄弟动作'
$replace = @(Get-JobsPackageOperationPlan -Packages $packages -Selected @('flutter-codegen') -Installed @('flutter-run') -Mode Configure)
Assert ($replace.Count -eq 1 -and ($replace[0].ActionIds -join ',') -ceq 'codegen') '显式配置模式仍按完整选择替换'
$legacy = @(Expand-JobsFeatureSelection -Packages $packages -Selected @('flutter-tools'))
Assert ($legacy.Count -eq 36) '旧总体功能标识保持全选兼容'
$plan = @(Get-JobsPackageOperationPlan -Packages $packages -Selected @('flutter-run') -Installed @('flutter-run', 'flutter-codegen') -Mode Uninstall)
Assert ($plan.Count -eq 1 -and $plan[0].Mode -ceq 'Install' -and @($plan[0].ActionIds).Count -eq 1 -and $plan[0].ActionIds[0] -ceq 'codegen') '部分卸载仅保留其它叶功能'
$plan = @(Get-JobsPackageOperationPlan -Packages $packages -Selected @('flutter-run') -Installed @('flutter-run') -Mode Uninstall)
Assert ($plan.Count -eq 1 -and $plan[0].Mode -ceq 'Uninstall') '移除最后一项时卸载整个菜单包'
Assert (@(Get-JobsPackageOperationPlan -Packages $packages -Selected @() -Installed @('flutter-run') -Mode Install).Count -eq 0) '安装不选整个Flutter组时保留已安装组'
$plan = @(Get-JobsPackageOperationPlan -Packages $packages -Selected @() -Installed @('flutter-run') -Mode Configure)
Assert ($plan.Count -eq 1 -and $plan[0].Mode -ceq 'Uninstall') '配置全不选可关闭Flutter组'
Assert-Throws { Expand-JobsFeatureSelection -Packages $packages -Selected @('flutter-unknown') } '未知叶动作拒绝进入计划'
Assert (@(Get-JobsFlutterStateActionIds -Settings ([pscustomobject]@{ Version = 2 })).Count -eq 36) '旧设置缺ActionIds保持全开'
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
        Assert (@($state.Checks).Count -eq $features.Count -and $state.Groups.Count -eq 9) '真实面板包含全部叶功能及用途分组'
        Assert ($state.ContentPanel.AutoScroll -and $state.Footer.Dock -eq [Windows.Forms.DockStyle]::Bottom) '仅内容区滚动且操作区固定'
        $group = @($state.Groups | Where-Object { $_.Name -ceq '🏥 Flutter项目体检' })[0]
        $click = $group.All.GetType().GetMethod('OnClick', [Reflection.BindingFlags]'Instance,NonPublic')
        [void]$click.Invoke($group.All, @([EventArgs]::Empty))
        Assert (@($state.Checks | Where-Object Checked).Count -eq 3 -and $group.Counter.Text -eq '已选 3 / 3') '组内全选只勾选本组且更新计数'
        [void]$click.Invoke($group.None, @([EventArgs]::Empty))
        Assert (@($state.Checks | Where-Object Checked).Count -eq 0 -and -not $state.ConfirmButton.Enabled -and $null -eq $state.Form.AcceptButton) '组内全不选恢复空选门禁'
    } finally { $state.Form.Dispose(); $state.ToolTip.Dispose(); $state.Font.Dispose() }
}
Write-Host ('PASS: FlutterFeatureSelection.Tests.ps1 (' + $count + ' assertions; no registry writes)')

# FeatureActions.psm1 | JobsFlutterTools 子菜单选择与兼容
# Created by Jobs on 2026年10月24日，星期六.
Set-StrictMode -Version 2.0

function Get-JobsFlutterActionCatalog {
    $groups = @('Flutter 开发辅助', 'Flutter 项目体检', 'Flutter 项目修复')
    $rows = @(
        @('run', '从终端运行 Flutter 项目', 0),
        @('pub-get', '拉取Flutter第三方依赖', 0),
        @('extract', '提取Flutter第三方依赖', 0),
        @('sdk-version', '查看当前Flutter项目的SDK版本', 0),
        @('sdk-manage', '安装/切换Flutter SDK版本', 0),
        @('ohos-sdk-manage', '安装/切换 Flutter@OpenHarmony SDK', 0),
        @('package', 'Flutter打包', 0),
        @('codegen', 'Flutter自动化生产代码', 0),
        @('native-doctor', '原生Flutter项目体检', 1),
        @('harmony-doctor', 'OpenHarmony Flutter 环境体检', 1),
        @('maintenance', 'Flutter清理维护工具', 0),
        @('repair-android', '修复 Android SDK / platforms 缺失', 2),
        @('repair-imports', '修复 Flutter 项目中文路径', 2),
        @('repair-namespace', '修复 Flutter 插件 namespace', 2)
    )
    foreach ($row in $rows) {
        [pscustomobject]@{ Id = [string]$row[0]; Label = [string]$row[1]; Group = $groups[[int]$row[2]] }
    }
}

function Resolve-JobsFlutterActionIds {
    param([AllowEmptyCollection()][object[]]$ActionIds)
    $catalog = @(Get-JobsFlutterActionCatalog)
    $seen = @{}
    foreach ($id in @($ActionIds)) {
        if ($id -isnot [string] -or $id -cnotin @($catalog.Id) -or $seen.ContainsKey($id)) {
            throw ('Flutter 子功能配置无效：' + $id)
        }
        $seen[$id] = $true
    }
    foreach ($entry in $catalog) { if ($seen.ContainsKey($entry.Id)) { $entry.Id } }
}

function Get-JobsFlutterStateActionIds {
    param($Settings)
    if ($null -eq $Settings.PSObject.Properties['ActionIds']) { return @(Get-JobsFlutterActionCatalog | ForEach-Object { $_.Id }) }
    if ($Settings.ActionIds -isnot [Array]) { throw 'Flutter ActionIds 必须是数组。' }
    return @(Resolve-JobsFlutterActionIds -ActionIds @($Settings.ActionIds))
}

Export-ModuleMember -Function Get-JobsFlutterActionCatalog, Resolve-JobsFlutterActionIds, Get-JobsFlutterStateActionIds

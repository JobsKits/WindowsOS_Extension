# FeatureActions.psm1 | JobsFlutterTools 子菜单选择与兼容
# Created by Jobs on 2026年10月24日，星期六.
Set-StrictMode -Version 2.0

function Get-JobsFlutterActionCatalog {
    $groups = @('🦋 Flutter 开发辅助', '🏥 Flutter项目体检', '🔧 Flutter 项目修复', '📥 拉取Flutter项目工程相关依赖', '🧩 提取Flutter项目工程依赖', '📤 导入Flutter项目工程依赖', '🔀 安装/切换Flutter运行环境', '🧱 Flutter 资源与构建依赖')
    $rows = @(
        @('run', '▶️ 从终端运行 Flutter 项目', 0),
        @('pub-get', '📥 拉取 Flutter Pub 依赖', 3),
        @('android-dependencies', '🤖 拉取 Android 原生依赖', 3),
        @('ohos-dependencies', '🕊️ 拉取 OpenHarmony 依赖', 3),
        @('native-dependencies', '🧱 准备原生库与构建依赖（组合操作）', 7),
        @('flutter-precache', '🗃️ 下载Flutter平台资源', 7),
        @('web-dependencies', '🌐 拉取 Web 工程依赖', 3),
        @('extract', '🧩 提取 Flutter Pub 依赖', 4),
        @('import-dependencies', '📤 导入 Flutter Pub 依赖', 5),
        @('export-gradle-dependencies', '🧩 提取 Gradle 分发与依赖缓存', 4),
        @('import-gradle-dependencies', '📤 导入 Gradle 分发与依赖缓存', 5),
        @('export-ohos-dependencies', '🧩 提取 OpenHarmony 依赖', 4),
        @('import-ohos-dependencies', '📤 导入 OpenHarmony 依赖', 5),
        @('export-native-dependencies', '🧩 提取 原生构建缓存', 4),
        @('import-native-dependencies', '📤 导入 原生构建缓存', 5),
        @('export-precache-dependencies', '🧩 提取 Flutter 平台资源', 4),
        @('import-precache-dependencies', '📤 导入 Flutter 平台资源', 5),
        @('export-web-dependencies', '🧩 提取 Web 依赖', 4),
        @('import-web-dependencies', '📤 导入 Web 依赖', 5),
        @('sdk-version', '🔎 查看当前Flutter项目工程的SDK版本', 1),
        @('sdk-manage', '🔀 安装/切换Flutter SDK', 6),
        @('ohos-sdk-manage', '🕊️ 安装/切换Flutter@OpenHarmony SDK', 6),
        @('java-manage', '☕ 安装/切换Java SDK', 6),
        @('gradle-download', '📚 下载Gradled分发与构建插件', 7),
        @('project-setup', '🚀 一键配置 Flutter 项目', 0),
        @('package', '📦 Flutter打包', 0),
        @('build-harmony', '📦 打包鸿蒙（HAP + APP）', 0),
        @('codegen', '⚙️ Flutter自动化生产代码', 0),
        @('native-doctor', '🧑‍⚕️ 原生Flutter项目体检', 1),
        @('harmony-doctor', '💓 OpenHarmony Flutter 环境体检', 1),
        @('maintenance', '♻️ Flutter清理维护工具', 0),
        @('repair-android', '🩹 修复 Android SDK / platforms 缺失', 2),
        @('repair-imports', '🈶 修复 Flutter 项目中文路径', 2),
        @('repair-namespace', '🏷️ 修复 Flutter 插件 namespace', 2),
        @('export-private-dependencies', '🔐 提取Flutter项目工程私库依赖', 4),
        @('import-private-dependencies', '📥 导入Flutter项目工程私库依赖', 5)
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

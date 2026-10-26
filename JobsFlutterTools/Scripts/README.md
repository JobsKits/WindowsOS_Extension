# Flutter 菜单实现

完整说明见 [README](../README.md)。`ContextMenu.cpp` / `FlutterToolsMenu.h` 固定菜单层级和动作顺序；`OpenCmd.ps1` / `Invoke.ps1` / `Action.psm1` 传递所选工程与固定动作。共享 Dart 引擎处理体检、URI / namespace 修复与维护。`Actions/` 自包含已有功能 worker；FVM 校验失败不会回退全局 Flutter。安装事务仅迁移本仓库固定旧 Flutter 入口。

`FeatureActions.psm1` 列出全部 14 项叶动作、显示名称及分组，并校验 `ActionIds` 数组。总面板用 `flutter-<动作>` 标识逐项选择，部署时合并为单个包操作，安装状态保存原始动作名。安装器在同一备份 / 回滚事务内原子发布包根 UTF-8 `menu-state.txt`（版本、当前 release、动作白名单，各行 LF，无 BOM），原生菜单每次读取当前指针，仅显示已选动作并隐藏空组，点击派发当前 release；卸载写空动作墓碑。release 根另存 ASCII `menu-actions.txt` 作为兼容文件。`Invoke.ps1` 再复核选择及当前 release。旧配置缺字段兼容全开，畸形配置停止。部分卸载重新部署剩余动作，最后一项移除时才注销整个包；独立安装入口仍默认全选。首次从旧 DLL 升级仍需用户重启 Explorer 或注销，后续选择通过稳定指针生效。

`HarmonySdk.psm1` 实现独立 `ohos-sdk-manage` 动作：CPF-Flutter tag 单选、commit 锁定、私有缓存、影子 FVM 体检及项目配置/链接发布。复用 `Actions/sdk-manage` 的 Git/FVM/fzf 健康检查和命令参数传递；真实项目仅发布 `.fvmrc` 和 `.fvm/flutter_sdk`，IDE、ignore 与源码保持原样，失败恢复及缓存范围见上级说明。`CheckHarmonySdk.ps1 -Target <项目根>` 只读展示计划，不联网、不运行工具、不写缓存。原生 SDK 选版仍由已有 `sdk-manage` worker 承接。

统一入口的 `sdk-manage` 分支可识别本工具管理的 CPF 绑定，由同一模块在影子项目完成 OpenHarmony → 官方原生 SDK 的切换，明确改用独立 `official` 缓存；其它情况继续调用原生 worker，未知 fork 和非官方有效来源在下载前拒绝。没有新增顶层扩展或跨包运行依赖。

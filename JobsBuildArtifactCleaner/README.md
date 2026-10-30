# JobsBuildArtifactCleaner

**最低支持系统：Windows 10 64 位（x64）。** 这是当前最低支持目标；具体最低 build 尚未锁定，完整实机兼容性仍待验证。最低基线不等于所有功能已经实测通过。

文件夹右键菜单“清理构建产物”。Windows 只支持 Flutter / Android，不提供 iOS 工程清理；Flutter 的 `ios/`、`macos/`、`build/ios/` 和 `build/macos/` 目录保留。

**系统兼容性：** 当前目标为 [**Windows**](https://www.microsoft.com/windows) 10 / 11 图形桌面，要求系统 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) 5.1 Desktop、.NET 与 STA；各系统版本和架构仍待实机验收，未锁定统一最低 build。XP / Vista / Windows 8 不支持当前入口；Windows 7 SP1 / 8.1 安装 [**WMF 5.1**](https://www.microsoft.com/en-us/download/details.aspx?id=54616)（要求 .NET Framework 4.5+）后，也仅可探索基础静态菜单，不构成对本包完整功能的支持承诺。Windows 11 使用“显示更多选项”或 `Shift+F10`；x86 / ARM64 均未获全功能实机兼容保证。

**本包依赖与测试范围：** 本包采用静态菜单，安装无需 MSVC，清理本身也不要求 Flutter SDK / Gradle。可先在虚拟机临时工程验收识别、预览、取消及删除边界，再在目标系统复核；菜单可安装与清理业务通过分别记录。

**管理操作：** 本目录以 `Manage.cmd` 为轻量启动入口，只唤起 GUI 后结束本次脚本；先在面板选择安装 / 更新或卸载。在面板确认安装 / 更新或卸载后立即执行，无二次终端确认。关闭或取消面板不执行；卸载保留日志、备份、运行文件和工具。

## 安装与使用

运行本目录 `Manage.cmd`，或在仓库总安装面板中勾选“清理构建产物”。单包可整体复制到其它位置独立安装，不需要其它功能包。使用 Windows PowerShell 5.1，无需管理员权限、Flutter SDK 或 Gradle。`Manage.cmd` 仅移除本功能菜单。

在资源管理器右键工程文件夹，或工程文件夹内空白处（Windows 11 的“显示更多选项”）。终端重新识别工程，列出类型、路径和实际存在的产物；先停止构建，再输入 `CLEAN` 删除，其它输入取消。未知目录 / iOS 工程会停止且不删除任何文件。静态菜单不在菜单展开时猜测项目类型。

## 识别与范围

仅识别传入目录，不向父级寻找工程；Flutter 优先于其 Android 子工程。

| 工程 | 识别条件 | 清理范围 |
| --- | --- | --- |
| Flutter | 同层 `pubspec.yaml`、`lib/`，清单声明 `sdk: flutter` | `build/`（存在 Apple 产物时仅清理其它子目录）、`.dart_tool/`，经识别的 `android/` 构建产物，Windows / Linux 的 `flutter/ephemeral/` |
| Android | Gradle 构建或 settings 文件，加 Android 插件或模块 `src/main/AndroidManifest.xml` | 根目录 `build/`、`.gradle/`、`.kotlin/`；本构建内有 Gradle 配置的模块 `build/`、`.cxx/`、`.externalNativeBuild/` |

普通 Dart / Java Gradle 不清理；嵌套独立 Gradle / Git / Flutter 工程不进入。不运行项目脚本、不联网，也不执行可能触及 Apple 平台的 `flutter clean`。源码、锁文件、依赖、Gradle wrapper、FVM SDK、签名和共享缓存保留。自定义输出路径不推断、不删除。

清理前整份计划验证，确认后重新识别；清理目标或其父目录是链接 / 联接时停止。产物内部的重解析项只删除链接本身，不递归到外部位置。读写或删除失败会明确报错；已经删除的产物不会回滚，需要重新构建。

## 验证

从仓库根运行 `pwsh -NoProfile -File Tests/BuildArtifactCleaner.Tests.ps1`，只使用临时夹具。配合 `Tests/Architecture.Tests.ps1`、`Tests/ActionModules.Tests.ps1`、`Tests/Catalog.Tests.ps1` 与 `Scripts/Sync-PackageInfrastructure.ps1` 检查单包部署、目录菜单计划、组合面板和共享机制一致性。Windows PowerShell 5.1 / Explorer 的真实交互需在 Windows 验收。

管理安装 / 卸载时双击 `Manage.cmd`，它只通过 WScript 唤起 GUI，随后立即结束本次脚本；不在 CMD 中编译、安装或等待输入。也可直接双击 `Manage.vbs` 进入同一面板。每个选项显示等待、执行中、完成或失败，底部实时滚动标准输出和错误，可选中复制或点击“复制全部日志”；无可靠百分比时显示执行中，总体显示完成项数。运行期间等当前事务结束后关闭，完整管理日志位于系统临时目录 `JobsExtensionManager-<运行编号>.log`。

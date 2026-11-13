# JobsBuildArtifactCleaner

**最低支持系统：Windows 10 64 位（x64）。** 这是当前最低支持目标；具体最低 build 尚未锁定，完整实机兼容性仍待验证。最低基线不等于所有功能已经实测通过。

文件夹右键菜单“清理构建产物”。Windows 只支持 Flutter / Android，不提供 iOS 工程清理；Flutter 的 `ios/`、`macos/`、`build/ios/` 和 `build/macos/` 目录保留。

**系统兼容性：** 当前目标为 [**Windows**](https://www.microsoft.com/windows) 10 / 11 图形桌面，要求系统 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) 5.1 Desktop、.NET 与 STA；各系统版本和架构仍待实机验收，未锁定统一最低 build。XP / Vista / Windows 8 不支持当前入口；Windows 7 SP1 / 8.1 安装 [**WMF 5.1**](https://www.microsoft.com/en-us/download/details.aspx?id=54616)（要求 .NET Framework 4.5+）后，也仅可探索基础静态菜单，不构成对本包完整功能的支持承诺。Windows 11 使用“显示更多选项”或 `Shift+F10`；x86 / ARM64 均未获全功能实机兼容保证。

**本包依赖与测试范围：** 本包采用静态菜单，安装无需 MSVC，清理本身也不要求 Flutter SDK / Gradle。可先在虚拟机临时工程验收识别、预览、取消及删除边界，再在目标系统复核；菜单可安装与清理业务通过分别记录。

**管理操作：** 本目录以 `Manage.cmd` 为轻量启动入口，只唤起 GUI 后结束本次脚本；先在面板选择安装 / 更新或卸载。在面板确认安装 / 更新或卸载后立即执行，无二次终端确认。关闭或取消面板不执行；卸载保留日志、备份、运行文件和工具。


**面板外观与语言：** 总面板和独立功能面板右上角均可选择“黑夜 / 白天 / 跟随系统”以及“简体中文 / 繁體中文 / བོད་ཡིག / English / 日本語 / Français / Español / Deutsch / Русский / 한국어 / 跟随系统”，默认均跟随系统，切换立即生效并保留当前勾选、任务和日志。窄窗或长文案放不下时，工具组移至标题下一行并保持右对齐；极窄窗口将主题、语言分两行，下拉控件右边缘对齐。选择保存在当前用户的 `%LOCALAPPDATA%\Jobs\WindowsExtension\panel-preferences.json`，下次打开自动恢复；保存失败在面板显示原因。跟随系统每秒检查应用主题和当前用户显示语言，繁体中文界面使用繁体、其它中文使用简体，其余已支持语种按系统语言匹配，未支持语言回退英文；Windows 显示语言通常须重新登录才生效。切换涵盖面板正文、功能说明、状态与动态计数、操作提示和辅助名称；藏文优先使用已安装 Microsoft Himalaya / Noto Sans Tibetan，日韩使用对应系统字体，缺失时回退。语言名称始终显示自称，图标、功能名和状态列独立，长文字换行；切换只影响管理面板，已安装右键菜单标题及后台工具的原始日志保持各自语言。共享完整译文以 `Scripts/ManagerPanelTranslations.json` 为编辑来源，发布时内嵌到同源面板模块，独立包无需访问兄弟目录或联网翻译。

**两种部署路线：** 源码管理面板默认使用“默认程序安装位置”，运行文件仍位于 `%LOCALAPPDATA%\Jobs\WindowsExtension\extensions\<功能ID>`。也可切换到“本地临时构建目录”，运行文件位于 `<功能包>\work\WindowsExtension\extensions\<功能ID>`；移走或清除该运行目录会使菜单失效。已部署副本的管理入口固定到自身真实路线，切换路线请从源码管理入口操作。菜单命令与 `deployment.json` 按当前路线定位配置，不依赖面板环境变量；提交失败恢复两侧状态。

**构建产物清理：** 安装位置选择、显示中的自动清理复选框与红色“🧹 清除构建产物”按钮排在同一行，垂直居中、间隔统一。英文或窄窗空间不足时，该行可水平滚动，文字保持完整，不拆成两行。仅默认安装位置路线显示默认关闭的“安装成功后清除此轮构建产物”和红底白字的“🧹 清除构建产物”独立按钮。自动清理仅处理本次成功安装产生的编译 GUID 子目录；独立按钮按当前选择清理本包 `work\JobsExtensionBuild` 专用编译工作区，不需要重新安装。临时路线隐藏清理控件。清理验证运行文件、标记与路径边界并持有事务锁，保留已经安装的 `.exe`、`.dll`、`.cmd`、`.ps1`、配置和注册表；自动清理失败明确显示“安装成功，清理失败”，独立清理失败正常报错。

**停止安装：** 安装进行中原按钮变为“停止安装”。点击只写停止请求，等待当前包事务完整结束，再把后续包标记为“未执行”；不强杀安装器、编译进程或资源管理器，未执行项不计失败或完成百分比。完成后可在同一面板继续清理、重试或关闭。

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

# `Scripts`：Flutter 第三方依赖提取

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、文件职责](#jobs-toc-heading-2)
- [二、运行与影响](#jobs-toc-heading-3)
- [三、维护与验证](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录是 [JobsFlutterDependencyExtractor](../README.md) 的完整独立运行与安装文件。安装后从本包 release 内运行；不读取父仓或相邻功能包。

**面板外观与语言：** 总面板和独立功能面板右上角均可选择“黑夜 / 白天 / 跟随系统”以及“简体中文 / 繁體中文 / བོད་ཡིག / English / 日本語 / Français / Español / Deutsch / Русский / 한국어 / 跟随系统”，默认均跟随系统，切换立即生效并保留当前勾选、任务和日志。窄窗或长文案放不下时，工具组移至标题下一行并保持右对齐；极窄窗口将主题、语言分两行，下拉控件右边缘对齐。选择保存在当前用户的 `%LOCALAPPDATA%\Jobs\WindowsExtension\panel-preferences.json`，下次打开自动恢复；保存失败在面板显示原因。跟随系统每秒检查应用主题和当前用户显示语言，繁体中文界面使用繁体、其它中文使用简体，其余已支持语种按系统语言匹配，未支持语言回退英文；Windows 显示语言通常须重新登录才生效。切换涵盖面板正文、功能说明、状态与动态计数、操作提示和辅助名称；藏文优先使用已安装 Microsoft Himalaya / Noto Sans Tibetan，日韩使用对应系统字体，缺失时回退。语言名称始终显示自称，图标、功能名和状态列独立，长文字换行；切换只影响管理面板，已安装右键菜单标题及后台工具的原始日志保持各自语言。共享完整译文以 `Scripts/ManagerPanelTranslations.json` 为编辑来源，发布时内嵌到同源面板模块，独立包无需访问兄弟目录或联网翻译。

**日志配色与滚动：** 日志使用独立的白天／黑夜背景、正文和错误／警告／成功／信息配色，ANSI 前景色按当前底色提高对比度；跟随系统采用对应一套。切换主题重配已有日志颜色，保留正文、选区和阅读位置。 Windows 高对比度开启、关闭或系统色变化时，已有日志和新输出同步采用对应底色与正文色，现有外观轮询同步面板。鼠标滚轮、触摸板、滚动条、方向／翻页键及选择正文暂停“自动滚动”，重新勾选才恢复追尾；后台继续接收日志。右键复制与 Ctrl+C 仅复制纯文本，可见区超过 100 万字符保留最后 70 万，原“复制全部日志”读取本次完整纯文本文件。追尾开关和阅读位置只保留当前窗口，不另存偏好。

**关闭与系统托盘：** 安装／卸载／构建清理进行中，点击窗口关闭、按 Esc 或使用底部关闭入口都直接退到系统托盘，后台任务和日志继续运行，不弹询问。任务完成后仍驻留，双击通知图标或选择“显示管理面板”恢复同一窗口、勾选与日志；托盘菜单显示当前状态。只有空闲关闭才询问“退到系统托盘／完全退出”，回车默认托盘，Esc 或“保留窗口”取消关闭选择；托盘的“完全退出”在任务中禁用并说明原因，执行出口再次检查任务，不能中途终止工作进程。真正退出才释放通知图标、菜单及计时器；托盘不可用时保留可见窗口。关闭选择不记忆，下次空闲关闭仍询问；托盘和隐藏状态仅属于本次进程。图标复用当前管理窗口的应用图标，无额外下载。

**整行选择：** 点击复选框、图标、功能文字、普通状态区或该功能行空白，仅切换该项一次，保留原 Tab／Space 复选框操作及勾选事件。任务执行中及不可用项禁止切换；失败日志链接和独立按钮优先执行自身动作，不连带勾选。组标题拖动、分组按钮和组尾空白不算功能行；移动、离开、滚动或触控滑动会取消本次点击候选，不接管原生滚动。选择本身不执行安装、卸载或清理，原默认空选、主题／语言切换保留勾选及持久化规则不变。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、文件职责</span><!-- jobs-toc:heading-end -->

| 文件 | 职责 |
| --- | --- |
| [Action.psm1](./Action.psm1) | 内置自述、回车确认、精确 Flutter 项目门禁、目录输入、健康原生 Dart 发现和同步提取。 |
| [ExtractFlutterDependencies.dart](./ExtractFlutterDependencies.dart) | 根据锁文件和 package_config 校验并复制 Pub 第三方依赖源码与许可证；只用 Dart 标准库。 |
| [Invoke.ps1](./Invoke.ps1/Invoke.ps1) | 已安装菜单入口，核对本包启用状态和目标后调用统一业务入口；失败保留终端。 |
| [Manage.ps1](./Manage.ps1/Manage.ps1) | 独立安装 / 卸载入口，由上一级 `.cmd` 启动，默认取消的原生确认窗口。 |
| [PackageInstaller.psm1](./PackageInstaller.psm1) | 本包文件校验与 release、当前用户菜单注册、备份、状态提交及异常回滚。 |
| [Common.psm1](./Common.psm1) | 本包内嵌的路径、原生 argv、进程超时清理和通用日志基础设施。 |

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、运行与影响</span><!-- jobs-toc:heading-end -->

正常使用上一级 [Install.cmd](../Install.cmd/Install.cmd)，然后右键 Flutter 项目文件夹选择“提取 Flutter 第三方依赖”。终端先打印固定在脚本内的自述，按回车继续；输出父目录输入或拖入均可，空行使用系统桌面。不会执行路径中的 Shell 表达式。

共享 Dart 引擎通过独立参数调用：

```powershell
dart.exe `
  .\ExtractFlutterDependencies.dart `
  --project 'D:\Flutter 项目' `
  --destination 'D:\依赖归档'
```

项目与依赖缓存只读，结果写入指定父目录下的新目录。不会安装 SDK、下载依赖或执行 `flutter pub get`；记录缺失、过期或包源码不可用时明确停止。导出范围与风险详见上一级 README。

在解析符号链接前排除 `.plugin_symlinks`，以及 `linux/flutter/ephemeral`、`windows/flutter/ephemeral`、`macos/Flutter/ephemeral`（包括嵌套 example 中的相同路径）。这些生成目录可能保留其他开发机器的失效链接，不属于源码归档。平台源码、许可证及普通源码中名为 `ephemeral` 的目录仍保留；其他路径中的失效、包外、循环及指向排除目录的链接跳过，终端与 `manifest.json` 的 `warnings` 记录包名、相对路径和原因；真实包根、普通源码读取 / 复制错误及特殊文件仍失败。清单通过 `excludedDirectories` 和 `excludedGeneratedDirectorySuffixes` 记录排除规则，`excludedRelativePaths` 保留为后者的等值兼容别名。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、维护与验证</span><!-- jobs-toc:heading-end -->

PowerShell 源码为 UTF-8 BOM、CRLF，兼容 Windows PowerShell 5.1。四份基础设施模板可由父仓维护工具受控同步；`Action.psm1` 与 Dart 引擎是本功能业务，不能用相邻包业务覆盖。跨平台引擎同源维护，发布时按 SHA-256 核对 Windows 与 macOS 副本。

业务日志在当前用户本地应用数据中本功能的 `logs/extract-*.log`；运行时显示精确位置，并脱敏地址凭据和敏感参数。普通测试只使用临时目录和模拟命令，不调用真实安装入口或注册菜单。静态与夹具验证不能代替 Windows 桌面实测。

跨平台引擎使用 [共享 Dart 行为回归](../../../MacOS@Extension/JobsFlutterDependencyExtractor/Tests/DependencyExtractionTests.dart)，以首个参数显式指定本包或统一菜单中的 Dart 引擎；覆盖生成目录排除、正常源码与许可证保留、链接告警及真实文件读取失败。当前已在 macOS 原生环境验证这些场景；Windows 的符号链接与读取权限须在目标系统独立验收，跳过的场景不计为已验证。Windows 安装资源复制与参数传递由现有 `Tests/FlutterDependencyExtractor.Tests.ps1`、`Tests/FlutterTools.Tests.ps1` 验证。

本目录的 `Manage.ps1/Manage.ps1`、`SelectionPanel.psm1` 和 `ManagementWorker.ps1/ManagementWorker.ps1` 构成本包自包含管理面板；由上级 `Manage.vbs` 无控制台启动。安装 / 卸载在隐藏后台执行，逐项状态与可复制实时日志留在面板中。总进度按已处理项 / 本次所选项显示计数和百分比；成功、未安装无需卸载与失败计入已处理，等待中、执行中和未执行项不计入；“未安装，无需卸载”单独显示且不算成功，最终分别汇总成功、无需卸载、失败与未执行数量。100% 仅表示本轮全部处理完毕。安装 / 更新和卸载分别计时；点击时只清零并启动当前操作计时，后台全部结束或启动失败时只冻结当前耗时。每秒刷新 `HH:mm:ss`（小时可超过 24），执行时显示“安装用时 / 卸载用时”，结束显示“安装总用时 / 卸载总用时”。两份耗时只在当前面板会话内独立保留。安装成功显示绿色“✅ 安装成功”。不改变右键业务工具自己的交互方式。失败状态可点击，在独立 PowerShell 中只读显示本次完整会话日志；包失败不阻止其它所选包，日志不可用时在面板提示。



<!-- JOBS_TERMINAL_STYLE_V1:BEGIN -->

> Windows 终端配色保护：支持完整颜色查询的交互控制台会先保存当前会话默认前景、背景与16色色表，再临时使用黑底白字和统一强调色；正常结束、业务失败及可捕获中断后恢复。用户运行中自行改动的颜色保留并提示，不修改用户主题、共享 Profile、注册表或全局策略。快照不包含进入前任意叠加的临时文字样式。非控制台、重定向、`NO_COLOR`、Sourcetree 及无法可靠保存／恢复颜色的环境保持原状态或降级为纯文本。

> 强制结束进程或终端崩溃无法保证自动恢复。恢复失败时保留并提示本轮 `%TEMP%\JobsTerminalStyle-<PID>-*.ps1` 恢复脚本，需在原控制台核对后运行；不要通过重置用户配置恢复。`-ExecutionPolicy Bypass` 如被入口使用，仅作用于本次子进程，不持久修改策略。

> 验证范围：已完成 PowerShell 语法、参数／退出与隔离生命周期核验；Windows 原生控制台的显示、按键与 `Ctrl+C` 实机验证尚未完成。

<!-- JOBS_TERMINAL_STYLE_V1:END -->


<!-- JOBS_SOURCE_SCRIPT_PACKAGES -->
**同名脚本包：** [Invoke.ps1](./Invoke.ps1/README.md)、[Manage.ps1](./Manage.ps1/README.md)、[ManagementWorker.ps1](./ManagementWorker.ps1/README.md)。源码路径与发布目录的 flat 资源名分开维护。
<!-- /JOBS_SOURCE_SCRIPT_PACKAGES -->

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

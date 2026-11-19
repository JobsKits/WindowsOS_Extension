# Android 模拟器检测与修复脚本

![Jobs出品，必属精品](https://picsum.photos/1500/400)

**固定桌面菜单顺序：** 本包随附 [DesktopMenuOrder.h](./DesktopMenuOrder.h)。已更新的 Android 新建 → Harmony 新建 → Android 修复 → Harmony 修复 → 文件显示切换 → 磁盘剩余菜单按固定功能次序协作插入，不依赖安装先后、标题语言或 handler 回调顺序。只识别本协议的整数标记，不更改其它菜单项、命令 ID、资格和业务入口；卸载任一项后其余项保持相对顺序，独立包仍可单独使用。相关包都须安装／更新后才完整采用此协议；旧版 handler 未带标记，不能保证与新版混用时的排序。菜单顺序不写入偏好或注册表。隔离验证见[生产 handler 排列回归](../../Tests/DesktopMenuOrderTests.cpp/README.md)，目标 Windows 的真实 Explorer 显示仍须单独验收。

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、文件职责](#files)
- [二、只读检查与验证](#check)

</details>
<!-- jobs-toc:end -->

---

**面板外观与语言：** 总面板和独立功能面板右上角均可选择“黑夜 / 白天 / 跟随系统”以及“简体中文 / 繁體中文 / བོད་ཡིག / English / 日本語 / Français / Español / Deutsch / Русский / 한국어 / 跟随系统”，默认均跟随系统，切换立即生效并保留当前勾选、任务和日志。窄窗或长文案放不下时，工具组移至标题下一行并保持右对齐；极窄窗口将主题、语言分两行，下拉控件右边缘对齐。选择保存在当前用户的 `%LOCALAPPDATA%\Jobs\WindowsExtension\panel-preferences.json`，下次打开自动恢复；保存失败在面板显示原因。跟随系统每秒检查应用主题和当前用户显示语言，繁体中文界面使用繁体、其它中文使用简体，其余已支持语种按系统语言匹配，未支持语言回退英文；Windows 显示语言通常须重新登录才生效。切换涵盖面板正文、功能说明、状态与动态计数、操作提示和辅助名称；藏文优先使用已安装 Microsoft Himalaya / Noto Sans Tibetan，日韩使用对应系统字体，缺失时回退。语言名称始终显示自称，图标、功能名和状态列独立，长文字换行；切换只影响管理面板，已安装右键菜单标题及后台工具的原始日志保持各自语言。共享完整译文以 `Scripts/ManagerPanelTranslations.json` 为编辑来源，发布时内嵌到同源面板模块，独立包无需访问兄弟目录或联网翻译。

**日志配色与滚动：** 日志使用独立的白天／黑夜背景、正文和错误／警告／成功／信息配色，ANSI 前景色按当前底色提高对比度；跟随系统采用对应一套。切换主题重配已有日志颜色，保留正文、选区和阅读位置。 Windows 高对比度开启、关闭或系统色变化时，已有日志和新输出同步采用对应底色与正文色，现有外观轮询同步面板。鼠标滚轮、触摸板、滚动条、方向／翻页键及选择正文暂停“自动滚动”，重新勾选才恢复追尾；后台继续接收日志。右键复制与 Ctrl+C 仅复制纯文本，可见区超过 100 万字符保留最后 70 万，原“复制全部日志”读取本次完整纯文本文件。追尾开关和阅读位置只保留当前窗口，不另存偏好。

**关闭与系统托盘：** 安装／卸载／构建清理进行中，点击窗口关闭、按 Esc 或使用底部关闭入口都直接退到系统托盘，后台任务和日志继续运行，不弹询问。任务完成后仍驻留，双击通知图标或选择“显示管理面板”恢复同一窗口、勾选与日志；托盘菜单显示当前状态。只有空闲关闭才询问“退到系统托盘／完全退出”，回车默认托盘，Esc 或“保留窗口”取消关闭选择；托盘的“完全退出”在任务中禁用并说明原因，执行出口再次检查任务，不能中途终止工作进程。真正退出才释放通知图标、菜单及计时器；托盘不可用时保留可见窗口。关闭选择不记忆，下次空闲关闭仍询问；托盘和隐藏状态仅属于本次进程。图标复用当前管理窗口的应用图标，无额外下载。

**整行选择：** 点击复选框、图标、功能文字、普通状态区或该功能行空白，仅切换该项一次，保留原 Tab／Space 复选框操作及勾选事件。任务执行中及不可用项禁止切换；失败日志链接和独立按钮优先执行自身动作，不连带勾选。组标题拖动、分组按钮和组尾空白不算功能行；移动、离开、滚动或触控滑动会取消本次点击候选，不接管原生滚动。选择本身不执行安装、卸载或清理，原默认空选、主题／语言切换保留勾选及持久化规则不变。

## 🔥 <span id="前言">前言</span>

> 本目录为独立 [**Windows**](https://www.microsoft.com/windows) 桌面扩展的自包含业务及安装实现。用途、运行实例、依赖、完整 AVD 备份和恢复边界见[功能 README](../README.md)。

## 一、<span id="files">文件职责</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文件 | 职责 |
| --- | --- |
| `RepairAndroidSimulator.ps1/RepairAndroidSimulator.ps1` | 独立运行及 `-Check`，支持设备、包名、阈值和目标容量参数。 |
| `Action.psm1` | 模拟器身份、安装位置、空间、精确卸载、编译状态、完整备份与冷启动复测。 |
| `ContextMenu.cpp` / `DesktopScope.h` / `.def` | 独立 COM handler，仅系统桌面空白显示。 |
| `OpenCmd.ps1/OpenCmd.ps1` / `Invoke.ps1/Invoke.ps1` | 安全打开可见终端并检查本包安装状态和目标。 |
| `Build.ps1/Build.ps1` | 使用已有 MSVC / Windows SDK 构建本包 DLL，缺失时停止注册。 |
| `Manage.ps1/Manage.ps1` / `PackageInstaller.psm1` | 当前用户精确菜单注册 / 卸载事务，不执行设备修复。 |
| `Common.psm1` | 本包路径、进程参数、超时和阶段日志基础设施。 |

## 二、<span id="check">只读检查与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录使用系统 [**PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) 5.1：

```powershell
powershell.exe `
  -NoLogo `
  -NoProfile `
  -ExecutionPolicy Bypass `
  -File ./RepairAndroidSimulator.ps1/RepairAndroidSimulator.ps1 `
  -Check
```

普通运行先展示内置自述，回车后执行默认轻量修复；缓存重置、单包卸载与容量调整另需精确 `YES`。`-Check` 不写日志、不设备写入、不改配置。所有 SDK 工具只发现不安装。扩容前备份整个 AVD 并校验，保留 userdata，不清空数据；实际分区与可用空间复测通过才报告成功。

日志为当前用户本地应用数据目录中本包 `logs/` 下的日期 `.log`；容量备份位于原 AVD 目录旁的 `.jobs-repair-backup-*`，终端输出精确路径。安装状态、`releases/` 与注册表 `backups/` 另由本包安装器维护，卸载保留这些产物。

隔离回归见 [`AndroidSimulatorRepairer.Tests.ps1`](../../Tests/AndroidSimulatorRepairer.Tests.ps1/AndroidSimulatorRepairer.Tests.ps1)。macOS 夹具及 Parser 不替代 Windows 5.1 / Explorer / 真实 Emulator 实机验收。

本目录的 `Manage.ps1/Manage.ps1`、`SelectionPanel.psm1` 和 `ManagementWorker.ps1/ManagementWorker.ps1` 构成本包自包含管理面板；由上级 `Manage.vbs` 无控制台启动。安装 / 卸载在隐藏后台执行，逐项状态与可复制实时日志留在面板中。日志区上沿的分隔条可上下拖动，调节结果在当前窗口保留；上下限为功能行、操作按钮和日志工具栏留出空间。日志正文右键可“复制”或“全选”，也支持 Ctrl+A / Ctrl+C；全选仅针对当前可见缓冲区，完整输出使用“复制全部日志”。总进度按已处理项 / 本次所选项显示计数和百分比；成功、未安装无需卸载与失败计入已处理，等待中、执行中和未执行项不计入；“未安装，无需卸载”单独显示且不算成功，最终分别汇总成功、无需卸载、失败与未执行数量。100% 仅表示本轮全部处理完毕。安装 / 更新和卸载分别计时；点击时只清零并启动当前操作计时，后台全部结束或启动失败时只冻结当前耗时。每秒刷新 `HH:mm:ss`（小时可超过 24），执行时显示“安装用时 / 卸载用时”，结束显示“安装总用时 / 卸载总用时”。两份耗时只在当前面板会话内独立保留。安装成功显示绿色“✅ 安装成功”。不改变右键业务工具自己的交互方式。失败状态可点击，在独立 PowerShell 中只读显示本次完整会话日志；包失败不阻止其它所选包，日志不可用时在面板提示。



<!-- JOBS_TERMINAL_STYLE_V1:BEGIN -->

> Windows 终端配色保护：支持完整颜色查询的交互控制台会先保存当前会话默认前景、背景与16色色表，再临时使用黑底白字和统一强调色；正常结束、业务失败及可捕获中断后恢复。用户运行中自行改动的颜色保留并提示，不修改用户主题、共享 Profile、注册表或全局策略。快照不包含进入前任意叠加的临时文字样式。非控制台、重定向、`NO_COLOR`、Sourcetree 及无法可靠保存／恢复颜色的环境保持原状态或降级为纯文本。

> 强制结束进程或终端崩溃无法保证自动恢复。恢复失败时保留并提示本轮 `%TEMP%\JobsTerminalStyle-<PID>-*.ps1` 恢复脚本，需在原控制台核对后运行；不要通过重置用户配置恢复。`-ExecutionPolicy Bypass` 如被入口使用，仅作用于本次子进程，不持久修改策略。

> 验证范围：已完成 PowerShell 语法、参数／退出与隔离生命周期核验；Windows 原生控制台的显示、按键与 `Ctrl+C` 实机验证尚未完成。

<!-- JOBS_TERMINAL_STYLE_V1:END -->


<!-- JOBS_SOURCE_SCRIPT_PACKAGES -->
**同名脚本包：** [Build.ps1](./Build.ps1/README.md)、[Invoke.ps1](./Invoke.ps1/README.md)、[Manage.ps1](./Manage.ps1/README.md)、[ManagementWorker.ps1](./ManagementWorker.ps1/README.md)、[OpenCmd.ps1](./OpenCmd.ps1/README.md)、[RepairAndroidSimulator.ps1](./RepairAndroidSimulator.ps1/README.md)。源码路径与发布目录的 flat 资源名分开维护。
<!-- /JOBS_SOURCE_SCRIPT_PACKAGES -->

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

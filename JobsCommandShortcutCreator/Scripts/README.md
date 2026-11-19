# 脚本快捷入口扩展 · 源码与管理脚本

此目录属于独立功能 `command-shortcut-create`，由上一级 [Manage.cmd](../Manage.cmd) / [Manage.vbs](../Manage.vbs/Manage.vbs) 打开 GUI。完整使用方式与风险见 [功能说明](../README.md)。

| 文件 | 职责 |
| --- | --- |
| `Manage.ps1/Manage.ps1`、`ManagementWorker.ps1/ManagementWorker.ps1` | 功能限定的 GUI管理、后台任务、逐项状态与日志 |
| `SelectionPanel.psm1` | 十语 / 三主题管理面板、空选门禁、后台状态 |
| `PackageInstaller.psm1` | 本项原生 DLL 构建、独立运行副本、注册表所有权、备份与卸载 |
| `Common.psm1` | 本包路径、参数引用、日志及通用进程支持 |
| `Build.ps1/Build.ps1` | 使用 MSVC / Windows SDK 编译当前架构 DLL，本身不注册菜单 |
| `ContextMenu.cpp`、`ContextMenu.def` | 原生 COM菜单、单选快照、十语标题及明确脚本投递 |
| `CommandShortcutTarget.h` | `.cmd` / `.bat` / `.ps1` 同名脚本包判定，拒绝重解析点 |
| `Invoke.ps1/Invoke.ps1` | 校验本项已安装且启用后加载唯一业务模块 |
| `Action.psm1` | 只调用本包创建入口对话框 |
| `CommandShortcut.ps1/CommandShortcut.ps1` | 目录 / 名称检查、相对入口生成、排他发布、十语与主题切换 |

业务加载不会执行包内原脚本。只有用户在创建对话框点击“创建”才写同级入口；管理操作不生成业务入口。所有路径从当前脚本或运行副本解析，不硬编码源码所在目录。

安装依赖 Windows PowerShell 5.1、WinForms、MSVC 与 Windows SDK；业务生成仅用系统 PowerShell / .NET。运行副本、备份和日志位于当前用户本地应用数据目录下 `Jobs/WindowsExtension/command-shortcut-create`，错误先查看面板和该功能日志。卸载按本项所有权撤回登记，不删除已生成入口及原始脚本。

**日志配色与滚动：** 日志使用独立的白天／黑夜背景、正文和错误／警告／成功／信息配色，ANSI 前景色按当前底色提高对比度；跟随系统采用对应一套。切换主题重配已有日志颜色，保留正文、选区和阅读位置。 Windows 高对比度开启、关闭或系统色变化时，已有日志和新输出同步采用对应底色与正文色，现有外观轮询同步面板。鼠标滚轮、触摸板、滚动条、方向／翻页键及选择正文暂停“自动滚动”，重新勾选才恢复追尾；后台继续接收日志。右键复制与 Ctrl+C 仅复制纯文本，可见区超过 100 万字符保留最后 70 万，原“复制全部日志”读取本次完整纯文本文件。追尾开关和阅读位置只保留当前窗口，不另存偏好。

**关闭与系统托盘：** 安装／卸载／构建清理进行中，点击窗口关闭、按 Esc 或使用底部关闭入口都直接退到系统托盘，后台任务和日志继续运行，不弹询问。任务完成后仍驻留，双击通知图标或选择“显示管理面板”恢复同一窗口、勾选与日志；托盘菜单显示当前状态。只有空闲关闭才询问“退到系统托盘／完全退出”，回车默认托盘，Esc 或“保留窗口”取消关闭选择；托盘的“完全退出”在任务中禁用并说明原因，执行出口再次检查任务，不能中途终止工作进程。真正退出才释放通知图标、菜单及计时器；托盘不可用时保留可见窗口。关闭选择不记忆，下次空闲关闭仍询问；托盘和隐藏状态仅属于本次进程。图标复用当前管理窗口的应用图标，无额外下载。

**整行选择：** 点击复选框、图标、功能文字、普通状态区或该功能行空白，仅切换该项一次，保留原 Tab／Space 复选框操作及勾选事件。任务执行中及不可用项禁止切换；失败日志链接和独立按钮优先执行自身动作，不连带勾选。组标题拖动、分组按钮和组尾空白不算功能行；移动、离开、滚动或触控滑动会取消本次点击候选，不接管原生滚动。选择本身不执行安装、卸载或清理，原默认空选、主题／语言切换保留勾选及持久化规则不变。


<!-- JOBS_SOURCE_SCRIPT_PACKAGES -->
**同名脚本包：** [Build.ps1](./Build.ps1/README.md)、[CommandShortcut.ps1](./CommandShortcut.ps1/README.md)、[Invoke.ps1](./Invoke.ps1/README.md)、[Manage.ps1](./Manage.ps1/README.md)、[ManagementWorker.ps1](./ManagementWorker.ps1/README.md)。源码路径与发布目录的 flat 资源名分开维护。
<!-- /JOBS_SOURCE_SCRIPT_PACKAGES -->

# `JobsDiskSpaceInfo` 脚本与原生菜单

本目录随独立包分发，不访问父工程或兄弟功能。

**固定桌面菜单顺序：** 本包随附 [DesktopMenuOrder.h](./DesktopMenuOrder.h)。已更新的 Android 新建 → Harmony 新建 → Android 修复 → Harmony 修复 → 文件显示切换 → 磁盘剩余菜单按固定功能次序协作插入，不依赖安装先后、标题语言或 handler 回调顺序。只识别本协议的整数标记，不更改其它菜单项、命令 ID、资格和业务入口；卸载任一项后其余项保持相对顺序，独立包仍可单独使用。相关包都须安装／更新后才完整采用此协议；旧版 handler 未带标记，不能保证与新版混用时的排序。菜单顺序不写入偏好或注册表。隔离验证见[生产 handler 排列回归](../../Tests/DesktopMenuOrderTests.cpp/README.md)，目标 Windows 的真实 Explorer 显示仍须单独验收。

| 文件 | 职责 |
| --- | --- |
| [ContextMenu.cpp](./ContextMenu.cpp)、[ContextMenu.def](./ContextMenu.def) | 独立 COM DLL；每次 `QueryContextMenu` 都重新读取本地卷，同一COM实例不保留容量快照，点击容量行才用系统 PowerShell 创建独立控制台，固定定位本包 Clean，不传所选路径。 |
| [DiskSpaceSummary.h](./DiskSpaceSummary.h) | 卷身份去重、字节合计、边界校验、十语言单行显示与两位小数百分比。 |
| [Build.ps1](./Build.ps1/Build.ps1) | 只用现有 MSVC / Windows SDK 编译本包 DLL；`-SourceRoot` 默认为包目录，`-OutputRoot` 必填。不注册、不下载工具。 |
| [PackageInstaller.psm1](./PackageInstaller.psm1) | 本包独立注册计划、运行文件发布、备份 / 回滚与当前用户安装状态。 |
| [Manage.ps1](./Manage.ps1/Manage.ps1)、[SelectionPanel.psm1](./SelectionPanel.psm1)、[ManagementWorker.ps1](./ManagementWorker.ps1/ManagementWorker.ps1) | 沿用平台独立包管理面板，支持安装 / 更新、卸载、默认空选、取消、主题 / 十语言与日志。 |
| [Clean.ps1](./Clean.ps1/README.md) | 随包完整自包含清理流程：先可选开发分组、再常规 clean，缓存首行全选、次行默认跳过及逐项选择，候选白名单、默认取消、精确确认、备份复检和日志。 |
| [Common.psm1](./Common.psm1)、[Invoke.ps1](./Invoke.ps1/Invoke.ps1)、[Action.psm1](./Action.psm1) | 保持包协议兼容；不注册静态执行命令，通用路径动作提示使用原生菜单的独立清理终端。 |

公开入口、使用条件、统计口径、日志、持久状态和验证边界见 [功能说明](../README.md)。容量查询不创建缓存或采集日志，API读取失败不会保留上一次成功描述；清理只有确认后才创建本包日志与必要备份。系统 DLL 卸载由 Explorer 管理，点击创建的控制台由用户关闭，不启动常驻采集器。开发阶段验证见 [容量回归](../Tests/DiskSpaceSummaryTests.cpp/README.md)、[重复菜单采样](../Tests/ContextMenuFreshnessTests.cpp/README.md)与 [清理回归](../Tests/CleanTests.ps1/README.md)。

**日志配色与滚动：** 日志使用独立的白天／黑夜背景、正文和错误／警告／成功／信息配色，ANSI 前景色按当前底色提高对比度；跟随系统采用对应一套。切换主题重配已有日志颜色，保留正文、选区和阅读位置。 Windows 高对比度开启、关闭或系统色变化时，已有日志和新输出同步采用对应底色与正文色，现有外观轮询同步面板。鼠标滚轮、触摸板、滚动条、方向／翻页键及选择正文暂停“自动滚动”，重新勾选才恢复追尾；后台继续接收日志。右键复制与 Ctrl+C 仅复制纯文本，可见区超过 100 万字符保留最后 70 万，原“复制全部日志”读取本次完整纯文本文件。追尾开关和阅读位置只保留当前窗口，不另存偏好。

**关闭与系统托盘：** 安装／卸载／构建清理进行中，点击窗口关闭、按 Esc 或使用底部关闭入口都直接退到系统托盘，后台任务和日志继续运行，不弹询问。任务完成后仍驻留，双击通知图标或选择“显示管理面板”恢复同一窗口、勾选与日志；托盘菜单显示当前状态。只有空闲关闭才询问“退到系统托盘／完全退出”，回车默认托盘，Esc 或“保留窗口”取消关闭选择；托盘的“完全退出”在任务中禁用并说明原因，执行出口再次检查任务，不能中途终止工作进程。真正退出才释放通知图标、菜单及计时器；托盘不可用时保留可见窗口。关闭选择不记忆，下次空闲关闭仍询问；托盘和隐藏状态仅属于本次进程。图标复用当前管理窗口的应用图标，无额外下载。

**整行选择：** 点击复选框、图标、功能文字、普通状态区或该功能行空白，仅切换该项一次，保留原 Tab／Space 复选框操作及勾选事件。任务执行中及不可用项禁止切换；失败日志链接和独立按钮优先执行自身动作，不连带勾选。组标题拖动、分组按钮和组尾空白不算功能行；移动、离开、滚动或触控滑动会取消本次点击候选，不接管原生滚动。选择本身不执行安装、卸载或清理，原默认空选、主题／语言切换保留勾选及持久化规则不变。

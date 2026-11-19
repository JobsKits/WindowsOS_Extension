# `Scripts`：新建 Harmony 模拟器

![Jobs出品，必属精品](https://picsum.photos/1500/400)

**固定桌面菜单顺序：** 本包随附 [DesktopMenuOrder.h](./DesktopMenuOrder.h)。已更新的 Android 新建 → Harmony 新建 → Android 修复 → Harmony 修复 → 文件显示切换 → 磁盘剩余菜单按固定功能次序协作插入，不依赖安装先后、标题语言或 handler 回调顺序。只识别本协议的整数标记，不更改其它菜单项、命令 ID、资格和业务入口；卸载任一项后其余项保持相对顺序，独立包仍可单独使用。相关包都须安装／更新后才完整采用此协议；旧版 handler 未带标记，不能保证与新版混用时的排序。菜单顺序不写入偏好或注册表。隔离验证见[生产 handler 排列回归](../../Tests/DesktopMenuOrderTests.cpp/README.md)，目标 Windows 的真实 Explorer 显示仍须单独验收。

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、文件职责](#files)
- [二、运行与维护边界](#boundaries)

</details>
<!-- jobs-toc:end -->

---

**面板外观与语言：** 总面板和独立功能面板右上角均可选择“黑夜 / 白天 / 跟随系统”以及“简体中文 / 繁體中文 / བོད་ཡིག / English / 日本語 / Français / Español / Deutsch / Русский / 한국어 / 跟随系统”，默认均跟随系统，切换立即生效并保留当前勾选、任务和日志。窄窗或长文案放不下时，工具组移至标题下一行并保持右对齐；极窄窗口将主题、语言分两行，下拉控件右边缘对齐。选择保存在当前用户的 `%LOCALAPPDATA%\Jobs\WindowsExtension\panel-preferences.json`，下次打开自动恢复；保存失败在面板显示原因。跟随系统每秒检查应用主题和当前用户显示语言，繁体中文界面使用繁体、其它中文使用简体，其余已支持语种按系统语言匹配，未支持语言回退英文；Windows 显示语言通常须重新登录才生效。切换涵盖面板正文、功能说明、状态与动态计数、操作提示和辅助名称；藏文优先使用已安装 Microsoft Himalaya / Noto Sans Tibetan，日韩使用对应系统字体，缺失时回退。语言名称始终显示自称，图标、功能名和状态列独立，长文字换行；切换只影响管理面板，已安装右键菜单标题及后台工具的原始日志保持各自语言。共享完整译文以 `Scripts/ManagerPanelTranslations.json` 为编辑来源，发布时内嵌到同源面板模块，独立包无需访问兄弟目录或联网翻译。

**日志配色与滚动：** 日志使用独立的白天／黑夜背景、正文和错误／警告／成功／信息配色，ANSI 前景色按当前底色提高对比度；跟随系统采用对应一套。切换主题重配已有日志颜色，保留正文、选区和阅读位置。 Windows 高对比度开启、关闭或系统色变化时，已有日志和新输出同步采用对应底色与正文色，现有外观轮询同步面板。鼠标滚轮、触摸板、滚动条、方向／翻页键及选择正文暂停“自动滚动”，重新勾选才恢复追尾；后台继续接收日志。右键复制与 Ctrl+C 仅复制纯文本，可见区超过 100 万字符保留最后 70 万，原“复制全部日志”读取本次完整纯文本文件。追尾开关和阅读位置只保留当前窗口，不另存偏好。

**关闭与系统托盘：** 安装／卸载／构建清理进行中，点击窗口关闭、按 Esc 或使用底部关闭入口都直接退到系统托盘，后台任务和日志继续运行，不弹询问。任务完成后仍驻留，双击通知图标或选择“显示管理面板”恢复同一窗口、勾选与日志；托盘菜单显示当前状态。只有空闲关闭才询问“退到系统托盘／完全退出”，回车默认托盘，Esc 或“保留窗口”取消关闭选择；托盘的“完全退出”在任务中禁用并说明原因，执行出口再次检查任务，不能中途终止工作进程。真正退出才释放通知图标、菜单及计时器；托盘不可用时保留可见窗口。关闭选择不记忆，下次空闲关闭仍询问；托盘和隐藏状态仅属于本次进程。图标复用当前管理窗口的应用图标，无额外下载。

**整行选择：** 点击复选框、图标、功能文字、普通状态区或该功能行空白，仅切换该项一次，保留原 Tab／Space 复选框操作及勾选事件。任务执行中及不可用项禁止切换；失败日志链接和独立按钮优先执行自身动作，不连带勾选。组标题拖动、分组按钮和组尾空白不算功能行；移动、离开、滚动或触控滑动会取消本次点击候选，不接管原生滚动。选择本身不执行安装、卸载或清理，原默认空选、主题／语言切换保留勾选及持久化规则不变。

## 🔥 <span id="前言">前言</span>

本目录是独立 [JobsHarmonySimulatorCreator](../README.md) 的完整运行代码，不引用其它功能包或 SourceTree 脚本。

## 一、<span id="files">文件职责</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文件 | 职责 |
| --- | --- |
| `Action.psm1` | 桌面 / x64 门禁、工具发现与依赖补齐、只读能力与镜像查询、选择、唯一命名、创建回读及可选启动。 |
| `HarmonyTools.ps1/HarmonyTools.ps1` | SDL Windows x64 CLT 下载、本地 ZIP 复用、大小 / SHA-256 / 解压路径校验、独立目录发布与失败清理。 |
| `CreateHarmonySimulator.ps1/CreateHarmonySimulator.ps1` | 独立业务入口；`-Check` 不创建、下载、启动或安装，参数见[功能说明](../README.md#run)。 |
| `ContextMenu.cpp` / `DesktopScope.h` / `ContextMenu.def` | 原生 `DesktopBackground` handler，只对无选中项的真实系统桌面插入一项，并拒绝 ARM 宿主。 |
| `Build.ps1/Build.ps1` | 只用已有 MSVC / Windows SDK 编译 x64 DLL；不注册、不安装编译器。 |
| `OpenCmd.ps1/OpenCmd.ps1` | 通过进程环境传递目标，打开 CMD 并启动固定 PowerShell 引导。 |
| `Invoke.ps1/Invoke.ps1` / `Common.psm1` | 安装状态门禁、路径 / 参数工具和进程超时清理；每包内嵌。 |
| `Manage.ps1/Manage.ps1` / `PackageInstaller.psm1` | 独立安装、备份、注册表事务与卸载；原生安装模块为模板明确覆盖项。 |

## 二、<span id="boundaries">运行与维护边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

安装 / 卸载从上一层 `.cmd` 进行，业务可通过 `Run.cmd` 独立运行。华为官方下载中心获取模拟器配套工具需要登录；正常桌面入口回车授权后，缺工具时使用 [SDL 免登录替代源](https://libsdl.org/harmonyos-devtools/) 安装 Windows x64 CLT 6.1.1.280。校验固定大小、SHA-256 与归档路径后解压，能力检查通过才发布独立目录；健康工具不升级。`HARMONY_CLT_ARCHIVE` 可复用同版本本地 ZIP。缺系统镜像时读取官方清单，回车选最新稳定版手机镜像；展示随工具的两份协议原文，用户回车明确同意后才执行 `-license accept`，再用 `-install ... -force` 下载所选项。镜像复检失败就停止，不循环等待外部准备；不覆盖实例、不修改全局配置。创建和启动命令不含 `-force`；成功后通过详情回读验证唯一名称、产品类型和系统版本，不能解析或不匹配就保留现场并停止。启动由本人选择，未确认许可时先展示原文并等待本人同意；官方额外交互保留在终端内。

首屏确认后、依赖安装前开始写本包日志；只读 Check 不写状态或业务日志。原生工具输出留在控制台，工具自身日志沿用 DevEco 配置。依赖回归入口为 [HarmonySimulatorBootstrap.Tests.ps1](../../Tests/HarmonySimulatorBootstrap.Tests.ps1)，使用临时小 ZIP 与下载替身；业务回归入口为 [HarmonySimulatorCreator.Tests.ps1](../../Tests/HarmonySimulatorCreator.Tests.ps1/HarmonySimulatorCreator.Tests.ps1)，纯路径门禁探针为 [HarmonyDesktopProbe.cpp](../../Tests/HarmonyDesktopProbe.cpp)。不将 macOS 假工具回归当成 Windows 真机或 Explorer 验收。

本目录的 `Manage.ps1/Manage.ps1`、`SelectionPanel.psm1` 和 `ManagementWorker.ps1/ManagementWorker.ps1` 构成本包自包含管理面板；由上级 `Manage.vbs` 无控制台启动。安装 / 卸载在隐藏后台执行，逐项状态与可复制实时日志留在面板中。日志区上沿的分隔条可上下拖动，调节结果在当前窗口保留；上下限为功能行、操作按钮和日志工具栏留出空间。日志正文右键可“复制”或“全选”，也支持 Ctrl+A / Ctrl+C；全选仅针对当前可见缓冲区，完整输出使用“复制全部日志”。总进度按已处理项 / 本次所选项显示计数和百分比；成功、未安装无需卸载与失败计入已处理，等待中、执行中和未执行项不计入；“未安装，无需卸载”单独显示且不算成功，最终分别汇总成功、无需卸载、失败与未执行数量。100% 仅表示本轮全部处理完毕。安装 / 更新和卸载分别计时；点击时只清零并启动当前操作计时，后台全部结束或启动失败时只冻结当前耗时。每秒刷新 `HH:mm:ss`（小时可超过 24），执行时显示“安装用时 / 卸载用时”，结束显示“安装总用时 / 卸载总用时”。两份耗时只在当前面板会话内独立保留。安装成功显示绿色“✅ 安装成功”。不改变右键业务工具自己的交互方式。失败状态可点击，在独立 PowerShell 中只读显示本次完整会话日志；包失败不阻止其它所选包，日志不可用时在面板提示。

**SDK 环境准备：** 已选择的 SDK／版本所需下载、安装及首次 Flutter／Dart 缓存补齐自动执行；网络失败或无进度超时后持续重试，间隔逐步增加并封顶 30 秒，没有次数和总时长上限，直到成功或本人 Ctrl+C／停止。仍在输出下载进度的传输不按总时长截断；成功后才进入后续业务。目标／版本选择、官方许可证与系统权限仍由本人处理；路径、权限、磁盘或明确不存在的版本会报告具体原因。每次尝试和真实进度追加到终端所示日志；同一 URL 有 ETag／Last-Modified 时安全续传，跨来源保留独立临时文件，不拼接不同来源。失败／取消保留下载现场；业务构建和配置写入不因网络重试而整体重放。

**Flutter SDK网络预检：** 下载／首次Dart自举／precache前，随包网络模块以真实小Range验证来源、TLS、字节和吞吐并择优；显式storage、Pub和代理（含空值）保留，AUTO仅核验官方／CFUG同对象及当前已配置代理，不猜端口、不改系统代理或Git。当前任务短期复用；真实获取失败会降权坏路线、轮换其它已验证候选并持续重试。FVM按实际api context来源处理，能力允许时Git与Dart制品分阶段；用户fork不改源。原生BITS按真实WinINET通道衡量，PAC未能有界解析时保留既有通道并明确未测速。详细边界见[随包选路模块](./SdkDownloadRoute.ps1/README.md)。

由 Flutter Runner 调用且设置本轮 `JOBS_FLUTTER_CREATED_DEVICE_FILE` 时，启动后按唯一新实例回读 [`hw.hdc.port`](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/ide-emulator-command-line/)，并用该实例 SDK 的 `hdc list targets` 核验精确地址，再写入 `Harmony<TAB>127.0.0.1:port`。父 Runner 继续等待 Flutter 返回同一 ID；不以实例名称、UUID 或其它已连接设备代替。180 秒未确认则保留实例、明确失败，取消或跳过启动不写结果；普通桌面入口不启用此接续协议。



<!-- JOBS_TERMINAL_STYLE_V1:BEGIN -->

> Windows 终端配色保护：支持完整颜色查询的交互控制台会先保存当前会话默认前景、背景与16色色表，再临时使用黑底白字和统一强调色；正常结束、业务失败及可捕获中断后恢复。用户运行中自行改动的颜色保留并提示，不修改用户主题、共享 Profile、注册表或全局策略。快照不包含进入前任意叠加的临时文字样式。非控制台、重定向、`NO_COLOR`、Sourcetree 及无法可靠保存／恢复颜色的环境保持原状态或降级为纯文本。

> 强制结束进程或终端崩溃无法保证自动恢复。恢复失败时保留并提示本轮 `%TEMP%\JobsTerminalStyle-<PID>-*.ps1` 恢复脚本，需在原控制台核对后运行；不要通过重置用户配置恢复。`-ExecutionPolicy Bypass` 如被入口使用，仅作用于本次子进程，不持久修改策略。

> 验证范围：已完成 PowerShell 语法、参数／退出与隔离生命周期核验；Windows 原生控制台的显示、按键与 `Ctrl+C` 实机验证尚未完成。

<!-- JOBS_TERMINAL_STYLE_V1:END -->


<!-- JOBS_SOURCE_SCRIPT_PACKAGES -->
**同名脚本包：** [Build.ps1](./Build.ps1/README.md)、[CreateHarmonySimulator.ps1](./CreateHarmonySimulator.ps1/README.md)、[HarmonyTools.ps1](./HarmonyTools.ps1/README.md)、[Invoke.ps1](./Invoke.ps1/README.md)、[Manage.ps1](./Manage.ps1/README.md)、[ManagementWorker.ps1](./ManagementWorker.ps1/README.md)、[OpenCmd.ps1](./OpenCmd.ps1/README.md)、[SdkDownloadOutput.ps1](./SdkDownloadOutput.ps1/README.md)。源码路径与发布目录的 flat 资源名分开维护。
<!-- /JOBS_SOURCE_SCRIPT_PACKAGES -->

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

# `JobsFlutterPubGet Scripts`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、文件与职责](#jobs-toc-heading-2)
- [二、调用与边界](#jobs-toc-heading-3)
- [三、日志与验证](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

**面板外观与语言：** 总面板和独立功能面板右上角均可选择“黑夜 / 白天 / 跟随系统”以及“简体中文 / 繁體中文 / བོད་ཡིག / English / 日本語 / Français / Español / Deutsch / Русский / 한국어 / 跟随系统”，默认均跟随系统，切换立即生效并保留当前勾选、任务和日志。窄窗或长文案放不下时，工具组移至标题下一行并保持右对齐；极窄窗口将主题、语言分两行，下拉控件右边缘对齐。选择保存在当前用户的 `%LOCALAPPDATA%\Jobs\WindowsExtension\panel-preferences.json`，下次打开自动恢复；保存失败在面板显示原因。跟随系统每秒检查应用主题和当前用户显示语言，繁体中文界面使用繁体、其它中文使用简体，其余已支持语种按系统语言匹配，未支持语言回退英文；Windows 显示语言通常须重新登录才生效。切换涵盖面板正文、功能说明、状态与动态计数、操作提示和辅助名称；藏文优先使用已安装 Microsoft Himalaya / Noto Sans Tibetan，日韩使用对应系统字体，缺失时回退。语言名称始终显示自称，图标、功能名和状态列独立，长文字换行；切换只影响管理面板，已安装右键菜单标题及后台工具的原始日志保持各自语言。共享完整译文以 `Scripts/ManagerPanelTranslations.json` 为编辑来源，发布时内嵌到同源面板模块，独立包无需访问兄弟目录或联网翻译。

**日志配色与滚动：** 日志使用独立的白天／黑夜背景、正文和错误／警告／成功／信息配色，ANSI 前景色按当前底色提高对比度；跟随系统采用对应一套。切换主题重配已有日志颜色，保留正文、选区和阅读位置。 Windows 高对比度开启、关闭或系统色变化时，已有日志和新输出同步采用对应底色与正文色，现有外观轮询同步面板。鼠标滚轮、触摸板、滚动条、方向／翻页键及选择正文暂停“自动滚动”，重新勾选才恢复追尾；后台继续接收日志。右键复制与 Ctrl+C 仅复制纯文本，可见区超过 100 万字符保留最后 70 万，原“复制全部日志”读取本次完整纯文本文件。追尾开关和阅读位置只保留当前窗口，不另存偏好。

**关闭与系统托盘：** 安装／卸载／构建清理进行中，点击窗口关闭、按 Esc 或使用底部关闭入口都直接退到系统托盘，后台任务和日志继续运行，不弹询问。任务完成后仍驻留，双击通知图标或选择“显示管理面板”恢复同一窗口、勾选与日志；托盘菜单显示当前状态。只有空闲关闭才询问“退到系统托盘／完全退出”，回车默认托盘，Esc 或“保留窗口”取消关闭选择；托盘的“完全退出”在任务中禁用并说明原因，执行出口再次检查任务，不能中途终止工作进程。真正退出才释放通知图标、菜单及计时器；托盘不可用时保留可见窗口。关闭选择不记忆，下次空闲关闭仍询问；托盘和隐藏状态仅属于本次进程。图标复用当前管理窗口的应用图标，无额外下载。

**整行选择：** 点击复选框、图标、功能文字、普通状态区或该功能行空白，仅切换该项一次，保留原 Tab／Space 复选框操作及勾选事件。任务执行中及不可用项禁止切换；失败日志链接和独立按钮优先执行自身动作，不连带勾选。组标题拖动、分组按钮和组尾空白不算功能行；移动、离开、滚动或触控滑动会取消本次点击候选，不接管原生滚动。选择本身不执行安装、卸载或清理，原默认空选、主题／语言切换保留勾选及持久化规则不变。

## 🔥 <span id="前言">前言</span>

负责“Flutter 安装依赖（pub get）。”的业务与独立包安装基础设施。用户使用上一级 Manage.cmd 的安装 / 更新或卸载面板，运行条件与菜单对象见 [功能 README](../README.md)。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、文件与职责 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 实际职责 |
| --- | --- |
| [Action.psm1](./Action.psm1) | 精确校验 Flutter 根与项目 SDK，同意后执行 pub get，可联网并更新锁文件与 .dart_tool。 |
| [Invoke.ps1](./Invoke.ps1/Invoke.ps1) | 菜单动作调度，读取本包目标并调用 Action，保存错误和结果。 |
| [Manage.ps1](./Manage.ps1/Manage.ps1) | 默认 `-Mode Manage` 打开本包安装 / 更新与卸载面板；默认空选，点击操作按钮后在 GUI 隐藏后台执行，不需要终端二次确认。 |
| [PackageInstaller.psm1](./PackageInstaller.psm1) | 声明校验、独立版本复制 / 哈希、菜单快照、状态提交与失败回滚。 |
| [Common.psm1](./Common.psm1) | 本包路径、目标、外部进程、日志与公共辅助；导入不运行业务。 |

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、调用与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

业务调度入口为 `Invoke-JobsFeature -Target <目标>`，由本包 Invoke.ps1 调用；本目录不是另一份总安装器。Action 中实现的具名功能包括：`Invoke-JobsFlutterProcess`、`Invoke-JobsFlutterAction`、`Invoke-JobsFeature`。

安装管理要求系统 Windows PowerShell Desktop 5.1、STA 与图形桌面。脚本自定位本包路径；安装写当前用户本功能菜单与状态，卸载保留运行版本、日志、备份、工具及停用记录，不自动卸载其它包。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、日志与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

业务修改范围以 Action 的所需功能为准，不能把安装确认当业务操作同意。日志和快照位于当前用户本包运行目录，由入口输出实际位置；详情见 [功能说明](../README.md)。文档只静态核对源码，没有执行安装、注册表写入或真实业务。

本目录的 `Manage.ps1/Manage.ps1`、`SelectionPanel.psm1` 和 `ManagementWorker.ps1/ManagementWorker.ps1` 构成本包自包含管理面板；由上级 `Manage.vbs` 无控制台启动。安装 / 卸载在隐藏后台执行，逐项状态与可复制实时日志留在面板中。日志区上沿的分隔条可上下拖动，调节结果在当前窗口保留；上下限为功能行、操作按钮和日志工具栏留出空间。日志正文右键可“复制”或“全选”，也支持 Ctrl+A / Ctrl+C；全选仅针对当前可见缓冲区，完整输出使用“复制全部日志”。总进度按已处理项 / 本次所选项显示计数和百分比；成功、未安装无需卸载与失败计入已处理，等待中、执行中和未执行项不计入；“未安装，无需卸载”单独显示且不算成功，最终分别汇总成功、无需卸载、失败与未执行数量。100% 仅表示本轮全部处理完毕。安装 / 更新和卸载分别计时；点击时只清零并启动当前操作计时，后台全部结束或启动失败时只冻结当前耗时。每秒刷新 `HH:mm:ss`（小时可超过 24），执行时显示“安装用时 / 卸载用时”，结束显示“安装总用时 / 卸载总用时”。两份耗时只在当前面板会话内独立保留。安装成功显示绿色“✅ 安装成功”。不改变右键业务工具自己的交互方式。失败状态可点击，在独立 PowerShell 中只读显示本次完整会话日志；包失败不阻止其它所选包，日志不可用时在面板提示。

**SDK 初始化进度：** 随包的 [SdkDownloadOutput.ps1](./SdkDownloadOutput.ps1/SdkDownloadOutput.ps1) 实时展示 SDK 相关命令输出，保留机器响应、退出码和超时边界；第一次调用 Flutter 触发 Dart / 工具缓存下载时，不再等待命令结束才显示。本动作仍要求现有项目 SDK；缺失 SDK 的安装由统一工具包的安装 / 切换入口处理。PubGet 的 URL / 认证信息继续脱敏后显示和落盘；测试不接触真实 SDK、账户缓存或系统菜单。

**SDK 环境准备：** 已选择的 SDK／版本所需下载、安装及首次 Flutter／Dart 缓存补齐自动执行；网络失败或无进度超时后持续重试，间隔逐步增加并封顶 30 秒，没有次数和总时长上限，直到成功或本人 Ctrl+C／停止。仍在输出下载进度的传输不按总时长截断；成功后才进入后续业务。目标／版本选择、官方许可证与系统权限仍由本人处理；路径、权限、磁盘或明确不存在的版本会报告具体原因。每次尝试和真实进度追加到终端所示日志；同一 URL 有 ETag／Last-Modified 时安全续传，跨来源保留独立临时文件，不拼接不同来源。失败／取消保留下载现场；业务构建和配置写入不因网络重试而整体重放。

**Flutter SDK网络预检：** 下载／首次Dart自举／precache前，随包网络模块以真实小Range验证来源、TLS、字节和吞吐并择优；显式storage、Pub和代理（含空值）保留，AUTO仅核验官方／CFUG同对象及当前已配置代理，不猜端口、不改系统代理或Git。当前任务短期复用；真实获取失败会降权坏路线、轮换其它已验证候选并持续重试。FVM按实际api context来源处理，能力允许时Git与Dart制品分阶段；用户fork不改源。原生BITS按真实WinINET通道衡量，PAC未能有界解析时保留既有通道并明确未测速。详细边界见[随包选路模块](./SdkDownloadRoute.ps1/README.md)。



<!-- JOBS_TERMINAL_STYLE_V1:BEGIN -->

> Windows 终端配色保护：支持完整颜色查询的交互控制台会先保存当前会话默认前景、背景与16色色表，再临时使用黑底白字和统一强调色；正常结束、业务失败及可捕获中断后恢复。用户运行中自行改动的颜色保留并提示，不修改用户主题、共享 Profile、注册表或全局策略。快照不包含进入前任意叠加的临时文字样式。非控制台、重定向、`NO_COLOR`、Sourcetree 及无法可靠保存／恢复颜色的环境保持原状态或降级为纯文本。

> 强制结束进程或终端崩溃无法保证自动恢复。恢复失败时保留并提示本轮 `%TEMP%\JobsTerminalStyle-<PID>-*.ps1` 恢复脚本，需在原控制台核对后运行；不要通过重置用户配置恢复。`-ExecutionPolicy Bypass` 如被入口使用，仅作用于本次子进程，不持久修改策略。

> 验证范围：已完成 PowerShell 语法、参数／退出与隔离生命周期核验；Windows 原生控制台的显示、按键与 `Ctrl+C` 实机验证尚未完成。

<!-- JOBS_TERMINAL_STYLE_V1:END -->


<!-- JOBS_SOURCE_SCRIPT_PACKAGES -->
**同名脚本包：** [Invoke.ps1](./Invoke.ps1/README.md)、[Manage.ps1](./Manage.ps1/README.md)、[ManagementWorker.ps1](./ManagementWorker.ps1/README.md)、[SdkDownloadOutput.ps1](./SdkDownloadOutput.ps1/README.md)。源码路径与发布目录的 flat 资源名分开维护。
<!-- /JOBS_SOURCE_SCRIPT_PACKAGES -->

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

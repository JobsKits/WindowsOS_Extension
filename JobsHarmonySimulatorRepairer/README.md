# JobsHarmonySimulatorRepairer · Harmony 模拟器检测与修复

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、功能与使用](#jobs-toc-heading-2)
- [二、安装、卸载与依赖](#jobs-toc-heading-3)
- [三、目录、日志与验证](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

**管理操作：** 本目录以 `Manage.cmd` 为轻量启动入口，只唤起 GUI 后结束本次脚本；先在面板选择安装 / 更新或卸载。在面板确认安装 / 更新或卸载后立即执行，无二次终端确认。任务开始前关闭或取消面板不会启动操作；卸载保留日志、备份、运行文件和工具。

## 🔥 <span id="前言">前言</span>

> **最低支持系统：Windows 10 x64。** 本地模拟器限官方支持的 AMD64 物理机；具体最低 build、Windows 5.1 / Explorer 菜单与真实模拟器仍须目标机验收。

仅在系统桌面空白右键显示“**Harmony 模拟器检测与修复**”。使用已有 [**DevEco Emulator**](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-command-line)，检测工具能力、已下载 Release 镜像和现有实例；选择后对该唯一实例执行保留数据的冷启动。


**面板外观与语言：** 总面板和独立功能面板右上角均可选择“黑夜 / 白天 / 跟随系统”以及“简体中文 / 繁體中文 / བོད་ཡིག / English / 日本語 / Français / Español / Deutsch / Русский / 한국어 / 跟随系统”，默认均跟随系统，切换立即生效并保留当前勾选、任务和日志。窄窗或长文案放不下时，工具组移至标题下一行并保持右对齐；极窄窗口将主题、语言分两行，下拉控件右边缘对齐。选择保存在当前用户的 `%LOCALAPPDATA%\Jobs\WindowsExtension\panel-preferences.json`，下次打开自动恢复；保存失败在面板显示原因。跟随系统每秒检查应用主题和当前用户显示语言，繁体中文界面使用繁体、其它中文使用简体，其余已支持语种按系统语言匹配，未支持语言回退英文；Windows 显示语言通常须重新登录才生效。切换涵盖面板正文、功能说明、状态与动态计数、操作提示和辅助名称；藏文优先使用已安装 Microsoft Himalaya / Noto Sans Tibetan，日韩使用对应系统字体，缺失时回退。语言名称始终显示自称，图标、功能名和状态列独立，长文字换行；切换只影响管理面板，已安装右键菜单标题及后台工具的原始日志保持各自语言。共享完整译文以 `Scripts/ManagerPanelTranslations.json` 为编辑来源，发布时内嵌到同源面板模块，独立包无需访问兄弟目录或联网翻译。

**管理面板关闭：** 空闲关闭时选择退到系统托盘或完全退出，默认回车为托盘、Esc 保留原窗；安装／卸载／构建清理进行中关闭直接后台，不询问、不终止任务。完工仍驻留，从托盘双击或“显示管理面板”恢复同一窗口；忙碌时不能完全退出。

**整行选择：** 点击复选框、图标、功能文字、普通状态区或该功能行空白，仅切换该项一次，保留原 Tab／Space 复选框操作及勾选事件。任务执行中及不可用项禁止切换；失败日志链接和独立按钮优先执行自身动作，不连带勾选。组标题拖动、分组按钮和组尾空白不算功能行；移动、离开、滚动或触控滑动会取消本次点击候选，不接管原生滚动。选择本身不执行安装、卸载或清理，原默认空选、主题／语言切换保留勾选及持久化规则不变。

**两种部署路线：** 源码管理面板默认使用“默认程序安装位置”，运行文件仍位于 `%LOCALAPPDATA%\Jobs\WindowsExtension\extensions\<功能ID>`。也可切换到“本地临时构建目录”，运行文件位于 `<功能包>\work\WindowsExtension\extensions\<功能ID>`；移走或清除该运行目录会使菜单失效。已部署副本的管理入口固定到自身真实路线，切换路线请从源码管理入口操作。菜单命令与 `deployment.json` 按当前路线定位配置，不依赖面板环境变量；提交失败恢复两侧状态。

**构建产物清理：** 安装位置选择、显示中的自动清理复选框与红色“🧹 清除构建产物”按钮排在同一行，垂直居中、间隔统一。英文或窄窗空间不足时，该行可水平滚动，文字保持完整，不拆成两行。仅默认安装位置路线显示默认关闭的“安装成功后清除此轮构建产物”和红底白字的“🧹 清除构建产物”独立按钮。自动清理仅处理本次成功安装产生的编译 GUID 子目录；独立按钮按当前选择清理本包 `work\JobsExtensionBuild` 专用编译工作区，不需要重新安装。临时路线隐藏清理控件。清理验证运行文件、标记与路径边界并持有事务锁，保留已经安装的 `.exe`、`.dll`、`.cmd`、`.ps1`、配置和注册表；自动清理失败明确显示“安装成功，清理失败”，独立清理失败正常报错。

**停止安装：** 安装进行中原按钮变为“停止安装”。点击只写停止请求，等待当前包事务完整结束，再把后续包标记为“未执行”；不强杀安装器、编译进程或资源管理器，未执行项不计失败或完成百分比。完成后可在同一面板继续清理、重试或关闭。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、功能与使用 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 入口 / 状态 | 行为 |
| --- | --- |
| `Run.cmd -Check` | 只读列出 CLI、镜像与实例，不创建日志、下载、接受许可或启动设备；未知输出报错。 |
| `Run.cmd/Run.cmd` 或桌面菜单 | 回车确认检测，选择唯一实例；停止状态经默认取消的键盘确认后冷启动，运行状态仍需输入精确 `YES` 才停止并冷启动。 |
| 实例为空 | 给出新建入口后停止，不创建替代实例。 |
| 工具、状态或身份不明 | 保留现场并停止，不猜测、不自动循环修复。 |

冷启动使用官方 `-start NAME -bootMode coldboot`（DevEco 6.1.0 Release 起支持），启动前复核名称、实例路径、设备类型和系统版本。运行中的实例先 `-stop NAME`，轮询官方 `isRunning=false` 后才启动，再回读 `isRunning=true`；这确认实例运行，不代表系统或 hdc 已就绪。不会使用 `reset`、删除镜像、清除应用或数据；重启会中断该实例的在途任务。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、安装、卸载与依赖 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

双击 [Manage.cmd](./Manage.cmd)，在同一面板选择安装 / 更新或卸载；也可在[总安装面板](../README.md)独立勾选。卸载只关闭本包菜单，保留模拟器、工具、日志和安装备份。安装需要现有 MSVC / Windows SDK，当前用户 COM 注册，无需管理员权限。

发现顺序为显式 `HARMONY_EMULATOR_BIN`、`DEVECO_STUDIO_HOME` / `TOOL_HOME`、常见 DevEco 安装位置、用户级 `LOCALAPPDATA/Jobs/HarmonySimulator/tools` 和 PATH；显式路径失效或发现多个兼容工具时停止。检测入口不安装工具或镜像、不修改代理和 PATH、不自动接受官方许可；需要开发者账号的镜像仍须在 DevEco Studio 完成本人授权。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、目录、日志与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 路径 | 职责 |
| --- | --- |
| [Scripts](./Scripts/README.md) | 自包含业务、原生桌面 handler、构建与安装事务。 |
| `Extension.json` | 固定独立身份 `harmony-simulator-repair`。 |
| `Manage.cmd` / `Run.cmd/Run.cmd` | 安装、卸载、独立检测与修复。 |

交互日志在当前用户 `LOCALAPPDATA/Jobs/WindowsExtension/extensions/harmony-simulator-repair/logs`，每次运行独立文件。安装状态和精确注册表备份同属本包根目录。隔离回归见 [HarmonySimulatorRepairer.Tests.ps1](../Tests/HarmonySimulatorRepairer.Tests.ps1/HarmonySimulatorRepairer.Tests.ps1)，不操作真实设备。官方参数及状态字段依据[华为命令行说明](https://developer.huawei.com/consumer/cn/doc/doccenter-deveco-studio/ide-emulator-command-line.md)。

管理安装 / 卸载时双击 `Manage.cmd`，它只通过 WScript 唤起 GUI，随后立即结束本次脚本；不在 CMD 中编译、安装或等待输入。也可直接双击 `Manage.vbs/Manage.vbs` 进入同一面板。每个选项显示等待、执行中、完成或失败，底部实时滚动标准输出和错误，可选中复制或点击“复制全部日志”；无可靠百分比时显示执行中，总体显示完成项数。运行期间等当前事务结束后关闭，完整管理日志位于系统临时目录 `JobsExtensionManager-<运行编号>.log`。



<!-- JOBS_TERMINAL_STYLE_V1:BEGIN -->

> Windows 终端配色保护：支持完整颜色查询的交互控制台会先保存当前会话默认前景、背景与16色色表，再临时使用黑底白字和统一强调色；正常结束、业务失败及可捕获中断后恢复。用户运行中自行改动的颜色保留并提示，不修改用户主题、共享 Profile、注册表或全局策略。快照不包含进入前任意叠加的临时文字样式。非控制台、重定向、`NO_COLOR`、Sourcetree 及无法可靠保存／恢复颜色的环境保持原状态或降级为纯文本。

> `.cmd`／`.bat` 入口内嵌完整会话守护：黑底白字及强调色保护就绪或明确降级后才开始业务，全部退出路径同步等待恢复回执；同时核对父进程身份。原 PowerShell／Python 启动命令和业务参数不经过再次解析，保护初始化后恢复进入时的延迟扩展模式，原业务自己的 `setlocal` 保留；嵌套 PowerShell 复用同一会话保护。守护脚本只写入本轮系统临时目录，成功恢复后清理控制文件。

> 强制结束进程或终端崩溃无法保证自动恢复。恢复失败时保留并提示本轮 `%TEMP%\JobsTerminalStyle-<PID>-*.ps1` 恢复脚本，需在原控制台核对后运行；不要通过重置用户配置恢复。`-ExecutionPolicy Bypass` 如被入口使用，仅作用于本次子进程，不持久修改策略。

> 验证范围：已完成 PowerShell 语法、参数／退出与隔离生命周期核验；Windows 原生控制台的显示、按键与 `Ctrl+C` 实机验证尚未完成。

<!-- JOBS_TERMINAL_STYLE_V1:END -->


<!-- JOBS_SOURCE_SCRIPT_PACKAGES -->
**同名脚本包：** [Manage.vbs](./Manage.vbs/README.md)、[Run.cmd](./Run.cmd/README.md)。源码路径与发布目录的 flat 资源名分开维护。
<!-- /JOBS_SOURCE_SCRIPT_PACKAGES -->

**键盘选择依赖：** 仅实际进入多项选择或最终执行确认时准备 fzf；健康路径、版本和真实选项探针通过就复用。缺失或损坏时沿当前流程调用当前用户 WinGet 安装／修复并刷新本进程 PATH；App Installer 缺失时仅打开一次官方界面并等待本流程复检，许可与系统权限由本人处理。网络失败持续重试至成功或 Ctrl+C；明确权限、磁盘、许可、版本阻塞停止。选择器不继承用户执行选项；默认取消，↑／↓／Tab 导航，← 返回真正上一层，Esc／Ctrl+C 取消。未进入选择、单一可复用目标、只读检查和管理 GUI 不因此安装依赖。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

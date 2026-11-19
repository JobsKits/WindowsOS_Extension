# `Scripts` Git 动态代理与桌面入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、真实文件与职责](#files)
- [二、依赖与执行边界](#dependencies)
- [三、产物、日志与验证](#outputs)

</details>
<!-- jobs-toc:end -->

---

**面板外观与语言：** 总面板和独立功能面板右上角均可选择“黑夜 / 白天 / 跟随系统”以及“简体中文 / 繁體中文 / བོད་ཡིག / English / 日本語 / Français / Español / Deutsch / Русский / 한국어 / 跟随系统”，默认均跟随系统，切换立即生效并保留当前勾选、任务和日志。窄窗或长文案放不下时，工具组移至标题下一行并保持右对齐；极窄窗口将主题、语言分两行，下拉控件右边缘对齐。选择保存在当前用户的 `%LOCALAPPDATA%\Jobs\WindowsExtension\panel-preferences.json`，下次打开自动恢复；保存失败在面板显示原因。跟随系统每秒检查应用主题和当前用户显示语言，繁体中文界面使用繁体、其它中文使用简体，其余已支持语种按系统语言匹配，未支持语言回退英文；Windows 显示语言通常须重新登录才生效。切换涵盖面板正文、功能说明、状态与动态计数、操作提示和辅助名称；藏文优先使用已安装 Microsoft Himalaya / Noto Sans Tibetan，日韩使用对应系统字体，缺失时回退。语言名称始终显示自称，图标、功能名和状态列独立，长文字换行；切换只影响管理面板，已安装右键菜单标题及后台工具的原始日志保持各自语言。共享完整译文以 `Scripts/ManagerPanelTranslations.json` 为编辑来源，发布时内嵌到同源面板模块，独立包无需访问兄弟目录或联网翻译。

**日志配色与滚动：** 日志使用独立的白天／黑夜背景、正文和错误／警告／成功／信息配色，ANSI 前景色按当前底色提高对比度；跟随系统采用对应一套。切换主题重配已有日志颜色，保留正文、选区和阅读位置。 Windows 高对比度开启、关闭或系统色变化时，已有日志和新输出同步采用对应底色与正文色，现有外观轮询同步面板。鼠标滚轮、触摸板、滚动条、方向／翻页键及选择正文暂停“自动滚动”，重新勾选才恢复追尾；后台继续接收日志。右键复制与 Ctrl+C 仅复制纯文本，可见区超过 100 万字符保留最后 70 万，原“复制全部日志”读取本次完整纯文本文件。追尾开关和阅读位置只保留当前窗口，不另存偏好。

**关闭与系统托盘：** 安装／卸载／构建清理进行中，点击窗口关闭、按 Esc 或使用底部关闭入口都直接退到系统托盘，后台任务和日志继续运行，不弹询问。任务完成后仍驻留，双击通知图标或选择“显示管理面板”恢复同一窗口、勾选与日志；托盘菜单显示当前状态。只有空闲关闭才询问“退到系统托盘／完全退出”，回车默认托盘，Esc 或“保留窗口”取消关闭选择；托盘的“完全退出”在任务中禁用并说明原因，执行出口再次检查任务，不能中途终止工作进程。真正退出才释放通知图标、菜单及计时器；托盘不可用时保留可见窗口。关闭选择不记忆，下次空闲关闭仍询问；托盘和隐藏状态仅属于本次进程。图标复用当前管理窗口的应用图标，无额外下载。

**整行选择：** 点击复选框、图标、功能文字、普通状态区或该功能行空白，仅切换该项一次，保留原 Tab／Space 复选框操作及勾选事件。任务执行中及不可用项禁止切换；失败日志链接和独立按钮优先执行自身动作，不连带勾选。组标题拖动、分组按钮和组尾空白不算功能行；移动、离开、滚动或触控滑动会取消本次点击候选，不接管原生滚动。选择本身不执行安装、卸载或清理，原默认空选、主题／语言切换保留勾选及持久化规则不变。

## 🔥 <span id="前言">前言</span>

本目录随独立包完整部署，不依赖总仓或其它包。桌面菜单安装与 Git 动态配置分开：菜单安装器只注册入口；用户点击后才进入配置确认。操作步骤、支持范围、路径优先级及恢复边界见[包 README](../README.md)。

## 一、<span id="files">真实文件与职责</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文件 | 职责与调用方 |
| --- | --- |
| [Manage.ps1](./Manage.ps1/Manage.ps1) | 包内安装 / 卸载入口，展示范围并确认，由裸露 CMD 调用。 |
| [PackageInstaller.psm1](./PackageInstaller.psm1) | 本包部署、备份和注册事务；只登记当前用户 `DesktopBackground`，列为通用模板的明确覆盖项。 |
| [Common.psm1](./Common.psm1)、[Invoke.ps1](./Invoke.ps1/Invoke.ps1) | 本包自带的目标解码、状态校验及运行入口。 |
| [Action.psm1](./Action.psm1) | 复核目标为当前系统桌面，再交给配置流程。 |
| [Configure.ps1](./Configure.ps1/Configure.ps1) | 可见终端的安装 / C 检查 / R 恢复交互；显式 Mode 供自动化使用。 |
| [ProxyInstaller.psm1](./ProxyInstaller.psm1) | 用户 PATH 和独立 Git 运行态的安装、私有快照、幂等、检查与精确恢复。 |
| [GitShim.cs](./GitShim.cs) | 编译真实 `git.exe`，参数经数据编码传递；原生 Git 继承输入输出句柄并返回其退出码。 |
| [Policy.ps1](./Policy.ps1/Policy.ps1) | 动态 Git 的内部入口，加载当前运行态桥接程序集和选路模块。 |
| [NetworkPolicy.psm1](./NetworkPolicy.psm1) | 原生 Git 配置解析、WinINET 静态代理发现、旁路匹配、短预检及一次业务转交。 |

## 二、<span id="dependencies">依赖与执行边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

使用系统 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) 5.1 Desktop 和 .NET Framework 编译 C# 桥接，菜单安装无须 MSVC。业务配置要求已有健康的 [**Git for Windows**](https://gitforwindows.org/)；HTTP 预检优先复用该安装或系统的 [**curl**](https://curl.se/docs/manpage.html)，没有工具时交回原始 Git，不联网安装依赖。

`Policy.ps1/Policy.ps1` 不是人工使用入口，不应手工拼接编码参数。安装、检查或恢复请运行上层 [ConfigureGit.cmd](../ConfigureGit.cmd/ConfigureGit.cmd)。系统代理只读取；代理变量和命令行配置仅传给当次业务子进程。原生 Git 的原始错误不写进脱敏审计。

## 三、<span id="outputs">产物、日志与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

菜单发布文件位于当前用户 `Jobs\WindowsExtension`；动态 Git 位于 `%LOCALAPPDATA%\JobsGitNetworkStrategy\runtime\bin`，与菜单版本独立。私有快照、`active.clixml`、`install.log` 和 `logs\route.log` 均保存在同一动态策略根目录。卸载菜单不会恢复用户 PATH 或删除业务快照。

修改运行源码后应同步测试参数透明性、显式配置保留、路由选择、业务至多一次及恢复冲突。隔离回归入口为 [GitProxyConfigurator.Tests.ps1](../../Tests/GitProxyConfigurator.Tests.ps1/GitProxyConfigurator.Tests.ps1)；跨端测试不能替代 Windows 控制台、真实注册表或 Explorer 验收。

本目录的 `Manage.ps1/Manage.ps1`、`SelectionPanel.psm1` 和 `ManagementWorker.ps1/ManagementWorker.ps1` 构成本包自包含管理面板；由上级 `Manage.vbs` 无控制台启动。安装 / 卸载在隐藏后台执行，逐项状态与可复制实时日志留在面板中。日志区上沿的分隔条可上下拖动，调节结果在当前窗口保留；上下限为功能行、操作按钮和日志工具栏留出空间。日志正文右键可“复制”或“全选”，也支持 Ctrl+A / Ctrl+C；全选仅针对当前可见缓冲区，完整输出使用“复制全部日志”。总进度按已处理项 / 本次所选项显示计数和百分比；成功、未安装无需卸载与失败计入已处理，等待中、执行中和未执行项不计入；“未安装，无需卸载”单独显示且不算成功，最终分别汇总成功、无需卸载、失败与未执行数量。100% 仅表示本轮全部处理完毕。安装 / 更新和卸载分别计时；点击时只清零并启动当前操作计时，后台全部结束或启动失败时只冻结当前耗时。每秒刷新 `HH:mm:ss`（小时可超过 24），执行时显示“安装用时 / 卸载用时”，结束显示“安装总用时 / 卸载总用时”。两份耗时只在当前面板会话内独立保留。安装成功显示绿色“✅ 安装成功”。不改变右键业务工具自己的交互方式。失败状态可点击，在独立 PowerShell 中只读显示本次完整会话日志；包失败不阻止其它所选包，日志不可用时在面板提示。



<!-- JOBS_TERMINAL_STYLE_V1:BEGIN -->

> Windows 终端配色保护：支持完整颜色查询的交互控制台会先保存当前会话默认前景、背景与16色色表，再临时使用黑底白字和统一强调色；正常结束、业务失败及可捕获中断后恢复。用户运行中自行改动的颜色保留并提示，不修改用户主题、共享 Profile、注册表或全局策略。快照不包含进入前任意叠加的临时文字样式。非控制台、重定向、`NO_COLOR`、Sourcetree 及无法可靠保存／恢复颜色的环境保持原状态或降级为纯文本。

> 强制结束进程或终端崩溃无法保证自动恢复。恢复失败时保留并提示本轮 `%TEMP%\JobsTerminalStyle-<PID>-*.ps1` 恢复脚本，需在原控制台核对后运行；不要通过重置用户配置恢复。`-ExecutionPolicy Bypass` 如被入口使用，仅作用于本次子进程，不持久修改策略。

> 验证范围：已完成 PowerShell 语法、参数／退出与隔离生命周期核验；Windows 原生控制台的显示、按键与 `Ctrl+C` 实机验证尚未完成。

<!-- JOBS_TERMINAL_STYLE_V1:END -->


<!-- JOBS_SOURCE_SCRIPT_PACKAGES -->
**同名脚本包：** [Configure.ps1](./Configure.ps1/README.md)、[Invoke.ps1](./Invoke.ps1/README.md)、[Manage.ps1](./Manage.ps1/README.md)、[ManagementWorker.ps1](./ManagementWorker.ps1/README.md)、[Policy.ps1](./Policy.ps1/README.md)。源码路径与发布目录的 flat 资源名分开维护。
<!-- /JOBS_SOURCE_SCRIPT_PACKAGES -->

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

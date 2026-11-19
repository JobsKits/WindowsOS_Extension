# `JobsFileHasher/Scripts`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、菜单与业务](#jobs-toc-heading-2)
- [二、管理、日志与验证](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录只包含 `file-hash` 的业务和随包基础设施。公开管理入口为上级 [Manage.cmd](../Manage.cmd)，不借用其它功能包或父工程的运行脚本。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、菜单与业务 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 职责 |
| --- | --- |
| [ContextMenu.cpp](./ContextMenu.cpp)、[FileHashTarget.h](./FileHashTarget.h) | 只对单个普通文件显示“🔎 查看文件指纹 Hash（SHA-256）”；用 CreateProcess 的 argv 打开新的 STA [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) 控制台。 |
| [Invoke.ps1](./Invoke.ps1/Invoke.ps1)、[Action.psm1](./Action.psm1) | 核验本包启用状态及路径，再进入唯一 Hash 业务；失败显示错误，窗口回车关闭。 |
| [FileHash.ps1](./FileHash.ps1/FileHash.ps1) | 流式 SHA-256、路径转义、Unicode 纯摘要剪贴板与有限重试；失败不复制旧摘要。 |
| [Build.ps1](./Build.ps1/Build.ps1)、[ContextMenu.def](./ContextMenu.def) | 用已有 MSVC 构建独立 `JobsFileHasherContextMenu.dll`，不注册。 |

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、管理、日志与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

`Manage.ps1/Manage.ps1`、`SelectionPanel.psm1`、`ManagementWorker.ps1/ManagementWorker.ps1` 提供本包安装 / 更新、卸载、两种部署路线、清理和合作式停止；`PackageInstaller.psm1` 只登记本包的 handler / CLSID，保留快照并在失败时恢复。`Common.psm1` 依据运行副本元数据定位安装状态及固定状态日志；日志与备份不包含正文。管理完整会话日志位于系统临时目录 `JobsExtensionManager-<运行编号>.log`。

运行端可 `Ctrl+C` 取消计算；目录、多选与链接不适用，不执行目标文件。隔离回归见上级 [功能说明](../README.md)；原生 Explorer 新窗口、真实系统剪贴板、PowerShell 5.1 / MSVC 结果与跨平台逻辑测试分开验收。



<!-- JOBS_TERMINAL_STYLE_V1:BEGIN -->

> Windows 终端配色保护：支持完整颜色查询的交互控制台会先保存当前会话默认前景、背景与16色色表，再临时使用黑底白字和统一强调色；正常结束、业务失败及可捕获中断后恢复。用户运行中自行改动的颜色保留并提示，不修改用户主题、共享 Profile、注册表或全局策略。快照不包含进入前任意叠加的临时文字样式。非控制台、重定向、`NO_COLOR`、Sourcetree 及无法可靠保存／恢复颜色的环境保持原状态或降级为纯文本。

> 强制结束进程或终端崩溃无法保证自动恢复。恢复失败时保留并提示本轮 `%TEMP%\JobsTerminalStyle-<PID>-*.ps1` 恢复脚本，需在原控制台核对后运行；不要通过重置用户配置恢复。`-ExecutionPolicy Bypass` 如被入口使用，仅作用于本次子进程，不持久修改策略。

> 验证范围：已完成 PowerShell 语法、参数／退出与隔离生命周期核验；Windows 原生控制台的显示、按键与 `Ctrl+C` 实机验证尚未完成。

<!-- JOBS_TERMINAL_STYLE_V1:END -->


<!-- JOBS_SOURCE_SCRIPT_PACKAGES -->
**同名脚本包：** [Build.ps1](./Build.ps1/README.md)、[FileHash.ps1](./FileHash.ps1/README.md)、[Invoke.ps1](./Invoke.ps1/README.md)、[Manage.ps1](./Manage.ps1/README.md)、[ManagementWorker.ps1](./ManagementWorker.ps1/README.md)。源码路径与发布目录的 flat 资源名分开维护。
<!-- /JOBS_SOURCE_SCRIPT_PACKAGES -->

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

**日志配色与滚动：** 日志使用独立的白天／黑夜背景、正文和错误／警告／成功／信息配色，ANSI 前景色按当前底色提高对比度；跟随系统采用对应一套。切换主题重配已有日志颜色，保留正文、选区和阅读位置。 Windows 高对比度开启、关闭或系统色变化时，已有日志和新输出同步采用对应底色与正文色，现有外观轮询同步面板。鼠标滚轮、触摸板、滚动条、方向／翻页键及选择正文暂停“自动滚动”，重新勾选才恢复追尾；后台继续接收日志。右键复制与 Ctrl+C 仅复制纯文本，可见区超过 100 万字符保留最后 70 万，原“复制全部日志”读取本次完整纯文本文件。追尾开关和阅读位置只保留当前窗口，不另存偏好。

**关闭与系统托盘：** 安装／卸载／构建清理进行中，点击窗口关闭、按 Esc 或使用底部关闭入口都直接退到系统托盘，后台任务和日志继续运行，不弹询问。任务完成后仍驻留，双击通知图标或选择“显示管理面板”恢复同一窗口、勾选与日志；托盘菜单显示当前状态。只有空闲关闭才询问“退到系统托盘／完全退出”，回车默认托盘，Esc 或“保留窗口”取消关闭选择；托盘的“完全退出”在任务中禁用并说明原因，执行出口再次检查任务，不能中途终止工作进程。真正退出才释放通知图标、菜单及计时器；托盘不可用时保留可见窗口。关闭选择不记忆，下次空闲关闭仍询问；托盘和隐藏状态仅属于本次进程。图标复用当前管理窗口的应用图标，无额外下载。

**整行选择：** 点击复选框、图标、功能文字、普通状态区或该功能行空白，仅切换该项一次，保留原 Tab／Space 复选框操作及勾选事件。任务执行中及不可用项禁止切换；失败日志链接和独立按钮优先执行自身动作，不连带勾选。组标题拖动、分组按钮和组尾空白不算功能行；移动、离开、滚动或触控滑动会取消本次点击候选，不接管原生滚动。选择本身不执行安装、卸载或清理，原默认空选、主题／语言切换保留勾选及持久化规则不变。

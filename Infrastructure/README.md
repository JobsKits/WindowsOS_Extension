# `Windows 扩展基础设施`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、真实文件与用途](#jobs-toc-heading-2)
- [二、运行条件与范围](#jobs-toc-heading-3)
- [三、目录关系与验证](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

独立功能包的公共安装、调用与运行时基础模块。各包携带所需副本，用户运行所选包自身入口；此目录不提供总安装面板。


**面板外观与语言：** 总面板和独立功能面板右上角均可选择“黑夜 / 白天 / 跟随系统”以及“简体中文 / 繁體中文 / English / 跟随系统”，默认均跟随系统，切换立即生效并保留当前勾选、任务和日志。窄窗或长文案放不下时，工具组移至标题下一行并保持右对齐；极窄窗口将主题、语言分两行，下拉控件右边缘对齐。选择保存在当前用户的 `%LOCALAPPDATA%\Jobs\WindowsExtension\panel-preferences.json`，下次打开自动恢复；保存失败在面板显示原因。跟随系统每秒检查应用主题和当前用户显示语言，繁体中文界面使用繁体、其它中文使用简体，未支持语言回退英文；Windows 显示语言通常须重新登录才生效。切换只影响管理面板，已安装右键菜单标题及后台工具的原始日志保持各自语言。

**两种部署路线：** 源码管理面板默认使用“默认程序安装位置”，运行文件仍位于 `%LOCALAPPDATA%\Jobs\WindowsExtension\extensions\<功能ID>`。也可切换到“本地临时构建目录”，运行文件位于 `<功能包>\work\WindowsExtension\extensions\<功能ID>`；移走或清除该运行目录会使菜单失效。已部署副本的管理入口固定到自身真实路线，切换路线请从源码管理入口操作。菜单命令与 `deployment.json` 按当前路线定位配置，不依赖面板环境变量；提交失败恢复两侧状态。

**构建产物清理：** 安装位置选择、显示中的自动清理复选框与红色“🧹 清除构建产物”按钮排在同一行，垂直居中、间隔统一。英文或窄窗空间不足时，该行可水平滚动，文字保持完整，不拆成两行。仅默认安装位置路线显示默认关闭的“安装成功后清除此轮构建产物”和红底白字的“🧹 清除构建产物”独立按钮。自动清理仅处理本次成功安装产生的编译 GUID 子目录；独立按钮按当前选择清理本包 `work\JobsExtensionBuild` 专用编译工作区，不需要重新安装。临时路线隐藏清理控件。清理验证运行文件、标记与路径边界并持有事务锁，保留已经安装的 `.exe`、`.dll`、`.cmd`、`.ps1`、配置和注册表；自动清理失败明确显示“安装成功，清理失败”，独立清理失败正常报错。

**停止安装：** 安装进行中原按钮变为“停止安装”。点击只写停止请求，等待当前包事务完整结束，再把后续包标记为“未执行”；不强杀安装器、编译进程或资源管理器，未执行项不计失败或完成百分比。完成后可在同一面板继续清理、重试或关闭。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、真实文件与用途 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 职责 |
| --- | --- |
| [Manage.cmd](./Manage.cmd) | 随包轻量启动模板，只唤起 `Manage.vbs` 后结束本次脚本，不承载安装或等待输入。 |
| [Manage.vbs](./Manage.vbs) | 随包 WScript 模板，以包自身完整路径隐藏启动 PowerShell GUI。 |
| [Manage.ps1](./Manage.ps1) | `-Mode Manage / Install / Uninstall`，读取所属包声明、打开同一个管理面板，面板确认后由隐藏后台注册或移除当前用户的该项菜单。 |
| [SelectionPanel.psm1](./SelectionPanel.psm1) | 逐项选择和等待 / 执行中 / 成功 / 失败状态，底部双流实时日志、上下拖动调高、右键全选 / 复制及自动滚动；按字体与 DPI 为计数、长标题、状态及工具栏分配空间，必要时换行；与总面板同字节。 |
| [ManagementWorker.ps1](./ManagementWorker.ps1) | 隐藏执行逐包事务并输出逐叶状态事件；单包失败后继续其它所选包，实际操作仍由对应安装器负责。 |
| [PackageInstaller.psm1](./PackageInstaller.psm1) | 校验包声明、复制版本文件、保存注册表与状态快照、更新本包启用状态和菜单。 |
| [Common.psm1](./Common.psm1) | 本包路径、配置、进程调用和日志等公共能力；导入不等于执行业务。 |
| [Invoke.ps1](./Invoke.ps1) | 根据所属包 Action 模块调度菜单动作，保存失败信息与退出码。 |

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、运行条件与范围 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

管理入口要求 Windows PowerShell Desktop 5.1、STA 和可用 WinForms，由各功能包 `Manage.cmd` 轻量唤起 `Manage.vbs`，随后立即结束启动脚本，隐藏 PowerShell 承担后续执行；也可直接双击 `Manage.vbs`；复制使用时须包含该包 Extension.json 与 Action 模块，不能只运行基础模块。安装与卸载只改当前用户、本功能注册表项与运行状态，写前保存精确备份。卸载保留禁用状态、运行文件、工具、备份和日志；不提权，不持久更改执行策略，不配置系统代理。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、目录关系与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

[平台总览](../README.md)负责组合面板与功能清单，[Scripts](../Scripts/README.md)负责总入口调度，具体业务属于各 Jobs* 包。面板逐字符接收标准输出 / 错误，无换行命令进度也增量显示；当前步骤没有可靠百分比时显示执行中。总进度按已处理项 / 本次所选项显示计数和百分比；成功与失败计入已处理，等待中、执行中和未执行项不计入，100% 表示全部处理完毕，结果以成功 / 失败汇总为准。安装 / 更新和卸载分别计时；点击时只清零并启动当前操作计时，后台全部结束或启动失败时只冻结当前耗时。每秒刷新 `HH:mm:ss`（小时可超过 24），执行时显示“安装用时 / 卸载用时”，结束显示“安装总用时 / 卸载总用时”。两份耗时只在当前面板会话内独立保留。安装成功显示绿色“✅ 安装成功”。执行中不能关闭面板，等事务结束后复制日志或关闭。失败项显示红色“失败，见日志”，点击后新开 PowerShell 窗口，用 `Get-Content -LiteralPath` 只读显示本次完整会话日志；提示包含实际日志位置。其它状态不可点击，日志缺失、不可读或终端无法启动时在面板显示具体原因；不影响当前后台任务，也不执行日志正文。日志区上沿的分隔条可上下拖动，调节结果在当前窗口保留；上下限为功能行、操作按钮和日志工具栏留出空间。日志正文右键可“复制”或“全选”，也支持 Ctrl+A / Ctrl+C；全选仅针对当前可见缓冲区，完整输出使用“复制全部日志”。完整面板日志位于系统临时目录 `JobsExtensionManager-<运行编号>.log`，可见区限长但“复制全部日志”读取完整文件。产物、业务日志和备份位于安装器显示的当前用户本包目录；本文按源码核对，未安装菜单或写入真实注册表。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

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

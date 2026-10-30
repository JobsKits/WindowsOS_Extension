# `JobsTerminalOpener Scripts`

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

## 🔥 <span id="前言">前言</span>

负责“用终端打开。”的业务与独立包安装基础设施。用户使用上一级 Manage.cmd 的安装 / 更新或卸载面板，运行条件与菜单对象见 [功能 README](../README.md)。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、文件与职责 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 实际职责 |
| --- | --- |
| [Action.psm1](./Action.psm1) | 在目标目录打开命令终端，文件目标使用父目录，不执行工程构建或依赖更新。 |
| [Invoke.ps1](./Invoke.ps1) | 菜单动作调度，读取本包目标并调用 Action，保存错误和结果。 |
| [Manage.ps1](./Manage.ps1) | 默认 `-Mode Manage` 打开本包安装 / 更新与卸载面板；默认空选，点击操作按钮后在 GUI 隐藏后台执行，不需要终端二次确认。 |
| [PackageInstaller.psm1](./PackageInstaller.psm1) | 声明校验、独立版本复制 / 哈希、菜单快照、状态提交与失败回滚。 |
| [Common.psm1](./Common.psm1) | 本包路径、目标、外部进程、日志与公共辅助；导入不运行业务。 |

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、调用与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

业务调度入口为 `Invoke-JobsFeature -Target <目标>`，由本包 Invoke.ps1 调用；本目录不是另一份总安装器。Action 中实现的具名功能包括：`Invoke-JobsFeature`。

安装管理要求系统 Windows PowerShell Desktop 5.1、STA 与图形桌面。脚本自定位本包路径；安装写当前用户本功能菜单与状态，卸载保留运行版本、日志、备份、工具及停用记录，不自动卸载其它包。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、日志与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

业务修改范围以 Action 的所需功能为准，不能把安装确认当业务操作同意。日志和快照位于当前用户本包运行目录，由入口输出实际位置；详情见 [功能说明](../README.md)。文档只静态核对源码，没有执行安装、注册表写入或真实业务。

本目录的 `Manage.ps1`、`SelectionPanel.psm1` 和 `ManagementWorker.ps1` 构成本包自包含管理面板；由上级 `Manage.vbs` 无控制台启动。安装 / 卸载在隐藏后台执行，逐项状态与可复制实时日志留在面板中。日志区上沿的分隔条可上下拖动，调节结果在当前窗口保留；上下限为功能行、操作按钮和日志工具栏留出空间。日志正文右键可“复制”或“全选”，也支持 Ctrl+A / Ctrl+C；全选仅针对当前可见缓冲区，完整输出使用“复制全部日志”。总进度按已处理项 / 本次所选项显示计数和百分比；成功与失败计入已处理，等待中、执行中和未执行项不计入，100% 表示全部处理完毕，结果以成功 / 失败汇总为准。安装 / 更新和卸载分别计时；点击时只清零并启动当前操作计时，后台全部结束或启动失败时只冻结当前耗时。每秒刷新 `HH:mm:ss`（小时可超过 24），执行时显示“安装用时 / 卸载用时”，结束显示“安装总用时 / 卸载总用时”。两份耗时只在当前面板会话内独立保留。安装成功显示绿色“✅ 安装成功”。不改变右键业务工具自己的交互方式。失败状态可点击，在独立 PowerShell 中只读显示本次完整会话日志；包失败不阻止其它所选包，日志不可用时在面板提示。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

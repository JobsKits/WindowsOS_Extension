# `Scripts`：Flutter SDK 安装与切换

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录是 [JobsFlutterVersionMgr](../README.md) 的自包含运行与安装源码。安装从包根的 [`Manage.cmd`](../Manage.cmd) 开始，卸载使用 [`Manage.cmd`](../Manage.cmd)；右键操作由已部署的 `Invoke.ps1` 在可见终端启动。不要把本目录拆散后单独分发。

| 文件 | 职责 |
| --- | --- |
| [Manage.ps1](./Manage.ps1) | 检查 Windows PowerShell 5.1 与 STA，确认后仅管理本包菜单。 |
| [PackageInstaller.psm1](./PackageInstaller.psm1) | 复制及校验本包运行文件、当前用户菜单注册、备份、状态事务与卸载。 |
| [Common.psm1](./Common.psm1) | 本包内嵌的路径、参数、进程及日志基础工具。 |
| [Invoke.ps1](./Invoke.ps1) | 校验本包启用状态，加载本包 Action，报告失败并保留终端。 |
| [Action.psm1](./Action.psm1) | 严格项目门禁、条件修复工具链、官方版本查询、fzf 单选、备份和精确项目 SDK 绑定。 |

安装器复制直属 `.ps1` / `.psm1` 进入独立 release，测试不会打包；运行时不读取总目录或相邻包。四份基础设施模块与仓库模板保持一致，唯一业务模块是 `Action.psm1`。

项目门禁首先运行，非法目标不会触发依赖安装。健康 Git / fzf / FVM 直接复用；缺 Git / fzf 时才检查 WinGet。必需组件安装回车执行、任意字符取消；最终项目操作同样直接回车执行安装/切换、任意非空输入取消，空格也会取消。Esc 选版取消不修改项目。

本包菜单安装不联网、不提权；业务工具安装和未缓存 SDK 下载会联网，并分别显示来源、范围与确认。PATH 与 TLS 1.2 补充只作用当前进程，退出后恢复；不修改网络代理或系统开发者模式。具体 SDK 来源服从 FVM 现有配置。

状态、私有工具、业务日志和备份位于当前用户本地应用数据的 `Jobs\WindowsExtension\extensions\flutter-version-manager`。切换前在项目外备份配置，既有 SDK 链接只记录目标；失败现场与已下载 SDK 保留。恢复方法、版本与权限限制见[包说明](../README.md#四文件日志与恢复)。

测试入口位于仓库 [`Tests/FlutterVersionMgr.Tests.ps1`](../../Tests/FlutterVersionMgr.Tests.ps1)，仅使用隔离夹具；Windows 真实菜单和 SDK 安装需单独验收。

本目录的 `Manage.ps1`、`SelectionPanel.psm1` 和 `ManagementWorker.ps1` 构成本包自包含管理面板；由上级 `Manage.vbs` 无控制台启动。安装 / 卸载在隐藏后台执行，逐项状态与可复制实时日志留在面板中。日志区上沿的分隔条可上下拖动，调节结果在当前窗口保留；上下限为功能行、操作按钮和日志工具栏留出空间。日志正文右键可“复制”或“全选”，也支持 Ctrl+A / Ctrl+C；全选仅针对当前可见缓冲区，完整输出使用“复制全部日志”。总进度按已处理项 / 本次所选项显示计数和百分比；成功与失败计入已处理，等待中、执行中和未执行项不计入，100% 表示全部处理完毕，结果以成功 / 失败汇总为准。安装 / 更新和卸载分别计时；点击时只清零并启动当前操作计时，后台全部结束或启动失败时只冻结当前耗时。每秒刷新 `HH:mm:ss`（小时可超过 24），执行时显示“安装用时 / 卸载用时”，结束显示“安装总用时 / 卸载总用时”。两份耗时只在当前面板会话内独立保留。安装成功显示绿色“✅ 安装成功”。不改变右键业务工具自己的交互方式。失败状态可点击，在独立 PowerShell 中只读显示本次完整会话日志；包失败不阻止其它所选包，日志不可用时在面板提示。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

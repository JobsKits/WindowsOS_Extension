# JobsHarmonySimulatorRepairer · Scripts

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、文件职责](#jobs-toc-heading-2)
- [二、入口、依赖与产物](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录随独立包完整交付，不读取总目录或相邻功能的业务代码。完整范围、风险和运行例子见[功能说明](../README.md)。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、文件职责 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 职责 |
| --- | --- |
| `Action.psm1` | 本包菜单业务入口。 |
| `Common.psm1` | 本包内嵌通用路径、日志与进程工具。 |
| `Invoke.ps1` | 验证已安装状态后转交本包业务。 |
| `Manage.ps1 / PackageInstaller.psm1` | 本包独立安装、卸载、精确备份与事务回滚。 |
| `ContextMenu.cpp / ContextMenu.def / Build.ps1` | 原生 COM 过滤、导出和 MSVC 构建；构建不注册。 |
| `OpenCmd.ps1` | 在独立终端安全转交已选路径。 |
| `HarmonyInstanceIdentity.cs` | 读取实例目录与 config.ini 的真实卷号和文件 ID，阻止同名同路径替换。 |
| `DesktopScope.h` | 精确系统桌面背景范围。 |
| `RepairHarmonySimulator.ps1` | 独立检查 / 修复，Check 为只读。 |

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、入口、依赖与产物 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

从上级目录运行 `Manage.cmd` 管理菜单；`Run.cmd` 运行独立业务，`Run.cmd -Check` 仅做只读体检。业务先显示用途并确认，安装不执行检测、重启或权限修改。依赖 Windows PowerShell 5.1，原生构建需要现有 MSVC 和 Windows SDK；官方 DevEco Emulator 必须支持 -list/-details/-imageList/-start/-stop/-bootMode。

菜单状态、安装备份、release、日志按 `Extension.json` 的独立 Id 位于当前用户 `LOCALAPPDATA/Jobs/WindowsExtension/extensions/`；交互检测日志位于本包 logs，每次独立；Check 不写日志。

本目录的 `Manage.ps1`、`SelectionPanel.psm1` 和 `ManagementWorker.ps1` 构成本包自包含管理面板；由上级 `Manage.vbs` 无控制台启动。安装 / 卸载在隐藏后台执行，逐项状态与可复制实时日志留在面板中。日志区上沿的分隔条可上下拖动，调节结果在当前窗口保留；上下限为功能行、操作按钮和日志工具栏留出空间。日志正文右键可“复制”或“全选”，也支持 Ctrl+A / Ctrl+C；全选仅针对当前可见缓冲区，完整输出使用“复制全部日志”。总进度按已处理项 / 本次所选项显示计数和百分比；成功与失败计入已处理，等待中、执行中和未执行项不计入，100% 表示全部处理完毕，结果以成功 / 失败汇总为准。安装 / 更新和卸载分别计时；点击时只清零并启动当前操作计时，后台全部结束或启动失败时只冻结当前耗时。每秒刷新 `HH:mm:ss`（小时可超过 24），执行时显示“安装用时 / 卸载用时”，结束显示“安装总用时 / 卸载总用时”。两份耗时只在当前面板会话内独立保留。安装成功显示绿色“✅ 安装成功”。不改变右键业务工具自己的交互方式。失败状态可点击，在独立 PowerShell 中只读显示本次完整会话日志；包失败不阻止其它所选包，日志不可用时在面板提示。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

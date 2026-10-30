# `JobsFlutterCodegen/Scripts`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、文件与入口](#entrypoints)
- [二、维护与验证](#maintenance)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录只实现本包的“Flutter 自动化生产代码”菜单与终端动作。运行和独立安装不查找父目录或相邻功能；[功能说明](../README.md)包含依赖、交互和风险。

## 一、<span id="entrypoints">文件与入口</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文件 | 职责 |
| --- | --- |
| `Manage.ps1` / `PackageInstaller.psm1` | 独立安装卸载、release、哈希、备份、COM 注册与事务恢复；优先从包根 `Manage.cmd` 打开。 |
| `Build.ps1` | 仅用已安装 MSVC / Windows SDK 编译本包原生 DLL；不下载或注册。 |
| `ContextMenu.cpp` / `FlutterProject.h` / `ContextMenu.def` | Explorer 内只读本地 pubspec，精确单选根目录识别；不在 Explorer 内执行 PowerShell、Flutter 或 CLR。 |
| `OpenCmd.ps1` | 固定命令启动 CMD，目标与入口经环境变量传递。 |
| `Invoke.ps1` / `Common.psm1` | 校验当前包安装状态、解析目标、调用本包 Action、显示错误和维护日志。 |
| `Action.psm1` | 本功能业务；同源 SDK、逐行输出、失败停止和脱敏日志。 |
| `Check.ps1` | 只读项目与生成计划，不启动 SDK 子进程。 |

## 二、<span id="maintenance">维护与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

四份基础机制在开发时由总工程模板校验，`PackageInstaller.psm1` 是本包明确声明的覆盖项，负责原生 COM 构建事务，其余三份保持模板一致。业务入口仅导出 `Invoke-JobsFeature`；不要将项目路径拼入 `-Command` 或 CMD 可执行文本。PowerShell 文件使用 UTF-8 BOM 与 CRLF，CMD 正文使用 ASCII 与 CRLF，兼容系统 PowerShell 5.1。

[独立回归](../../Tests/FlutterDoctorCodegen.Tests.ps1)使用临时项目与假工具，不执行真实项目生成。真实安装需 Windows 桌面及原生编译环境；本机 macOS 逻辑回归只能验证配置 / 参数 / 事务计划，不能证明 Explorer 内 COM 已成功加载。日志和卸载边界见[功能说明](../README.md#check-and-logs)。

本目录的 `Manage.ps1`、`SelectionPanel.psm1` 和 `ManagementWorker.ps1` 构成本包自包含管理面板；由上级 `Manage.vbs` 无控制台启动。安装 / 卸载在隐藏后台执行，逐项状态与可复制实时日志留在面板中。日志区上沿的分隔条可上下拖动，调节结果在当前窗口保留；上下限为功能行、操作按钮和日志工具栏留出空间。日志正文右键可“复制”或“全选”，也支持 Ctrl+A / Ctrl+C；全选仅针对当前可见缓冲区，完整输出使用“复制全部日志”。总进度按已处理项 / 本次所选项显示计数和百分比；成功与失败计入已处理，等待中、执行中和未执行项不计入，100% 表示全部处理完毕，结果以成功 / 失败汇总为准。安装 / 更新和卸载分别计时；点击时只清零并启动当前操作计时，后台全部结束或启动失败时只冻结当前耗时。每秒刷新 `HH:mm:ss`（小时可超过 24），执行时显示“安装用时 / 卸载用时”，结束显示“安装总用时 / 卸载总用时”。两份耗时只在当前面板会话内独立保留。安装成功显示绿色“✅ 安装成功”。不改变右键业务工具自己的交互方式。失败状态可点击，在独立 PowerShell 中只读显示本次完整会话日志；包失败不阻止其它所选包，日志不可用时在面板提示。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

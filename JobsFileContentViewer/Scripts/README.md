# `JobsFileContentViewer Scripts`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、入口与职责](#jobs-toc-heading-2)
- [二、确认、输出与验证](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录承载单文件“📄 用终端查看文件内容”的原生菜单、只读流式输出与独立安装事务。用户从上级 [Manage.cmd](../Manage.cmd) 进入安装 / 更新或卸载面板，确认后立即执行；显示条件、阈值和用法见 [功能说明](../README.md)。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、入口与职责 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 职责 |
| --- | --- |
| [ContextMenu.cpp](./ContextMenu.cpp) / [FileViewerTarget.h](./FileViewerTarget.h) | 只接受单个普通文件；不读正文，不为目录、多选、链接或设备插入菜单；新开可见控制台，以 `-File` 和转义参数启动本包入口。 |
| [Invoke.ps1](./Invoke.ps1) | 核对本包启用状态、解析路径、调用 Action；错误可见，结束后回车关闭。 |
| [Action.psm1](./Action.psm1) / [FileViewer.ps1](./FileViewer.ps1) | 目标复核、1 MiB / 自定义阈值门禁、二进制 / 编码确认、固定块只读输出与控制字符转义。入口为 `Invoke-JobsFeature -Target`。 |
| [Manage.ps1](./Manage.ps1) | 本包安装 / 更新与卸载选择面板，取消无操作。 |
| [PackageInstaller.psm1](./PackageInstaller.psm1) | 本包文件复制 / 哈希、原生构建、HKCU 菜单快照、事务回滚与状态提交；卸载只处理本包。 |
| [Build.ps1](./Build.ps1) / [ContextMenu.def](./ContextMenu.def) | 复用已安装 MSVC / Windows SDK 编译原生 DLL，不注册、不联网安装依赖。 |
| [Common.psm1](./Common.psm1) | 内嵌公共路径、参数转义及固定状态日志工具，不依赖父目录。 |

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、确认、输出与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

环境变量 `JOBS_FILE_VIEWER_MAX_BYTES` 未设置时为 `1048576` 字节。严格超过阈值才在读取前询问，只有精确 `YES` 执行；回车、其它输入和 EOF 取消。8 KiB 采样疑似二进制或编码无效时单独询问，后续 4096 字符块流式输出，窗口保留结果。正文不进入日志，文件不被修改，`Ctrl+C` 可终止。

安装管理需要系统 Windows PowerShell 5.1 Desktop / STA 和图形桌面；构建需要对应架构的 C++ 工具和 Windows SDK。部署、日志与快照只归本包当前用户目录。目录可完整单独复制，所有运行依赖均在包内；专项 `PackageInstaller.psm1` 明确覆盖模板，其余基础设施副本保持字节一致。

隔离回归入口位于上级仓库 `Tests/FileContentViewer.Tests.ps1` 与 `Tests/FileViewerMenuProbe.cpp`；这些验证只使用临时文件。真实 Windows Explorer 菜单 / 新窗口交互、MSVC 与不同架构兼容性需在目标机单独验收。

本目录的 `Manage.ps1`、`SelectionPanel.psm1` 和 `ManagementWorker.ps1` 构成本包自包含管理面板；由上级 `Manage.vbs` 无控制台启动。安装 / 卸载在隐藏后台执行，逐项状态与可复制实时日志留在面板中。日志区上沿的分隔条可上下拖动，调节结果在当前窗口保留；上下限为功能行、操作按钮和日志工具栏留出空间。日志正文右键可“复制”或“全选”，也支持 Ctrl+A / Ctrl+C；全选仅针对当前可见缓冲区，完整输出使用“复制全部日志”。总进度按已处理项 / 本次所选项显示计数和百分比；成功与失败计入已处理，等待中、执行中和未执行项不计入，100% 表示全部处理完毕，结果以成功 / 失败汇总为准。安装 / 更新和卸载分别计时；点击时只清零并启动当前操作计时，后台全部结束或启动失败时只冻结当前耗时。每秒刷新 `HH:mm:ss`（小时可超过 24），执行时显示“安装用时 / 卸载用时”，结束显示“安装总用时 / 卸载总用时”。两份耗时只在当前面板会话内独立保留。安装成功显示绿色“✅ 安装成功”。不改变右键业务工具自己的交互方式。失败状态可点击，在独立 PowerShell 中只读显示本次完整会话日志；包失败不阻止其它所选包，日志不可用时在面板提示。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

# `JobsFileVolumes / Scripts`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、模块与维护链路](#modules)
- [二、开发验证](#validation)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录自包含文件分卷右键菜单的选择校验、精确传输、流式读写与用户级安装事务，不依赖父仓或 `WindowsOS_11` 路径。用户使用方式见[功能说明](../README.md)。

## 一、<span id="modules">模块与维护链路</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文件 | 作用 |
| --- | --- |
| `VolumeSelection.h` | 单普通文件 / 完整同组多选资格；拒绝链接、设备名、非法编号、缺卷、重复和空卷。 |
| `ContextMenu.cpp`、`ContextMenu.def` | 原生 `IShellExtInit` / `IContextMenu`，菜单及点击复核；一次性 JSON 清单交给单个控制台。 |
| `SelectionRequest.ps1` | 只解析本包临时目录的JSON路径数组；成功读取后删除本次清单，拒绝非数组、空值、过大或链接请求。 |
| `Invoke.ps1` | 验证当前启用状态及清单目录 / 文件类型 / 大小，读取精确路径数组，显示自述并回车继续，失败保留窗口。 |
| `Action.psm1` | 合并 / 拆分动作入口；拆分调用原生上限选择窗口。 |
| `FileVolumes.ps1` | 固定 1 MiB 缓冲区、只读输入锁、分卷与重组 SHA-256、无覆盖发布和失败候选保留；始终保留原件。 |
| `Build.ps1` | 仅用已有 MSVC / Windows SDK 编译本包 DLL，不注册菜单。 |
| `PackageInstaller.psm1` | 本包动态 handler、CLSID、先构建再注册的备份 / 回滚事务。 |
| `Manage.ps1`、`Common.psm1` | 与仓库基础设施模板一致的管理面板、路径与日志工具。 |

总面板 `file-volumes` → 本包 `Extension.json` → `PackageInstaller.psm1` 的独立 release / DLL → `VolumeSelection.h` 的显隐 → `Invoke.ps1` 的精确选择 → `FileVolumes.ps1`。不应将精确选择退回单个 `%1` 参数或扫描目录补齐，否则多个进程和漏选校验会失效。

## 二、<span id="validation">开发验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

业务内核可在测试中直接载入 `FileVolumes.ps1`，用临时文件调用 `Invoke-JobsFileSplit -Path ... -LimitBytes ...`、`Invoke-JobsFileMerge -Paths ...`。输出目录为完整源文件名追加 `.chunks`，合并结果在分卷同目录。内核验证不显示 GUI，不执行安装。完整回归路径及目标机限制见[验证说明](../README.md#transport)。

原生菜单依据 [**Microsoft 的 IContextMenu 说明**](https://learn.microsoft.com/en-us/windows/win32/shell/how-to-implement-the-icontextmenu-interface)实现，选择清单避开 [**CreateProcessW 命令行长度上限**](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw)。本机 portable probe 验证门禁逻辑；真实 DLL 必须在匹配 Explorer 架构的 Windows 机器构建及验收。

本目录的 `Manage.ps1`、`SelectionPanel.psm1` 和 `ManagementWorker.ps1` 构成本包自包含管理面板；由上级 `Manage.vbs` 无控制台启动。安装 / 卸载在隐藏后台执行，逐项状态与可复制实时日志留在面板中。日志区上沿的分隔条可上下拖动，调节结果在当前窗口保留；上下限为功能行、操作按钮和日志工具栏留出空间。日志正文右键可“复制”或“全选”，也支持 Ctrl+A / Ctrl+C；全选仅针对当前可见缓冲区，完整输出使用“复制全部日志”。总进度按已处理项 / 本次所选项显示计数和百分比；成功与失败计入已处理，等待中、执行中和未执行项不计入，100% 表示全部处理完毕，结果以成功 / 失败汇总为准。安装 / 更新和卸载分别计时；点击时只清零并启动当前操作计时，后台全部结束或启动失败时只冻结当前耗时。每秒刷新 `HH:mm:ss`（小时可超过 24），执行时显示“安装用时 / 卸载用时”，结束显示“安装总用时 / 卸载总用时”。两份耗时只在当前面板会话内独立保留。安装成功显示绿色“✅ 安装成功”。不改变右键业务工具自己的交互方式。失败状态可点击，在独立 PowerShell 中只读显示本次完整会话日志；包失败不阻止其它所选包，日志不可用时在面板提示。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

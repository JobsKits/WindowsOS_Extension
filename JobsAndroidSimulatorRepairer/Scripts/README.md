# Android 模拟器检测与修复脚本

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、文件职责](#files)
- [二、只读检查与验证](#check)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

> 本目录为独立 [**Windows**](https://www.microsoft.com/windows) 桌面扩展的自包含业务及安装实现。用途、运行实例、依赖、完整 AVD 备份和恢复边界见[功能 README](../README.md)。

## 一、<span id="files">文件职责</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文件 | 职责 |
| --- | --- |
| `RepairAndroidSimulator.ps1` | 独立运行及 `-Check`，支持设备、包名、阈值和目标容量参数。 |
| `Action.psm1` | 模拟器身份、安装位置、空间、精确卸载、编译状态、完整备份与冷启动复测。 |
| `ContextMenu.cpp` / `DesktopScope.h` / `.def` | 独立 COM handler，仅系统桌面空白显示。 |
| `OpenCmd.ps1` / `Invoke.ps1` | 安全打开可见终端并检查本包安装状态和目标。 |
| `Build.ps1` | 使用已有 MSVC / Windows SDK 构建本包 DLL，缺失时停止注册。 |
| `Manage.ps1` / `PackageInstaller.psm1` | 当前用户精确菜单注册 / 卸载事务，不执行设备修复。 |
| `Common.psm1` | 本包路径、进程参数、超时和阶段日志基础设施。 |

## 二、<span id="check">只读检查与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录使用系统 [**PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) 5.1：

```powershell
powershell.exe `
  -NoLogo `
  -NoProfile `
  -ExecutionPolicy Bypass `
  -File ./RepairAndroidSimulator.ps1 `
  -Check
```

普通运行先展示内置自述，回车后执行默认轻量修复；缓存重置、单包卸载与容量调整另需精确 `YES`。`-Check` 不写日志、不设备写入、不改配置。所有 SDK 工具只发现不安装。扩容前备份整个 AVD 并校验，保留 userdata，不清空数据；实际分区与可用空间复测通过才报告成功。

日志为当前用户本地应用数据目录中本包 `logs/` 下的日期 `.log`；容量备份位于原 AVD 目录旁的 `.jobs-repair-backup-*`，终端输出精确路径。安装状态、`releases/` 与注册表 `backups/` 另由本包安装器维护，卸载保留这些产物。

隔离回归见 [`AndroidSimulatorRepairer.Tests.ps1`](../../Tests/AndroidSimulatorRepairer.Tests.ps1)。macOS 夹具及 Parser 不替代 Windows 5.1 / Explorer / 真实 Emulator 实机验收。

本目录的 `Manage.ps1`、`SelectionPanel.psm1` 和 `ManagementWorker.ps1` 构成本包自包含管理面板；由上级 `Manage.vbs` 无控制台启动。安装 / 卸载在隐藏后台执行，逐项状态与可复制实时日志留在面板中。日志区上沿的分隔条可上下拖动，调节结果在当前窗口保留；上下限为功能行、操作按钮和日志工具栏留出空间。日志正文右键可“复制”或“全选”，也支持 Ctrl+A / Ctrl+C；全选仅针对当前可见缓冲区，完整输出使用“复制全部日志”。总进度按已处理项 / 本次所选项显示计数和百分比；成功与失败计入已处理，等待中、执行中和未执行项不计入，100% 表示全部处理完毕，结果以成功 / 失败汇总为准。安装 / 更新和卸载分别计时；点击时只清零并启动当前操作计时，后台全部结束或启动失败时只冻结当前耗时。每秒刷新 `HH:mm:ss`（小时可超过 24），执行时显示“安装用时 / 卸载用时”，结束显示“安装总用时 / 卸载总用时”。两份耗时只在当前面板会话内独立保留。安装成功显示绿色“✅ 安装成功”。不改变右键业务工具自己的交互方式。失败状态可点击，在独立 PowerShell 中只读显示本次完整会话日志；包失败不阻止其它所选包，日志不可用时在面板提示。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

# 桌面右键：Android 模拟器检测与修复

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、安装与使用](#quick-start)
- [二、依赖与设备边界](#dependencies)
- [三、容量调整、备份与恢复](#capacity-and-backup)
- [四、卸载、日志与文件](#uninstall-and-logs)
- [五、验证与实机边界](#verification)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

> 独立 [**Windows**](https://www.microsoft.com/windows) 扩展。系统桌面空白右键 → `Android 模拟器检测与修复` → 可见终端，处理 [**Android Emulator**](https://developer.android.com/studio/run/emulator) 的 `INSTALL_FAILED_INSUFFICIENT_STORAGE`。安装菜单不修复设备；点击后先展示用途与影响，回车才开始。双击 `Run.cmd` 使用相同内置核心，无须父工程、兄弟包或 JobsCommand。

| 场景 | 操作及结果 |
| --- | --- |
| 安装位置被固定为外部存储 | 默认恢复 `pm set-install-location 0`，回读确认为自动。 |
| `/data` 可用空间不足 | 精确 `YES` 后可重置编译状态，或卸载本人输入的单一精确包名，再复测空间。 |
| 仍然不足且需要调容量 | 完整备份 AVD 后改容量，冷启动后复核实际 `/data`；写配置不等于已经扩容。 |
| 只想检查 | `-Check` 只查询，不创建日志、改设备、备份、改配置或启动模拟器。异常非零退出。 |

## 一、<span id="quick-start">安装与使用</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

1、双击 [`Install.cmd`](./Install.cmd)，确认本功能的当前用户菜单安装；也可以在仓库总面板只勾选本功能。只编译和登记本包，不操作 Android 设备。

2、正常启动已有 AVD，在系统桌面空白处右键选择本菜单。Windows 11 传统 COM 菜单位于“显示更多选项”。普通目录背景、文件夹及选中项均不显示。程序不会注册所有目录背景。

3、阅读终端内自述，直接回车授权默认恢复安装位置及空间检测；任意非空输入、EOF 或 Ctrl+C 停止。有多台模拟器时必须选择有效编号。

4、可选缓存重置、应用卸载及 AVD 容量调整分别需要输入精确大写 `YES`。退出时如果问题仍存在，明确失败并返回非零；不会把“已尝试”报成修复成功。

在本功能目录通过系统 [**PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) 5.1 运行只读检查：

```powershell
powershell.exe `
  -NoLogo `
  -NoProfile `
  -ExecutionPolicy Bypass `
  -File ./Scripts/RepairAndroidSimulator.ps1 `
  -Check
```

指定设备、待卸载包名及更大的容量：

```powershell
powershell.exe `
  -NoLogo `
  -NoProfile `
  -ExecutionPolicy Bypass `
  -File ./Scripts/RepairAndroidSimulator.ps1 `
  -Serial emulator-5554 `
  -AppId com.example.app `
  -ThresholdMB 1200 `
  -TargetDataSize 16G
```

`-AppId` 只选择包名，执行卸载仍需 `YES`。默认阈值 `800 MB`、容量 `8G`；已有配置或实际分区达到 / 超过目标时会停止，使用上述参数指定更大值。容量格式为正整数字节或大写 `K/M/G/T`。

## 二、<span id="dependencies">依赖与设备边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 运行依赖已有 Android SDK 的 [**ADB**](https://developer.android.com/tools/adb)；容量调整另需 `emulator.exe`。显式 `ANDROID_HOME` 优先，其次 `ANDROID_SDK_ROOT`；显式路径缺失或损坏立即停止。没有显式 SDK 时依次发现当前 PATH 与 `%LOCALAPPDATA%\Android\Sdk`，不下载工具、不修改 PATH、代理或系统设置。
- 安装依赖已有 [**MSVC / Windows SDK**](https://visualstudio.microsoft.com/visual-cpp-build-tools/) 的 C++ 桌面开发工具。缺失时在注册表修改前停止，不自动安装编译器。
- 只选择在线 `emulator-数字`，并检查 `ro.kernel.qemu=1` 与 `adb emu avd name` 唯一名称；每次设备写入前复检。真机、离线、未授权和身份不明确的目标均拒绝。
- 不自动卸载内置应用、不执行 `wipe-data`、不删除 userdata / qcow2 / 锁。精确包名卸载会删除所选应用的数据；编译状态重置可能令应用下一次启动变慢。

## 三、<span id="capacity-and-backup">容量调整、备份与恢复</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- AVD 根路径依次为 `ANDROID_AVD_HOME`、`ANDROID_USER_HOME/avd`、当前用户 `.android/avd`，从 `<name>.ini` 的 `path` / `path.rel` 定位真实目录。拒绝越界相对路径、重复定位项、链接和重解析点，并回读唯一 `AvdId` 与目标一致；确认 / 停机期间路径或配置变化即停止。
- 调整前核对默认数据目录与启动参数；显式 `disk.dataPartition.path` / `initPath`、`-data` / `-datadir`、无法读取进程参数或无法关联目标时拒绝自动扩容，保留只读和轻量修复能力。
- 目标容量必须严格大于现有配置和实际 `/data` 总量，并不得小于已有 userdata 镜像逻辑长度。原容量缺失、重复或无法解析时停止，绝不猜测后缩容。
- 确认后先正常关闭目标，等待 ADB 消失、所有本机 Emulator / QEMU 进程退出且 AVD 锁释放；不杀其它 AVD，也不删除锁。超时保持配置原样。其它模拟器仍开着时须先正常关闭后重试。
- 在 AVD 同级创建 `.jobs-repair-backup-时间-唯一值/`，完整复制 AVD 与定位文件，逐文件 SHA-256 对账。磁盘须容纳完整备份、目标容量增长及 `1 GB` 余量；不足或备份失败停止，保留现场。
- 仅替换 `disk.dataPartition.size`，保留其它配置，使用 `-no-snapshot-load -no-snapshot-save` 冷启动。已有 userdata 是否自动扩容取决于 Emulator / 镜像版本，Emulator 可能迁移 userdata 或重建 qcow2 overlay，因此完整备份必须保留。没有实际分区增量或空间仍低于阈值均返回失败，不自动清空数据。
- 手工恢复时先退出所有模拟器并确认锁释放，从终端显示的备份中恢复 `avd/` 原目录内容及对应 `locator.ini`。保留现态另一份备份后再覆盖；不要在运行中恢复。卸载菜单不会撤回已单独确认的设备操作或删除这些备份。

官方依据：[Emulator 启动、数据路径与快照参数](https://developer.android.com/studio/run/emulator-commandline)、[AVD 环境变量](https://developer.android.com/tools/variables)、[Emulator 既有 userdata 扩容实现](https://android.googlesource.com/platform/external/qemu/+/refs/heads/emu-32-release/android-qemu2-glue/main.cpp#1904)。源码参考不代表所有 Emulator 版本都能无损扩容，最终以本机复测与备份为准。

## 四、<span id="uninstall-and-logs">卸载、日志与文件</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

双击 [`Uninstall.cmd`](./Uninstall.cmd) 仅卸载本包菜单与本包 CLSID，保留当前用户独立发布文件、禁用状态、工具、日志和 AVD 备份；不会停用其它扩展。

| 文件 / 路径 | 职责 |
| --- | --- |
| `Install.cmd` / `Uninstall.cmd` | 本包独立安装 / 卸载。 |
| `Run.cmd` | 无须安装菜单的独立运行，参数传给相同核心。 |
| `Scripts/RepairAndroidSimulator.ps1` / `Action.psm1` | 内置自述、只读、身份检查与修复流程。 |
| `Scripts/ContextMenu.cpp` / `DesktopScope.h` | 原生桌面空白门禁，不在 Explorer 内运行 SDK。 |
| `%LOCALAPPDATA%\Jobs\WindowsExtension\extensions\android-simulator-repair\logs` | 本功能状态日志；只读检查不创建。 |
| 同级 `backups` / `releases` | 当前用户菜单注册状态备份与版本化发布文件。 |
| AVD 同级 `.jobs-repair-backup-*` | 容量调整前完整设备备份，终端显示精确位置。 |

日志记录固定阶段与结果，详细错误在可见终端显示；失败的部分备份保留供核查，不自动当作可恢复成功备份。

## 五、<span id="verification">验证与实机边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

[`AndroidSimulatorRepairer.Tests.ps1`](../Tests/AndroidSimulatorRepairer.Tests.ps1) 使用假 ADB / CIM 和隔离 AVD 文件验证设备过滤、身份伪装、只读无写入、精确卸载、失败传播、路径与容量保护、停机先于修改、完整备份和配置保留。架构 / Catalog 检查独立复制交付与只注册桌面 handler；所有 PowerShell 源码使用 UTF-8 BOM 并通过 Parser。

2026-10-23 本地验证：新业务 96、Architecture 499、Catalog 47、ActionModules 120、C++ 桌面门禁 9 断言通过；16 个现行包基础设施一致。Windows CI 已接入本业务回归和本包 MSVC 构建检查，但未推送触发。

macOS 的 PowerShell 7 夹具与纯 C++ 门禁验证不能替代 Windows PowerShell 5.1、MSVC 编译、Explorer 桌面菜单及真实 Emulator 扩容。没有在本机安装 / 注册本功能，也没有操作真实 Android 设备；Windows 实机与实际 userdata 迁移仍待目标电脑验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

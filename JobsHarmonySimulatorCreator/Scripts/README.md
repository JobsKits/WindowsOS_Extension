# `Scripts`：新建鸿蒙模拟器

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、文件职责](#files)
- [二、运行与维护边界](#boundaries)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录是独立 [JobsHarmonySimulatorCreator](../README.md) 的完整运行代码，不引用其它功能包或 SourceTree 脚本。

## 一、<span id="files">文件职责</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文件 | 职责 |
| --- | --- |
| `Action.psm1` | 桌面 / x64 门禁、工具发现、只读能力与镜像查询、选择、唯一命名、创建回读及可选启动。 |
| `CreateHarmonySimulator.ps1` | 独立业务入口；`-Check` 不创建、下载、启动或安装，参数见[功能说明](../README.md#run)。 |
| `ContextMenu.cpp` / `DesktopScope.h` / `ContextMenu.def` | 原生 `DesktopBackground` handler，只对无选中项的真实系统桌面插入一项，并拒绝 ARM 宿主。 |
| `Build.ps1` | 只用已有 MSVC / Windows SDK 编译 x64 DLL；不注册、不安装编译器。 |
| `OpenCmd.ps1` | 通过进程环境传递目标，打开 CMD 并启动固定 PowerShell 引导。 |
| `Invoke.ps1` / `Common.psm1` | 安装状态门禁、路径 / 参数工具和进程超时清理；每包内嵌。 |
| `Manage.ps1` / `PackageInstaller.psm1` | 独立安装、备份、注册表事务与卸载；原生安装模块为模板明确覆盖项。 |

## 二、<span id="boundaries">运行与维护边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

安装 / 卸载从上一层 `.cmd` 进行，业务可通过 `Run.cmd` 独立运行。只选已下载镜像，缺工具 / 镜像提示官方准备后停止；不会自动下载、安装、接受许可、覆盖实例或修改全局配置。创建命令不含 `-force`；成功后通过详情回读验证唯一名称、产品类型和系统版本，不能解析或不匹配就保留现场并停止。启动由本人选择，官方许可交互保留在终端内。

确认创建后才写本包日志；只读 Check 不写状态或业务日志。原生工具输出留在控制台，工具自身日志沿用 DevEco 配置。业务回归入口为 [HarmonySimulatorCreator.Tests.ps1](../../Tests/HarmonySimulatorCreator.Tests.ps1)，纯路径门禁探针为 [HarmonyDesktopProbe.cpp](../../Tests/HarmonyDesktopProbe.cpp)。不将 macOS 假工具回归当成 Windows 真机或 Explorer 验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

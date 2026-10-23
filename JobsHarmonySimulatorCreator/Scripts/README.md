# `Scripts`：新建 Harmony 模拟器

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
| `Action.psm1` | 桌面 / x64 门禁、工具发现与依赖补齐、只读能力与镜像查询、选择、唯一命名、创建回读及可选启动。 |
| `HarmonyTools.ps1` | SDL Windows x64 CLT 下载、本地 ZIP 复用、大小 / SHA-256 / 解压路径校验、独立目录发布与失败清理。 |
| `CreateHarmonySimulator.ps1` | 独立业务入口；`-Check` 不创建、下载、启动或安装，参数见[功能说明](../README.md#run)。 |
| `ContextMenu.cpp` / `DesktopScope.h` / `ContextMenu.def` | 原生 `DesktopBackground` handler，只对无选中项的真实系统桌面插入一项，并拒绝 ARM 宿主。 |
| `Build.ps1` | 只用已有 MSVC / Windows SDK 编译 x64 DLL；不注册、不安装编译器。 |
| `OpenCmd.ps1` | 通过进程环境传递目标，打开 CMD 并启动固定 PowerShell 引导。 |
| `Invoke.ps1` / `Common.psm1` | 安装状态门禁、路径 / 参数工具和进程超时清理；每包内嵌。 |
| `Manage.ps1` / `PackageInstaller.psm1` | 独立安装、备份、注册表事务与卸载；原生安装模块为模板明确覆盖项。 |

## 二、<span id="boundaries">运行与维护边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

安装 / 卸载从上一层 `.cmd` 进行，业务可通过 `Run.cmd` 独立运行。华为官方下载中心获取模拟器配套工具需要登录；正常桌面入口回车授权后，缺工具时使用 [SDL 免登录替代源](https://libsdl.org/harmonyos-devtools/) 安装 Windows x64 CLT 6.1.1.280。校验固定大小、SHA-256 与归档路径后解压，能力检查通过才发布独立目录；健康工具不升级。`HARMONY_CLT_ARCHIVE` 可复用同版本本地 ZIP。缺系统镜像时读取官方清单，回车选最新稳定版手机镜像；展示随工具的两份协议原文，用户回车明确同意后才执行 `-license accept`，再用 `-install ... -force` 下载所选项。镜像复检失败就停止，不循环等待外部准备；不覆盖实例、不修改全局配置。创建和启动命令不含 `-force`；成功后通过详情回读验证唯一名称、产品类型和系统版本，不能解析或不匹配就保留现场并停止。启动由本人选择，未确认许可时先展示原文并等待本人同意；官方额外交互保留在终端内。

首屏确认后、依赖安装前开始写本包日志；只读 Check 不写状态或业务日志。原生工具输出留在控制台，工具自身日志沿用 DevEco 配置。依赖回归入口为 [HarmonySimulatorBootstrap.Tests.ps1](../../Tests/HarmonySimulatorBootstrap.Tests.ps1)，使用临时小 ZIP 与下载替身；业务回归入口为 [HarmonySimulatorCreator.Tests.ps1](../../Tests/HarmonySimulatorCreator.Tests.ps1)，纯路径门禁探针为 [HarmonyDesktopProbe.cpp](../../Tests/HarmonyDesktopProbe.cpp)。不将 macOS 假工具回归当成 Windows 真机或 Explorer 验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

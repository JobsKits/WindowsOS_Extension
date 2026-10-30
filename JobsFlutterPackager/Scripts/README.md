# `Scripts`：Flutter打包实现

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、文件职责](#jobs-toc-heading-2)
- [二、边界与维护](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录独立实现 **Flutter打包**，运行前先看[功能说明](../README.md)。安装和卸载从上一层 `.cmd` 入口进行。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、文件职责 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 职责 |
| --- | --- |
| `ContextMenu.cpp` / `FlutterProject.h` / `ContextMenu.def` | 原生动态菜单与精确 Flutter pubspec 识别，非项目目录不插入菜单。 |
| `Build.ps1` | 使用已安装 MSVC / Windows SDK 编译本包 DLL，不联网或注册。 |
| `OpenCmd.ps1` | 通过进程环境安全传入目标，打开 CMD，再启动固定 PowerShell 引导命令。 |
| `Invoke.ps1` / `Common.psm1` | 校验本包安装状态、解析目标、统一错误和终端生命周期。 |
| `Action.psm1` | 内置自述、fzf 选择、项目与 SDK / Java 检查、Android 及 HarmonyOS 构建和产物验证；OpenHarmony 自包含检查 DevEco 工具链。 |
| `Manage.ps1` / `PackageInstaller.psm1` | 本包独立安装、原生 DLL 构建、当前用户注册表事务、备份和卸载。 |

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、边界与维护 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

本包没有跨功能或 SourceTree 运行依赖。`PackageInstaller.psm1` 声明为独立覆盖模板；其它通用副本沿用仓库模板。构建先完成 DLL 再修改菜单和状态；卸载只删除本包处理器与 CLSID，保留日志及备份。右键运行会写入所选 Flutter 工程的依赖 / 构建目录，iOS 选择在任何 Flutter 命令前停止。OpenHarmony 通过同一平台选择器进入，要求已有 ohos 平台；支持 HAP / APP / 两者与 release / debug / profile，显式适配 SDK 优先，否则复用项目 FVM；SDK 缺失不会自动安装。Node、npm、ohpm、hvigorw、Java 及 SDK 包型能力全部通过后才获取依赖。

OpenHarmony 使用 `FLUTTER_OHOS_SDK / OHOS_BUILD_TARGET / BUILD_MODE`，不接受 flavor。DevEco 工具 PATH、Java、SDK 及去色设置限于本次进程，异常后同样恢复。`.bat / .cmd` 检查通过 PowerShell 原生命令调用，不依赖其它功能包或 Mac 脚本；HAP / APP 校验非空输出、保留合法缓存并提示未签名文件。

`Invoke-JobsFlutterHarmonyAction` 与聚合副本共用双产物快捷逻辑：再次检查鸿蒙工程及项目 FVM，回车确认后固定 `all / release` 与空 flavor，无临时 SDK 覆盖，按 HAP → APP 顺序验证两种非空产物后才报告完成；它不改变通用平台选择的参数能力。快捷边界见[FlutterHarmonyPackage.Tests.ps1](../../Tests/FlutterHarmonyPackage.Tests.ps1)。

回归入口为 [FlutterPackager.Tests.ps1](../../Tests/FlutterPackager.Tests.ps1)。真实 Windows DLL、菜单、CMD 和 fzf 验收与跨平台脚本检查分开记录。

本目录的 `Manage.ps1`、`SelectionPanel.psm1` 和 `ManagementWorker.ps1` 构成本包自包含管理面板；由上级 `Manage.vbs` 无控制台启动。安装 / 卸载在隐藏后台执行，逐项状态与可复制实时日志留在面板中。日志区上沿的分隔条可上下拖动，调节结果在当前窗口保留；上下限为功能行、操作按钮和日志工具栏留出空间。日志正文右键可“复制”或“全选”，也支持 Ctrl+A / Ctrl+C；全选仅针对当前可见缓冲区，完整输出使用“复制全部日志”。总进度按已处理项 / 本次所选项显示计数和百分比；成功与失败计入已处理，等待中、执行中和未执行项不计入，100% 表示全部处理完毕，结果以成功 / 失败汇总为准。安装 / 更新和卸载分别计时；点击时只清零并启动当前操作计时，后台全部结束或启动失败时只冻结当前耗时。每秒刷新 `HH:mm:ss`（小时可超过 24），执行时显示“安装用时 / 卸载用时”，结束显示“安装总用时 / 卸载总用时”。两份耗时只在当前面板会话内独立保留。安装成功显示绿色“✅ 安装成功”。不改变右键业务工具自己的交互方式。失败状态可点击，在独立 PowerShell 中只读显示本次完整会话日志；包失败不阻止其它所选包，日志不可用时在面板提示。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

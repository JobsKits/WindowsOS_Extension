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

回归入口为 [FlutterPackager.Tests.ps1](../../Tests/FlutterPackager.Tests.ps1)。真实 Windows DLL、菜单、CMD 和 fzf 验收与跨平台脚本检查分开记录。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

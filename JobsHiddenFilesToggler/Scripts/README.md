# `JobsHiddenFilesToggler` · Scripts

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、文件职责](#files)
- [二、入口与运行边界](#boundaries)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录完整随 [JobsHiddenFilesToggler](../README.md) 独立交付，不引用其他功能包或总目录的运行代码。系统桌面空白菜单按当前状态显示“👁️ 显示文件”或“🙈 隐藏文件”，点击直接切换当前用户隐藏文件偏好。

## 一、<span id="files">文件职责</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文件 | 职责 |
| --- | --- |
| `ContextMenu.cpp` / `ContextMenu.def` | 原生 COM 菜单与导出；查询时只读状态，点击才启动本包后台业务。 |
| `DesktopScope.h` | 真实系统桌面、空白处、无选中项门禁。 |
| `HiddenFilesMenu.h` | 读取当前用户 `Hidden` 设置，生成下一动作标题和 emoji；异常状态置灰。 |
| `Build.ps1` | 使用已有 MSVC / Windows SDK 编译本包 DLL；不注册、不联网。 |
| `Action.psm1` | 重新读取当前用户 `Hidden` DWORD，按菜单固定的 Show / Hide 目标幂等写入；独立入口使用 Toggle，串行锁保护与写入复核。 |
| `ExplorerRefresher.cs` | 通过 `WM_SETTINGCHANGE` 与 `SHChangeNotify` 请求刷新资源管理器。 |
| `ToggleHiddenFiles.ps1` | 上层 `Run.cmd` 的独立切换入口，无需先安装菜单。 |
| `Invoke.ps1` / `Common.psm1` | 安装状态校验、本包运行入口、日志与通用路径工具。 |
| `Manage.ps1` / `PackageInstaller.psm1` | 独立安装、菜单注册、精确备份与事务回滚。 |

## 二、<span id="boundaries">入口与运行边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

从上级目录使用 `Install.cmd` / `Uninstall.cmd` 管理菜单，`Run.cmd` 独立切换偏好。安装依赖系统 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) `5.1 Desktop`、STA、现有 MSVC 与 Windows SDK；业务无需联网或管理员权限。安装 / 卸载不改变隐藏文件状态。

注册范围仅当前用户 `DesktopBackground` 原生 handler 和本包 CLSID。业务只读写当前用户资源管理器 `Advanced\Hidden`，不修改 `ShowSuperHidden`、系统级策略、文件隐藏属性或其他账户。菜单读取失败时置灰，点击后的失败保持明确报错，不强制重启资源管理器。

回归入口：[隐藏文件状态与包隔离](../../Tests/HiddenFiles.Tests.ps1)、[动态标题与桌面门禁](../../Tests/HiddenFilesMenuProbe.cpp)。验证使用替身或临时注册表位置，不调用本机真实切换入口。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

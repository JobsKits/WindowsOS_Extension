# JobsRunAuthorizationRevoker · Scripts

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、文件职责](#jobs-toc-heading-2)
- [二、入口、依赖与产物](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录随独立包完整交付，不读取总目录或相邻功能的业务代码。完整范围、风险和运行例子见[功能说明](../README.md)。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、文件职责 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 职责 |
| --- | --- |
| `Action.psm1` | 本包菜单业务入口。 |
| `Common.psm1` | 本包内嵌通用路径、日志与进程工具。 |
| `Invoke.ps1` | 验证已安装状态后转交本包业务。 |
| `Manage.ps1 / PackageInstaller.psm1` | 本包独立安装、卸载、精确备份与事务回滚。 |
| `ContextMenu.cpp / ContextMenu.def / Build.ps1` | 原生 COM 过滤、导出和 MSVC 构建；构建不注册。 |
| `OpenCmd.ps1` / `TerminalLauncher.ps1` | 以文件父目录为工作目录，在独立终端安全转交单文件路径，CMD 不插入用户路径文本。 |
| `RunPermissionFile.cs` | 锁定真实单文件并精确读写 DACL，核验有效 ExecuteFile。 |
| `RunPermissions.ps1` | 确认、快照、冲突保护及失败回滚。 |
| `ChangeRunPermission.ps1` | 独立单文件入口。 |

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、入口、依赖与产物 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

从上级目录运行 `Install.cmd` / `Uninstall.cmd` 管理菜单；`Run.cmd` 运行独立业务，`Run.cmd -Target "C:\目录\file.exe"` 选择一个文件。业务先显示用途并确认，安装不执行检测、重启或权限修改。依赖 Windows PowerShell 5.1，原生构建需要现有 MSVC 和 Windows SDK；权限业务仅本机 NTFS，并要求当前用户已有文件读取和 DACL 修改权限。

菜单状态、安装备份、release、日志按 `Extension.json` 的独立 Id 位于当前用户 `LOCALAPPDATA/Jobs/WindowsExtension/extensions/`；文件权限精确记录由两包共用 `LOCALAPPDATA/Jobs/WindowsExtension/run-permissions`，卸载不恢复目标权限或删除记录。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

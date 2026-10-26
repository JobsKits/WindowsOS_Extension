# JobsRunAuthorizationRevoker · 解除运行授权

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、成对行为与边界](#jobs-toc-heading-2)
- [二、安装与独立运行](#jobs-toc-heading-3)
- [三、精确快照、冲突与目录](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

> **最低支持系统：Windows 10 x64。** Windows 5.1 / MSVC / Explorer 与实际 NTFS ACL 行为仍须目标机验收；不声明已验证最低 build。

对一个可执行文件或脚本显示“**🔒 解除运行授权**”，在独立终端核对路径并输入精确 `YES` 才修改。通过 [**Windows 文件 ACL**](https://learn.microsoft.com/en-us/dotnet/api/system.security.accesscontrol.filesystemrights) 管理当前用户 `ExecuteFile`（执行文件）权限；不执行所选文件。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、成对行为与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 动作 | 精确行为 |
| --- | --- |
| 运行授权 | 从本功能保存的原始 DACL 重新构造，只撤回本工具造成的拒绝 / 允许项，再增加当前用户 `ExecuteFile` 允许 ACE；已有组或其它拒绝导致有效授权失败时回滚。 |
| 解除运行授权 | 保留原 DACL，增加当前用户 `ExecuteFile` 显式拒绝 ACE，使继承来的允许不能抵消本次撤权。 |
| 重复同向操作 | 核对记录、身份与有效权限，匹配时不重复写入。 |
| 外部 DACL 或文件身份变化 | 停止并保留现场，不用旧快照覆盖新规则。 |

只支持本机 NTFS 的可执行或脚本格式普通单文件；目录、多选、背景、符号链接、联接、硬链接、UNC、设备路径及备用数据流均排除。原生菜单先按可执行或脚本扩展名过滤，README.md、txt、图片、压缩包等普通数据文件不显示两项权限菜单；业务再次核验格式、卷、父路径和硬链接数。其它用户、其它权限、继承设置、所有者、来源标记、PowerShell 执行策略和全局安全设置不变。保留读取权限的解释器仍可读取脚本并执行内容；`ExecuteFile` 撤权不是全面防执行隔离。文件扩展名和系统关联也不会因授权改变。

支持的格式为 `exe / com / scr / cpl / bat / cmd / ps1 / vbs / vbe / js / jse / wsf / wsh / hta / py / pyw / pl / rb / sh / bash / zsh / fish / ksh / csh / tcsh / php / lua / command`，扩展名不区分大小写；系统是否已安装对应解释器需另行满足。两个包均安装后，适用文件始终显示“🔓 运行授权”和“🔒 解除运行授权”：已有当前用户有效 ExecuteFile 时前者置灰、后者可点；没有时相反；权限无法可靠读取时两项都置灰。打开菜单和点击时重新检查状态，已达目标状态不重复写入。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、安装与独立运行 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

双击 [Install.cmd](./Install.cmd) 安装，[Uninstall.cmd](./Uninstall.cmd) 卸载；在[总面板](../README.md)可分别勾选两个包。每个包可单独复制安装，不依赖另一个包的运行代码。安装用现有 MSVC / Windows SDK 编译单文件原生菜单并按当前用户注册。

独立入口传入一个文件，终端会显示范围、快照位置并要求 `YES`；取消或 EOF 不改权限。

```powershell
.\Run.cmd -Target "C:\研发目录\example.exe"
```

卸载只关闭菜单，保留已修改的文件权限和恢复记录；需要重新授权时先运行对应授权菜单，不能把卸载等同权限恢复。不提权、不能取得读 / 修改 DACL 权限时明确失败。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、精确快照、冲突与目录 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

两包使用当前用户 `LOCALAPPDATA/Jobs/WindowsExtension/run-permissions` 下同一份每文件记录，按卷号、文件 ID、当前 SID 标识，另存每次操作的内容摘要、原始 DACL、修改前 DACL 和预期 DACL。正常编辑同一文件内容后仍可往返切换，不用首次内容摘要锁死后续操作。持有禁止写入 / 删除共享的文件句柄完成身份、内容和 DACL 操作，拒绝硬链接与路径重解析；修改失败仅在当前 DACL 仍等于本次预期时回滚，出现并发变更则保留记录并报错。中断后的 Prepared 记录可对照修改前 / 预期状态恢复流程，不会无条件覆盖。

| 路径 | 职责 |
| --- | --- |
| [Scripts](./Scripts/README.md) | 原生菜单、权限核心、独立业务与安装事务。 |
| `Extension.json` | 包身份与控制台入口。 |
| `Install.cmd` / `Uninstall.cmd` / `Run.cmd` | 安装、卸载、独立执行。 |

测试见 [RunPermissions.Tests.ps1](../Tests/RunPermissions.Tests.ps1)：本机编译 / 隔离流程与 Windows 临时 NTFS 文件实际 ACL 往返分别记录；不修改用户真实文件。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

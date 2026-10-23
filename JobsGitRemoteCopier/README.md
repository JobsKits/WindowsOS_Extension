# `JobsGitRemoteCopier`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、适用范围与前提](#jobs-toc-heading-2)
- [二、安装与卸载](#jobs-toc-heading-3)
  - [Install.cmd](#jobs-toc-heading-4)
  - [Uninstall.cmd](#jobs-toc-heading-5)
- [三、功能行为与风险](#jobs-toc-heading-6)
- [四、目录与状态](#jobs-toc-heading-7)
- [五、排查与验证](#jobs-toc-heading-8)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

**右键功能：复制 Git 远程地址。** 找到所选文件或目录所属的 [**Git**](https://git-scm.com/) 工作树，把原始 remote 地址写入剪贴板。

这是可独立复制和使用的 [**Windows**](https://www.microsoft.com/windows) 功能包，自带安装、卸载和运行源码，不需要总目录或其他功能包。**只复制整个 `JobsGitRemoteCopier` 文件夹，双击 [`Install.cmd`](./Install.cmd) 即可安装本项；[`Uninstall.cmd`](./Uninstall.cmd) 只卸载本项。**

| 操作 | 结果 |
| --- | --- |
| 右键仓库目录 → 复制 Git 远程地址 | remote 是 `git@github.com:org/repo.git` 时，剪贴板保留同一原始地址。 |
| 单独运行包内 `Install.cmd` | 仅安装或更新 `copy-git-remote`。 |
| 单独运行包内 `Uninstall.cmd` | 仅移除本包菜单，保留其他包。 |

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、适用范围与前提 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 系统为 Windows 10 / 11，系统自带的 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) `5.1` Desktop、系统 .NET 与图形桌面可用。
- 单个文件、文件夹、磁盘根目录和文件夹空白处；文件按其父目录解析。
- 执行时需要健康的 Git 与图形桌面剪贴板；安装菜单本身不下载工具。
- 菜单按单选设计，多选批量操作不在支持范围内。**Windows 11 需要进入“显示更多选项”或使用 `Shift+F10` 打开经典菜单。**
- 安装作用于当前用户，不需要管理员权限；不修改系统菜单样式、默认关联或永久执行策略。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、安装与卸载 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

### <span id="jobs-toc-heading-4" data-jobs-toc="v2">[Install.cmd](./Install.cmd)</span><!-- jobs-toc:heading-end -->

> **目的：** 只安装或更新“复制 Git 远程地址”。

- 打印脚本来源、包身份、目标目录与注册表范围，确认后部署本包。
- 复制本包运行文件到独立版本目录，逐文件核对 SHA-256，备份本包菜单注册。
- 只写本包菜单和配置；遇到同名但无本工具归属标记的注册表键则停止。
- 本包提交失败时回滚本包菜单与配置；完成后重新右键查看，不强制重启资源管理器。

### <span id="jobs-toc-heading-5" data-jobs-toc="v2">[Uninstall.cmd](./Uninstall.cmd)</span><!-- jobs-toc:heading-end -->

> **目的：** 只移除“复制 Git 远程地址”，保留可追溯数据。

- 确认后备份本包注册，移除本包菜单和开始菜单卸载快捷方式。
- 保留 `settings.json` 并写入 `Enabled=false`，避免兼容配置重新启用本项。
- 保留本包运行版本、日志、备份和私有工具；不删除其他软件，也不停止其他会话。
- 需要彻底清理时，先等待本包会话退出，再手动清理本包部署目录。

入口从自身位置查找脚本，不依赖启动目录。`-ExecutionPolicy Bypass` 仅作用于本次进程。企业执行策略或应用控制仍可能限制未签名脚本，应遵循设备管理策略。

## <span id="jobs-toc-heading-6" data-jobs-toc="v2">三、功能行为与风险 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 通过 Git 自身解析普通仓库、子模块、`.git` 指针文件、linked worktree 和上级工作树。
- 优先当前分支关联 remote，其次 `origin`，最后只接受唯一 remote；缺少或有歧义时停止。
- 保留 SSH 协议、`.git` 后缀以及原始 remote 内容；不会转换成网页地址。原始地址可能带凭据，不应粘贴到公开位置，也不把它原样写入日志。

## <span id="jobs-toc-heading-7" data-jobs-toc="v2">四、目录与状态 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

```text
JobsGitRemoteCopier/
├── Extension.json              本包身份与菜单属性
├── Install.cmd                 本包安装 / 更新
├── Uninstall.cmd               本包卸载
├── README.md
└── Scripts/
    ├── Manage.ps1              本包管理入口
    ├── PackageInstaller.psm1   本包注册、备份、回滚与状态提交
    ├── Common.psm1             随包内嵌的通用基础实现
    ├── Invoke.ps1              本包菜单运行入口
    └── Action.psm1             本功能业务实现
```

全部运行文件均在包内。即使移走总目录及其他包，本包仍能独立安装、运行和卸载。

状态位于当前用户本地应用数据的 `Jobs\WindowsExtension\extensions\copy-git-remote` 中；`settings.json` 保存 `Version: 2`、`Enabled` 和 `ReleasePath`。`releases/`、`logs/`、`backups/` 和 `tools/` 分别保存本包运行版本、日志、菜单快照和私有依赖；实际日志及备份位置由运行入口打印。菜单直接运行本包业务，不使用总目录的集中请求队列。

注册表范围限于当前用户 `HKCU\Software\Classes` 下的 `shell\Jobs.WindowsExtension.copy-git-remote` 菜单键，不写 `HKLM`。适用对象由本包 `Extension.json` 的 `DirectoryOnly` 控制。

安装状态按功能独立读取：本包状态优先；缺少时才读取兼容总配置中的本项选择。安装或卸载只更新本项，其它功能、运行目录和备份保留。

## <span id="jobs-toc-heading-8" data-jobs-toc="v2">五、排查与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

不能复制时，先确认目标位于 Git 工作树且 remote 可唯一确定。此包复制远程地址；复制本地路径使用独立的 `JobsPathCopier` 包。

菜单未出现时，重新右键并检查 Windows 11 经典菜单入口，再查看本包安装日志。其他包的菜单状态与日志无需改动。

源码的语法、独立包结构和跨平台回归不能代替 Windows 真实桌面验收；应在 Windows 核对安装确认、菜单对象、中文特殊路径、依赖缺失分支以及只卸载本包后其他功能仍可用。普通验证不执行真实业务写操作。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

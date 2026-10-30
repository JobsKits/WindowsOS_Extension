# `JobsGitRemoteOpener`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、适用范围与前提](#jobs-toc-heading-2)
- [二、安装与卸载](#jobs-toc-heading-3)
  - [安装 / 更新： Manage.cmd](#jobs-toc-heading-4)
  - [卸载： Manage.cmd](#jobs-toc-heading-5)
- [三、功能行为与风险](#jobs-toc-heading-6)
- [四、目录与状态](#jobs-toc-heading-7)
- [五、排查与验证](#jobs-toc-heading-8)

</details>
<!-- jobs-toc:end -->

---

**管理操作：** 本目录以 `Manage.cmd` 为轻量启动入口，只唤起 GUI 后结束本次脚本；先在面板选择安装 / 更新或卸载。在面板确认安装 / 更新或卸载后立即执行，无二次终端确认。关闭或取消面板不执行；卸载保留日志、备份、运行文件和工具。

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

**最低支持系统：Windows 10 64 位（x64）。** 这是当前最低支持目标；具体最低 build 尚未锁定，完整实机兼容性仍待验证。最低基线不等于所有功能已经实测通过。

**右键功能：打开 Git 远程地址。** 找到所选文件或目录所属的 [**Git**](https://git-scm.com/) 工作树，通过系统默认浏览器打开对应远程仓库网页。

这是可独立复制和使用的 [**Windows**](https://www.microsoft.com/windows) 功能包，自带安装、卸载和运行源码，不需要总目录或其他功能包。**只复制整个 `JobsGitRemoteOpener` 文件夹，双击 [`Manage.cmd`](./Manage.cmd)，在面板选择“安装 / 更新”或“卸载”；只处理本项。**

| 操作 | 结果 |
| --- | --- |
| 右键仓库子目录 → 打开 Git 远程地址 | 将 `git@github.com:org/repo.git` 转成 `https://github.com/org/repo` 后打开。 |
| 在 `Manage.cmd` 选择“安装 / 更新” | 仅安装或更新 `open-git-remote`。 |
| 在 `Manage.cmd` 选择“卸载” | 仅移除本包菜单，保留其他包。 |

**系统兼容性：** 当前目标为 [**Windows**](https://www.microsoft.com/windows) 10 / 11 图形桌面，要求系统 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) 5.1 Desktop、.NET 与 STA；各系统版本和架构仍待实机验收，未锁定统一最低 build。XP / Vista / Windows 8 不支持当前入口；Windows 7 SP1 / 8.1 安装 [**WMF 5.1**](https://www.microsoft.com/en-us/download/details.aspx?id=54616)（要求 .NET Framework 4.5+）后，也仅可探索基础静态菜单，不构成对本包完整功能的支持承诺。Windows 11 使用“显示更多选项”或 `Shift+F10`；x86 / ARM64 均未获全功能实机兼容保证。

**本包依赖与测试范围：** 本包采用静态菜单，安装无需 MSVC；Git for Windows、默认浏览器及其网络 / 认证能力的系统要求单独满足。虚拟机可验证路径解析与浏览器打开，菜单能显示不代表旧系统浏览器已具备访问远端的能力。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、适用范围与前提 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 系统为 Windows 10 / 11，系统自带的 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) `5.1` Desktop、系统 .NET 与图形桌面可用。
- 单个文件、文件夹、磁盘根目录和文件夹空白处；文件按其父目录解析。
- 执行时需要健康的 Git 与默认浏览器；安装菜单本身不下载工具。
- 菜单按单选设计，多选批量操作不在支持范围内。**Windows 11 需要进入“显示更多选项”或使用 `Shift+F10` 打开经典菜单。**
- 安装作用于当前用户，不需要管理员权限；不修改系统菜单样式、默认关联或永久执行策略。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、安装与卸载 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

### <span id="jobs-toc-heading-4" data-jobs-toc="v2">安装 / 更新： [Manage.cmd](./Manage.cmd)</span><!-- jobs-toc:heading-end -->

> **目的：** 只安装或更新“打开 Git 远程地址”。

- 打印脚本来源、包身份、目标目录与注册表范围，确认后部署本包。
- 复制本包运行文件到独立版本目录，逐文件核对 SHA-256，备份本包菜单注册。
- 只写本包菜单和配置；遇到同名但无本工具归属标记的注册表键则停止。
- 本包提交失败时回滚本包菜单与配置；完成后重新右键查看，不强制重启资源管理器。

### <span id="jobs-toc-heading-5" data-jobs-toc="v2">卸载： [Manage.cmd](./Manage.cmd)</span><!-- jobs-toc:heading-end -->

> **目的：** 只移除“打开 Git 远程地址”，保留可追溯数据。

- 确认后备份本包注册，移除本包菜单和开始菜单卸载快捷方式。
- 保留 `settings.json` 并写入 `Enabled=false`，避免兼容配置重新启用本项。
- 保留本包运行版本、日志、备份和私有工具；不删除其他软件，也不停止其他会话。
- 需要彻底清理时，先等待本包会话退出，再手动清理本包部署目录。

入口从自身位置查找脚本，不依赖启动目录。`-ExecutionPolicy Bypass` 仅作用于本次进程。企业执行策略或应用控制仍可能限制未签名脚本，应遵循设备管理策略。

## <span id="jobs-toc-heading-6" data-jobs-toc="v2">三、功能行为与风险 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 通过 Git 自身解析普通仓库、子模块、`.git` 指针文件、linked worktree 和上级工作树。
- 优先当前分支关联 remote，其次 `origin`，最后只接受唯一 remote；缺少或有歧义时停止。
- 浏览器转换移除凭据，拒绝本地路径和非网络协议；复制原始地址由独立的 `JobsGitRemoteCopier` 包提供。

## <span id="jobs-toc-heading-7" data-jobs-toc="v2">四、目录与状态 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

```text
JobsGitRemoteOpener/
├── Extension.json              本包身份与菜单属性
├── Manage.cmd                  本包安装 / 更新与卸载管理
├── README.md
└── Scripts/
    ├── Manage.ps1              本包管理入口
    ├── PackageInstaller.psm1   本包注册、备份、回滚与状态提交
    ├── Common.psm1             随包内嵌的通用基础实现
    ├── Invoke.ps1              本包菜单运行入口
    └── Action.psm1             本功能业务实现
```

全部运行文件均在包内。即使移走总目录及其他包，本包仍能独立安装、运行和卸载。

状态位于当前用户本地应用数据的 `Jobs\WindowsExtension\extensions\open-git-remote` 中；`settings.json` 保存 `Version: 2`、`Enabled` 和 `ReleasePath`。`releases/`、`logs/`、`backups/` 和 `tools/` 分别保存本包运行版本、日志、菜单快照和私有依赖；实际日志及备份位置由运行入口打印。菜单直接运行本包业务，不使用总目录的集中请求队列。

注册表范围限于当前用户 `HKCU\Software\Classes` 下的 `shell\Jobs.WindowsExtension.open-git-remote` 菜单键，不写 `HKLM`。适用对象由本包 `Extension.json` 的 `DirectoryOnly` 控制。

安装状态按功能独立读取：本包状态优先；缺少时才读取兼容总配置中的本项选择。安装或卸载只更新本项，其它功能、运行目录和备份保留。

## <span id="jobs-toc-heading-8" data-jobs-toc="v2">五、排查与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

不能打开时，先确认目标位于 Git 工作树、remote 可唯一确定且为网络仓库地址。需要登录的仓库仍由浏览器处理登录。

菜单未出现时，重新右键并检查 Windows 11 经典菜单入口，再查看本包安装日志。其他包的菜单状态与日志无需改动。

源码的语法、独立包结构和跨平台回归不能代替 Windows 真实桌面验收；应在 Windows 核对安装确认、菜单对象、中文特殊路径、依赖缺失分支以及只卸载本包后其他功能仍可用。普通验证不执行真实业务写操作。

管理安装 / 卸载时双击 `Manage.cmd`，它只通过 WScript 唤起 GUI，随后立即结束本次脚本；不在 CMD 中编译、安装或等待输入。也可直接双击 `Manage.vbs` 进入同一面板。每个选项显示等待、执行中、完成或失败，底部实时滚动标准输出和错误，可选中复制或点击“复制全部日志”；无可靠百分比时显示执行中，总体显示完成项数。运行期间等当前事务结束后关闭，完整管理日志位于系统临时目录 `JobsExtensionManager-<运行编号>.log`。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

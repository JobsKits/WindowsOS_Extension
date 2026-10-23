# `JobsGitEmptyCommitPusher`

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

**右键功能：空白 Commit 并 Push。** 在确认工作树和推送目标后，为当前 [**Git**](https://git-scm.com/) 分支创建空白提交并推送。

这是可独立复制和使用的 [**Windows**](https://www.microsoft.com/windows) 功能包，自带安装、卸载和运行源码，不需要总目录或其他功能包。**只复制整个 `JobsGitEmptyCommitPusher` 文件夹，双击 [`Install.cmd`](./Install.cmd) 即可安装本项；[`Uninstall.cmd`](./Uninstall.cmd) 只卸载本项。**

| 操作 | 结果 |
| --- | --- |
| 右键有明确 upstream 的仓库目录 → 空白 Commit 并 Push | 展示目标并要求输入 `YES`，确认后创建空白提交并只推送该提交。 |
| 单独运行包内 `Install.cmd` | 仅安装或更新 `git-empty-commit-push`。 |
| 单独运行包内 `Uninstall.cmd` | 仅移除本包菜单，保留其他包。 |

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、适用范围与前提 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 系统为 Windows 10 / 11，系统自带的 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) `5.1` Desktop、系统 .NET 与图形桌面可用。
- 仅文件夹及文件夹空白处；目标和父目录必须为普通目录。
- 需要健康的 Git、可解析工作树、当前分支与明确上游，以及可用的仓库认证。
- 菜单按单选设计，多选批量操作不在支持范围内。**Windows 11 需要进入“显示更多选项”或使用 `Shift+F10` 打开经典菜单。**
- 安装作用于当前用户，不需要管理员权限；不修改系统菜单样式、默认关联或永久执行策略。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、安装与卸载 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

### <span id="jobs-toc-heading-4" data-jobs-toc="v2">[Install.cmd](./Install.cmd)</span><!-- jobs-toc:heading-end -->

> **目的：** 只安装或更新“空白 Commit 并 Push”。

- 打印脚本来源、包身份、目标目录与注册表范围，确认后部署本包。
- 复制本包运行文件到独立版本目录，逐文件核对 SHA-256，备份本包菜单注册。
- 只写本包菜单和配置；遇到同名但无本工具归属标记的注册表键则停止。
- 本包提交失败时回滚本包菜单与配置；完成后重新右键查看，不强制重启资源管理器。

### <span id="jobs-toc-heading-5" data-jobs-toc="v2">[Uninstall.cmd](./Uninstall.cmd)</span><!-- jobs-toc:heading-end -->

> **目的：** 只移除“空白 Commit 并 Push”，保留可追溯数据。

- 确认后备份本包注册，移除本包菜单和开始菜单卸载快捷方式。
- 保留 `settings.json` 并写入 `Enabled=false`，避免兼容配置重新启用本项。
- 保留本包运行版本、日志、备份和私有工具；不删除其他软件，也不停止其他会话。
- 需要彻底清理时，先等待本包会话退出，再手动清理本包部署目录。

入口从自身位置查找脚本，不依赖启动目录。`-ExecutionPolicy Bypass` 仅作用于本次进程。企业执行策略或应用控制仍可能限制未签名脚本，应遵循设备管理策略。

## <span id="jobs-toc-heading-6" data-jobs-toc="v2">三、功能行为与风险 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 暂存区非空、detached HEAD、没有明确上游或推送配置不明确时停止。允许未暂存 / 未跟踪文件存在。
- 禁止 `git add`、强推和全分支推送；只有输入精确 `YES` 后才创建与推送空白提交。
- 推送使用已核对的提交 SHA 和确认过的目标地址；Git hooks 按仓库配置运行，hooks 改变提交树时停止推送。
- 推送失败保留本地提交并明确提示；先核对现场再处理，不能盲目重试整个操作以免再创建空白提交。

## <span id="jobs-toc-heading-7" data-jobs-toc="v2">四、目录与状态 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

```text
JobsGitEmptyCommitPusher/
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

状态位于当前用户本地应用数据的 `Jobs\WindowsExtension\extensions\git-empty-commit-push` 中；`settings.json` 保存 `Version: 2`、`Enabled` 和 `ReleasePath`。`releases/`、`logs/`、`backups/` 和 `tools/` 分别保存本包运行版本、日志、菜单快照和私有依赖；实际日志及备份位置由运行入口打印。菜单直接运行本包业务，不使用总目录的集中请求队列。

注册表范围限于当前用户 `HKCU\Software\Classes` 下的 `shell\Jobs.WindowsExtension.git-empty-commit-push` 菜单键，不写 `HKLM`。适用对象由本包 `Extension.json` 的 `DirectoryOnly` 控制。

安装状态按功能独立读取：本包状态优先；缺少时才读取兼容总配置中的本项选择。安装或卸载只更新本项，其它功能、运行目录和备份保留。

## <span id="jobs-toc-heading-8" data-jobs-toc="v2">五、排查与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

此功能会写入提交历史并访问远程。失败时查看本包日志和当前分支，确认是否已创建提交；菜单卸载不会撤销已创建或推送的提交。

菜单未出现时，重新右键并检查 Windows 11 经典菜单入口，再查看本包安装日志。其他包的菜单状态与日志无需改动。

源码的语法、独立包结构和跨平台回归不能代替 Windows 真实桌面验收；应在 Windows 核对安装确认、菜单对象、中文特殊路径、依赖缺失分支以及只卸载本包后其他功能仍可用。普通验证不执行真实业务写操作。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

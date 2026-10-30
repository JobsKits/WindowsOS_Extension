# `JobsGitPuller`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、冲突三选项](#jobs-toc-heading-2)
- [二、安装与卸载](#jobs-toc-heading-3)
- [三、范围与依赖](#jobs-toc-heading-4)
- [四、保护、日志与人工恢复](#jobs-toc-heading-5)
- [五、文件与验证](#jobs-toc-heading-6)

</details>
<!-- jobs-toc:end -->

---

**管理操作：** 本目录以 `Manage.cmd` 为轻量启动入口，只唤起 GUI 后结束本次脚本；先在面板选择安装 / 更新或卸载。在面板确认安装 / 更新或卸载后立即执行，无二次终端确认。关闭或取消面板不执行；卸载保留日志、备份、运行文件和工具。

## 🔥 <span id="前言">前言</span>

**最低支持系统：Windows 10 64 位（x64）。** 这是当前最低支持目标；具体最低 build 尚未锁定，完整实机兼容性仍待验证。最低基线不等于所有功能已经实测通过。

**右键功能：拉取 Git 到最新。** 将当前文件夹所属 [**Git**](https://git-scm.com/) 工作树的当前分支整合到其已配置 upstream 最新提交；保留本地已提交历史，不强制对齐远端。

这是可独立复制的 [**Windows**](https://www.microsoft.com/windows) 功能包。复制整个 `JobsGitPuller` 文件夹，双击 [`Manage.cmd`](./Manage.cmd) 安装本项；[`Manage.cmd`](./Manage.cmd) 只卸载本项。运行源码、安装器和基础模块都在包内，不依赖总目录或相邻功能包。

| 情况 | 行为 |
| --- | --- |
| 当前文件夹不属于 Git 工作树 | 静默返回，不访问远端。 |
| 工作树干净 | 显示分支、remote 与脱敏来源，fetch 后 merge 最新 upstream。 |
| 有未提交内容 | 列出改动；直接回车确认，任意非空输入（包括空格）或 EOF 取消。 |
| 拉取或恢复本地改动产生冲突 | 提供下列三个选项；提交后仍可能再次冲突。 |
| 网络、认证、权限或快照失败 | 报错停止；不会误进入放弃改动菜单。 |

**系统兼容性：** 当前目标为 [**Windows**](https://www.microsoft.com/windows) 10 / 11 图形桌面，要求系统 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) 5.1 Desktop、.NET 与 STA；各系统版本和架构仍待实机验收，未锁定统一最低 build。XP / Vista / Windows 8 不支持当前入口；Windows 7 SP1 / 8.1 安装 [**WMF 5.1**](https://www.microsoft.com/en-us/download/details.aspx?id=54616)（要求 .NET Framework 4.5+）后，也仅可探索基础静态菜单，不构成对本包完整功能的支持承诺。Windows 11 使用“显示更多选项”或 `Shift+F10`；x86 / ARM64 均未获全功能实机兼容保证。

**本包依赖与测试范围：** 本包采用静态菜单，安装无需 MSVC；Git for Windows、凭据组件和仓库 hooks 的系统 / 架构要求单独满足。虚拟机业务验证应使用临时仓库和临时远端，覆盖拉取、冲突与恢复，不能由菜单显示推定实际 Git 兼容。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、冲突三选项 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 输入 | 执行结果 |
| --- | --- |
| `1`、空行或 EOF | 恢复**本轮**拉取前 HEAD、暂存区、未暂存文件及快照内未跟踪文件，然后退出。 |
| `2`，再精确输入 `YES` | 恢复本轮基线，放弃本轮未提交内容，再次 fetch / merge。保留本地已提交历史，不 reset 到远端；忽略文件不删除。取消 `YES` 时恢复本轮基线并退出。 |
| `3` | 恢复本轮基线，输入 Commit 信息后提交，再次 fetch / merge。**直接回车允许空 Commit 信息**，EOF 取消；没有可提交改动时恢复后停止。 |

`2` 或 `3` 成功后，已确认的放弃结果或新提交成为下一轮基线。再次发生代码冲突仍提供三选项；此时选 `1` 会保留刚创建的本地提交，已确认放弃的旧改动不会重新出现。最初与后续快照引用都继续保留，便于人工找回。此功能不会推送提交。

等待输入后会复核分支、HEAD、暂存及工作文件内容。发现外部编辑或探测失败时保留现场并停止，不自动重置；运行期间请勿同时编辑或操作同一仓库。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、安装与卸载 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

唯一管理入口直接放在包根目录，独立于总目录安装面板；本包可单独拷走安装，不依赖相邻功能包。

在 [`Manage.cmd`](./Manage.cmd) 选择“安装 / 更新”，显示来源、包身份及目标，确认后仅复制本包，逐文件校验 SHA-256 并注册当前用户 `HKCU\Software\Classes` 下本包菜单。缺 [**Git for Windows**](https://git-scm.com/download/win) 时提示并停止，不自动安装工具。遇到未知同名注册键时停止；本包部署失败时恢复本包注册与配置。它不联网、不提权、不改永久执行策略。

在 [`Manage.cmd`](./Manage.cmd) 唤起的面板选择“卸载”，点击按钮后仅移除本包菜单及卸载快捷方式，写入 `Enabled=false`，保留程序版本、日志与菜单备份；不会撤销 Git 拉取、提交或恢复锚点。入口从自身位置找文件，不依赖终端启动目录。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、范围与依赖 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- Windows 10 / 11，系统 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) `5.1 Desktop`、系统 .NET 与图形桌面。
- 仅文件夹及目录空白处，单选；选择工作树内的子目录时操作整个所属仓库。目标及父目录必须为普通目录。
- Windows 11 通过“显示更多选项”或 `Shift+F10` 进入经典右键菜单。
- 需要已有提交、正常本地分支及唯一远端 upstream；没有 upstream、detached HEAD、裸仓库、正在 merge / rebase / cherry-pick 的仓库均停止。
- 稀疏检出、`assume-unchanged`、`skip-worktree`、变化中的子模块、未跟踪嵌套 Git、未跟踪符号链接不进入自动快照。子模块不递归拉取、更新、暂存或清理。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、保护、日志与人工恢复 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

首次先 fetch 确认网络可用，不改变本地 index / 工作文件；随后创建 HEAD 锚点和原 index 副本，使用 `stash push --include-untracked` 保存父仓改动，并以独立引用固定 stash 对象。合并关闭自动 stash 和子模块递归，使用 `--no-overwrite-ignore` 拒绝覆盖忽略文件。恢复使用 `stash apply --index`，保留暂存 / 未暂存边界，**不 pop 或 drop 任何 stash**。Git hooks 按仓库原配置执行，提交失败时保留提交尝试后的现场与原恢复锚点。

恢复和放弃操作只考虑本轮快照记载的未跟踪文件，删除前核对路径、文件类型及 Git blob；内容在操作期间改变时停止。不会运行 `git clean`，也不会递归删除忽略目录或嵌套仓库。上游改动进入已有嵌套 Git 或符号链接路径时拒绝自动合并。每个共享 Git 元数据目录只允许一个本功能会话；linked worktree 共用同一把锁。

菜单状态、release、安装备份和脱敏日志保存在当前用户本地应用数据的 `Jobs\WindowsExtension\extensions\git-pull-latest`，分别位于 `settings.json`、`releases/`、`backups/` 与 `logs/`。Git 业务恢复记录保存在目标仓库实际 Git 元数据的 `jobs-git-puller/<会话ID>/recovery.json`，原 index 副本为同目录 `index.before`；终端打印精确位置。恢复引用为 `refs/jobs-git-puller/<会话ID>/head` 及有本地改动时的 `/worktree`，每次 fetch 还将远端提交固定在唯一的 `/upstream` 引用，避免其它窗口更新 `FETCH_HEAD` 后合并错误目标。以上引用默认长期保留，占用空间由用户检查后自行管理。

人工恢复前先检查当前分支和改动，另行保存当前现场。将下例 `<会话ID>` 替换为终端打印的真实会话，再只读查看快照；不要在存在新改动时直接重置或重复 apply：

```powershell
git show --stat refs/jobs-git-puller/<会话ID>/head
git stash show --stat refs/jobs-git-puller/<会话ID>/worktree
```

部分失败、进程中断或外部并发写入不能保证自动复原。恢复引用不会因本工具卸载而删除；也不会替代忽略文件、子仓或整个磁盘的备份。

## <span id="jobs-toc-heading-6" data-jobs-toc="v2">五、文件与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

```text
JobsGitPuller/
├── Extension.json              本包菜单身份与属性
├── Manage.cmd  当前用户本包安装与卸载
├── README.md
└── Scripts/
    ├── README.md               源码职责和入口
    ├── Manage.ps1              本包管理入口
    ├── PackageInstaller.psm1   本包部署、注册、菜单备份与事务恢复
    ├── Common.psm1             内嵌路径、进程及日志工具
    ├── Invoke.ps1              本包交互终端入口
    └── Action.psm1             Git 检测、快照、拉取与冲突状态机
```

仓库 [`Tests/GitPuller.Tests.ps1`](../Tests/GitPuller.Tests.ps1) 使用临时裸远端、工作树和自动输入检查核心流程；不操作真实项目、不执行安装入口。独立包、参数转义、基础设施同步及目录过滤器回归一并检查。Windows 真实桌面的菜单显示、注册表、Git 凭据窗口和 Windows PowerShell 5.1 仍需现场验收；macOS 便携 PowerShell 的测试不能替代这些验收。

管理安装 / 卸载时双击 `Manage.cmd`，它只通过 WScript 唤起 GUI，随后立即结束本次脚本；不在 CMD 中编译、安装或等待输入。也可直接双击 `Manage.vbs` 进入同一面板。每个选项显示等待、执行中、完成或失败，底部实时滚动标准输出和错误，可选中复制或点击“复制全部日志”；无可靠百分比时显示执行中，总体显示完成项数。运行期间等当前事务结束后关闭，完整管理日志位于系统临时目录 `JobsExtensionManager-<运行编号>.log`。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

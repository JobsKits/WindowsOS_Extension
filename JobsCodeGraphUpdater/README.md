# `JobsCodeGraphUpdater`

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

**右键功能：更新代码地图（.codegraph）。** 在精确选定的工程目录中创建或更新 [**CodeGraph**](https://github.com/colbymchenry/codegraph) 代码地图。

这是可独立复制和使用的 [**Windows**](https://www.microsoft.com/windows) 功能包，自带安装、卸载和运行源码，不需要总目录或其他功能包。**只复制整个 `JobsCodeGraphUpdater` 文件夹，双击 [`Manage.cmd`](./Manage.cmd)，在面板选择“安装 / 更新”或“卸载”；只处理本项。**

| 操作 | 结果 |
| --- | --- |
| 右键工程目录 → 更新代码地图（.codegraph） | 当前层无图则创建，有图则同步，并核对输出指向当前目标。 |
| 在 `Manage.cmd` 选择“安装 / 更新” | 仅安装或更新 `codegraph-bootstrap`。 |
| 在 `Manage.cmd` 选择“卸载” | 仅移除本包菜单，保留其他包。 |

**系统兼容性：** 当前目标为 [**Windows**](https://www.microsoft.com/windows) 10 / 11 图形桌面，要求系统 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) 5.1 Desktop、.NET 与 STA；各系统版本和架构仍待实机验收，未锁定统一最低 build。XP / Vista / Windows 8 不支持当前入口；Windows 7 SP1 / 8.1 安装 [**WMF 5.1**](https://www.microsoft.com/en-us/download/details.aspx?id=54616)（要求 .NET Framework 4.5+）后，也仅可探索基础静态菜单，不构成对本包完整功能的支持承诺。Windows 11 使用“显示更多选项”或 `Shift+F10`；x86 / ARM64 均未获全功能实机兼容保证。

**本包依赖与测试范围：** 本包安装静态菜单无需 MSVC；业务只接受 Windows x64 / ARM64 的 CodeGraph 1.6.2，x86 不支持。Node / WinGet 及 CLI 随包运行时可能有更高系统或 build 下限；WMF 5.1 可安装不代表这些依赖可运行。虚拟机可验证菜单与实际代码地图动作，仍需记录真实工具版本和架构。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、适用范围与前提 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 系统为 Windows 10 / 11，系统自带的 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) `5.1` Desktop、系统 .NET 与图形桌面可用。
- 仅文件夹及文件夹空白处；目标和父目录必须为普通目录。
- 使用已核对行为的 CodeGraph `1.6.2`，支持 Windows x64 / ARM64；业务使用其随包 Node / SQLite 运行时，安装通道要求健康的 [**Node.js**](https://nodejs.org/) `>=20 <25` / [**npm**](https://docs.npmjs.com/)。
- 菜单按单选设计，多选批量操作不在支持范围内。**Windows 11 需要进入“显示更多选项”或使用 `Shift+F10` 打开经典菜单。**
- 安装作用于当前用户，不需要管理员权限；不修改系统菜单样式、默认关联或永久执行策略。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、安装与卸载 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

### <span id="jobs-toc-heading-4" data-jobs-toc="v2">安装 / 更新： [Manage.cmd](./Manage.cmd)</span><!-- jobs-toc:heading-end -->

> **目的：** 只安装或更新“更新代码地图（.codegraph）”。

- 打印脚本来源、包身份、目标目录与注册表范围，确认后部署本包。
- 复制本包运行文件到独立版本目录，逐文件核对 SHA-256，备份本包菜单注册。
- 只写本包菜单和配置；遇到同名但无本工具归属标记的注册表键则停止。
- 本包提交失败时回滚本包菜单与配置；完成后重新右键查看，不强制重启资源管理器。

### <span id="jobs-toc-heading-5" data-jobs-toc="v2">卸载： [Manage.cmd](./Manage.cmd)</span><!-- jobs-toc:heading-end -->

> **目的：** 只移除“更新代码地图（.codegraph）”，保留可追溯数据。

- 确认后备份本包注册，移除本包菜单和开始菜单卸载快捷方式。
- 保留 `settings.json` 并写入 `Enabled=false`，避免兼容配置重新启用本项。
- 保留本包运行版本、日志、备份和私有工具；不删除其他软件，也不停止其他会话。
- 需要彻底清理时，先等待本包会话退出，再手动清理本包部署目录。

入口从自身位置查找脚本，不依赖启动目录。`-ExecutionPolicy Bypass` 仅作用于本次进程。企业执行策略或应用控制仍可能限制未签名脚本，应遵循设备管理策略。

## <span id="jobs-toc-heading-6" data-jobs-toc="v2">三、功能行为与风险 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 每次先体检 PowerShell / .NET、已有 Node/npm、[**WinGet**](https://learn.microsoft.com/windows/package-manager/winget/)、CodeGraph 随包 Node / SQLite 及 `init` / `sync` / `status` 命令；输出实际路径与版本。健康 CLI 可直接更新地图，未使用的缺失上游仅诊断，不强制安装。
- 缺少或损坏匹配 CLI 时，沿实际安装链补齐依赖：先复用健康 Node/npm；需要修复时从 WinGet 官方源 `OpenJS.NodeJS.LTS` 的版本清单选择最高 `24.x`，展示精确版本与来源，回车确认后只尝试一次安装，再刷新本进程 PATH 并复检。为修复同版本损坏，强制重跑所选官方安装器；可能替换现有损坏或不兼容 Node、请求系统授权并更新其 PATH，扩展不主动提权。
- WinGet 本身缺失 / 损坏、官方源无可核实的 `24.x`、安装或复检失败时，打印官方修复来源并停止。不会自动安装 WSL、修改代理或替换健康工具。
- 安装上游就绪后，展示[官方 npm 包来源](https://www.npmjs.com/package/@colbymchenry/codegraph/v/1.6.2)，回车确认后检查官方 npm 源连通性，再安装 / 修复到本包私有 `tools/`，禁止 npm 生命周期脚本；随包 Node、SQLite 真实读写和 CLI 命令再次体检通过才开始目标建图。每层失败停止，不无限重试。
- 不主动升级健康工具；本包只刷新当前进程 PATH，Node 官方安装器可能登记系统 / 用户 PATH。不启动 watcher / server，不安装 Git hooks。
- 先以随包运行时只读检查目标层的 [**SQLite**](https://sqlite.org/) 数据库；拒绝损坏、缺少节点表、路径不符或重解析目录，不回退父目录建图。
- 运行后核对目标与结果；失败即停止，窗口保留到回车关闭。工具安装及代码地图写入都属于明确确认后的操作。

[**Homebrew**](https://docs.brew.sh/Homebrew-on-Linux) 在 Windows 只支持 WSL 2 的 Linux 环境，不能安装本菜单使用的 Windows 原生工具链；本包采用上述 WinGet / 官方 npm 路线，macOS 的 Homebrew 路线由平行扩展负责。

| 体检层 | 检查及失败处理 |
| --- | --- |
| 系统宿主 | Windows PowerShell 5.1 Desktop、.NET SHA-256、x64 / ARM64；不满足即停止。 |
| 安装上游 | Node 主版本范围、标准库可用性及 npm 实际启动；WinGet 版本 / `--info`。健康独立 CLI 无须修复这些上游。 |
| 必需安装路径 | WinGet 官方源精确 `24.x` → Node/npm 复检 → 私有 npm 包 → CLI 复检；任一步失败阻止下游。 |
| 代码地图运行时 | 版本 `1.6.2`、内存 SQLite 建表 / 写入 / 读取、必需命令帮助。 |
| 精确项目输出 | 写前只读数据库完整性；写后 JSON 必须包含当前目标的绝对项目 / 索引路径、完成状态及零待处理变更。 |

## <span id="jobs-toc-heading-7" data-jobs-toc="v2">四、目录与状态 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

```text
JobsCodeGraphUpdater/
├── Extension.json              本包身份与菜单属性
├── Manage.cmd                  本包安装 / 更新与卸载管理
├── README.md
└── Scripts/
    ├── Manage.ps1              本包管理入口
    ├── PackageInstaller.psm1   本包注册、备份、回滚与状态提交
    ├── Common.psm1             随包内嵌的通用基础实现
    ├── Invoke.ps1              本包菜单运行入口
    ├── Action.psm1             本功能业务实现
    └── README.md               运行链、依赖体检与维护验证
```

全部运行文件均在包内。即使移走总目录及其他包，本包仍能独立安装、运行和卸载。

状态位于当前用户本地应用数据的 `Jobs\WindowsExtension\extensions\codegraph-bootstrap` 中；`settings.json` 保存 `Version: 2`、`Enabled` 和 `ReleasePath`。`releases/`、`logs/`、`backups/` 和 `tools/` 分别保存本包运行版本、日志、菜单快照和私有依赖；实际日志及备份位置由运行入口打印。菜单直接运行本包业务，不使用总目录的集中请求队列。

注册表范围限于当前用户 `HKCU\Software\Classes` 下的 `shell\Jobs.WindowsExtension.codegraph-bootstrap` 菜单键，不写 `HKLM`。适用对象由本包 `Extension.json` 的 `DirectoryOnly` 控制。

安装状态按功能独立读取：本包状态优先；缺少时才读取兼容总配置中的本项选择。安装或卸载只更新本项，其它功能、运行目录和备份保留。

## <span id="jobs-toc-heading-8" data-jobs-toc="v2">五、排查与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

遇到已有 `.codegraph` 检查失败时先保留现场并查看本包日志，不删除数据库后盲目重试；缺工具分支会显示精确安装来源。上游提示异常时，先看它是否正在阻塞安装：已有健康的随包运行时可以继续更新地图；需要安装时必须先修复该层。Windows Node `25+` 不满足此版本安装兼容范围，不会被误判为健康安装通道。

菜单未出现时，重新右键并检查 Windows 11 经典菜单入口，再查看本包安装日志。其他包的菜单状态与日志无需改动。

源码的语法、独立包结构和跨平台回归不能代替 Windows 真实桌面验收；应在 Windows 核对安装确认、菜单对象、中文特殊路径、依赖缺失分支以及只卸载本包后其他功能仍可用。普通验证不执行真实业务写操作。

管理安装 / 卸载时双击 `Manage.cmd`，它只通过 WScript 唤起 GUI，随后立即结束本次脚本；不在 CMD 中编译、安装或等待输入。也可直接双击 `Manage.vbs` 进入同一面板。每个选项显示等待、执行中、完成或失败，底部实时滚动标准输出和错误，可选中复制或点击“复制全部日志”；无可靠百分比时显示执行中，总体显示完成项数。运行期间等当前事务结束后关闭，完整管理日志位于系统临时目录 `JobsExtensionManager-<运行编号>.log`。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

# `Windows@Extension`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

为 [**Windows**](https://www.microsoft.com/windows) 开发人员提供资源管理器右键菜单，与同级 [`MacOS@Extension`](../MacOS@Extension/README.md) 对齐日常开发操作。提供 **10 个独立功能包**：每包自带功能源码、安装、卸载和运行模块，可以只复制其中一个包使用；根入口提供 **10 项复选框组合安装面板**。使用系统自带的 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) `5.1`，不需要编译、不需要管理员权限。

**快速开始：** 将整个 `Windows@Extension` 文件夹复制到 Windows，双击 [`Install.cmd`](./Install.cmd)，在原生复选框窗口选择功能并保存。只需一项功能时，也可单独复制对应包，双击包内 `Install.cmd`；例如 [`JobsPathCopier/Install.cmd`](./JobsPathCopier/Install.cmd) 只安装复制绝对路径。重新右键文件、文件夹、磁盘或文件夹空白处即可；**Windows 11 需要点击“显示更多选项”**，也可使用 `Shift+F10` 打开经典菜单。

| 操作 | 实际结果 |
| --- | --- |
| 右键 `D:\项目\Demo` → 复制绝对路径 | 剪贴板得到 `D:\项目\Demo`，无额外引号。 |
| 右键源文件 → 用终端打开 | 在源文件的父目录启动终端。 |
| 总面板保存时取消勾选某一已安装功能 | 调用该包自己的卸载逻辑；已选功能逐包安装或更新。 |
| 只复制 `JobsPathCopier` 并运行包内 `Install.cmd` | 只部署复制路径包，不需要总目录或其他九个包。 |
| 在 Windows 11 找不到菜单 | 进入“显示更多选项”；不修改系统菜单样式。 |
| 单包卸载 | 只移除该包菜单，保存 `Enabled=false`，保留运行文件、日志、备份和工具依赖。 |
| 总面板中一包失败 | 停止后续操作，列出已完成和失败的包；已完成的包保持其结果。 |

导航：[功能对照](#features) · [安装配置](#installation) · [目录结构](#structure) · [运行边界](#behavior) · [验证](#verification)

## 一、<span id="features">功能对照</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 独立功能包 | 右键功能与行为 |
| --- | --- |
| [JobsGitRemoteOpener](./JobsGitRemoteOpener/README.md) | 打开 Git 远程地址；文件、文件夹及背景目录，找到当前 [**Git**](https://git-scm.com/) 工作树的远程地址，转换为浏览器网页。 |
| [JobsGitRemoteCopier](./JobsGitRemoteCopier/README.md) | 复制 Git 远程地址；复制原始 remote，包括 SSH 协议与 `.git` 后缀，不把复制结果改成网页地址。 |
| [JobsPathCopier](./JobsPathCopier/README.md) | 复制绝对路径；单个文件、文件夹、磁盘根目录或当前背景目录。 |
| [JobsVisualStudioOpener](./JobsVisualStudioOpener/README.md) | 用 [**Visual Studio**](https://visualstudio.microsoft.com/) 打开项目；优先当前层 `.sln` / `.slnx`，其次项目文件，多个候选时明确选择。 |
| [JobsVSCodeOpener](./JobsVSCodeOpener/README.md) | 用 [**Visual Studio Code**](https://code.visualstudio.com) 打开项目；当前文件夹，选中文件时打开其父目录。 |
| [JobsAndroidStudioOpener](./JobsAndroidStudioOpener/README.md) | 用 [**Android Studio**](https://developer.android.com/studio?hl=zh-c) 打开项目；当前文件夹，选中文件时打开其父目录。 |
| [JobsTerminalOpener](./JobsTerminalOpener/README.md) | 用终端打开；优先 [**Windows Terminal**](https://learn.microsoft.com/windows/terminal/)，未安装时回退系统 PowerShell，工作目录为所选目录或文件父目录。 |
| [JobsFlutterPubGet](./JobsFlutterPubGet/README.md) | Flutter 安装依赖（pub get）；仅文件夹，检查同层 `pubspec.yaml`、`lib/` 和 Flutter SDK 声明后执行 [**Flutter**](https://flutter.dev/) 依赖获取。 |
| [JobsCodeGraphUpdater](./JobsCodeGraphUpdater/README.md) | 更新代码地图（.codegraph）；仅文件夹，当前层无图时创建、有图时同步 [**CodeGraph**](https://github.com/colbymchenry/codegraph)，检查结果指向精确目标。 |
| [JobsGitEmptyCommitPusher](./JobsGitEmptyCommitPusher/README.md) | 空白 Commit 并 Push；仅文件夹，检查工作树、当前分支、暂存区和上游，输入 `YES` 后创建空白提交并推送。 |

macOS 原版的 [**Xcode**](https://developer.apple.com/xcode/) 项目入口由 Visual Studio 项目入口承接；[**CocoaPods**](https://cocoapods.org/) 的安装 / 升级入口属于 macOS 工具链，Windows 版不提供。两端当前分别是 11 项和 10 项。

每项功能拥有独立源码包、运行目录、菜单注册、配置、日志及卸载入口；包内运行代码不引用总目录或其他包。通用基础代码在维护时同步到各包，安装后不需要共享运行模块。经典静态菜单无法在打开菜单时运行完整项目检测；启用的目录操作会显示在普通目录菜单中，点击后再校验并给出具体错误，非法目标不会运行依赖或提交命令。菜单按单选设计，多选批量操作不在支持范围内。

## 二、<span id="installation">安装、配置与卸载</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

系统前提：Windows 10 / 11，Windows PowerShell `5.1` Desktop、系统 .NET 与图形桌面可用。各功能只在执行时检查自己的 Git、IDE 或 SDK 依赖；安装菜单本身不下载软件。企业执行策略、应用控制或杀毒策略可能阻止未签名脚本，须遵循设备管理策略处理。

### [Install.cmd](./Install.cmd)

> **目的：** 打开组合安装面板，按勾选结果调用各包自己的安装或卸载逻辑。

- 打印来源、安装目标和注册表范围，打开可缩放的原生复选框窗口。
  - 首次默认全选；已有状态时按各包的启用状态恢复勾选；取消不写入安装状态。
- 保存后，按清单顺序逐包处理：安装或更新已选包，卸载取消勾选且原先已安装的包。
  - 只部署所选包自身的运行模块；每包逐文件校验 SHA-256，并只检查、备份和修改自己的菜单键。
  - 遇到没有本工具归属标记的同名键，停止并保留原内容。
- 每个包独立提交配置；该包失败时回滚该包的菜单与状态。
  - 整批操作逐包执行；一包失败就停止，汇报已完成与失败项，前面成功的包不撤销。
- 各包创建自己的开始菜单卸载入口，通知资源管理器刷新关联。
  - 不强制重启资源管理器；重新打开右键菜单查看结果。

### [Configure.cmd](./Configure.cmd)

> **目的：** 重新打开同一个组合安装面板，对十项功能分别勾选、关闭、全选或全不选。

- 读取各包的现有状态并勾选已启用项。
- 保存时逐包安装或更新已选项，卸载取消勾选的已安装项；取消保持原选择。
- 组合配置需要保留完整源码总目录，再运行根目录 `Configure.cmd`。
  - 已安装菜单使用各包自己的部署副本，不依赖源码位置；单包仍可独立重装或通过自己的卸载入口移除。

### [Uninstall.cmd](./Uninstall.cmd)

> **目的：** 打开卸载面板，只移除选中的已安装功能包，保留可追溯数据和正在执行的会话。

- 卸载面板只列出已安装的包，默认全部勾选；可以只选择其中几项。
- 每包备份自己的菜单注册，删除自己的菜单键和卸载快捷方式，写入 `Enabled=false` 状态。
  - 保留停用状态可防止旧版总配置把已卸载功能重新识别为启用。
- 保留各包的 `releases/`、`logs/`、`backups/` 和 `tools/`，不删除其他软件或正在运行的会话。
  - 需要彻底清理时，等待本工具终端全部退出，再手动移除当前用户本地应用数据中的 `Jobs\WindowsExtension` 文件夹。

三个总入口只负责选择与编排，不部署集中业务模块。各包的 `Install.cmd` / `Uninstall.cmd` 可直接运行，操作仅涉及该包。所有入口都从自身位置查找脚本，与当前终端目录无关。`-ExecutionPolicy Bypass` 仅作用于本次 PowerShell 进程，不修改系统或用户的永久执行策略；不提权，不配置代理。

也可在项目根目录的 Windows PowerShell 中运行：

```powershell
powershell.exe `
  -NoLogo `
  -NoProfile `
  -STA `
  -ExecutionPolicy Bypass `
  -File .\Scripts\Manage.ps1 `
  -Mode Install
```

## 三、<span id="structure">目录结构与安装状态</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```text
Windows@Extension/
├── Install.cmd / Configure.cmd  十项复选框组合安装入口
├── Uninstall.cmd               已安装包的选择卸载入口
├── Extensions.json             包名与功能标识清单
├── Scripts/                    总面板、清单校验和逐包编排
├── Infrastructure/             纯通用基础代码的维护模板
├── JobsGitRemoteOpener/         打开 Git 远程地址
├── JobsGitRemoteCopier/         复制 Git 远程地址
├── JobsPathCopier/              复制绝对路径
├── JobsVisualStudioOpener/      用 Visual Studio 打开项目
├── JobsVSCodeOpener/            用 VSCode 打开项目
├── JobsAndroidStudioOpener/     用 Android Studio 打开项目
├── JobsTerminalOpener/          用终端打开
├── JobsFlutterPubGet/           Flutter 依赖获取
├── JobsCodeGraphUpdater/        创建或更新代码地图
├── JobsGitEmptyCommitPusher/    空白提交并推送
├── Tests/                      架构、独立包与行为回归
└── .github/workflows/          Windows PowerShell 5.1 验证入口
```

每个功能包采用同一自包含结构：

```text
<功能包名>/
├── Extension.json              包身份、菜单名称与适用范围
├── Install.cmd / Uninstall.cmd  只管理本包的双击入口
├── README.md                   本包的独立使用说明
└── Scripts/
    ├── Manage.ps1              本包安装 / 卸载入口
    ├── PackageInstaller.psm1   本包注册、备份、回滚与状态提交
    ├── Common.psm1             随包内嵌的纯通用基础模块
    ├── Invoke.ps1              本包菜单运行入口
    └── Action.psm1             仅本功能的业务实现
```

包内模块不向上查找总目录或相邻包。`Infrastructure/` 仅用于维护时同步基础代码，运行和独立安装不读取它。`Extension.json` 声明 `Id`、`Name`、`Label`、`Description`、`DirectoryOnly` 和 `Console`；组合清单只登记包身份，业务逻辑归各包的 `Action.psm1`。

安装状态位于**当前用户本地应用数据**的 `Jobs\WindowsExtension\extensions\<功能ID>` 下：每包的 `settings.json` 以 `Version: 2`、`Enabled`、`ReleasePath` 保存启用状态与生效版本；`releases/` 保存该包运行文件；`backups/` 保存该包菜单 CLIXML 快照；`logs/` 保存该包运行日志；`tools/` 保存该包经确认安装的私有依赖。菜单直接启动本包运行入口，业务函数在本包进程内执行。

旧版整体安装按功能逐步迁移：优先读取对应包的新状态；该包尚无新状态时，才读取旧总 `settings.json` 的 `Features`。重装或卸载一个包只迁移该项，不改变其他尚未迁移功能的状态；旧运行目录和备份继续保留。卸载后的 `Enabled=false` 也优先于旧总配置。

注册范围只包含 `HKCU\Software\Classes` 下 `*`、`Directory`、`Directory\Background`、`Drive` 的 `shell\Jobs.WindowsExtension.<功能ID>`。不修改文件默认关联、不占用其他软件的菜单键、不写 `HKLM`。

当前是 `JobsGenesis` 下与 `MacOS@Extension` 平行的源码目录，尚未登记为独立 Git 子模块，也没有创建远端。父仓 `.gitmodules` 没有对应条目，不虚构远端地址或固定提交；因此未提供子仓下载、提交或推送脚本。

### [Sync-PackageInfrastructure.ps1](./Scripts/Sync-PackageInfrastructure.ps1)

> **目的：** 在开发维护时核对或显式同步各独立包内嵌的纯通用基础代码。

- 默认只检查 `Infrastructure/` 中的 `Common.psm1`、`Invoke.ps1`、`Manage.ps1`、`PackageInstaller.psm1` 与十个包的副本是否一致，有差异时报告并失败，不写文件。
- 显式传入 `-Write` 才同步这四份模板到各包；不修改 `Action.psm1`、`Extension.json` 或包的业务配置。
- 修改模板后先同步，再执行回归；CI 使用默认只检查模式，防止维护副本漂移。

从总目录只检查：

```powershell
powershell.exe `
  -NoProfile `
  -ExecutionPolicy Bypass `
  -File .\Scripts\Sync-PackageInfrastructure.ps1
```

开发者确认需要同步后，显式写入：

```powershell
powershell.exe `
  -NoProfile `
  -ExecutionPolicy Bypass `
  -File .\Scripts\Sync-PackageInfrastructure.ps1 `
  -Write
```

## 四、<span id="behavior">命令执行与失败处理</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- **路径传递：** 使用注册表参数和原生进程参数传递路径，菜单仅启动对应包的 `Invoke.ps1`；不把项目路径拼成可执行的 PowerShell 表达式。目录背景、盘符根目录、中文、空格及 `&` / `%` 等特殊字符均按路径数据处理。
  - Flutter、CodeGraph 和 Git 写操作要求目标及父目录均为普通目录；符号链接、目录联接和其他重解析目录会被拒绝，避免操作落到另一个位置。
- **Git 远程：** 通过 Git 自身解析工作树与子模块，兼容 `.git` 文件、linked worktree 和上级工作树。优先当前分支关联 remote，再选 `origin`，最后只接受唯一 remote；缺少或存在歧义时停止。复制保留原地址；浏览器转换移除凭据，拒绝本地路径和非网络协议。
- **IDE：** 查询常规安装位置、PATH，以及 Visual Studio 的 `vswhere.exe`。非标准安装可把真实 IDE 可执行文件目录加入用户 PATH；Android Studio 也支持 `ANDROID_STUDIO_HOME`。缺失时提示并打开官方安装页后结束，不继续打开项目。
- **Flutter：** 复用项目已有 `.fvm/flutter_sdk` 或 PATH 中健康的 SDK，验证项目后确认执行 `flutter pub get`；不自动下载 SDK，不递归寻找其他工程。
- **CodeGraph：** 固定使用已核对命令行为的 `1.6.2`，兼容 Windows x64 / ARM64，复用该版本的健康工具。缺少 [**Node.js**](https://nodejs.org/) / [**npm**](https://docs.npmjs.com/) 时提示安装官方工具链；缺少匹配版本时显示[官方 npm 包来源](https://www.npmjs.com/package/@colbymchenry/codegraph/v/1.6.2)，经确认安装到本工具的私有前缀，不替换已有的其他版本。不主动升级健康工具，不写全局 PATH，不启动 watcher / server，不安装 Git hooks。在调用 CLI 前以随包运行时只读检查当前目录的 [**SQLite**](https://sqlite.org/) 数据库；拒绝损坏、缺少节点表或指向其他位置的 `.codegraph`，不回退父目录建图。
- **空白提交：** 暂存区非空、detached HEAD、没有明确上游或推送配置不明确时停止。允许未暂存 / 未跟踪文件存在，禁止 `git add`、强推或全分支推送。只有在确认前置条件并输入 `YES` 后才会创建和推送空白提交；推送失败保留该提交并明确提示，不能盲目重试整个操作。
  - 推送固定使用已核对的提交 SHA 和确认过的目标地址，避免并行操作改变 `HEAD` 或 remote 后推送其他内容。Git hooks 按仓库原配置运行；若 hooks 改变提交树，停止推送并保留本地现场。
- **日志：** 安装管理和业务终端分别保留日志。Git 远程可能包含凭据；不把原始凭据地址写入日志，复制动作仍按需求保留原地址。终端命令失败返回错误并停止当前流程，窗口保留到回车关闭。
  - Flutter、CodeGraph 和空白提交各自在可见的交互终端中运行本包业务，确认提示和执行结果保持可见。

注册表快照用于排查和恢复本工具菜单状态，保存在安装器输出的精确文件位置；不是整个注册表的备份。旧版本目录默认保留，正在运行的会话继续使用自己的版本文件。

## 五、<span id="verification">验证与验收</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

从根目录运行无第三方测试框架的回归：

```powershell
powershell.exe `
  -NoProfile `
  -ExecutionPolicy Bypass `
  -File .\Scripts\Sync-PackageInfrastructure.ps1

powershell.exe `
  -NoProfile `
  -ExecutionPolicy Bypass `
  -File .\Tests\Core.Tests.ps1

powershell.exe `
  -NoProfile `
  -ExecutionPolicy Bypass `
  -File .\Tests\Installer.Tests.ps1

powershell.exe `
  -NoProfile `
  -ExecutionPolicy Bypass `
  -File .\Tests\Worker.Tests.ps1

powershell.exe `
  -NoProfile `
  -ExecutionPolicy Bypass `
  -File .\Tests\PackageInstaller.Tests.ps1

powershell.exe `
  -NoProfile `
  -ExecutionPolicy Bypass `
  -File .\Tests\Architecture.Tests.ps1

powershell.exe `
  -NoProfile `
  -ExecutionPolicy Bypass `
  -File .\Tests\ActionModules.Tests.ps1
```

核心回归覆盖独立包的参数转义、路径处理、远程网页转换、进程树超时清理和临时真实 Git 工作树。总安装器回归核对逐包操作计划和失败停止；独立包安装器回归核对隔离注册、卸载、冲突保护、配置提交与事务回滚。架构回归将功能包单独复制到临时目录，检查包内容完整、功能业务归属和不依赖总目录的边界。业务模块回归覆盖各包独立导入与调用、项目门禁、Git 推送计划、暂存区保护及数据库只读检查，不运行真实安装入口或实际推送。仓库附带 Windows CI 配置，包含基础模板一致性检查及上述回归；但未推送触发，不能将其视为已通过的远程结果。

交付验证在 macOS 上通过便携 PowerShell 运行语法及可跨平台行为检查；**Windows 真实桌面的菜单显示、剪贴板、IDE、终端和注册表回归仍须在 Windows 验收**。推荐依次验证首次组合安装、取消配置、部分选择、单独复制一包安装、卸载一包而保留其他包、目录空白处、磁盘根目录、中文特殊路径、依赖缺失提示及旧版逐项迁移。

官方实现依据：[当前用户菜单注册](https://learn.microsoft.com/windows/win32/shell/context-menu-handlers)、[Windows 11 经典菜单兼容入口](https://blogs.windows.com/blog/2021/07/19/extending-the-context-menu-and-share-dialog-in-windows-11/)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

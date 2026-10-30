> 当前 `Manage.cmd` 转交同级 [JobsFlutterTools](../JobsFlutterTools/README.md) 安装统一菜单，不能只复制本旧目录新装；`Manage.cmd` 保留旧功能卸载。下文的原生 / 静态菜单实现、状态路径与业务命令是保留源码的说明，当前新安装以统一包及项目 FVM 为准。原“Flutter项目体检”在统一菜单称为“原生Flutter项目体检”。

# `JobsFlutterVersionMgr`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、前提与工具链](#jobs-toc-heading-2)
- [二、选择、安装与切换](#jobs-toc-heading-3)
- [三、安装与卸载入口](#jobs-toc-heading-4)
  - [安装 / 更新： Manage.cmd](#jobs-toc-heading-5)
  - [卸载： Manage.cmd](#jobs-toc-heading-6)
- [四、文件、日志与恢复](#jobs-toc-heading-7)
- [五、验证边界与依据](#jobs-toc-heading-8)

</details>
<!-- jobs-toc:end -->

---

**管理操作：** 本目录以 `Manage.cmd` 为轻量启动入口，只唤起 GUI 后结束本次脚本；先在面板选择安装 / 更新或卸载。在面板确认安装 / 更新或卸载后立即执行，无二次终端确认。关闭或取消面板不执行；卸载保留日志、备份、运行文件和工具。

## 🔥 <span id="前言">前言</span>

**最低支持系统：Windows 10 64 位（x64）。** 这是当前最低支持目标；具体最低 build 尚未锁定，完整实机兼容性仍待验证。最低基线不等于所有功能已经实测通过。

**右键功能：Flutter SDK 安装/切换（FVM）。** 对目标文件夹做 [**Flutter**](https://flutter.dev/) 项目校验，在可见的终端里体检工具链、查询官方历史及最新版本，通过 [**fzf**](https://github.com/junegunn/fzf) 单选后，为当前工程安装或切换指定的 [**FVM**](https://fvm.app/) Flutter SDK 版本。

**本目录 [`Manage.cmd`](./Manage.cmd) 需要同级完整 `JobsFlutterTools`，并转交统一菜单安装；单独复制旧目录不能新装。可直接复制统一包独立交付。[`Manage.cmd`](./Manage.cmd) 只卸载本旧功能。** 以下保留的 FVM 引导业务不需要现成 Flutter / Dart，当前统一入口另外受其项目 FVM 门禁约束。

| 操作 | 实际行为 |
| --- | --- |
| 右键 Flutter 项目文件夹 → Flutter SDK 安装/切换（FVM） | 严格检查同层 `pubspec.yaml` 的 `dependencies.flutter.sdk: flutter`，然后进入终端。 |
| 选择尚未缓存的具体版本 | 确认并备份后，通过 FVM 下载、初始化并绑定该 SDK。 |
| 选择已经初始化的缓存版本 | 通过 FVM 切换当前项目，不重复安装 SDK。 |
| 官方版本源不可用 | 仅列出已经初始化的本机 SDK，标注“离线（最新未知）”；无可用缓存则停止。 |
| fzf 中按 Esc，或最终确认输入任意字符后回车 | 取消，项目配置不写入；此前经单独确认安装的工具会保留。 |
| 最终确认直接回车 | 先备份，再为当前项目安装或切换已选版本，并复核实际 SDK。 |
| 右键普通目录、仅有 `flutter_test` 或描述文字的目录 | 终端立即拒绝，尚未调用工具体检、安装或 SDK 下载。 |

静态注册表菜单无法在弹出时解析项目文件，所以目录菜单可能显示在普通文件夹中；**只有通过运行时项目门禁的目录才会继续。Windows 11 请打开“显示更多选项”或按 `Shift+F10`。**

**系统兼容性：** 当前目标为 [**Windows**](https://www.microsoft.com/windows) 10 / 11 图形桌面，要求系统 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) 5.1 Desktop、.NET 与 STA；各系统版本和架构仍待实机验收，未锁定统一最低 build。XP / Vista / Windows 8 不支持当前入口；Windows 7 SP1 / 8.1 即使安装 [**WMF 5.1**](https://www.microsoft.com/en-us/download/details.aspx?id=54616)（要求 .NET Framework 4.5+），也只满足部分运行时前提；本包及当前原生菜单安装不在这两个旧系统的支持范围。Windows 11 使用“显示更多选项”或 `Shift+F10`；x86 / ARM64 均未获全功能实机兼容保证。

**当前入口与依赖：** `Manage.cmd` 转交同级 `JobsFlutterTools` 的统一菜单安装；只复制这个旧目录不能完成新安装，需保留同级完整 `JobsFlutterTools`，或直接复制统一包。`Manage.cmd` 仍用于移除本旧功能。统一包安装需要已有 C++ 桌面工作负载、MSVC / Windows SDK 与系统 .NET Framework C# 编译器；各 SDK / IDE / 生成器的实际系统要求另行满足，旧系统上菜单能显示不能证明业务可运行。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、前提与工具链</span><!-- jobs-toc:heading-end -->

运行环境为 [**Windows**](https://www.microsoft.com/windows) 10 / 11、系统 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) `5.1 Desktop`、系统 .NET 与交互桌面。支持 Windows x64 / ARM64。菜单安装仅写当前用户，不提权、不改永久执行策略。

| 层级 | 健康检查 | 缺失或损坏时 |
| --- | --- | --- |
| [**Git**](https://git-scm.com/) | 查找 PATH 和常见用户 / 系统目录，执行 `--version`。 | 检查 WinGet 后，回车确认安装 `Git.Git`，限定 `--scope user`，刷新当前进程 PATH 并二次复检。 |
| fzf | 执行 `--version`。 | 同样经 WinGet 安装 `junegunn.fzf` 并复检。 |
| FVM | 复用健康的 `fvm.exe` / Dart 安装的 `fvm.bat` / `fvm.cmd`，执行 `--version` 与 JSON API 体检。 | 查询官方 GitHub 最新 release，按 x64 / ARM64 选 ZIP，显示完整来源与 SHA-256；回车确认后下载、校验并安装到本包 `tools/`。 |
| [**WinGet / App Installer**](https://learn.microsoft.com/windows/package-manager/winget/) | 只在需要安装 Git / fzf 时执行 `winget --version`。 | 打开官方 Microsoft Store 的 App Installer 页面后停止；安装或更新后重新打开右键菜单。 |
| 符号链接能力 | 最终确认后，在临时目录检验 SDK 链接所需权限并精确清理。 | 给出 Windows“开发者模式”指导后停止；不自动修改设置或要求整套菜单以管理员运行。 |

每一层只修复缺失或损坏分支，健康组件直接复用；安装失败或二次体检失败就停止。已有 FVM 不支持所需 JSON API 时提示先修复或升级，不静默覆盖已有安装。Windows 使用原生工具链；不安装 macOS 的 Homebrew。

工具安装是单独确认步骤：**必需工具缺失时回车安装，任意字符取消整个流程。** WinGet 来源协议与软件包协议随明确安装命令接受；受企业软件策略或用户权限限制时保持失败，不切换到系统安装范围。已有健康 Git / fzf 时不要求 WinGet 存在。

FVM 独立包来自官方 [`btwld/fvm` release](https://github.com/btwld/fvm/releases)，同时兼容官方旧仓 `leoafarias/fvm` 的发布地址。缺少可验证的 GitHub asset SHA-256 digest、ZIP 路径越界或执行复检失败时停止。本包自己安装的 FVM 路径记录在 `tools/fvm-path.txt`，不写全局 PATH；后续终端命令使用脚本输出的 FVM 完整路径，或自行将该工具目录加入用户 PATH。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、选择、安装与切换</span><!-- jobs-toc:heading-end -->

- 仅检查所选文件夹本层的 `pubspec.yaml`，不递归扫描，也不向父目录借用工程条件。不要求先有 `lib/` 或本机 Flutter SDK，便于已有 Flutter 包和新拉取工程接入。
- 支持常见 block 映射、`flutter: {sdk: flutter}`、`dependencies: {flutter: {sdk: flutter}}`、引用键值和尾注释。注释、描述标量、`dev_dependencies.flutter_test`、嵌套伪装及重复关键键不计入。YAML 别名、标签或多行 flow 写法无法可靠解释时安全停止，提示先改成常见 block 写法。
- 查询 Flutter 官方 [`releases_windows.json`](https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json)，展示 stable / beta / dev 的具体历史版本、发布日期、各渠道最新版本、当前 `.fvmrc` 绑定及缓存是否就绪；master 浮动分支不列为具体版本。
- 在项目外建立本次私有体检目录，复制目标自身的当前/旧版配置（没有则写入空对象），屏蔽祖先配置后，通过 `fvm api context` 与 `fvm api list --compress --skip-size-calculation` 读取目标将采用的 FVM 实际缓存；尊重已有 FVM 缓存配置，不猜测固定缓存目录。项目 `cachePath`、`FVM_CACHE_PATH` 及最终有效缓存位置必须是绝对路径，相对路径会在工具安装前停止，要求先明确原缓存位置。只有 FVM 标为已初始化且 Flutter / Dart 可执行文件齐全的缓存才支持离线切换。
- fzf 内输入搜索，方向键选中，Enter 确认一项，Esc 取消；不继承可能执行其他命令的用户 `FZF_DEFAULT_OPTS` 或选项文件。
- 最终展示“原版本 → 新版本”、缓存状态、写入范围和下载来源。**这一步直接回车执行安装/切换；输入任意字符后回车取消，空格也算非空输入。**
- 复核项目与写入路径，再备份配置，在精确工程根创建或合并 `.fvmrc`。优先读取当前根 `.fvmrc`，缺失时从本层旧 `.fvm/fvm_config.json` 迁移（包括 flavors、缓存、源和 IDE 策略）；保留其他配置字段，设置 `flutter` 为具体版本，并设置 `updateMelosSettings: false`，避免影响祖先 `.fvmrc` 或 `melos.yaml`。
- 根配置建立后再次比较有效 FVM 缓存目录与 SDK 来源，若因原先继承父配置而变化则在 SDK 操作前停止，要求重新选版；已写配置可按备份恢复。缓存未就绪时执行 `fvm install <version> --skip-pub-get`；再执行 `fvm use <version> --skip-pub-get --skip-setup`。不设置全局版本，也不自动安装项目 pub 依赖。
- 补回上游 FVM 序列化时省略的原有扩展配置字段。成功后核对 `.fvmrc`、`.fvm/flutter_sdk` 链接及 `fvm flutter --version --machine` 的实际版本。任何一步失败就停止，不将部分完成报告为成功；窗口保留到回车关闭。

SDK 下载由 FVM 执行，其来源服从已有 FVM 配置。终端会显示实际 `flutterUrl` 与缓存位置；自定义源不会被改写为官方源。官方版本清单只决定可选择的版本，不代表 SDK 一定从同一域名下载。入口不配置或切换网络代理。

IDE 的 Flutter SDK 路径应设置为项目内 `.fvm/flutter_sdk`。普通 `flutter` 命令仍按系统 PATH 选择 SDK；后续使用 `fvm flutter ...`。建议把 `.fvmrc` 纳入版本管理，并确认 `.fvm/` 已忽略；脚本不会执行 Git 暂存、提交或推送。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、安装与卸载入口</span><!-- jobs-toc:heading-end -->

### <span id="jobs-toc-heading-5" data-jobs-toc="v2">安装 / 更新： [Manage.cmd](./Manage.cmd)</span><!-- jobs-toc:heading-end -->

> **目的：** 转交同级 JobsFlutterTools 安装统一菜单；下面的逐包事务步骤保留为旧实现说明。

- 从自身位置定位清单和源码，打印来源、独立安装目录与注册表范围。
- 本包管理面板的操作选择与执行确认后，只复制本包运行文件，逐文件核对 SHA-256。
- 备份本项菜单键和状态；归属冲突则停止，事务失败则回滚本项菜单与状态。
- 更新本项配置和开始菜单卸载入口，通知资源管理器；不安装工具或下载 SDK。

### <span id="jobs-toc-heading-6" data-jobs-toc="v2">卸载： [Manage.cmd](./Manage.cmd)</span><!-- jobs-toc:heading-end -->

> **目的：** 仅停用并移除本项菜单，保留工程和可追溯数据。

- 确认后备份本项注册表键与状态，再移除本项菜单及卸载快捷方式。
- 写入 `Enabled=false`，保留已部署源码、工具、运行日志、项目备份和 FVM SDK 缓存。
- 不影响其他包、项目 `.fvmrc` 或 SDK 链接；不卸载 Git / fzf / FVM。

注册范围为当前用户 `HKCU\Software\Classes` 下 Directory、Directory\Background、Drive 的 `shell\Jobs.WindowsExtension.flutter-version-manager`，不写 HKLM；单选运行，多选批处理不在支持范围内。`.cmd` 中 `-ExecutionPolicy Bypass` 仅作用于当前进程；企业策略仍然有效。

## <span id="jobs-toc-heading-7" data-jobs-toc="v2">四、文件、日志与恢复</span><!-- jobs-toc:heading-end -->

```text
JobsFlutterVersionMgr/
├── Extension.json              本包身份及菜单属性
├── Manage.cmd                  安装 / 更新与卸载管理
├── README.md
└── Scripts/
    ├── README.md               内部脚本职责与调用边界
    ├── Manage.ps1              本包管理入口
    ├── PackageInstaller.psm1   注册、备份、回滚和独立状态
    ├── Common.psm1             随包内嵌的通用基础机制
    ├── Invoke.ps1              可见终端运行入口
    └── Action.psm1             项目、工具链、选版与切换实现
```

本包在当前用户本地应用数据的 `Jobs\WindowsExtension\extensions\flutter-version-manager` 下独立保存 `settings.json`、`releases/`、`logs/`、`tools/`、`backups/`。安装管理日志按日期保存；业务每个进程使用独立 `fvm-日期时间-随机ID.log`，包含脱敏来源、工具路径、操作和结果；终端显示项目备份精确位置。SDK 安装原生进度在终端显示，未逐字收录为日志。选版期间 `pubspec.yaml` 或 `.fvmrc` 若被其他工具修改，本轮会在项目写入前停止，须重新选版。

写入前备份 `.fvmrc`、`.gitignore`、`.vscode/settings.json`、根 `*.code-workspace` 及 `.fvm/` 中普通文件；`snapshot.json` 记录原本缺失的条目和链接目标，SDK 链接不遍历、不复制缓存。备份保存在项目外，并核对普通文件 SHA-256。失败时先查看项目差异，按快照将必要配置从 `files/` 恢复；原本不存在的条目应在确认后仅移除新增部分，SDK 链接按快照重建。不会自动回滚或删除已经下载的 SDK，以便保留失败现场。

目标及祖先目录、`.fvm/`、`.vscode/` 必须是普通目录，配置必须是普通文件；拒绝这些位置的符号链接、目录联接或其他重解析路径。`.fvm/` 内既有 SDK 链接属于正常 FVM 结构，只记录目标，不跟随备份。

## <span id="jobs-toc-heading-8" data-jobs-toc="v2">五、验证边界与依据</span><!-- jobs-toc:heading-end -->

仓库 [`FlutterVersionMgr.Tests.ps1`](../Tests/FlutterVersionMgr.Tests.ps1) 使用临时文件和受控工具夹具，覆盖项目识别、历史 / 最新标识、离线缓存、取消不写项目、原有配置保留、精确备份、父项目保护及切换后的版本复核。配套架构回归将本包独立复制后检查安装内容和注册命令，全部测试不安装真实工具或 SDK。

已完成 macOS 便携 PowerShell 的语法及隔离夹具检查；**Windows PowerShell 5.1 实际桌面、注册表菜单、fzf 终端键盘、WinGet 安装、ARM64、开发者模式权限及真实 SDK 安装 / 切换仍须在 Windows 验收。** 普通开发验证不运行真实安装入口、注册菜单或访问业务项目。

一手依据：[FVM 安装](https://fvm.app/documentation/getting-started/installation)、[FVM 命令与跳过依赖选项](https://fvm.app/documentation/guides/basic-commands)、[FVM JSON API](https://fvm.app/documentation/advanced/json-api)、[fzf Windows 安装](https://github.com/junegunn/fzf#windows-packages)、[Flutter SDK 归档](https://docs.flutter.dev/install/archive)、[WinGet](https://learn.microsoft.com/windows/package-manager/winget/)。

管理安装 / 卸载时双击 `Manage.cmd`，它只通过 WScript 唤起 GUI，随后立即结束本次脚本；不在 CMD 中编译、安装或等待输入。也可直接双击 `Manage.vbs` 进入同一面板。每个选项显示等待、执行中、完成或失败，底部实时滚动标准输出和错误，可选中复制或点击“复制全部日志”；无可靠百分比时显示执行中，总体显示完成项数。运行期间等当前事务结束后关闭，完整管理日志位于系统临时目录 `JobsExtensionManager-<运行编号>.log`。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

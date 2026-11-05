> 当前 `Manage.cmd` 转交同级 [JobsFlutterTools](../JobsFlutterTools/README.md) 安装统一菜单，不能只复制本旧目录新装；`Manage.cmd` 保留旧功能卸载。下文的原生 / 静态菜单实现、状态路径与业务命令是保留源码的说明，当前新安装以统一包及项目 FVM 为准。原“Flutter项目体检”在统一菜单称为“原生Flutter项目体检”。

# `JobsFlutterSdkInspector`

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

**右键功能：查看当前 Flutter SDK 版本。** 在经过校验的 [**Flutter**](https://flutter.dev/) 工程目录上查询当前实际使用的 Flutter SDK 版本：项目由 [**FVM**](https://fvm.app) 管理且已链接 SDK 时显示 FVM 版本；没有 FVM 或 SDK 未链接时显示系统 SDK 环境。结果与 `environment` 约束逐项核对，全程日志输出在 CMD 窗口。

这是保留旧业务与卸载能力的 [**Windows**](https://www.microsoft.com/windows) 源码目录。**新安装必须带同级完整 `JobsFlutterTools`，或直接复制统一包；本目录 [`Manage.cmd`](./Manage.cmd) 转交统一安装，[`Manage.cmd`](./Manage.cmd) 只卸载本旧功能。**

| 操作 | 结果 |
| --- | --- |
| 右键包含 `pubspec.yaml` 的 Flutter 工程 → 查看当前 Flutter SDK 版本 | 严格校验后，在 CMD 中只读显示 SDK 来源、Flutter / Dart 版本与约束核对结论 |
| 运行包内 `Manage.cmd` | 转交同级 JobsFlutterTools 安装统一菜单；旧目录不能单独新装。 |
| 在 `Manage.cmd` 选择“卸载” | 仅移除本包菜单，保留其他包 |

**系统兼容性：** 当前目标为 [**Windows**](https://www.microsoft.com/windows) 10 / 11 图形桌面，要求系统 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) 5.1 Desktop、.NET 与 STA；各系统版本和架构仍待实机验收，未锁定统一最低 build。XP / Vista / Windows 8 不支持当前入口；Windows 7 SP1 / 8.1 即使安装 [**WMF 5.1**](https://www.microsoft.com/en-us/download/details.aspx?id=54616)（要求 .NET Framework 4.5+），也只满足部分运行时前提；本包及当前原生菜单安装不在这两个旧系统的支持范围。Windows 11 使用“显示更多选项”或 `Shift+F10`；x86 / ARM64 均未获全功能实机兼容保证。

**当前入口与依赖：** `Manage.cmd` 转交同级 `JobsFlutterTools` 的统一菜单安装；只复制这个旧目录不能完成新安装，需保留同级完整 `JobsFlutterTools`，或直接复制统一包。`Manage.cmd` 仍用于移除本旧功能。统一包安装需要已有 C++ 桌面工作负载、MSVC / Windows SDK 与系统 .NET Framework C# 编译器；各 SDK / IDE / 生成器的实际系统要求另行满足，旧系统上菜单能显示不能证明业务可运行。


**面板外观与语言：** 总面板和独立功能面板右上角均可选择“黑夜 / 白天 / 跟随系统”以及“简体中文 / 繁體中文 / English / 跟随系统”，默认均跟随系统，切换立即生效并保留当前勾选、任务和日志。窄窗或长文案放不下时，工具组移至标题下一行并保持右对齐；极窄窗口将主题、语言分两行，下拉控件右边缘对齐。选择保存在当前用户的 `%LOCALAPPDATA%\Jobs\WindowsExtension\panel-preferences.json`，下次打开自动恢复；保存失败在面板显示原因。跟随系统每秒检查应用主题和当前用户显示语言，繁体中文界面使用繁体、其它中文使用简体，未支持语言回退英文；Windows 显示语言通常须重新登录才生效。切换只影响管理面板，已安装右键菜单标题及后台工具的原始日志保持各自语言。

**两种部署路线：** 源码管理面板默认使用“默认程序安装位置”，运行文件仍位于 `%LOCALAPPDATA%\Jobs\WindowsExtension\extensions\<功能ID>`。也可切换到“本地临时构建目录”，运行文件位于 `<功能包>\work\WindowsExtension\extensions\<功能ID>`；移走或清除该运行目录会使菜单失效。已部署副本的管理入口固定到自身真实路线，切换路线请从源码管理入口操作。菜单命令与 `deployment.json` 按当前路线定位配置，不依赖面板环境变量；提交失败恢复两侧状态。

**构建产物清理：** 安装位置选择、显示中的自动清理复选框与红色“🧹 清除构建产物”按钮排在同一行，垂直居中、间隔统一。英文或窄窗空间不足时，该行可水平滚动，文字保持完整，不拆成两行。仅默认安装位置路线显示默认关闭的“安装成功后清除此轮构建产物”和红底白字的“🧹 清除构建产物”独立按钮。自动清理仅处理本次成功安装产生的编译 GUID 子目录；独立按钮按当前选择清理本包 `work\JobsExtensionBuild` 专用编译工作区，不需要重新安装。临时路线隐藏清理控件。清理验证运行文件、标记与路径边界并持有事务锁，保留已经安装的 `.exe`、`.dll`、`.cmd`、`.ps1`、配置和注册表；自动清理失败明确显示“安装成功，清理失败”，独立清理失败正常报错。

**停止安装：** 安装进行中原按钮变为“停止安装”。点击只写停止请求，等待当前包事务完整结束，再把后续包标记为“未执行”；不强杀安装器、编译进程或资源管理器，未执行项不计失败或完成百分比。完成后可在同一面板继续清理、重试或关闭。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、适用范围与前提 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 系统为 Windows 10 / 11，系统自带的 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) `5.1` Desktop、系统 .NET 与图形桌面可用。
- 仅文件夹及文件夹空白处；静态菜单对所有文件夹显示（资源管理器静态动词无法按目录内容过滤），点击时再次严格校验工程条件，不满足时以明确原因退出。
- 复用项目已有 `.fvm\flutter_sdk` 或 PATH 中健康的 Flutter SDK，不主动安装 / 切换 SDK；首次调用 Flutter 仍可能下载同版本 Dart / 工具缓存，并显示进度。
- 菜单按单选设计，多选批量操作不在支持范围内。**Windows 11 需要进入“显示更多选项”或使用 `Shift+F10` 打开经典菜单。**
- 安装作用于当前用户，不需要管理员权限；不修改系统菜单样式、默认关联或永久执行策略。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、安装与卸载 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

### <span id="jobs-toc-heading-4" data-jobs-toc="v2">安装 / 更新： [Manage.cmd](./Manage.cmd)</span><!-- jobs-toc:heading-end -->

> **目的：** 将安装请求转交同级 JobsFlutterTools；下面保留的逐包安装事务说明适用于旧实现。

- 打印脚本来源、包身份、目标目录与注册表范围，确认后部署本包。
- 复制本包运行文件到独立版本目录，逐文件核对 SHA-256，备份本包菜单注册；安装前对 `.ps1` / `.psm1` 做 PowerShell 语法解析检查，语法错误直接拦截。
- 只写本包菜单和配置；遇到同名但无本工具归属标记的注册表键则停止。
- 本包提交失败时回滚本包菜单与配置；完成后重新右键查看，不强制重启资源管理器。

### <span id="jobs-toc-heading-5" data-jobs-toc="v2">卸载： [Manage.cmd](./Manage.cmd)</span><!-- jobs-toc:heading-end -->

> **目的：** 只移除“查看当前 Flutter SDK 版本”，保留可追溯数据。

- 确认后备份本包注册，移除本包菜单和开始菜单卸载快捷方式。
- 保留 `settings.json` 并写入 `Enabled=false`，避免兼容配置重新启用本项。
- 保留本包运行版本、日志、备份和私有工具；不删除其他软件，也不停止其他会话。
- 需要彻底清理时，先等待本包会话退出，再手动清理本包部署目录。

入口从自身位置查找脚本，不依赖启动目录。`-ExecutionPolicy Bypass` 仅作用于本次进程。企业执行策略或应用控制仍可能限制未签名脚本，应遵循设备管理策略。

## <span id="jobs-toc-heading-6" data-jobs-toc="v2">三、功能行为与风险 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 目标同层必须有 `pubspec.yaml` 且真实声明 `dependencies.flutter.sdk: flutter`（保守 YAML 解析，与 `JobsFlutterVersionMgr` 同源实现）；不递归寻找其他工程，纯 Dart / `flutter_test` / 注释不算 Flutter 项目。
- 目标及父目录必须为普通目录；拒绝符号链接、目录联接和其他重解析目录。
- **查询范围**：不主动安装 / 切换 SDK，不修改项目配置；执行现有 SDK 时可能联网补齐 Dart / 工具缓存并显示进度。版本命令是 `flutter --version --machine`（300 秒超时，超时终止本次进程树）。
- SDK 来源判定顺序：项目 `.fvm\flutter_sdk\bin\flutter.bat` → PATH 中 `flutter.bat` → `%USERPROFILE%\fvm\default\bin\flutter.bat`。
- 版本结论只采信实际执行的 `--version --machine` JSON；与 `.fvmrc` 配置版本、`environment.sdk` / `environment.flutter` 约束逐项核对，无法可靠判定的约束写法输出“未知”，不假装满足。`^0.2.3` 按 [**Dart**](https://dart.dev/tools/pub/dependencies#caret-syntax) 规则表示 `>=0.2.3 <0.3.0`；`environment` 的 `sdk` / `flutter` 重复声明时跳过核对。

## <span id="jobs-toc-heading-7" data-jobs-toc="v2">四、目录与状态 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

```text
JobsFlutterSdkInspector/
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

旧业务运行文件与卸载器保留在包内；当前新安装还必须有同级 `JobsFlutterTools`，不能移走它后继续使用本目录的 `Manage.cmd`。

状态位于当前用户本地应用数据的 `Jobs\WindowsExtension\extensions\flutter-sdk-inspector` 中；`settings.json` 保存 `Version: 2`、`Enabled` 和 `ReleasePath`。`releases/`、`logs/`、`backups/` 分别保存本包运行版本、日志和菜单快照；实际日志及备份位置由运行入口打印。菜单直接运行本包业务，不使用总目录的集中请求队列。

注册表范围限于当前用户 `HKCU\Software\Classes` 下的 `shell\Jobs.WindowsExtension.flutter-sdk-inspector` 菜单键，不写 `HKLM`。适用对象由本包 `Extension.json` 的 `DirectoryOnly` 控制。

## <span id="jobs-toc-heading-8" data-jobs-toc="v2">五、排查与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

本包在 macOS PowerShell `7.6.7` 下运行[专项夹具测试](../Tests/FlutterSdkInspector.Tests.ps1)，72 项断言通过；覆盖项目识别、FVM / 系统 SDK 选择、版本约束边界、重复配置、符号链接拒绝与查询前后项目文件 SHA-256 不变，真实 Flutter 调用由夹具模拟。基础脚本与既有各包逐字节一致，`Action.psm1` 带 UTF-8 BOM（PS 5.1 中文必需）；语法解析与组合清单另由总回归校验。**源码检查不能代替 Windows 真实桌面验收**，应在 Windows 上完成：

1、双击 `Manage.cmd`（安装前的 PowerShell 语法闸门会拦截语法错误）；
2、右键 FVM 管理的 Flutter 项目 → 菜单出现 → 点击后 CMD 显示 FVM 来源与版本；
3、右键无 FVM 的 Flutter 项目 → 显示系统 SDK 来源与版本；
4、右键普通文件夹点击菜单 → 被严格校验拒绝并说明原因；
5、只卸载本包后其他功能仍可用。

菜单可见但校验失败时，核对目标同层的工程文件与 Flutter 声明。SDK 缺失时先安装官方 SDK 或用 FVM 安装版本；本扩展不自动下载。菜单未出现时，重新右键并检查 Windows 11 经典菜单入口，再查看本包安装日志。

管理安装 / 卸载时双击 `Manage.cmd`，它只通过 WScript 唤起 GUI，随后立即结束本次脚本；不在 CMD 中编译、安装或等待输入。也可直接双击 `Manage.vbs` 进入同一面板。每个选项显示等待、执行中、完成或失败，底部实时滚动标准输出和错误，可选中复制或点击“复制全部日志”；无可靠百分比时显示执行中，总体显示完成项数。运行期间等当前事务结束后关闭，完整管理日志位于系统临时目录 `JobsExtensionManager-<运行编号>.log`。

**SDK 版本查询进度：** 随包 `SdkDownloadOutput.ps1` 实时显示启动准备与下载过程，机器 JSON 独立保留供版本解析；URL / 认证字段继续脱敏。仅复用现有 SDK，缺失的项目绑定仍交由安装 / 切换入口处理。

**SDK 环境准备：** 已选择的 SDK／版本所需下载、安装及首次 Flutter／Dart 缓存补齐自动执行；网络失败或无进度超时后持续重试，间隔逐步增加并封顶 30 秒，没有次数和总时长上限，直到成功或本人 Ctrl+C／停止。仍在输出下载进度的传输不按总时长截断；成功后才进入后续业务。目标／版本选择、官方许可证与系统权限仍由本人处理；路径、权限、磁盘或明确不存在的版本会报告具体原因。每次尝试和真实进度追加到终端所示日志；同一 URL 有 ETag／Last-Modified 时安全续传，跨来源保留独立临时文件，不拼接不同来源。失败／取消保留下载现场；业务构建和配置写入不因网络重试而整体重放。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

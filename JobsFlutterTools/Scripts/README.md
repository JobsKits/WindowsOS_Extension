# Flutter 菜单实现

完整说明见 [README](../README.md)。

当前 36 项白名单保留逐项开关：联网拉取 4 项、本地提取 7 项、本地导入 7 项、运行环境 3 项、资源与构建依赖 3 项、体检 3 项、根层日常操作 6 项、外层修复 3 项。`ContextMenu.cpp` 在开发辅助内直属“拉取Flutter项目工程相关依赖”“提取Flutter项目工程依赖”“导入Flutter项目工程依赖”“安装/切换Flutter运行环境”“Flutter 资源与构建依赖”和体检组，空组隐藏；修复保持一级组。`native-dependencies` 在“Flutter 资源与构建依赖”组内显示“准备原生库与构建依赖（组合操作）”，`sdk-version` 位于体检首项。Pub 源码与平台快照保持各自格式，export / import 分别放进提取 / 导入组。菜单完整树和逐组 ID 见[固定菜单结构](../README.md#固定菜单结构)。`ContextMenu.cpp` / `FlutterToolsMenu.h` 固定菜单层级和动作顺序；`OpenCmd.ps1` / `Invoke.ps1` / `Action.psm1` 传递所选工程与固定动作。共享 Dart 引擎处理体检、URI / namespace 修复与维护。`Actions/` 自包含已有功能 worker；常规 worker 的 FVM 校验失败不会回退全局 Flutter；依赖动作在显式确认后允许进入既有 SDK 准备并复检。安装事务仅迁移本仓库固定旧 Flutter 入口。

`FeatureActions.psm1` 列出全部 36 项叶动作（2026-10-30，按 `Get-JobsFlutterActionCatalog` 与 `FlutterToolsMenu.h` 可执行动作去重计数）、显示名称及分组，并校验 `ActionIds` 数组。总面板用 `flutter-<动作>` 标识逐项选择，部署时合并为单个包操作，安装状态保存原始动作名。安装器在同一备份 / 回滚事务内原子发布包根 UTF-8 `menu-state.txt`（版本、当前 release、动作白名单，各行 LF，无 BOM），原生菜单每次读取当前指针，仅显示已选动作并隐藏空组，点击派发当前 release；卸载写空动作墓碑。release 根另存 ASCII `menu-actions.txt` 作为兼容文件。`Invoke.ps1` 再复核选择及当前 release。旧设置缺少 `ActionIds` 时兼容全部现有动作，畸形配置停止。管理面板默认空选，安装只增加本次选择，卸载只移除所选叶；部分卸载重新部署剩余动作，最后一项移除时才注销整个包。首次从旧 DLL 升级，或原生动作表增加新动作时，仍需用户重启 Explorer 或注销以载入新 DLL；仅切换当前 DLL 已认识的动作时可通过稳定指针生效。

`HarmonySdk.psm1` 实现独立 `ohos-sdk-manage` 动作：CPF-Flutter tag 单选、commit 锁定、私有缓存、影子 FVM 体检及项目配置/链接发布。复用 `Actions/sdk-manage` 的 Git/FVM/fzf 健康检查和命令参数传递；真实项目仅发布 `.fvmrc` 和 `.fvm/flutter_sdk`，IDE、ignore 与源码保持原样，失败恢复及缓存范围见上级说明。`CheckHarmonySdk.ps1 -Target <项目根>` 只读展示计划，不联网、不运行工具、不写缓存。原生 SDK 选版仍由已有 `sdk-manage` worker 承接。

统一入口的 `sdk-manage` 分支可识别本工具管理的 CPF 绑定，由同一模块在影子项目完成 OpenHarmony → 官方原生 SDK 的切换，明确改用独立 `official` 缓存；其它情况继续调用原生 worker，未知 fork 和非官方有效来源在下载前拒绝。没有新增顶层扩展或跨包运行依赖。

[SelectionPanel.psm1](./SelectionPanel.psm1) 是随包管理面板，与总面板 `Scripts/Installer.psm1` 保持同字节，独立包可逐项安装或卸载 34 个叶动作，不依赖父目录。取消、空选、切换操作不写状态；面板安装 / 更新与卸载按钮是本次菜单管理的最终确认，后台不另等终端输入。业务快照导入仍保留自己的精确 `YES` 门禁。

`Actions/import-dependencies/Scripts/` 提供[依赖导入](./Actions/import-dependencies/Scripts/README.md)：CMD 输入或拖入完整导出目录，初筛后由同目录 Dart 核心完整校验，显示计划并要求精确 `YES` 才写入；原源码复制到项目独立 vendor 目录，先备份再增量配置 overrides。release 必须携带 `Action.psm1`、`Common.psm1`、`ImportFlutterDependencies.dart` 和其复用的 `ExtractFlutterDependencies.dart`，不依赖兄弟安装包或外部源码路径。

本目录的 `Manage.ps1`、`SelectionPanel.psm1` 和 `ManagementWorker.ps1` 构成本包自包含管理面板；由上级 `Manage.vbs` 无控制台启动。安装 / 卸载在隐藏后台执行，逐项状态与可复制实时日志留在面板中。总进度按已处理项 / 本次所选项显示计数和百分比；成功与失败计入已处理，等待中、执行中和未执行项不计入，100% 表示全部处理完毕，结果以成功 / 失败汇总为准。安装 / 更新和卸载分别计时；点击时只清零并启动当前操作计时，后台全部结束或启动失败时只冻结当前耗时。每秒刷新 `HH:mm:ss`（小时可超过 24），执行时显示“安装用时 / 卸载用时”，结束显示“安装总用时 / 卸载总用时”。两份耗时只在当前面板会话内独立保留。安装成功显示绿色“✅ 安装成功”。不改变右键业务工具自己的交互方式。失败状态可点击，在独立 PowerShell 中只读显示本次完整会话日志；包失败不阻止其它所选包，日志不可用时在面板提示。

`build-harmony` 是合法 Flutter 根目录始终可见的已选独立叶动作；`FlutterToolsMenu.h` 与 `FeatureActions.psm1` 同步标识和名称。菜单生成不以 `ohos/` 是否存在过滤入口，原生点击与 PowerShell worker 仍复核普通非链接的 `lib/`、`ohos/` 和两份工程配置；缺少时提示先适配并停止。`Action.psm1` 直接调用同包 `Actions/package` 内的 `Invoke-JobsFlutterHarmonyAction`，固定项目 FVM、release、HAP + APP，不弹二级产物选择。两种构建和产物验证通过才成功；完整依赖、确认、日志与部署步骤见[上级说明](../README.md#鸿蒙-hap--app-打包)。

[ProjectSetup.psm1](./ProjectSetup.psm1) 处理 `project-setup`、`gradle-download`、`java-manage`，在常规 FVM 门禁之前分发。流程支持 fzf 的 FVM / 系统 Flutter、Windows 原生 jEnv / 系统 Java，官方 SDK 校验、Wrapper 原版本兼容检查与标准缓存预填、Pub / 构建插件解析和只读运行前诊断。下载、镜像、备份、取消、环境恢复与部署说明见[上级一键配置说明](../README.md#一键配置与-gradle-插件下载)。已有业务 worker 仍使用工程 FVM，不能把本机环境 JSON 当成所有旧动作已支持系统模式。

`ProjectSetupDashboard.ps1` / `ProjectSetupWorker.ps1` 为运行仪表盘与真实控制台承接；`ProjectSetupProgress.psm1` 只传递真实阶段事件，`ProjectSetupProcess.cs` 在 CLR 原生线程实时排空 stdout / stderr 并保存原始文本，避免 PowerShell 事件处理器缺少 runspace。`ProjectSetupRun.ps1` 由同模块加载，复用本包 Android 核心，处理 Android / Windows / Web 平台补齐、设备空态、AVD、启动参数和本次 appId 的 `app.started` 门禁。发布时上述文件、`ProjectSetupLogTail.psm1` 和版本单源 `SetupVersion.json` 必须与 `ProjectSetup.psm1`、原有 `Actions/` 一同复制；不得依赖外部 JobsGenesis 绝对路径。Windows 的 SetParent / DPI / conhost 交互需要单独原生验证。

`ProjectSetupLogTail.psm1` 为独立终端回退视图提供持久 UTF8 Decoder、字节 offset、128 KiB 单轮读取预算和约 20 万字符显示尾部；只读日志，完整原始文件保留。Dashboard 在 reparent 前拒绝不可见、最小化或零客户区 HWND，不能只凭 SetParent 成功就隐藏回退视图。

`SetupVersion.json` 提供工具语义版本和 build；阶段事件的可选 `version` 保存真实工具版本，UI 独立小字与 tooltip 显示。`ProjectSetupDashboard.ps1` 以水平 `SplitContainer` 拖动调整里程碑 / 原生终端高度，组间使用 ASCII `>>>>>`。版本和尺寸协议见 `Tests/FlutterProjectSetupVersion.Tests.ps1`。

[ProjectDependencies.ps1](./ProjectDependencies.ps1) 由 `ProjectSetup.psm1` 随包加载，统一实现 `pub-get` 与五个独立依赖动作：`android-dependencies`、`ohos-dependencies`、`native-dependencies`、`flutter-precache`、`web-dependencies`。`Action.psm1` 在旧 FVM 门禁之前分发这些动作；`Invoke.ps1 -Check` 仅输出计划，完全不运行 SDK / 选择器或联网写文件。完整参数、锁文件、确认、副作用与平台边界见[分层依赖准备](../README.md#分层依赖准备)。旧 Pub worker 的公开入口也委托同一内核，保持纯 Pub 语义。

`flutter-precache` / `native-dependencies` 的 CMD 首屏在首次确认前按“一行一个要点 + 子项缩进”展示实际命令、资源例子和组合操作范围，不提前下载；具体内容见 [FAQ](../README.md#dependency-faq)。

Android 使用临时 Gradle init task 对 `canBeResolved` 的项目和 buildscript configurations 调用 `resolve()`，实际检查 artifact 文件并要求本次完成标记；无法解析即失败，不采用 lenient 模式。OHOS 要求项目 wrapper 的 `--sync` 能力与 `hvigor/hvigor-config.json5`，使用现有 DevEco 工具的 ohpm，不安装任意全局 npm 包。Web 按工程锁文件及 `packageManager` 选择健康包管理器，不调用 Flutter。`native-dependencies` 通过 `Get-JobsSetupRunArguments -ForBuild` 形成 debug 构建计划，并先检查 SDK `build <目标> --help`；一键配置将相同计划传给最终 `run`，保留入口 / flavor / dart-define。

发布目录需同时携带 `ProjectDependencies.ps1`、`ProjectSetup.psm1`、`ProjectSetupRun.ps1`、`HarmonySdk.psm1` 与已有 `Actions/`；`PackageInstaller.psm1` 按本包直属脚本和 worker 递归清单复制，不借用兄弟安装包。隔离回归见 `Tests/FlutterProjectDependencies.Tests.ps1`；一键配置原始输出、版本事件及真实 `app.started` 门禁沿既有测试覆盖，Windows 原生安装 / GUI / 实际下载和构建另验。

[ProjectDependencyArchive.ps1](./ProjectDependencyArchive.ps1) 与 [NativeDependencyArchive.dart](./NativeDependencyArchive.dart) 为原生层配对归档内核。前者沿 `ProjectSetup` 导出 `Invoke-JobsProjectDependencyArchiveAction`，使用 `export/import-{gradle,ohos,native,precache,web}-dependencies` 动作；动态定位并验证 Dart，选择缓存组件及源 / 目标根，先以引擎 `--check` 完整预检，再按导入大写 `YES` 门禁执行。Dart 用 `--project --kind --platform --tool-version --directory --source-root/--target-root` 接收明确数据，不回读快照开发机路径。`--directory` 在提取时是输出父目录，导入时是完整快照目录；引擎导入另需 `--confirm YES`，执行前再次校验。

Gradle 在 `modules-2` 与项目固定 Wrapper 分发间选择，OHPM / Hvigor 分开；native 仅当前目标 `build` 子目录，precache 仅 SDK artifacts，JS 仅清单旁 node_modules。根目录类型校验、同宿主 / 版本 / 锁指纹、逐文件证据、同名不同内容拒绝及不执行归档脚本的边界见[配对归档说明](../README.md#原生依赖的配对提取与导入)。Pub 源码提取 / 导入保持原独立格式和语义。`PackageInstaller` 必须随直属脚本复制此 wrapper 与 Dart 引擎；`Tests/FlutterDependencyArchiveShell.Tests.ps1` 验证确认、失败传播、源根限制及环境恢复，Dart 引擎另外验证真实归档数据。

私库配对动作通过 `Action.psm1` 将 `-PrivateOnly` 转给现有 extract/import worker，再传递 Dart 的 `--private-only`。新动作追加在 catalog 末尾，保留旧原生命令 offset；实际菜单把私库项放在 Pub 项之后。

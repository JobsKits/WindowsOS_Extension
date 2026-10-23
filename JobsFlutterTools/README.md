# Flutter 开发、体检、修复与维护

`JobsFlutterTools` 是 Flutter 工程右键菜单的统一入口。只有同层 `pubspec.yaml` 声明 Flutter SDK 的工程文件夹才展示菜单；支持选中文件夹或工程内空白处。菜单由单个扩展创建，子菜单顺序固定，不再由多个独立扩展竞争排列。其他软件提供的菜单相对于本组的位置由操作系统决定。

## 固定菜单结构

```text
Flutter开发相关辅助工具
├─ 运行Flutter项目
├─ 拉取Flutter第三方依赖
├─ 提取Flutter第三方依赖
├─ 查看当前Flutter项目的SDK版本
├─ 安装/切换Flutter SDK版本
├─ 安装/切换 Flutter@OpenHarmony SDK
├─ Flutter打包
├─ Flutter自动化生产代码
├─ Flutter项目体检
│  ├─ 原生Flutter项目体检
│  └─ 鸿蒙Flutter环境体检
└─ Flutter清理维护工具
Flutter项目修复
├─ 修复 Android SDK / platforms 缺失
├─ 修复 Flutter 项目中文路径
└─ 修复 Flutter 插件 namespace
```

后续 Flutter 动作应增加到本包的固定动作表和对应分组，不再新增独立的顶层扩展。修复组也是一级菜单，其顺序固定在开发辅助组之后。

## FVM 与体检

执行入口要求项目 `.fvmrc`（或旧 `.fvm/fvm_config.json`）及 `.fvm/flutter_sdk`。缺失时提示先安装/切换项目版本，不会调用全局 Flutter。原生 SDK 安装/切换沿用 FVM 管理流程；不执行 `fvm global`、不把 Flutter 写入全局 PATH 或 Shell 配置。检查、修复及维护引擎使用该 SDK 内的 Dart 3+，无需额外安装 Dart 包。

原生体检检查 FVM、Flutter 版本声明与实际版本、同源 Dart 及 `flutter doctor -v`。基础 doctor 的警告、错误或无法判定的输出都不能算健康。

Harmony 体检先检查同一套 **FVM 管理的 Harmony Flutter SDK 的基础环境**，再检查 `hap` 构建能力、DevEco/CLT、Node、OHPM、Hvigor、HDC、Java、SDK 编译组件、项目 `ohos/` 结构及已解析原生插件的 `ohos` 声明。只有全部通过才报告健康；不会仅凭模拟器已启动就报告项目可运行。静态插件声明检查不能代替实际构建，联邦插件的替代实现需按失败列表核对。

Harmony Flutter 是适配分支，普通 Flutter 安装并不会自动带来 Harmony 构建能力。“安装/切换 Flutter@OpenHarmony SDK”从 [CPF-Flutter 适配仓库](https://gitcode.com/CPF-Flutter/flutter_flutter) 读取带 `ohos` 的正式或预发布 tag（兼容 `v` 前缀），稳定 tag 优先、同组按基础版本倒序，以 fzf 单选；Esc 取消，最终回车执行、任意非空输入取消。显示完整来源、tag、不可变 commit 和缓存位置，不默认安装浮动最新版。原生 SDK 选择器仍使用原生 Flutter 发布清单。

OpenHarmony SDK 下载到当前用户本地应用数据中的 `JobsFlutter/fvm/harmony/versions/custom_jobs_ohos_<commit>`，仅复用来源、commit 及源码状态相符的缓存；冲突目录和已有源码改动会阻断，不覆盖。克隆使用完整 Git 历史，所选 tag 在选择期间改变、与分支同名或缺少 `build hap` 能力时停止。缺 Git/FVM/fzf 时沿用原生选版入口的健康检查与分别确认安装；FVM 独立 ZIP 核对官方 SHA-256。

FVM 在私有影子项目中执行 `use custom_jobs_ohos_<commit> --skip-setup --skip-pub-get`，初始化并检查实际 Flutter commit、`build hap --help`，随后才发布真实项目的 `.fvmrc` 与 `.fvm/flutter_sdk` 绝对目录联接。保留已有额外配置、flavors、IDE、ignore、源码与其它 `.fvm` 元数据，不运行 pub get、不生成 `ohos/`、不安装 DevEco、不运行打包。`.fvmrc` 的 `cachePath` / `flutterUrl` 指向所选隔离缓存与适配来源；使用其它 flavors 前也要核对其版本是否在该来源可用。不会设置 FVM 全局 fork 或 global，不改用户/系统 PATH、`JAVA_HOME` 或全局 Flutter 配置。

发布前复查项目指纹；旧 `.fvmrc` 与链接目标写入本包 `backups/openharmony-*`，发布失败只在文件与链接仍是本次预期内容时恢复，发现并发改动则保留原链接与快照等待人工核对。失败下载目录保留便于诊断，不删除既有 SDK。所有临时 FVM 环境变量在结束时恢复。只读计划入口如下，不联网、不运行 Git/FVM/Flutter、不创建缓存；计划通过不代表实际构建环境健康：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\Scripts\CheckHarmonySdk.ps1 `
  -Target 'D:\Projects\MyFlutterApp'
```

SDK 安装/切换完成后使用“鸿蒙 Flutter 环境体检”核对 DevEco/CLT、插件与项目适配，真实签名和 HAP 构建另验。多套 DevEco/CLT 并存时通过本次终端的 `TOOL_HOME` 或 `DEVECO_STUDIO_HOME` 指定。Java 安装/切换菜单目前仅在 macOS 提供，本 Windows 入口不安装或切换 Java。

需要切回原生 SDK 时，使用相邻的“安装/切换Flutter SDK版本”。仅当当前绑定符合本工具的 CPF 来源、`custom_jobs_ohos_<commit>` 与隔离 `harmony` 缓存约定时，进入专用反向流程：在影子项目选择官方 Flutter 版本，明确使用 `https://github.com/flutter/flutter.git` 和同级独立 `official` 缓存，安装、实际版本及来源核验通过后再发布真实项目绑定。失败或取消保留原 OpenHarmony SDK 与配置；SDK 缓存保留，可再次从 OpenHarmony 菜单切回。未知 fork 不自动迁移，也不会用官方发布清单从未知来源下载安装。

## 修复范围与备份

- **Android SDK / platforms**：优先使用项目已有 `sdk.dir`，再参考本机 SDK 环境。按工程 `compileSdk`（或 FVM SDK 的默认值）补齐 platform；优先遵循显式 `buildToolsVersion`，否则选稳定 build-tools。补齐所需 Java/官方命令行工具，校验组件，再备份并更新当前项目 `android/local.properties`。不会安装模拟器镜像，不写 `flutter config`，SDK 许可证仍由本人阅读接受。
- **中文路径**：修复 Dart `import` / `export` / `part` URI 中合法的中文 UTF-8 百分号编码。保留 URI 分隔符、注释和普通字符串；跳过构建及缓存目录。此功能不重命名项目文件夹、不升级依赖。
- **namespace**：从当前项目 `.dart_tool/package_config.json` 定位已解析 Flutter 插件，仅在其 Android Gradle 文件缺少 namespace、且 manifest 有明确 package 时修复。支持 Groovy/Kotlin，已有 namespace 不改，无法判断的插件跳过。不会遍历整个 Pub 缓存。插件可能被多个项目共用，确认前会列出具体文件。

后两项先预览，输入 `REPAIR` 才写入；备份在项目 `.jobs_flutter_backups/<时间>/`，`manifest.json` 保存每个原路径与唯一备份文件的映射，同名 Gradle/Dart 文件不会相互覆盖。Android 配置备份在 `android/.jobs-sdk-backup*`。取消或预览不改文件。恢复时应先核对目标文件此后是否有其他修改，再从映射取回原文件。

这些能力基于用户指定的 `JobsCommand@Flutter/小工具/` 中 Android SDK 修复、中文路径修复、namespace 修复和清理维护工具的用途接入；重用了本仓库的 SDK 引导，并收紧了全局安装、缓存扫描及备份范围。源工具是 `.command` 目录，namespace 工具目录名还包含一个字面双引号；安装后不依赖这些外部绝对路径。

## 清理维护

维护工具放在开发辅助组末尾。回车取消，不默认清理。依赖刷新、项目 `clean + pub get`、主动升级依赖和 Pub 缓存修复分别选择；只执行选中的操作，失败立即停止。共享 Pub、Gradle 或当前 FVM SDK 缓存清理会显示路径并要求 `CLEAN`；不会删除 Pub 可执行文件、Gradle 配置/凭据或项目锁文件。共享缓存会影响共用它的项目，重建可能重新下载。请先关闭相关构建进程；Windows 正在使用的 SDK 文件可能被系统锁定，失败会如实报告，保留尚未删除的文件。macOS 另提供当前项目 iOS 生成缓存清理，不删除 `ios/Flutter` 源文件或全局 DerivedData。

## 迁移

安装本包后停用旧 Flutter 独立菜单，包括 Terminal 的旧 pub-get 项。其余菜单保留。旧 Flutter 安装入口会转到本包；旧源代码、运行数据及卸载入口保留供兼容和排查。卸载统一组不会重新启用已停用的旧菜单。

现有运行、依赖提取、SDK 查询/管理、打包和代码生成流程复用本仓库对应工具；统一入口及附带 worker 都约束到项目 FVM。更新这些工具时应同步本包资源并运行回归测试。Mac / Windows 共用的 `FlutterProjectTools.dart` 必须保持逐字节一致。

## Windows 安装与验证

运行 `Install.cmd`，或在总安装面板选择 `Flutter开发相关辅助工具`。需要 Windows PowerShell 5.1、MSVC C++ 桌面构建工具和 Windows SDK；安装期间本地编译原生菜单 DLL 及运行宿主，不将 PowerShell/CLR/Flutter 注入 Explorer。Windows 11 在“显示更多选项”中显示。没有对 Windows 进行冒充实机验收：当前验证环境是 macOS，已验证 PowerShell 语法、包复制、FVM 绑定与注册表计划，Windows 原生 DLL 编译、注册及点击仍需 Windows 机器验证。

迁移与统一注册写入同一事务，只处理带本仓库 `JobsOwner` 的旧 Flutter 注册项。归属不明时停止并回滚；不删旧工具、工程、SDK 或缓存。卸载运行 `Uninstall.cmd`。

测试：`Tests/FlutterTools.Tests.ps1`、`Tests/HarmonyFlutterSdk.Tests.ps1`（仓库根）；共享 Dart 引擎的集成测试见 Mac 仓库 `JobsFlutterTools/Tests/ToolsTests.py`。菜单动作表在 `Scripts/FlutterToolsMenu.h`，执行动作枚举须与之同步。

# Flutter 开发、体检、修复与维护

**最低支持系统：Windows 10 64 位（x64）。** 这是当前最低支持目标；具体最低 build 尚未锁定，完整实机兼容性仍待验证。最低基线不等于所有功能已经实测通过。

`JobsFlutterTools` 是 Flutter 工程右键菜单的统一入口。只有同层 `pubspec.yaml` 声明 Flutter SDK 的工程文件夹才展示菜单；支持选中文件夹或工程内空白处。菜单由单个扩展创建，子菜单顺序固定，不再由多个独立扩展竞争排列。其他软件提供的菜单相对于本组的位置由操作系统决定。

**系统兼容性：** 当前目标为 [**Windows**](https://www.microsoft.com/windows) 10 / 11 图形桌面，要求系统 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) 5.1 Desktop、.NET 与 STA；各系统版本和架构仍待实机验收，未锁定统一最低 build。XP / Vista / Windows 8 不支持当前入口；Windows 7 SP1 / 8.1 即使安装 [**WMF 5.1**](https://www.microsoft.com/en-us/download/details.aspx?id=54616)（要求 .NET Framework 4.5+），也只满足部分运行时前提；本包及当前原生菜单安装不在这两个旧系统的支持范围。Windows 11 使用“显示更多选项”或 `Shift+F10`；x86 / ARM64 均未获全功能实机兼容保证。

**本包依赖与测试范围：** 安装原生菜单需要已有 [**Visual Studio / Build Tools**](https://visualstudio.microsoft.com/visual-cpp-build-tools/) 的“使用 C++ 的桌面开发”、MSVC、Windows SDK 及与 Explorer 一致的架构工具；缺失即停止。源码中的 x86 / ARM64 分支不等于已支持，纯 32 位宿主还存在 `ProgramFiles(x86)` 工具定位风险。运行宿主另需系统 .NET Framework 的 `csc.exe`。Flutter / Dart / FVM、Java、Android / DevEco 工具链随实际版本可能提高系统或 build 下限；Android / Harmony 本地模拟器按 AMD64 物理机单独验收，不能由 Windows ARM 虚拟机菜单测试推定可运行。

**管理操作：** 本目录以 `Manage.cmd` 为轻量启动入口，只唤起 GUI 后结束本次脚本；先在面板选择安装 / 更新或卸载。在面板确认安装 / 更新或卸载后立即执行，无二次终端确认。关闭或取消面板不执行；卸载保留日志、备份、运行文件和工具。

## 一键配置与 Gradle 插件下载

“🚀 一键配置 Flutter 项目”（`project-setup`）、“📚 下载Gradled分发与构建插件”（`gradle-download`）及“☕ 安装/切换Java SDK”（`java-manage`）由 [ProjectSetup.psm1](./Scripts/ProjectSetup.psm1) 实现，都是本包可独立勾选的叶动作。源码更新后通过本包 `Manage.cmd` 或总管理面板安装 / 更新并选中；新增原生动作需要重启 Explorer 或注销后载入新 DLL。只改源码不会更新已安装菜单。

一键流程：原生仪表盘 → 下半真实 CMD 自述回车 → fzf 选择工程已有 Android / Web / Windows / OpenHarmony 目标 → Flutter / Java 管理方式和 SDK → 补齐所选平台工具与 Flutter 平台资源 → Android 所选 JDK / Gradle / AGP 兼容检查、固定分发与 Wrapper 初始化 → `pub get` / 构建插件 → 对应 Maven、OHPM / Hvigor 或可选 JS 依赖 → 按所选启动配置实际 debug 构建原生库与延迟依赖 → doctor / 设备诊断 → 选择实际运行或本次仅准备。只有 Android 目标需要 Gradle；选择 Android 却缺少合法 Wrapper 时停止，未选 Android 不受该目录的 Wrapper 故障阻断，独立 Gradle 动作在没有 Android 平台时拒绝执行。Apple 目标要求 macOS，Linux 桌面要求 Linux 宿主，不显示为 Windows 可运行平台；OpenHarmony 始终要求鸿蒙适配 SDK 与已有 DevEco 工具。

- **Flutter 选择**：首项推荐 [FVM](https://fvm.app/)，复用当前工程 SDK 或进入已有安装 / 切换流程；该流程结束后输入 `CONTINUE` 才继续使用实际项目 SDK，取消不会默默进入下游。系统模式复用 PATH 中的普通 Flutter、手动指定 SDK 根目录，或从 [Flutter 官方归档](https://docs.flutter.dev/install/archive) 选择 Stable 版并校验官方元数据 SHA-256、解压到当前用户缓存。系统模式只绑定本工具本次流程及工程配置，不改计算机全局 PATH、不删除原 `.fvmrc`。两个模式均检查 Flutter 与同源 Dart。
- **Java 选择**：首项推荐原生 [JEnv-for-Windows](https://github.com/FelixSelter/JEnv-for-Windows)，它与 macOS 的 [jenv.be](https://www.jenv.be/) 为不同实现。也可复用系统 JDK、手动指定目录，或选择 [Temurin](https://adoptium.net/) 主版本 17 / 21 / 25 / 27 / 26 / 11 / 8，按本机 x64 / ARM64 获取官方 API 元数据与 ZIP 并校验 SHA-256。系统中只有 JRE、java/javac 主版本不一致，或选择与工程 Gradle/AGP 不兼容时停止，不擅自升级工程版本。
- **jEnv 安装与绑定**：有健康 Git 时从作者仓库首次克隆到用户缓存，显示并记录提交，后续复用同一缓存；源码改动或 origin 不符时停止。直接调用上游 `add` / `local` 模块写入其原生 `APPDATA` 下 `JEnv/jenv.config.json`，保留 global 和其它项目映射并先备份；避开主脚本会修改全局 PATH 的初始化，不安装全局 shim。缺 Git 时经确认复用本包 WinGet 依赖安装与复检；取消则停止，或返回选择系统 Java。后续在其它终端使用 jEnv 时仍须按上游说明自行初始化；本工具直接为 Gradle 子进程绑定 JDK。
- **Java 生效范围**：所选完整 JDK 通过本次进程 `JAVA_HOME`、PATH 和 `GRADLE_OPTS` 的 `org.gradle.java.home` 传给 Wrapper 与构建插件，结束后精确恢复未设置 / 空值 / 原值。工程已有 `android/gradle/gradle-daemon-jvm.properties` 时停止要求核对，它优先于常规 Java 环境。不会运行全局 `flutter config --jdk-dir`。

[Gradle](https://docs.gradle.org/current/userguide/gradle_wrapper.html) 版本始终取 `android/gradle/wrapper/gradle-wrapper.properties` 的固定 `distributionUrl`，不依据 Java 自动升级 Gradle 或 AGP。优先使用项目 `distributionSha256Sum`；没有时从官方 `.sha256` 获取可信摘要。下载可选“官方 + 官方备用”或“官方 + 官方备用 + 腾讯分发 / 阿里云插件镜像回退”；镜像 ZIP 仍用项目或官方摘要核验。下载有 15 秒连接限制、30 秒低速判断、有界重试和来源切换；不用 `-k`、不改系统代理或持久镜像。小文件请求限 60 秒、Gradle ZIP 每次限 900 秒，失败保留日志后停止。

已验证 ZIP 按 Wrapper 的 URL MD5 / base36 规则预填真正的 `zipStoreBase / zipStorePath` 缓存，遵循 `GRADLE_USER_HOME` 和 `PROJECT`（以 `android/` 为根），同时校验分发目录。支持标准两种 base 与安全相对路径；未知 base、重复键或越界路径停止。发布使用 Wrapper 同名 `.lck` 排他锁和原子替换，不伪造 `.ok`；随后由工程 `gradlew.bat --version` 自行解压、验证并核对实际版本，后续 `flutter build` 复用同一缓存。插件解析仅网络故障再试一次，认证 / 权限 / 证书 / 编译错误直接停止。可选阿里云仓库通过本次 `--init-script` 增加，不改工程和用户仓库声明；插件仍遵循项目既有 Gradle 依赖校验配置。

本工具选择保存到工程 `.jobs/flutter-environment.json`（`Platform`、`FlutterMode`、`FlutterPath`、`JavaMode`、`JavaHome`），含本机绝对路径，宜作为本机配置忽略。Java 独立动作保存 `.jobs/java-environment.json`，后续一键流程可选择复用。跨平台配置不会直接沿用，原配置有唯一备份。SDK / 下载归档在本包用户数据的 `toolchains/`，日志为 `logs/project-setup-<运行编号>.log`，终端显示实际位置；jEnv 配置、工程环境 JSON 与 `android/local.properties` 更新前各保留就近备份。`local.properties` 增量更新所选 `flutter.sdk` 及所准备的 Android `sdk.dir`，保留其它字段。恢复前应核对文件之后是否已有其它改动，再使用对应备份；不自动卸载已安装 SDK。

fzf 中 Enter 选定、Esc / Ctrl+C 取消；子层 `←` 返回真正上一选择层。返回 / 取消停止后续步骤，已经完成的安装、项目绑定、配置和缓存保留，不能视为全流程回滚。首次自述取消不执行 SDK 安装或配置。未安装 fzf 时经确认使用 WinGet 当前用户安装并复检；选择系统模式不强制安装 FVM。日志脱敏，不记录私库密码或 Token。

**准备完成不等于已运行。** 一键流程末尾 fzf 明确选择“实际编译安装并启动验证”或“仅完成环境准备”。运行分支列真实平台设备，空列表有重新加载、等待设备授权、启动现有 Android AVD 或新建 AVD；镜像 / 机型用 fzf 选择并支持 `←` 返回，镜像下载、许可与硬件加速按现有 Android 核心检查，不自动启用虚拟化或重置设备。Android 模拟器只支持上游允许的 x64 宿主，ARM64 可走真机及相应桌面 / Web 目标。AVD 创建不覆盖已有设备。

运行参数来自工程实际入口及用户选择：`lib/main*.dart` 或手动指定工程内 `.dart`、debug / profile / release、Android flavor（静态候选或手动输入），可选已有 JSON `dart-define-from-file`。不记录 define 的值，不将输入当 Shell 命令。最后输入 `RUN` 才会实际编译、安装并启动到所选设备；其它输入停止，准备结果保留。Flutter 以 machine 协议运行，先关联本次 `app.start` 的 `appId`，只有收到相同 `appId` 的 `app.started` 才标为运行验证成功；15 分钟未启动、进程失败或只有普通日志文字都不能算通过。启动后保留终端 `r` 热重载、`R` 热重启、`q` 停止控制。设备签名、Android 许可、私库认证及 UAC 均由本人处理，不自动同意；Pub 失败可在处理凭证 / 网络后明确重试一次。

### 平台工具准备

- Android 复用随包 `Actions/android-support` 的 Google 官方下载、健康检查与修复核心，确定工程 compileSdk、选择或遵循 build-tools，补齐 platform-tools 与所声明的 NDK / CMake，安装后检查关键文件。最新命令行工具需要 Java21+ 时使用独立工具 JDK，Gradle 仍绑定所选项目 JDK。SDK 许可证直接在下方控制台由本人阅读接受，不自动回答 yes。
- Windows 桌面先用 vswhere 检查对应架构 C++ 工具。缺失时可选择通过 WinGet 官方源安装 Visual Studio Build Tools 2022 的 C++ 工作负载与推荐 SDK；安装器可能请求管理员 UAC，未授权或复检失败则停止。不会因为当前不是 Windows 桌面目标而强装 C++。
- Web 检查 Chrome / Edge；缺失时可选择经 WinGet 安装 Chrome。各平台执行对应 `flutter precache`，不擅自生成其它平台工程。

### 原生仪表盘与完整日志

[ProjectSetupDashboard.ps1](./Scripts/ProjectSetupDashboard.ps1) 上方为五组横向里程碑与各组子节点，组间以等宽 ASCII `>>>>>` 连接；上部里程碑与下部黑色终端使用可拖动的水平分隔条，分别保留最小高度，拖动同步调整原生控制台，按实际事件显示未开始 / 执行中 / 等待用户 / 已完成 / 失败 / 不适用，不使用估算百分比。下方优先通过独立经典 `conhost.exe` 承载 CMD / PowerShell，再用 Win32 `SetParent`、子窗口样式和 `MoveWindow` 嵌入真实控制台；fzf、许可、启动参数和运行控制均保持原生 TTY 输入。嵌入前核对 HWND 可见、未最小化且客户区非零；ConPTY 仅消息 HWND 或系统 DPI / 终端宿主等条件不允许嵌入时，界面明确显示“独立终端”回退，下方增量显示原始工具日志末尾；不能把该回退称为已成功嵌入。日志读取保留字节 offset 与 UTF8 Decoder，每轮最多读取 128 KiB，回退视图最多显示约 20 万 UTF16 字符，积压时直接追到有界尾部；跨块中文 / emoji 保持完整，原始文件从不截断。此原生路径仍须目标 Windows 桌面验收。

窗口工具版号取同包 [SetupVersion.json](./Scripts/SetupVersion.json)，当前为 `v1.1.0 build 2026.10.29.2`。版本与节点状态分开显示：Flutter / 同源 Dart / FVM、完整 Java / javac / 厂商构建号 / jEnv、Wrapper 实际 Gradle、同一 Gradle 进程已加载 AGP、Android API / Build Tools / platform-tools / NDK / CMake / cmdline-tools、VS / MSVC / Windows SDK 或浏览器。安装后读取实际工具输出、组件 `source.properties` 和本机文件版本；没有可确认信息时写“未检测”或“不适用”，不拿期望安装号当实测号。节点小字容纳不下的完整版本可悬停查看。AGP 探针以临时只读 init script 运行并清理，不改项目版本或仓库。

每次 GUI 会话在系统临时目录创建 `JobsFlutterSetup-<运行编号>/`：`events.jsonl` 保存里程碑，`raw.log` 保存未经过脱敏或摘要替换的工具 stdout / stderr，`transcript.log` 保存交互会话文本，`raw.log.stdout.bin` / `raw.log.stderr.bin` 额外保留两条原始字节流，便于外部工具使用不同编码时复核；fzf 原生屏幕绘制不作为可复现日志承诺。终端与原始文件同步输出，不用阶段摘要代替原始内容。日志仅保留在本机；“打开完整日志”可定位该会话目录。独立 CLI 的原始日志与本包 `project-setup-*.log` 审计日志相邻；审计日志继续脱敏。窗口关闭时可选择只停止本次 PID 子树、转独立终端继续、或取消关闭；不按进程名终止其它 Flutter 会话。停止不卸载已经安装的设备应用、SDK 或已创建 AVD。

首次业务需要联网，离线仅复用完整缓存；没有 Windows 原生 PowerShell 5.1 / WinForms / conhost、真实 SDK 下载或设备运行结果时，只能说明源码与隔离回归通过，不能宣称已完成 Explorer 点击、控制台嵌入或真实项目运行验收。

## 分层依赖准备

“📥 拉取 Flutter Pub 依赖”（`pub-get`）只执行 Pub 依赖解析。已有健康项目 FVM 或本机明确保存的系统 SDK 直接复用；未绑定、缺失或损坏时进入现有 SDK 安装/切换，完成并通过 Flutter / 同源 Dart 复检后继续；选版或最终确认取消就停止。不会借用父工程或未经选择的 PATH Flutter。

| 菜单 / 动作 | 当前能力与边界 |
| --- | --- |
| 📥 拉取 Flutter Pub 依赖 / `pub-get` | 仅正常 `pub get` 和必要的项目 SDK 准备 / 复检，不代表 Maven、OHPM、原生库或 Flutter 平台资源齐全，不执行 `pub upgrade`。 |
| 📚 下载Gradled分发与构建插件 / `gradle-download` | 沿既有流程准备固定 Wrapper 分发、真实缓存初始化与配置阶段构建插件，以及必要的 Flutter / Pub 前置步骤；不会编译 App，不能代替全部 Maven / 原生依赖下载。 |
| Android 原生依赖 / `android-dependencies` | 准备项目所需 Java、Android SDK 与固定 Gradle Wrapper，先 Pub，再以临时 init task 请求全部可解析的项目及 buildscript configurations 的真实 artifact 文件，下载 Maven 原生库及 AGP / Kotlin 等构建插件；任一解析失败即停止，不以 `dependencies` 图或 `help` 成功代替下载。保留原版本、仓库与私库认证。 |
| OpenHarmony 依赖 / `ohos-dependencies` | 在 `ohos/` 执行 `ohpm install`，并使用项目自己的 Hvigor wrapper `--sync` 同步固定配置中的构建插件；先核对 `--help` 能力，缺少 wrapper / DevEco 工具就停止，不全局安装最新 Hvigor。缺少项目 SDK 时由鸿蒙 SDK 管理流程准备。 |
| 🧱 准备原生库与构建依赖（组合操作） / `native-dependencies` | 从工程已有的 Android、Windows、Web、Ohos 中选择目标，复用入口 / flavor / dart-define 选择，以对应 Flutter debug 构建触发 CMake、NuGet、FFI build hooks 或该平台所需产物。可能编译和输出构建文件，但不安装、启动应用；不保证所有平台或后续完全离线。 |
| 🗃️ 下载Flutter平台资源 / `flutter-precache` | 按工程已有目标选择 SDK 缓存，先确认该 SDK 支持相应 `precache --<平台>`；不夹带 Pub、Java / Android 工具安装或原生构建。Flutter 引擎资源不能代替 Android SDK / NDK / CMake 或 DevEco 系统工具。 |
| 🌐 拉取 Web 工程依赖 / `web-dependencies` | 仅工程根或 `web/` 存在 `package.json` 时执行；按 npm / pnpm / Yarn 锁文件分别使用 `npm ci`、`pnpm install --frozen-lockfile`、Yarn Classic `--frozen-lockfile` 或现代 Yarn `--immutable`。复核 `packageManager` 固定版本，多个管理器锁或缺少锁文件停止；保留生命周期脚本输出与失败。不需要或安装 Flutter。没有 JS 清单明确报告不适用。 |

每项先打印用途与影响，回车继续、非空取消；选择器 Esc / Ctrl+C 停止后续。仅当前进程绑定 Java / DevEco 等环境并在成功或失败后恢复；已完成的缓存、SDK 安装与生成文件保留。Android SDK 许可交由本人确认，不修改全局代理、仓库或依赖版本，不直接改第三方源码。Windows 不准备 Apple 平台或 Linux 宿主依赖；这些需在对应系统处理。

一键配置复用上述目标依赖内核：所选平台工具及 SDK 缓存 → Pub / 构建插件 → Android Maven / OHOS 同步 / 可选 JS → 所选配置的 debug 原生产物构建 → 诊断与最终运行选择。构建所选的入口、flavor、dart-define 原样交给最终运行；只有本次 appId 收到 `app.started` 才算应用启动成功。依赖或构建失败停止后续；选择“只准备”不启动应用。

只读检查可在仓库或完整复制的发布目录运行，不执行工具、联网或写文件，也不要求已安装菜单：

```powershell
powershell -NoProfile -File .\Scripts\Invoke.ps1 `
  -Target "<Flutter工程绝对路径>" `
  -Action android-dependencies `
  -Check
```

将 `-Action` 替换为表中动作或 `pub-get`。依赖操作的日志在本包用户数据 `logs/dependencies-<运行编号>.log`，终端显示实际位置；构建工具原始输出沿现有实时日志链保留。模块及取消/失败传播经过隔离假命令验证；真实 Windows Explorer、PowerShell 5.1、SDK 下载、Maven / ohpm / JS 安装、native 构建与设备运行须在目标机另验。

<strong id="dependency-faq">资源与组合操作常见问题</strong>

单独打开“下载Flutter平台资源”或“准备原生库与构建依赖（组合操作）”时，Terminal / CMD 会在首次回车确认之前逐行展示本项自述：一行一个要点，命令、资源示例和边界在对应要点下缩进。阅读后回车继续，非空输入或取消停止；不用先开始下载才能看清范围。

**“下载Flutter平台资源”具体下载什么？**

它运行所选 SDK 的 `flutter precache --<平台>`，把 Flutter 自己的引擎、编译和渲染配套资源放进 SDK 缓存。例如 Android 的引擎制品与 `gen_snapshot` AOT 工具，iOS 的 `Flutter.xcframework`，以及 Web 编译 SDK 和该版本配套的 CanvasKit / Skwasm 等 JS / Wasm 资源；具体文件、架构和 debug / profile / release 组合取决于 SDK 版本及目标。[平台缓存源码](https://github.com/flutter/flutter/blob/master/packages/flutter_tools/lib/src/flutter_cache.dart)、[引擎制品定义](https://github.com/flutter/flutter/blob/master/packages/flutter_tools/lib/src/artifacts.dart)和 [Web 渲染说明](https://docs.flutter.dev/platform-integration/web)给出了这些资源的职责。

Android 的 `--android` 在当前上游实现中还覆盖 Flutter 自身的 `android_maven` 制品，因此不能理解为“完全不碰 Maven”；它不会替工程解析全部 Maven / 第三方包，也不能代替工程 `pub get`、`pod install` 或完整 Android SDK / NDK / CMake、Xcode、DevEco 安装。已有健康缓存通常直接复用。以当前 SDK 的 `flutter precache --help` 和[官方命令实现](https://github.com/flutter/flutter/blob/master/packages/flutter_tools/lib/src/commands/precache.dart)为准。

Windows 此资源菜单只提供本机支持的已有 Android / Windows / Web / OpenHarmony 目标；上面的 iOS framework 用于解释资源类别，不表示 Windows 可以准备或构建 Apple 目标。

**“准备原生库与构建依赖（组合操作）”为什么与其它入口有重叠？**

它先检查当前目标 SDK 和必要工具，正常 `pub get`，然后复用 Android Maven、OpenHarmony OHPM / Hvigor 或已有 Web JS 工程的单类解析；Windows 桌面目标检查 C++ 工具链。单项 Windows 组合流程还会执行该目标 `precache`，再以选定入口、flavor 和 defines 实际 debug `flutter build`；项目采用 CMake、NuGet 或 FFI build hooks 时，构建可能下载或编译对应原生库。它会生成产物，不安装或启动应用，也不为其它平台准备全家桶。[执行模块](./Scripts/ProjectDependencies.ps1)与 [Dart hooks 说明](https://dart.dev/tools/hooks)对应这一边界。

重叠来自共享前置、平台包和资源阶段；已有健康缓存会复用，需要限定范围时选择单类菜单。成功只覆盖本次目标与配置，不保证未来所有 flavor / 架构完全离线。一键配置在这些步骤后还有单独的设备运行确认，不能把组合准备等同于应用启动验收。

## 原生依赖的配对提取与导入

“提取Flutter项目工程依赖”中的“🧩 提取 Flutter Pub 依赖”与“导入Flutter项目工程依赖”中的“📤 导入 Flutter Pub 依赖”保留 Pub 已解析源码格式。另有五类平台缓存的十个配对动作，分别在两组逐项启用，动作名为 `export-<类型>-dependencies` / `import-<类型>-dependencies`；不能把原生缓存快照当作 Pub 源码快照，也不能把缓存目录作为另一类型导入。

| 类型 | 提取范围与导入兼容条件 |
| --- | --- |
| `gradle` | 在菜单内选择 Maven 原生库 / 插件 `caches/modules-2`，或项目 Wrapper 固定版本的分发目录，两种快照分开。同宿主、相同项目固定 Gradle / 组件与锁指纹才允许导入；支持项目配置的 Wrapper zipStorePath。`modules-2` 是共享缓存，可能包含其它工程包，不包含整个 Gradle 用户目录、`gradle.properties`、`init.d` 或 daemon。 |
| `ohos` | 分别选择 `ohos/oh_modules`（OHPM）或 `.hvigor` 缓存层；根据本机真实 OHPM / 工程 Hvigor wrapper 版本区分，不能互换。可显式指定同类型根目录；不捆绑 DevEco 安装目录或用户凭证。 |
| `native` | 仅当前工程所选目标的 `build/app`（Android）、`build/windows`、`build/web` 或 `build/ohos`，不会提取整个 `build`。绑定本机 OS / ABI、Flutter 版本及工程锁；这是目标构建缓存，不能替代源码或跨系统构建链，未选平台和散落在其它路径的插件缓存不在快照内。 |
| `precache` | 所选 Flutter SDK 的 `bin/cache/artifacts`；保留对应 SDK / ABI 与目标标签，不包含 SDK 源码、Dart runtime。导入到本次指定的 SDK 产物目录，只有匹配版本才可用。 |
| `web` | 根或 `web/` 中实际 `package.json` 所在目录的 `node_modules`；区分这两个作用域，核对同宿主 / Node / ABI 及锁指纹。导入只复制已校验内容，不运行 `postinstall` 等归档脚本；需要重新安装或运行构建钩子时使用相应依赖菜单。 |

提取时确认缓存组件、源根与输出父目录，默认输出父目录为系统桌面；共享引擎建立唯一快照目录，写入 `manifest.json` 与 `payload/`。清单包含类型、宿主、目标、工具版本、工程配置 / 锁指纹和逐文件 SHA-256 / 长度 / 执行权限信息，避免保存来源机器的绝对路径。Dart 运行时优先从项目 SDK、显式 `DART_SDK` 或已安装命令发现，健康检查失败可手动指定已有 SDK，本动作不自动安装运行时。

导入时输入或拖入完整快照目录，明确本次目标根；先逐文件预检宿主、版本、锁与校验，再精确输入大写 `YES` 才写入。空回车、小写 `yes`、取消或任一校验失败均不导入；实际执行会再次校验，发现同名不同内容拒绝覆盖。相同文件可复用，现有工程、第三方源码与不同缓存内容保留；失败或取消不会清掉已完成的其它任务。日志在本包用户数据 `logs/native-archive-<编号>.log`，终端显示实际路径。

可使用 `Scripts/Invoke.ps1 -Target "<工程绝对路径>" -Action export-native-dependencies -Check` 查看不运行工具、不复制、不写日志的计划；将类型及 `export` / `import` 替换为对应动作。所有快照仅用于兼容环境中的缓存恢复，不保证跨系统、跨 ABI、全部平台或完全离线；分享前检查共享缓存中可能包含的私有包。Windows 真实拖入、SDK 工具版本探测与缓存恢复仍需目标机验证，Shell 隔离测试和 Dart 数据校验测试分别记录。

## 私库便捷迁移

源工程右键 → **🧩 提取Flutter项目工程依赖 → 🔐 提取Flutter项目工程私库依赖**（`export-private-dependencies`）。选择输出父目录，生成 `FlutterPrivateDependencies-<项目名>-<时间>-<随机值>/`；把整个目录随工程带到另一台机器。

目标工程右键 → **📤 导入Flutter项目工程依赖 → 📥 导入Flutter项目工程私库依赖**（`import-private-dependencies`）。输入或拖入完整快照目录，预检成功后输入 `YES`。源码写到当前工程的 `vendor/flutter_dependencies/<本次目录>/packages/`，并为全部私库（包括间接依赖）生成相对 `path` overrides。最后单独运行 `flutter pub get` 获取公共包；私库改用工程内的源码，不再访问旧机器路径或私库 Git 服务器。

- 提取范围：锁文件中所有 Git、path、自建 hosted Pub 源的已解析包，包含开发和间接依赖、Git 仓库子目录、插件包内平台源码、资源及许可证。公共 `pub.dev`、`pub.dartlang.org`、`pub.flutter-io.cn`、`pub-web.flutter-io.cn` 的包和 SDK 不复制，也不要求公共缓存仍存在。
- 无法仅凭 Git URL 判断仓库权限，所以 Git 依赖全部收录（包括公开 Git 仓库）；其它自建 Pub 镜像也按私库收录，以免漏包。
- macOS / Windows 使用同一 Dart 引擎与快照格式。提取端须已有 `pubspec.lock`、`.dart_tool/package_config.json` 和完整私库源码；导入端只需工程与健康的项目 FVM Dart，不需要旧私库缓存或 Git 凭据。
- 私库快照带文件级 SHA-256，缺包、内容损坏、包名/版本不符、Git url/ref/path 声明冲突会停止。导入前和发布覆盖文件前都会复检；普通 Pub 快照与私库快照不能混用入口。
- 保留 `pubspec.yaml` 和原锁文件；已有 `pubspec_overrides.yaml` 按字节备份，无关覆盖与注释保留。同名覆盖与来源一致时转换为新本地路径，不一致则拒绝覆盖。完整快照及导入后的 vendor 源码应一起备份；还原时使用本次目录中的配置备份。
- 当前支持独立 Flutter 工程，不支持 Pub workspace。包外/失效源码链接会导致私库提取失败，避免静默漏源码。跳过 `.git`、构建产物、生成链接目录；不迁移 Git 历史和机器凭据，也不承诺迁移独立 CocoaPods / Maven / Gradle 私服中的原生二进制。这些仍使用各自的平台依赖入口。

`flutter@aito_ie` 蓝本验证：5 个 Git 包（`eeasy_camera_plugin`、`flutter_im_plugin`、`flutter_nb_net`、`seres_flutter_plugin`、`seres_flutter_unionpay_plugin`）和 1 个本地包（`tigertally_flutter_plugin`）可提取，公共包不进入快照。

## 固定菜单结构

```text
🦋 Flutter开发相关辅助工具
├─ ▶️ 从终端运行 Flutter 项目
├─ 📥 拉取Flutter项目工程相关依赖
│  ├─ 📥 拉取 Flutter Pub 依赖
│  ├─ 🤖 拉取 Android 原生依赖
│  ├─ 🕊️ 拉取 OpenHarmony 依赖
│  └─ 🌐 拉取 Web 工程依赖
├─ 🧩 提取Flutter项目工程依赖
│  ├─ 🧩 提取 Flutter Pub 依赖
│  ├─ 🔐 提取Flutter项目工程私库依赖
│  ├─ 🧩 提取 Gradle 分发与依赖缓存
│  ├─ 🧩 提取 OpenHarmony 依赖
│  ├─ 🧩 提取 原生构建缓存
│  ├─ 🧩 提取 Flutter 平台资源
│  └─ 🧩 提取 Web 依赖
├─ 📤 导入Flutter项目工程依赖
│  ├─ 📤 导入 Flutter Pub 依赖
│  ├─ 📥 导入Flutter项目工程私库依赖
│  ├─ 📤 导入 Gradle 分发与依赖缓存
│  ├─ 📤 导入 OpenHarmony 依赖
│  ├─ 📤 导入 原生构建缓存
│  ├─ 📤 导入 Flutter 平台资源
│  └─ 📤 导入 Web 依赖
├─ 🔀 安装/切换Flutter运行环境
│  ├─ 🔀 安装/切换Flutter SDK
│  ├─ 🕊️ 安装/切换Flutter@OpenHarmony SDK
│  └─ ☕ 安装/切换Java SDK
├─ 🧱 Flutter 资源与构建依赖
│  ├─ 📚 下载Gradled分发与构建插件
│  ├─ 🗃️ 下载Flutter平台资源
│  └─ 🧱 准备原生库与构建依赖（组合操作）
├─ 🚀 一键配置 Flutter 项目
├─ 📦 Flutter打包
├─ 📦 打包鸿蒙（HAP + APP）
├─ ⚙️ Flutter自动化生产代码
├─ 🏥 Flutter项目体检
│  ├─ 🔎 查看当前Flutter项目工程的SDK版本
│  ├─ 🧑‍⚕️ 原生Flutter项目体检
│  └─ 💓 OpenHarmony Flutter 环境体检
└─ ♻️ Flutter清理维护工具
🔧 Flutter项目修复
├─ 🩹 修复 Android SDK / platforms 缺失
├─ 🈶 修复 Flutter 项目中文路径
└─ 🏷️ 修复 Flutter 插件 namespace
```

后续 Flutter 动作应增加到本包的固定动作表和对应分组，不再新增独立的顶层扩展。修复组也是一级菜单，其顺序固定在开发辅助组之后。

菜单中的分组标题不算可执行动作。固定白名单共 36 项，与安装 `ActionIds`、原生菜单和 PowerShell 参数枚举对账；不能通过旧 URL 或直接传入未知动作绕过开关。Windows 不添加 CocoaPods / Swift Package 的拉取或快照动作。

| 组 / 叶动作数 | 固定动作 ID |
| --- | --- |
| 根层日常操作 / 6 | `run`、`project-setup`、`package`、`build-harmony`、`codegen`、`maintenance` |
| 拉取Flutter项目工程相关依赖 / 4 | `pub-get`、`android-dependencies`、`ohos-dependencies`、`web-dependencies` |
| 提取Flutter项目工程依赖 / 7 | `extract`、`export-private-dependencies`、`export-gradle-dependencies`、`export-ohos-dependencies`、`export-native-dependencies`、`export-precache-dependencies`、`export-web-dependencies` |
| 导入Flutter项目工程依赖 / 7 | `import-dependencies`、`import-private-dependencies`、`import-gradle-dependencies`、`import-ohos-dependencies`、`import-native-dependencies`、`import-precache-dependencies`、`import-web-dependencies` |
| 安装/切换Flutter运行环境 / 3 | `sdk-manage`、`ohos-sdk-manage`、`java-manage` |
| Flutter 资源与构建依赖 / 3 | `gradle-download`、`flutter-precache`、`native-dependencies` |
| Flutter项目体检 / 3 | `sdk-version`、`native-doctor`、`harmony-doctor` |
| 项目修复 / 3 | `repair-android`、`repair-imports`、`repair-namespace` |

## 鸿蒙 HAP + APP 打包

在总管理面板或本包 `Manage.cmd` 中勾选“📦 打包鸿蒙（HAP + APP）”，对应独立叶开关 `flutter-build-harmony`。合法 Flutter 根目录始终显示该已选入口，尚无 `ohos/` 也能看到；子目录、单文件及多选不显示。点击后仍要求普通非链接的 `lib/`、`ohos/`、`ohos/build-profile.json5` 和 `ohos/oh-package.json5`；缺少或无效时提示先完成鸿蒙平台适配，本次不启动构建。直接调用 PowerShell 分发器也保留同一门禁，不自动生成平台或切换 SDK。

在工程文件夹右键选择该项，独立 CMD 显示内置自述后，按回车开始；任意非空输入或 `Ctrl+C` 取消。快捷入口不再要求选择平台或产物：固定使用当前项目 `.fvm/flutter_sdk`，按 `pub get → build hap --release → build app --release` 顺序执行。`BUILD_MODE`、`OHOS_BUILD_TARGET`、`FLAVOR`、`FLUTTER_OHOS_SDK` 不会改变此快捷动作；不会回退全局 SDK。通用“Flutter打包”保留原平台/产物选择流程。

需要现有 DevEco Studio / command-line-tools、HarmonyOS SDK、Node、npm、ohpm、hvigorw 和 Java；沿用打包内核的进程级环境检查与恢复，并核对项目 FVM 同时支持 `build hap` 和 `build app`。缺任一命令、依赖获取失败、任一步构建失败、缺失或空产物都停止；仅两种非空产物均验证后报告整体完成；APP 构建结束还会复核本轮已验证路径仍同时存在，不重新挑选其它旧包替代。产物目录及其祖先中的链接不参与采集。产物从工程 `build/ohos/`、`ohos/build/outputs/` 及各模块 `build/**/outputs/` 查找，保留工程签名配置，未签名产物明确提示；缓存产物会标明需核对。日志在当前用户本地应用数据中的 `Jobs/WindowsExtension/extensions/flutter-tools/logs/harmony-*.log`，实际路径在 CMD 显示。源码中的快捷动作和原生菜单需通过管理入口安装 / 更新后生效；加入新动作后需重启 Explorer 或注销再登录以加载新 DLL，安装器不主动重启 Explorer。

## 依赖导入

源码更新后，先通过本包 `Manage.cmd` 或总管理面板执行安装 / 更新并勾选导入项，才能出现在已安装菜单；仅修改仓库文件不会改变 Explorer 当前产物。原生动作表发生变化时还需按下文重载 Explorer。

“导入Flutter项目工程依赖 → 📤 导入 Flutter Pub 依赖”与提取入口配对；只需有效 Flutter 声明，不要求项目已有 `lib/`：先在**目标工程**右键选择该项，再在独立 CMD 提示处输入或拖入**完整导出目录**（包含 `manifest.json`、`pubspec.yaml`、`pubspec.lock`、`packages/`）。目录提示处空回车或空白输入会持续重新询问，按 `Ctrl+C` 或输入结束退出；普通目录、单包源码、未完成导出或损坏包无法继续。完整校验清单格式、包名、版本、源码文件和目标冲突后显示计划，精确输入 `YES` 才导入，其它输入取消；不会执行依赖源码。

源码原样复制到项目 `vendor/flutter_dependencies/<唯一运行目录>/packages/`，增量合并 `pubspec_overrides.yaml` 的本地 path 覆盖；目标 pubspec 原始覆盖区与快照完整原文一致时允许恢复；其它同名覆盖冲突拒绝，既有配置先备份到该运行目录。保留项目原声明、锁文件与导出来源，不自动 pub get、不改全局缓存或 SDK；完成后按需手动获取依赖。当前仅支持独立 Flutter 项目，Pub workspace 根和成员均暂不支持；不保证 SDK / 原生依赖齐全或完全离线构建。交互、只读 CLI、产物与恢复边界见[导入核心说明](./Scripts/Actions/import-dependencies/Scripts/README.md)。日志在本包 `logs/import-*.log`，运行时显示精确位置。

## FVM 与体检

常规运行、打包、体检、修复及维护入口要求项目 `.fvmrc`（或旧 `.fvm/fvm_config.json`）及 `.fvm/flutter_sdk`。缺失时提示先安装/切换项目版本，不会调用全局 Flutter。原生 SDK 安装/切换沿用 FVM 管理流程；不执行 `fvm global`、不把 Flutter 写入全局 PATH 或 Shell 配置。检查、修复及维护引擎使用该 SDK 内的 Dart 3+，无需额外安装 Dart 包。

原生体检检查 FVM、Flutter 版本声明与实际版本、同源 Dart 及 `flutter doctor -v`。基础 doctor 的警告、错误或无法判定的输出都不能算健康。

Harmony 体检先检查同一套 **FVM 管理的 Harmony Flutter SDK 的基础环境**，再检查 `hap` 构建能力、DevEco/CLT、Node、OHPM、Hvigor、HDC、Java、SDK 编译组件、项目 `ohos/` 结构及已解析原生插件的 `ohos` 声明。只有全部通过才报告健康；不会仅凭模拟器已启动就报告项目可运行。静态插件声明检查不能代替实际构建，联邦插件的替代实现需按失败列表核对。

Harmony Flutter 是适配分支，普通 Flutter 安装并不会自动带来 Harmony 构建能力。“安装/切换Flutter@OpenHarmony SDK”从 [CPF-Flutter 适配仓库](https://gitcode.com/CPF-Flutter/flutter_flutter) 读取带 `ohos` 的正式或预发布 tag（兼容 `v` 前缀），稳定 tag 优先、同组按基础版本倒序，以 fzf 单选；Esc 取消，最终回车执行、任意非空输入取消。显示完整来源、tag、不可变 commit 和缓存位置，不默认安装浮动最新版。原生 SDK 选择器仍使用原生 Flutter 发布清单。

OpenHarmony SDK 下载到当前用户本地应用数据中的 `JobsFlutter/fvm/harmony/versions/custom_jobs_ohos_<commit>`，仅复用来源、commit 及源码状态相符的缓存；冲突目录和已有源码改动会阻断，不覆盖。克隆使用完整 Git 历史，所选 tag 在选择期间改变、与分支同名或缺少 `build hap` 能力时停止。缺 Git/FVM/fzf 时沿用原生选版入口的健康检查与分别确认安装；FVM 独立 ZIP 核对官方 SHA-256。

FVM 在私有影子项目中执行 `use custom_jobs_ohos_<commit> --skip-setup --skip-pub-get`，初始化并检查实际 Flutter commit、`build hap --help`，随后才发布真实项目的 `.fvmrc` 与 `.fvm/flutter_sdk` 绝对目录联接。保留已有额外配置、flavors、IDE、ignore、源码与其它 `.fvm` 元数据，不运行 pub get、不生成 `ohos/`、不安装 DevEco、不运行打包。`.fvmrc` 的 `cachePath` / `flutterUrl` 指向所选隔离缓存与适配来源；使用其它 flavors 前也要核对其版本是否在该来源可用。不会设置 FVM 全局 fork 或 global，不改用户/系统 PATH、`JAVA_HOME` 或全局 Flutter 配置。

发布前复查项目指纹；旧 `.fvmrc` 与链接目标写入本包 `backups/openharmony-*`，发布失败只在文件与链接仍是本次预期内容时恢复，发现并发改动则保留原链接与快照等待人工核对。失败下载目录保留便于诊断，不删除既有 SDK。所有临时 FVM 环境变量在结束时恢复。只读计划入口如下，不联网、不运行 Git/FVM/Flutter、不创建缓存；计划通过不代表实际构建环境健康：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\Scripts\CheckHarmonySdk.ps1 `
  -Target 'D:\Projects\MyFlutterApp'
```

SDK 安装/切换完成后使用“OpenHarmony Flutter 环境体检”核对 DevEco/CLT、插件与项目适配，真实签名和 HAP 构建另验。多套 DevEco/CLT 并存时通过本次终端的 `TOOL_HOME` 或 `DEVECO_STUDIO_HOME` 指定。Java 安装 / 切换与一键配置使用上方的 Windows 原生流程。

需要切回原生 SDK 时，使用相邻的“安装/切换Flutter SDK”。仅当当前绑定符合本工具的 CPF 来源、`custom_jobs_ohos_<commit>` 与隔离 `harmony` 缓存约定时，进入专用反向流程：在影子项目选择官方 Flutter 版本，明确使用 `https://github.com/flutter/flutter.git` 和同级独立 `official` 缓存，安装、实际版本及来源核验通过后再发布真实项目绑定。失败或取消保留原 OpenHarmony SDK 与配置；SDK 缓存保留，可再次从 OpenHarmony 菜单切回。未知 fork 不自动迁移，也不会用官方发布清单从未知来源下载安装。

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

现有运行、依赖提取、SDK 查询/管理、打包和代码生成流程复用本仓库对应工具；常规工具及附带 worker 约束到项目 FVM；一键配置、Java 与 Gradle 准备入口支持明确选择的系统 SDK。更新这些工具时应同步本包资源并运行回归测试。Mac / Windows 共用的 `FlutterProjectTools.dart` 必须保持逐字节一致。

## Windows 安装与验证

运行唯一 `Manage.cmd` 打开本包安装 / 更新与卸载面板，无需父目录。面板展开上方菜单的全部 **36 项叶功能**（2026-10-30，依据 `FeatureActions.psm1` 与 `FlutterToolsMenu.h` 按可执行动作去重），按日常开发、联网拉取、本地提取、本地导入、运行环境、资源、体检和修复分组，每组和底部均有全选 / 全不选，短屏只滚动内容区。至少勾选一个功能才能安装；所有选中项仍由同一个包构建注册一次。安装 / 更新 Flutter 组时，将本次勾选合并到已启用动作；未选的兄弟动作保留。卸载面板可仅移除某些叶功能，剩余动作继续保留。未启用任何子项的归档、体检或修复组自动隐藏。

安装状态的 `ActionIds` 保存实际动作白名单；同一事务发布包根的 `menu-state.txt`，包含当前 release 和相同动作白名单。原生 DLL 每次展开和点击都读该稳定指针并派发当前 release，仅切换当前 DLL 已认识的动作时，后续重新选择不依赖 Explorer 重新载入 DLL；卸载墓碑使用空白名单。release 内另存 `menu-actions.txt` 作为兼容白名单。PowerShell 执行再次检查当前选择和 release。旧安装没有子功能字段时按全部现有动作兼容；损坏、重复或未知动作不会自动变成全开。**首次从不支持子功能选择的旧 DLL 升级，或安装包含新原生动作（例如“提取 / 导入原生构建缓存”）的版本后，需要先关闭正在操作的资源管理器窗口，再重启 Explorer，或注销重新登录，使新 DLL 被载入**；安装器不会主动终止窗口。独立面板默认空选，切换操作会清空勾选；未安装功能在卸载时置灰。空选、取消或关闭不执行；安装 / 更新与卸载均以面板按钮为最终确认，在隐藏后台执行，无终端二次输入。

需要 Windows PowerShell 5.1、MSVC C++ 桌面构建工具和 Windows SDK；安装期间本地编译原生菜单 DLL 及运行宿主，不将 PowerShell/CLR/Flutter 注入 Explorer。Windows 11 在“显示更多选项”中显示。当前 macOS 已验证选择计划、兼容状态、白名单解析、包复制及语法；Windows 原生 DLL 编译、WinForms 控件与 Explorer 点击仍需 Windows 机器验证。

迁移与统一注册写入同一事务，只处理带本仓库 `JobsOwner` 的旧 Flutter 注册项。归属不明时停止并回滚；不删旧工具、工程、SDK 或缓存。卸载运行 `Manage.cmd` 并选择卸载，勾选一项、多项或全选；其它动作保留。

测试：`Tests/FlutterTools.Tests.ps1`、`Tests/HarmonyFlutterSdk.Tests.ps1`（仓库根）；共享 Dart 引擎的集成测试见 Mac 仓库 `JobsFlutterTools/Tests/ToolsTests.py`。菜单动作表在 `Scripts/FlutterToolsMenu.h`，执行动作枚举须与之同步。

管理安装 / 卸载时双击 `Manage.cmd`，它只通过 WScript 唤起 GUI，随后立即结束本次脚本；不在 CMD 中编译、安装或等待输入。也可直接双击 `Manage.vbs` 进入同一面板。每个选项显示等待、执行中、完成或失败，底部实时滚动标准输出和错误，可选中复制或点击“复制全部日志”；无可靠百分比时显示执行中，总体显示完成项数。运行期间等当前事务结束后关闭，完整管理日志位于系统临时目录 `JobsExtensionManager-<运行编号>.log`。

一键配置隔离回归：`Tests/FlutterProjectSetup.Tests.ps1`，验证版本门禁、官方 / 备用线路、SHA-256、标准 Wrapper 缓存、锁冲突、配置备份、阶段顺序、取消、失败停止与环境恢复；仪表盘、原始流与机器协议见 `Tests/FlutterProjectSetupDashboard.Tests.ps1`，增量日志与消息 HWND 门禁见 `Tests/FlutterProjectSetupLogTail.Tests.ps1`。版本、ASCII 连接符及可拖分隔协议见 `Tests/FlutterProjectSetupVersion.Tests.ps1`。这些测试不会真实下载 SDK、注册菜单或修改业务工程。

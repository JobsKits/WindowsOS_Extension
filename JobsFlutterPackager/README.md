> 当前 `Install.cmd` 转交同级 [JobsFlutterTools](../JobsFlutterTools/README.md) 安装统一菜单，不能只复制本旧目录新装；`Uninstall.cmd` 保留旧功能卸载。下文的原生 / 静态菜单实现、状态路径与业务命令是保留源码的说明，当前新安装以统一包及项目 FVM 为准。原“Flutter项目体检”在统一菜单称为“原生Flutter项目体检”。

# `JobsFlutterPackager`：Flutter打包

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、安装与卸载](#installation)
- [二、运行、参数与产物](#build)
- [三、日志与验证](#logs)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

**最低支持系统：Windows 10 64 位（x64）。** 这是当前最低支持目标；具体最低 build 尚未锁定，完整实机兼容性仍待验证。最低基线不等于所有功能已经实测通过。

在 [**Windows**](https://www.microsoft.com/windows) 资源管理器右键 [**Flutter**](https://flutter.dev/) 项目文件夹，点击 **Flutter打包**，CMD 打开本包 [**PowerShell**](https://learn.microsoft.com/powershell/) 脚本，用 [**fzf**](https://github.com/junegunn/fzf) 选择 [**Android**](https://developer.android.com/) / [**iOS**](https://developer.apple.com/ios/) / [**OpenHarmony**](https://developer.huawei.com/consumer/cn/harmonyos/)。菜单是一个独立入口；Android 再选 APK、AAB 或两者，OpenHarmony 再选 HAP、APP 或两者。

| 选择 | 执行结果 |
| --- | --- |
| Android → APK | `flutter pub get` 成功后执行 `flutter build apk --release`，验证对应非空 APK。 |
| Android → AAB | 获取依赖后执行 `flutter build appbundle --release`，验证对应非空 AAB。 |
| Android → APK + AAB | 获取一次依赖，依次打 APK、AAB；任一步失败立即停止。 |
| HarmonyOS → HAP | 核对 OpenHarmony 适配 SDK 与现有 ohos 工程，获取依赖后执行 `flutter build hap --release`，验证非空 HAP。 |
| HarmonyOS → APP | 获取依赖后执行 `flutter build app --release`，验证非空 APP；签名沿用工程配置。 |
| HarmonyOS → HAP + APP | 获取一次依赖，依次打 HAP、APP；任一步失败立即停止。 |
| iOS | 明确提示需要 macOS + [**Xcode**](https://developer.apple.com/xcode/) 并停止，尚未执行 `pub get` 或 `build`。 |
| Esc / Ctrl+C | 取消选择，不开始打包。 |

**系统兼容性：** 当前目标为 [**Windows**](https://www.microsoft.com/windows) 10 / 11 图形桌面，要求系统 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) 5.1 Desktop、.NET 与 STA；各系统版本和架构仍待实机验收，未锁定统一最低 build。XP / Vista / Windows 8 不支持当前入口；Windows 7 SP1 / 8.1 即使安装 [**WMF 5.1**](https://www.microsoft.com/en-us/download/details.aspx?id=54616)（要求 .NET Framework 4.5+），也只满足部分运行时前提；本包及当前原生菜单安装不在这两个旧系统的支持范围。Windows 11 使用“显示更多选项”或 `Shift+F10`；x86 / ARM64 均未获全功能实机兼容保证。

**当前入口与依赖：** `Install.cmd` 转交同级 `JobsFlutterTools` 的统一菜单安装；只复制这个旧目录不能完成新安装，需保留同级完整 `JobsFlutterTools`，或直接复制统一包。`Uninstall.cmd` 仍用于移除本旧功能。统一包安装需要已有 C++ 桌面工作负载、MSVC / Windows SDK 与系统 .NET Framework C# 编译器；各 SDK / IDE / 生成器的实际系统要求另行满足，旧系统上菜单能显示不能证明业务可运行。

## 一、<span id="installation">安装与卸载</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

新安装需保留同级完整 `JobsFlutterTools`，本目录 [Install.cmd](./Install.cmd) 转交统一菜单；也可直接复制统一包，或在总面板选择统一 Flutter 工具组。[Uninstall.cmd](./Uninstall.cmd) 只移除本旧菜单，保留程序、日志和备份。以下逐包原生 DLL、注册与路径说明对应保留的旧实现；Windows 11 在“显示更多选项”内查看。

安装要求 Windows 10 / 11、系统 Windows PowerShell 5.1 Desktop、现有 Visual Studio / Build Tools 的“使用 C++ 的桌面开发”（MSVC、Windows SDK 与 Explorer 对应架构工具）。缺失时停止，不自动下载或安装。安装只写当前用户注册表，无需管理员；原生 DLL 在 Explorer 内仅检查小于等于 1 MiB 的本地 `pubspec.yaml`，不启动 Flutter、PowerShell 或 CLR。

菜单仅对当前层 `pubspec.yaml` 明确声明 `dependencies.flutter.sdk: flutter` 的本地 Flutter 根目录插入一项。支持选中单个项目目录及其背景；普通目录、父目录、`android/` 子目录、文件、多选、网络目录和链接目录不显示。不扫描子目录、不向上寻找父工程。尚未适配 ohos 的 Flutter 工程仍显示同一“Flutter打包”入口；选 OpenHarmony 后明确报告缺失平台，不自动创建平台。

## 二、<span id="build">运行、参数与产物</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

选择器依赖健康的 fzf。Android 需要 [**Flutter**](https://flutter.dev/) SDK、完整 JDK 17、Android SDK 及项目 `android/gradlew.bat`。缺 fzf 时提示手动执行 `winget install --id junegunn.fzf --exact`，安装后重新打开终端；不会改用其它选择器。优先使用 `.fvm/flutter_sdk/bin/flutter.bat`；已有 FVM 绑定但 SDK 不完整就停止，不隐式切换全局版本。

默认 `release`，环境变量 `BUILD_MODE` 支持 `release / debug / profile`，Android 的 `FLAVOR` 指定 flavor；两者只影响本次构建。底层 `Invoke-JobsPackagerBuild` 同时支持 `-Mode` / `-Flavor` 参数，显式参数优先。flavor 以英文字母开头，后续仅允许字母、数字、下划线和连字符。Android 的 Java 17 只设置当前进程和子进程，构建后恢复。使用 Flutter 自身输出持续显示进度并同步写日志。

APK 位于项目 `build/app/outputs/flutter-apk/`，AAB 位于 `build/app/outputs/bundle/`。每次命令成功后仍按 mode、flavor 检查非空文件；Gradle 合法复用既有产物时明确标为“现存产物，请核对”，不会强制清理重建，也不会误用其它 flavor。路径兼容参考 [Flutter 官方 Android 产物查找](https://github.com/flutter/flutter/blob/stable/packages/flutter_tools/lib/src/android/gradle.dart)。不会自动 clean、删除旧产物、提交、推送或操作远程主机。

OpenHarmony 需要当前层已有 `ohos/build-profile.json5`、`ohos/oh-package.json5`，以及能运行 `flutter build hap / app` 的 OpenHarmony 适配版 SDK；普通 Android / iOS Flutter SDK 不具备这些命令。实际执行 SDK 版本与所选包型的帮助检查，确认能力后才运行 `pub get`。不隐式安装 SDK、创建平台、升级工具链或修改签名；源码依据见[适配 SDK 主仓库](https://gitcode.com/CPF-Flutter/flutter_flutter)。

| OpenHarmony 配置 | 含义 |
| --- | --- |
| `FLUTTER_OHOS_SDK` | 可选的 OpenHarmony 适配 SDK 根目录，优先取其 `bin/flutter.bat` / `flutter.exe`；未指定时沿用项目 FVM，再使用 PATH。固定 FVM 缺失仍停止。 |
| `OHOS_BUILD_TARGET` | `hap / app / all`；默认 `hap`，设置后成为 fzf 的首选项，仍可交互改选。 |
| `BUILD_MODE` | `release / debug / profile`；默认 release，profile 需工程已有对应 build mode 配置。 |
| `DEVECO_STUDIO_HOME` / `TOOL_HOME` | DevEco Studio 或 command-line-tools 的安装根目录。按现有目录补齐本进程的工具 PATH，可复用内置 Java。 |
| `DEVECO_SDK_HOME` | HarmonyOS SDK 目录；兼容 `HOS_SDK_HOME`，不将 `OHOS_SDK_HOME` 自动视为同义路径。 |
| `JAVA_HOME` / `NODE_HOME` | 保留显式选择；目录不完整时停止。检查现有 Node、npm、ohpm、hvigorw、Java 的健康状态。 |

OpenHarmony 底层函数 `Invoke-JobsPackagerHarmonyBuild` 支持显式 `-Type / -Mode / -FlutterSdk`，优先于对应环境变量。OpenHarmony 拒绝 `FLAVOR / -Flavor`，避免部分适配 SDK 对未知 flavor 静默退回 default。所有 PATH、Java、SDK 与去色配置仅影响本进程和构建子进程，成功或失败都会恢复调用前环境。

HAP / APP 从 `build/ohos/` 及 `ohos/build`、各模块构建目录的 `outputs/` 收集，兼容工程自定义产物名称，跳过中间目录和依赖目录。非空旧产物在构建命令成功后可复用 Hvigor 缓存，并明确标为“现存 OpenHarmony 产物”；未签名文件单独提示。脚本不据此保证上架签名或设备兼容，需结合工程配置验收。

## 三、<span id="logs">日志与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

日志位于当前用户本地应用数据中 `Jobs/WindowsExtension/extensions/flutter-package/logs/`；运行开始显示实际路径。安装事务的配置与注册表备份保存在同一功能根目录。终端失败保留窗口和错误；关闭窗口会结束前台打包，不承诺后台继续。

[隔离回归](../Tests/FlutterPackager.Tests.ps1) 检查项目识别、FVM 边界、平台选择、iOS 提前停止、参数、失败顺序、APK / AAB / HAP / APP 产物验证、DevEco 工具健康链、普通 SDK 拒绝及成功 / 失败后的环境恢复；使用假命令，不运行真实 Flutter、Gradle 或注册菜单。macOS 可运行便携 PowerShell 7 检查可移植业务逻辑；Windows PowerShell 5.1、MSVC 原生 DLL、资源管理器显示、CMD / fzf 键盘交互及真实 Android / HarmonyOS 签名打包需 Windows 实机验收；macOS 上运行的 `.bat / .cmd` 假工具使用 Unix 夹具，不代表 Windows 批处理执行已验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

> 当前 `Install.cmd` 转交同级 [JobsFlutterTools](../JobsFlutterTools/README.md) 安装统一菜单，不能只复制本旧目录新装；`Uninstall.cmd` 保留旧功能卸载。下文的原生 / 静态菜单实现、状态路径与业务命令是保留源码的说明，当前新安装以统一包及项目 FVM 为准。原“Flutter项目体检”在统一菜单称为“原生Flutter项目体检”。

# `JobsFlutterDependencyExtractor`：提取 Flutter 第三方依赖

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、安装与卸载](#jobs-toc-heading-2)
- [二、提取流程与范围](#jobs-toc-heading-3)
- [三、文件与日志](#jobs-toc-heading-4)
- [四、验证与边界](#jobs-toc-heading-5)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

**最低支持系统：Windows 10 64 位（x64）。** 这是当前最低支持目标；具体最低 build 尚未锁定，完整实机兼容性仍待验证。最低基线不等于所有功能已经实测通过。

保留旧实现的 [**Windows**](https://www.microsoft.com/windows) 文件夹右键扩展源码。读取精确所选 [**Flutter**](https://flutter.dev/) 项目的锁定依赖与解析记录，把直接、间接、开发用的非 SDK [**Pub**](https://dart.dev/tools/pub/dependencies) 包源码及许可证复制到指定父目录。输入或拖入目录；直接回车采用系统 API 返回的桌面，兼容桌面重定向和 OneDrive。

| 操作 | 实际结果 |
| --- | --- |
| 右键项目文件夹 → 提取 Flutter 第三方依赖 | 打开可见终端，先显示内置自述，按回车继续。 |
| 输出路径直接回车 | 使用当前用户系统桌面，每次生成新的独立目录。 |
| 输入 `D:\源码归档\第三方包` 或拖入目录 | 按完整路径传递；不求值 PowerShell 表达式。 |
| 缺少锁文件、解析记录、源码缓存或记录已过期 | 停止并提示手动执行 `flutter pub get`，不会自动联网修复。 |
| 非 Flutter 或选择项目父目录 | 明确停止，不向下递归猜测项目。 |

**系统兼容性：** 当前目标为 [**Windows**](https://www.microsoft.com/windows) 10 / 11 图形桌面，要求系统 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) 5.1 Desktop、.NET 与 STA；各系统版本和架构仍待实机验收，未锁定统一最低 build。XP / Vista / Windows 8 不支持当前入口；Windows 7 SP1 / 8.1 即使安装 [**WMF 5.1**](https://www.microsoft.com/en-us/download/details.aspx?id=54616)（要求 .NET Framework 4.5+），也只满足部分运行时前提；本包及当前原生菜单安装不在这两个旧系统的支持范围。Windows 11 使用“显示更多选项”或 `Shift+F10`；x86 / ARM64 均未获全功能实机兼容保证。

**当前入口与依赖：** `Install.cmd` 转交同级 `JobsFlutterTools` 的统一菜单安装；只复制这个旧目录不能完成新安装，需保留同级完整 `JobsFlutterTools`，或直接复制统一包。`Uninstall.cmd` 仍用于移除本旧功能。统一包安装需要已有 C++ 桌面工作负载、MSVC / Windows SDK 与系统 .NET Framework C# 编译器；各 SDK / IDE / 生成器的实际系统要求另行满足，旧系统上菜单能显示不能证明业务可运行。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、安装与卸载</span><!-- jobs-toc:heading-end -->

新安装在 Windows 10 / 11 保留同级完整 `JobsFlutterTools`，本目录 [Install.cmd](./Install.cmd) 转交统一包；也可直接复制统一包，或在父仓面板选择统一 Flutter 工具组。统一安装仍只写当前用户菜单，无须管理员权限；Windows 11 在“显示更多选项”中使用。

本目录保留自己的清单、业务模块、Dart 提取引擎及旧生命周期实现；新安装入口另需同级统一包，保留旧源码时也须保留完整 `Scripts/`。下述静态菜单在文件夹、目录空白处和磁盘根目录可见，点击后严格验证目录，这是旧实现；当前统一菜单按精确 Flutter 根目录显示。

双击 [Uninstall.cmd](./Uninstall.cmd) 只注销本功能，保留当前用户本地应用数据中的运行版本、日志、注册表备份和禁用状态；不删除已经导出的依赖。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、提取流程与范围</span><!-- jobs-toc:heading-end -->

1、右键项目本身，阅读终端内置自述；按回车继续，任意非空输入取消，`Ctrl+C` 随时中止。

2、校验该目录自身的 `pubspec.yaml`，必须明确声明 `dependencies.flutter.sdk: flutter`。根目录和配置不能是链接或目录联接；不把描述文字、注释或只有 `flutter_test` 的项目当作 Flutter 项目。YAML 别名、标签和多行 flow 等无法可靠解析的结构请先改成常见 block 写法。

3、输入或拖入输出父目录；直接回车默认系统桌面。支持中文、空格、单引号、`&`、`%` 和 `!` 等合法路径字符；外层引号仅作为拖入表示处理，不执行命令。目录不存在时由引擎安全创建，已有提取目录不会被覆盖。

4、依次查找项目 `.fvm/flutter_sdk`、Flutter SDK 内置 Dart（环境变量、PATH 或项目包配置指向的 SDK），再检查 PATH 的 `dart.exe`。先只读核对 MZ/PE 签名与支持的机器类型，再运行健康探测通过的原生 Dart；不执行可能触发 SDK 下载的 Flutter 批处理入口，不安装或升级 SDK。

5、引擎联合校验 `pubspec.lock` 与 `.dart_tool/package_config.json`，从配置记录定位当前实际使用的包源码，逐包核对并复制。包含 hosted、Git、path 来源的直接、间接及开发依赖；不复制 Flutter/Dart SDK 包，不包含 CocoaPods、Gradle、系统框架等另行解析的原生依赖。包内随源码分发的原生文件仍属于源码复制内容。

成功结果位于输出父目录的 `FlutterDependencies-<项目名>-<UTC时间>-<随机标识>/`，包含 `packages/<包名>/` 源码、`manifest.json` 核对清单、原始 `pubspec.yaml` / `pubspec.lock` 证据及结果 `README.md`。Pub workspace 以所选项目的直接及开发依赖闭包筛选，不把同工作区其它成员独有依赖全部带走。预检失败不创建结果；复制失败保留隐藏的 `.FlutterDependencies-*.incomplete-*`，不会冒充完整产物。

原始 Pub 清单与锁文件可能包含私有地址，分享提取目录前请检查这些原始证据。运行日志的展示脱敏不会修改原始证据内容。

提取结果用于源码查阅、归档和许可证核对，不能直接当作已改好依赖路径的离线工程。原项目、缓存与 SDK 保持原内容；不会自动 `pub get`、下载依赖、改代理、改全局环境或修改依赖声明。缺少或过期的记录需要用户自行在项目根目录成功运行 `flutter pub get` 后重试。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、文件与日志</span><!-- jobs-toc:heading-end -->

业务入口和逐文件职责见 [Scripts/README.md](./Scripts/README.md)。运行依赖为系统 Windows PowerShell 5.1 Desktop、系统 .NET 和已经可用的 Dart SDK，不需要 Python、Node.js 或第三方 PowerShell 模块。

运行文件与日志按包保存在当前用户本地应用数据的 `Jobs\WindowsExtension\extensions\flutter-dependency-extract` 下，业务每次建立唯一 `logs/extract-*.log`，终端显示具体位置。来源、输出父目录、实际 Dart 与结果会同步写入日志；地址凭据、查询参数及敏感字段脱敏。失败返回非零状态，并保留终端直到回车关闭。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、验证与边界</span><!-- jobs-toc:heading-end -->

仓库的 `Tests/FlutterDependencyExtractor.Tests.ps1` 使用临时目录验证项目门禁、默认桌面与路径处理、工具发现、参数传输、错误停止和独立 release 打包；不注册真实菜单、不下载 SDK、不运行真实项目的依赖获取。引擎另以临时 Pub 项目测试源码与许可证提取，具体已执行结果以交付说明为准。

源码验证不能代替 Windows 真实桌面菜单、系统桌面重定向及 SDK 运行的实机验收。运行中按 `Ctrl+C` 可能留下未完成的提取目录，未显示成功前不能当作完整结果；源项目与依赖缓存不会因此被改写。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

> 当前 `Install.cmd` 转交同级 [JobsFlutterTools](../JobsFlutterTools/README.md) 安装统一菜单，不能只复制本旧目录新装；`Uninstall.cmd` 保留旧功能卸载。下文的原生 / 静态菜单实现、状态路径与业务命令是保留源码的说明，当前新安装以统一包及项目 FVM 为准。原“Flutter项目体检”在统一菜单称为“原生Flutter项目体检”。

# JobsFlutterRunner · 从终端运行 Flutter 项目

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、安装与卸载](#installation)
- [二、设备与运行行为](#running)
- [三、文件、日志与安全边界](#files)
- [四、验证与实现依据](#verification)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

**最低支持系统：Windows 10 64 位（x64）。** 这是当前最低支持目标；具体最低 build 尚未锁定，完整实机兼容性仍待验证。最低基线不等于所有功能已经实测通过。

在 [**Windows**](https://www.microsoft.com/windows) 资源管理器右键运行 [**Flutter**](https://flutter.dev/) 项目。只有目标目录自身的 `pubspec.yaml` 声明 `dependencies.flutter.sdk: flutter` 才插入菜单；普通目录、纯 Dart 工程、只依赖 flutter_test 的目录和父子工程目录均不显示。菜单同时支持选中文件夹及工程内空白处；Windows 11 位于“显示更多选项”。

| 操作 | 结果 |
| --- | --- |
| 右键 Flutter 根目录 → 从终端运行 Flutter 项目 | 打开 CMD，显示工具来源，选择实际设备或启动已有 Android AVD。 |
| 选定设备 | 独立后台执行 `flutter run --machine`，CMD 持续显示日志。 |
| 按 `r` / `R` | 热重载 / 热重启。 |
| 按 `s` | 请求停止当前应用；10 秒后仍未退出则终止本次 Flutter 专属进程树。 |
| 按 `q` 或直接关闭 CMD | 退出日志，Flutter 继续后台运行。 |
| 再次右键同一项目 | 自动连接已有运行会话，从日志开头重看；不重复启动第二个 Flutter。 |

**系统兼容性：** 当前目标为 [**Windows**](https://www.microsoft.com/windows) 10 / 11 图形桌面，要求系统 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) 5.1 Desktop、.NET 与 STA；各系统版本和架构仍待实机验收，未锁定统一最低 build。XP / Vista / Windows 8 不支持当前入口；Windows 7 SP1 / 8.1 即使安装 [**WMF 5.1**](https://www.microsoft.com/en-us/download/details.aspx?id=54616)（要求 .NET Framework 4.5+），也只满足部分运行时前提；本包及当前原生菜单安装不在这两个旧系统的支持范围。Windows 11 使用“显示更多选项”或 `Shift+F10`；x86 / ARM64 均未获全功能实机兼容保证。

**当前入口与依赖：** `Install.cmd` 转交同级 `JobsFlutterTools` 的统一菜单安装；只复制这个旧目录不能完成新安装，需保留同级完整 `JobsFlutterTools`，或直接复制统一包。`Uninstall.cmd` 仍用于移除本旧功能。统一包安装需要已有 C++ 桌面工作负载、MSVC / Windows SDK 与系统 .NET Framework C# 编译器；各 SDK / IDE / 生成器的实际系统要求另行满足，旧系统上菜单能显示不能证明业务可运行。

## 一、<span id="installation">安装与卸载</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

新安装保留同级完整 `JobsFlutterTools`，双击本目录 `Install.cmd` 转交统一菜单，或在上级组合面板选择统一 Flutter 工具组；也可直接复制统一包独立交付。`Uninstall.cmd` 只卸载本旧功能与其 COM 注册。以下逐包构建、事务和路径说明对应保留的旧实现。

需要 Windows 10 / 11、系统 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) 5.1 Desktop，以及已经安装的 [**Visual Studio Build Tools**](https://visualstudio.microsoft.com/visual-cpp-build-tools/) 或 Visual Studio：勾选“使用 C++ 的桌面开发”、MSVC 与 Windows SDK。ARM64 还需要对应 ARM64 编译工具。安装器用 `vswhere` 复用这些组件；缺失时停止并给出说明，不自动下载编译器、不写入半成品菜单。

安装会先复制本包、编译原生菜单 DLL 和系统 .NET Framework 后台宿主，再进入当前用户注册表 / 状态事务；不需要管理员权限，不改变系统执行策略或代理。每次使用独立 release，旧 DLL 不原地覆盖。已打开的 Explorer 可能缓存旧处理器；关闭该文件夹窗口后重开，仍无变化时注销再登录。卸载保留运行文件、日志、备份和已有 Flutter 会话；先在日志按 `s` 可明确停止会话。

## 二、<span id="running">设备与运行行为</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

优先使用项目 `.fvm/flutter_sdk/bin/flutter.bat`。存在 `.fvmrc`、`.fvm/fvm_config.json` 或 SDK 链接却缺少项目 SDK 时停止并提示先修复 FVM；只有未绑定 FVM 的工程才使用 PATH 中的 Flutter。先执行 `flutter --version --machine` 检查实际 SDK，再读取 `flutter devices --machine`。设备列表按工程已有 `android` / `.android`、`windows`、`web` 平台目录过滤；Windows 不提供 iOS 运行设备。无设备时显示完整说明与 `[r] 重新加载`、`[q] 取消`，不会自动替项目生成平台文件。

Android AVD 通过官方 [**Android Emulator**](https://developer.android.com/studio/run/emulator-commandline) 的 `-list-avds` 查询，`-avd <name>` 启动。路径依次来自 `ANDROID_SDK_ROOT`、`ANDROID_HOME`、当前用户 Android SDK 默认位置及 PATH。子进程继承当前环境，包括 `ANDROID_AVD_HOME`、`ANDROID_USER_HOME` 和 `ANDROID_EMULATOR_HOME`；不迁移 AVD、不覆盖 SDK 配置、不自动创建或下载系统镜像。启动后回车重新加载，选择已就绪的实际设备。

`flutter run` 使用项目默认入口和 Debug 模式；Flutter 自己仍可能执行 Pub、Gradle、编译及联网下载。需要 flavor、额外 dart-define 或自定义 target 的工程，请使用项目已有命令。日志快捷键通过 Flutter machine 协议发送 `app.restart` / `app.stop`，构建尚未返回 appId 时提示等待。

后台宿主通过 Win32 `DETACHED_PROCESS` 和独立进程组启动，不继承 CMD 控制台；标准输出 / 错误均由后台宿主持有。Flutter 子树放入本会话专属 Job，启动前用 stdin 门闩确保先归属再运行；关闭日志终端不会触发停止。Windows 关闭、注销、IDE / 浏览器本身退出、设备断开以及 Flutter 自身故障仍会结束运行。

## 三、<span id="files">文件、日志与安全边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```text
JobsFlutterRunner/
├── Install.cmd / Uninstall.cmd  转交统一安装 / 卸载本旧功能
├── Extension.json              功能清单和自定义安装器白名单
├── README.md
└── Scripts/
    ├── ContextMenu.cpp / .def   原生 IShellExtInit + IContextMenu
    ├── FlutterProject.h        精确 Flutter YAML 识别
    ├── RunnerHost.cs           独立后台运行、日志和 machine 控制
    ├── Build.ps1               只构建，不注册
    ├── OpenCmd.ps1             启动 CMD 宿主
    ├── Action.psm1             设备选择、重连日志和快捷键
    └── Common / Invoke / Manage / PackageInstaller  本包生命周期
```

安装数据位于当前用户本地应用数据的 `Jobs/WindowsExtension/extensions/flutter-run/`：`settings.json` 为启用状态，`backups/` 为注册表 / 状态快照，`releases/` 为保留的独立版本，`runs/<项目路径摘要>/<时间与随机标识>/` 保存会话。每次 CMD 首屏会打印完整 `run.log` 路径；同目录 `machine.jsonl` 是原始 machine 输出，`state.json` 包含进程身份和状态，`startup-error.log` 只在启动失败时生成。

原生菜单只读取本机根 `pubspec.yaml`（不超过 1 MiB），不执行项目代码、不启动 Flutter、不加载 CLR。链接、junction、UNC / 映射网络盘和非普通文件均排除；多选不显示。支持常见 block、单行 flow 和引号写法；YAML 别名、标签、多行 flow 或重复关键项按无法可靠识别处理。目录内 `pubspec` 内容变化后，下次打开右键即重新判断。

日志包含应用原始输出和本地路径，分享前自行检查。停止只作用于当前会话专属 Job，不按进程名批量结束 Dart、Flutter 或其它项目。

## 四、<span id="verification">验证与实现依据</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

父仓提供 `Tests/FlutterRunner.Tests.ps1`（临时文件、项目识别、设备过滤、会话身份、控制请求与独立注册计划）；Windows 使用 `-Native` 额外编译产物并通过假 Flutter 检查后台运行及 r / R / s 协议。测试不安装扩展、不启动真实设备、不修改真实项目。原生识别夹具由 `Tests/FlutterRunnerProjectProbe.cpp` 共用同一头文件。

实现选用 Microsoft 官方的 [IShellExtInit 初始化接口](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nn-shobjidl_core-ishellextinit) 与 [IContextMenu::QueryContextMenu](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-icontextmenu-querycontextmenu)：无效目录插入零个菜单项。Microsoft 明确[不支持 .NET 进程内 Shell 扩展](<https://learn.microsoft.com/en-us/previous-versions/windows/desktop/legacy/dd758089(v=vs.85)>)，因此使用原生 C++ 桥接；CLR 仅运行于独立宿主。Windows 真实 Explorer 的显示 / 隐藏、原生 DLL 加载、设备运行、关闭 CMD 后存活仍需 Windows 实机验收；跨平台静态 / 夹具验证不代替实机结果。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

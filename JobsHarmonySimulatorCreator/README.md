# `JobsHarmonySimulatorCreator`：新建 Harmony 模拟器

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、安装、卸载与菜单范围](#installation)
- [二、工具来源、运行与参数](#run)
- [三、创建、验证与许可](#workflow)
- [四、文件、日志与验证](#files-tests)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

**最低支持系统：Windows 10 64 位（x64）。** 这是当前最低支持目标；具体最低 build 尚未锁定，完整实机兼容性仍待验证。最低基线不等于所有功能已经实测通过。

在 **x64 Windows 10 / 11** 的系统桌面空白处右键，点击 **新建 Harmony 模拟器**，通过 CMD 补齐工具与系统镜像，回车默认选择最新稳定版手机 [**HarmonyOS**](https://developer.huawei.com/consumer/cn/harmonyos/) 镜像，调用官方 DevEco Emulator 创建独立新实例，回读验证后由本人决定是否启动。普通文件夹、选中文件 / 目录和多选不显示本入口；Windows ARM / 32 位宿主不支持。

| 操作 | 结果 |
| --- | --- |
| 桌面空白右键 → 新建 Harmony 模拟器 | 显示说明并确认，体检并补齐工具和所选 Release 镜像，创建新实例，验证后可选启动。 |
| 未指定工具且没有兼容 DevEco Emulator | 首屏回车确认后，从 SDL 免登录镜像补齐 Windows x64 工具依赖，校验并复检；不升级健康工具。 |
| 没有已下载镜像 | 读取官方可下载清单；默认最新稳定版手机，阅读原文并本人回车同意后下载、复检，然后继续创建。 |
| 已有同名实例 | 拒绝覆盖；未指定名称时自动生成唯一名称。 |
| `Run.cmd -Check` | 只查询帮助、已下载镜像和实例；不创建、下载、启动或写安装状态。 |

**系统兼容性：** 当前目标为 [**Windows**](https://www.microsoft.com/windows) 10 / 11 图形桌面，要求系统 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) 5.1 Desktop、.NET 与 STA；各系统版本和架构仍待实机验收，未锁定统一最低 build。XP / Vista / Windows 8 不支持当前入口；Windows 7 SP1 / 8.1 即使安装 [**WMF 5.1**](https://www.microsoft.com/en-us/download/details.aspx?id=54616)（要求 .NET Framework 4.5+），也只满足部分运行时前提；本包及当前原生菜单安装不在这两个旧系统的支持范围。Windows 11 使用“显示更多选项”或 `Shift+F10`；x86 / ARM64 均未获全功能实机兼容保证。

**本包依赖与测试范围：** 仅支持 AMD64（x64）Windows 10 / 11 物理机；Windows ARM、32 位系统及虚拟机不在 [DevEco 本地模拟器官方支持范围](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-requirements)。安装原生菜单需要已有 [**Visual Studio / Build Tools**](https://visualstudio.microsoft.com/visual-cpp-build-tools/) 的“使用 C++ 的桌面开发”、MSVC、Windows SDK 及与 Explorer 一致的架构工具；缺失即停止。源码中的 x86 / ARM64 分支不等于已支持，纯 32 位宿主还存在 `ProgramFiles(x86)` 工具定位风险。`Run.cmd` 不要求编译菜单，但仍受相同宿主、SDK、镜像与硬件虚拟化限制。

## 一、<span id="installation">安装、卸载与菜单范围</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

仅复制本目录即可独立使用。双击 [Install.cmd](./Install.cmd) 编译并注册本包，或在总安装面板单独勾选本功能；[Uninstall.cmd](./Uninstall.cmd) 只卸载本包菜单，保留日志、备份和运行文件。Windows 11 在“显示更多选项”中查看。安装只写当前用户注册表，需要已有 Visual Studio / Build Tools 的 C++ 桌面工作负载、MSVC 和 Windows SDK；不自动安装编译器、不提权。

原生 DLL 仅注册 `DesktopBackground` handler，并同时核对系统真实桌面路径、没有选中项、宿主为原生 x64；不会在 Explorer 内启动 SDK 或 PowerShell。独立 CLI 也会检查宿主和桌面范围。官方本地模拟器不支持 Windows ARM、32 位处理器或虚拟机，并要求硬件虚拟化等条件，参见[使用环境](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-requirements)；本入口不自动修改 BIOS、Hyper-V、系统功能或安全设置。

## 二、<span id="run">工具来源、运行与参数</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

需要具备创建能力的 DevEco Emulator。官方从 DevEco Studio **6.1.0 Beta1** 起提供 `-create` / `-imageList`，Command Line Tools 也可携带 Emulator。工具位置为 DevEco Studio 的 `tools/emulator/Emulator.exe` 或 Command Line Tools 的 `emulator/Emulator.exe`；按实际 `-help` 能力检查，不仅凭目录名或版本号判断。工具、镜像和实例目录属于不同对象，沿用现有配置。

华为官方下载中心下载模拟器配套工具（DevEco Studio / Command Line Tools）需要登录华为账号，依据[华为《账号服务与权限》](https://developer.huawei.com/consumer/cn/doc/app/hdc-services-and-benefits-0000002723168012)。如果希望免登录下载，**本入口使用 SDL 镜像作为替代下载源**。SDL（Simple DirectMedia Layer）项目托管并在[构建流程](https://discourse.libsdl.org/t/sdl-ci-add-harmonyos-openharmony-builds-to-github-actions/69513)中使用这份包；它是第三方镜像，不是另一种模拟器。

Windows x64 使用 [CLT 6.1.1.280](https://libsdl.org/harmonyos-devtools/commandline-tools-windows-x64-6.1.1.280.zip)，2,601,671,927 字节（约 2.60 GB）。桌面菜单首屏回车授权后，缺少兼容工具时自动下载；校验固定大小、SHA-256 和 ZIP 路径，检查工具能力后新增到 `%LOCALAPPDATA%/Jobs/HarmonySimulator/tools/clt-6.1.1.280-<唯一后缀>/`，下次自动发现。摘要固定于本次验证的 **SDL 镜像快照**，不是华为官方公布的摘要。失败清理本次暂存，不覆盖既有工具。macOS 桌面右键入口使用对应 ARM64 包，见[Mac 平行工程](../../MacOS@Extension/JobsHarmonySimulatorCreator/README.md)。

**SDL 工具包不含可启动的 Release 系统镜像**；脚本会通过官方 Emulator 自动下载选中的稳定版系统镜像；工具下载免登录不代表官方服务的所有地区或账号限制都不存在。已下载同一 ZIP 可用 `HARMONY_CLT_ARCHIVE` 指定本地文件，仍执行完整校验，不修改或删除原 ZIP。

| 配置 | 含义 |
| --- | --- |
| `HARMONY_EMULATOR_BIN` / `-EmulatorBin` | 显式指定 `Emulator.exe` 的绝对路径；文件无效时停止，不切其它工具。 |
| `DEVECO_STUDIO_HOME` / `TOOL_HOME` | 显式指定 DevEco / Command Line Tools 根目录；无完整 Emulator 时停止。 |
| 未显式指定工具 | 检查常见 DevEco 安装位置、脚本已安装 CLT 和 PATH；逐个过滤不兼容工具，多份兼容候选要求明确指定。没有兼容工具时，正常入口从 SDL 安装；`-Check` 只报告缺失。 |
| `HARMONY_CLT_ARCHIVE` | 已下载的同版本 SDL ZIP；安装时仍校验大小和 SHA-256。 |
| `-Name` | 可选实例名称；以英文字母开头，最多 64 字符，允许英文字母、数字、空格、下划线及加号，不能以空格结尾；官方 Emulator 不接受连字符 `-`。默认使用下划线生成唯一名称。 |
| `-NoStart` | 创建并验证后结束，不询问启动。 |
| `-Check` | 只读查询工具能力、已下载镜像及现有实例。 |

双击 [Run.cmd](./Run.cmd) 也执行相同的新建流程，无需先注册菜单。需要精确参数时，在本目录使用已有 Windows PowerShell：

```powershell
powershell.exe `
  -NoProfile `
  -File .\Scripts\CreateHarmonySimulator.ps1 `
  -Check

powershell.exe `
  -NoProfile `
  -File .\Scripts\CreateHarmonySimulator.ps1 `
  -Name JobsHarmonyDemo `
  -NoStart
```

进入终端后，直接回车继续、任意非空输入取消；选择器优先使用健康的 [**fzf**](https://github.com/junegunn/fzf)，否则显示编号，回车默认第 1 项、`q` 取消，EOF 停止。选择器临时隔离用户 execute 配置并使用 UTF-8，退出后恢复。工具会查询镜像元数据，可能访问华为服务；缺少工具时安装 SDL 镜像依赖；缺镜像时通过官方 CLI 下载所选项；不配置代理或改 PATH。

## 三、<span id="workflow">创建、验证与许可</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

流程只使用官方公开命令，参数依据[通过命令行使用模拟器](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-command-line)：

- 先检查 `Emulator -help`，再通过 `-imageList -downloaded true` 获取可选择的已下载镜像，并通过 `-list -details` 读取现有实例。
- 缺本地镜像时调用 `-imageList -downloaded false`，手机优先、数字版本降序；回车选首项并确认下载。展示 Emulator 随附 `agreement/` 中两份许可原文，用户在明确的“本人同意”提示下回车后才调用 `-license accept`。任意非空输入取消，每次任务最多确认一次。然后用 `-install -deviceType TYPE -osVersion VERSION -force` 下载；仅已确认的新镜像安装省略重复提示，创建与启动不用 `-force`。必须在本地清单验证到所选类型和版本才继续，返回 0 但未安装也视为失败，不无限复检。
- 选择镜像后生成唯一名称，显示计划并等待创建确认；调用 `-create NAME -deviceType TYPE -osVersion VERSION`。实例 / 镜像路径沿用 DevEco 已配置默认值，机型使用官方最新默认模板。
- 确认后再次读取清单并复检重名，再执行创建；创建命令必须成功，且回读清单必须包含唯一、名称 / 产品类型 / 系统版本均匹配的新实例，才报告验证完成。不会覆盖或删除既有实例，也不传 `-force`。
- 独立 CLT 创建完成后，若新实例缺少 SDK 字段，验证同包 `sdk/default/openharmony/toolchains/hdc.exe` 后补入该实例的 `sdkPath`；保留官方已有路径，不改全局环境或旧实例。
- 创建后可回车启动，任意非空输入只保留实例并跳过；启动使用 `-start NAME`，保留原生控制台及官方额外交互；若本次尚未确认许可，先展示许可原文并本人回车同意。

官方镜像查询示例使用 JSON 数组；实例详情文档只给字段说明，未提供实际顶层样例。当前解析器接受数组或单个包含无控制字符的字符串 `name` 的 JSON 对象，拒绝重复或大小写冲突的名称，针对同版本 Mac CLI 实测的空结果，仅将退出码为 0 的精确 `No images matching the criteria were found.` / `[Empty]` 转为空数组；其它容器、非 JSON、缺字段或验证不匹配均停止。命令返回后无法验证时，会保留现场并提示去 Device Manager 核对，避免把日志文案或仅打开 IDE 当成成功。

Phone、平板、折叠屏等模拟器受官方中国大陆使用区域限制，具体以[设备支持类型](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-devicetype)为准。需要登录开发者账号的版本不能通过命令行启动，应使用 DevEco Studio；本包不绕过登录、地域或许可。已创建的实例启动失败时继续保留，不自动删除重建。

## 四、<span id="files-tests">文件、日志与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```text
JobsHarmonySimulatorCreator/
├── Install.cmd / Uninstall.cmd   独立安装与卸载
├── Run.cmd                       独立新建与只读 Check 入口
├── Extension.json                本包身份与桌面菜单信息
├── README.md
└── Scripts/                      原生桌面门禁、业务、安装事务与说明
```

首屏确认后、依赖准备前，操作日志保存在当前用户本地应用数据 `Jobs/WindowsExtension/extensions/harmony-simulator-create/logs/`；工具启动前显示路径。原生创建 / 启动输出直接在终端显示，保留官方交互；SDK 自身日志位置沿用其配置。安装备份位于本包用户运行根目录；关闭终端可能影响前台任务。

macOS PowerShell 7.6.8 隔离验证基线：镜像流程 17、业务 64、SDL 依赖 36、总目录菜单 58 条断言均通过。

[依赖安装回归](../Tests/HarmonySimulatorBootstrap.Tests.ps1)与[业务回归](../Tests/HarmonySimulatorCreator.Tests.ps1)与[镜像流程回归](../Tests/HarmonySimulatorImages.Tests.ps1)使用临时目录和假 Emulator，不联网安装、不注册菜单、不创建真实实例；[桌面门禁探针](../Tests/HarmonyDesktopProbe.cpp)核对纯路径范围。macOS PowerShell 7 只能证明可移植业务和夹具行为；Windows PowerShell 5.1、真实 `Emulator.exe` 输出结构、MSVC DLL、Explorer 菜单、硬件虚拟化、许可和真实创建 / 启动仍需 Windows 实机验收。

2026-10-23 验证：PowerShell 7.6.8 下依赖安装回归 36 断言、创建业务 64 断言、独立 Action 模块 168 断言、独立包架构 558 断言全部通过；桌面范围 C++ 探针 13 断言通过。Windows 完整 ZIP 的 CRC 全检和 102,433 条路径核查通过；下载函数已对 SDL 站点完成真实流式读取验证。Windows PowerShell 5.1、扩展路径在 Windows 上的解压、真实 Emulator.exe 与 Explorer 菜单仍待 Windows 实机验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

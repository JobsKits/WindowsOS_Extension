# `JobsHarmonySimulatorCreator`：新建鸿蒙模拟器

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

在 **x64 Windows 10 / 11** 的系统桌面空白处右键，点击 **新建鸿蒙模拟器**，通过 CMD 选择本机已下载的 [**HarmonyOS**](https://developer.huawei.com/consumer/cn/harmonyos/) 镜像，调用官方 DevEco Emulator 创建独立新实例，回读验证后由本人决定是否启动。普通文件夹、选中文件 / 目录和多选不显示本入口；Windows ARM / 32 位宿主不支持。

| 操作 | 结果 |
| --- | --- |
| 桌面空白右键 → 新建鸿蒙模拟器 | 显示说明并确认，体检工具，选择已下载的 Release 镜像，创建新实例，验证后可选启动。 |
| 没有 DevEco Emulator 或版本不支持创建 | 给出官方准备方式并停止，不以打开 IDE 代替创建成功。 |
| 没有已下载镜像 | 提示在 DevEco Studio 的 Device Manager 下载并本人确认许可后重试，本入口不下载。 |
| 已有同名实例 | 拒绝覆盖；未指定名称时自动生成唯一名称。 |
| `Run.cmd -Check` | 只查询帮助、已下载镜像和实例；不创建、下载、启动或写安装状态。 |

## 一、<span id="installation">安装、卸载与菜单范围</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

仅复制本目录即可独立使用。双击 [Install.cmd](./Install.cmd) 编译并注册本包，或在总安装面板单独勾选本功能；[Uninstall.cmd](./Uninstall.cmd) 只卸载本包菜单，保留日志、备份和运行文件。Windows 11 在“显示更多选项”中查看。安装只写当前用户注册表，需要已有 Visual Studio / Build Tools 的 C++ 桌面工作负载、MSVC 和 Windows SDK；不自动安装编译器、不提权。

原生 DLL 仅注册 `DesktopBackground` handler，并同时核对系统真实桌面路径、没有选中项、宿主为原生 x64；不会在 Explorer 内启动 SDK 或 PowerShell。独立 CLI 也会检查宿主和桌面范围。官方本地模拟器不支持 Windows ARM、32 位处理器或虚拟机，并要求硬件虚拟化等条件，参见[使用环境](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-requirements)；本入口不自动修改 BIOS、Hyper-V、系统功能或安全设置。

## 二、<span id="run">工具来源、运行与参数</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

需要具备创建能力的 DevEco Emulator。官方从 DevEco Studio **6.1.0 Beta1** 起提供 `-create` / `-imageList`，Command Line Tools 也可携带 Emulator。工具位置为 DevEco Studio 的 `tools/emulator/Emulator.exe` 或 Command Line Tools 的 `emulator/Emulator.exe`；按实际 `-help` 能力检查，不仅凭目录名或版本号判断。工具、镜像和实例目录属于不同对象，沿用现有配置。

| 配置 | 含义 |
| --- | --- |
| `HARMONY_EMULATOR_BIN` / `-EmulatorBin` | 显式指定 `Emulator.exe` 的绝对路径；文件无效时停止，不切其它工具。 |
| `DEVECO_STUDIO_HOME` / `TOOL_HOME` | 显式指定 DevEco / Command Line Tools 根目录；无完整 Emulator 时停止。 |
| 未显式指定工具 | 检查常见 DevEco 安装位置，再检查 PATH；多份候选要求明确指定。误选 Android Emulator 时能力检查会拒绝。 |
| `-Name` | 可选实例名称；以英文字母开头，最多 64 字符，允许字母、数字、下划线及连字符。默认生成唯一名称。 |
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

进入终端后，直接回车继续、任意非空输入取消；选择器优先使用健康的 [**fzf**](https://github.com/junegunn/fzf)，否则显示编号，回车默认第 1 项、`q` 取消，EOF 停止。选择器临时隔离用户 execute 配置并使用 UTF-8，退出后恢复。工具会查询镜像元数据，可能访问华为服务；不会安装工具、下载镜像、配置代理或改 PATH。

## 三、<span id="workflow">创建、验证与许可</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

流程只使用官方公开命令，参数依据[通过命令行使用模拟器](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-command-line)：

- 先检查 `Emulator -help`，再通过 `-imageList -downloaded true` 获取可选择的已下载镜像，并通过 `-list -details` 读取现有实例。
- 选择镜像后生成唯一名称，显示计划并等待创建确认；调用 `-create NAME -deviceType TYPE -osVersion VERSION`。实例 / 镜像路径沿用 DevEco 已配置默认值，机型使用官方最新默认模板。
- 确认后再次读取清单并复检重名，再执行创建；创建命令必须成功，且回读清单必须包含唯一、名称 / 产品类型 / 系统版本均匹配的新实例，才报告验证完成。不会覆盖或删除既有实例，也不传 `-force`。
- 创建后可回车启动，任意非空输入只保留实例并跳过；启动使用 `-start NAME`，保留原生控制台及官方许可交互，不代答 `yes`、不执行 `-license accept`。

官方镜像查询示例使用 JSON 数组；实例详情文档只给字段说明，未提供实际顶层样例。当前解析器接受数组或单个包含无控制字符的字符串 `name` 的 JSON 对象，拒绝重复或大小写冲突的名称，其它容器、非 JSON、缺字段或验证不匹配均停止。命令返回后无法验证时，会保留现场并提示去 Device Manager 核对，避免把日志文案或仅打开 IDE 当成成功。

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

确认创建后，操作日志保存在当前用户本地应用数据 `Jobs/WindowsExtension/extensions/harmony-simulator-create/logs/`；工具启动前显示路径。原生创建 / 启动输出直接在终端显示，保留官方交互；SDK 自身日志位置沿用其配置。安装备份位于本包用户运行根目录；关闭终端可能影响前台任务。

[业务回归](../Tests/HarmonySimulatorCreator.Tests.ps1)使用临时目录和假 Emulator，不联网安装、不注册菜单、不创建真实实例；[桌面门禁探针](../Tests/HarmonyDesktopProbe.cpp)核对纯路径范围。macOS PowerShell 7 只能证明可移植业务和夹具行为；Windows PowerShell 5.1、真实 `Emulator.exe` 输出结构、MSVC DLL、Explorer 菜单、硬件虚拟化、许可和真实创建 / 启动仍需 Windows 实机验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

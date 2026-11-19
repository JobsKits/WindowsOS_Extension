# Dart 文件独立运行资产盘点

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

2026-11-17，用户要求每个 Flutter Demo 可由终端或 `.dart` 右键独立启动。本表记录 Windows 右键增量；终端命令与 macOS 实现由各自工程维护。独立指指定 `main()`，仍使用所属 Flutter 工程的依赖、资源及平台宿主，不把辅助库改成新的 App。

沿现有项目边界，Explorer 原生菜单保持固定中文；十语与三态主题由既有管理面板承担。当前新增 Demo 菜单没有另行宣称十语覆盖。

## 一、<span id="assets">源码资产</span> <a href="#前言">🔼</a> <a href="#🔚">🔽</a>

| 资产／入口 | 行为、默认值与差异 | 持久化与生命周期 | 代码位置 | 当前状态 |
| --- | --- | --- | --- | --- |
| 原生单文件菜单 | 单选本地普通 `.dart`，最近 pubspec 明确声明 Flutter 才显示“从终端运行 Flutter Demo”；在父级直接插入运行叶子，不创建仅一项的 Flutter 分组；仅已启用 run 动作，目录多动作分组不变，文件不显示打包／修复等工程动作 | 每次菜单及点击重读本地路径；多选、UNC、链接及非 Flutter 嵌套包拒绝 | `JobsFlutterTools/Scripts/ContextMenu.cpp`、`FlutterRunTarget.h`，单体同源逻辑 | 源码本来已父级直达；本轮防退回归通过；包边界既有 C++ 夹具已验；Explorer 另验 |
| CMD 运输 | 原始文件完整交给运行器；CMD 工作目录为所选文件的父目录，运行阶段再定位工程根 | 环境变量仅属于新建 CMD 子进程，不写全局配置 | 两包 `Scripts/OpenCmd.ps1/OpenCmd.ps1`、统一包 `Scripts/Action.psm1` | 源码已实现；真实 CMD 运输待 Windows |
| Demo 定位与入口预检 | 最近 pubspec 是硬边界；无 main、整行注释伪 main 及 part 停止；根目录仍用默认 main | 不写工程；轻量预检，完整语法与签名由 Flutter 编译器验证 | `JobsFlutterRunner/Scripts/Action.psm1` 的 `Resolve-JobsRunnerTarget` 及聚合副本 | 300 个现工程注册目标实际解析通过 |
| 运行会话 | 工程＋目标文件计算会话键，根目录保留旧工程键；同 Demo 可重连，不同 Demo 不错连 | 各自 request/state、锁、日志及控制文件；关闭 CMD 后后台继续，s 停当前会话 | `Get-JobsRunnerProjectRoot`、`Start-JobsRunnerSession`、`RunnerHost.cs` | 隔离回归通过；Win32 detached／Job 另验 |
| 后台目标 | 请求和状态保存 Target；复核普通文件、路径归属、链接与嵌套包，使用环境变量运输 `-t`；未指定文件不加 -t | 门闩后才启动 Flutter；原热重载／重启／停止协议保留 | `RunnerHost.cs`，单体／统一包顶层／Actions/run 三副本 | C# 全文件编译通过（JSON API stub），6 项目标与命令断言通过；非真实 Windows 宿主 |
| 环境准备 | 仍按工程管理，与按 Demo 隔离的运行会话分别定位；e 停本工程环境准备 | 保留既有任务生命周期、自愈与下载策略 | `Show-JobsRunnerLog`、`Invoke-JobsFlutterRunAction` | 源码已接线；本轮不下载或安装 SDK |
| 设备可读单列 | 仅显示设备 name，缺省显示“未命名设备”；隐藏内部设备ID和共享选择器行标识；同名目标按内部序号映射，不按名称反查 | 仅本轮对象映射，无新持久偏好；组顺序、刷新、返回和取消不变 | 两份 Action 的 `Select-JobsRunnerChoice`、`Select-JobsRunnerDevice` | 设备组253检查通过，包含选择第二个同名设备返回其原ID；原生控制台另验 |
| 公共依赖与SDK对齐 | 初次完整体检后若base失败，设备选择前先以本次SDK执行pub get；索引归属复检仍失败就停止，只有剩余选定平台缺项才准备平台工具 | 可更新本工程依赖索引／锁文件，不切全局SDK；Flutter／flutter_test／flutter_web_plugins／sky_engine归属当前SDK，FVM链接等价可通过 | `RunPreflight.ps1/RunPreflight.ps1`、`RepairRunEnvironment.ps1/RepairRunEnvironment.ps1`及聚合副本 | Preflight136检查通过；不将Mac验证当Windows实机 |
| Android许可终态 | 退出零并且本轮末尾官方完整成功行才能通过，句点可选，支持CR／ANSI；拒绝、无终态、后续错误或非零退出均阻断 | 不替本人接受许可，沿原日志与官方许可存储；6份同源运行／创建内核保持一致 | `AndroidRuntime.ps1/AndroidRuntime.ps1` 的 `Test-JobsAndroidLicensesAccepted`及同源副本 | Android39检查通过，含8许可正反案例和fakeJava进程边界；非真实sdkmanager授权 |
| 安装与卸载 | 普通文件 handler 加入既有同一事务，目录三范围和 CLSID 保留；不增加功能 ID | Manifest DirectoryOnly=false；当前用户精确归属、撤销与备份沿既有实现 | 两包 `Extension.json`、`PackageInstaller.psm1` | 纯计划验证通过；本轮未执行注册／卸载 |

## 二、<span id="verification">验证与交付边界</span> <a href="#前言">🔼</a> <a href="#🔚">🔽</a>

### 2.1、<span id="current-checks">当前菜单、设备与依赖检查</span> <a href="#前言">🔼</a> <a href="#🔚">🔽</a>

- Runner65、设备分组253、Preflight136、Android39、HarmonyPrepare98检查全部通过；具体包括Dart父级叶子防退、目录多项分组保留、仅名称显示和第二个同名设备精确回映、SDK依赖归属与先修依赖、8个许可终态正反案例。
- 本轮改动为两份Action、两份RunPreflight、两份RepairRunEnvironment、两份PrepareHarmonyRun及6个Android同源内核；ContextMenu的Dart分支原已直接插入父级，本轮以回归防止再套分组。当前同名包装与旧平铺发布路径分别验证，不把测试路径迁移失败跳过为成功。
- 上述结果来自macOS PowerShell、临时元数据、fakeJava与假SDK进程及现有进程夹具；未替本人接受许可、未安装SDK、未启动真实App，不替代Windows PowerShell5.1、Explorer／COM、真实sdkmanager或设备运行验收。

### 2.2、<span id="file-baseline">保留的文件入口贯通基线</span> <a href="#前言">🔼</a> <a href="#🔚">🔽</a>

以下保留前轮文件目标和安装纯计划记录；不代表本轮新源码已在真实Windows完整重验。

- `Tests/FlutterRunner.Tests.ps1/FlutterRunner.Tests.ps1`：63 项断言通过，包含本次路径、入口、会话与注册增量，未运行 `-Native`。
- `Tests/FlutterDartTargetTests.cpp/FlutterDartTargetTests.cpp`：C++14 编译运行通过，9 项生产包边界算法断言。
- 修改范围内 10 份 PowerShell 文件解析通过；现工程全部 300 个注册 Demo 精确解析到对应 `.dart` 与工程根。
- `RunnerHost.cs` 使用现有 .NET 编译器编译完整源码，缺失的 .NET Framework JSON API 以只供编译的 stub 补足；6 项实际纯方法断言通过，不调用该 stub，不调用 Win32。该结果不能替代 Windows PowerShell 5.1、实际 JSON 序列化、CMD argv、Explorer COM 或 Win32 Job 的验证。
- 统一包安装／卸载计划均包含文件＋三类目录 handler 和本包 CLSID；本轮不访问真实注册表、不安装菜单、不启动设备或 App。
- 旧 `FlutterTools.Tests.ps1` 首次执行已通过本次注册计划断言，随后因既有脚本同名目录迁移后 `ProjectSetupRun.ps1` 的 hash 检查仍将目录当文件而中止；本轮没有把该完整组记为通过，改用独立只读计划检查覆盖本次修改。依赖自愈及其它迁移由并行任务维护。

源码需在目标 Windows 通过现有 `JobsFlutterTools/Manage.cmd` 安装／更新后生效。Windows 原生 DLL 构建、文件右键目视及真实 Demo 启动仍待目标机验收；macOS 的成功结果不代表这些项目已经通过。

<a id="🔚" href="#前言">返回前言</a>

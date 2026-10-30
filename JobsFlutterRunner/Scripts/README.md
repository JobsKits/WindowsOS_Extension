# JobsFlutterRunner 脚本与原生桥接

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、入口与职责](#entrypoints)
- [二、后台生命周期与排障](#lifecycle)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录自包含 [**Flutter**](https://flutter.dev/) 运行菜单的安装、原生识别、CMD 交互与后台监督；整个功能包可单独复制。用户入口与环境要求见[包说明](../README.md)。

## 一、<span id="entrypoints">入口与职责</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文件 | 职责 |
| --- | --- |
| `Manage.ps1` / `PackageInstaller.psm1` | 安装确认、独立备份、release、当前用户 COM 注册与回滚；卸载保留数据。 |
| `Build.ps1` | 从现有 vswhere / MSVC / Windows SDK 编译原生 DLL，系统 csc 编译独立后台宿主；只构建，不安装或联网。 |
| `ContextMenu.cpp` / `FlutterProject.h` / `ContextMenu.def` | 原生菜单初始化和根 YAML 判断，无效目标不插入菜单。 |
| `OpenCmd.ps1` / `Invoke.ps1` | 通过固定 CMD 引导行进入本包，路径通过环境和独立参数传递；检查已安装状态。 |
| `Action.psm1` | fzf 选择设备、启动已有 / 缺失时初始化 Android AVD；按 serial 等待 Flutter，启动 / 重连日志和快捷键。 |
| `AndroidRuntime.ps1` | 随包工具链自检、官方下载校验、AVD 名称与启动就绪检测；复用 JobsAndroidSimulatorCreator 自维护函数，不依赖兄弟包。 |
| `RunnerHost.cs` | detached 独立监督进程、专属 Job、日志和 Flutter machine 双向控制。 |
| `Common.psm1` | 通用路径、参数、进程与日志工具。 |

只构建验证时，在 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) 5.1 中执行，输出路径自行选择：

```powershell
.\Build.ps1 `
    -SourceRoot .. `
    -OutputRoot ..\build
```

正常安装使用包根 `Manage.cmd`，不手工调用注册表写入方法。`Extension.json` 的 `InfrastructureOverrides` 只允许 `PackageInstaller.psm1`，避免父仓通用模板同步覆盖本包原生编译和 COM 生命周期。

## 二、<span id="lifecycle">后台生命周期与排障</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

先在 CMD 选择设备，随后只通过文件日志和原子控制请求与后台通信。后台持有 Flutter 标准输入 / 输出 / 错误及每项目排他锁，CMD 不持有 Flutter 进程。会话 PID 必须同时匹配进程开始时间才重连，避免 PID 复用；`r` / `R` 使用 `app.restart`，`s` 使用 `app.stop`，超时只终止本会话 Job。

CMD 首屏打印日志位置。`run.log` 用于阅读，`machine.jsonl` 用于协议排障，`state.json` 用于检查开始 / 运行 / 停止 / 失败，`startup-error.log` 用于定位后台启动失败。没有设备时仍可选择 Android 初始化或重新加载；AVD 缺失时在本流程确认工具准备、选择型号与镜像、确认创建并等待实际设备。安装器缺 MSVC / SDK 时会在写注册表之前停止，按提示补齐现有开发工具后重试。

原生 COM 与 Win32 detached / Job 运行须在 Windows 实机验证；本机跨平台测试不会真实注册右键菜单或运行用户工程。

本目录的 `Manage.ps1`、`SelectionPanel.psm1` 和 `ManagementWorker.ps1` 构成本包自包含管理面板；由上级 `Manage.vbs` 无控制台启动。安装 / 卸载在隐藏后台执行，逐项状态与可复制实时日志留在面板中。日志区上沿的分隔条可上下拖动，调节结果在当前窗口保留；上下限为功能行、操作按钮和日志工具栏留出空间。日志正文右键可“复制”或“全选”，也支持 Ctrl+A / Ctrl+C；全选仅针对当前可见缓冲区，完整输出使用“复制全部日志”。总进度按已处理项 / 本次所选项显示计数和百分比；成功与失败计入已处理，等待中、执行中和未执行项不计入，100% 表示全部处理完毕，结果以成功 / 失败汇总为准。安装 / 更新和卸载分别计时；点击时只清零并启动当前操作计时，后台全部结束或启动失败时只冻结当前耗时。每秒刷新 `HH:mm:ss`（小时可超过 24），执行时显示“安装用时 / 卸载用时”，结束显示“安装总用时 / 卸载总用时”。两份耗时只在当前面板会话内独立保留。安装成功显示绿色“✅ 安装成功”。不改变右键业务工具自己的交互方式。失败状态可点击，在独立 PowerShell 中只读显示本次完整会话日志；包失败不阻止其它所选包，日志不可用时在面板提示。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

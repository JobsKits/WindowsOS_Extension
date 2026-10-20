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
| `Action.psm1` | Flutter / Android AVD 查询，按工程平台筛设备，启动 / 重连日志和快捷键。 |
| `RunnerHost.cs` | detached 独立监督进程、专属 Job、日志和 Flutter machine 双向控制。 |
| `Common.psm1` | 通用路径、参数、进程与日志工具。 |

只构建验证时，在 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) 5.1 中执行，输出路径自行选择：

```powershell
.\Build.ps1 `
    -SourceRoot .. `
    -OutputRoot ..\build
```

正常安装使用包根 `Install.cmd`，不手工调用注册表写入方法。`Extension.json` 的 `InfrastructureOverrides` 只允许 `PackageInstaller.psm1`，避免父仓通用模板同步覆盖本包原生编译和 COM 生命周期。

## 二、<span id="lifecycle">后台生命周期与排障</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

先在 CMD 选择设备，随后只通过文件日志和原子控制请求与后台通信。后台持有 Flutter 标准输入 / 输出 / 错误及每项目排他锁，CMD 不持有 Flutter 进程。会话 PID 必须同时匹配进程开始时间才重连，避免 PID 复用；`r` / `R` 使用 `app.restart`，`s` 使用 `app.stop`，超时只终止本会话 Job。

CMD 首屏打印日志位置。`run.log` 用于阅读，`machine.jsonl` 用于协议排障，`state.json` 用于检查开始 / 运行 / 停止 / 失败，`startup-error.log` 用于定位后台启动失败。没有设备时用 `r` 重新加载；AVD 缺失须先用 Android Studio 建立 Windows 可用镜像。安装器缺 MSVC / SDK 时会在写注册表之前停止，按提示补齐现有开发工具后重试。

原生 COM 与 Win32 detached / Job 运行须在 Windows 实机验证；本机跨平台测试不会真实注册右键菜单或运行用户工程。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

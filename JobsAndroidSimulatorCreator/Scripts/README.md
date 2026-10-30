# Android 模拟器扩展脚本与原生桥接

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、调用与验证](#jobs-toc-heading-2)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

> 本目录是独立 Android 模拟器功能的运行与安装实现。用户入口为上级目录的 `Manage.cmd`、`Manage.cmd`、`Run.cmd`；单包复制到任意目录后仍可独立安装。

| 文件 | 职责 |
| --- | --- |
| `Manage.ps1` / `PackageInstaller.psm1` | 当前用户安装、精确卸载和本包注册 / 状态管理。 |
| `Build.ps1` | 使用已有 MSVC / Windows SDK 构建原生菜单，不自动安装编译器。 |
| `ContextMenu.cpp` / `.def` / `DesktopScope.h` | 桌面背景 COM 桥接；仅无选中项且匹配系统 Desktop 时显示，点击后交给独立终端。 |
| `OpenCmd.ps1` / `Invoke.ps1` | 安全打开 CMD 并传递桌面目标；右键固定进入新建流程，SDK 工具不进入 Explorer 进程。 |
| `CreateAndroidSimulator.ps1` | 独立交互入口及 `-Check` 只读体检。 |
| `Action.psm1` | SDK / Java / 工具健康检查、官方源自动补齐 / 修复、映像和机型选择、唯一命名、创建与启动验证。 |
| `Common.psm1` | 当前用户路径、进程参数、日志与通用基础设施。 |

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、调用与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

在本目录使用 Windows PowerShell 5.1：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ./CreateAndroidSimulator.ps1 `
  -Check
```

只读体检不安装、卸载或创建 SDK 根目录。两个运行入口统一在首屏说明自动下载和修复边界，回车后体检整条依赖链，健康复用，缺失依赖自动补齐，损坏组件只修复一次并立即复检。Java 21 从 [**Adoptium**](https://adoptium.net/installation/archives) 官方元数据及 ZIP 安装到用户目录，SHA-256 校验，采用与最终目录同卷的私有 stage；Command-Line Tools 同样保留旧版本并同卷安装。没有镜像时自动查询官方清单，选中后直接安装；编号列表 `q` / EOF 可取消。SDK 官方许可证仍由用户本人处理，不自动回答 `yes`。仅重装损坏 Emulator / ADB 包，保留映像及 AVD，失败停止；创建 AVD 前回车确认，不覆盖已有设备。

日志位于本功能当前用户数据目录的 `logs/`。详细依赖、安装边界、日志及隔离测试见[功能 README](../README.md)。本机 macOS 下的 Parser / PowerShell / C++ 夹具不能替代 Windows MSVC 与 Explorer 实机验收。

本目录的 `Manage.ps1`、`SelectionPanel.psm1` 和 `ManagementWorker.ps1` 构成本包自包含管理面板；由上级 `Manage.vbs` 无控制台启动。安装 / 卸载在隐藏后台执行，逐项状态与可复制实时日志留在面板中。日志区上沿的分隔条可上下拖动，调节结果在当前窗口保留；上下限为功能行、操作按钮和日志工具栏留出空间。日志正文右键可“复制”或“全选”，也支持 Ctrl+A / Ctrl+C；全选仅针对当前可见缓冲区，完整输出使用“复制全部日志”。总进度按已处理项 / 本次所选项显示计数和百分比；成功与失败计入已处理，等待中、执行中和未执行项不计入，100% 表示全部处理完毕，结果以成功 / 失败汇总为准。安装 / 更新和卸载分别计时；点击时只清零并启动当前操作计时，后台全部结束或启动失败时只冻结当前耗时。每秒刷新 `HH:mm:ss`（小时可超过 24），执行时显示“安装用时 / 卸载用时”，结束显示“安装总用时 / 卸载总用时”。两份耗时只在当前面板会话内独立保留。安装成功显示绿色“✅ 安装成功”。不改变右键业务工具自己的交互方式。失败状态可点击，在独立 PowerShell 中只读显示本次完整会话日志；包失败不阻止其它所选包，日志不可用时在面板提示。

<a id="🔚" href="#前言">回到首页</a>

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

> 本目录是独立 Android 模拟器功能的运行与安装实现。用户入口为上级目录的 `Install.cmd`、`Uninstall.cmd`、`Run.cmd`；单包复制到任意目录后仍可独立安装。

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

<a id="🔚" href="#前言">回到首页</a>

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
| `Action.psm1` | SDK / Java / 工具健康检查、官方源确认修复、映像和机型选择、唯一命名、创建与启动验证。 |
| `Common.psm1` | 当前用户路径、进程参数、日志与通用基础设施。 |

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、调用与验证</span><!-- jobs-toc:heading-end -->

在本目录使用 Windows PowerShell 5.1：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ./CreateAndroidSimulator.ps1 `
  -Check
```

只读体检不安装或卸载 SDK 包。交互安装工具 / 映像需明确输入 `YES`，官方许可证交由用户本人处理；创建 AVD 前再次确认，不覆盖已有设备。工具补齐在 SDK 同卷私有 stage 中下载和校验，新增独立 Command-line Tools 版本；损坏 Emulator / ADB 经确认仅重装对应工具包，保留映像及 AVD，失败停止。

日志位于本功能当前用户数据目录的 `logs/`。详细依赖、安装边界、日志及隔离测试见[功能 README](../README.md)。本机 macOS 下的 Parser / PowerShell / C++ 夹具不能替代 Windows MSVC 与 Explorer 实机验收。

<a id="🔚" href="#前言">回到首页</a>

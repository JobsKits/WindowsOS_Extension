# `JobsFlutterCodegen/Scripts`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、文件与入口](#entrypoints)
- [二、维护与验证](#maintenance)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录只实现本包的“Flutter 自动化生产代码”菜单与终端动作。运行和独立安装不查找父目录或相邻功能；[功能说明](../README.md)包含依赖、交互和风险。

## 一、<span id="entrypoints">文件与入口</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文件 | 职责 |
| --- | --- |
| `Manage.ps1` / `PackageInstaller.psm1` | 独立安装卸载、release、哈希、备份、COM 注册与事务恢复；优先从包根 `Install.cmd` / `Uninstall.cmd` 打开。 |
| `Build.ps1` | 仅用已安装 MSVC / Windows SDK 编译本包原生 DLL；不下载或注册。 |
| `ContextMenu.cpp` / `FlutterProject.h` / `ContextMenu.def` | Explorer 内只读本地 pubspec，精确单选根目录识别；不在 Explorer 内执行 PowerShell、Flutter 或 CLR。 |
| `OpenCmd.ps1` | 固定命令启动 CMD，目标与入口经环境变量传递。 |
| `Invoke.ps1` / `Common.psm1` | 校验当前包安装状态、解析目标、调用本包 Action、显示错误和维护日志。 |
| `Action.psm1` | 本功能业务；同源 SDK、逐行输出、失败停止和脱敏日志。 |
| `Check.ps1` | 只读项目与生成计划，不启动 SDK 子进程。 |

## 二、<span id="maintenance">维护与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

四份基础机制在开发时由总工程模板校验，`PackageInstaller.psm1` 是本包明确声明的覆盖项，负责原生 COM 构建事务，其余三份保持模板一致。业务入口仅导出 `Invoke-JobsFeature`；不要将项目路径拼入 `-Command` 或 CMD 可执行文本。PowerShell 文件使用 UTF-8 BOM 与 CRLF，CMD 正文使用 ASCII 与 CRLF，兼容系统 PowerShell 5.1。

[独立回归](../../Tests/FlutterDoctorCodegen.Tests.ps1)使用临时项目与假工具，不执行真实项目生成。真实安装需 Windows 桌面及原生编译环境；本机 macOS 逻辑回归只能验证配置 / 参数 / 事务计划，不能证明 Explorer 内 COM 已成功加载。日志和卸载边界见[功能说明](../README.md#check-and-logs)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

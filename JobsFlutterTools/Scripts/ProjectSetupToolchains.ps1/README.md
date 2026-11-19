# `ProjectSetupToolchains.ps1`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、入口与参数](#entry)
- [二、路径、输出与恢复](#paths)
- [三、验证范围](#verification)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

ProjectSetupToolchains.ps1 | 一键配置按平台复用的工具发现、准备与复检。 仅由 ProjectSetup 加载；安装前明确选择，运行时 PATH 变化由上层 finally 恢复。

本包保存真正脚本 [ProjectSetupToolchains.ps1](./ProjectSetupToolchains.ps1)。完整功能、依赖及操作入口见[所属目录说明](../README.md)；本说明补充该脚本的实际参数、路径和运行边界。

## 一、<span id="entry">入口与参数</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 文件夹与真正脚本完整同名，整体复制时保留上级功能目录的资源与模块；本内部脚本包不等于脱离功能目录后的独立软件。
- 当前项目最低系统目标为 Windows 10 64 位（x64）；解释器、宿主与 SDK 依赖继续服从脚本原有要求，跨端运行结果另行验证。VBS 使用系统 WScript，CMD 使用系统命令解释器，PowerShell 入口延续原宿主和版本约束。
- 交互入口沿用原自述、确认与取消；后台 worker／source 模块沿用调用方已确认的请求，不因为包装增加重复等待。取消、空选、EOF 和失败按原业务协议处理。

## 二、<span id="paths">路径、输出与恢复</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 源码入口位于本同名包；资源从实际脚本位置定位，不依赖启动工作目录。上级公开管理 CMD 仍直接放置，可从功能目录启动原管理面板。
- 源包装与已发布运行目录分别处理：安装器读取源包装后，继续发布原 flat 资源文件名，保留旧收据、菜单、后台进程和资源名约定。已有 SDK 资源包的层级保留，不统一压平。
- 参数、输出、日志位置与持久状态由原实现及所属功能管理；本次包装不新增全局配置、代理、服务或额外解释器。恢复／卸载仍使用原功能入口，不手工删除共享工具、用户数据或未知归属对象。
- 原业务可能涉及的文件、进程、网络或菜单副作用，以首屏说明、计划与原确认门禁为准；查询参数不等于授权执行安装、构建、下载、清理或卸载。

## 三、<span id="verification">验证范围</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

源路径包装、原参数声明、双布局寻址与语法在本机隔离目录核对；34 个功能包的只读发布构造前后文件清单一致。该结果不代表 Windows 原生 CMD／VBS、GUI、注册表、UAC、真实 SDK 下载、构建、安装或卸载已验收。修改后的脚本尚未替换用户已安装资源。

**必要 WinGet 分支：** 只有已经进入安装／修复且本人通过原有确认的流程才准备 App Installer／WinGet；健康、只读、取消和未选择 Chrome 安装不获取。缺失时只打开一次官方界面并在当前流程复检，不要求重开菜单；命令不再传自动接受协议或禁用交互旗标，许可和权限由本人处理。暂时网络失败沿本次流程退避，间隔封顶 30 秒，Ctrl+C 停止；取消／重启请求及确定的权限、许可、版本和包阻塞直接返回。成功后刷新本进程 PATH 并运行原必要工具复检，不持久化修改 PATH。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

Visual Studio 分支仅在明确选择 Windows 安装／修复后调用；已有实例走原生 Installer modify，缺实例才准备 WinGet。系统 VS 实例／UAC 目标保持；保留取消和需重启状态，使用完整原生交互处理许可。

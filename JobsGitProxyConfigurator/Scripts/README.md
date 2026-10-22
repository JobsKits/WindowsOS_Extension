# `Scripts` Git 动态代理与桌面入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、真实文件与职责](#files)
- [二、依赖与执行边界](#dependencies)
- [三、产物、日志与验证](#outputs)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录随独立包完整部署，不依赖总仓或其它包。桌面菜单安装与 Git 动态配置分开：菜单安装器只注册入口；用户点击后才进入配置确认。操作步骤、支持范围、路径优先级及恢复边界见[包 README](../README.md)。

## 一、<span id="files">真实文件与职责</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文件 | 职责与调用方 |
| --- | --- |
| [Manage.ps1](./Manage.ps1) | 包内安装 / 卸载入口，展示范围并确认，由裸露 CMD 调用。 |
| [PackageInstaller.psm1](./PackageInstaller.psm1) | 本包部署、备份和注册事务；只登记当前用户 `DesktopBackground`，列为通用模板的明确覆盖项。 |
| [Common.psm1](./Common.psm1)、[Invoke.ps1](./Invoke.ps1) | 本包自带的目标解码、状态校验及运行入口。 |
| [Action.psm1](./Action.psm1) | 复核目标为当前系统桌面，再交给配置流程。 |
| [Configure.ps1](./Configure.ps1) | 可见终端的安装 / C 检查 / R 恢复交互；显式 Mode 供自动化使用。 |
| [ProxyInstaller.psm1](./ProxyInstaller.psm1) | 用户 PATH 和独立 Git 运行态的安装、私有快照、幂等、检查与精确恢复。 |
| [GitShim.cs](./GitShim.cs) | 编译真实 `git.exe`，参数经数据编码传递；原生 Git 继承输入输出句柄并返回其退出码。 |
| [Policy.ps1](./Policy.ps1) | 动态 Git 的内部入口，加载当前运行态桥接程序集和选路模块。 |
| [NetworkPolicy.psm1](./NetworkPolicy.psm1) | 原生 Git 配置解析、WinINET 静态代理发现、旁路匹配、短预检及一次业务转交。 |

## 二、<span id="dependencies">依赖与执行边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

使用系统 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) 5.1 Desktop 和 .NET Framework 编译 C# 桥接，菜单安装无须 MSVC。业务配置要求已有健康的 [**Git for Windows**](https://gitforwindows.org/)；HTTP 预检优先复用该安装或系统的 [**curl**](https://curl.se/docs/manpage.html)，没有工具时交回原始 Git，不联网安装依赖。

`Policy.ps1` 不是人工使用入口，不应手工拼接编码参数。安装、检查或恢复请运行上层 [ConfigureGit.cmd](../ConfigureGit.cmd)。系统代理只读取；代理变量和命令行配置仅传给当次业务子进程。原生 Git 的原始错误不写进脱敏审计。

## 三、<span id="outputs">产物、日志与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

菜单发布文件位于当前用户 `Jobs\WindowsExtension`；动态 Git 位于 `%LOCALAPPDATA%\JobsGitNetworkStrategy\runtime\bin`，与菜单版本独立。私有快照、`active.clixml`、`install.log` 和 `logs\route.log` 均保存在同一动态策略根目录。卸载菜单不会恢复用户 PATH 或删除业务快照。

修改运行源码后应同步测试参数透明性、显式配置保留、路由选择、业务至多一次及恢复冲突。隔离回归入口为 [GitProxyConfigurator.Tests.ps1](../../Tests/GitProxyConfigurator.Tests.ps1)；跨端测试不能替代 Windows 控制台、真实注册表或 Explorer 验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

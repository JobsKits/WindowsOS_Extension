# `Scripts`：Git 拉取与冲突恢复

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、源码与入口](#jobs-toc-heading-2)
- [二、依赖与运行保护](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录随 [JobsGitPuller](../README.md) 整包独立分发。安装使用包根 [`Install.cmd`](../Install.cmd)，卸载使用 [`Uninstall.cmd`](../Uninstall.cmd)；已安装右键菜单直接启动本包 `Invoke.ps1`。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、源码与入口 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 职责 |
| --- | --- |
| [Manage.ps1](./Manage.ps1) | 核对 Windows PowerShell 5.1 / STA，确认后管理本包。 |
| [PackageInstaller.psm1](./PackageInstaller.psm1) | 本包复制、哈希校验、当前用户注册、备份、状态提交及失败恢复。 |
| [Common.psm1](./Common.psm1) | 本包内嵌的参数、路径、进程、超时及脱敏日志工具。 |
| [Invoke.ps1](./Invoke.ps1) | 校验本包启用状态，调用本包业务并显示错误。 |
| [Action.psm1](./Action.psm1) | 识别工作树、确认改动、读取 upstream、fetch、创建恢复锚点、merge、恢复和三选项重试。 |

四份基础设施代码与仓库维护模板一致；运行不读取模板、总面板或其它包。安装器复制本目录直属 `.ps1` / `.psm1` 到本包 release。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、依赖与运行保护 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

业务依赖 [**Git for Windows**](https://git-scm.com/download/win)，不自动下载或安装依赖。仅当前进程清除 Git 工作树重定向变量、关闭隐藏的终端密码输入并使用 C locale 识别错误；退出恢复原环境，不改代理、全局 Git 配置或系统环境。

普通目录静默返回；本地有改动时空行确认，网络失败不进入快照。自动恢复仅管理父仓的 HEAD、index、工作文件和快照内未跟踪文件；子模块、忽略文件、嵌套仓库和外部并发变化按[包说明的边界](../README.md#三保护日志与人工恢复)处理。终端会打印恢复引用与仓库元数据中的恢复记录位置，日志另存于本包当前用户数据目录。

测试入口是仓库 [`Tests/GitPuller.Tests.ps1`](../../Tests/GitPuller.Tests.ps1)，仅使用临时裸远端和独立工作树；真实安装和 Windows 菜单需单独验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

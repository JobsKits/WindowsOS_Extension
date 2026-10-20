# `Scripts`：代码地图更新与工具链体检

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、文件与入口](#jobs-toc-heading-2)
- [二、运行链与风险](#jobs-toc-heading-3)
- [三、维护验证](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录随 [JobsCodeGraphUpdater](../README.md) 整包独立分发。通过包根 [`Install.cmd`](../Install.cmd) 安装右键菜单，[`Uninstall.cmd`](../Uninstall.cmd) 只卸载本项；菜单直接启动本目录 `Invoke.ps1`，不依赖总工程或其它功能包。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、文件与入口 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 职责 |
| --- | --- |
| [Manage.ps1](./Manage.ps1) | Windows PowerShell 5.1 / STA 门禁、来源显示及本包安装 / 卸载确认。 |
| [PackageInstaller.psm1](./PackageInstaller.psm1) | 独立 release、SHA-256 校验、当前用户注册、备份、状态提交及失败恢复。 |
| [Common.psm1](./Common.psm1) | 路径、原生参数传递、进程超时、脱敏日志及本包状态目录。 |
| [Invoke.ps1](./Invoke.ps1) | 核对启用状态和目录类型，调用本包业务，窗口保留至回车关闭。 |
| [Action.psm1](./Action.psm1) | 精确目录保护、分层体检、条件修复、首次 `init` / 已有 `sync` 及输出身份核验。 |

四份通用基础设施来自本仓维护模板；安装后运行自己的副本。菜单安装只复制本地文件和写本包 HKCU 注册，不联网下载依赖。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、运行链与风险 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

每次先体检 PowerShell / .NET、已安装 Node/npm 与 WinGet，再核验 CodeGraph `1.6.2` 随包 Node、SQLite 读写和必需命令。健康的独立 CLI 直接执行目标业务；未使用的安装上游缺失只报告。需要安装 / 修复 CLI 时，Node/npm 必须满足 `>=20 <25`；缺少健康工具时从 WinGet 官方源精确选择 Node `24.x`，确认后尝试一次，再刷新本进程 PATH、复检。WinGet 不可用或修复失败立即停止，打印官方处理来源。

CodeGraph 安装先检查官方 npm 源连通性，再安装到本包私有 `tools/`，固定 `1.6.2` 并关闭生命周期脚本。依赖安装各自回车确认，非空取消；Node 修复强制重跑所选官方安装器，可能替换损坏或不兼容版本、请求系统授权并登记 PATH，扩展不主动提权。Homebrew 的 Windows 支持属于 WSL 2，本原生菜单使用 WinGet，不自动部署 WSL 或变更代理。

目标与父目录必须为普通目录；已有地图先只读检查精确 SQLite 数据库，不允许父目录回退。运行结束以官方 JSON 核验当前绝对路径、完成状态及零待处理变更。失败保留现场，日志位于本包用户数据目录 `logs/`；完整状态和风险见[包说明](../README.md)。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、维护验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

仓库 [`Tests/Worker.Tests.ps1`](../../Tests/Worker.Tests.ps1) 使用隔离目录、模拟依赖和临时 SQLite 验证版本 / 路径门禁、健康 CLI 复用、条件修复、失败停止和首次 / 更新分支；不真实安装依赖、注册菜单或访问网络。完整包部署与注册计划由现有架构 / 安装测试覆盖。PowerShell 夹具和源码检查不能替代 Windows 10 / 11 真实菜单、UAC、中文特殊路径与下载链验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

# `Windows 扩展基础设施`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、真实文件与用途](#jobs-toc-heading-2)
- [二、运行条件与范围](#jobs-toc-heading-3)
- [三、目录关系与验证](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

独立功能包的公共安装、调用与运行时基础模块。各包携带所需副本，用户运行所选包自身入口；此目录不提供总安装面板。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、真实文件与用途 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 职责 |
| --- | --- |
| [Manage.ps1](./Manage.ps1) | `-Mode Install / Uninstall`，读取所属包声明、默认取消的 GUI 确认，注册或移除当前用户的该项菜单。 |
| [PackageInstaller.psm1](./PackageInstaller.psm1) | 校验包声明、复制版本文件、保存注册表与状态快照、更新本包启用状态和菜单。 |
| [Common.psm1](./Common.psm1) | 本包路径、配置、进程调用和日志等公共能力；导入不等于执行业务。 |
| [Invoke.ps1](./Invoke.ps1) | 根据所属包 Action 模块调度菜单动作，保存失败信息与退出码。 |

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、运行条件与范围 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

管理入口要求 Windows PowerShell Desktop 5.1、STA 和可用 WinForms，通常由各功能包 `.cmd` 使用自身完整路径调用；复制使用时须包含该包 Extension.json 与 Action 模块，不能只运行基础模块。安装与卸载只改当前用户、本功能注册表项与运行状态，写前保存精确备份。卸载保留禁用状态、运行文件、工具、备份和日志；不提权，不持久更改执行策略，不配置系统代理。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、目录关系与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

[平台总览](../README.md)负责组合面板与功能清单，[Scripts](../Scripts/README.md)负责总入口调度，具体业务属于各 Jobs* 包。产物、日志和备份位于安装器显示的当前用户本包目录；本文按源码核对，未安装菜单或写入真实注册表。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

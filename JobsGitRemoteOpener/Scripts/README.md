# `JobsGitRemoteOpener Scripts`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、文件与职责](#jobs-toc-heading-2)
- [二、调用与边界](#jobs-toc-heading-3)
- [三、日志与验证](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

负责“打开 Git 远程地址。”的业务与独立包安装基础设施。用户使用上一级 Install.cmd / Uninstall.cmd，运行条件与菜单对象见 [功能 README](../README.md)。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、文件与职责 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 实际职责 |
| --- | --- |
| [Action.psm1](./Action.psm1) | 解析目标 Git 远程地址并通过默认浏览器打开；非 Git 目标不执行仓库写操作。 |
| [Invoke.ps1](./Invoke.ps1) | 菜单动作调度，读取本包目标并调用 Action，保存错误和结果。 |
| [Manage.ps1](./Manage.ps1) | `-Mode Install / Uninstall` 的本包入口，按默认取消窗口确认安装或卸载。 |
| [PackageInstaller.psm1](./PackageInstaller.psm1) | 声明校验、独立版本复制 / 哈希、菜单快照、状态提交与失败回滚。 |
| [Common.psm1](./Common.psm1) | 本包路径、目标、外部进程、日志与公共辅助；导入不运行业务。 |

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、调用与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

业务调度入口为 `Invoke-JobsFeature -Target <目标>`，由本包 Invoke.ps1 调用；本目录不是另一份总安装器。Action 中实现的具名功能包括：`Get-JobsGitRemote`、`Invoke-JobsFeature`。

安装管理要求系统 Windows PowerShell Desktop 5.1、STA 与图形桌面。脚本自定位本包路径；安装写当前用户本功能菜单与状态，卸载保留运行版本、日志、备份、工具及停用记录，不自动卸载其它包。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、日志与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

业务修改范围以 Action 的所需功能为准，不能把安装确认当业务操作同意。日志和快照位于当前用户本包运行目录，由入口输出实际位置；详情见 [功能说明](../README.md)。文档只静态核对源码，没有执行安装、注册表写入或真实业务。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

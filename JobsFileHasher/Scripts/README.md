# `JobsFileHasher/Scripts`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、菜单与业务](#jobs-toc-heading-2)
- [二、管理、日志与验证](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录只包含 `file-hash` 的业务和随包基础设施。公开管理入口为上级 [Manage.cmd](../Manage.cmd)，不借用其它功能包或父工程的运行脚本。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、菜单与业务 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 职责 |
| --- | --- |
| [ContextMenu.cpp](./ContextMenu.cpp)、[FileHashTarget.h](./FileHashTarget.h) | 只对单个普通文件显示“🔎 查看文件指纹 Hash（SHA-256）”；用 CreateProcess 的 argv 打开新的 STA [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) 控制台。 |
| [Invoke.ps1](./Invoke.ps1)、[Action.psm1](./Action.psm1) | 核验本包启用状态及路径，再进入唯一 Hash 业务；失败显示错误，窗口回车关闭。 |
| [FileHash.ps1](./FileHash.ps1) | 流式 SHA-256、路径转义、Unicode 纯摘要剪贴板与有限重试；失败不复制旧摘要。 |
| [Build.ps1](./Build.ps1)、[ContextMenu.def](./ContextMenu.def) | 用已有 MSVC 构建独立 `JobsFileHasherContextMenu.dll`，不注册。 |

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、管理、日志与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

`Manage.ps1`、`SelectionPanel.psm1`、`ManagementWorker.ps1` 提供本包安装 / 更新、卸载、两种部署路线、清理和合作式停止；`PackageInstaller.psm1` 只登记本包的 handler / CLSID，保留快照并在失败时恢复。`Common.psm1` 依据运行副本元数据定位安装状态及固定状态日志；日志与备份不包含正文。管理完整会话日志位于系统临时目录 `JobsExtensionManager-<运行编号>.log`。

运行端可 `Ctrl+C` 取消计算；目录、多选与链接不适用，不执行目标文件。隔离回归见上级 [功能说明](../README.md)；原生 Explorer 新窗口、真实系统剪贴板、PowerShell 5.1 / MSVC 结果与跨平台逻辑测试分开验收。



<!-- JOBS_TERMINAL_STYLE_V1:BEGIN -->

> Windows 终端配色保护：支持完整颜色查询的交互控制台会先保存当前会话默认前景、背景与16色色表，再临时使用黑底白字和统一强调色；正常结束、业务失败及可捕获中断后恢复。用户运行中自行改动的颜色保留并提示，不修改用户主题、共享 Profile、注册表或全局策略。快照不包含进入前任意叠加的临时文字样式。非控制台、重定向、`NO_COLOR`、Sourcetree 及无法可靠保存／恢复颜色的环境保持原状态或降级为纯文本。

> 强制结束进程或终端崩溃无法保证自动恢复。恢复失败时保留并提示本轮 `%TEMP%\JobsTerminalStyle-<PID>-*.ps1` 恢复脚本，需在原控制台核对后运行；不要通过重置用户配置恢复。`-ExecutionPolicy Bypass` 如被入口使用，仅作用于本次子进程，不持久修改策略。

> 验证范围：已完成 PowerShell 语法、参数／退出与隔离生命周期核验；Windows 原生控制台的显示、按键与 `Ctrl+C` 实机验证尚未完成。

<!-- JOBS_TERMINAL_STYLE_V1:END -->

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

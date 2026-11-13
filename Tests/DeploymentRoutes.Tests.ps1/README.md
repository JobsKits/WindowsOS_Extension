# `DeploymentRoutes.Tests.ps1` · 部署路线与清理边界回归

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、用途与断言范围](#coverage)
- [二、运行方式](#run)
- [三、临时夹具与验证边界](#isolation)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

> [DeploymentRoutes.Tests.ps1](./DeploymentRoutes.Tests.ps1) 验证本仓右键扩展的部署与运行文件边界，只使用临时夹具。

## 一、<span id="coverage">用途与断言范围</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 验证 `installed / build` 各自的运行目录、配置与运行态绑定，包括统一 [**Flutter**](https://flutter.dev/) 包内嵌动作的状态位置。
- 验证路线切换、事务失败回滚、未启用路线卸载及自动 / 独立清理；清理保护运行文件、配置、源码和外部目标，拒绝归属不符、链接和事务锁冲突。
- 验证后台安装的路线传递、成功后清理、安装失败保留产物、自动清理失败仍保持安装成功，以及独立清理失败单独报告。
- 验证停止请求只在包事务边界生效，未开始项目显示未执行且不计完成百分比。

## 二、<span id="run">运行方式</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

依赖 [**PowerShell**](https://learn.microsoft.com/powershell/)；脚本保持 Windows PowerShell 5.1 兼容，也可在 [**macOS**](https://www.apple.com/macos/) 的 PowerShell 7 中运行。脚本从自身所在目录向上定位仓库根，不依赖启动工作目录。

在本目录运行：

```powershell
pwsh -NoLogo -NoProfile -File "./DeploymentRoutes.Tests.ps1"
```

使用 [**Windows**](https://www.microsoft.com/windows) 自带的 PowerShell 5.1 时运行：

```powershell
powershell.exe -NoLogo -NoProfile -File ".\DeploymentRoutes.Tests.ps1"
```

脚本无参数、无交互；运行后直接执行隔离断言，标准输出显示结果，断言失败抛出异常并返回非零。未创建独立日志文件，需要留档时由调用方捕获标准输出与标准错误。

## 三、<span id="isolation">临时夹具与验证边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

测试使用临时目录和假构建；真实包安装器的状态提交与回滚在临时模块中执行，注册表写入、系统通知和快捷方式创建均替换为隔离实现。后台 worker 只运行临时假安装器；不安装真实扩展、不重启资源管理器。创建测试链接需要权限，无法创建时该链接分支明确跳过。

临时文件位于系统临时目录，退出时清理；当前进程临时调整的 `LOCALAPPDATA` 在结束时恢复。隔离断言通过不能代替真实桌面菜单、原生界面或工具链业务验收。



<!-- JOBS_TERMINAL_STYLE_V1:BEGIN -->

> Windows 终端配色保护：支持完整颜色查询的交互控制台会先保存当前会话默认前景、背景与16色色表，再临时使用黑底白字和统一强调色；正常结束、业务失败及可捕获中断后恢复。用户运行中自行改动的颜色保留并提示，不修改用户主题、共享 Profile、注册表或全局策略。快照不包含进入前任意叠加的临时文字样式。非控制台、重定向、`NO_COLOR`、Sourcetree 及无法可靠保存／恢复颜色的环境保持原状态或降级为纯文本。

> 强制结束进程或终端崩溃无法保证自动恢复。恢复失败时保留并提示本轮 `%TEMP%\JobsTerminalStyle-<PID>-*.ps1` 恢复脚本，需在原控制台核对后运行；不要通过重置用户配置恢复。`-ExecutionPolicy Bypass` 如被入口使用，仅作用于本次子进程，不持久修改策略。

> 验证范围：已完成 PowerShell 语法、参数／退出与隔离生命周期核验；Windows 原生控制台的显示、按键与 `Ctrl+C` 实机验证尚未完成。

<!-- JOBS_TERMINAL_STYLE_V1:END -->

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

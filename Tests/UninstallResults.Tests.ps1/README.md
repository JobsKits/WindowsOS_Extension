# Windows 卸载结果隔离回归

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

核对“未安装，无需卸载”独立终态、真实失败传播、逐包继续处理及 GUI 分类统计；不安装、注册或卸载真实功能。

## 一、<span id="run">运行与覆盖</span>

```powershell
pwsh -NoProfile -File ./UninstallResults.Tests.ps1
```

使用临时假安装器运行真实隐藏 worker，验证无需卸载、普通成功、失败、伪造包身份和安装操作误报的区别；直接执行面板计数与结束函数，验证无需卸载计入已处理而成功数不增加，未执行不计进度，原有三语言可显示完整文案。另核对所有 worker、面板副本哈希。真实路线状态保护见同级 Tests 中 `DeploymentRoutes.Tests.ps1/`，其中系统登记入口均为隔离替身。

## 二、<span id="boundary">范围与限制</span>

测试仅写本轮临时目录并在退出时清理，不修改用户配置、菜单、系统主题或语言。PowerShell 跨平台回归与 Windows 原生 WinForms 控件尺寸、Explorer 菜单、真实安装 / 卸载分开验收。无需卸载只表达当前路线无需处理，不代表扫描或清除了另一位置安装及历史运行文件。

同源校验通过既有 `Resolve-JobsScriptLayoutPath` 解析源码同名包装与旧平铺入口，比较真实脚本文件摘要，不把包装目录交给 `Get-FileHash`；状态、计数和真实失败断言保持原标准。



<!-- JOBS_TERMINAL_STYLE_V1:BEGIN -->

> Windows 终端配色保护：支持完整颜色查询的交互控制台会先保存当前会话默认前景、背景与16色色表，再临时使用黑底白字和统一强调色；正常结束、业务失败及可捕获中断后恢复。用户运行中自行改动的颜色保留并提示，不修改用户主题、共享 Profile、注册表或全局策略。快照不包含进入前任意叠加的临时文字样式。非控制台、重定向、`NO_COLOR`、Sourcetree 及无法可靠保存／恢复颜色的环境保持原状态或降级为纯文本。

> 强制结束进程或终端崩溃无法保证自动恢复。恢复失败时保留并提示本轮 `%TEMP%\JobsTerminalStyle-<PID>-*.ps1` 恢复脚本，需在原控制台核对后运行；不要通过重置用户配置恢复。`-ExecutionPolicy Bypass` 如被入口使用，仅作用于本次子进程，不持久修改策略。

> 验证范围：已完成 PowerShell 语法、参数／退出与隔离生命周期核验；Windows 原生控制台的显示、按键与 `Ctrl+C` 实机验证尚未完成。

<!-- JOBS_TERMINAL_STYLE_V1:END -->

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

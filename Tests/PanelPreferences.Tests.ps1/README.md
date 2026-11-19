# 安装面板主题与语言回归

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行与覆盖](#jobs-toc-heading-2)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

[PanelPreferences.Tests.ps1](./PanelPreferences.Tests.ps1) 只使用系统临时目录中的偏好文件，不注册、安装或卸载扩展，不改真实用户偏好、系统主题或显示语言。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行与覆盖 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 从当前目录运行：

  ```powershell
  pwsh -NoLogo -NoProfile -File ./PanelPreferences.Tests.ps1
  ```

- [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) 5.1 图形桌面使用 `powershell.exe -NoProfile -STA -File .\PanelPreferences.Tests.ps1`，可额外验证原生控件的十语言右上角工具组、窗口缩放与窄窗布局、安装位置与自动清理复选框紧邻、红色清理按钮位于底部、切换时保留活动任务与勾选、旧日志重着色和文本选择。
- 跨平台覆盖默认值、全部偏好组合保存与替换、未知或损坏配置、UI 语言映射、主题覆盖、右上角布局的不同 DPI 与窄窗回退计算、安装位置与自动清理复选框紧邻及窄窗水平滚动计算、当前功能清单英文资源、动态进度及中文路径保护，以及总面板、模板和独立包模块的字节一致、BOM 和语法。
- 通过输出 `PASS` 和断言数量；Windows 控件分支未运行时输出 `SKIP`。真实 Windows 10 / 11 的系统主题与显示语言变更、原生菜单安装以及不同 DPI 桌面仍须单独验收。
- 测试失败返回非零状态，临时偏好在结束时清理；不会修改或清除用户实际偏好。



<!-- JOBS_TERMINAL_STYLE_V1:BEGIN -->

> Windows 终端配色保护：支持完整颜色查询的交互控制台会先保存当前会话默认前景、背景与16色色表，再临时使用黑底白字和统一强调色；正常结束、业务失败及可捕获中断后恢复。用户运行中自行改动的颜色保留并提示，不修改用户主题、共享 Profile、注册表或全局策略。快照不包含进入前任意叠加的临时文字样式。非控制台、重定向、`NO_COLOR`、Sourcetree 及无法可靠保存／恢复颜色的环境保持原状态或降级为纯文本。

> 强制结束进程或终端崩溃无法保证自动恢复。恢复失败时保留并提示本轮 `%TEMP%\JobsTerminalStyle-<PID>-*.ps1` 恢复脚本，需在原控制台核对后运行；不要通过重置用户配置恢复。`-ExecutionPolicy Bypass` 如被入口使用，仅作用于本次子进程，不持久修改策略。

> 验证范围：已完成 PowerShell 语法、参数／退出与隔离生命周期核验；Windows 原生控制台的显示、按键与 `Ctrl+C` 实机验证尚未完成。

<!-- JOBS_TERMINAL_STYLE_V1:END -->

完整词库隔离回归逐项覆盖七种新增语言的 366 个英文键、原三语兼容、动态占位、大小写仅差异的键、系统语种映射、全部偏好组合和藏文字体回退；原生条件分支覆盖十语言长文案与切换后勾选、日志和状态列。

卡片布局补充验证覆盖默认 Flutter 右列、同列／跨列排序、空列回移、高卡片标题前后落点、独立范围隔离、真实 JSON 整数读写与坏布局回退；顶部自动清理紧邻部署选择，红色清理入口在两种操作的底部主按钮右侧。Windows 原生拖放、居中文本绘制与 DPI 字体仍需在 Windows 运行此套件核对。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

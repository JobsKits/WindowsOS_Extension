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

- [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) 5.1 图形桌面使用 `powershell.exe -NoProfile -STA -File .\PanelPreferences.Tests.ps1`，可额外验证原生控件的三语右上角工具组、窗口缩放与窄窗布局、安装位置与两个清理控件同排、切换时保留活动任务与勾选、旧日志重着色和文本选择。
- 跨平台覆盖默认值、全部偏好组合保存与替换、未知或损坏配置、UI 语言映射、主题覆盖、右上角布局的不同 DPI 与窄窗回退计算、安装位置与清理控件同排及窄窗水平滚动计算、当前功能清单英文资源、动态进度及中文路径保护，以及总面板、模板和独立包模块的字节一致、BOM 和语法。
- 通过输出 `PASS` 和断言数量；Windows 控件分支未运行时输出 `SKIP`。真实 Windows 10 / 11 的系统主题与显示语言变更、原生菜单安装以及不同 DPI 桌面仍须单独验收。
- 测试失败返回非零状态，临时偏好在结束时清理；不会修改或清除用户实际偏好。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

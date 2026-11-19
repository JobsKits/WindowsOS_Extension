# 管理面板整行选择回归

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行与覆盖](#jobs-toc-heading-2)
- [二、实现与验证边界](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

[PanelRowSelection.Tests.ps1](./PanelRowSelection.Tests.ps1) 以合成控件和事件序列运行生产 [Installer.psm1](../../Scripts/Installer.psm1) 的行命中、按下／移动／抬起控制器及模块作用域回调，不安装、卸载、清理或操作真实用户窗口。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行与覆盖 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

在本目录运行：

```powershell
pwsh -NoLogo -NoProfile -File ./PanelRowSelection.Tests.ps1
```

- 实际装配生产回调后，图标、标题、普通状态及行内左右空白／间隙均只切换一个原复选框；同一候选先消费再通知，重复或父级抬起不二次切换。
- 原 CheckBox 保持原生 AutoCheck、Tab／Space 与 CheckedChanged；新增逻辑不在其 MouseUp 上再做切换。
- 链接区域非空的失败状态和独立按钮保留自身动作；忙碌时日志仍可读，普通行选择锁定。
- GroupBox 的平铺子控件按当前实际行边界命中，组头、组尾、边界外和相邻行不混淆；不把整个大分组当作某行。
- 拖动阈值按 DPI 缩放；移动后回到原点、离开、滚轮、滚动事件、位置快照变化、失焦、跨源释放，以及按下后变忙／禁用／进入分组拖动均不误选。
- 生产回调返回后仍可调用所属模块；38 份主面板、模板与随包副本保持同字节。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、实现与验证边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

每行仍由 CheckBox、图标 Label、标题 Label 和状态 LinkLabel 平铺组成，不增加覆盖整行的透明按钮或全局输入钩子。只有完整左键序列、当前同一来源／行、滚动位置未变且复选框可用时才切换。失败链接及独立动作优先；扩展区域沿用原生鼠标或触控晋升事件，不截获触控消息、不重写滚动距离。

点击只修改本窗口原复选框，默认值、持久化、主题、语言、托盘及后台任务协议保持原规则。所有新增回调均在本包模块内运行，不依赖源码父工程、兄弟包或外部资源。

测试输出 PASS 和断言数量，失败返回非零。合成控件不能代替 Windows PowerShell 5.1、真实 WinForms 命中、屏幕缩放、键盘、鼠标、触屏和精确触摸板验收；原生条件验证可在 Windows 的 [SelectionPanel.Tests.ps1](../SelectionPanel.Tests.ps1/SelectionPanel.Tests.ps1) 运行（STA）。源码和事件边界已验证不代表原生设备已验收，普通测试不为验收真实注册菜单或运行安装器。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

# 管理面板关闭与托盘回归

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行与覆盖](#jobs-toc-heading-2)
- [二、默认值、持久化与边界](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

[PanelTray.Tests.ps1](./PanelTray.Tests.ps1) 执行真实 [Installer.psm1](../../Scripts/Installer.psm1) 的任务保全、关闭选择、托盘恢复、事件桥接和释放控制流，只替换窗口、通知区域与消息循环的原生边界，不启动安装、卸载、清理或业务进程。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行与覆盖 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

在本目录运行：

```powershell
pwsh -NoLogo -NoProfile -File ./PanelTray.Tests.ps1
```

目标管理入口要求 Windows PowerShell 5.1 Desktop 和 STA，由 Manage.vbs 或 powershell.exe -STA 启动。测试在 Windows 也使用内存关闭控制器；非 Windows 额外编译最小 WinForms 边界，执行生产 NotifyIcon 事件装配及 [Application.Run](https://learn.microsoft.com/en-us/dotnet/api/system.windows.forms.application.run) 包装流程。

- 安装、卸载、构建清理忙碌时直接后台，不弹选择、不停止 Timer；Started 不作为持续忙碌标记。
- 空闲选择托盘／完全退出／保留原窗、重复关闭、防重入、选择期间任务出现，以及进程未退／输出未排空／队列未空／状态不可读的保守保护。
- 初始化返回后的托盘双击、恢复、退出、菜单打开事件仍可访问所属模块；禁用出口被程序触发也复检忙碌状态，打开菜单即时刷新状态。
- 生产 Complete 执行后继续隐藏驻留；明确空闲退出后 Show 的 finally 才释放资源；旧选择模式仍返回同一明确确认结果，普通关闭返回 null，外层 CLI 退出合同保留。
- 自有图标克隆与通知组件恰好释放一次，共享原图标保留；恢复复用原窗口与勾选；通知文字不超过旧 API 的 63 个 UTF16 字符且不切断代理对。
- 实际选择框呈现函数逐白天／黑夜／跟随系统及十语言绑定标题、说明和动作；自有字体克隆随语言替换，不误释放父窗字体，原生绘色边界单独替换。
- 新增九项文案十语言齐全、当前状态原文保留、38 份面板同字节。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、默认值、持久化与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

默认窗口可见。空闲关闭每次询问，回车默认托盘，Esc 或关闭选择框保留原窗；任务中直接后台，完工不自动退出或弹出窗口。首次后台后通知图标保留，恢复始终复用同一窗口。状态与退出门禁每秒及打开菜单时刷新；任务期间底部关闭按钮和 Esc 同样转后台。托盘不可用时保留可见窗口，不新增强杀任务出口。

主题和语言沿用原用户偏好，关闭选择框跟随当前外观、字体及高对比度；关闭选择和隐藏状态不持久化，不增开机自启。真正退出释放 UI 资源，保留完整纯文本日志及已保存偏好。图标来自当前 Form.Icon 的自有克隆，不依赖外部素材、网络、父工程或兄弟包。

测试输出 PASS 和断言数，失败返回非零。内存 WinForms 边界不能代替真实 Windows 通知区域、消息循环、Explorer 重启、键鼠、DPI、多屏、三主题十语言视觉及 PowerShell 5.1 原生验收；这些须目标桌面另验。强制结束进程、注销、关机或断电不属于普通关闭门禁可保证的存活范围。测试不改系统外观，不触碰正在运行的窗口，不部署或注册菜单。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

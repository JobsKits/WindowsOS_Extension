# 安装面板彩色日志回归

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行与覆盖](#jobs-toc-heading-2)
- [二、验证边界](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

[PanelLog.Tests.ps1](./PanelLog.Tests.ps1) 验证真实总面板 [Installer.psm1](../../Scripts/Installer.psm1) 的解析、配色、缓冲区及追加控制流，不安装或卸载菜单，不执行真实清理，不写真实用户偏好。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行与覆盖 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

从本目录运行：

```powershell
pwsh -NoLogo -NoProfile -File ./PanelLog.Tests.ps1
```

Windows 图形桌面以 `powershell.exe -NoProfile -STA -File .\PanelLog.Tests.ps1` 额外使用真实 WinForms 控件；其它系统提取并编译生产 C# View 方法，只将 WinForms／HWND 边界替换为内存控件，不能代表真实窗口滚动验证。

- 覆盖 ANSI 16／256／RGB 前景、分块控制序列、独立标准输出／错误流、OSC／DCS／APC／PM／C1 载荷过滤、正文路径和 Unicode 保留。 标准 `file:line(:column): warning` 和 `file(line,column): warning` 诊断即使走标准错误流也保持警告色；任意正文中的 warning 字词不触发该规则。
- 验证明暗两套日志背景、正文和语义／ANSI 前景对比度不低于 4.5；高对比度模式采用系统窗口色。 以只读系统采样夹具验证高对比度开关／系统色变更使 timer 失效，并在追加前同轮更新已有背景、正文与新字颜色，不修改真实系统设置。
- 验证生产追加保留文本选区、手动导航暂停追尾、内部追加不误判为用户导航、所有消息仍传给控件基类；主题反复切换不清空正文与选区。
- 验证跨块换行、可见缓冲区限长、完整纯文本日志及 38 份总面板／公共模板／独立副本同字节。
- 直接运行生产完成与停止读取控制流，验证最终成功／失败／停止汇总显式传递对应级别，保留原正文、退出码、日志条数及业务收尾；无需卸载不冒充成功。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、验证边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

跨平台结果不覆盖 user32 原生视口恢复、鼠标／触摸板硬件输入、剪贴板、Windows PowerShell 5.1 编译或系统外观变更；这些须在 Windows 10／11 图形桌面另行核对。原生控件保存像素滚动位置，并按 [EM_GETSCROLLPOS 官方说明](https://learn.microsoft.com/en-us/windows/win32/controls/em-getscrollpos)的 16 位像素限制，为长日志补充首个可见行锚点。日志不带富文本到剪贴板，不执行控制载荷；本次完整纯文本日志可由原复制入口或外部文本工具读取。

测试输出 `PASS` 与断言数，失败返回非零；临时会话日志在结束时清除。主题和语言仍沿用原偏好文件；自动滚动、选区及阅读位置仅属于当前窗口。管理面板同源范围包含 `Scripts/Installer.psm1`、`Scripts/SelectionPanel.psm1`、`Infrastructure/SelectionPanel.psm1` 和 35 个独立包的 `Scripts/SelectionPanel.psm1`。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

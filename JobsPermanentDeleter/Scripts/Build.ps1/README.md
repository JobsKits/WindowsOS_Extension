# Build.ps1 · 原生永久删除菜单

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

从完整功能目录运行，只准备 DLL，不登记菜单：

```powershell
powershell.exe -NoLogo -NoProfile -File .\Scripts\Build.ps1\Build.ps1 -OutputRoot .\work\native
```

[Build.ps1](./Build.ps1) 从自身定位源码，按当前 [**Explorer**](https://support.microsoft.com/windows) 原生架构输出 `JobsPermanentDeleterContextMenu.dll`。x64／ARM64 优先验证 `Dist/BuildVerification.json` 的功能 ID、固定五项源码、DLL 摘要与 PE 架构，复制后仍比对同次回执的预期摘要。不同源／缺产物／x86 改走现有 [**MSVC**](https://learn.microsoft.com/cpp/build/)／[**Windows**](https://www.microsoft.com/windows) SDK；缺工具明确失败，不联网安装编译器。链接 Shell、COM、User32、Advapi32 和 Gdi32 系统库。

随包两架构成品通过 [**MacOS**](https://www.apple.com/macos/) 的 [**Zig**](https://ziglang.org/) 0.15.2 交叉编译，构建依据及摘要随[回执](../../Dist/BuildVerification.json)交付；不代表 Windows 原生加载或实际点按已验。系统工具链构建路线仍保留用于后续修改源码。完整运行包见[功能说明](../../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

# Build.ps1 · 构建原生隐藏属性菜单

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

从完整功能目录运行，只构建不登记：

```powershell
powershell.exe -NoLogo -NoProfile -File .\Scripts\Build.ps1\Build.ps1 -OutputRoot .\work\native
```

[Build.ps1](./Build.ps1) 从自身位置解析源码，输出 `JobsFileVisibilityContextMenu.dll`；匹配当前 Explorer 架构并检查 MSVC／Windows SDK。依赖系统库含 Shell、COM、User32 和 Advapi32；不联网安装工具。安装面板先构建，再进入注册事务。产物只在目标 Windows 工具链构建，MacOS 隔离核心夹具不等于 DLL 构建。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

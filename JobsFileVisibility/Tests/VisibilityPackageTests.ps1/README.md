# VisibilityPackageTests.ps1 · 独立发布夹具

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

从功能目录运行：

```powershell
pwsh -NoLogo -NoProfile -File .\Tests\VisibilityPackageTests.ps1\VisibilityPackageTests.ps1
```

本测试在系统临时目录复制、改名并发布当前独立包，检查三键范围、平铺入口、源码与发布摘要一致、十语及语法；结束只删除本轮临时副本。既有 Windows 5.1 安装运行与原生桌面另验。本机 PowerShell 默认缓存路径有既有失效链接，测试通过进程级 `XDG_CACHE_HOME`／`XDG_CONFIG_HOME`／`XDG_DATA_HOME` 定向临时路径执行，未改用户缓存或持久配置。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

# 鸿蒙准备的自包含工具快照

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

此目录复用本仓 Jobs 维护的 SDK 管理器、下载路由与 CLT 工具核心，随独立运行包和聚合包完整运输，运行时不查找兄弟工程。`SourceSnapshots.json` 记录来源、哈希和提取函数。

只调用正式 tag / commit、缓存安装、精确备份与绑定发布函数，不调用 SDK 管理器交互总入口或全局版本切换。CLT 复用现有校验下载逻辑，仅准备工具，不执行模拟器镜像、AVD 创建或启动。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

# 鸿蒙当前运行准备隔离回归

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

执行 `pwsh -NoProfile -File Tests/HarmonyRunPrepare.Tests.ps1/HarmonyRunPrepare.Tests.ps1`。可用 `-Dart`、`-Packages` 指向现有同源 SDK，额外验证真实 YAML / pub_semver 约束解析。

测试复用真实编排、正式 tag 解析、SDK 管理器桥接、原子平台发布与原设备匹配；外部获取、命令执行与用户项目只使用临时目录和假边界。覆盖许可取消、插件未适配、commit 改变、复检失败和设备错配，确保失败不能运行应用；不进行真实下载、绑定或安装。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

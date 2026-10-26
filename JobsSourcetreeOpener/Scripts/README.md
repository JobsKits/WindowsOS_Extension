# Jobs Sourcetree 打开源码

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

完整用法见[功能说明](../README.md)。`ContextMenu.cpp` 使用 `GitRepository.h` 检查普通工作树，再用 `SourcetreeInstallation.h` 检查实际程序；菜单构建与点击都重新检测，未安装时不会插入叶子或空父菜单。`Action.psm1` 复核最近仓库和安装位置，启动 Sourcetree；不会拉取、提交或推送。

`Build.ps1` 只编译本包 DLL，不安装编译器、不注册。`ContextMenu.def` 限定 COM 导出；`PackageInstaller.psm1` 管理独立 release、构建和注册事务。`Invoke.ps1`、`Manage.ps1`、`Common.psm1` 与维护模板逐字一致，运行只依赖本包副本。新项与 Git 回退 handler 通过已有 HMENU 共享 Git 父菜单；新项固定插在首位。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

# Jobs Git 回退源码

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)

</details>
<!-- jobs-toc:end -->

## 🔥 <span id="前言">前言</span>

完整使用说明见[功能 README](../README.md)。`ContextMenu.cpp` + `GitRepository.h` 负责只读菜单过滤；`Action.psm1` 负责真实 Git 复核、fzf 六种回退和危险确认。`Invoke.ps1`、`Common.psm1`、`Manage.ps1` 与仓库基础模板保持一致；本包 `PackageInstaller.psm1` 管理独立原生 COM 构建与注册事务，安装前构建失败不注册菜单。

`Build.ps1` 仅编译本包 DLL，不安装编译器或注册；`ContextMenu.def` 只导出 COM 入口。菜单点击用 Windows argv 引用直接打开独立 PowerShell 控制台，不经 CMD 或解释用户路径。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

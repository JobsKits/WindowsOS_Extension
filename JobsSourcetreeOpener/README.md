# Jobs 用 [**Sourcetree**](https://www.sourcetreeapp.com/) 打开

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、安装与卸载](#installation)
- [二、打开行为与验证](#behavior)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

**最低支持系统：** 目标为 [**Windows**](https://www.microsoft.com/windows) 10 x64、Windows PowerShell 5.1 Desktop；最低 build 和真实 Explorer 验收仍待验证。Windows 11 使用“显示更多选项”或 `Shift+F10`。入口为 **🌿 Git操作 → 🌳 用 Sourcetree 打开**，位于 Git 分组第一项。

只有已安装 Sourcetree 且选中普通本地 [**Git**](https://git-scm.com/) 工作树目录时显示；未安装、注册信息残留或程序文件已移除时隐藏。菜单每次构建重新检测，无需重新安装扩展；点击后复核，再打开最近的内层仓库。普通目录、裸仓、Git 元数据内部、文件、多选、链接和网络目录隐藏。

## 一、<span id="installation">安装与卸载</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 双击 [Install.cmd](./Install.cmd)，或在[总面板](../README.md#installation)勾选本项；卸载使用 [Uninstall.cmd](./Uninstall.cmd)。只管理当前用户本包的 COM 注册、运行版本、日志与状态，不运行 Git 写操作、不自动安装 Sourcetree。
- 原生动态菜单需要现有 [**Visual Studio Build Tools**](https://visualstudio.microsoft.com/visual-cpp-build-tools/) 的 C++ 桌面工作负载、MSVC、Windows SDK 及匹配 Explorer 的架构工具。缺少时注册前停止，不联网下载。
- 检测当前用户及系统 `App Paths\SourceTree.exe`，再检测 `LocalAppData`、`ProgramFiles` 和 `ProgramFiles(x86)` 下 `SourceTree/SourceTree.exe`、`Atlassian/SourceTree/SourceTree.exe`。自定义位置需由应用安装器登记 App Paths；路径必须实际存在且指向普通 `SourceTree.exe` 文件。
- 与 Git 回退包复用已创建的 Git 父菜单；单独安装本包也可展示完整分组，应用缺失时不创建空父菜单。其它包的安装选择保持独立。

## 二、<span id="behavior">打开行为与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

菜单只读取本地元数据，不在 Explorer 内启动 Git、PowerShell 或 CLR。点击后在独立后台进程中复检目录和安装路径，以数组语义引用参数启动 `SourceTree.exe log -f <仓库根目录>`；支持嵌套仓库、子模块 gitfile 与 worktree。参数来源参考 [Atlassian Windows CLI 记录](https://jira.atlassian.com/browse/SRCTREEWIN-14472)，Sourcetree 自身的登录、首次配置及版本行为由应用负责。

独立包可直接复制使用，运行时不依赖总仓或其它包。日志和安装快照归当前用户 `Jobs/WindowsExtension/extensions/open-sourcetree` 的 `logs/`、`backups/`；卸载保留这些文件及禁用状态。安装和卸载不修改业务仓库。

[PowerShell 隔离回归](../Tests/SourcetreeOpener.Tests.ps1)验证未安装、安装后、点击前卸载、内层仓库、畸形边界与原始路径传递；[便携原生探针](../Tests/SourcetreeInstallationProbe.cpp)验证安装缺失、残留候选及程序名。隔离检查不启动真实应用；MSVC 构建、Explorer 实际显隐和真实 Sourcetree 打开仍需 Windows 验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

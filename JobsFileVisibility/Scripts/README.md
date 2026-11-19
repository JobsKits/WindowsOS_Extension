# 所选项目隐藏属性 · 实现入口

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

| 文件 | 职责 |
| --- | --- |
| [ContextMenu.cpp](./ContextMenu.cpp) | 原生 CF_HDROP 多选菜单、身份快照、错误汇总；COM 异常转 HRESULT，选择最多 128 项。 |
| [FileVisibility.h](./FileVisibility.h) | 仅 Hidden 位的句柄读写；拒绝根／链接／设备，保留属性与时间，写后身份核对及 Shell 通知。 |
| [FileVisibilityText.h](./FileVisibilityText.h)、[VisibilityRuntime.h](./VisibilityRuntime.h) | 十语文案、当前用户语言偏好及当前 DLL 精确注册归属核验。 |
| [Build.ps1](./Build.ps1/README.md)、[ContextMenu.def](./ContextMenu.def) | 使用本机 MSVC／SDK 编译 DLL 及同一业务导出，不注册。 |
| [Action.psm1](./Action.psm1)、[Invoke.ps1](./Invoke.ps1/README.md) | 显式 Hide／Show CLI 调同 DLL，不另写一套属性修改逻辑。 |
| [Manage.ps1](./Manage.ps1/README.md)、[ManagementWorker.ps1](./ManagementWorker.ps1/README.md) | 当前包独立安装／卸载面板与后台事务。 |
| [PackageInstaller.psm1](./PackageInstaller.psm1) | 自包含 release、构建、三键注册计划与本包回滚／清理。 |
| [SelectionPanel.psm1](./SelectionPanel.psm1)、[Common.psm1](./Common.psm1) | 现行完整十语／主题面板与本包基础设施。 |

源码 `.ps1` 使用同名包装，发布复制时压平；所有运行资源按自身包目录解析。包内无需父仓、其它功能业务、网络 API 或第三方解释器。安装／卸载影响和真实验收边界见[功能说明](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

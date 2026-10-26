# `JobsAndroidStudioOpener Scripts`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、文件与职责](#jobs-toc-heading-2)
- [二、调用与边界](#jobs-toc-heading-3)
- [三、日志与验证](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

负责“用 Android Studio 打开项目。”的业务与独立包安装基础设施。用户使用上一级 Install.cmd / Uninstall.cmd，运行条件与菜单对象见 [功能 README](../README.md)。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、文件与职责 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 实际职责 |
| --- | --- |
| [Action.psm1](./Action.psm1) | 复核非空且为 Android / Flutter 根目录后查找 Android Studio 并打开；缺 IDE 提示官方页面，不安装 IDE。 |
| `ContextMenu.cpp` / `ContextMenu.def` / `Build.ps1` | 菜单生成和点击时先做非空 / 项目门禁，MSVC 构建本包独立 DLL。 |
| `IDEProject.h` / `FlutterProject.h` | 原生只读识别核心，不加载 CLR、PowerShell 或执行项目代码。 |
| `IDEProject.cs` / `ProjectEligibility.ps1` | 后台同义识别；Flutter YAML 解析与现有运行包一致。 |
| [Invoke.ps1](./Invoke.ps1) | 菜单动作调度，读取本包目标并调用 Action，保存错误和结果。 |
| [Manage.ps1](./Manage.ps1) | `-Mode Install / Uninstall` 的本包入口，按默认取消窗口确认安装或卸载。 |
| [PackageInstaller.psm1](./PackageInstaller.psm1) | 声明校验、独立版本复制 / 哈希、菜单快照、状态提交与失败回滚。 |
| [Common.psm1](./Common.psm1) | 本包路径、目标、外部进程、日志与公共辅助；导入不运行业务。 |

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、调用与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

业务调度入口为 `Invoke-JobsFeature -Target <目标>`，由本包 Invoke.ps1 调用；本目录不是另一份总安装器。Action 中实现的具名功能包括：`Get-JobsAndroidStudio`、`Invoke-JobsFeature`。

安装管理要求系统 Windows PowerShell Desktop 5.1、STA、图形桌面及已有 MSVC / Windows SDK。脚本自定位本包路径；安装只登记本包原生处理器、精确清退本包旧静态入口并保存状态，卸载保留运行版本、日志、备份、工具及停用记录，不自动卸载其它包。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、日志与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

业务修改范围以 Action 的所需功能为准，不能把安装确认当业务操作同意。日志和快照位于当前用户本包运行目录，由入口输出实际位置；详情见 [功能说明](../README.md)。非空 / 项目资格见上级 README；菜单与后台分别复核，目录变空或类型变化时停止。隔离测试使用临时目录和替身启动器，不执行真实安装、注册表写入或打开 IDE。两包识别核心独立内嵌且同字节维护，修改后同步另一包并运行 IDEProject 回归。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

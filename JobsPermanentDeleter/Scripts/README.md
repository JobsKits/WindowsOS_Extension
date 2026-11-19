# 永久删除 · 源码与运行资源

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

| 文件／目录 | 职责 |
| --- | --- |
| `ContextMenu.cpp` / `ContextMenu.def` | 原生 COM 菜单、完整多选数据及同一删除确认门禁；不拼接 Shell 命令。 |
| `PermanentDelete.h` | 路径与真实句柄路径校验、祖先固定、全树预检和按句柄后序删除。 |
| `DeleteDialog.h` / `DeleteText.h` | 左红确认右蓝取消、十语言、三主题及错误说明。 |
| `Build.ps1/` / `Prebuilt.psm1` | 核对源摘要／产物摘要／架构，复用成品或本机 MSVC 构建。 |
| `PackageInstaller.psm1` | 本包 release、事务登记、精确卸载及构建清理；包含固定成品和回执。 |
| `SelectionPanel.psm1` / `ManagementWorker.ps1/` / `Manage.ps1/` | 独立管理 GUI、后台任务、托盘、十语、日志及状态。 |
| `Invoke.ps1/` / `Action.psm1` | 维护 CLI，仍调用原生二次确认框，没有 force／quiet 删除参数。 |
| `Common.psm1` | 本包路径与通用环境；不包含其它功能业务。 |

源码 [**PowerShell**](https://learn.microsoft.com/powershell/) 脚本使用同名包装，发布时按显式标记压平；原生源、资源、入口与成品在同一独立包内，以实际脚本位置解析。每次调用只在明确确认后对所选对象执行本轮操作。安装／卸载、日志与验证边界见[功能说明](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

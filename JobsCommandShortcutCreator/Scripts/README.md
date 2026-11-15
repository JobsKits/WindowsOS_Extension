# 脚本快捷入口扩展 · 源码与管理脚本

此目录属于独立功能 `command-shortcut-create`，由上一级 [Manage.cmd](../Manage.cmd) / [Manage.vbs](../Manage.vbs) 打开 GUI。完整使用方式与风险见 [功能说明](../README.md)。

| 文件 | 职责 |
| --- | --- |
| `Manage.ps1`、`ManagementWorker.ps1` | 功能限定的 GUI管理、后台任务、逐项状态与日志 |
| `SelectionPanel.psm1` | 十语 / 三主题管理面板、空选门禁、后台状态 |
| `PackageInstaller.psm1` | 本项原生 DLL 构建、独立运行副本、注册表所有权、备份与卸载 |
| `Common.psm1` | 本包路径、参数引用、日志及通用进程支持 |
| `Build.ps1` | 使用 MSVC / Windows SDK 编译当前架构 DLL，本身不注册菜单 |
| `ContextMenu.cpp`、`ContextMenu.def` | 原生 COM菜单、单选快照、十语标题及明确脚本投递 |
| `CommandShortcutTarget.h` | `.cmd` / `.bat` / `.ps1` 同名脚本包判定，拒绝重解析点 |
| `Invoke.ps1` | 校验本项已安装且启用后加载唯一业务模块 |
| `Action.psm1` | 只调用本包创建入口对话框 |
| `CommandShortcut.ps1` | 目录 / 名称检查、相对入口生成、排他发布、十语与主题切换 |

业务加载不会执行包内原脚本。只有用户在创建对话框点击“创建”才写同级入口；管理操作不生成业务入口。所有路径从当前脚本或运行副本解析，不硬编码源码所在目录。

安装依赖 Windows PowerShell 5.1、WinForms、MSVC 与 Windows SDK；业务生成仅用系统 PowerShell / .NET。运行副本、备份和日志位于当前用户本地应用数据目录下 `Jobs/WindowsExtension/command-shortcut-create`，错误先查看面板和该功能日志。卸载按本项所有权撤回登记，不删除已生成入口及原始脚本。

# `JobsPermanentDeleter` · 永久删除

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

选中普通文件或文件夹，右键选择 **永久删除（不进回收站）**。二次确认框完整列出本轮所选根路径及含子项总数；**左侧“确认”红底白字，右侧“取消”蓝底白字**。焦点和默认操作为取消；普通回车、Esc 或关闭窗口不执行默认删除。主动将焦点切到确认按钮并激活，或点击确认，才执行删除。

| 场景 | 实际行为 |
| --- | --- |
| 单选／多选 | 最多 128 个根目标；父子重叠选择合并为外层目录，重复项去重。 |
| 文件夹 | 确认前完整预检并持有全树句柄；确认后按子项到目录的顺序直接删除。 |
| 取消／关闭 | 仅释放句柄，不删除、不修改文件属性，不进入回收站。 |
| 新增内容 | 确认期间新增的子项不在计划中，不会删除；原目录因此无法删除时如实报告。 |
| 部分失败 | 停止后续操作，显示已删除数量、失败路径及 Win32 错误码；已删除内容不能撤销。 |
| 权限／占用／只读 | 无法安全预检即整单拒绝；不自动提权，不清除只读属性，不强制关闭占用程序。 |

**范围与限制：** 只支持普通本地磁盘绝对路径，每条规范路径少于 248 字符，全树最多 4096 个节点、递归层级最多 64。拒绝驱动器根目录、[**Windows**](https://www.microsoft.com/windows)／Program Files／ProgramData 树、当前用户配置目录本身及其祖先、设备／扩展命名空间、网络共享、短文件名与 SUBST 别名。选择对象、已有祖先或树内含任意重解析点／符号链接／联接时整单拒绝，不遍历链接。目标目录及文件会在确认期间保持打开并限制写入／改名；不将未知新增内容追加入原计划。失败后关闭对话框，再修正原因并重新选择。

## 一、<span id="management">安装 / 更新与卸载</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

双击 [Manage.cmd](./Manage.cmd) 打开本功能独立面板，或在平台总面板选择“永久删除（不进回收站）”。默认空选，支持安装／更新、卸载与两条既有部署路线；取消不部署。完整目录可复制、改名，从任意工作目录启动。面板含十语言、白天／黑夜／跟随系统、托盘驻留、执行状态与日志；删除确认框同样提供十语言和三种主题。确认框初值读取当前用户的面板偏好，临时切换只在当前对话框生效，不保存删除授权。

Windows 10 / 11 图形桌面使用系统 Windows [**PowerShell**](https://learn.microsoft.com/powershell/) 5.1 Desktop；Windows 11 从“显示更多选项”的经典右键菜单使用。本包独立 ID `permanent-delete`，CLSID `{79022A9C-59CF-485A-90D8-67C67EE7CE33}`，仅注册当前用户的 `*` 文件及 `Directory` 目录 handler，不注册背景或驱动器菜单。安装前核对完整 release，再事务登记；卸载只关闭本功能，不恢复已经删除的文件。旧缓存菜单及 CLI 在精确注册归属失效后拒绝删除。

## 二、<span id="delivery">完整源码与可运行成品</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 交付项 | 入口 |
| --- | --- |
| 可修改业务、确认框、十语与安装源码 | [Scripts](./Scripts/README.md) |
| 管理运行入口 | [Manage.cmd](./Manage.cmd) → 包内 WScript／PowerShell GUI |
| Windows 原生 DLL | [x64](./Dist/x64/JobsPermanentDeleter.dll) ／ [ARM64](./Dist/arm64/JobsPermanentDeleter.dll) |
| 自包含运行分发包 | [JobsPermanentDeleter-Windows.zip](./Dist/JobsPermanentDeleter-Windows.zip) |
| 源码与产物摘要 | [BuildVerification.json](./Dist/BuildVerification.json) |
| 可复现构建入口 | [Build.ps1](./Scripts/Build.ps1/README.md) |
| 隔离回归 | [Tests](./Tests/README.md) |

安装优先核对随包预编译产物：固定五项 native 源码 SHA-256、功能 ID、DLL 摘要与 PE 架构全部匹配才部署，复制后再次比对同次回执摘要；源码变化、成品缺失／不符或 x86 则尝试本机 [**MSVC**](https://learn.microsoft.com/cpp/build/)／Windows SDK 构建。缺少编译器明确失败，不自动安装工具或留下半套菜单。运行时不依赖开发机、父仓、其它功能、在线翻译或额外语言解释器。

当前在 [**MacOS**](https://www.apple.com/macos/) 交叉构建 x64／ARM64 PE DLL，并验证导出与依赖、生产核心边界夹具、PowerShell 7 的复制改名发布／十语／回执变异检查。**Windows 原生加载、PowerShell 5.1、MSVC 编译、确认框实际点按与 [**Explorer**](https://support.microsoft.com/windows) 注册尚待 Windows 目标机验收**；未安装菜单，未删除用户真实文件。完整状态见项目根[永久删除资产盘点](../../项目相关报告/永久删除资产盘点.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

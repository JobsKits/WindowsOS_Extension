# `JobsFileHasher` · 查看文件指纹 Hash

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、安装 / 更新与卸载](#jobs-toc-heading-2)
- [二、计算与剪贴板](#jobs-toc-heading-3)
- [三、文件与验证](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

右键任意一个普通文件 → **🔎 查看文件指纹 Hash（SHA-256）**，在新开的 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) 窗口显示文件路径、字节数和 SHA-256，同时将 **64 位小写十六进制纯摘要**复制到系统剪贴板，不含文件名、标签或换行。空文件、无扩展名、二进制和大文件都支持；计算采用 .NET 流式 SHA-256，不把整个文件装入内存，不执行文件、不修改内容。

| 操作 / 条件 | 结果 |
| --- | --- |
| 单个普通文件 | 提供菜单；点击后重新核验并计算、显示、复制。 |
| 目录、背景、多选、链接或设备 | 菜单隐藏；运行端拒绝不适用对象。 |
| 路径含中文、空格、`&`、`%`、单引号或方括号 | 原生 argv 与 LiteralPath 传输，不拼入 CMD 命令。 |
| 无法读取、写共享冲突、目标消失 | 显示错误，不更新剪贴板；不复制上次或不完整摘要。 |
| 剪贴板被占用或不可用 | 有限重试后明确失败；本次摘要仍显示在终端可手动复制。 |
| 大文件计算中 | 终端提示正在计算，可 `Ctrl+C` 中止；完成后提示回车关闭。 |

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、安装 / 更新与卸载 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

完整 `JobsFileHasher` 目录可以独立复制。双击 [Manage.cmd](./Manage.cmd) 或 [Manage.vbs](./Manage.vbs/Manage.vbs)，在本包图形面板选择安装 / 更新或卸载；默认空选，取消不执行。总面板也可单独选择 `file-hash`，不影响查看正文或权限菜单。面板沿用已有语言与黑夜 / 白天 / 跟随系统设置，管理日志可复制，安装期间支持事务完成后的合作式停止。

最低目标为 Windows 10 x64，运行使用系统 PowerShell 5.1 Desktop；Windows 11 使用“显示更多选项”或 `Shift+F10` 经典菜单。原生构建依赖已安装的 [**MSVC / Windows SDK**](https://visualstudio.microsoft.com/visual-cpp-build-tools/)，匹配 Explorer 架构；缺编译器明确失败，不联网安装、不提权。x86 / ARM64、PowerShell 5.1、MSVC 和 Explorer 实机兼容另行验收。

默认程序位置为 `%LOCALAPPDATA%\Jobs\WindowsExtension\extensions\file-hash`，可在源码面板选择本包 `work\WindowsExtension` 路线。运行副本绑定自己的 `deployment.json`，不依赖原源码路径、启动工作目录或管理器环境变量。默认安装位置支持本轮自动清理和独立清理专用编译产物，保留已安装 DLL、脚本、状态与注册。

安装先复制并校验独立 release、编译 DLL，再事务登记当前用户的文件 handler 与 CLSID：`HKCU\Software\Classes\*\shellex\ContextMenuHandlers\Jobs.WindowsExtension.file-hash`、`HKCU\Software\Classes\CLSID\{CD2D9483-9017-4717-96E3-B7153427F0C6}`。失败精确恢复本包状态；卸载仅关闭本包菜单，保留日志、备份和运行版本，用户文件及其它功能不变。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、计算与剪贴板 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

文件流只授予读共享，Windows 上存在不兼容写入者时失败；计算期间排除新的写入 / 删除共享。菜单静态预检不能代替运行时复核。终端转义路径中的控制字符，文件内容始终作为字节读取。读取失败或中断不调用剪贴板写入；成功后在 STA 桌面线程用系统 Unicode 文本格式写入纯摘要，系统占用时最多五次尝试。

Hash 是本次读取内容的指纹；之后编辑文件必须重新计算。终端保留结果供核对，管理日志只保存固定状态，不保存文件正文。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、文件与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 职责 |
| --- | --- |
| [Extension.json](./Extension.json) | 独立 `file-hash` 身份与可见控制台。 |
| [Manage.cmd](./Manage.cmd) | 仅唤起本功能图形管理面板。 |
| [Scripts/README.md](./Scripts/README.md) | 原生菜单、流式计算、剪贴板与安装实现。 |

`Tests/FileHash.Tests.ps1` 使用临时空文件、标准 abc 向量、随机大二进制和特殊路径验证摘要、只读保持、失败不复制、剪贴板失败与独立打包。`Tests/FileHashMenuProbe.cpp` 验证单选范围；共享安装器、清单和模板一致性由隔离回归覆盖。验证不真实注册菜单、不覆盖系统剪贴板；Windows 原生 PowerShell 5.1 / MSVC / Explorer 菜单及系统剪贴板交互仍需目标桌面验收。


<!-- JOBS_SOURCE_SCRIPT_PACKAGES -->
**同名脚本包：** [Manage.vbs](./Manage.vbs/README.md)。源码路径与发布目录的 flat 资源名分开维护。
<!-- /JOBS_SOURCE_SCRIPT_PACKAGES -->

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

**管理面板关闭：** 空闲关闭时选择退到系统托盘或完全退出，默认回车为托盘、Esc 保留原窗；安装／卸载／构建清理进行中关闭直接后台，不询问、不终止任务。完工仍驻留，从托盘双击或“显示管理面板”恢复同一窗口；忙碌时不能完全退出。

**整行选择：** 点击复选框、图标、功能文字、普通状态区或该功能行空白，仅切换该项一次，保留原 Tab／Space 复选框操作及勾选事件。任务执行中及不可用项禁止切换；失败日志链接和独立按钮优先执行自身动作，不连带勾选。组标题拖动、分组按钮和组尾空白不算功能行；移动、离开、滚动或触控滑动会取消本次点击候选，不接管原生滚动。选择本身不执行安装、卸载或清理，原默认空选、主题／语言切换保留勾选及持久化规则不变。

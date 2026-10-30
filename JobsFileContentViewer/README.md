# `JobsFileContentViewer`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、安装 / 更新与卸载](#jobs-toc-heading-2)
- [二、阈值与只读输出](#jobs-toc-heading-3)
- [三、目录、日志与验证](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

**最低支持系统：Windows 10 64 位（x64）。** 当前以系统 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) 5.1 Desktop 与 Windows 10 / 11 图形桌面为目标，最低 build 与完整实机兼容性尚待验证；Windows 11 通过“显示更多选项”或 `Shift+F10` 使用经典菜单。

右键一个文件 → **📄 用终端查看文件内容**，在新的可见 PowerShell 窗口只读显示正文。功能对应 CMD 的 [`type`](https://learn.microsoft.com/windows-server/administration/windows-commands/type) / PowerShell 的 [`Get-Content`](https://learn.microsoft.com/powershell/module/microsoft.powershell.management/get-content?view=powershell-5.1)；实际用 .NET 固定块读取，避免一次把大文件或无换行长文本装入内存。文件路径和正文始终作为数据，不执行所选脚本。

| 操作 / 条件 | 结果 |
| --- | --- |
| 右键一个普通文件 | 显示“📄 用终端查看文件内容”，点击后重新验证目标。 |
| 目录、桌面 / 文件夹背景、多选、链接或设备 | 不显示本项；运行端也拒绝无效目标。 |
| 文件大小 ≤ 默认 1 MiB | 直接读取；恰好 `1048576` 字节不触发大小确认。 |
| 文件大小 > 阈值 | 先显示实际字节数和阈值；输入精确 `YES` 后回车才读取正文，其他输入、回车、EOF 均取消。 |
| 疑似二进制、控制字符或未知编码 | 最多读取 8192 字节采样后单独询问 `YES`；取消不输出正文。 |
| 输出过程中 | `Ctrl+C` 中止；完成后由窗口提示回车关闭。 |

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、安装 / 更新与卸载 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

整个 `JobsFileContentViewer` 目录可独立复制。双击 [Manage.cmd](./Manage.cmd)，在面板选择“安装 / 更新”或“卸载”，确认后立即执行；取消不修改安装状态。也可通过上级总管理面板只勾选本项 `file-content-viewer`。

安装要求已有 [**MSVC / Windows SDK**](https://visualstudio.microsoft.com/visual-cpp-build-tools/) 和匹配 Explorer 架构的 C++ 工具。安装器先复制本包独立 release 并校验 SHA-256、编译原生菜单 DLL，再以当前用户注册本包文件 handler 和 CLSID；缺编译器停止，不联网安装、不提权、不改变永久执行策略。

安装 / 卸载只操作本包 `HKCU\Software\Classes\*\shellex\ContextMenuHandlers\Jobs.WindowsExtension.file-content-viewer` 和 `HKCU\Software\Classes\CLSID\{DBC7884D-ECD9-43CB-A026-AFD8A9BBC2A7}`，保留其它功能。事务失败恢复本包菜单和配置。卸载保留运行版本、日志、快照和 `Enabled=false` 状态；不删除用户文件。系统开始菜单中的卸载快捷方式仍可使用。

本包适配 Windows 原生架构编译入口；x86 / ARM64 与真实 Explorer 菜单尚需目标机验收，不以本机 PowerShell 7 回归代替 Windows PowerShell 5.1 / MSVC 验收。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、阈值与只读输出 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

环境变量 `JOBS_FILE_VIEWER_MAX_BYTES` 指定十进制字节阈值，未设置时为 `1048576`；有效范围 `1` 至 `9223372036854775807`。空值、零、负数、带空格、非整数及溢出均报错停止。可在终端中调整后调用本包业务验证，不持久修改环境：

```powershell
$env:JOBS_FILE_VIEWER_MAX_BYTES = '5242880'
Import-Module .\Scripts\Action.psm1 -DisableNameChecking
Invoke-JobsFeature -Target 'D:\项目\说明.md'
Remove-Item Env:JOBS_FILE_VIEWER_MAX_BYTES
```

右键启动进程继承 Explorer 的环境；已经运行的 Explorer 不会自动获得另一个终端临时设置的变量。需要右键使用自定义阈值时，在 Windows 用户环境变量中自行配置并重新登录，或重新启动包含该环境的桌面会话。默认值随包可直接使用。

大小确认先于文件内容读取。打开前重新检查目标，打开后用实际长度复核已变化的大文件；文件流仅授予读共享，在 Windows 上拒绝已有写入者或后续写入 / 删除共享冲突，读取冲突按错误停止。菜单检查与打开之间仍存在文件系统状态变化窗口，不能把静态预检视为文件永远不变的保证。

编码识别支持 UTF-8、带 BOM 的 UTF-16 LE / BE 与 UTF-32 LE / BE；无 BOM 默认 UTF-8。采样解码失败或含非文本控制字符时要求明确确认，确认后无效字节显示为 `�`，不猜测本机 ANSI 代码页。正文固定 4096 字符块输出，处理跨块的 UTF-8 / Unicode 和 CRLF；CRLF 规范成换行，独立 CR 显示为 `\r`，ESC / BEL / C1 和双向控制符等显示为 `\uXXXX`。后部控制符同样转义；二进制没有有意义的文本排版保证，查看原始二进制请使用专门工具。

阈值是继续输出的确认门槛，确认后会完整输出到 EOF。极大文本仍可能使终端滚屏缓慢；可随时 `Ctrl+C`。不会自动等待日志追加、不修改文件、不执行正文、不发送内容到网络，也不把正文写进日志。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、目录、日志与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 职责 |
| --- | --- |
| [Extension.json](./Extension.json) | 独立功能身份、标题与可见控制台设置。 |
| [Manage.cmd](./Manage.cmd) | 本包安装 / 更新与卸载管理入口。 |
| [Scripts/README.md](./Scripts/README.md) | 菜单、流式读取、构建与安装模块说明。 |

部署状态位于当前用户本地应用数据中的 `Jobs\WindowsExtension\extensions\file-content-viewer`，分别由 `settings.json`、`releases/`、`logs/`、`backups/` 保存状态、运行版本、固定状态日志和注册表快照。窗口显示目标路径及正文，日志只保留操作状态；不保存文件内容。读取失败显示错误后保留窗口，重新右键前先核对文件存在、可读且无写共享冲突。

本仓的 `Tests/FileContentViewer.Tests.ps1` 用临时夹具验证大小边界、确认 / 取消 / EOF、Unicode、采样和输出跨块、未知编码、控制符、特殊路径、大型无换行文件及只读保持；`Tests/FileViewerMenuProbe.cpp` 检查单选 / 目录 / 链接资格。安装器、独立包、清单与模板一致性另由共享隔离回归验证。验证不注册真实菜单，不修改用户业务文件；Windows PowerShell 5.1、MSVC 构建与 Explorer 真实显示 / 新窗口交互仍需目标桌面验收。

管理安装 / 卸载时双击 `Manage.cmd`，它只通过 WScript 唤起 GUI，随后立即结束本次脚本；不在 CMD 中编译、安装或等待输入。也可直接双击 `Manage.vbs` 进入同一面板。每个选项显示等待、执行中、完成或失败，底部实时滚动标准输出和错误，可选中复制或点击“复制全部日志”；无可靠百分比时显示执行中，总体显示完成项数。运行期间等当前事务结束后关闭，完整管理日志位于系统临时目录 `JobsExtensionManager-<运行编号>.log`。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

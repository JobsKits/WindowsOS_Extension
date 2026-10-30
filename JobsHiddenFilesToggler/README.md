# `JobsHiddenFilesToggler` · 显示 / 隐藏文件

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、安装、卸载与使用](#installation)
- [二、设置与刷新边界](#scope)
- [三、文件、记录与验证](#files-tests)

</details>
<!-- jobs-toc:end -->

---

**管理操作：** 本目录以 `Manage.cmd` 为轻量启动入口，只唤起 GUI 后结束本次脚本；先在面板选择安装 / 更新或卸载。在面板确认安装 / 更新或卸载后立即执行，无二次终端确认。关闭或取消面板不执行；卸载保留日志、备份、运行文件和工具。

## 🔥 <span id="前言">前言</span>

**最低支持系统：Windows 10 x64。** 当前面向 [**Windows**](https://www.microsoft.com/windows) 10 / 11 图形桌面；具体最低 build、各架构的原生菜单与刷新效果仍须实机验收。

在系统桌面空白处右键，菜单显示下一步动作：当前隐藏隐藏文件时显示“**👁️ 显示文件**”，当前已经显示时显示“**🙈 隐藏文件**”。点击后立即切换当前用户的资源管理器隐藏文件偏好，不再弹出执行确认。普通文件夹空白、选中项和多选不显示本入口。

| 当前隐藏文件设置 | 桌面右键菜单 | 点击结果 |
| --- | --- | --- |
| 隐藏（`Hidden=2`，或尚无该设置） | 👁️ 显示文件 | 将当前用户 `Hidden` 写为 DWORD `1`。 |
| 显示（`Hidden=1`） | 🙈 隐藏文件 | 将当前用户 `Hidden` 写为 DWORD `2`。 |
| 读取失败、类型错误或值无效 | ⚠️ 隐藏文件状态不可用（置灰） | 不猜测状态，不启动切换。 |

打开菜单只读取状态并固定该标题对应的显示或隐藏目标。点击后再次读取当前设置，只应用标题承诺的动作；如果外部已切换到目标状态，则不重复写入，不会把“显示文件”点成隐藏。同一用户的操作由串行锁保护。它控制当前账户的资源管理器显示偏好，会影响桌面和资源管理器视图，不修改文件自身的隐藏属性；独立 `Run.cmd` 保留反转当前状态的操作。

## 一、<span id="installation">安装、卸载与使用</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

本目录可以单独复制使用。双击 [Manage.cmd](./Manage.cmd) 安装本包，或在[总安装面板](../README.md#installation)勾选“显示 / 隐藏文件”；[Manage.cmd](./Manage.cmd) 仅移除本包菜单，保留运行文件、日志和安装备份。安装和卸载都不切换隐藏文件状态。

安装动态菜单需要已有 [**Visual Studio / Build Tools**](https://visualstudio.microsoft.com/visual-cpp-build-tools/) 的“使用 C++ 的桌面开发”、MSVC、Windows SDK，以及与资源管理器一致的架构工具。安装器使用系统 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) `5.1 Desktop` 与 STA，仅写当前用户菜单注册；不提权、不联网、不安装编译器。缺少依赖时在注册前停止。

Windows 11 在“显示更多选项”中查看，也可使用 `Shift+F10` 打开经典菜单。每次重新右键都会读取当前设置并更新文字与 emoji。菜单业务在后台执行，不打开终端；[Run.cmd](./Run.cmd) 可在未安装菜单时独立执行同一切换，也会立即改变当前用户偏好。

## 二、<span id="scope">设置与刷新边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

只读写当前账户 `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` 中的 `Hidden` DWORD：`1` 表示显示、`2` 表示隐藏。缺省按系统默认隐藏处理；无法识别的值或类型保持原样并停止。

不会修改 `ShowSuperHidden`、受保护操作系统文件显示策略、文件属性、其他用户或机器级注册表。显示普通隐藏文件不等于显示受保护系统文件。再次点击相反动作即可切回显示 / 隐藏状态；卸载不是恢复偏好的操作。

写入后核对结果，并通过 `WM_SETTINGCHANGE`、`SHChangeNotify` 通知资源管理器刷新；不强制终止或重启资源管理器。不同 Windows 版本和已打开窗口的刷新时机可能不同，真实桌面效果须在目标机核对。

## 三、<span id="files-tests">文件、记录与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 路径 | 职责 |
| --- | --- |
| `Extension.json` | 独立包身份 `hidden-files-toggle` 与安装说明。 |
| `Manage.cmd` | 本包安装和卸载，不切换显示偏好。 |
| `Run.cmd` | 未安装菜单时独立切换当前用户隐藏文件显示。 |
| [Scripts](./Scripts/README.md) | 动态桌面菜单、隐藏文件状态切换、刷新和安装事务。 |

本包运行目录、安装备份与日志按独立标识保存在当前用户本地应用数据的 `Jobs/WindowsExtension/extensions/hidden-files-toggle/` 中，不依赖相邻功能包或总目录的运行代码。

[HiddenFiles.Tests.ps1](../Tests/HiddenFiles.Tests.ps1)使用内存状态和 Windows 临时注册表夹具核对状态解析、切换、失败边界与独立包；[HiddenFilesMenuProbe.cpp](../Tests/HiddenFilesMenuProbe.cpp)核对动态标题与桌面门禁。隔离验证不修改当前用户真实隐藏文件设置；MSVC、Explorer 右键展示及刷新仍须真实 Windows 验收。

管理安装 / 卸载时双击 `Manage.cmd`，它只通过 WScript 唤起 GUI，随后立即结束本次脚本；不在 CMD 中编译、安装或等待输入。也可直接双击 `Manage.vbs` 进入同一面板。每个选项显示等待、执行中、完成或失败，底部实时滚动标准输出和错误，可选中复制或点击“复制全部日志”；无可靠百分比时显示执行中，总体显示完成项数。运行期间等当前事务结束后关闭，完整管理日志位于系统临时目录 `JobsExtensionManager-<运行编号>.log`。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

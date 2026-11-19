# `JobsDiskSpaceInfo` 磁盘空间与终端清理

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、显示与统计口径](#behavior)
- [二、独立安装与卸载](#management)
- [三、源码与验证](#sources)
- [四、清理流程与原 clean 功能对照](#cleanup)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

功能标识 `disk-space-info`。在资源管理器的文件、文件夹、磁盘、目录空白处和桌面空白处右键菜单显示一行汇总，例如 `💽 磁盘剩余：250.00 GB / 1.00 TB (25.00%)`。该行可点击，打开本包独立 PowerShell 终端，由用户选择并确认后才清理；不区分当前所选对象所在磁盘，也不展开逐盘详情。

## 一、<span id="behavior">显示与统计口径</span> <a href="#前言">🔼</a>

- 每次 Explorer 调用 `QueryContextMenu` 构建弹出菜单时，都重新枚举并读取本机已挂载、可读写的本地固定或可移动卷；同一个 COM 实例被反复复用也不缓存容量或描述。使用卷 GUID 去重，同一卷的盘符、文件夹挂载点或其它别名不重复累计。当前已打开的菜单是一份当时快照，不在菜单停留期间轮询；关闭后重开再采样。
- 排除网络盘、光盘、只读卷、没有用户挂载路径的隐藏分区；不扫描文件内容或目录。总容量与总余量来自系统 `GetDiskSpaceInformationW` 的实际分配单元，不受调用用户的磁盘配额限制；存储池不足的单元从余量扣除。已挂载的可写 VHD / VHDX 文件镜像仍按 Windows 本地卷规则参与，底层存储与其镜像容量可能同时计入；当前没有加入未经原生验证的镜像分类 API，Storage Spaces 也不按“虚拟”一概排除。
- 先按字节分别求和，再以总余量 / 总容量计算百分比，固定两位小数。容量使用十进制 B / KB / MB / GB / TB / PB / EB，并保留两位小数。
- 枚举或符合条件的卷查询失败、零总容量或数值异常时显示本地化“磁盘空间暂不可用”，仍可点击进入清理，不把查询失败冒充 `0.00%` 或部分汇总。
- 描述跟随 Windows 当前用户显示语言，支持简体中文、繁体中文、藏文、英文、日文、法文、西班牙文、德文、俄罗斯文和韩文；其它语言回退英文。使用 Explorer 系统菜单的外观。
- 范围为 Windows 文件管理器支持的经典右键菜单；Windows 11 从“显示更多选项”或 `Shift+F10` 查看。浏览器、其它应用私有右键菜单和虚拟命名空间不在文件系统 handler 范围内。

## 二、<span id="management">独立安装与卸载</span> <a href="#前言">🔼</a>

完整复制本目录后双击 [Manage.cmd](./Manage.cmd) 或 [Manage.vbs](./Manage.vbs/Manage.vbs)。同一面板提供安装 / 更新及卸载，默认空选；任务开始前关闭或取消不会启动操作。也可在 [平台总面板](../README.md) 仅选择“💽 磁盘剩余空间”。管理面板沿用十语言选择与白天 / 黑夜 / 跟随系统主题；这些偏好只影响管理面板，菜单语言跟随 Windows。

要求 Windows 10 1809（Build 17763）或更新的 Windows 10 / 11 图形桌面、Windows PowerShell Desktop 5.1、系统 .NET / WinForms，以及现有 Visual Studio / Build Tools 的 C++ 桌面工具、MSVC 与 Windows SDK。按 Explorer 的 x64 / ARM64 / x86 架构编译；缺失工具时在注册前停止，不自动下载或安装编译器。磁盘 API 不可用时显示不可用，架构分支不代表已完成全部目标机验收。

安装只注册当前用户 `HKCU\Software\Classes` 下本包五类 `shellex\ContextMenuHandlers` 及独立 CLSID `{E10272DD-32AF-4BD0-97D2-B74D201FA6F1}`，不会修改其它菜单。默认运行位置为当前用户本地应用数据中的 `Jobs\WindowsExtension\extensions\disk-space-info`；临时构建路线使用本包 `work\WindowsExtension`，移走该位置会使菜单失效。菜单由系统按需加载 DLL，查看容量不启动进程；点击才按本包 DLL 的实际位置启动系统 PowerShell 和随包 `Scripts/Clean.ps1/Clean.ps1`，不传所选文件路径，不调用仓库外的脚本。

安装 / 卸载事务保存本包注册表与状态快照，失败尝试回滚。卸载只撤销本包注册并保存禁用状态，保留运行版本、日志与备份，不强制重启 Explorer。安装结果、部署位置和完整会话日志可在管理面板查看；会话日志在系统临时目录，持久状态及备份在上述本包运行目录。

## 三、<span id="sources">源码与验证</span> <a href="#前言">🔼</a>

实现位于 [Scripts](./Scripts/README.md)，C++ 合计与显示回归见 [容量核心测试](./Tests/DiskSpaceSummaryTests.cpp/README.md)，同一菜单实例连续重开、动态值与失败不复用回归见 [菜单实时采样测试](./Tests/ContextMenuFreshnessTests.cpp/README.md)。现有平台 `Installer.Tests.ps1`、`Architecture.Tests.ps1`、`NativeBuild.Tests.ps1` 与面板偏好回归覆盖本包注册计划、独立发布、构建参数及翻译；这些检查不写真实注册表或安装扩展。

Windows 原生 DLL 编译、真实 Explorer 点击、独立控制台与多卷容量仍需在目标 Windows 桌面验收；不能由 macOS 的 C++ 核心测试或 PowerShell 隔离检查推定已安装可用。非零薄置备存储池没有实机统计证据。

## 四、<span id="cleanup">清理流程与原 clean 功能对照</span> <a href="#前言">🔼</a>

常规类别清理失败后会列出剩余失败路径和日志，并询问是否继续；回车仅重试原确认计划中的失败项，非空输入或 EOF 停止并保留失败，Ctrl+C 中断。各轮追加同一日志，成功项出队，不纳入新候选；前置开发分组不进入此循环。

终端询问正文采用青色粗体，回车选项绿粗体、任意／非空输入选项红粗体，分隔符普通；无这两类输入选项的询问同样突出正文。仅在交互 ConsoleHost 明确支持虚拟终端时使用样式；`NO_COLOR` 存在（含空值）、非交互或能力不足时使用纯文本，日志不包含控制码。该显示规则不改变选择、确认与取消行为。

完整参数、路径白名单和恢复方式见 [独立 Clean.ps1 说明](./Scripts/Clean.ps1/README.md)。先询问是否进入开发分组：回车继续，任意内容后回车跳过，输入结束取消整轮；只有明确继续后才选择组并收集候选。Windows 不提供 Xcode Device Support 或 SwiftUI Previews，不操作 Apple 目录；对应适用组为缺失 Android AVD 登记、明确工程的 Windows runner 输出、逐个 APK / AAB 交付包和已知下载 / 着色器缓存。每组 `fzf` 首行“清理当前组全部”，支持单项 / 多项选择；Enter 勾选、Space 提交已有选集，无勾选时提交当前行，已有选集不额外加入光标项；核对最终范围后回车执行，任意非空内容加回车取消开发阶段并进入常规，EOF / Ctrl+C 取消整轮。开发阶段普通失败也继续常规，最终保留失败结果。无健康 fzf 时开发组全部保留，不安装工具。

后续常规阶段仅处理用户 Temp 中七天以上的直属项目、PSReadLine 历史和失效开发快捷方式；不会再次清理开发阶段跳过或未选的缓存、模拟器、构建输出与归档。常规每轮仍默认取消，选中确认项后空格执行；点击菜单本身不删除文件。候选按通用工程／依赖／SDK标记、只读内容及扫描预算识别保护，不硬编码用户名或个人环境目录；任一标记、重解析点、读取失败或预算超限都保留整项。扫描最多10,000项、64层，检查时间预算5秒，执行前和暂存后同样复检。程序锁定、越界、候选变化、备份失败等会保留或报告未完成。

| 原 `clean.command` 能力 | Windows 独立实现 |
| --- | --- |
| zsh 历史 / sessions | 仅标准 PSReadLine 持久历史文件，先备份；不接管其它终端内存。 |
| 用户 Library/Caches | 精确用户 Temp 与已知开发缓存白名单，根目录保留；分组跳过有保护。 |
| Apple 平台构建 App 移入废纸篓 | 明确 Flutter 工程的标准 Windows runner App 输出，先完整可核对备份，再移除。 |
| LaunchServices 失效开发 App 登记 | 仅用户 Start Menu 中目标实体已缺失且属于严格开发输出路径的快捷方式，先备份；正常软件与文件关联保留。 |
| 缺失 iOS 模拟器登记 | Windows 无 CoreSimulator；只处理默认 Android AVD 中实体确实缺失的精确 `.ini` 登记，正常设备与 SDK 保留。 |
| Homebrew cleanup | Windows 无 Homebrew 版本清理；对应已知 pip / npm / NuGet 下载缓存，仅在开发 Caches 组显式选择后处理，不卸载工具版本。 |

常规用户缓存先用已有健康 fzf 明确选择：第一行“全选用户缓存”，第二行“跳过用户缓存清理”（默认焦点），下方可逐项勾选。Enter 勾选／取消，Space 确认已选集；没有勾选时选定当前行并确认，有勾选时不额外加入当前光标项。默认光标在跳过行时 Space 仍是跳过；搜索无匹配且无勾选时留在菜单。全选展开本轮完整候选，搜索不缩小其范围，跳过优先于全选，取消或失败不清理。选择后仍展示准确范围并沿用“选中确认清理后空格执行”的最终确认；无健康 fzf 时保留缓存且不自动安装。Windows 原生 fzf 控制台按键仍待目标机验收。

历史、快捷方式、AVD 登记、构建 App 与归档的恢复副本位于当前用户 LocalAppData 的本包 `clean-backups/<编号>`，`.restore.json` 保留原位置；备份仍占空间。缓存直接删除，不能自动恢复。首次确认清理后才创建本包 `logs/clean-<编号>.log`；预览、跳过、取消不创建清理日志或备份。处理失败可返回原位置的暂存项目会尽力恢复，无法恢复时打印准确位置。

原 clean 功能增删必须同一任务同步本包 Windows 独立源码、macOS 右键实现和功能对照；差异按平台真实能力说明。原文件仅是开发期行为参考，运行时不引用原文件、原仓库或 macOS 代码。隔离回归见 [CleanTests.ps1](./Tests/CleanTests.ps1/README.md)，源码 / 夹具、原生菜单和真实清理分别验收。

统计 API 依据：[卷枚举](https://learn.microsoft.com/windows/win32/api/fileapi/nf-fileapi-findfirstvolumew)、[卷挂载路径](https://learn.microsoft.com/windows/win32/api/fileapi/nf-fileapi-getvolumepathnamesforvolumenamew)、[磁盘空间](https://learn.microsoft.com/windows/win32/api/fileapi/nf-fileapi-getdiskspaceinformationw)、[实际容量及配额字段](https://learn.microsoft.com/windows/win32/api/fileapi/ns-fileapi-disk_space_information)。

<a id="🔚" href="#前言">我是有底线的➤点我回到首页</a>

**管理面板关闭：** 空闲关闭时选择退到系统托盘或完全退出，默认回车为托盘、Esc 保留原窗；安装／卸载／构建清理进行中关闭直接后台，不询问、不终止任务。完工仍驻留，从托盘双击或“显示管理面板”恢复同一窗口；忙碌时不能完全退出。

**整行选择：** 点击复选框、图标、功能文字、普通状态区或该功能行空白，仅切换该项一次，保留原 Tab／Space 复选框操作及勾选事件。任务执行中及不可用项禁止切换；失败日志链接和独立按钮优先执行自身动作，不连带勾选。组标题拖动、分组按钮和组尾空白不算功能行；移动、离开、滚动或触控滑动会取消本次点击候选，不接管原生滚动。选择本身不执行安装、卸载或清理，原默认空选、主题／语言切换保留勾选及持久化规则不变。

# Android 模拟器扩展脚本与原生桥接

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、调用与验证](#jobs-toc-heading-2)

</details>
<!-- jobs-toc:end -->

---

**SDK 获取策略：** Java、Android Command-Line Tools、SDK 组件和模拟器系统镜像的下载／远程清单获取失败后持续自动重试，直到成功或按 Ctrl+C／停止主动结束，无须确认重试；等待逐步延长且最多 30 秒。实时显示真实输出，重试日志追加到系统临时目录的 `JobsSdkAcquisition-进程号.log`。归档校验失败仅重取本次私有文件；成功后清理本次暂存，失败／取消保留未提交暂存并显示位置，不删除已有健康 SDK。许可证、架构／参数／权限等确定的本地问题单独处理；创建和启动 AVD 不在重试循环中。

**面板外观与语言：** 总面板和独立功能面板右上角均可选择“黑夜 / 白天 / 跟随系统”以及“简体中文 / 繁體中文 / བོད་ཡིག / English / 日本語 / Français / Español / Deutsch / Русский / 한국어 / 跟随系统”，默认均跟随系统，切换立即生效并保留当前勾选、任务和日志。窄窗或长文案放不下时，工具组移至标题下一行并保持右对齐；极窄窗口将主题、语言分两行，下拉控件右边缘对齐。选择保存在当前用户的 `%LOCALAPPDATA%\Jobs\WindowsExtension\panel-preferences.json`，下次打开自动恢复；保存失败在面板显示原因。跟随系统每秒检查应用主题和当前用户显示语言，繁体中文界面使用繁体、其它中文使用简体，其余已支持语种按系统语言匹配，未支持语言回退英文；Windows 显示语言通常须重新登录才生效。切换涵盖面板正文、功能说明、状态与动态计数、操作提示和辅助名称；藏文优先使用已安装 Microsoft Himalaya / Noto Sans Tibetan，日韩使用对应系统字体，缺失时回退。语言名称始终显示自称，图标、功能名和状态列独立，长文字换行；切换只影响管理面板，已安装右键菜单标题及后台工具的原始日志保持各自语言。共享完整译文以 `Scripts/ManagerPanelTranslations.json` 为编辑来源，发布时内嵌到同源面板模块，独立包无需访问兄弟目录或联网翻译。

## 🔥 <span id="前言">前言</span>

> 本目录为Runner随包保留的Android模拟器运行源码；下文安装、管理入口与模块职责对应原独立功能包，完整说明见功能README。用户入口为上级目录的 `Manage.cmd`、`Manage.cmd`、`Run.cmd`；单包复制到任意目录后仍可独立安装。

| 文件 | 职责 |
| --- | --- |
| `Manage.ps1` / `PackageInstaller.psm1` | 当前用户安装、精确卸载和本包注册 / 状态管理。 |
| `Build.ps1` | 使用已有 MSVC / Windows SDK 构建原生菜单，不自动安装编译器。 |
| `ContextMenu.cpp` / `.def` / `DesktopScope.h` | 桌面背景 COM 桥接；仅无选中项且匹配系统 Desktop 时显示，点击后交给独立终端。 |
| `OpenCmd.ps1` / `Invoke.ps1` | 安全打开 CMD 并传递桌面目标；右键固定进入新建流程，SDK 工具不进入 Explorer 进程。 |
| `CreateAndroidSimulator.ps1/CreateAndroidSimulator.ps1` | 独立交互入口及 `-Check` 只读体检。 |
| `Action.psm1` | SDK / Java / 工具健康检查、官方源自动补齐 / 修复、映像和机型选择、唯一命名、创建与启动验证。 |
| `SdkDownloadOutput.ps1/SdkDownloadOutput.ps1` | SDK 获取持续重试、续传、真实输出与追加日志；仅包围环境获取。 |
| `Common.psm1` | 当前用户路径、进程参数、日志与通用基础设施。 |

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、调用与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

在本目录使用 Windows PowerShell 5.1：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ./CreateAndroidSimulator.ps1/CreateAndroidSimulator.ps1 `
  -Check
```

只读体检不安装、卸载或创建 SDK 根目录。两个运行入口统一在首屏说明自动下载和修复边界，回车后体检整条依赖链，健康复用，缺失依赖自动补齐，损坏组件修复后立即复检（获取过程持续重试）。Java 21 从 [**Adoptium**](https://adoptium.net/installation/archives) 官方元数据及 ZIP 安装到用户目录，SHA-256 校验，采用与最终目录同卷的私有 stage；Command-Line Tools 同样保留旧版本并同卷安装。没有镜像时自动查询官方清单，选中后直接安装；编号列表 `q` / EOF 可取消。SDK 官方许可证仍由用户本人处理，不自动回答 `yes`。仅重装损坏 Emulator / ADB 包，保留映像及 AVD，失败停止；创建 AVD 前回车确认，不覆盖已有设备。

日志位于本功能当前用户数据目录的 `logs/`。详细依赖、安装边界、日志及隔离测试见[功能 README](../../../../../../../../JobsAndroidSimulatorCreator/README.md)。本机 macOS 下的 Parser / PowerShell / C++ 夹具不能替代 Windows MSVC 与 Explorer 实机验收。

本目录的 `Manage.ps1`、`SelectionPanel.psm1` 和 `ManagementWorker.ps1` 构成本包自包含管理面板；由上级 `Manage.vbs` 无控制台启动。安装 / 卸载在隐藏后台执行，逐项状态与可复制实时日志留在面板中。日志区上沿的分隔条可上下拖动，调节结果在当前窗口保留；上下限为功能行、操作按钮和日志工具栏留出空间。日志正文右键可“复制”或“全选”，也支持 Ctrl+A / Ctrl+C；全选仅针对当前可见缓冲区，完整输出使用“复制全部日志”。总进度按已处理项 / 本次所选项显示计数和百分比；成功、未安装无需卸载与失败计入已处理，等待中、执行中和未执行项不计入；“未安装，无需卸载”单独显示且不算成功，最终分别汇总成功、无需卸载、失败与未执行数量。100% 仅表示本轮全部处理完毕。安装 / 更新和卸载分别计时；点击时只清零并启动当前操作计时，后台全部结束或启动失败时只冻结当前耗时。每秒刷新 `HH:mm:ss`（小时可超过 24），执行时显示“安装用时 / 卸载用时”，结束显示“安装总用时 / 卸载总用时”。两份耗时只在当前面板会话内独立保留。安装成功显示绿色“✅ 安装成功”。不改变右键业务工具自己的交互方式。失败状态可点击，在独立 PowerShell 中只读显示本次完整会话日志；包失败不阻止其它所选包，日志不可用时在面板提示。

**Flutter SDK网络预检：** 下载／首次Dart自举／precache前，随包网络模块以真实小Range验证来源、TLS、字节和吞吐并择优；显式storage、Pub和代理（含空值）保留，AUTO仅核验官方／CFUG同对象及当前已配置代理，不猜端口、不改系统代理或Git。当前任务短期复用；真实获取失败会降权坏路线、轮换其它已验证候选并持续重试。FVM按实际api context来源处理，能力允许时Git与Dart制品分阶段；用户fork不改源。原生BITS按真实WinINET通道衡量，PAC未能有界解析时保留既有通道并明确未测速。详细边界见[随包选路模块](./SdkDownloadRoute.ps1/README.md)。

**调用参数：** `CreateAndroidSimulator.ps1 -Create` 直接进入新建流程，复用桌面创建核心及全部原确认、许可和日志；不传 `-Create` 保留原操作选择，`-Check` 始终只读优先。Flutter Runner 使用此参数，不会误选成启动旧 AVD。

由 Flutter Runner 调用且设置本轮 `JOBS_FLUTTER_CREATED_DEVICE_FILE` 时，仅在新建 AVD 并确认系统启动完成后写入 `Android<TAB>serial`；取消、失败和普通只启动入口不写结果。此变量仅在调用子进程时临时传入，不改全局环境。



<!-- JOBS_TERMINAL_STYLE_V1:BEGIN -->

> Windows 终端配色保护：支持完整颜色查询的交互控制台会先保存当前会话默认前景、背景与16色色表，再临时使用黑底白字和统一强调色；正常结束、业务失败及可捕获中断后恢复。用户运行中自行改动的颜色保留并提示，不修改用户主题、共享 Profile、注册表或全局策略。快照不包含进入前任意叠加的临时文字样式。非控制台、重定向、`NO_COLOR`、Sourcetree 及无法可靠保存／恢复颜色的环境保持原状态或降级为纯文本。

> 强制结束进程或终端崩溃无法保证自动恢复。恢复失败时保留并提示本轮 `%TEMP%\JobsTerminalStyle-<PID>-*.ps1` 恢复脚本，需在原控制台核对后运行；不要通过重置用户配置恢复。`-ExecutionPolicy Bypass` 如被入口使用，仅作用于本次子进程，不持久修改策略。

> 验证范围：已完成 PowerShell 语法、参数／退出与隔离生命周期核验；Windows 原生控制台的显示、按键与 `Ctrl+C` 实机验证尚未完成。

<!-- JOBS_TERMINAL_STYLE_V1:END -->


<!-- JOBS_SOURCE_SCRIPT_PACKAGES -->
**同名脚本包：** [CreateAndroidSimulator.ps1](./CreateAndroidSimulator.ps1/README.md)、[SdkDownloadOutput.ps1](./SdkDownloadOutput.ps1/README.md)。源码路径与发布目录的 flat 资源名分开维护。
<!-- /JOBS_SOURCE_SCRIPT_PACKAGES -->

<a id="🔚" href="#前言">回到首页</a>

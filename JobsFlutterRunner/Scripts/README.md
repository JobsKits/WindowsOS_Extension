# JobsFlutterRunner 脚本与原生桥接

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、入口与职责](#entrypoints)
- [二、后台生命周期与排障](#lifecycle)

</details>
<!-- jobs-toc:end -->

---

**面板外观与语言：** 总面板和独立功能面板右上角均可选择“黑夜 / 白天 / 跟随系统”以及“简体中文 / 繁體中文 / བོད་ཡིག / English / 日本語 / Français / Español / Deutsch / Русский / 한국어 / 跟随系统”，默认均跟随系统，切换立即生效并保留当前勾选、任务和日志。窄窗或长文案放不下时，工具组移至标题下一行并保持右对齐；极窄窗口将主题、语言分两行，下拉控件右边缘对齐。选择保存在当前用户的 `%LOCALAPPDATA%\Jobs\WindowsExtension\panel-preferences.json`，下次打开自动恢复；保存失败在面板显示原因。跟随系统每秒检查应用主题和当前用户显示语言，繁体中文界面使用繁体、其它中文使用简体，其余已支持语种按系统语言匹配，未支持语言回退英文；Windows 显示语言通常须重新登录才生效。切换涵盖面板正文、功能说明、状态与动态计数、操作提示和辅助名称；藏文优先使用已安装 Microsoft Himalaya / Noto Sans Tibetan，日韩使用对应系统字体，缺失时回退。语言名称始终显示自称，图标、功能名和状态列独立，长文字换行；切换只影响管理面板，已安装右键菜单标题及后台工具的原始日志保持各自语言。共享完整译文以 `Scripts/ManagerPanelTranslations.json` 为编辑来源，发布时内嵌到同源面板模块，独立包无需访问兄弟目录或联网翻译。

**日志配色与滚动：** 日志使用独立的白天／黑夜背景、正文和错误／警告／成功／信息配色，ANSI 前景色按当前底色提高对比度；跟随系统采用对应一套。切换主题重配已有日志颜色，保留正文、选区和阅读位置。 Windows 高对比度开启、关闭或系统色变化时，已有日志和新输出同步采用对应底色与正文色，现有外观轮询同步面板。鼠标滚轮、触摸板、滚动条、方向／翻页键及选择正文暂停“自动滚动”，重新勾选才恢复追尾；后台继续接收日志。右键复制与 Ctrl+C 仅复制纯文本，可见区超过 100 万字符保留最后 70 万，原“复制全部日志”读取本次完整纯文本文件。追尾开关和阅读位置只保留当前窗口，不另存偏好。

**关闭与系统托盘：** 安装／卸载／构建清理进行中，点击窗口关闭、按 Esc 或使用底部关闭入口都直接退到系统托盘，后台任务和日志继续运行，不弹询问。任务完成后仍驻留，双击通知图标或选择“显示管理面板”恢复同一窗口、勾选与日志；托盘菜单显示当前状态。只有空闲关闭才询问“退到系统托盘／完全退出”，回车默认托盘，Esc 或“保留窗口”取消关闭选择；托盘的“完全退出”在任务中禁用并说明原因，执行出口再次检查任务，不能中途终止工作进程。真正退出才释放通知图标、菜单及计时器；托盘不可用时保留可见窗口。关闭选择不记忆，下次空闲关闭仍询问；托盘和隐藏状态仅属于本次进程。图标复用当前管理窗口的应用图标，无额外下载。

**整行选择：** 点击复选框、图标、功能文字、普通状态区或该功能行空白，仅切换该项一次，保留原 Tab／Space 复选框操作及勾选事件。任务执行中及不可用项禁止切换；失败日志链接和独立按钮优先执行自身动作，不连带勾选。组标题拖动、分组按钮和组尾空白不算功能行；移动、离开、滚动或触控滑动会取消本次点击候选，不接管原生滚动。选择本身不执行安装、卸载或清理，原默认空选、主题／语言切换保留勾选及持久化规则不变。

## 🔥 <span id="前言">前言</span>

本目录自包含 [**Flutter**](https://flutter.dev/) 运行菜单的安装、原生识别、CMD 交互与后台监督；整个功能包可单独复制。用户入口与环境要求见[包说明](../README.md)。

## 一、<span id="entrypoints">入口与职责</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文件 | 职责 |
| --- | --- |
| `Manage.ps1/Manage.ps1` / `PackageInstaller.psm1` | 安装确认、独立备份、release、当前用户 COM 注册与回滚；卸载保留数据。 |
| `Build.ps1/Build.ps1` | 从现有 vswhere / MSVC / Windows SDK 编译原生 DLL，系统 csc 编译独立后台宿主；只构建，不安装或联网。 |
| `ContextMenu.cpp` / `FlutterProject.h` / `FlutterRunTarget.h` / `ContextMenu.def` | 原生菜单初始化、根 YAML 与 Dart 最近包边界判断，无效目标不插入菜单。 |
| `OpenCmd.ps1/OpenCmd.ps1` / `Invoke.ps1/Invoke.ps1` | 通过固定 CMD 引导行进入本包，路径通过环境和独立参数传递；检查已安装状态。 |
| `Action.psm1` | fzf 区分真实设备、虚拟设备与桌面 / Web；虚拟组按 Android / Harmony 展示已有实例，清单末尾提供对应系统新建入口，精确等待本次目标后承接当前工程。 |
| [SimulatorCreators](./SimulatorCreators/README.md) | 桌面 Android / Harmony 原创建脚本的最小闭包；由独立 PowerShell 调用，不依赖其它功能已安装。 |
| `AndroidRuntime.ps1/AndroidRuntime.ps1` | 随包工具链自检、官方下载校验、AVD 名称与启动就绪检测；复用 JobsAndroidSimulatorCreator 自维护函数，不依赖兄弟包。 |
| [自动准备](./RunPreflight.ps1/RepairRunEnvironment.ps1/README.md) / [日志展示](./RunPreflight.ps1/RunDisplay.ps1/README.md) | 所选平台直接补齐，其它移动平台可选隔离后台准备；逐项✅/❌、错误红字、URL绿色下划线和结构标签图标。 |
| `RunnerHost.cs` | detached 独立监督进程、专属 Job、日志和 Flutter machine 双向控制。 |
| `Common.psm1` | 通用路径、参数、进程与日志工具。 |

只构建验证时，在 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) 5.1 中执行，输出路径自行选择：

```powershell
Build.ps1\Build.ps1 `
    -SourceRoot .. `
    -OutputRoot ..\build
```

正常安装使用包根 `Manage.cmd`，不手工调用注册表写入方法。`Extension.json` 的 `InfrastructureOverrides` 只允许 `PackageInstaller.psm1`，避免父仓通用模板同步覆盖本包原生编译和 COM 生命周期。

## 二、<span id="lifecycle">后台生命周期与排障</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

先在 CMD 选择设备，随后只通过文件日志和原子控制请求与后台通信。后台持有 Flutter 标准输入 / 输出 / 错误及每项目排他锁，CMD 不持有 Flutter 进程。会话 PID 必须同时匹配进程开始时间才重连，避免 PID 复用；`r` / `R` 使用 `app.restart`，`s` 使用 `app.stop`，超时只终止本会话 Job；`e` 仅停止本工程已核验身份的后台环境准备及其下载子树，当前 Flutter 会话保留。

CMD 首屏打印日志位置。`run.log` 用于阅读，`machine.jsonl` 用于协议排障，`state.json` 用于检查开始 / 运行 / 停止 / 失败，`startup-error.log` 用于定位后台启动失败。没有设备时仍保留虚拟设备和重新加载入口。Android / Harmony 各自清单先列已有实例、最后提供对应的新建虚拟设备入口；Windows 不提供 iOS。创建调用随包桌面原入口，保留工具准备、官方许可、型号 / 镜像选择、确认及日志，创建且启动成功后通过本轮结果文件返回精确设备 ID，最长等待 Flutter 识别 180 秒，随后自动运行当前工程；取消、跳过启动或失败不运行。子层 ← 返回，Esc 取消整个运行选择；平台清单不额外插入取消行，确保新建始终位于末尾；创建失败不自动运行应用。安装器缺 MSVC / SDK 时会在写注册表之前停止，按提示补齐现有开发工具后重试。

原生 COM 与 Win32 detached / Job 运行须在 Windows 实机验证；本机跨平台测试不会真实注册右键菜单或运行用户工程。

本目录的 `Manage.ps1/Manage.ps1`、`SelectionPanel.psm1` 和 `ManagementWorker.ps1/ManagementWorker.ps1` 构成本包自包含管理面板；由上级 `Manage.vbs` 无控制台启动。安装 / 卸载在隐藏后台执行，逐项状态与可复制实时日志留在面板中。日志区上沿的分隔条可上下拖动，调节结果在当前窗口保留；上下限为功能行、操作按钮和日志工具栏留出空间。日志正文右键可“复制”或“全选”，也支持 Ctrl+A / Ctrl+C；全选仅针对当前可见缓冲区，完整输出使用“复制全部日志”。总进度按已处理项 / 本次所选项显示计数和百分比；成功、未安装无需卸载与失败计入已处理，等待中、执行中和未执行项不计入；“未安装，无需卸载”单独显示且不算成功，最终分别汇总成功、无需卸载、失败与未执行数量。100% 仅表示本轮全部处理完毕。安装 / 更新和卸载分别计时；点击时只清零并启动当前操作计时，后台全部结束或启动失败时只冻结当前耗时。每秒刷新 `HH:mm:ss`（小时可超过 24），执行时显示“安装用时 / 卸载用时”，结束显示“安装总用时 / 卸载总用时”。两份耗时只在当前面板会话内独立保留。安装成功显示绿色“✅ 安装成功”。不改变右键业务工具自己的交互方式。失败状态可点击，在独立 PowerShell 中只读显示本次完整会话日志；包失败不阻止其它所选包，日志不可用时在面板提示。

**SDK 初始化进度：** 随包的 [SdkDownloadOutput.ps1](./SdkDownloadOutput.ps1/SdkDownloadOutput.ps1) 实时展示 SDK 相关命令输出，保留机器响应、退出码和超时边界；第一次调用 Flutter 触发 Dart / 工具缓存下载时，不再等待命令结束才显示。本动作仍要求现有项目 SDK；缺失 SDK 的安装由统一工具包的安装 / 切换入口处理。PubGet 的 URL / 认证信息继续脱敏后显示和落盘；测试不接触真实 SDK、账户缓存或系统菜单。

**SDK 平台缓存：** 选定运行设备／打包目标后先执行相应 `flutter precache --android`／`--windows`／`--web`；鸿蒙先核实当前 SDK 帮助支持 `--ohos` 再获取，平台引擎制品准备成功后才启动运行或构建。

**SDK 环境准备：** 已选择的 SDK／版本所需下载、安装及首次 Flutter／Dart 缓存补齐自动执行；网络失败或无进度超时后持续重试，间隔逐步增加并封顶 30 秒，没有次数和总时长上限，直到成功或本人 Ctrl+C／停止。仍在输出下载进度的传输不按总时长截断；成功后才进入后续业务。目标／版本选择、官方许可证与系统权限仍由本人处理；路径、权限、磁盘或明确不存在的版本会报告具体原因。每次尝试和真实进度追加到终端所示日志；同一 URL 有 ETag／Last-Modified 时安全续传，跨来源保留独立临时文件，不拼接不同来源。失败／取消保留下载现场；业务构建和配置写入不因网络重试而整体重放。

[下载前版本上下文隔离回归](../../Tests/SdkVersionContext.Tests.ps1/README.md)覆盖独立／聚合 Runner、旧缓存拒绝、未知版本、日志顺序与机器响应；不触碰用户 SDK 或真实会话。

**下载前版本上下文：** 每次 SDK 初始化／平台缓存获取前，先显示项目声明的 Flutter、本地 SDK 的版本标识与实际路径、目标内置 Dart、engine 提交以及宿主系统／架构，并写入同一获取日志。这里只读取本地文件及本地 Git exact tag，不执行 Flutter／Dart 探测或联网查询版本。Dart 只采用明确的源码版本文件、engine 匹配的版本 JSON 或 engine stamp 匹配的当前缓存；旧缓存及 `dart-sdk.old` 不作为目标版本。缺少可信依据时明确显示“未解析”，下载完成后再确认。

**设备发现前通用缓存：** 设备枚举前先执行 `flutter precache --universal`，准备 `sky_engine`、patched SDK 等通用资源，再进入短时设备查询。只准备通用制品，不强制下载全部平台；保留项目绑定 SDK，复用健康缓存。缺失制品沿随包网络选路实时显示真实下载进度，失败持续自动重试，Ctrl+C／停止结束；准备失败不会被误报为“无设备”，也不启动应用。

**Flutter SDK网络预检：** 下载／首次Dart自举／precache前，随包网络模块以真实小Range验证来源、TLS、字节和吞吐并择优；显式storage、Pub和代理（含空值）保留，AUTO仅核验官方／CFUG同对象及当前已配置代理，不猜端口、不改系统代理或Git。当前任务短期复用；真实获取失败会降权坏路线、轮换其它已验证候选并持续重试。FVM按实际api context来源处理，能力允许时Git与Dart制品分阶段；用户fork不改源。原生BITS按真实WinINET通道衡量，PAC未能有界解析时保留既有通道并明确未测速。详细边界见[随包选路模块](./SdkDownloadRoute.ps1/README.md)。

**运行设备分组：** 根 fzf 提供“目前已有的真实设备 / 虚拟设备 / 其他运行目标（桌面 / Web）/ 重新加载设备列表”。真实设备组排除模拟器，桌面 / Web 独立保留；虚拟设备按 Android / Harmony 分组，各系统先列已有实例、最后显示对应系统新建入口，不要求工程已有对应目录。没有实例也由本人明确选择新建，不自动替换已有设备。子层 ← 或返回行回到真正上一层，Esc 取消。无设备或查询失败时仍可重新加载或进入虚拟设备分组。创建直接运行本包 `SimulatorCreators` 中的桌面原入口，不要求另装模拟器菜单；原 SDK 下载、许可证、确认、唯一命名和日志沿用。创建且启动成功后自动等待 Flutter 识别本次精确目标，再运行当前工程；启动已有实例后自动等待原设备身份并承接当前运行。Windows 不提供 iOS 本地模拟器。



<!-- JOBS_TERMINAL_STYLE_V1:BEGIN -->

> Windows 终端配色保护：支持完整颜色查询的交互控制台会先保存当前会话默认前景、背景与16色色表，再临时使用黑底白字和统一强调色；正常结束、业务失败及可捕获中断后恢复。用户运行中自行改动的颜色保留并提示，不修改用户主题、共享 Profile、注册表或全局策略。快照不包含进入前任意叠加的临时文字样式。非控制台、重定向、`NO_COLOR`、Sourcetree 及无法可靠保存／恢复颜色的环境保持原状态或降级为纯文本。

> 强制结束进程或终端崩溃无法保证自动恢复。恢复失败时保留并提示本轮 `%TEMP%\JobsTerminalStyle-<PID>-*.ps1` 恢复脚本，需在原控制台核对后运行；不要通过重置用户配置恢复。`-ExecutionPolicy Bypass` 如被入口使用，仅作用于本次子进程，不持久修改策略。

> 验证范围：已完成 PowerShell 语法、参数／退出与隔离生命周期核验；Windows 原生控制台的显示、按键与 `Ctrl+C` 实机验证尚未完成。

<!-- JOBS_TERMINAL_STYLE_V1:END -->

**运行前环境体检：** SDK 公共组件准备后，先展示 iOS / Android / 鸿蒙状态（Windows 的 iOS 不适用），并保留桌面 / Web 检查。设备选定或新建就绪后复查，基础 SDK、工程依赖和本次运行平台全部通过才继续目标缓存准备与应用启动；其它平台失败只显示原因。检查不下载、不切换 SDK、不生成平台文件；原有 SDK 自动获取流程保持独立。普通 Flutter 缺少 HAP、HDC / 工具链未就绪、缺少 `ohos/`、插件未声明鸿蒙适配、doctor 警告、超时或无法解析均明确显示，不能当作健康。详细检查与验证边界见[体检说明](./RunPreflight.ps1/README.md)。

**已连接设备的诊断展示：** HDC 目标和当前 Windows 原生 USB 调试接口也会独立检查；即使 SDK 尚不支持、工程没有 `ohos/` 或 HDC 工具缺失，已确认连接的设备仍显示“鸿蒙USB设备—已连接，环境未就绪”。选中该行会在当前运行流程自动准备兼容正式鸿蒙 SDK、项目 FVM 绑定、CLT 工具、缺失的 `ohos/` 及依赖；不需要另找配置入口。官方许可由本人确认，不下载模拟器镜像，不切换全局 SDK，不覆盖已有业务源码。准备后必须通过原有平台体检，并精确确认最初选中的设备才运行；插件缺实现、取消或失败会停止本轮。仅凭华为厂商名、普通 ADB、存储或键盘记录不会判为鸿蒙设备。

**启动虚拟设备：** 顶层选择“虚拟设备”，二级按 Android / Harmony 分组，Windows 不提供 iOS；每个系统先列已有实例，末尾为“新建 Android 虚拟设备”或“新建 Harmony 虚拟设备”。选中已有实例直接复用或启动，显式选择新建才调用随包创建器；没有实例时仍显示新建入口。先自动体检、补齐启动工具与必要配置，复检后才列已有实例；仅启动阶段不切业务工程 FVM、不生成 `ohos/` 或检查项目插件，只启动本人选中的一项，不创建替代设备。Android 仅更新当前 SDK 的正式 Emulator / ADB 组件，缺镜像只补原 AVD 的确切包；鸿蒙仅补原实例的确切 Release 镜像，SDK 配置需修复时先保留原字节备份。已运行实例直接复用，不自动停止、重置或清数据。之后按原 AVD serial / 原实例 UUID、路径与 HDC 端口等待 Flutter，项目平台或插件门禁不通过时保留实例，不运行 App，也不改选其它设备。

所有菜单 fzf 明确绑定 ↑ / ↓ 选择，子层 ← 返回，Esc 取消；仅显式设置 `JOBS_FLUTTER_RUNNER_FZF=0` 或非交互 / 输入重定向时使用文本序号菜单，`b` / `←` 返回、`q` 取消，空输入与无效输入不会默认启动；正常交互缺失 fzf 或体检失败时明确停止，修复后重试。官方更新目录或下载授权无法核验时停止启动，可在当前流程打开官方页面并返回本层重试，不读取浏览器 Cookie 或绕过认证。官方许可仍由本人接受，工具 / 镜像获取可取消，只有选定原虚拟设备且真实 HDC 已就绪、准备继续运行 Flutter 时，才按本工程约束核验兼容正式 SDK 并复用既有业务准备和门禁；项目绑定沿用精确备份，不切换全局 Flutter / Java。


<!-- JOBS_SOURCE_SCRIPT_PACKAGES -->
**同名脚本包：** [AndroidRuntime.ps1](./AndroidRuntime.ps1/README.md)、[Build.ps1](./Build.ps1/README.md)、[Invoke.ps1](./Invoke.ps1/README.md)、[Manage.ps1](./Manage.ps1/README.md)、[ManagementWorker.ps1](./ManagementWorker.ps1/README.md)、[OpenCmd.ps1](./OpenCmd.ps1/README.md)、[SdkDownloadOutput.ps1](./SdkDownloadOutput.ps1/README.md)。源码路径与发布目录的 flat 资源名分开维护。
<!-- /JOBS_SOURCE_SCRIPT_PACKAGES -->

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

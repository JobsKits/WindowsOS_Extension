# `FlutterTools run Scripts`

`Action.psm1` 接收工程根目录或单个 `.dart` 文件，按最近 `pubspec.yaml` 定位 Flutter 包，轻量排除无 main 的辅助文件与 `part`；完整语法交给编译器。请求与 `RunnerHost.cs` 保存 `Target` 并传给 `flutter run --machine -t`。后台会话按工程＋目标隔离，环境准备仍按工程管理；本目录随统一包复制，不依赖兄弟工程。菜单前置判断由上层 `FlutterRunTarget.h` 与原生桥接完成。

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、文件与能力](#jobs-toc-heading-2)
- [二、调用、依赖与参数](#jobs-toc-heading-3)
- [三、副作用、日志与验证](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

统一 Flutter 菜单中“Flutter 设备运行”的自包含业务核心，功能范围和菜单显示条件见 [统一包说明](../../../../README.md)。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、文件与能力 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 职责 |
| --- | --- |
| [Action.psm1](./Action.psm1) | 按“目前已有的真实设备 / 虚拟设备 / 其他运行目标（桌面 / Web）”分组，用 fzf 选择及刷新/取消，独立 RunnerHost 托管 Flutter 会话，提供重载、重启与停止；终端关闭策略见统一包说明。 |
| [Common.psm1](./Common.psm1) | 本模块随包运行路径、目标、进程调用和日志辅助。 |
| [SimulatorCreators](./SimulatorCreators/README.md) | 随包桌面 Android / Harmony 原创建入口及最小依赖，无需另装模拟器菜单。 |
| [RunnerHost.cs](./RunnerHost.cs) | 独立 Flutter 会话宿主，控制与日志由业务模块协调。 |

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、调用、依赖与参数 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

由统一包 [Scripts 调度](../../../README.md) 选择此 Action，再以明确 Target 调用 `Invoke-JobsFeature`；此目录不单独注册菜单或作为安装包。读取目标自己的 Flutter / FVM 绑定，缺少已锁 SDK 时停止；具体版本选择、构建产物、输入与默认随对应动作声明，不强行共用同一套写操作。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、副作用、日志与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

按“目前已有的真实设备 / 虚拟设备 / 其他运行目标（桌面 / Web）”分组，用 fzf 选择及刷新/取消，独立 RunnerHost 托管 Flutter 会话，提供重载、重启与停止；终端关闭策略见统一包说明。

业务输出、临时会话、配置快照及产物按该 Action 与统一包说明保存，实际日志位置由终端显示。项目路径作为数据传递，先校验目标再执行；取消不自动进入其它动作。本文按源码静态核对，未操作真实 SDK、项目、模拟器、菜单或注册表。

**SDK 初始化进度：** 随包的 [SdkDownloadOutput.ps1](./SdkDownloadOutput.ps1/SdkDownloadOutput.ps1) 实时展示 SDK 相关命令输出，保留机器响应、退出码和超时边界；第一次调用 Flutter 触发 Dart / 工具缓存下载时，不再等待命令结束才显示。本动作仍要求现有项目 SDK；缺失 SDK 的安装由统一工具包的安装 / 切换入口处理。PubGet 的 URL / 认证信息继续脱敏后显示和落盘；测试不接触真实 SDK、账户缓存或系统菜单。

**下载前版本上下文：** 每次 SDK 初始化／平台缓存获取前，先显示项目声明的 Flutter、本地 SDK 的版本标识与实际路径、目标内置 Dart、engine 提交以及宿主系统／架构，并写入同一获取日志。这里只读取本地文件及本地 Git exact tag，不执行 Flutter／Dart 探测或联网查询版本。Dart 只采用明确的源码版本文件、engine 匹配的版本 JSON 或 engine stamp 匹配的当前缓存；旧缓存及 `dart-sdk.old` 不作为目标版本。缺少可信依据时明确显示“未解析”，下载完成后再确认。

**设备发现前通用缓存：** 设备枚举前先执行 `flutter precache --universal`，准备 `sky_engine`、patched SDK 等通用资源，再进入短时设备查询。只准备通用制品，不强制下载全部平台；保留项目绑定 SDK，复用健康缓存。缺失制品沿随包网络选路实时显示真实下载进度，失败持续自动重试，Ctrl+C／停止结束；准备失败不会被误报为“无设备”，也不启动应用。

**Flutter SDK网络预检：** 下载／首次Dart自举／precache前，随包网络模块以真实小Range验证来源、TLS、字节和吞吐并择优；显式storage、Pub和代理（含空值）保留，AUTO仅核验官方／CFUG同对象及当前已配置代理，不猜端口、不改系统代理或Git。当前任务短期复用；真实获取失败会降权坏路线、轮换其它已验证候选并持续重试。FVM按实际api context来源处理，能力允许时Git与Dart制品分阶段；用户fork不改源。原生BITS按真实WinINET通道衡量，PAC未能有界解析时保留既有通道并明确未测速。详细边界见[随包选路模块](./SdkDownloadRoute.ps1/README.md)。

**运行设备分组：** 根 fzf 提供“目前已有的真实设备 / 虚拟设备 / 其他运行目标（桌面 / Web）/ 重新加载设备列表”。真实设备组排除模拟器，桌面 / Web 独立保留；虚拟设备按 Android / Harmony 分组，各系统先列已有实例、最后显示对应系统新建入口，不要求工程已有对应目录。没有实例也由本人明确选择新建，不自动替换已有设备。子层 ← 或返回行回到真正上一层，Esc 取消。无设备或查询失败时仍可重新加载或进入虚拟设备分组。创建直接运行本包 `SimulatorCreators` 中的桌面原入口，不要求另装模拟器菜单；原 SDK 下载、许可证、确认、唯一命名和日志沿用。创建且启动成功后自动等待 Flutter 识别本次精确目标，再运行当前工程；启动已有实例后自动等待原设备身份并承接当前运行。Windows 不提供 iOS 本地模拟器。



<!-- JOBS_TERMINAL_STYLE_V1:BEGIN -->

> Windows 终端配色保护：支持完整颜色查询的交互控制台会先保存当前会话默认前景、背景与16色色表，再临时使用黑底白字和统一强调色；正常结束、业务失败及可捕获中断后恢复。用户运行中自行改动的颜色保留并提示，不修改用户主题、共享 Profile、注册表或全局策略。快照不包含进入前任意叠加的临时文字样式。非控制台、重定向、`NO_COLOR`、Sourcetree 及无法可靠保存／恢复颜色的环境保持原状态或降级为纯文本。

> 强制结束进程或终端崩溃无法保证自动恢复。恢复失败时保留并提示本轮 `%TEMP%\JobsTerminalStyle-<PID>-*.ps1` 恢复脚本，需在原控制台核对后运行；不要通过重置用户配置恢复。`-ExecutionPolicy Bypass` 如被入口使用，仅作用于本次子进程，不持久修改策略。

> 验证范围：已完成 PowerShell 语法、参数／退出与隔离生命周期核验；Windows 原生控制台的显示、按键与 `Ctrl+C` 实机验证尚未完成。

<!-- JOBS_TERMINAL_STYLE_V1:END -->

**运行前环境体检：** SDK 公共组件准备后先展示 iOS / Android / 鸿蒙状态（Windows 的 iOS 不适用）。设备选择或新建结束后复查，基础环境和本次运行平台全部通过才继续目标缓存准备与应用启动；其它平台未就绪只显示原因。检查不下载、不切换 SDK、不生成平台文件；原有 SDK 自动准备保持独立。普通 SDK 缺少 HAP、HDC / 工具链缺失、`ohos/` 或插件适配缺失、doctor 警告、超时和无法解析均明确显示。详细规则及验证边界见[体检说明](./RunPreflight.ps1/README.md)。

**已连接设备的诊断展示：** HDC 目标和当前 Windows 原生 USB 调试接口也会独立检查；即使 SDK 尚不支持、工程没有 `ohos/` 或 HDC 工具缺失，已确认连接的设备仍显示“鸿蒙USB设备—已连接，环境未就绪”。选中该行会在当前运行流程自动准备兼容正式鸿蒙 SDK、项目 FVM 绑定、CLT 工具、缺失的 `ohos/` 及依赖；不需要另找配置入口。官方许可由本人确认，不下载模拟器镜像，不切换全局 SDK，不覆盖已有业务源码。准备后必须通过原有平台体检，并精确确认最初选中的设备才运行；插件缺实现、取消或失败会停止本轮。仅凭华为厂商名、普通 ADB、存储或键盘记录不会判为鸿蒙设备。

**启动虚拟设备：** 顶层选择“虚拟设备”，二级按 Android / Harmony 分组，Windows 不提供 iOS；每个系统先列已有实例，末尾为“新建 Android 虚拟设备”或“新建 Harmony 虚拟设备”。选中已有实例直接复用或启动，显式选择新建才调用随包创建器；没有实例时仍显示新建入口。先自动体检、补齐启动工具与必要配置，复检后才列已有实例；仅启动阶段不切业务工程 FVM、不生成 `ohos/` 或检查项目插件，只启动本人选中的一项，不创建替代设备。Android 仅更新当前 SDK 的正式 Emulator / ADB 组件，缺镜像只补原 AVD 的确切包；鸿蒙仅补原实例的确切 Release 镜像，SDK 配置需修复时先保留原字节备份。已运行实例直接复用，不自动停止、重置或清数据。之后按原 AVD serial / 原实例 UUID、路径与 HDC 端口等待 Flutter，项目平台或插件门禁不通过时保留实例，不运行 App，也不改选其它设备。

所有菜单 fzf 明确绑定 ↑ / ↓ 选择，子层 ← 返回，Esc 取消；仅显式设置 `JOBS_FLUTTER_RUNNER_FZF=0` 或非交互 / 输入重定向时使用文本序号菜单，`b` / `←` 返回、`q` 取消，空输入与无效输入不会默认启动；正常交互缺失 fzf 或体检失败时明确停止，修复后重试。官方更新目录或下载授权无法核验时停止启动，可在当前流程打开官方页面并返回本层重试，不读取浏览器 Cookie 或绕过认证。官方许可仍由本人接受，工具 / 镜像获取可取消，只有选定原虚拟设备且真实 HDC 已就绪、准备继续运行 Flutter 时，才按本工程约束核验兼容正式 SDK 并复用既有业务准备和门禁；项目绑定沿用精确备份，不切换全局 Flutter / Java。


<!-- JOBS_SOURCE_SCRIPT_PACKAGES -->
**同名脚本包：** [AndroidRuntime.ps1](./AndroidRuntime.ps1/README.md)、[SdkDownloadOutput.ps1](./SdkDownloadOutput.ps1/README.md)。源码路径与发布目录的 flat 资源名分开维护。
<!-- /JOBS_SOURCE_SCRIPT_PACKAGES -->

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

# `FlutterTools run Scripts`

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
| [Action.psm1](./Action.psm1) | 查询设备、编号选择及刷新/取消，独立 RunnerHost 托管 Flutter 会话，提供重载、重启与停止；终端关闭策略见统一包说明。 |
| [Common.psm1](./Common.psm1) | 本模块随包运行路径、目标、进程调用和日志辅助。 |
| [RunnerHost.cs](./RunnerHost.cs) | 独立 Flutter 会话宿主，控制与日志由业务模块协调。 |

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、调用、依赖与参数 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

由统一包 [Scripts 调度](../../../README.md) 选择此 Action，再以明确 Target 调用 `Invoke-JobsFeature`；此目录不单独注册菜单或作为安装包。读取目标自己的 Flutter / FVM 绑定，缺少已锁 SDK 时停止；具体版本选择、构建产物、输入与默认随对应动作声明，不强行共用同一套写操作。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、副作用、日志与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

查询设备、编号选择及刷新/取消，独立 RunnerHost 托管 Flutter 会话，提供重载、重启与停止；终端关闭策略见统一包说明。

业务输出、临时会话、配置快照及产物按该 Action 与统一包说明保存，实际日志位置由终端显示。项目路径作为数据传递，先校验目标再执行；取消不自动进入其它动作。本文按源码静态核对，未操作真实 SDK、项目、模拟器、菜单或注册表。

**SDK 初始化进度：** 随包的 [SdkDownloadOutput.ps1](./SdkDownloadOutput.ps1) 实时展示 SDK 相关命令输出，保留机器响应、退出码和超时边界；第一次调用 Flutter 触发 Dart / 工具缓存下载时，不再等待命令结束才显示。本动作仍要求现有项目 SDK；缺失 SDK 的安装由统一工具包的安装 / 切换入口处理。PubGet 的 URL / 认证信息继续脱敏后显示和落盘；测试不接触真实 SDK、账户缓存或系统菜单。

**下载前版本上下文：** 每次 SDK 初始化／平台缓存获取前，先显示项目声明的 Flutter、本地 SDK 的版本标识与实际路径、目标内置 Dart、engine 提交以及宿主系统／架构，并写入同一获取日志。这里只读取本地文件及本地 Git exact tag，不执行 Flutter／Dart 探测或联网查询版本。Dart 只采用明确的源码版本文件、engine 匹配的版本 JSON 或 engine stamp 匹配的当前缓存；旧缓存及 `dart-sdk.old` 不作为目标版本。缺少可信依据时明确显示“未解析”，下载完成后再确认。

**设备发现前通用缓存：** 设备枚举前先执行 `flutter precache --universal`，准备 `sky_engine`、patched SDK 等通用资源，再进入短时设备查询。只准备通用制品，不强制下载全部平台；保留项目绑定 SDK，复用健康缓存。缺失制品沿随包网络选路实时显示真实下载进度，失败持续自动重试，Ctrl+C／停止结束；准备失败不会被误报为“无设备”，也不启动应用。

**Flutter SDK网络预检：** 下载／首次Dart自举／precache前，随包网络模块以真实小Range验证来源、TLS、字节和吞吐并择优；显式storage、Pub和代理（含空值）保留，AUTO仅核验官方／CFUG同对象及当前已配置代理，不猜端口、不改系统代理或Git。当前任务短期复用；真实获取失败会降权坏路线、轮换其它已验证候选并持续重试。FVM按实际api context来源处理，能力允许时Git与Dart制品分阶段；用户fork不改源。原生BITS按真实WinINET通道衡量，PAC未能有界解析时保留既有通道并明确未测速。详细边界见[随包选路模块](./SdkDownloadRoute.ps1/README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

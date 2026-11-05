# `FlutterTools android-support Scripts`

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

**SDK 获取策略：** Java、Android Command-Line Tools、SDK 组件和模拟器系统镜像的下载／远程清单获取失败后持续自动重试，直到成功或按 Ctrl+C／停止主动结束，无须确认重试；等待逐步延长且最多 30 秒。实时显示真实输出，重试日志追加到系统临时目录的 `JobsSdkAcquisition-进程号.log`。归档校验失败仅重取本次私有文件；成功后清理本次暂存，失败／取消保留未提交暂存并显示位置，不删除已有健康 SDK。许可证、架构／参数／权限等确定的本地问题单独处理；创建和启动 AVD 不在重试循环中。

## 🔥 <span id="前言">前言</span>

统一 Flutter 菜单中“Android 运行支持”的自包含业务核心，功能范围和菜单显示条件见 [统一包说明](../../../../README.md)。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、文件与能力 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 职责 |
| --- | --- |
| [Action.psm1](./Action.psm1) | 复用或检查已有 Android SDK、Java、AVD；运行前按现有项目与设备选择调用，不把创建 / 安装混为只读诊断。 |
| [Common.psm1](./Common.psm1) | 本模块随包运行路径、目标、进程调用和日志辅助。 |

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、调用、依赖与参数 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

由统一包 [Scripts 调度](../../../README.md) 选择此 Action，再以明确 Target 调用 `Invoke-JobsFeature`；此目录不单独注册菜单或作为安装包。读取目标自己的 Flutter / FVM 绑定，缺少已锁 SDK 时停止；具体版本选择、构建产物、输入与默认随对应动作声明，不强行共用同一套写操作。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、副作用、日志与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

复用或检查已有 Android SDK、Java、AVD；运行前按现有项目与设备选择调用，不把创建 / 安装混为只读诊断。

业务输出、临时会话、配置快照及产物按该 Action 与统一包说明保存，实际日志位置由终端显示。项目路径作为数据传递，先校验目标再执行；取消不自动进入其它动作。本文按源码静态核对，未操作真实 SDK、项目、模拟器、菜单或注册表。

**Flutter SDK网络预检：** 下载／首次Dart自举／precache前，随包网络模块以真实小Range验证来源、TLS、字节和吞吐并择优；显式storage、Pub和代理（含空值）保留，AUTO仅核验官方／CFUG同对象及当前已配置代理，不猜端口、不改系统代理或Git。当前任务短期复用；真实获取失败会降权坏路线、轮换其它已验证候选并持续重试。FVM按实际api context来源处理，能力允许时Git与Dart制品分阶段；用户fork不改源。原生BITS按真实WinINET通道衡量，PAC未能有界解析时保留既有通道并明确未测速。详细边界见[随包选路模块](./SdkDownloadRoute.ps1/README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

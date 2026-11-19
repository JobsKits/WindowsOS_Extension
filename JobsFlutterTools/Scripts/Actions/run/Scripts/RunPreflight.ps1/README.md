# 运行前环境体检

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、检查与门禁](#checks)
- [二、副作用与验证边界](#boundaries)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

供 [**Flutter**](https://flutter.dev/) 运行器加载的函数库；不作为独立安装或修复入口。

## 一、<span id="checks">检查与门禁</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- SDK 准备结束后，先展示 iOS、Android、鸿蒙的检查结果；Windows 的 iOS 显示“不适用”。同时展示现有桌面和 Web 检查。
- 通过同源 [**Dart**](https://dart.dev) 和当前 SDK 的包索引执行随包 `DoctorScope.dart`，复用官方本地工具链验证器；不执行公网资源检测、设备扫描或远端版本查询。全部检查完成后一次输出结构化结果，按平台解析；警告、执行失败、超时和无法解析均不算通过。检查 [**fvm**](https://fvm.app) 声明、依赖索引和本地依赖路径。
- Android 复用随包 SDK / Command-Line Tools 定位器，核对 ADB 与工程 Gradle wrapper。鸿蒙检查 HAP 能力、DevEco / CLT、HDC、Node、OHPM、Hvigor、Java、SDK 组件、`ohos/` 清单及插件平台声明；普通 SDK 未支持鸿蒙也会显示失败原因。
- 体检明细逐条换行，通过显示绿色 ✅，未满足显示整条红色 ❌；纯文本保留符号。所选 Android / Harmony 缺项直接准备，随后重新检查；其它缺失移动平台可选择回车在私有工程与SDK副本后台准备，任意非空输入跳过，后台不阻塞当前运行。[自动准备说明](./RepairRunEnvironment.ps1/README.md)列出副作用、隔离缓存及待应用边界。[终端展示说明](./RunDisplay.ps1/README.md)说明URL、错误正文与结构标签配色。
- 同一轮、同一工程及绑定 SDK 的首份报告完整展示；后续复检只显示状态或详情变化的检查项，未变化的鸿蒙插件清单不重复。全部结果未变化时只显示简短复检提示。工程路径、Flutter 入口、实际 SDK、本地 engine / 版本身份或 FVM 声明改变后重新全量展示；新一轮运行显式重置。展示快照只保存内存中的比较值，不缓存体检结果，不减少真实复检或运行门禁。
- 设备选择或新建结束后重新检查；只有基础环境和所选平台全部通过，才继续目标平台缓存准备和应用启动。其它平台未就绪不阻断本次健康目标。

- HDC 目标和当前 Windows 原生 USB 调试接口也会独立检查；即使 SDK 尚不支持、工程没有 `ohos/` 或 HDC 工具缺失，已确认连接的设备仍显示“鸿蒙USB设备—已连接，环境未就绪”。选中该行会在当前运行流程自动准备兼容正式鸿蒙 SDK、项目 FVM 绑定、CLT 工具、缺失的 `ohos/` 及依赖；不需要另找配置入口。官方许可由本人确认，不下载模拟器镜像，不切换全局 SDK，不覆盖已有业务源码。准备后必须通过原有平台体检，并精确确认最初选中的设备才运行；插件缺实现、取消或失败会停止本轮。仅凭华为厂商名、普通 ADB、存储或键盘记录不会判为鸿蒙设备。

## 二、<span id="boundaries">副作用与验证边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

检查函数不下载、不切换 SDK、不生成项目平台、不启动应用；原有 SDK 自动准备仍在独立阶段执行，选定目标后的平台缓存准备仍保留。缺少 Dart / snapshot 时只报告缺失，不经 Flutter shim 自举。官方工具自身可能读取配置、执行网络探测或维护诊断缓存；体检通过不代表实际编译、签名或真机业务已通过。

状态函数为 `Get-JobsRunnerPreflight`，显示函数为 `Write-JobsRunnerPreflight`，门禁函数为 `Assert-JobsRunnerPreflight`。 运行链调用显示函数时同时传入当前 Flutter 入口与工程路径；未提供可靠作用域的独立调用保留每次全量展示。回归入口见仓库 `Tests/FlutterRunnerPreflight.Tests.ps1/`；Windows 原生 Explorer 与真实设备须另验。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

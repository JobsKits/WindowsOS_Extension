# 启动已有虚拟设备

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、资源与命令](#jobs-toc-heading-2)
- [二、验证边界](#jobs-toc-heading-3)
- [三、官方目录与本人提供的证据](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

**启动虚拟设备：** 顶层选择“启动虚拟设备”，二级仅“启动Android模拟器 / 启动鸿蒙模拟器”，Windows 不提供 iOS。先自动体检、补齐启动工具与必要配置，复检后才列已有实例；仅启动阶段不切业务工程 FVM、不生成 `ohos/` 或检查项目插件，只启动本人选中的一项，不创建替代设备。Android 仅更新当前 SDK 的正式 Emulator / ADB 组件，缺镜像只补原 AVD 的确切包；鸿蒙仅补原实例的确切 Release 镜像，SDK 配置需修复时先保留原字节备份。已运行实例直接复用，不自动停止、重置或清数据。之后按原 AVD serial / 原实例 UUID、路径与 HDC 端口等待 Flutter，项目平台或插件门禁不通过时保留实例，不运行 App，也不改选其它设备。

所有菜单 fzf 明确绑定 ↑ / ↓ 选择，子层 ← 返回，Esc 取消；正常交互中 fzf 缺失或体检失败时明确停止。仅本人显式关闭 fzf 或非交互输入时使用文本序号菜单，`b` / `←` 返回、`q` 取消，空输入与无效输入不会默认启动。官方更新目录或下载授权无法核验时停止启动，可在当前流程打开官方页面并返回本层重试，不读取浏览器 Cookie 或绕过认证。官方许可仍由本人接受，工具 / 镜像获取可取消，只有选定原虚拟设备且真实 HDC 已就绪、准备继续运行 Flutter 时，才按本工程约束核验兼容正式 SDK 并复用既有业务准备和门禁；项目绑定沿用精确备份，不切换全局 Flutter / Java。

鸿蒙先真实查询官方 Windows x64 Release 目录和下载授权，校验包名、版本、大小、SHA-256 与受信 HTTPS 地址，按实际 `version.txt` 比较更新；版本无法核验或登录 / 协议阻止目录获取时明确未就绪，不能用固定旧版本代替通过。可在当前流程打开官方页、完成本人操作后重试本层；不读取 Cookie 或绕过认证。只有最新包完整核验后才自动侧装并复检，旧安装保留。仅当当前 `-help` 明确公开能力时，用官方 `-screenProfileList -deviceType phone -details -update` 刷新机型目录。该刷新不代表 CLT 二进制升级，也不改变已有实例系统版本。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、资源与命令</span><!-- jobs-toc:heading-end -->

仅由运行器加载，复用随包 `AndroidRuntime.ps1`、`PrepareHarmonyRun.ps1` 和 `SimulatorCreators/Harmony`。整体目录随独立包、聚合包运输；不访问兄弟源码目录。

鸿蒙使用官方 [`Emulator -list -details` 与 `-start`](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-command-line/)，带原实例 `-instancePath`，已明确的镜像路径用 `-imageRoot`；不传 reset、delete 或启动 force。镜像确切补齐仅使用官方 `-install`，本人接受许可后才能下载。需要开发者账号授权、区域限制或官方拒绝时保留失败，不绕过。Android 正式通道依据[官方 sdkmanager 文档](https://developer.android.com/tools/sdkmanager)，只处理当前 SDK 的 `emulator` / `platform-tools`，不执行整体 `--update`。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、验证边界</span><!-- jobs-toc:heading-end -->

Android 更新检查同时保留 stdout / stderr，按真实 `Installed packages` 四列、`Available Packages` 三列及可选 `Available Updates` 三列表交叉核验正式版本。空、截断、未知输出、XML 错误、预览或版本矛盾不能当作无更新；确定的目录 / 参数错误不会作为网络故障循环获取。

已有 AVD 在菜单出现前固定路径、完整配置和原生卷号 / File ID；选择后、补镜像后再次核验。等待 Flutter 后复查原文件对象、稳定实例字段及 ADB 的 serial → 原 AVD 名称对应，防止同名同内容重建或端口被其它实例复用。启动期间允许非身份运行字段变化。鸿蒙同样在菜单前固定身份；启动后核验原 UUID 等稳定身份并记录完整配置，长时间工程准备结束后再核验原身份、完整配置和原 HDC 端口，不能因端口字符串相同而复用其它实例。

`Tests/FlutterRunnerVirtualStart.Tests.ps1/` 在临时实例上验证实际编排、配置备份、原身份、argv、返回取消和失败停止，外部获取与启动边界使用假命令；另有设备分组与 release 闭包测试。当前宿主仅编译 Windows FileIdInfo 提供器并用受控文件身份边界验证重建检测，没有执行真实 Windows kernel32 调用、下载、官方许可、模拟器、注册菜单或业务应用。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、官方目录与本人提供的证据</span><!-- jobs-toc:heading-end -->

先通过官方公开文档接口读取当前兼容 Release 的 `Command line tools` 表，仅取 `Command Line` 行；本机实际 `version.txt` 等于或高于该版本且组件健康时直接继续能力复检，不强求匿名下载授权。工具缺失、落后或公开目录无法核验时，再查询官方 Windows x64 Release 目录和下载授权。HTML、未知 schema、401、`90910011`、缺 hash 或非官方 URL 都不能当作“无更新”。浏览器登录不会自动为匿名脚本请求提供 CSRF，不承诺打开页面后重试必然成功。

本层可明确选择本人取得的官方元数据 JSON。字段为：`source` 固定官方 delegate URL、`checkedAtUtc` 为最近 24 小时内本人核验的 UTC 时间、`versionResponse` 为官方 `getToolVersionList` 的完整原始 JSON 对象（保留外层 returnCode / resJson 或内层 code / value）；另提供完整 `downloadResponse`，或本机官方 ZIP 的绝对 `archivePath`。不填写猜测下载 URL / 摘要，不将包版本号当作目录证据。脚本仍校验明确 Release、Win1、精确包名、官方大小与 SHA-256，并在安全解压后核对实际 `version.txt` 与必要结构；匿名在线目录仍不可访问时会如实说明。本轮元数据仅在内存读取，归档与回执使用本轮私有目录；Windows 子目录仅当前用户与 SYSTEM 可访问。日志显示脱敏 URL，下载保留原签名地址，不记录认证 Cookie。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>


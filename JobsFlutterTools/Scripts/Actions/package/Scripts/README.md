# `FlutterTools package Scripts`

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

统一 Flutter 菜单中“Flutter 多平台打包”的自包含业务核心，功能范围和菜单显示条件见 [统一包说明](../../../../README.md)。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、文件与能力 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 职责 |
| --- | --- |
| [Action.psm1](./Action.psm1) | Android APK/AAB 与 OpenHarmony HAP/APP；BUILD_MODE 默认 release，Android 可设 FLAVOR，OpenHarmony 需要适配 SDK 并拒绝 flavor。 |
| [Common.psm1](./Common.psm1) | 本模块随包运行路径、目标、进程调用和日志辅助。 |

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、调用、依赖与参数 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

`build-harmony` 复用本模块的 `Invoke-JobsFlutterHarmonyAction`，固定项目 FVM、`all / release` 和空 flavor：回车确认后获取一次依赖，依次构建并验证非空 HAP、APP，任一步失败停止。环境中的 mode、单产物、flavor 和 SDK 覆盖不改变快捷动作，不再弹 fzf 平台/包型选择。合法 Flutter 根目录可看到已选入口；缺少有效 `ohos/` 与工程配置时明确提示先适配，不启动工具。完整说明见[统一包鸿蒙打包](../../../../README.md#鸿蒙-hap--app-打包)。

由统一包 [Scripts 调度](../../../README.md) 选择此 Action，再以明确 Target 调用 `Invoke-JobsFeature`；此目录不单独注册菜单或作为安装包。读取目标自己的 Flutter / FVM 绑定，缺少已锁 SDK 时停止；具体版本选择、构建产物、输入与默认随对应动作声明，不强行共用同一套写操作。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、副作用、日志与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

Android APK/AAB 与 OpenHarmony HAP/APP；BUILD_MODE 默认 release，Android 可设 FLAVOR，OpenHarmony 需要适配 SDK 并拒绝 flavor。

业务输出、临时会话、配置快照及产物按该 Action 与统一包说明保存，实际日志位置由终端显示。项目路径作为数据传递，先校验目标再执行；取消不自动进入其它动作。本文按源码静态核对，未操作真实 SDK、项目、模拟器、菜单或注册表。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

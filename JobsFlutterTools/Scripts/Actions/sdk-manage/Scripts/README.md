# `FlutterTools sdk-manage Scripts`

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

统一 Flutter 菜单中“项目 FVM 选版”的自包含业务核心，功能范围和菜单显示条件见 [统一包说明](../../../../README.md)。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、文件与能力 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 职责 |
| --- | --- |
| [Action.psm1](./Action.psm1) | 查询官方发行版与就绪缓存，用 fzf 单选精确版本；回车最终执行、非空取消，写前备份并保留原配置字段，不设全局版本或自动 pub get。 |
| [Common.psm1](./Common.psm1) | 本模块随包运行路径、目标、进程调用和日志辅助。 |

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、调用、依赖与参数 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

由统一包 [Scripts 调度](../../../README.md) 选择此 Action，再以明确 Target 调用 `Invoke-JobsFeature`；此目录不单独注册菜单或作为安装包。读取目标自己的 Flutter / FVM 绑定，缺少已锁 SDK 时停止；具体版本选择、构建产物、输入与默认随对应动作声明，不强行共用同一套写操作。

本 worker 仅接受官方 Flutter 来源；项目中的未知 fork、自定义版本或非官方有效 FVM 来源会在下载前拒绝。本统一包按约定管理的 CPF OpenHarmony 绑定，由上级调度转入 `HarmonySdk.psm1` 的影子工程反向流程，验证官方 SDK 后再发布，不直接在真实项目清空配置或向 CPF 缓存安装原生 SDK。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、副作用、日志与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

查询官方发行版与就绪缓存，用 fzf 单选精确版本；回车最终执行、非空取消，写前备份并保留原配置字段，不设全局版本或自动 pub get。

业务输出、临时会话、配置快照及产物按该 Action 与统一包说明保存，实际日志位置由终端显示。项目路径作为数据传递，先校验目标再执行；取消不自动进入其它动作。本文按源码静态核对，未操作真实 SDK、项目、模拟器、菜单或注册表。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

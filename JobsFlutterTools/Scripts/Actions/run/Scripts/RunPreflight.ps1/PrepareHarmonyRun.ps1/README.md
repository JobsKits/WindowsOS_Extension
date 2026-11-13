# 当前运行流程准备鸿蒙环境

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、准备顺序](#jobs-toc-heading-2)
- [二、失败与验证](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

由运行器在选中未就绪鸿蒙设备后调用 `Invoke-JobsRunnerPrepareHarmony`，返回本次 SDK、进程环境与原设备 ID；不是独立菜单入口。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、准备顺序</span><!-- jobs-toc:heading-end -->

复用当前兼容 HAP SDK，或按工程真实 Flutter / Dart 约束从正式 tag 自动选择候选；锁定并复核 commit 后备份并原子发布当前项目 FVM 绑定。SDK 缓存与项目绑定独立于全局版本。随后准备 CLT 编译工具、必要 Java 17，官方许可由本人阅读接受；不创建模拟器、不下载镜像。

缺少 `ohos/` 时，先在项目内唯一临时目录生成并核对平台清单，再仅原子移入 `ohos/`；不复制默认 `lib/`，不覆盖已有平台目录。执行 pub get、检查原生插件声明，再执行工程自身 OHPM / Hvigor wrapper。复检全部通过后，HDC 与 Flutter 必须共同识别最初设备的精确 ID，才交回正常运行链。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、失败与验证</span><!-- jobs-toc:heading-end -->

不改写公司或第三方插件，不伪造鸿蒙实现；缺项按行列出并停止。许可取消、本地永久错误、commit 变化、体检失败或原设备失联均不会启动应用或改跑另一台设备。准备阶段不整体重放业务命令；已完成的 SDK 缓存与项目绑定备份保留。环境变量只传给本次运行并精确恢复。

隔离回归位于 `Tests/HarmonyRunPrepare.Tests.ps1/`。测试不联网、不安装、不改变用户项目；真实 Windows 下载、官方许可、驱动、签名与 HAP 构建仍须在目标机验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

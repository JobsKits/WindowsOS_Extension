# 运行环境自动准备

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

供 [**Flutter**](https://flutter.dev/) 运行器加载。所选 Android / Harmony 缺失环境直接准备并复检，不再询问是否补齐；Android 按当前工程及绑定 SDK 的 compileSdk / Build Tools / NDK / CMake 声明准备组件，配置写入前保留备份。Harmony 复用兼容正式 SDK、CLT、项目平台及依赖准备；官方许可、账号权限与不可自动判断的工程约束仍如实停止。

其它未选择且缺失的移动平台询问“回车后台补齐；任意字符+回车不补”。回车后独立无窗口 PowerShell 在本项目运行数据的 `EnvironmentPreparation/<系统>/` 中建立私有工程、SDK及用户缓存副本，后台获取不等待当前运行；不会改动当前工程 FVM、平台文件、依赖索引或当前 SDK。完整 SDK 副本可能占用较多磁盘。遇到外部链接或共享 Git worktree 布局时明确失败，不跟随到原目录。

运行日志界面按 `e` 可停止本工程的后台准备，当前 Flutter 会话保留。worker 的 PID 与启动时间须同时匹配才停止；Windows worker 持有只属于本轮的 Kill-on-close Job，worker 被终止时一并回收下载子树，文件锁由进程结束释放。正常完成解除本轮 Job 的退出回收后离开，失败与停止保留现场。

同项目同平台任务用独占文件锁保护；Android 前台准备另有 SDK 独占锁。后台日志为 `prepare-<运行编号>.log`，状态为 `state.txt`，成功后 `prepared.txt` 记录准备位置及待应用说明。后台不自动发布工程变化；当前运行结束后重新发起相应平台运行，由前台核验后应用。已有有效写者不会被抢占，失败与取消保留现场；官方许可需要交互时后台记录未完成，不能代替本人接受。

隔离回归验证直接准备、其它平台选择、私有缓存、原工程与SDK保全及锁冲突；不执行真实SDK安装、后台系统进程或业务运行。Windows PowerShell 5.1 / 原生控制台与真实工具获取须另验。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

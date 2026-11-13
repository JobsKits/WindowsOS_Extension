# Flutter Runner 设备分组回归

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

使用 PowerShell 与临时工程验证独立 Runner 和统一 Flutter Tools 内嵌 run；不安装 SDK、创建真实模拟器、注册菜单或运行用户项目。

## 一、<span id="usage">运行与覆盖</span>

```powershell
pwsh -NoProfile -File ./FlutterRunnerDeviceGroups.Tests.ps1
```

另覆盖“鸿蒙USB设备—已连接，环境未就绪”诊断行、查看缺项后返回已有列表、继续选择真实目标和取消不运行；硬件发现使用隔离数据，不读取测试机真实 USB / HDC。

设备查询及选择输入使用隔离函数，保留真实根层 / 子层编排和工程平台过滤，覆盖已有 / 启动虚拟 / 新建分组、Harmony 入口不依赖 ohos 目录、返回、取消、空列表刷新、只启动已有 Android / 鸿蒙、创建成功后直接运行精确目标、延迟发现、超时、取消与平台不匹配。另在中文空格路径生成独立 release，核对创建器闭包与原桌面源码哈希；仅替换临时 release 中的唯一入口为假脚本，实际运行子 PowerShell 核对 Android 显式新建参数、结构化结果文件与父环境恢复、无结果不运行、平台错误拒绝及 Harmony 非零退出返回；完整运行夹具验证新建与 Flutter 启动均只执行一次，HDC 夹具验证鸿蒙目标精确映射。

## 二、<span id="limits">依赖与边界</span>

需要现有 PowerShell 7 运行本跨平台回归；正常产品仍调用 Windows 系统 PowerShell。测试产生的临时目录在退出时清理。Windows PowerShell 5.1 / 原生控制台 fzf、Explorer 菜单、SDK 获取、真实模拟器及 Flutter 工程运行须在目标机另验。其它 Runner 回归见同级 Tests 的 `FlutterRunner.Tests.ps1` 与 `FlutterRunnerAndroid.Tests.ps1`。



<!-- JOBS_TERMINAL_STYLE_V1:BEGIN -->

> Windows 终端配色保护：支持完整颜色查询的交互控制台会先保存当前会话默认前景、背景与16色色表，再临时使用黑底白字和统一强调色；正常结束、业务失败及可捕获中断后恢复。用户运行中自行改动的颜色保留并提示，不修改用户主题、共享 Profile、注册表或全局策略。快照不包含进入前任意叠加的临时文字样式。非控制台、重定向、`NO_COLOR`、Sourcetree 及无法可靠保存／恢复颜色的环境保持原状态或降级为纯文本。

> 强制结束进程或终端崩溃无法保证自动恢复。恢复失败时保留并提示本轮 `%TEMP%\JobsTerminalStyle-<PID>-*.ps1` 恢复脚本，需在原控制台核对后运行；不要通过重置用户配置恢复。`-ExecutionPolicy Bypass` 如被入口使用，仅作用于本次子进程，不持久修改策略。

> 验证范围：已完成 PowerShell 语法、参数／退出与隔离生命周期核验；Windows 原生控制台的显示、按键与 `Ctrl+C` 实机验证尚未完成。

<!-- JOBS_TERMINAL_STYLE_V1:END -->

**启动虚拟设备：** 顶层选择“启动虚拟设备”，二级仅“启动Android模拟器 / 启动鸿蒙模拟器”，Windows 不提供 iOS。先自动体检、补齐启动工具与必要配置，复检后才列已有实例；仅启动阶段不切业务工程 FVM、不生成 `ohos/` 或检查项目插件，只启动本人选中的一项，不创建替代设备。Android 仅更新当前 SDK 的正式 Emulator / ADB 组件，缺镜像只补原 AVD 的确切包；鸿蒙仅补原实例的确切 Release 镜像，SDK 配置需修复时先保留原字节备份。已运行实例直接复用，不自动停止、重置或清数据。之后按原 AVD serial / 原实例 UUID、路径与 HDC 端口等待 Flutter，项目平台或插件门禁不通过时保留实例，不运行 App，也不改选其它设备。

所有菜单 fzf 明确绑定 ↑ / ↓ 选择，子层 ← 返回，Esc 取消；fzf 缺失或体检失败时使用文本序号菜单，`b` / `←` 返回、`q` 取消，空输入与无效输入不会默认启动。官方更新目录或下载授权无法核验时停止启动，可在当前流程打开官方页面并返回本层重试，不读取浏览器 Cookie 或绕过认证。官方许可仍由本人接受，工具 / 镜像获取可取消，只有选定原虚拟设备且真实 HDC 已就绪、准备继续运行 Flutter 时，才按本工程约束核验兼容正式 SDK 并复用既有业务准备和门禁；项目绑定沿用精确备份，不切换全局 Flutter / Java。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

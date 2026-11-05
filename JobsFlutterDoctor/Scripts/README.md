# `JobsFlutterDoctor/Scripts`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、文件与入口](#entrypoints)
- [二、维护与验证](#maintenance)

</details>
<!-- jobs-toc:end -->

---

**面板外观与语言：** 总面板和独立功能面板右上角均可选择“黑夜 / 白天 / 跟随系统”以及“简体中文 / 繁體中文 / English / 跟随系统”，默认均跟随系统，切换立即生效并保留当前勾选、任务和日志。窄窗或长文案放不下时，工具组移至标题下一行并保持右对齐；极窄窗口将主题、语言分两行，下拉控件右边缘对齐。选择保存在当前用户的 `%LOCALAPPDATA%\Jobs\WindowsExtension\panel-preferences.json`，下次打开自动恢复；保存失败在面板显示原因。跟随系统每秒检查应用主题和当前用户显示语言，繁体中文界面使用繁体、其它中文使用简体，未支持语言回退英文；Windows 显示语言通常须重新登录才生效。切换只影响管理面板，已安装右键菜单标题及后台工具的原始日志保持各自语言。

## 🔥 <span id="前言">前言</span>

本目录只实现本包的“Flutter 项目体检”菜单与终端动作。运行和独立安装不查找父目录或相邻功能；[功能说明](../README.md)包含依赖、交互和风险。

## 一、<span id="entrypoints">文件与入口</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文件 | 职责 |
| --- | --- |
| `Manage.ps1` / `PackageInstaller.psm1` | 独立安装卸载、release、哈希、备份、COM 注册与事务恢复；优先从包根 `Manage.cmd` 打开。 |
| `Build.ps1` | 仅用已安装 MSVC / Windows SDK 编译本包原生 DLL；不下载或注册。 |
| `ContextMenu.cpp` / `FlutterProject.h` / `ContextMenu.def` | Explorer 内只读本地 pubspec，精确单选根目录识别；不在 Explorer 内执行 PowerShell、Flutter 或 CLR。 |
| `OpenCmd.ps1` | 固定命令启动 CMD，目标与入口经环境变量传递。 |
| `Invoke.ps1` / `Common.psm1` | 校验当前包安装状态、解析目标、调用本包 Action、显示错误和维护日志。 |
| `Action.psm1` | 本功能业务；同源 SDK、逐行输出、失败停止和脱敏日志。 |
| `Check.ps1` | 只读项目与生成计划，不启动 SDK 子进程。 |

## 二、<span id="maintenance">维护与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

四份基础机制在开发时由总工程模板校验，`PackageInstaller.psm1` 是本包明确声明的覆盖项，负责原生 COM 构建事务，其余三份保持模板一致。业务入口仅导出 `Invoke-JobsFeature`；不要将项目路径拼入 `-Command` 或 CMD 可执行文本。PowerShell 文件使用 UTF-8 BOM 与 CRLF，CMD 正文使用 ASCII 与 CRLF，兼容系统 PowerShell 5.1。

[独立回归](../../Tests/FlutterDoctorCodegen.Tests.ps1)使用临时项目与假工具，不执行真实项目生成。真实安装需 Windows 桌面及原生编译环境；本机 macOS 逻辑回归只能验证配置 / 参数 / 事务计划，不能证明 Explorer 内 COM 已成功加载。日志和卸载边界见[功能说明](../README.md#check-and-logs)。

本目录的 `Manage.ps1`、`SelectionPanel.psm1` 和 `ManagementWorker.ps1` 构成本包自包含管理面板；由上级 `Manage.vbs` 无控制台启动。安装 / 卸载在隐藏后台执行，逐项状态与可复制实时日志留在面板中。日志区上沿的分隔条可上下拖动，调节结果在当前窗口保留；上下限为功能行、操作按钮和日志工具栏留出空间。日志正文右键可“复制”或“全选”，也支持 Ctrl+A / Ctrl+C；全选仅针对当前可见缓冲区，完整输出使用“复制全部日志”。总进度按已处理项 / 本次所选项显示计数和百分比；成功与失败计入已处理，等待中、执行中和未执行项不计入，100% 表示全部处理完毕，结果以成功 / 失败汇总为准。安装 / 更新和卸载分别计时；点击时只清零并启动当前操作计时，后台全部结束或启动失败时只冻结当前耗时。每秒刷新 `HH:mm:ss`（小时可超过 24），执行时显示“安装用时 / 卸载用时”，结束显示“安装总用时 / 卸载总用时”。两份耗时只在当前面板会话内独立保留。安装成功显示绿色“✅ 安装成功”。不改变右键业务工具自己的交互方式。失败状态可点击，在独立 PowerShell 中只读显示本次完整会话日志；包失败不阻止其它所选包，日志不可用时在面板提示。

**SDK 环境准备：** 已选择的 SDK／版本所需下载、安装及首次 Flutter／Dart 缓存补齐自动执行；网络失败或无进度超时后持续重试，间隔逐步增加并封顶 30 秒，没有次数和总时长上限，直到成功或本人 Ctrl+C／停止。仍在输出下载进度的传输不按总时长截断；成功后才进入后续业务。目标／版本选择、官方许可证与系统权限仍由本人处理；路径、权限、磁盘或明确不存在的版本会报告具体原因。每次尝试和真实进度追加到终端所示日志；同一 URL 有 ETag／Last-Modified 时安全续传，跨来源保留独立临时文件，不拼接不同来源。失败／取消保留下载现场；业务构建和配置写入不因网络重试而整体重放。

**Flutter SDK网络预检：** 下载／首次Dart自举／precache前，随包网络模块以真实小Range验证来源、TLS、字节和吞吐并择优；显式storage、Pub和代理（含空值）保留，AUTO仅核验官方／CFUG同对象及当前已配置代理，不猜端口、不改系统代理或Git。当前任务短期复用；真实获取失败会降权坏路线、轮换其它已验证候选并持续重试。FVM按实际api context来源处理，能力允许时Git与Dart制品分阶段；用户fork不改源。原生BITS按真实WinINET通道衡量，PAC未能有界解析时保留既有通道并明确未测速。详细边界见[随包选路模块](./SdkDownloadRoute.ps1/README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

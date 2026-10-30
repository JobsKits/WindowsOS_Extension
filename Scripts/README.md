# `Scripts`：组合安装入口与维护工具

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、文件用途速览](#script-purpose)
- [二、菜单安装、配置与卸载](#menu-entry)
- [三、通用模板检查与同步](#template-sync)
- [四、本地动态目录与远端折叠目录](#toc-maintenance)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录负责扩展包的组合选择、逐包编排、通用模板同步，以及 [**Markdown**](https://markdown.cn) 目录过滤器的兼容入口。首次使用先看[仓库总说明](../README.md)，安装菜单运行根目录的 `.cmd` 轻量入口，唤起同一 GUI 后立即结束启动脚本；各项右键功能的业务实现位于对应包的 `Scripts/Action.psm1`。

## 一、<span id="script-purpose">文件用途速览</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文件 | 负责什么 | 如何使用 |
| --- | --- | --- |
| [Manage.ps1](./Manage.ps1) | 读取清单和安装状态，打开组合面板，按默认 `Manage` 面板选择的安装 / 卸载操作编排各独立包。 | 优先通过根目录 `.vbs` 无控制台启动；需要 Windows 图形桌面和 `STA` 进程，`-Preview` 只在面板日志显示选择而不部署。 |
| [ManagementWorker.ps1](./ManagementWorker.ps1) | 执行面板形成的逐包计划，流式输出日志和逐叶状态事件；单包失败后继续其它所选包，最后汇总结果。 | 内部隐藏后台入口，不直接双击；只调用选中包自己的安装器。 |
| [Catalog.psm1](./Catalog.psm1) | 校验总清单与各包身份、文件完整性，生成操作计划，再调用各包自己的安装模块。 | 内部模块，由 `Manage.ps1` 导入；不直接执行右键业务。 |
| [Installer.psm1](./Installer.psm1) | 按用途分组显示复选框，按字体与 DPI 测量全部计数、功能标题、状态及底部说明；宽度不足时减少列数或换行，保持文字完整且控件不重叠。功能内容可滚动，操作按钮始终可见，日志上沿可拖动调高；日志右键可复制 / 全选，支持 Ctrl+A / Ctrl+C。 | 界面与隐藏进程桥接模块；安装 / 卸载空选时禁用操作按钮与回车，点击后逐叶显示等待、执行中、成功、失败或未执行，实际注册仍由包安装器承担。 |
| [Sync-PackageInfrastructure.ps1](./Sync-PackageInfrastructure.ps1) | 对照 `../Infrastructure/` 核对各包内嵌的六份通用模板，以及各管理目录的 `Manage.cmd` / `Manage.vbs` 启动模板。 | 默认只检查；显式传入 `-Write` 才覆盖对应模板副本。 |
| [MarkdownToc.mjs](./MarkdownToc.mjs) | 提供目录过滤器的同源码兼容入口。 | 正式过滤器统一从 `../.jobs-markdown-toc/` 运行，按[目录维护说明](#toc-maintenance)操作。 |

总清单位于 [Extensions.json](../Extensions.json)，登记 24 个现行安装包，面板展开为 42 项可选功能，其中 Flutter 含 19 项叶动作（依据 Extensions.json 与 FeatureActions.psm1，2026-10-28）；磁盘保留的八个旧 Flutter 包不再各占一项面板入口；[Flutter SDK 安装/切换包](../JobsFlutterVersionMgr/README.md) 同样只由面板编排，其工具链体检、fzf 选版与项目绑定在本包终端内进行。包内的 `Extension.json` 声明功能身份与菜单信息；`PackageInstaller.psm1` 承担本包部署、注册、备份和回滚；`Invoke.ps1` 是已安装菜单的运行入口。[Git 拉取包](../JobsGitPuller/README.md) 同样独立处理上游拉取、改动快照与冲突恢复。[Flutter 第三方依赖提取包](../JobsFlutterDependencyExtractor/README.md) 通过本包健康 Dart 读取锁文件与解析记录，输出父目录空行默认系统桌面，不安装工具或自动获取依赖。[Flutter打包 包](../JobsFlutterPackager/README.md) 也独立编译 Flutter 根目录专属菜单，在 CMD 用 fzf 选择 Android / iOS / HarmonyOS 及 APK / AAB / HAP / APP；OpenHarmony 核对已有 ohos 平台、适配 SDK 和 DevEco 工具链，不自动安装或创建平台，Windows 选择 iOS 时提前停止。统一包另外提供[打包鸿蒙（HAP + APP）](../JobsFlutterTools/README.md#鸿蒙-hap--app-打包)独立叶，只有鸿蒙工程显示，固定项目 FVM 与 release，一次生成并验证两种非空产物。组合面板保持打开，隐藏后台按清单逐包执行，底部实时追加标准输出 / 错误并支持复制；日志区上沿的分隔条可上下拖动，调节结果在当前窗口保留；上下限为功能行、操作按钮和日志工具栏留出空间。日志正文右键可“复制”或“全选”，也支持 Ctrl+A / Ctrl+C；全选仅针对当前可见缓冲区，完整输出使用“复制全部日志”。单包失败后继续其它所选包；已完成的包保持结果，失败包由自己的安装器回滚。

[Flutter 项目体检包](../JobsFlutterDoctor/README.md)与[Flutter 代码生成包](../JobsFlutterCodegen/README.md)同样独立构建根目录动态菜单；前者只运行版本与 doctor，后者经确认执行 pub get 和已配置的生成器。二者各自的 `Scripts/Check.ps1 -Target` 只读打印计划，不调用 SDK；FVM 已声明但项目 SDK 缺失时停止。

[Git 动态代理包](../JobsGitProxyConfigurator/README.md)采用独立 DesktopBackground 静态注册，仅系统桌面背景显示；其 PackageInstaller.psm1 是通用模板明确覆盖项。菜单安装与卸载不触发 Git 环境修改；用户点击后在本包终端确认安装、C 检查或 R 恢复，动态运行态与菜单发布目录分开保存。

[新建 Harmony 模拟器包](../JobsHarmonySimulatorCreator/README.md) 是独立的 Windows x64 桌面空白原生 handler，复用已安装的 [**DevEco Studio / Command Line Tools**](https://developer.huawei.com/consumer/cn/deveco-studio/)；终端选择本机已下载镜像并创建新实例，创建后可选择启动。缺工具或镜像时给出官方准备方式后停止，不自动下载、安装或接受许可；独立 `Run.cmd` 与菜单使用相同新建流程。

[Android 模拟器检测与修复包](../JobsAndroidSimulatorRepairer/README.md)同样采用独立桌面空白原生 handler；安装只注册菜单，点击后在可见终端诊断与修复已启动模拟器的安装空间。应用卸载和容量配置变更分别要求精确 `YES`；卸载会删除对应应用数据，不执行 Wipe Data；卸载菜单保留 AVD、备份与日志。

[单文件内容查看包](../JobsFileContentViewer/README.md) 从 `file-content-viewer` 映射到 `JobsFileContentViewer`，原生桥接严格单选普通文件，新可见 PowerShell 运行本包 `FileViewer.ps1`；默认超过 1 MiB 前询问精确 `YES`，环境变量 `JOBS_FILE_VIEWER_MAX_BYTES` 可调，正文只显示在终端。

## 二、<span id="menu-entry">菜单安装、配置与卸载</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

运行根目录 [【Windows】🧩管理资源管理器扩展.cmd](../【Windows】🧩管理资源管理器扩展.cmd)。同一窗口上方选择安装 / 更新或卸载，默认空选；操作切换清空勾选，卸载时未安装项置灰。分组和底部均可全选 / 全不选，空选、取消、关闭不执行。Flutter 展开 16 个叶动作，卸载按已安装白名单减去所选动作，最后一项移除时注销包；其它动作保留。

勾选后点击安装 / 更新或卸载即在同一面板后台执行，不再要求终端回车或 YES。每包独立备份和回滚，单包失败后继续其它所选包并汇总各项结果；全局运行条件或管理计划无效时停止。独立功能目录使用 `Manage.cmd` 唤起同一面板后立即结束启动脚本，也可直接使用 `Manage.vbs`，不依赖总调度；每包携带同字节 `SelectionPanel.psm1` 和 `ManagementWorker.ps1`。总进度按已处理项 / 本次所选项显示计数和百分比；成功与失败计入已处理，等待中、执行中和未执行项不计入，100% 表示全部处理完毕，结果以成功 / 失败汇总为准。安装 / 更新和卸载分别计时；点击时只清零并启动当前操作计时，后台全部结束或启动失败时只冻结当前耗时。每秒刷新 `HH:mm:ss`（小时可超过 24），执行时显示“安装用时 / 卸载用时”，结束显示“安装总用时 / 卸载总用时”。两份耗时只在当前面板会话内独立保留。安装成功显示绿色“✅ 安装成功”。

失败项显示红色“失败，见日志”，点击后新开 PowerShell 窗口，用 `Get-Content -LiteralPath` 只读显示本次完整会话日志；提示包含实际日志位置。其它状态不可点击，日志缺失、不可读或终端无法启动时在面板显示具体原因；不影响当前后台任务，也不执行日志正文。

清单枚举保留不可用包的诊断，不预先要求未选包源码完整；选中执行时再次核对包身份和安装器。

需要 Windows 10 / 11 图形桌面、系统 Windows PowerShell 5.1 Desktop、STA 与系统 .NET。在本目录可运行：

```powershell
powershell.exe `
  -NoLogo `
  -NoProfile `
  -STA `
  -ExecutionPolicy Bypass `
  -File .\Manage.ps1 `
  -Mode Manage `
  -Preview
```

去掉 `-Preview` 才进入执行确认；预览只在底部日志显示选择，不写状态或注册表。内部兼容 `Install / Configure / Uninstall` 模式，`Configure` 空选可形成全卸载计划，同样由面板操作按钮确认后执行。状态、日志、版本和注册表备份按包保存在当前用户本地应用数据的 `Jobs\WindowsExtension\extensions\<功能ID>` 中；卸载保留这些数据，详见[平台安装章节](../README.md#installation)。

## 三、<span id="template-sync">通用模板检查与同步</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

维护模板位于 `../Infrastructure/`。六份 PowerShell 同步范围为 `Common.psm1`、`Invoke.ps1`、`Manage.ps1`、`PackageInstaller.psm1`、`SelectionPanel.psm1`、`ManagementWorker.ps1`，目标为总清单登记的各包 `Scripts/` 副本；同时核对所有管理目录（包括旧 Flutter 包）根层的 `Manage.cmd` / `Manage.vbs` 启动模板，不会覆盖 `Action.psm1`、`Extension.json` 或功能业务配置。“用 Sourcetree 打开”已从 `Extensions.json` 移除；`JobsSourcetreeOpener/` 只保留旧安装卸载与兼容源码，其原生菜单不再插入叶子。原生 Flutter、Android / Harmony 模拟器、单文件权限 / 内容查看和 Sourcetree 打开包声明仅覆盖 `PackageInstaller.psm1`，同步器对这项明确白名单跳过；本包原生构建与 COM 安装事务独立维护。各包运行时使用自己内嵌的副本，不依赖模板目录。

在本目录只读检查，一致时输出成功信息，发现差异时返回失败：

```powershell
powershell.exe `
  -NoProfile `
  -ExecutionPolicy Bypass `
  -File .\Sync-PackageInfrastructure.ps1
```

确认模板是预期版本后，显式写入各包副本：

```powershell
powershell.exe `
  -NoProfile `
  -ExecutionPolicy Bypass `
  -File .\Sync-PackageInfrastructure.ps1 `
  -Write
```

`-Write` 会覆盖上述六类副本，执行前先保存包内需要保留的修改。同步完成后运行[仓库回归](../README.md#verification)，检查模板一致性及各包行为。

## 四、<span id="toc-maintenance">本地动态目录与远端折叠目录</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

使用 [**Typora**](https://typora.io/) 时，本地文档保留 `[toc]`；安装 [**Git clean / smudge 过滤器**](https://git-scm.com/docs/gitattributes#_filter)后，整文件暂存自动生成默认收起的目录，检出时恢复本地标签。处理范围由 [manifest.json](../.jobs-markdown-toc/manifest.json) 精确登记，路径均相对仓库根；新增或移动文档须先确认有效标签，增量更新清单和根 `.gitattributes` 精确路径，再运行 `install` 与 `verify`。直接推送旧提交不会刷新目录。

过滤器维护需要 [**Node.js**](https://nodejs.org) `20` 或更新版本及 Git，不依赖第三方 npm 包。这套依赖用于文档维护；Windows 组合安装面板本身不需要 Node.js。个别右键功能的 Node.js 依赖按其包说明单独检查。

下列命令从本 `Scripts/` 目录运行；新克隆先安装一次，换机或 Node.js 可执行文件位置变化后重新安装：

```shell
node ../.jobs-markdown-toc/MarkdownToc.mjs install
node ../.jobs-markdown-toc/MarkdownToc.mjs status
```

仓库首次接入时，先在 [**Sourcetree**](https://www.sourcetreeapp.com/) 审查差异，按[首次提交步骤](../.jobs-markdown-toc/README.md#first-adoption)整文件暂存清单内全部文档，同时纳入 `.gitattributes`、完整工具目录及实际改动的兼容脚本、测试或 CI 文件，再运行全清单 `check`。这些操作由用户正常暂存完成，工具不自动暂存。已接入仓库的新克隆安装后，日常只需整文件暂存改过的受控文档。

| 命令 | 读取与写入边界 |
| --- | --- |
| `install` | 预检清单文档与属性，只安装本仓 local 过滤器配置，并将本工具发布块恢复为本地标签。 |
| `verify` | 只读核对清单工作区文档的转换往返与幂等性。 |
| `check` | 校验清单文档的**原始暂存区内容**，检查目录是否对应已暂存正文。缺失、未暂存或过期时报告失败。 |
| `preview [相对文档路径]` | 将指定清单文档的发布版输出到标准输出；参数仍相对仓库根，不相对当前终端目录。 |
| `uninstall` | 配置未被外部改动时恢复安装前配置，工作区保留生成目录；之后目录不再自动更新。 |

日常保存文档后，在自己的 Git 客户端将**改过的受控文档整文件暂存**，再执行检查；新增文档时还需暂存对应清单与属性改动。部分行或区块暂存、网页直接改标题、未安装过滤器的环境，都可能使提交中的目录过期。

```shell
node ../.jobs-markdown-toc/MarkdownToc.mjs verify
node ../.jobs-markdown-toc/MarkdownToc.mjs check
node ../.jobs-markdown-toc/MarkdownToc.mjs preview Scripts/README.md
```

停用目录转换使用下列命令；它与根管理入口的菜单卸载是两个独立操作：

```shell
node ../.jobs-markdown-toc/MarkdownToc.mjs uninstall
```

过滤器的安装、验证、预览与卸载均不暂存文件、不创建提交、不推送，也不改全局 Git 配置或 hooks。恢复记录位于本仓实际 Git 元数据目录的 `jobs-markdown-toc.json`；终端报告配置与错误，`preview` 的标准输出只有发布版文档。发布块、标题锚点的生成和还原属于同一受控转换，不能手工删除其中一半。

隔离回归位于 [MarkdownToc.Tests.mjs](../Tests/MarkdownToc.Tests.mjs)。网页折叠语法见 [**GitHub 官方说明**](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/organizing-information-with-collapsed-sections)与 [**GitLab 官方说明**](https://docs.gitlab.com/user/markdown/#collapsible-section)；[**Gitee**](https://gitee.com)及自建服务须以各自实际渲染效果验收，不能用本地预览代替远端验证。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

[构建产物清理包](../JobsBuildArtifactCleaner/README.md)以 `clean-build-artifacts` 登记，沿用单功能安装器和文件夹菜单；运行时仅识别 Flutter / Android。总面板安装或卸载该包均不会执行清理。

[Harmony 模拟器检测与修复](../JobsHarmonySimulatorRepairer/README.md)、[运行授权](../JobsRunAuthorizer/README.md)与[解除运行授权](../JobsRunAuthorizationRevoker/README.md)同样按独立包编排；前者仅桌面空白，后两者仅普通单文件。安装和卸载不会重启实例或修改目标权限。

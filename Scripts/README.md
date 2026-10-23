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

本目录负责扩展包的组合选择、逐包编排、通用模板同步，以及 [**Markdown**](https://markdown.cn) 目录过滤器的兼容入口。首次使用先看[仓库总说明](../README.md)，安装菜单直接运行根目录的 `.cmd` 入口；各项右键功能的业务实现位于对应包的 `Scripts/Action.psm1`。

## 一、<span id="script-purpose">文件用途速览</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文件 | 负责什么 | 如何使用 |
| --- | --- | --- |
| [Manage.ps1](./Manage.ps1) | 读取清单和安装状态，打开组合面板，按 `Install / Configure / Uninstall` 编排各独立包。 | 优先通过根目录 `.cmd` 启动；需要 Windows 图形桌面和 `STA` 进程，`-Preview` 只返回选择而不部署。 |
| [Catalog.psm1](./Catalog.psm1) | 校验总清单与各包身份、文件完整性，生成操作计划，再调用各包自己的安装模块。 | 内部模块，由 `Manage.ps1` 导入；不直接执行右键业务。 |
| [Installer.psm1](./Installer.psm1) | 显示固定无滚动的复选框面板，按内容与工作区使用一至三列；提供全选、全不选、对应模式操作和取消。 | 内部界面模块；安装 / 卸载空选时禁用操作按钮与回车；不写注册表，不安装扩展包。 |
| [Sync-PackageInfrastructure.ps1](./Sync-PackageInfrastructure.ps1) | 对照 `../Infrastructure/` 核对各包内嵌的四份通用模板。 | 默认只检查；显式传入 `-Write` 才覆盖对应模板副本。 |
| [MarkdownToc.mjs](./MarkdownToc.mjs) | 提供目录过滤器的同源码兼容入口。 | 正式过滤器统一从 `../.jobs-markdown-toc/` 运行，按[目录维护说明](#toc-maintenance)操作。 |

总清单位于 [Extensions.json](../Extensions.json)，包含 16 项现行安装功能；磁盘保留的八个旧 Flutter 包不再各占一项面板入口；[Flutter SDK 安装/切换包](../JobsFlutterVersionMgr/README.md) 同样只由面板编排，其工具链体检、fzf 选版与项目绑定在本包终端内进行。包内的 `Extension.json` 声明功能身份与菜单信息；`PackageInstaller.psm1` 承担本包部署、注册、备份和回滚；`Invoke.ps1` 是已安装菜单的运行入口。[Git 拉取包](../JobsGitPuller/README.md) 同样独立处理上游拉取、改动快照与冲突恢复。[Flutter 第三方依赖提取包](../JobsFlutterDependencyExtractor/README.md) 通过本包健康 Dart 读取锁文件与解析记录，输出父目录空行默认系统桌面，不安装工具或自动获取依赖。[Flutter打包 包](../JobsFlutterPackager/README.md) 也独立编译 Flutter 根目录专属菜单，在 CMD 用 fzf 选择 Android / iOS / HarmonyOS 及 APK / AAB / HAP / APP；鸿蒙核对已有 ohos 平台、适配 SDK 和 DevEco 工具链，不自动安装或创建平台，Windows 选择 iOS 时提前停止。组合面板保存后按清单逐包执行，一包失败即停止，已完成的包保持结果，失败包由自己的安装器回滚。

[Flutter 项目体检包](../JobsFlutterDoctor/README.md)与[Flutter 代码生成包](../JobsFlutterCodegen/README.md)同样独立构建根目录动态菜单；前者只运行版本与 doctor，后者经确认执行 pub get 和已配置的生成器。二者各自的 `Scripts/Check.ps1 -Target` 只读打印计划，不调用 SDK；FVM 已声明但项目 SDK 缺失时停止。

[Git 动态代理包](../JobsGitProxyConfigurator/README.md)采用独立 DesktopBackground 静态注册，仅系统桌面背景显示；其 PackageInstaller.psm1 是通用模板明确覆盖项。菜单安装与卸载不触发 Git 环境修改；用户点击后在本包终端确认安装、C 检查或 R 恢复，动态运行态与菜单发布目录分开保存。

[新建 Harmony 模拟器包](../JobsHarmonySimulatorCreator/README.md) 是独立的 Windows x64 桌面空白原生 handler，复用已安装的 [**DevEco Studio / Command Line Tools**](https://developer.huawei.com/consumer/cn/deveco-studio/)；终端选择本机已下载镜像并创建新实例，创建后可选择启动。缺工具或镜像时给出官方准备方式后停止，不自动下载、安装或接受许可；独立 `Run.cmd` 与菜单使用相同新建流程。

[Android 模拟器检测与修复包](../JobsAndroidSimulatorRepairer/README.md)同样采用独立桌面空白原生 handler；安装只注册菜单，点击后在可见终端诊断与修复已启动模拟器的安装空间。应用卸载和容量配置变更分别要求精确 `YES`；卸载会删除对应应用数据，不执行 Wipe Data；卸载菜单保留 AVD、备份与日志。

## 二、<span id="menu-entry">菜单安装、配置与卸载</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 根目录入口 | 面板行为 |
| --- | --- |
| [【Windows】🧩安装资源管理器扩展.cmd](../【Windows】🧩安装资源管理器扩展.cmd) | 每次默认全选；点击“安装”只安装或更新已选包，保留未勾选的已安装包。 |
| [Install.cmd](../Install.cmd) | 英文兼容入口，直接调用相同的 `Install` 模式。 |
| [Configure.cmd](../Configure.cmd) | 恢复已启用项；点击“保存配置”安装 / 更新已选包、卸载取消勾选的已安装包，允许空选关闭全部。 |
| [【Windows】🧩卸载资源管理器扩展.cmd](../【Windows】🧩卸载资源管理器扩展.cmd) | 只列出已安装功能并默认全选；点击“卸载”只移除勾选项，保留未勾选项。 |
| [Uninstall.cmd](../Uninstall.cmd) | 英文兼容入口，直接调用相同的 `Uninstall` 模式。 |

五个入口都直接调用本目录的 `Manage.ps1`，并从自身位置定位源码。面板的功能名称一项一行，悬停查看完整说明；选项区固定无滚动，窗口按内容和屏幕工作区自动定尺寸，按包数与工作区选择一至三列。底栏统一提供“全选 / 全不选 / 安装、卸载或保存配置 / 取消”；安装和卸载空选时按钮置灰且回车不能绕过，配置允许空选关闭全部。取消或关闭面板不修改包。每个功能包也有自己的独立安装和卸载入口；只复制某一包时不需要这个总 `Scripts/` 目录。

运行环境是 Windows 10 / 11、系统 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) `5.1 Desktop`、系统 `.NET` 与图形桌面。`.cmd` 仅为当前进程设置执行策略参数，不提权、不联网安装工具；各功能自身的依赖和操作确认见对应包说明。[Flutter 运行包](../JobsFlutterRunner/README.md) 使用现有 MSVC / Windows SDK 编译原生动态菜单，在 CMD 选择设备与连接独立后台日志；缺编译器时停止，不自动安装。

需要命令行打开组合配置面板时，在本 `Scripts/` 目录运行：

```powershell
powershell.exe `
  -NoLogo `
  -NoProfile `
  -STA `
  -ExecutionPolicy Bypass `
  -File .\Manage.ps1 `
  -Mode Configure
```

只检查面板时追加 `-Preview`，五个根目录 `.cmd` 入口也都支持传入该参数；例如在本目录运行：

```powershell
powershell.exe `
  -NoLogo `
  -NoProfile `
  -STA `
  -ExecutionPolicy Bypass `
  -File .\Manage.ps1 `
  -Mode Install `
  -Preview
```

预览窗口标题标明“仅预览”，按钮显示“返回选择”；确认后返回面板选择，不部署、不写安装状态或注册表。可将模式改为 `Configure` 或 `Uninstall`；卸载预览始终列出全部登记包并默认全选，让没有安装历史的机器也能查看完整面板，真实卸载仍只列出当前已安装包。自动回归见 [SelectionPanel.Tests.ps1](../Tests/SelectionPanel.Tests.ps1)，真实 Windows 桌面的布局、悬停说明及键盘操作按[总说明的验收步骤](../README.md#verification)另行核验。

菜单安装状态、运行日志和注册表备份按包保存在**当前用户本地应用数据**的 `Jobs\WindowsExtension\extensions\<功能ID>` 下。卸载保留日志、备份和版本文件。注册范围、迁移与故障处理详见[总说明的安装章节](../README.md#installation)和[安装状态章节](../README.md#structure)。

## 三、<span id="template-sync">通用模板检查与同步</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

维护模板位于 `../Infrastructure/`。同步范围只有 `Common.psm1`、`Invoke.ps1`、`Manage.ps1`、`PackageInstaller.psm1`，目标为总清单登记的各包 `Scripts/` 副本；不会覆盖 `Action.psm1`、`Extension.json` 或功能业务配置。原生 Flutter 与 Android / Harmony 模拟器包声明仅覆盖 `PackageInstaller.psm1`，同步器对这项明确白名单跳过；本包原生构建与 COM 安装事务独立维护。各包运行时使用自己内嵌的副本，不依赖模板目录。

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

`-Write` 会覆盖上述四类副本，执行前先保存包内需要保留的修改。同步完成后运行[仓库回归](../README.md#verification)，检查模板一致性及各包行为。

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

停用目录转换使用下列命令；它与根 `Uninstall.cmd` 的菜单卸载是两个独立操作：

```shell
node ../.jobs-markdown-toc/MarkdownToc.mjs uninstall
```

过滤器的安装、验证、预览与卸载均不暂存文件、不创建提交、不推送，也不改全局 Git 配置或 hooks。恢复记录位于本仓实际 Git 元数据目录的 `jobs-markdown-toc.json`；终端报告配置与错误，`preview` 的标准输出只有发布版文档。发布块、标题锚点的生成和还原属于同一受控转换，不能手工删除其中一半。

隔离回归位于 [MarkdownToc.Tests.mjs](../Tests/MarkdownToc.Tests.mjs)。网页折叠语法见 [**GitHub 官方说明**](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/organizing-information-with-collapsed-sections)与 [**GitLab 官方说明**](https://docs.gitlab.com/user/markdown/#collapsible-section)；[**Gitee**](https://gitee.com)及自建服务须以各自实际渲染效果验收，不能用本地预览代替远端验证。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

[构建产物清理包](../JobsBuildArtifactCleaner/README.md)以 `clean-build-artifacts` 登记，沿用单功能安装器和文件夹菜单；运行时仅识别 Flutter / Android。总面板安装或卸载该包均不会执行清理。

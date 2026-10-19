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
| [Manage.ps1](./Manage.ps1) | 读取清单和安装状态，打开组合面板，按 `Install / Configure / Uninstall` 编排各独立包。 | 优先通过根目录 `.cmd` 启动；需要 Windows 图形桌面和 `STA` 进程。 |
| [Catalog.psm1](./Catalog.psm1) | 校验总清单与各包身份、文件完整性，生成操作计划，再调用各包自己的安装模块。 | 内部模块，由 `Manage.ps1` 导入；不直接执行右键业务。 |
| [Installer.psm1](./Installer.psm1) | 显示可缩放的复选框面板，提供全选、全不选、保存、取消。 | 内部界面模块；不写注册表，不安装扩展包。 |
| [Sync-PackageInfrastructure.ps1](./Sync-PackageInfrastructure.ps1) | 对照 `../Infrastructure/` 核对各包内嵌的四份通用模板。 | 默认只检查；显式传入 `-Write` 才覆盖对应模板副本。 |
| [MarkdownToc.mjs](./MarkdownToc.mjs) | 提供目录过滤器的同源码兼容入口。 | 正式过滤器统一从 `../.jobs-markdown-toc/` 运行，按[目录维护说明](#toc-maintenance)操作。 |

总清单位于 [Extensions.json](../Extensions.json)，包含十三项独立功能；[Flutter SDK 安装/切换包](../JobsFlutterVersionMgr/README.md) 同样只由面板编排，其工具链体检、fzf 选版与项目绑定在本包终端内进行。包内的 `Extension.json` 声明功能身份与菜单信息；`PackageInstaller.psm1` 承担本包部署、注册、备份和回滚；`Invoke.ps1` 是已安装菜单的运行入口。[Git 拉取包](../JobsGitPuller/README.md) 同样独立处理上游拉取、改动快照与冲突恢复。[Flutter 第三方依赖提取包](../JobsFlutterDependencyExtractor/README.md) 通过本包健康 Dart 读取锁文件与解析记录，输出父目录空行默认系统桌面，不安装工具或自动获取依赖。组合面板保存后按清单逐包执行，一包失败即停止，已完成的包保持结果，失败包由自己的安装器回滚。

## 二、<span id="menu-entry">菜单安装、配置与卸载</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 根目录入口 | 面板行为 |
| --- | --- |
| [Install.cmd](../Install.cmd) | 首次默认全选；有历史状态时恢复选择。保存后安装或更新已选包，卸载取消勾选且已安装的包。 |
| [Configure.cmd](../Configure.cmd) | 重新选择启用功能；与安装入口使用同一套组合面板和逐包操作逻辑。 |
| [Uninstall.cmd](../Uninstall.cmd) | 只列出已安装功能，卸载勾选项，保留未勾选项。 |

三个入口都调用本目录的 `Manage.ps1`，并从自身位置定位源码。取消面板不修改包。每个功能包也有自己的独立安装和卸载入口；只复制某一包时不需要这个总 `Scripts/` 目录。

运行环境是 Windows 10 / 11、系统 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) `5.1 Desktop`、系统 `.NET` 与图形桌面。`.cmd` 仅为当前进程设置执行策略参数，不提权、不联网安装工具；各功能自身的依赖和操作确认见对应包说明。

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

菜单安装状态、运行日志和注册表备份按包保存在**当前用户本地应用数据**的 `Jobs\WindowsExtension\extensions\<功能ID>` 下。卸载保留日志、备份和版本文件。注册范围、迁移与故障处理详见[总说明的安装章节](../README.md#installation)和[安装状态章节](../README.md#structure)。

## 三、<span id="template-sync">通用模板检查与同步</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

维护模板位于 `../Infrastructure/`。同步范围只有 `Common.psm1`、`Invoke.ps1`、`Manage.ps1`、`PackageInstaller.psm1`，目标为总清单登记的各包 `Scripts/` 副本；不会覆盖 `Action.psm1`、`Extension.json` 或功能业务配置。各包运行时使用自己内嵌的副本，不依赖模板目录。

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

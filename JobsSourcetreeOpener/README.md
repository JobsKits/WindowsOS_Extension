# Jobs 用 [**Sourcetree**](https://www.sourcetreeapp.com/) 打开

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、安装与卸载](#installation)
- [二、打开行为与验证](#behavior)

</details>
<!-- jobs-toc:end -->

---

**管理操作：** 本目录以 `Manage.cmd` 为轻量启动入口，只唤起 GUI 后结束本次脚本；先在面板选择安装 / 更新或卸载。在面板确认安装 / 更新或卸载后立即执行，无二次终端确认。关闭或取消面板不执行；卸载保留日志、备份、运行文件和工具。

## 🔥 <span id="前言">前言</span>

**最低支持系统：** 目标为 [**Windows**](https://www.microsoft.com/windows) 10 x64、Windows PowerShell 5.1 Desktop；最低 build 和真实 Explorer 验收仍待验证。Windows 11 使用“显示更多选项”或 `Shift+F10`。“用 Sourcetree 打开”已移除；总管理清单不再提供此项，保留本目录用于旧安装卸载和兼容回归。

当前原生 COM 实现始终返回零个菜单项，且拒绝旧菜单命令；不再根据 Sourcetree 的安装状态显示入口。旧版已安装 DLL 需通过本包管理入口卸载后，系统菜单才会消失。


**面板外观与语言：** 总面板和独立功能面板右上角均可选择“黑夜 / 白天 / 跟随系统”以及“简体中文 / 繁體中文 / བོད་ཡིག / English / 日本語 / Français / Español / Deutsch / Русский / 한국어 / 跟随系统”，默认均跟随系统，切换立即生效并保留当前勾选、任务和日志。窄窗或长文案放不下时，工具组移至标题下一行并保持右对齐；极窄窗口将主题、语言分两行，下拉控件右边缘对齐。选择保存在当前用户的 `%LOCALAPPDATA%\Jobs\WindowsExtension\panel-preferences.json`，下次打开自动恢复；保存失败在面板显示原因。跟随系统每秒检查应用主题和当前用户显示语言，繁体中文界面使用繁体、其它中文使用简体，其余已支持语种按系统语言匹配，未支持语言回退英文；Windows 显示语言通常须重新登录才生效。切换涵盖面板正文、功能说明、状态与动态计数、操作提示和辅助名称；藏文优先使用已安装 Microsoft Himalaya / Noto Sans Tibetan，日韩使用对应系统字体，缺失时回退。语言名称始终显示自称，图标、功能名和状态列独立，长文字换行；切换只影响管理面板，已安装右键菜单标题及后台工具的原始日志保持各自语言。共享完整译文以 `Scripts/ManagerPanelTranslations.json` 为编辑来源，发布时内嵌到同源面板模块，独立包无需访问兄弟目录或联网翻译。

**两种部署路线：** 源码管理面板默认使用“默认程序安装位置”，运行文件仍位于 `%LOCALAPPDATA%\Jobs\WindowsExtension\extensions\<功能ID>`。也可切换到“本地临时构建目录”，运行文件位于 `<功能包>\work\WindowsExtension\extensions\<功能ID>`；移走或清除该运行目录会使菜单失效。已部署副本的管理入口固定到自身真实路线，切换路线请从源码管理入口操作。菜单命令与 `deployment.json` 按当前路线定位配置，不依赖面板环境变量；提交失败恢复两侧状态。

**构建产物清理：** 安装位置选择、显示中的自动清理复选框与红色“🧹 清除构建产物”按钮排在同一行，垂直居中、间隔统一。英文或窄窗空间不足时，该行可水平滚动，文字保持完整，不拆成两行。仅默认安装位置路线显示默认关闭的“安装成功后清除此轮构建产物”和红底白字的“🧹 清除构建产物”独立按钮。自动清理仅处理本次成功安装产生的编译 GUID 子目录；独立按钮按当前选择清理本包 `work\JobsExtensionBuild` 专用编译工作区，不需要重新安装。临时路线隐藏清理控件。清理验证运行文件、标记与路径边界并持有事务锁，保留已经安装的 `.exe`、`.dll`、`.cmd`、`.ps1`、配置和注册表；自动清理失败明确显示“安装成功，清理失败”，独立清理失败正常报错。

**停止安装：** 安装进行中原按钮变为“停止安装”。点击只写停止请求，等待当前包事务完整结束，再把后续包标记为“未执行”；不强杀安装器、编译进程或资源管理器，未执行项不计失败或完成百分比。完成后可在同一面板继续清理、重试或关闭。

## 一、<span id="installation">安装与卸载</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 双击 [Manage.cmd](./Manage.cmd)，选择“卸载”并勾选本项，再点击卸载；不再提供重新安装。只管理当前用户本包的 COM 注册、运行版本、日志与状态，不运行 Git 写操作、不自动安装 Sourcetree。
- 原生动态菜单需要现有 [**Visual Studio Build Tools**](https://visualstudio.microsoft.com/visual-cpp-build-tools/) 的 C++ 桌面工作负载、MSVC、Windows SDK 及匹配 Explorer 的架构工具。缺少时注册前停止，不联网下载。
- 检测当前用户及系统 `App Paths\SourceTree.exe`，再检测 `LocalAppData`、`ProgramFiles` 和 `ProgramFiles(x86)` 下 `SourceTree/SourceTree.exe`、`Atlassian/SourceTree/SourceTree.exe`。自定义位置需由应用安装器登记 App Paths；路径必须实际存在且指向普通 `SourceTree.exe` 文件。
- 与 Git 回退包复用已创建的 Git 父菜单；单独安装本包也可展示完整分组，应用缺失时不创建空父菜单。其它包的安装选择保持独立。

## 二、<span id="behavior">打开行为与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

保留的历史业务模块只读取本地元数据，不在 Explorer 内启动 Git、PowerShell 或 CLR；当前原生门禁不会派发此业务。旧模块以数组语义引用参数启动 `SourceTree.exe log -f <仓库根目录>`；支持嵌套仓库、子模块 gitfile 与 worktree。参数来源参考 [Atlassian Windows CLI 记录](https://jira.atlassian.com/browse/SRCTREEWIN-14472)，Sourcetree 自身的登录、首次配置及版本行为由应用负责。

独立包可直接复制使用，运行时不依赖总仓或其它包。日志和安装快照归当前用户 `Jobs/WindowsExtension/extensions/open-sourcetree` 的 `logs/`、`backups/`；卸载保留这些文件及禁用状态。安装和卸载不修改业务仓库。

[PowerShell 隔离回归](../Tests/SourcetreeOpener.Tests.ps1)验证保留业务模块的安装检测、内层仓库、畸形边界与原始路径传递，同时检查退役 COM 不再插入菜单或启动进程，以及旧安装入口拒绝重新安装；[便携原生探针](../Tests/SourcetreeInstallationProbe.cpp)验证安装缺失、残留候选及程序名。隔离检查不启动真实应用；MSVC 构建、旧注册卸载及 Explorer 中入口消失仍需 Windows 验收。

管理安装 / 卸载时双击 `Manage.cmd`，它只通过 WScript 唤起 GUI，随后立即结束本次脚本；不在 CMD 中编译、安装或等待输入。也可直接双击 `Manage.vbs` 进入同一面板。每个选项显示等待、执行中、完成或失败，底部实时滚动标准输出和错误，可选中复制或点击“复制全部日志”；无可靠百分比时显示执行中，总体显示完成项数。运行期间等当前事务结束后关闭，完整管理日志位于系统临时目录 `JobsExtensionManager-<运行编号>.log`。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

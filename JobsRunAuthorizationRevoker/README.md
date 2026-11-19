# JobsRunAuthorizationRevoker · 移除执行权限

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、成对行为与边界](#jobs-toc-heading-2)
- [二、安装与独立运行](#jobs-toc-heading-3)
- [三、精确快照、冲突与目录](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

**管理操作：** 本目录以 `Manage.cmd` 为轻量启动入口，只唤起 GUI 后结束本次脚本；先在面板选择安装 / 更新或卸载。在面板确认安装 / 更新或卸载后立即执行，无二次终端确认。任务开始前关闭或取消面板不会启动操作；卸载保留日志、备份、运行文件和工具。

## 🔥 <span id="前言">前言</span>

> **最低支持系统：Windows 10 x64。** Windows 5.1 / MSVC / Explorer 与实际 NTFS ACL 行为仍须目标机验收；不声明已验证最低 build。

对任意一个普通文件显示“**➖ 移除执行权限**”，在独立终端核对路径并输入精确 `YES` 才修改。通过 [**Windows 文件 ACL**](https://learn.microsoft.com/en-us/dotnet/api/system.security.accesscontrol.filesystemrights) 管理当前用户 `ExecuteFile`（执行文件）权限；不执行所选文件。


**面板外观与语言：** 总面板和独立功能面板右上角均可选择“黑夜 / 白天 / 跟随系统”以及“简体中文 / 繁體中文 / བོད་ཡིག / English / 日本語 / Français / Español / Deutsch / Русский / 한국어 / 跟随系统”，默认均跟随系统，切换立即生效并保留当前勾选、任务和日志。窄窗或长文案放不下时，工具组移至标题下一行并保持右对齐；极窄窗口将主题、语言分两行，下拉控件右边缘对齐。选择保存在当前用户的 `%LOCALAPPDATA%\Jobs\WindowsExtension\panel-preferences.json`，下次打开自动恢复；保存失败在面板显示原因。跟随系统每秒检查应用主题和当前用户显示语言，繁体中文界面使用繁体、其它中文使用简体，其余已支持语种按系统语言匹配，未支持语言回退英文；Windows 显示语言通常须重新登录才生效。切换涵盖面板正文、功能说明、状态与动态计数、操作提示和辅助名称；藏文优先使用已安装 Microsoft Himalaya / Noto Sans Tibetan，日韩使用对应系统字体，缺失时回退。语言名称始终显示自称，图标、功能名和状态列独立，长文字换行；切换只影响管理面板，已安装右键菜单标题及后台工具的原始日志保持各自语言。共享完整译文以 `Scripts/ManagerPanelTranslations.json` 为编辑来源，发布时内嵌到同源面板模块，独立包无需访问兄弟目录或联网翻译。

**管理面板关闭：** 空闲关闭时选择退到系统托盘或完全退出，默认回车为托盘、Esc 保留原窗；安装／卸载／构建清理进行中关闭直接后台，不询问、不终止任务。完工仍驻留，从托盘双击或“显示管理面板”恢复同一窗口；忙碌时不能完全退出。

**整行选择：** 点击复选框、图标、功能文字、普通状态区或该功能行空白，仅切换该项一次，保留原 Tab／Space 复选框操作及勾选事件。任务执行中及不可用项禁止切换；失败日志链接和独立按钮优先执行自身动作，不连带勾选。组标题拖动、分组按钮和组尾空白不算功能行；移动、离开、滚动或触控滑动会取消本次点击候选，不接管原生滚动。选择本身不执行安装、卸载或清理，原默认空选、主题／语言切换保留勾选及持久化规则不变。

**两种部署路线：** 源码管理面板默认使用“默认程序安装位置”，运行文件仍位于 `%LOCALAPPDATA%\Jobs\WindowsExtension\extensions\<功能ID>`。也可切换到“本地临时构建目录”，运行文件位于 `<功能包>\work\WindowsExtension\extensions\<功能ID>`；移走或清除该运行目录会使菜单失效。已部署副本的管理入口固定到自身真实路线，切换路线请从源码管理入口操作。菜单命令与 `deployment.json` 按当前路线定位配置，不依赖面板环境变量；提交失败恢复两侧状态。

**构建产物清理：** 安装位置选择、显示中的自动清理复选框与红色“🧹 清除构建产物”按钮排在同一行，垂直居中、间隔统一。英文或窄窗空间不足时，该行可水平滚动，文字保持完整，不拆成两行。仅默认安装位置路线显示默认关闭的“安装成功后清除此轮构建产物”和红底白字的“🧹 清除构建产物”独立按钮。自动清理仅处理本次成功安装产生的编译 GUID 子目录；独立按钮按当前选择清理本包 `work\JobsExtensionBuild` 专用编译工作区，不需要重新安装。临时路线隐藏清理控件。清理验证运行文件、标记与路径边界并持有事务锁，保留已经安装的 `.exe`、`.dll`、`.cmd`、`.ps1`、配置和注册表；自动清理失败明确显示“安装成功，清理失败”，独立清理失败正常报错。

**停止安装：** 安装进行中原按钮变为“停止安装”。点击只写停止请求，等待当前包事务完整结束，再把后续包标记为“未执行”；不强杀安装器、编译进程或资源管理器，未执行项不计失败或完成百分比。完成后可在同一面板继续清理、重试或关闭。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、成对行为与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 动作 | 精确行为 |
| --- | --- |
| 运行授权 | 从本功能保存的原始 DACL 重新构造，只撤回本工具造成的拒绝 / 允许项，再增加当前用户 `ExecuteFile` 允许 ACE；已有组或其它拒绝导致有效授权失败时回滚。 |
| 解除运行授权 | 保留原 DACL，增加当前用户 `ExecuteFile` 显式拒绝 ACE，使继承来的允许不能抵消本次撤权。 |
| 重复同向操作 | 核对记录、身份与有效权限，匹配时不重复写入。 |
| 外部 DACL 或文件身份变化 | 停止并保留现场，不用旧快照覆盖新规则。 |

只支持本机 NTFS 的任意普通单文件；目录、多选、背景、符号链接、联接、硬链接、UNC、设备路径及备用数据流均排除。不再按扩展名过滤，README.md、txt、图片、压缩包和无扩展名文件同样适用；业务再次核验卷、父路径和硬链接数。其它用户、其它权限、继承设置、所有者、来源标记、PowerShell 执行策略和全局安全设置不变。保留读取权限的解释器仍可读取脚本并执行内容；`ExecuteFile` 撤权不是全面防执行隔离。文件扩展名和系统关联也不会因授权改变。

授予 / 移除执行权限只改变当前用户 Windows `ExecuteFile` ACL；Windows 没有 POSIX `chmod +x / -x` 执行位，普通数据文件获授执行权限也不会转为可运行程序；文件格式与解释器仍需满足系统要求。两个包均安装后，适用文件始终显示“➕ 授予执行权限”和“➖ 移除执行权限”：已有当前用户有效 ExecuteFile 时前者置灰、后者可点；没有时相反；权限无法可靠读取时两项都置灰。打开菜单和点击时重新检查状态，已达目标状态不重复写入。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、安装与独立运行 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

双击 [Manage.cmd](./Manage.cmd)，在同一面板选择安装 / 更新或卸载；在[总面板](../README.md)可分别勾选两个包。每个包可单独复制安装，不依赖另一个包的运行代码。安装用现有 MSVC / Windows SDK 编译单文件原生菜单并按当前用户注册。

独立入口传入一个文件，终端会显示范围、快照位置并要求 `YES`；取消或 EOF 不改权限。

```powershell
.\Run.cmd -Target "C:\研发目录\example.exe"
```

卸载只关闭菜单，保留已修改的文件权限和恢复记录；需要重新授权时先运行对应授权菜单，不能把卸载等同权限恢复。不提权、不能取得读 / 修改 DACL 权限时明确失败。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、精确快照、冲突与目录 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

两包使用当前用户 `LOCALAPPDATA/Jobs/WindowsExtension/run-permissions` 下同一份每文件记录，按卷号、文件 ID、当前 SID 标识，另存每次操作的内容摘要、原始 DACL、修改前 DACL 和预期 DACL。正常编辑同一文件内容后仍可往返切换，不用首次内容摘要锁死后续操作。持有禁止写入 / 删除共享的文件句柄完成身份、内容和 DACL 操作，拒绝硬链接与路径重解析；修改失败仅在当前 DACL 仍等于本次预期时回滚，出现并发变更则保留记录并报错。中断后的 Prepared 记录可对照修改前 / 预期状态恢复流程，不会无条件覆盖。

| 路径 | 职责 |
| --- | --- |
| [Scripts](./Scripts/README.md) | 原生菜单、权限核心、独立业务与安装事务。 |
| `Extension.json` | 包身份与控制台入口。 |
| `Manage.cmd` / `Run.cmd` | 安装、卸载、独立执行。 |

测试见 [RunPermissions.Tests.ps1](../Tests/RunPermissions.Tests.ps1/RunPermissions.Tests.ps1)：本机编译 / 隔离流程与 Windows 临时 NTFS 文件实际 ACL 往返分别记录；不修改用户真实文件。

管理安装 / 卸载时双击 `Manage.cmd`，它只通过 WScript 唤起 GUI，随后立即结束本次脚本；不在 CMD 中编译、安装或等待输入。也可直接双击 `Manage.vbs/Manage.vbs` 进入同一面板。每个选项显示等待、执行中、完成或失败，底部实时滚动标准输出和错误，可选中复制或点击“复制全部日志”；无可靠百分比时显示执行中，总体显示完成项数。运行期间等当前事务结束后关闭，完整管理日志位于系统临时目录 `JobsExtensionManager-<运行编号>.log`。


<!-- JOBS_SOURCE_SCRIPT_PACKAGES -->
**同名脚本包：** [Manage.vbs](./Manage.vbs/README.md)。源码路径与发布目录的 flat 资源名分开维护。
<!-- /JOBS_SOURCE_SCRIPT_PACKAGES -->

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

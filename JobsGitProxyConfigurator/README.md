# `JobsGitProxyConfigurator` 配置 Git 动态代理

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、安装、使用与卸载](#installation)
  - [安装 / 更新：Manage.cmd](#install-menu)
  - [【Windows】配置Git动态代理.cmd](#configure-git)
  - [卸载：Manage.cmd](#uninstall-menu)
- [二、动态选路与支持范围](#routing)
- [三、状态、日志与恢复保护](#state)
- [四、目录与验证](#structure)

</details>
<!-- jobs-toc:end -->

---

**管理操作：** 本目录以 `Manage.cmd` 为轻量启动入口，只唤起 GUI 后结束本次脚本；先在面板选择安装 / 更新或卸载。在面板确认安装 / 更新或卸载后立即执行，无二次终端确认。任务开始前关闭或取消面板不会启动操作；卸载保留日志、备份、运行文件和工具。

## 🔥 <span id="前言">前言</span>

**最低支持系统：Windows 10 64 位（x64）。** 这是当前最低支持目标；具体最低 build 尚未锁定，完整实机兼容性仍待验证。最低基线不等于所有功能已经实测通过。

**系统桌面空白处右键 → 配置 Git 动态代理 → 回车安装、C 检查、R 恢复。** 本包由 Jobs 维护，与 [macOS 对应模块](../../MacOS@Extension/JobsGitProxyConfigurator/README.md)提供同名入口，可单独复制整个目录使用。核对日期：**2026-10-22**。

| 操作 | 实际结果 |
| --- | --- |
| 安装菜单 | 只部署本包并登记当前用户的桌面背景菜单，不安装 Git 动态运行态。 |
| 点击桌面菜单 | 在可见终端进入配置流程，回车才写入用户级配置。 |
| C 检查 | 只读核对受控文件、用户 PATH、原始 Git 与当前进程解析路径。 |
| R 恢复 | 再次确认后精确恢复最新安装前的用户 PATH 与运行文件。 |
| 卸载菜单 | 仅移除本包菜单，保留另行安装的动态 Git、日志和恢复快照。 |

运行环境是 [**Windows**](https://www.microsoft.com/windows) 10 / 11、系统 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) 5.1 Desktop 与系统 .NET；配置时还需要已经安装且健康的 [**Git for Windows**](https://gitforwindows.org/)。不提权、不下载工具、不修改系统代理、VPN、`.gitconfig` 或项目远端。Windows 11 入口位于经典菜单的“显示更多选项”。

**系统兼容性：** 当前目标为 [**Windows**](https://www.microsoft.com/windows) 10 / 11 图形桌面，要求系统 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) 5.1 Desktop、.NET 与 STA；各系统版本和架构仍待实机验收，未锁定统一最低 build。XP / Vista / Windows 8 不支持当前入口；Windows 7 SP1 / 8.1 安装 [**WMF 5.1**](https://www.microsoft.com/en-us/download/details.aspx?id=54616)（要求 .NET Framework 4.5+）后，也仅可探索基础静态菜单，不构成对本包完整功能的支持承诺。Windows 11 使用“显示更多选项”或 `Shift+F10`；x86 / ARM64 均未获全功能实机兼容保证。

**本包依赖与测试范围：** 本包静态菜单安装无需 MSVC；另行确认配置 Git 时，系统 .NET / C# 编译能力用于生成 `git.exe` 入口。Git for Windows、curl、终端及 GUI 的版本和架构必须各自可运行；虚拟机中应分别验证菜单、编译后的入口和真实网络选路，不能只以注册成功认定完整兼容。


**面板外观与语言：** 总面板和独立功能面板右上角均可选择“黑夜 / 白天 / 跟随系统”以及“简体中文 / 繁體中文 / བོད་ཡིག / English / 日本語 / Français / Español / Deutsch / Русский / 한국어 / 跟随系统”，默认均跟随系统，切换立即生效并保留当前勾选、任务和日志。窄窗或长文案放不下时，工具组移至标题下一行并保持右对齐；极窄窗口将主题、语言分两行，下拉控件右边缘对齐。选择保存在当前用户的 `%LOCALAPPDATA%\Jobs\WindowsExtension\panel-preferences.json`，下次打开自动恢复；保存失败在面板显示原因。跟随系统每秒检查应用主题和当前用户显示语言，繁体中文界面使用繁体、其它中文使用简体，其余已支持语种按系统语言匹配，未支持语言回退英文；Windows 显示语言通常须重新登录才生效。切换涵盖面板正文、功能说明、状态与动态计数、操作提示和辅助名称；藏文优先使用已安装 Microsoft Himalaya / Noto Sans Tibetan，日韩使用对应系统字体，缺失时回退。语言名称始终显示自称，图标、功能名和状态列独立，长文字换行；切换只影响管理面板，已安装右键菜单标题及后台工具的原始日志保持各自语言。共享完整译文以 `Scripts/ManagerPanelTranslations.json` 为编辑来源，发布时内嵌到同源面板模块，独立包无需访问兄弟目录或联网翻译。

**管理面板关闭：** 空闲关闭时选择退到系统托盘或完全退出，默认回车为托盘、Esc 保留原窗；安装／卸载／构建清理进行中关闭直接后台，不询问、不终止任务。完工仍驻留，从托盘双击或“显示管理面板”恢复同一窗口；忙碌时不能完全退出。

**整行选择：** 点击复选框、图标、功能文字、普通状态区或该功能行空白，仅切换该项一次，保留原 Tab／Space 复选框操作及勾选事件。任务执行中及不可用项禁止切换；失败日志链接和独立按钮优先执行自身动作，不连带勾选。组标题拖动、分组按钮和组尾空白不算功能行；移动、离开、滚动或触控滑动会取消本次点击候选，不接管原生滚动。选择本身不执行安装、卸载或清理，原默认空选、主题／语言切换保留勾选及持久化规则不变。

**两种部署路线：** 源码管理面板默认使用“默认程序安装位置”，运行文件仍位于 `%LOCALAPPDATA%\Jobs\WindowsExtension\extensions\<功能ID>`。也可切换到“本地临时构建目录”，运行文件位于 `<功能包>\work\WindowsExtension\extensions\<功能ID>`；移走或清除该运行目录会使菜单失效。已部署副本的管理入口固定到自身真实路线，切换路线请从源码管理入口操作。菜单命令与 `deployment.json` 按当前路线定位配置，不依赖面板环境变量；提交失败恢复两侧状态。

**构建产物清理：** 安装位置选择、显示中的自动清理复选框与红色“🧹 清除构建产物”按钮排在同一行，垂直居中、间隔统一。英文或窄窗空间不足时，该行可水平滚动，文字保持完整，不拆成两行。仅默认安装位置路线显示默认关闭的“安装成功后清除此轮构建产物”和红底白字的“🧹 清除构建产物”独立按钮。自动清理仅处理本次成功安装产生的编译 GUID 子目录；独立按钮按当前选择清理本包 `work\JobsExtensionBuild` 专用编译工作区，不需要重新安装。临时路线隐藏清理控件。清理验证运行文件、标记与路径边界并持有事务锁，保留已经安装的 `.exe`、`.dll`、`.cmd`、`.ps1`、配置和注册表；自动清理失败明确显示“安装成功，清理失败”，独立清理失败正常报错。

**停止安装：** 安装进行中原按钮变为“停止安装”。点击只写停止请求，等待当前包事务完整结束，再把后续包标记为“未执行”；不强杀安装器、编译进程或资源管理器，未执行项不计失败或完成百分比。完成后可在同一面板继续清理、重试或关闭。

## 一、<span id="installation">安装、使用与卸载</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

### <span id="install-menu">安装 / 更新：[Manage.cmd](./Manage.cmd)</span>

> **目的：** 独立部署“配置 Git 动态代理”桌面右键菜单。

- 从本地包定位安装模块，展示来源、当前用户目标与注册范围，确认后部署本包。
- 仅登记 `HKCU\Software\Classes\DesktopBackground\shell\Jobs.WindowsExtension.git-proxy-configure`，不加入文件、目录或普通目录背景菜单。
- 重新右键系统桌面空白处即可使用；总安装面板也可单独选择本功能。
  - 不强制重启资源管理器。菜单保存安装时的系统桌面位置；系统桌面迁移后重新安装菜单更新路径。

### <span id="configure-git">[【Windows】配置Git动态代理.cmd](./【Windows】配置Git动态代理.cmd/【Windows】配置Git动态代理.cmd)</span>

> **目的：** 直接进入与桌面菜单相同的安装、检查或恢复流程。

- 阅读修改范围后，直接回车安装、C 只读检查、R 进入恢复确认，其它输入取消。
- 安装会编译真实的 `git.exe` 入口、保存原始 Git 路径、备份用户 PATH 的原值与类型，再增加专用目录。
  - 同版本且受控状态完整时不重复创建快照；已知安装可升级，未知文件或后续修改冲突时停止。
- 安装显示动态入口路径，C 显示当前检查进程实际解析的 Git。写入用户 PATH 不会更新已有会话；普通新终端仍可能继承父进程的旧环境，重新登录或从已更新环境的父进程启动后再核对。
  - **机器 PATH 中的 Git 可能仍排在用户 PATH 前。** 此时使用运行目录中的 `OpenGitCmd.cmd` 或 `OpenGitPowerShell.cmd`，它们只为新开的终端前置动态入口。
  - [**Sourcetree**](https://www.sourcetreeapp.com/) 等应用需保存工作后将 Git 路径选择为下述真实 `git.exe`；本包不猜测或改写应用私有偏好。终端默认继承父进程环境的行为见[微软说明](https://learn.microsoft.com/windows/win32/procthread/environment-variables)。
- R 只恢复最新操作前的精确状态；升级后回到上一版，重复 R 不继续卸载更早版本。若曾手动让 Sourcetree 等应用选择 shim，还需手动恢复其原 Git 路径。

```text
%LOCALAPPDATA%\JobsGitNetworkStrategy\runtime\bin\git.exe
%LOCALAPPDATA%\JobsGitNetworkStrategy\runtime\bin\OpenGitCmd.cmd
%LOCALAPPDATA%\JobsGitNetworkStrategy\runtime\bin\OpenGitPowerShell.cmd
```

### <span id="uninstall-menu">卸载：[Manage.cmd](./Manage.cmd)</span>

> **目的：** 只卸载本包菜单，保留业务运行态和可追溯数据。

- 展示本功能影响范围，确认后调用本包独立卸载模块。
- 移除本功能注册并保留菜单部署文件、日志、备份及已安装的动态 Git。
  - 需要恢复 Git 配置时，先进入配置流程选 R，或在菜单卸载后双击本包的配置入口。

菜单安装与卸载统一使用 [Manage.cmd](./Manage.cmd)；[ConfigureGit.cmd](./ConfigureGit.cmd/ConfigureGit.cmd) 是 Git 网络策略业务入口。显式自动化可运行 `ConfigureGit.cmd -Mode Install` 或 `-Mode Check`；`-Mode Restore` 仍要求交互确认。执行策略参数只作用于本次进程，不持久修改策略。

## 二、<span id="routing">动态选路与支持范围</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

原生 `git.exe` 保留调用参数，普通本地命令直接转交原始 Git。HTTP(S) `clone`、`fetch`、`pull`、`ls-remote`、`push` 在已知单目标场景先选择路由，原始 Git 业务最多执行一次；失败后不会盲目重复推送、拉取或克隆。

- 进入自动系统选路时读取当前用户启用的 WinINET 静态 HTTP / HTTPS / SOCKS 代理，不绑定软件品牌、主机或端口。
- 默认 `JOBS_GIT_ROUTE_PRIORITY=system`：短探测系统代理候选，不可用再探测直连；VPN 关闭后也重新判断。可显式设 `direct` 调整顺序。
- 保留已有显式代理、显式空代理、环境代理、`NO_PROXY` 与系统旁路规则；代理只传给当次 Git 子进程。
- 探测只访问去掉凭据、路径和查询的站点根，不关闭证书校验；探测工具与 Git 证书能力不同时交回原生 Git 检查。
- SSH、本地地址、未知参数、多远端与可能递归访问多个站点的操作保守交给原始 Git。PAC / WPAD、仅应用内部暴露的代理不自动执行或猜测；TUN 跟随操作系统路由。
- 未发现可用 curl 时直接交回原始 Git，不临时下载依赖，也不将未预检说成网络已通过。

没有任何脚本能保证所有 VPN、企业认证、远端故障和中途断网均成功。预检成功不代表实际 Git 传输一定成功；最终错误与退出码仍由原始 Git 返回。静态桌面菜单注册方式采用微软定义的 [DesktopBackground 对象](https://learn.microsoft.com/windows/win32/shell/reg-shell-exts)。

## 三、<span id="state">状态、日志与恢复保护</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 位置 | 用途 |
| --- | --- |
| `%LOCALAPPDATA%\Jobs\WindowsExtension\extensions\git-proxy-configure` | 桌面菜单的发布文件、配置、安装日志与注册表备份。 |
| `%LOCALAPPDATA%\JobsGitNetworkStrategy\runtime\bin` | 独立于菜单版本的动态 Git、原始 Git 路径与终端入口。 |
| `%LOCALAPPDATA%\JobsGitNetworkStrategy\snapshots`、`active.clixml` | 用户 PATH 的缺失 / 空值 / 类型及运行文件字节快照。 |
| `%LOCALAPPDATA%\JobsGitNetworkStrategy\install.log`、`logs\route.log` | 安装 / 恢复结果及脱敏的站点、选路状态和退出码。 |

配置目录使用当前用户私有 ACL。审计不保存原始 PATH、仓库路径、完整 URL 或凭据；快照本身包含恢复需要的本地配置，应保留在私有目录。恢复前同时校验受控文件和 PATH，发现用户后续修改即停止，不整份覆盖用户环境。检查只验证本机安装状态，不代表联网成功。

## 四、<span id="structure">目录与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```text
./
├── Extension.json
├── Manage.cmd                  安装 / 更新与卸载管理
├── 【Windows】配置Git动态代理.cmd
├── Scripts/       # 自包含菜单、安装器、原生 Git 桥接与选路策略
└── README.md
```

模块与依赖说明见 [Scripts/README.md](./Scripts/README.md)。仓库测试位于 [Tests/GitProxyConfigurator.Tests.ps1](../Tests/GitProxyConfigurator.Tests.ps1/GitProxyConfigurator.Tests.ps1)，在仓库根目录运行：

```powershell
pwsh -NoProfile -File .\Tests\GitProxyConfigurator.Tests.ps1
```

跨端 PowerShell 的隔离测试和 C# 编译检查只证明测试覆盖范围。真实 Windows PowerShell 5.1 编译 EXE、Explorer 菜单、终端 / GUI 的输入输出及 Ctrl+C、Sourcetree 路径选择和真实远端访问仍须 Windows 实机验收；本机 macOS 的通过结果不替代这些检查。

管理安装 / 卸载时双击 `Manage.cmd`，它只通过 WScript 唤起 GUI，随后立即结束本次脚本；不在 CMD 中编译、安装或等待输入。也可直接双击 `Manage.vbs/Manage.vbs` 进入同一面板。每个选项显示等待、执行中、完成或失败，底部实时滚动标准输出和错误，可选中复制或点击“复制全部日志”；无可靠百分比时显示执行中，总体显示完成项数。运行期间等当前事务结束后关闭，完整管理日志位于系统临时目录 `JobsExtensionManager-<运行编号>.log`。



<!-- JOBS_TERMINAL_STYLE_V1:BEGIN -->

> Windows 终端配色保护：支持完整颜色查询的交互控制台会先保存当前会话默认前景、背景与16色色表，再临时使用黑底白字和统一强调色；正常结束、业务失败及可捕获中断后恢复。用户运行中自行改动的颜色保留并提示，不修改用户主题、共享 Profile、注册表或全局策略。快照不包含进入前任意叠加的临时文字样式。非控制台、重定向、`NO_COLOR`、Sourcetree 及无法可靠保存／恢复颜色的环境保持原状态或降级为纯文本。

> `.cmd`／`.bat` 入口内嵌完整会话守护：黑底白字及强调色保护就绪或明确降级后才开始业务，全部退出路径同步等待恢复回执；同时核对父进程身份。原 PowerShell／Python 启动命令和业务参数不经过再次解析，保护初始化后恢复进入时的延迟扩展模式，原业务自己的 `setlocal` 保留；嵌套 PowerShell 复用同一会话保护。守护脚本只写入本轮系统临时目录，成功恢复后清理控制文件。

> 强制结束进程或终端崩溃无法保证自动恢复。恢复失败时保留并提示本轮 `%TEMP%\JobsTerminalStyle-<PID>-*.ps1` 恢复脚本，需在原控制台核对后运行；不要通过重置用户配置恢复。`-ExecutionPolicy Bypass` 如被入口使用，仅作用于本次子进程，不持久修改策略。

> 验证范围：已完成 PowerShell 语法、参数／退出与隔离生命周期核验；Windows 原生控制台的显示、按键与 `Ctrl+C` 实机验证尚未完成。

<!-- JOBS_TERMINAL_STYLE_V1:END -->


<!-- JOBS_SOURCE_SCRIPT_PACKAGES -->
**同名脚本包：** [ConfigureGit.cmd](./ConfigureGit.cmd/README.md)、[Manage.vbs](./Manage.vbs/README.md)、[【Windows】配置Git动态代理.cmd](./%E3%80%90Windows%E3%80%91%E9%85%8D%E7%BD%AEGit%E5%8A%A8%E6%80%81%E4%BB%A3%E7%90%86.cmd/README.md)。源码路径与发布目录的 flat 资源名分开维护。
<!-- /JOBS_SOURCE_SCRIPT_PACKAGES -->

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

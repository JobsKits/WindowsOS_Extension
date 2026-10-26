# Jobs [**Windows**](https://www.microsoft.com/windows) Git 提交回退

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、安装与卸载](#installation)
- [二、选择、取消与边界](#behavior)
- [三、验证](#verification)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

> **最低支持系统：** 目标为 Windows 10 x64、Windows PowerShell 5.1 Desktop；最低 build 与完整 Windows 实机兼容性尚未验收。Windows 11 位于“显示更多选项”（或 `Shift+F10`）。菜单名称为 **Git操作 → Git 提交回退**。

仅普通本地 [**Git**](https://git-scm.com/) 工作树文件夹及其内部文件夹显示；支持子模块、嵌套 Git 和 worktree。点击后打开独立 PowerShell 窗口，先展示用途和回车确认，再用 [**fzf**](https://github.com/junegunn/fzf) 选择模式及目标。远端快照仅读取本机已有跟踪引用，不 fetch、不推送。

| 模式 | 目标与结果 |
| --- | --- |
| soft 回退到 upstream | 多远端时明确选当前分支的本地跟踪快照；仅接受 HEAD 祖先，移动分支并保留工作区和既有索引。 |
| 选择提交 soft 回退 | 最近最多 200 条全部分支历史中选提交，目标必须是当前 HEAD 祖先；撤回已同步提交也只影响本地。 |
| hard 回退到 upstream | 本地快照固定到完整提交号，精确输入 `YES` 后回退。 |
| 选择提交 hard 回退 | 从最近最多 200 条全部分支历史选择，允许回到非祖先提交；精确 `YES`。 |
| 选择 tag hard 回退 | 选择 tag 后解析为提交号；精确 `YES`。 |
| 选择 reflog hard 回退 | 选择最近最多 200 条 reflog；完整提交号固定目标，精确 `YES`。 |

hard 会丢弃已跟踪的未提交修改；阻挡目标检出的未跟踪路径也可能被 Git 删除。不会执行 `git clean`，也不会递归重置子模块工作树。子仓回退后父仓可能显示 gitlink 差异，父仓索引不会被本功能暂存或提交。请先自行保护重要文件；本功能没有自动备份。

## 一、<span id="installation">安装与卸载</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 单独复制本目录，双击 [`Install.cmd`](./Install.cmd)；或在[总安装面板](../README.md#installation)勾选“Git 提交回退”。只注册当前用户的本包 COM handler 和 CLSID，不提权、不改系统菜单样式。32 位宿主通过 `Sysnative` 选择系统原生 PowerShell；直接从 32 位 PowerShell 调用安装器时，在写入前拒绝，避免 COM 注册视图与 Explorer 架构不符。
- 菜单使用原生 C++ handler。安装需要已有 [**Visual Studio Build Tools**](https://visualstudio.microsoft.com/visual-cpp-build-tools/) 的 C++ 桌面工作负载、MSVC、Windows SDK 及与 Explorer 对应的 x64 / ARM64 / x86 工具；缺少时在注册前停止，不自动下载编译器。
- 执行回退需要可用 Git 和 fzf。缺失或损坏时停止，不自动安装、不退回手输编号；普通确认和精确 `YES` 保留文本输入。
- 双击 [`Uninstall.cmd`](./Uninstall.cmd) 只移除本包菜单并禁用状态，保留运行版本、日志和安装快照。安装 / 卸载不会运行 Git 回退。

## 二、<span id="behavior">选择、取消与边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

模式层回车选择、`Esc` 取消；目标层回车选择、`←` 返回模式层、`Esc` 取消整个流程。无匹配、空选或输入结束均不回退；选择器失败返回失败。hard 的回车、非 `YES` 输入和输入结束都取消。`Ctrl+C` 可结束当前窗口流程。

- 文件、多选、链接、目录联接、网络目录、普通非 Git 文件夹、裸仓与 Git 元数据内部隐藏。最近内层 `.git` 畸形时直接拒绝，不会越过它回退父仓。菜单只读本地元数据，执行时再用真实 Git 复核。
- 无提交仓库、未解决冲突、merge / rebase / cherry-pick / revert / bisect 等未完成操作及索引锁会停止。游离 HEAD 只允许明确历史提交 / tag / reflog 模式，远端模式停止。选择期间仓库身份、分支或 HEAD 变化会停止；hard 确认期间索引、工作区差异或文件状态变化也会停止。
- 多远端逐项显示本地跟踪引用和提交号；选择期间引用变化会停止。soft 目标不在 HEAD 祖先链时停止，不自动选择其它线路。选择相同 HEAD 只报告实际索引状态，不虚报待提交文件。
- 运行文件全部随包部署，不依赖原 SourceTree 目录。只读 Git 检查设短超时；真正 reset 等待其原始退出结果，避免大工作树写入被固定超时强杀。每个 Git 子进程清除仓库定位覆盖变量，父进程环境保持原值。
- 日志位于 `%LOCALAPPDATA%\Jobs\WindowsExtension\extensions\git-rollback\logs`；安装快照和禁用状态同属该包，不影响其它扩展。

## 三、<span id="verification">验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

[隔离 Git 回归](../Tests/GitRollback.Tests.ps1)创建临时仓库验证仓库边界、soft / hard、确认取消与现场变化；[便携菜单判定探针](../Tests/GitRollbackMetadataProbe.cpp)直接调用原生 handler 共用的元数据判定头。测试不安装系统菜单，不操作真实工作仓库。编码回归可先编译 `Tests/GitRollbackFzfProbe.cpp`，再给 Git 回归传入 `-FzfProbeExecutable <可执行路径>`，验证初始 ASCII 管道下中文模式 UTF8 往返及编码恢复；实际 fzf 的目标选择与无匹配左键返回已在 macOS PowerShell 7 的真实 TTY 验证。原生 DLL 的 MSVC 构建、Windows 5.1 窗口与 Explorer 实际显示仍需 Windows 验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

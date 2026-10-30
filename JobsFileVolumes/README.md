# `JobsFileVolumes`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、使用与输出](#usage)
- [二、安装、更新与卸载](#management)
- [三、精确多选、日志与验证](#transport)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

文件右键提供 **🧩 合并分卷** 与 **✂️ 拆分文件**，两项按当前选择互斥显示，共享 `file-volumes` 一个安装开关。分卷格式与同级 macOS 工具、`WindowsOS_11` 的 `merge.command` / `split.command` 兼容：`完整文件名@序号of总数`，支持补零编号和名称中的 `@`。不要求另一个仓库存在，不调用 macOS `.command`。

最低目标为 [**Windows**](https://www.microsoft.com/windows) 10 x64 图形桌面、系统 [**Windows PowerShell**](https://learn.microsoft.com/powershell/scripting/windows-powershell/overview) 5.1 Desktop。Windows 11 使用“显示更多选项”或 `Shift+F10`；原生菜单需要匹配 Explorer 架构的 MSVC / Windows SDK。完整实机兼容性仍需目标机验收。

| 右键选择 | 可见入口 / 结果 |
| --- | --- |
| 单个普通文件，包括分卷本身 | ✂️ 拆分文件；显示自述并回车继续后选择分卷上限。 |
| 完整多选同目录、同原名的一组非空分卷 | 🧩 合并分卷；按数字卷号恢复，与选择顺序无关。 |
| 少选一卷、混组、混总数、重复编号、普通文件多选、空卷 | 隐藏合并，不扫描目录补齐未选文件。 |
| 文件夹、背景、链接、设备、多选混入目录 | 两项均不显示；执行前再次检查。 |
| 拆分上限 | 默认 50 MiB，另有 100 MiB、1900 MiB、自定义 0.001 至 1048576 MiB（3 位小数，向下取整为字节）。 |
| 文件不大于上限、超过 10000 卷 | 报错停止；调小或调大上限后重试。 |

**始终保留源文件及分卷，不提供自动删除。** 输出存在时停止，绝不覆盖。业务采用固定 1 MiB 缓冲区，无需将整个大文件装入内存。

## 一、<span id="usage">使用与输出</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

1、右键 `D:\资料\archive.tar.gz`，选择“✂️ 拆分文件”，在控制台阅读自述并回车，再在原生窗口选择上限。取消或关闭选择窗口不生成分卷，`Ctrl+C` 可中断。

2、结果发布到 `D:\资料\archive.tar.gz.chunks\`，文件为 `archive.tar.gz@1ofN` 至 `archive.tar.gz@NofN`。先计算 `N = ceil(大小 / 上限)`，再按 `ceil(大小 / N)` 均匀拆分，每卷不超过上限。

3、在分卷目录中完整选中这一组分卷，右键“🧩 合并分卷”；合并发布到**分卷所在目录**的 `archive.tar.gz`。不同组分开处理，目录内其它未选文件不会参与。合并后完整文件与分卷共存，再次合并需另选输出位置或自行处理已有结果。

所有输出先在同目录独占 `.JobsSplit-<随机值>.partial/` 或 `.JobsMerge-<随机值>.partial` 生成；校验总长度、分卷上限、SHA-256 和输入状态后以不覆盖的文件 / 目录移动发布。分卷读取在 Windows 使用 `FileShare.Read` 阻止写入 / 删除共享冲突；已有写入者导致操作失败。失败候选保留并在窗口提示精确路径，不把残缺结果当作完整文件；确认不需要后可自行清理。未提供断点续传，重新运行会创建新的候选。

菜单识别与点击间文件可能发生变化，运行端会重新校验。菜单识别保守比较完整原名和父路径大小写；不跨目录猜测同组，不支持其它工具的 ZIP / 7z 压缩分卷。设备名、非法 Windows 原文件名、零 / 越界编号及超过 9 位的数字标记被拒绝。

## 二、<span id="management">安装、更新与卸载</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

整个 `JobsFileVolumes` 目录可独立复制。双击 [Manage.cmd](./Manage.cmd) 进入管理面板，选“安装 / 更新”或“卸载”后直接执行；关闭 / 取消不处理。也可通过上级总管理面板选择 `file-volumes`。本包统一启用 / 停用两个互斥入口，不影响其它功能。

安装先复制独立 release、校验复制摘要，再用现有 [**MSVC / Windows SDK**](https://visualstudio.microsoft.com/visual-cpp-build-tools/) 编译动态菜单 DLL；缺失时停止，不联网安装编译器。只登记当前用户的 `HKCU\Software\Classes\*\shellex\ContextMenuHandlers\Jobs.WindowsExtension.file-volumes` 和 `HKCU\Software\Classes\CLSID\{6F7BA84C-324C-472C-B618-B0E3D44244DB}`。不登记静态菜单作为降级，保证多选条件由真实选择决定。

安装失败事务恢复本包注册表及设置；卸载停用菜单并保留运行文件、备份、日志和禁用墓碑。运行状态在当前用户本地应用数据 `Jobs\WindowsExtension\extensions\file-volumes\`，下分 `settings.json`、`releases/`、`backups/`、`logs/`。不提权，不修改永久执行策略，不读取其它功能的选择。

## 三、<span id="transport">精确多选、日志与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

原生 handler 读取 `CF_HDROP` 的全部选择，只启动一个可见 PowerShell 控制台。选择路径写为 UTF-8 JSON 临时清单，以文件参数传递，避免命令行长度限制和路径脚本注入；最多 10000 项，清单上限 16 MiB。成功读取后删除本次清单；内容不写日志。启动失败删除本次清单，启动后被强制终止或清单解析失败可能留下 `%TEMP%\JobsFileVolumes\selection-<GUID>.json`，只包含所选路径，可自行删除。控制台显示具体路径，持久日志只记操作状态。

| 文件 | 职责 |
| --- | --- |
| [Extension.json](./Extension.json) | 功能身份、总面板名称和基础设施覆盖白名单。 |
| [Scripts/README.md](./Scripts/README.md) | 原生菜单、精确选择、流式业务与安装模块说明。 |
| [Manage.cmd](./Manage.cmd) | 当前用户安装 / 更新与卸载入口。 |

隔离回归 `Tests/FileVolumes.Tests.ps1` 覆盖真实随机字节跨块拆分 / 重组、数值排序、特殊路径、缺卷 / 重复 / 空卷、无覆盖、链接、输入变化及失败保留；`Tests/FileVolumesMenuProbe.cpp` 覆盖单选 / 完整多选和隐藏条件。独立复制、组合清单、安装计划与模板由共享回归核对。测试只用临时夹具，不注册真实菜单或处理用户业务文件；本轮 macOS PowerShell 7 与 portable C++ 通过不代替 Windows PowerShell 5.1、MSVC、Explorer 和真实锁行为验收。

管理安装 / 卸载时双击 `Manage.cmd`，它只通过 WScript 唤起 GUI，随后立即结束本次脚本；不在 CMD 中编译、安装或等待输入。也可直接双击 `Manage.vbs` 进入同一面板。每个选项显示等待、执行中、完成或失败，底部实时滚动标准输出和错误，可选中复制或点击“复制全部日志”；无可靠百分比时显示执行中，总体显示完成项数。运行期间等当前事务结束后关闭，完整管理日志位于系统临时目录 `JobsExtensionManager-<运行编号>.log`。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

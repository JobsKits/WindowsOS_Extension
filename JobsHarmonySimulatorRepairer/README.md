# JobsHarmonySimulatorRepairer · Harmony 模拟器检测与修复

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、功能与使用](#jobs-toc-heading-2)
- [二、安装、卸载与依赖](#jobs-toc-heading-3)
- [三、目录、日志与验证](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

> **最低支持系统：Windows 10 x64。** 本地模拟器限官方支持的 AMD64 物理机；具体最低 build、Windows 5.1 / Explorer 菜单与真实模拟器仍须目标机验收。

仅在系统桌面空白右键显示“**Harmony 模拟器检测与修复**”。使用已有 [**DevEco Emulator**](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-command-line)，检测工具能力、已下载 Release 镜像和现有实例；选择后对该唯一实例执行保留数据的冷启动。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、功能与使用 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 入口 / 状态 | 行为 |
| --- | --- |
| `Run.cmd -Check` | 只读列出 CLI、镜像与实例，不创建日志、下载、接受许可或启动设备；未知输出报错。 |
| `Run.cmd` 或桌面菜单 | 回车确认检测，选择唯一实例；停止状态回车冷启动，运行状态输入精确 `YES` 后停止并冷启动。 |
| 实例为空 | 给出新建入口后停止，不创建替代实例。 |
| 工具、状态或身份不明 | 保留现场并停止，不猜测、不自动循环修复。 |

冷启动使用官方 `-start NAME -bootMode coldboot`（DevEco 6.1.0 Release 起支持），启动前复核名称、实例路径、设备类型和系统版本。运行中的实例先 `-stop NAME`，轮询官方 `isRunning=false` 后才启动，再回读 `isRunning=true`；这确认实例运行，不代表系统或 hdc 已就绪。不会使用 `reset`、删除镜像、清除应用或数据；重启会中断该实例的在途任务。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、安装、卸载与依赖 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

双击 [Install.cmd](./Install.cmd) 安装，[Uninstall.cmd](./Uninstall.cmd) 卸载；也可在[总安装面板](../README.md)独立勾选。卸载只关闭本包菜单，保留模拟器、工具、日志和安装备份。安装需要现有 MSVC / Windows SDK，当前用户 COM 注册，无需管理员权限。

发现顺序为显式 `HARMONY_EMULATOR_BIN`、`DEVECO_STUDIO_HOME` / `TOOL_HOME`、常见 DevEco 安装位置、用户级 `LOCALAPPDATA/Jobs/HarmonySimulator/tools` 和 PATH；显式路径失效或发现多个兼容工具时停止。检测入口不安装工具或镜像、不修改代理和 PATH、不自动接受官方许可；需要开发者账号的镜像仍须在 DevEco Studio 完成本人授权。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、目录、日志与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 路径 | 职责 |
| --- | --- |
| [Scripts](./Scripts/README.md) | 自包含业务、原生桌面 handler、构建与安装事务。 |
| `Extension.json` | 固定独立身份 `harmony-simulator-repair`。 |
| `Install.cmd` / `Uninstall.cmd` / `Run.cmd` | 安装、卸载、独立检测与修复。 |

交互日志在当前用户 `LOCALAPPDATA/Jobs/WindowsExtension/extensions/harmony-simulator-repair/logs`，每次运行独立文件。安装状态和精确注册表备份同属本包根目录。隔离回归见 [HarmonySimulatorRepairer.Tests.ps1](../Tests/HarmonySimulatorRepairer.Tests.ps1)，不操作真实设备。官方参数及状态字段依据[华为命令行说明](https://developer.huawei.com/consumer/cn/doc/doccenter-deveco-studio/ide-emulator-command-line.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

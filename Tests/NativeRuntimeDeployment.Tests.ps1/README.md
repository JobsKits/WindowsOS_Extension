# `NativeRuntimeDeployment.Tests.ps1` · 原生运行产物部署回归

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、用途与断言范围](#coverage)
- [二、运行方式](#run)
- [三、临时夹具与验证边界](#isolation)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

> [NativeRuntimeDeployment.Tests.ps1](./NativeRuntimeDeployment.Tests.ps1) 验证本仓右键扩展的部署与运行文件边界，只使用临时夹具。

## 一、<span id="coverage">用途与断言范围</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 验证独立 [**Flutter**](https://flutter.dev/) 运行包和联合 Flutter 包在 `installed / build` 两条路线中都具有必需的菜单 DLL 与后台宿主 EXE。
- 验证联合包内嵌 `run` 动作的后台宿主位于真实 release 的 `Scripts/Actions/run/bin/`，不会落入编译工作区父级。
- 验证自动 / 独立清理后运行 DLL 与 EXE 的路径、内容哈希保持一致，默认安装位置不混入 OBJ / RSP 等编译中间文件。
- 验证缺失后台宿主时阻断部署并保留旧宿主；执行联合包真实构建尾段时使用假编译器，检查输出不越出指定目录。

## 二、<span id="run">运行方式</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

依赖 [**PowerShell**](https://learn.microsoft.com/powershell/)；脚本保持 Windows PowerShell 5.1 兼容，也可在 [**macOS**](https://www.apple.com/macos/) 的 PowerShell 7 中运行。脚本从自身所在目录向上定位仓库根，不依赖启动工作目录。

在本目录运行：

```powershell
pwsh -NoLogo -NoProfile -File "./NativeRuntimeDeployment.Tests.ps1"
```

使用 [**Windows**](https://www.microsoft.com/windows) 自带的 PowerShell 5.1 时运行：

```powershell
powershell.exe -NoLogo -NoProfile -File ".\NativeRuntimeDeployment.Tests.ps1"
```

脚本无参数、无交互；运行后直接执行隔离断言，标准输出显示结果，断言失败抛出异常并返回非零。清单 JSON 和随包脚本按 UTF-8 读取，不依赖 Windows PowerShell 5.1 的系统代码页。未创建独立日志文件，需要留档时由调用方捕获标准输出与标准错误。

## 三、<span id="isolation">临时夹具与验证边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

测试只在临时目录生成假 DLL / EXE 和编译中间文件；联合包构建尾段使用临时假 [**C#**](https://learn.microsoft.com/dotnet/csharp/) 编译器。不调用 [**MSVC**](https://learn.microsoft.com/cpp/build/reference/compiling-a-c-cpp-program) 、不写系统菜单注册表、不安装扩展，也不运行生成的后台宿主。

临时文件位于系统临时目录，退出时清理；当前进程临时调整的 `LOCALAPPDATA` 在结束时恢复。隔离断言通过不能代替真实桌面菜单、原生界面或工具链业务验收。



<!-- JOBS_TERMINAL_STYLE_V1:BEGIN -->

> Windows 终端配色保护：支持完整颜色查询的交互控制台会先保存当前会话默认前景、背景与16色色表，再临时使用黑底白字和统一强调色；正常结束、业务失败及可捕获中断后恢复。用户运行中自行改动的颜色保留并提示，不修改用户主题、共享 Profile、注册表或全局策略。快照不包含进入前任意叠加的临时文字样式。非控制台、重定向、`NO_COLOR`、Sourcetree 及无法可靠保存／恢复颜色的环境保持原状态或降级为纯文本。

> 强制结束进程或终端崩溃无法保证自动恢复。恢复失败时保留并提示本轮 `%TEMP%\JobsTerminalStyle-<PID>-*.ps1` 恢复脚本，需在原控制台核对后运行；不要通过重置用户配置恢复。`-ExecutionPolicy Bypass` 如被入口使用，仅作用于本次子进程，不持久修改策略。

> 验证范围：已完成 PowerShell 语法、参数／退出与隔离生命周期核验；Windows 原生控制台的显示、按键与 `Ctrl+C` 实机验证尚未完成。

<!-- JOBS_TERMINAL_STYLE_V1:END -->

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

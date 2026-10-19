# `Scripts`：Flutter 第三方依赖提取

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、文件职责](#jobs-toc-heading-2)
- [二、运行与影响](#jobs-toc-heading-3)
- [三、维护与验证](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录是 [JobsFlutterDependencyExtractor](../README.md) 的完整独立运行与安装文件。安装后从本包 release 内运行；不读取父仓或相邻功能包。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、文件职责</span><!-- jobs-toc:heading-end -->

| 文件 | 职责 |
| --- | --- |
| [Action.psm1](./Action.psm1) | 内置自述、回车确认、精确 Flutter 项目门禁、目录输入、健康原生 Dart 发现和同步提取。 |
| [ExtractFlutterDependencies.dart](./ExtractFlutterDependencies.dart) | 根据锁文件和 package_config 校验并复制 Pub 第三方依赖源码与许可证；只用 Dart 标准库。 |
| [Invoke.ps1](./Invoke.ps1) | 已安装菜单入口，核对本包启用状态和目标后调用统一业务入口；失败保留终端。 |
| [Manage.ps1](./Manage.ps1) | 独立安装 / 卸载入口，由上一级 `.cmd` 启动，默认取消的原生确认窗口。 |
| [PackageInstaller.psm1](./PackageInstaller.psm1) | 本包文件校验与 release、当前用户菜单注册、备份、状态提交及异常回滚。 |
| [Common.psm1](./Common.psm1) | 本包内嵌的路径、原生 argv、进程超时清理和通用日志基础设施。 |

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、运行与影响</span><!-- jobs-toc:heading-end -->

正常使用上一级 [Install.cmd](../Install.cmd)，然后右键 Flutter 项目文件夹选择“提取 Flutter 第三方依赖”。终端先打印固定在脚本内的自述，按回车继续；输出父目录输入或拖入均可，空行使用系统桌面。不会执行路径中的 Shell 表达式。

共享 Dart 引擎通过独立参数调用：

```powershell
dart.exe `
  .\ExtractFlutterDependencies.dart `
  --project 'D:\Flutter 项目' `
  --destination 'D:\依赖归档'
```

项目与依赖缓存只读，结果写入指定父目录下的新目录。不会安装 SDK、下载依赖或执行 `flutter pub get`；记录缺失、过期或包源码不可用时明确停止。导出范围与风险详见上一级 README。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、维护与验证</span><!-- jobs-toc:heading-end -->

PowerShell 源码为 UTF-8 BOM、CRLF，兼容 Windows PowerShell 5.1。四份基础设施模板可由父仓维护工具受控同步；`Action.psm1` 与 Dart 引擎是本功能业务，不能用相邻包业务覆盖。跨平台引擎同源维护，发布时按 SHA-256 核对 Windows 与 macOS 副本。

业务日志在当前用户本地应用数据中本功能的 `logs/extract-*.log`；运行时显示精确位置，并脱敏地址凭据和敏感参数。普通测试只使用临时目录和模拟命令，不调用真实安装入口或注册菜单。静态与夹具验证不能代替 Windows 桌面实测。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

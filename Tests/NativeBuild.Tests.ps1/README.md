# 原生构建参数回归

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行与覆盖范围](#usage)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

> 使用临时目录执行各包构建脚本的响应文件生成片段，检查 [**MSVC**](https://learn.microsoft.com/en-us/cpp/build/reference/cl-command-files?view=msvc-170) 按物理行处理 `/link` 的参数边界。

## 一、<span id="usage">运行与覆盖范围</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录运行，支持 Windows PowerShell 5.1 或 PowerShell 7：

```powershell
./NativeBuild.Tests.ps1
```

- 检查全部 `Jobs*/Scripts/Build.ps1` 生成的 `/OUT`、`/DEF`、系统库及编译参数归属，覆盖中文、空格和特殊字符路径，并用旧格式反例检验断言。
- 不调用编译器、不安装扩展；仅在系统临时目录写入响应文件，结束时清理本轮目录，失败返回非零退出码。
- 工作流在真实 MSVC 构建前运行本测试；此检查不能代替 Windows 上的实际编译和桌面菜单验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

# `NamedParameterTests.ps1`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行方式](#run)
- [二、覆盖与边界](#coverage)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

比较临时 [**PowerShell**](https://learn.microsoft.com/powershell/) 源脚本与所生成相对路径入口的参数绑定和退出码。测试调用真实生成器，仅运行自行创建的临时脚本，不显示界面、不注册菜单，也不读写管理面板偏好。

## 一、<span id="run">运行方式</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录使用可运行项目脚本的 PowerShell 执行：

```powershell
pwsh -NoLogo -NoProfile -File ./NamedParameterTests.ps1
```

运行器通过当前进程的解释器分别启动源脚本与入口，比较结构化输出和实际退出码；临时夹具在结束后清理，诊断直接写入标准输出或标准错误。主生成器的说明见[功能 README](../../README.md)。

## 二、<span id="coverage">覆盖与边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

覆盖命名参数、开启与关闭的开关、空字符串、位置参数、别名、必填参数的 `AllowEmptyString`、`ValueFromRemainingArguments` 的未命名余参与显式 `-Rest @(...)` 数组绑定及源脚本 `exit 23`，并核对源文件未被改写。普通脚本将公共参数名定义为不同类型时，入口须明确拒绝并提示 `reserved launcher parameter`，不能静默将原值变成开关。

该入口验证 PowerShell 绑定逻辑，不执行 `.cmd` 或 `.bat`，也不代表 [**Windows**](https://www.microsoft.com/windows) 原生 Shell 注册、批处理参数、代码页和 GUI 已验收。显式布尔开关的 `-File` 测试需要 PowerShell 6 或以上版本，不能把新版本测试结果当作 Windows PowerShell 5.1 的原生验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

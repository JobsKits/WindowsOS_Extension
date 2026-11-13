# 运行前体检隔离回归

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行与覆盖](#usage)
- [二、验证边界](#limits)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

以临时工程、SDK 文件和假工具验证独立及聚合运行器；不联网、不安装 SDK、不创建真实设备、不注册菜单或运行用户工程。

## 一、<span id="usage">运行与覆盖</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录运行现有 [**PowerShell**](https://learn.microsoft.com/powershell/)：

```powershell
pwsh -NoProfile -File ./FlutterRunnerPreflight.Tests.ps1
```

覆盖 HDC 目标 / 原生 USB 证据、可运行目标去重、无 HDC 工具仍可见、授权未就绪、HDC 超时、普通华为外设 / ADB / 非 USB / 断开记录排除，以及三端状态、iOS 不适用、普通 SDK 无 HAP、缺少 HDC / 鸿蒙清单 / 插件适配、doctor 警告和畸形输出、版本不符、超时、健康目标与其它平台失败并存、取消、目标复检失败，以及运行前失败时缓存准备和应用启动均不执行。已有分组回归继续验证创建及精确设备承接。

## 二、<span id="limits">验证边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

跨平台隔离测试不代表 Windows PowerShell 5.1、原生控制台、Explorer 菜单和真实设备已验收；SDK 自身诊断行为、构建及签名仍须目标环境核对。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

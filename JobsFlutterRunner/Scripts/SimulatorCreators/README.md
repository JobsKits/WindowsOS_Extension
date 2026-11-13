# Flutter Runner 模拟器创建入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

本目录保存 Jobs 桌面 Android / Harmony 新建模拟器入口的最小运行闭包，随当前 Runner 发布，不依赖兄弟包已安装。入口与依赖逐字节复用原工程，不维护第二套创建逻辑。

## 一、<span id="entry">入口与影响</span>

- [Android](./Android/Scripts/README.md)：`CreateAndroidSimulator.ps1 -Create`，明确新建，保留官方 SDK、镜像、许可、确认、日志及已有设备保护。
- [Harmony](./Harmony/Scripts/README.md)：`CreateHarmonySimulator.ps1`，新建唯一实例；保留工具与镜像准备、华为许可、区域约束、确认及日志。

Runner 用独立 Windows PowerShell 在当前控制台调用入口，隔离同名模块；创建且启动成功后通过本轮独立结果文件返回精确目标，Runner 等待 Flutter 识别后自动运行当前工程。取消、跳过启动或失败不运行；当前工程不支持该平台时保留实例并返回选择。两类本地模拟器沿原 x64 宿主要求；Windows 没有 iOS 本地模拟器入口。

## 二、<span id="verify">维护与验证</span>

维护原创建器后同步此闭包并核对文件哈希。隔离测试只使用临时目录、假设备及子进程入口，不安装 SDK、注册菜单或创建真实设备；Windows 原生控制台与真实设备需另验。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

# `FileContentViewer.Tests.ps1`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、入口与参数](#entry)
- [二、路径、输出与恢复](#paths)
- [三、验证范围](#verification)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

FileContentViewer.Tests.ps1 | WindowsOS@Extension 临时文件和隔离终端输出，不安装、不注册，不读取用户业务文件。

本包保存真正脚本 [FileContentViewer.Tests.ps1](./FileContentViewer.Tests.ps1)。完整功能、依赖及操作入口见[所属目录说明](../README.md)；本说明补充该脚本的实际参数、路径和运行边界。

## 一、<span id="entry">入口与参数</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 文件夹与真正脚本完整同名，整体复制时保留上级功能目录的资源与模块；本内部脚本包不等于脱离功能目录后的独立软件。
- 当前项目最低系统目标为 Windows 10 64 位（x64）；解释器、宿主与 SDK 依赖继续服从脚本原有要求，跨端运行结果另行验证。VBS 使用系统 WScript，CMD 使用系统命令解释器，PowerShell 入口延续原宿主和版本约束。
- 交互入口沿用原自述、确认与取消；后台 worker／source 模块沿用调用方已确认的请求，不因为包装增加重复等待。取消、空选、EOF 和失败按原业务协议处理。

## 二、<span id="paths">路径、输出与恢复</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 源码入口位于本同名包；资源从实际脚本位置定位，不依赖启动工作目录。上级公开管理 CMD 仍直接放置，可从功能目录启动原管理面板。
- 源包装与已发布运行目录分别处理：安装器读取源包装后，继续发布原 flat 资源文件名，保留旧收据、菜单、后台进程和资源名约定。已有 SDK 资源包的层级保留，不统一压平。
- 参数、输出、日志位置与持久状态由原实现及所属功能管理；本次包装不新增全局配置、代理、服务或额外解释器。恢复／卸载仍使用原功能入口，不手工删除共享工具、用户数据或未知归属对象。
- 原业务可能涉及的文件、进程、网络或菜单副作用，以首屏说明、计划与原确认门禁为准；查询参数不等于授权执行安装、构建、下载、清理或卸载。

## 三、<span id="verification">验证范围</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

源路径包装、原参数声明、双布局寻址与语法在本机隔离目录核对；34 个功能包的只读发布构造前后文件清单一致。该结果不代表 Windows 原生 CMD／VBS、GUI、注册表、UAC、真实 SDK 下载、构建、安装或卸载已验收。修改后的脚本尚未替换用户已安装资源。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

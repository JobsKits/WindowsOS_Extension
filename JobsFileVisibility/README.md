# `JobsFileVisibility` · 隐藏 / 显示所选项目

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、安装 / 更新与卸载](#management)
- [二、源码、运行资源与验证](#source-build)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

选中一个或多个普通文件／文件夹，右键选择 **🙈 隐藏所选项目** 或 **👁️ 显示所选项目**。最多 128 项；同一选择混有隐藏和可见项目时，两项均可用。全可见时禁用显示，全隐藏时禁用隐藏；状态读取失败时两项禁用。背景、驱动器根目录、设备、重解析点／符号链接及包含它们的混合选择不提供功能；设备命名空间及扩展路径前缀不属于本入口支持范围。

| 使用 | 行为 |
| --- | --- |
| 隐藏所选项目 | 仅给所选对象设置 `FILE_ATTRIBUTE_HIDDEN`，不递归子项。 |
| 显示所选项目 | 仅清除所选对象的 Hidden 位，保留其它属性、文件名和内容。 |
| 隐藏后恢复 | 先用系统“隐藏的项目”或已有全局隐藏显示菜单让对象可选，再右键“显示所选项目”。 |
| 部分失败 | 继续处理剩余项，错误弹窗列失败计数、最多八项路径及 Win32 错误码；成功项保留。 |
| 目标发生替换 | 点击时及写后复核文件身份；失败如实报告，不声称全部成功。 |

本功能 `file-visibility` 与已有 `hidden-files-toggle` 是两个独立安装项。它不改当前用户的全局显示偏好；System 属性仍保留，因此受保护系统文件可能仍受系统显示设置限制。隐藏不是访问权限或加密保护。

## 一、<span id="management">安装 / 更新与卸载</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

完整目录可独立复制、改名。双击 [Manage.cmd](./Manage.cmd) 或 [Manage.vbs](./Manage.vbs/Manage.vbs)，在本包面板选择安装 / 更新或卸载；也可从本平台总面板选择“🫥 隐藏 / 显示所选项目”。默认空选，取消不部署；主操作按钮为本次管理确认。现有十语言、白天／黑夜／跟随系统、后台托盘、任务状态与日志功能一并随包提供。原生菜单及错误提示复用管理面板语言偏好，跟随系统使用显示语言；错误对话框沿系统原生外观。

目标为 Windows 10 / 11 图形桌面及系统 PowerShell 5.1 Desktop；Windows 11 在“显示更多选项”经典菜单中使用。安装需要已经准备好的 [**MSVC 与 Windows SDK**](https://visualstudio.microsoft.com/visual-cpp-build-tools/)，构建匹配 Explorer 的 DLL；缺编译器明确失败，不先写半套注册表。x64／ARM64／x86 构建路线沿既有模板，原生验收分别进行。

安装先校验独立 release、构建 `bin/JobsFileVisibilityContextMenu.dll`，再事务登记当前用户的 `*` 文件 handler、`Directory` 目录 handler，以及独立 CLSID `{F667A0A8-C7A6-4C79-A420-12DA30EBF981}`；无背景、Drive 或其它功能键。默认路径 `%LOCALAPPDATA%\Jobs\WindowsExtension\extensions\file-visibility`，另有本包 `work\WindowsExtension` 构建目录路线。卸载只关闭本项菜单并保留管理日志／备份／运行版本，不恢复此前对用户文件作出的隐藏设置；恢复使用显示动作。旧缓存菜单在注册归属失效后拒绝写入。

## 二、<span id="source-build">源码、运行资源与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

[Scripts](./Scripts/README.md) 提供原生 C++ 源码、构建入口、PowerShell 安装与 CLI、完整可运行的解释型管理面板资源。菜单由 DLL 直接操作完整 `CF_HDROP` 选择，不拼接 CMD／PowerShell 参数，没有命令行长度截断；CLI 显式使用 Hide 或 Show 并调用同 DLL 实现。读写通过不跟随所选链接的句柄进行；只设置当前 Hidden 位，时间字段保持不变，写后校验并通知 Explorer。多选执行逐项完成，不承诺跨文件原子事务。

本机已验证 C++ 边界夹具和 PowerShell 7 自包含复制／发布、安装计划、十语与语法；Windows 原生 DLL 构建、PowerShell 5.1、MSVC、Explorer 和 WinForms 桌面仍待目标系统验收。这里交付源码、可复现构建及解释型管理运行包。测试入口见 [Tests](./Tests/README.md)，本次验证批次见项目根资产盘点。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

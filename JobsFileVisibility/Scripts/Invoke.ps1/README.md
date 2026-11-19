# Invoke.ps1 · 显式隐藏 / 显示入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

此维护入口校验本包安装状态后转交 [Action.psm1](../Action.psm1)；普通右键菜单直接在 DLL 中操作，不经过本入口。`-Target` 接受字符串数组，`-State` 必须明确为 `Hide` 或 `Show`，没有 Toggle 默认值。应使用匹配 DLL 架构的系统 Windows PowerShell 5.1。

```powershell
& '已安装release\Scripts\Invoke.ps1' -Target @('C:\资料\文件.txt','C:\资料\目录') -State Hide
& '已安装release\Scripts\Invoke.ps1' -Target @('C:\资料\文件.txt','C:\资料\目录') -State Show
```

选中路径作为数据传入同 DLL 导出；不改变全局偏好。失败抛终止错误，部分成功保留；不需要以管理员运行，不执行文件、不递归。包未安装／已卸载、DLL 缺失或精确注册归属不匹配时拒绝写入。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

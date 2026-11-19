# Invoke.ps1 · 永久删除维护入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[Invoke.ps1](./Invoke.ps1) 要求 `-Target` 字符串数组，校验本包已安装／启用状态，再调用同 DLL 导出 `JobsConfirmPermanentDelete`。只有确认框明确确认后才删除；没有跳过确认或自动强删参数。使用匹配 DLL 架构的系统 [**Windows**](https://www.microsoft.com/windows) [**PowerShell**](https://learn.microsoft.com/powershell/) 5.1。

```powershell
& '已安装release\Scripts\Invoke.ps1' -Target @('C:\资料\文件.txt','C:\资料\目录')
```

路径作为数组数据传入；不经 CMD 二次解析。取消返回而不删除；失败抛终止错误，并保留原生窗口的失败路径／计数。完整限制、默认值、主题语言和安装／卸载见[功能说明](../../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

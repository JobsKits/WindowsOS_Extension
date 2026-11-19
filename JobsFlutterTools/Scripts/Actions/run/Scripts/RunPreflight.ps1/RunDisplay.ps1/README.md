# 运行日志终端展示

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

仅格式化终端展示副本，不改变 SDK 工具返回数据、下载参数或原始日志。阶段标题标红；`[错误]`、Error / failed 等错误正文标红；结构标签保留原文并添加语义图标，例如 `💬 [会话]`、`📦 [依赖]`、`⚠️ [警告]`、`❌ [错误]`。

可靠交互控制台中，URL 使用绿色；支持 VT 时同时使用下划线，URL后恢复行内原颜色，句末标点不染色。SDK 原生命令双流使用有界分块展示过滤器，跨块标签在换行时合并处理；脚本输出、创建器输出和日志查看使用同一文字格式化方法。关闭展示层后恢复原 TextWriter，不修改终端 Profile 或持久配置。

非交互、`NO_COLOR`、`TERM=dumb` 或既有纯文本模式不增加 ANSI，图标和原标签仍保留；不支持 VT 时不发送下划线控制序列。原始SDK日志保持脱敏纯文本，机器响应保持原始返回值供解析。隔离测试覆盖错误、URL、标签、逐行处理、跨块输出及数据保全；Windows 实机显示仍须另验。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

# 已有虚拟设备启动隔离回归

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、覆盖](#jobs-toc-heading-2)
- [二、边界](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

运行 `pwsh -NoProfile -File Tests/FlutterRunnerVirtualStart.Tests.ps1/FlutterRunnerVirtualStart.Tests.ps1`；Windows CI 同时以系统 PowerShell 5.1 执行。仅运行官方 HTTP 重试与菜单边界时，在同一命令末尾加 `-BoundaryOnly`。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、覆盖</span><!-- jobs-toc:heading-end -->

复用实际两份运行器及启动函数，验证限定正式组件更新、原 AVD 身份、一次启动、HDC 精确回执、现有实例 SDK 原字节备份和配置保留。许可取消、配置或 UUID 变化、空列表、返回、超时及项目门禁失败均不能改跑其它设备或创建替代实例。真实随包 Creator 私有模块和嵌套 argv 也会加载核对。官方原生 HTTP 边界覆盖 PS7 TaskCanceled / 内层 Timeout、DNS、408 / 429 / 503 后成功、Retry-After、授权 / HTML / schema 立即阻断及请求 / 退避中取消；菜单边界覆盖正常交互 fzf 缺失 / 损坏停止、显式关闭 / 非交互文本返回和方向键绑定。

官方目录重试核对两次 Headers 对象引用独立，并分别校验官网 Origin、有效 UTC 日期和正 Int64 序号；退避等待在夹具中只计数，允许系统同一时钟刻度产生相同序号，不以真实 sleep 或时间戳唯一性代替重建验证。

更新目录使用实际 sdkmanager 完整三表格式；覆盖缺表 / 缺列 / 错序 / 截断 / 预览版本 / 版本矛盾 / 非目标包畸形，以及真实 AndroidRuntime 返回 exit0 且 stderr 带 XML 错误。实际 SDK 重试核心配假进程，确认确定的目录或参数错误仅查询一次。AVD 覆盖菜单期间改路径、同名同内容重建但原生对象标记不同、启动后实例替换或 serial 复用，以及非身份运行字段变化的合法启动。鸿蒙覆盖菜单期间改配置、长准备后 UUID / 配置 / 端口改变或实例消失，以及启动期新增动态字段的合法情形。

官方归档正向侧装保留真实 ZIP 成员、大小、SHA、完整组件与实际版本复检；测试缓存使用外层 GUID 加短子目录隔离，Windows 按真实 stage 规则与最长归档成员核对普通 API 路径小于 260 字符。主失败和清理失败均输出完整异常、源码位置与调用栈；清理失败不覆盖已发生的主失败，单独发生的清理失败仍使测试失败。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、边界</span><!-- jobs-toc:heading-end -->

仅创建与删除本轮临时夹具，不联网、不安装 SDK、不启动真实模拟器或 App、不写注册表或用户工程。当前宿主只编译 Windows FileIdInfo 的 C# 提供器，文件对象标记使用受控提供器；真实 Windows kernel32、PowerShell 控制台按键、硬件加速、工具下载和模拟器兼容性仍需目标机验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>


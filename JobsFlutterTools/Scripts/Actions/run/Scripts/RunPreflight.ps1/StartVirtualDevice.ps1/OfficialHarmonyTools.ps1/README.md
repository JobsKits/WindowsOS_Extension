# 官方鸿蒙工具版本与归档核验

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、授权与证据](#jobs-toc-heading-2)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

仅供同包运行器 source 的函数库，不注册独立菜单。先查询官方公开兼容 Release 的 Command Line 表行，再按实际 `version.txt` 比较；已有健康且满足兼容版本的工具无需下载授权。缺失或落后时校验官方正式 Windows x64 包元数据、可信 HTTPS URL、精确文件名、大小和 SHA-256，独立侧装、安全解压后复核实际版本与结构，不覆盖旧安装。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、授权与证据</span><!-- jobs-toc:heading-end -->

官方登录、协议或未知 schema 阻止核验时不启动设备；可在当前流程打开官方页面、重新检查或显式提供本人取得的官方原始元数据与归档。不读取 Cookie，不假定浏览器登录能授权匿名脚本请求。详细字段和验证边界见[启动说明](../README.md#三官方目录与本人提供的证据)。本轮敏感响应只在内存使用；归档和 HDC 回执存放本轮私有目录，日志脱敏而下载保留原签名 URL。当前支持已核验的 6.1.1 兼容线，不将未知大版本套用 JDK17 链。

公开正文、版本目录和下载 URL 的原生 HTTP 请求每次最多 20 秒；超时、DNS、408 / 429 / 5xx 在本层自动退避重试，等待按秒分片，Ctrl+C 可取消。401 / 403、官方授权错误、HTML 或 schema 错误立即保持未就绪；重试边界不包含解析后的安装或设备启动。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

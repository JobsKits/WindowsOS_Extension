# SDK 网络选路隔离回归

新探测传输入口全部使用内存假响应，不进行真实 DNS、TLS、下载或代理连接。覆盖官方／CFUG等价证据与择优、显式空值及代理保留、缓存及失效、错误页与伪 Range 拒绝、官方对象 MD5 元数据及完整对象路径、企业既有代理、原生 BITS 实际通道、冷／热 SDK、目标架构与用户 fork、私有 realm、自定义 engine、请求 channel 与旧缓存区分、Google 完全离线可用 CFUG、真实大下载 A 失败后轮换 B、AUTO 镜像未同步 404。通用缓存场景直接加载公共副本，避免仅验证 Runner 专用副本而遗漏分发差异；路径拆分同时在 Windows PowerShell 5.1 验证。

```powershell
pwsh -NoLogo -NoProfile -File ./SdkNetworkRoute.Tests.ps1
```

运行器通用缓存另外覆盖：冷缓存按实际 engine 预检 sky_engine，健康 stamps 和 payload 不强制联网；旧 engine 或丢失 payload 不能误判就绪；显式 storage／realm 保持原样。

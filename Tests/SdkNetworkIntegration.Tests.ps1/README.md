# Windows SDK网络分发隔离回归

运行 `pwsh -NoProfile -File ./SdkNetworkIntegration.Tests.ps1`。检查三个仓的公共副本、独立／聚合release包含同名模块、精确channel安装和CLI纯machine stdout。网络、解压均使用临时假数据，不安装SDK、不改代理或注册表。

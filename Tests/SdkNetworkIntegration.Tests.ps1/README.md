# Windows SDK网络分发隔离回归

运行 `pwsh -NoProfile -File ./SdkNetworkIntegration.Tests.ps1`。检查三个仓的公共副本、独立／聚合release包含同名模块、精确channel安装和CLI纯machine stdout。发布清单夹具同时包含 x64／ARM64，按当前宿主架构验证唯一新归档及其 SHA，不把 x64 假数据当作全部 Windows 环境。网络、解压均使用临时假数据，不安装SDK、不改代理或注册表。

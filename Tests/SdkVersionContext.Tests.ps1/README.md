# 下载前 SDK 版本上下文隔离回归

通过临时项目、SDK 元数据及假获取进程，对独立 Runner 和统一工具包分别验证：下载前显示项目声明、本地 Flutter 版本、SDK 路径、目标 Dart、engine 与宿主平台；拒绝旧 Dart 缓存和旧 engine 元数据，未知版本明确说明；保留机器响应及旧声明格式。不运行 Flutter、Dart、不联网、不接触真实会话或用户 SDK。

```powershell
pwsh -NoLogo -NoProfile -File ./SdkVersionContext.Tests.ps1
```

实际运行入口还覆盖：版本检查后先准备通用 SDK，再枚举设备；设备取消不启动业务，SDK 准备失败／取消原样传播并阻断后续设备查询。

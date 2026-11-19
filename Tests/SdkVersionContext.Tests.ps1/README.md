# 下载前 SDK 版本上下文隔离回归

通过临时项目、SDK 元数据及假获取进程，对独立 Runner 和统一工具包分别验证：下载前显示项目声明、本地 Flutter 版本、SDK 路径、目标 Dart、engine 与宿主平台；拒绝旧 Dart 缓存和旧 engine 元数据，未知版本明确说明；保留机器响应及旧声明格式。不运行 Flutter、Dart、不联网、不接触真实会话或用户 SDK。

```powershell
pwsh -NoLogo -NoProfile -File ./SdkVersionContext.Tests.ps1
```

实际运行入口还覆盖：版本检查后先准备通用 SDK，再获取、展示和校验同一份本轮体检报告，最后枚举设备。体检阶段使用明确替身，只验证当前 SDK／工程、报告身份和阶段顺序，不让假 Flutter 文件名进入真实 SDK 路径或宿主体检；实际环境体检另由对应回归覆盖。

设备取消不调用运行宿主；通用 SDK 准备失败／取消时原样传播，不进入体检或设备查询；体检报告展示后仍须通过校验，校验失败同样原样传播，并阻止设备查询和业务启动。独立 Runner 与统一工具包都执行这些隔离场景，可使用 Windows PowerShell 5.1 或 `pwsh` 运行。

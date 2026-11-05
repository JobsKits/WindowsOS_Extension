# SDK 获取持续重试隔离回归

使用临时目录、假命令、回环 HTTP 与本机已有 PowerShell，验证超出固定重试次数后仍继续、成功后停止、退避封顶、权限错误、主动取消、持续下载进度、安全续传、摘要失败重取与独立包资源一致性。也覆盖 Windows SDK 安装失败／退出零但缺组件的持续获取、UAC 取消、重启要求，以及 FVM 返回零但实际缺少 SDK 文件的继续准备。不下载真实 SDK、不修改系统环境或菜单。

```powershell
pwsh -NoLogo -NoProfile -File ./SdkAcquisitionRetry.Tests.ps1
```

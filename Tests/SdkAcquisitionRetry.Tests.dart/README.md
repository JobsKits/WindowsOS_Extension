# Dart SDK 获取重试隔离回归

使用本机已有 Dart、临时假 Flutter 验证失败重试、成功停止、机器响应、业务只执行一次、退避期间 Ctrl+C 和日志脱敏。当前假工具为 Unix shell；Windows 原生控制台取消仍需实机验收。

```shell
dart ./SdkAcquisitionRetry.Tests.dart
```

Mac宿主的导入型测试将主文件与无网络选路桥接假件放在私有临时目录，仅验证Dart层重试、机器输出与取消；生产随包定位及PowerShell网络核心分别由分发和网络回归覆盖。

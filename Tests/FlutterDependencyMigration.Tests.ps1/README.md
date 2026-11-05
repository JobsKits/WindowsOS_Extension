# 一键依赖迁移终端与 ZIP 隔离回归

```powershell
pwsh -NoProfile -File ./FlutterDependencyMigration.Tests.ps1
```

在系统临时目录创建独立项目、产物和原始缓存夹具，使用替身引擎核对参数与交互，并真实生成、读取和哈希校验 ZIP。覆盖默认私库、空格确认全提取、不打包、保留/删除本次产物、源文件变动拒绝删除、空输入重问、YES 导入门禁和预检冲突停止。

不注册菜单、不安装 SDK、不写入真实 Pub/Gradle 缓存。缓存结构识别与真实 Dart 融合另由共享引擎测试验证。PowerShell 7 在 MacOS 的结果不能替代 Windows PowerShell 5.1、CMD 拖入及 Explorer 实机验收。

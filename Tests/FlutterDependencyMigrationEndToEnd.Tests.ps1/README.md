# 一键迁移真实数据链回归

```powershell
pwsh -NoProfile -File ./FlutterDependencyMigrationEndToEnd.Tests.ps1
```

需要已经可用的 Dart；可用 `JOBS_TEST_DART` 指定现有可执行文件，不安装工具。测试把 `JobsFlutterTools` 通过真实发布器复制到临时 release，并校验迁移模块及三个 Dart 文件的哈希。

只替换运行时发现与终端输入，实际执行发布副本中的 wrapper、Dart、文件复制、ZIP 与 SHA-256 校验。覆盖默认私库、Pub 相对路径恢复、按证据筛选 Maven 私有组、预检取消零写入、YES 融合、改名 Pub/Gradle 父目录识别、凭据排除及冲突保留。

缓存目标通过临时 `PUB_CACHE`、`GRADLE_USER_HOME`、`MAVEN_REPO_LOCAL` 隔离，结束时恢复进程环境并清理夹具；不修改用户工程、真实缓存、全局 SDK，不联网，不注册菜单。MacOS / PowerShell 7 的结果只证明该宿主上的真实数据链；Windows PowerShell 5.1、FVM PE 健康检查、CMD 拖入、DLL 与 Explorer 仍需 Windows 原生验收。

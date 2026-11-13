# 一键迁移真实数据链回归

```powershell
pwsh -NoProfile -File ./FlutterDependencyMigrationEndToEnd.Tests.ps1
```

需要已经可用的 Dart；可用 `JOBS_TEST_DART` 指定现有可执行文件，不安装工具。测试把 `JobsFlutterTools` 通过真实发布器复制到临时 release，并校验迁移模块及三个 Dart 文件的哈希。

只替换运行时发现与终端输入，实际执行发布副本中的 wrapper、Dart、文件复制、ZIP 与 SHA-256 校验。覆盖默认私库、Pub 相对路径恢复、按证据筛选 Maven 私有组、预检取消零写入、YES 融合、改名 Pub/Gradle 父目录识别、凭据排除、冲突取消、保留本机跳过冲突且继续新增、导入源覆盖不备份、默认桌面备份旧字节、最终确认空回车重问、非空非 YES 零备份，以及源和目标在确认期间变化时的计划保护。

缓存目标通过临时 `PUB_CACHE`、`GRADLE_USER_HOME`、`MAVEN_REPO_LOCAL` 隔离，结束时恢复进程环境并清理夹具；不修改用户工程、真实缓存、全局 SDK，不联网，不注册菜单。MacOS / PowerShell 7 的结果只证明该宿主上的真实数据链；Windows PowerShell 5.1、FVM PE 健康检查、CMD 拖入、DLL 与 Explorer 仍需 Windows 原生验收。


<!-- JOBS_TERMINAL_STYLE_V1:BEGIN -->

> Windows 终端配色保护：支持完整颜色查询的交互控制台会先保存当前会话默认前景、背景与16色色表，再临时使用黑底白字和统一强调色；正常结束、业务失败及可捕获中断后恢复。用户运行中自行改动的颜色保留并提示，不修改用户主题、共享 Profile、注册表或全局策略。快照不包含进入前任意叠加的临时文字样式。非控制台、重定向、`NO_COLOR`、Sourcetree 及无法可靠保存／恢复颜色的环境保持原状态或降级为纯文本。

> 强制结束进程或终端崩溃无法保证自动恢复。恢复失败时保留并提示本轮 `%TEMP%\JobsTerminalStyle-<PID>-*.ps1` 恢复脚本，需在原控制台核对后运行；不要通过重置用户配置恢复。`-ExecutionPolicy Bypass` 如被入口使用，仅作用于本次子进程，不持久修改策略。

> 验证范围：已完成 PowerShell 语法、参数／退出与隔离生命周期核验；Windows 原生控制台的显示、按键与 `Ctrl+C` 实机验证尚未完成。

<!-- JOBS_TERMINAL_STYLE_V1:END -->

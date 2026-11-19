# CommandShortcutTests.ps1

从本目录运行：

```powershell
powershell.exe -NoLogo -NoProfile -File ./CommandShortcutTests.ps1
```

使用系统临时目录，结束后清理自己创建的样本；不会安装扩展、改注册表、显示GUI或运行真实业务脚本。覆盖三个原生脚本包格式、源内容保持、同级生成、格式 / 文件名拒绝、重名文件 / 目录 / 悬空链接、主题语言文案、整体改名及 PowerShell 字面量参数和退出码。参数回执按 UTF-8 读取，JSON 解析后独立归一化数组，兼容 Windows PowerShell 5.1 的管道数组行为；逐项核对数量与内容，计数失败保留原始回执。可使用 Windows PowerShell 5.1 或 `pwsh` 执行。

符号链接夹具复用仓库的 [NativeFixtures.ps1](../../../Tests/NativeFixtures.ps1/NativeFixtures.ps1)，完整源码仓需保留该文件。Windows PowerShell 5.1 通过系统 API 创建链接；只有确实缺少符号链接权限时输出 `SKIP` 并跳过相应链接断言，其它错误继续失败。不启用开发者模式、不修改系统策略。

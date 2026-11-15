# CommandShortcutTests.ps1

从本目录运行：

```powershell
pwsh -NoLogo -NoProfile -File ./CommandShortcutTests.ps1
```

使用系统临时目录，结束后清理自己创建的样本；不会安装扩展、改注册表、显示GUI或运行真实业务脚本。覆盖三个原生脚本包格式、源内容保持、同级生成、格式 / 文件名拒绝、重名文件 / 目录 / 悬空链接、主题语言文案、整体改名及 PowerShell 字面量参数和退出码。符号链接样本要求运行时提供对应 .NET API，Windows 创建链接还受本机权限限制。

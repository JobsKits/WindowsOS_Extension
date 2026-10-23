# 清理脚本

`Action.psm1` 在运行时识别精确的当前 Flutter / Android 工程，先生成并校验路径白名单，显示计划，输入 CLEAN 后重新识别并删除。Windows 没有 iOS 清理分支。

`Common.psm1`、`Invoke.ps1`、`Manage.ps1`、`PackageInstaller.psm1` 为 Infrastructure 模板的逐字节副本，按仓库同步工具维护。`Invoke.ps1` 只载入本包；安装脚本不触发清理。详见[功能说明](../README.md)。

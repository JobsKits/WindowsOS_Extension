# 脚本快捷入口扩展 · 隔离测试

| 测试 | 覆盖 |
| --- | --- |
| [CommandShortcutTests.ps1](./CommandShortcutTests.ps1/README.md) | 临时目录生成、三格式、中文特殊字符、参数 / 退出码、目录整体迁移、拒绝覆盖及十语完整性 |
| [NamedParameterTests.ps1](./NamedParameterTests.ps1/README.md) | 命名参数、别名、位置参数、开关 false、空字符串、剩余参数和保留参数冲突拒绝 |
| [CommandShortcutTargetTests.cpp](./CommandShortcutTargetTests.cpp/README.md) | 原生菜单资格逻辑，单选、多选、同名脚本、格式及重解析点 |

测试不注册、卸载或刷新真实菜单，不启动业务 GUI。PowerShell测试会执行自己创建的无副作用 PowerShell样本并验证参数和退出码；不执行 `.cmd` / `.bat`。Windows 原生 DLL、Explorer、WinForms 和真实批处理运行需单独验收。

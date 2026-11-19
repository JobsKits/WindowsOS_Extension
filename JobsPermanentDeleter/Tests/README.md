# 永久删除 · 隔离验证

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

| 验证入口 | 覆盖 |
| --- | --- |
| [PermanentDeleteCoreTests.cpp](./PermanentDeleteCoreTests.cpp/PermanentDeleteCoreTests.cpp) | 直接编译生产核心，使用内存 Win32 边界验证确认／取消、子项顺序、身份变化、根／系统路径、重解析点、短名／SUBST 别名、权限、只读、新增子项、失败计数与数量上限。 |
| [PermanentDeletePackageTests.ps1](./PermanentDeletePackageTests.ps1/PermanentDeletePackageTests.ps1) | 中文空格特殊字符路径复制改名、发布包含源与两DLL、精确注册计划、十语、语法及源码／回执／路径／DLL hash／架构变异。 |

```sh
clang++ -std=c++14 -Wall -Wextra -Werror Tests/PermanentDeleteCoreTests.cpp/PermanentDeleteCoreTests.cpp -o /tmp/jobs-delete-tests
/tmp/jobs-delete-tests
pwsh -NoProfile -File Tests/PermanentDeletePackageTests.ps1/PermanentDeletePackageTests.ps1
```

夹具只使用内存文件模型及测试临时发布目录，不注册真实扩展，不删除用户文件。C++ 边界结果、[**MacOS**](https://www.apple.com/macos/) 交叉构建、[**PowerShell**](https://learn.microsoft.com/powershell/) 7 发布检查与 [**Windows**](https://www.microsoft.com/windows) 实机验收分别记录；实际默认焦点、颜色、点按、符号链接权限、NTFS 句柄行为、[**Explorer**](https://support.microsoft.com/windows) 和 PowerShell 5.1 尚待目标系统验证。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

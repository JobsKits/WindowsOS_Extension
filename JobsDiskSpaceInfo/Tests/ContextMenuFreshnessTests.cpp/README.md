# 重复打开菜单的实时采样回归

本目录直接编译生产 [ContextMenu.cpp](../../Scripts/ContextMenu.cpp)，用最小 [Win32 / COM 边界声明](./Win32Stubs/windows.h)与[接口声明](./Win32Stubs/shlobj.h)替代系统调用；采样、过滤、汇总、格式化和 `Menu::QueryContextMenu` 均执行生产逻辑，不复制一套菜单实现。夹具只在内存中更改合成卷数据、记录插入标题，不访问真实磁盘、注册表、清理脚本或进程。

[ContextMenuFreshnessTests.cpp](./ContextMenuFreshnessTests.cpp)在同一个 `Menu` 对象上反复调用 `QueryContextMenu`，验证余量变化、总容量变化、卷挂载 / 移除、部分查询失败、枚举失败、API缺失、不完整枚举、恢复与真实零余量。每次正常打开都检查系统API重新调用；失败显示不可用，不复用上一次成功值或部分汇总。另检查系统语言重新读取、非弹出探测不采样、枚举句柄关闭及线程错误模式恢复。

在本目录执行以下命令，输出只写系统临时目录：

```shell
clang++ -std=c++14 -Wall -Wextra -Werror \
  -fsanitize=address,undefined -fno-omit-frame-pointer \
  -I ./Win32Stubs ./ContextMenuFreshnessTests.cpp \
  -o "${TMPDIR:-/tmp}/jobs-context-menu-freshness-tests"
"${TMPDIR:-/tmp}/jobs-context-menu-freshness-tests"
```

这些声明只供隔离测试编译，不能进入发布包或替代 Windows SDK；macOS 的 `wchar_t`、调用约定和原生菜单环境与 Windows 不同。测试通过说明生产 C++ 控制流在同一对象上会重新采样，不能外推 Windows 原生 DLL、Explorer 显示或真实磁盘 API 已验收。原生 Windows 需要另测“打开 → 关闭 → 创建 / 删除文件或挂载卷 → 重开”，并分别确认查询失败与恢复。

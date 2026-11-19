# 磁盘空间合计与格式回归

只测试生产 [DiskSpaceSummary.h](../../Scripts/DiskSpaceSummary.h) 的真实逻辑：多个卷求和、挂载别名去重、满盘与空盘、零容量、溢出、查询失败后拒绝部分总量，以及十语言单行描述和百分比两位小数。不注册菜单、不查询真实磁盘。

以 C++14 或更新编译器编译本目录 [DiskSpaceSummaryTests.cpp](./DiskSpaceSummaryTests.cpp)，运行临时输出文件。Windows 使用 MSVC 的 `/EHsc /std:c++14 /utf-8`；macOS 可用 `clang++ -std=c++14`。编译输出放系统临时目录。

本测试通过不能替代 Windows 原生 `IContextMenu` 菜单显示、可点击状态与真实卷统计的验收。

同一个生产菜单对象反复构建与读取失败不复用旧值，另见 [ContextMenuFreshnessTests](../ContextMenuFreshnessTests.cpp/README.md)。

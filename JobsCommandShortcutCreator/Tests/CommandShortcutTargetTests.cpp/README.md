# CommandShortcutTargetTests.cpp

使用 C++14 编译器编译当前目录的 `CommandShortcutTargetTests.cpp`，再运行产生的测试程序。例如在本目录中：

```shell
clang++ -std=c++14 -Wall -Wextra -Werror ./CommandShortcutTargetTests.cpp -o ./CommandShortcutTargetTests
./CommandShortcutTargetTests
```

测试用内存属性表代替 `GetFileAttributesW`，直接包含生产资格判定头文件；不访问真实注册表、启动Explorer或编译实际 COM DLL。覆盖单选 / 多选、三种后缀及大小写、重解析点、同名普通脚本缺失、错误类型与普通目录。

# Windows 桌面菜单固定顺序回归

本目录编译六份真实生产 `ContextMenu.cpp`，只用合成 Win32 / COM 声明替代菜单、桌面、偏好和磁盘 API；不复制排序实现，不读真实注册表，不创建业务进程，不安装 DLL。

固定相对次序为 Android 新建、Harmony 新建、Android 修复、Harmony 修复、文件显示切换、磁盘剩余。每个包自带同源 `DesktopMenuOrder.h`，菜单项通过 `MENUITEMINFOW.dwItemData` 保存整数命名空间和功能次序；不保存其它 DLL 的指针，也不使用标题判断身份。命令编号、业务归属、独立安装与卸载不变。只承诺使用同一协议的六项之间的相对顺序，其它应用菜单的位置由系统及其各自 handler 管理。

[DesktopMenuOrderTests.cpp](./DesktopMenuOrderTests.cpp)覆盖全部功能子集、回调排列和三种系统建议插入位置，共 5,871 例；逐次检查局部顺序、原始 command ID、第三方项全部字段及相对顺序。另验证默认动作探测、命令 ID 范围不足、非桌面／有选中项资格、Harmony 原生 x64 门禁、隐藏文件状态读取失败时禁用，以及菜单 API 三类失败。失败不插入降级菜单，不启动业务。未知命名空间、未知次序及 64 位高位数据均不参与排序。

在本目录执行以下命令，输出仅写系统临时目录：

```shell
clang++ -std=c++14 -Wall -Wextra -Werror \
  -fsanitize=address,undefined -fno-omit-frame-pointer \
  -I ./Win32Stubs ./DesktopMenuOrderTests.cpp \
  -o "${TMPDIR:-/tmp}/jobs-desktop-menu-order-tests"
"${TMPDIR:-/tmp}/jobs-desktop-menu-order-tests"
```

边界声明复用[磁盘菜单既有测试声明](../../JobsDiskSpaceInfo/Tests/ContextMenuFreshnessTests.cpp/Win32Stubs/windows.h)，并补充本测试所需桌面接口；它们不能进入发布包。六个生产包的头文件须逐字节一致，原生构建仍只依赖 Windows SDK，发布器将本包头文件随源码复制后编译，不访问兄弟包。

上述检查通过不等于 Windows MSVC／Explorer 实机通过。相关六包须一起安装／更新以采用共同协议；旧版独立 handler 没有标记，混用不能保证整体排序。目标机另验不同安装顺序、停用／卸载部分功能、反复重开菜单及各项实际点击。macOS 的 FinderSync 跨进程菜单不能套用此 HMENU 实现。

公开接口依据：[MENUITEMINFOW](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-menuiteminfow)、[GetMenuItemInfoW](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getmenuiteminfow)、[IContextMenu::QueryContextMenu](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-icontextmenu-querycontextmenu)。

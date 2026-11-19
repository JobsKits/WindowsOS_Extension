# Dart 文件菜单包边界夹具

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

复用生产 `FlutterRunTarget.h`，验证 `.dart` 后缀、最近包边界、非 Flutter 嵌套包阻断、根目录、中文空格及特殊字符。只在内存构造目录，不注册菜单、不启动 SDK 或设备。

## 一、<span id="run">运行与边界</span> <a href="#前言">🔼</a> <a href="#🔚">🔽</a>

在本目录使用 C++14 编译器执行：

```shell
clang++ -std=c++14 FlutterDartTargetTests.cpp -o /tmp/jobs-flutter-dart-target-tests
/tmp/jobs-flutter-dart-target-tests
```

成功输出 `PASS: 9 Dart menu package-boundary assertions`。文件系统属性、Windows COM、CMD 参数运输与真实后台生命周期仍须在 Windows 原生环境验收；本夹具不替代这些检查。

<a id="🔚" href="#前言">返回前言</a>

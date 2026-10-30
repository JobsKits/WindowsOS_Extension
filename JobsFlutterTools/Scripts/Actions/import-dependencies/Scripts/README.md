# `FlutterTools import-dependencies Scripts`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、输入与交互](#usage)
- [二、文件与参数](#files)
- [三、产物、边界与验证](#outputs)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

统一 [**Flutter**](https://flutter.dev/) 菜单的“📤 导入Flutter第三方依赖”业务核心。目标只需有效 Flutter 项目声明，不要求已有 `lib/`。先识别本工具的完整依赖导出结果，再向所选工程配置本地源码依赖；入口、安装选择和项目条件见[统一包说明](../../../../README.md)。此目录随统一包交付，不单独注册菜单。

## 一、<span id="usage">输入与交互</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

快照含提取时的 `warnings` 时，预检计划显示告警数量与原 `manifest.json` 路径；已跳过的源内容不会由导入补齐。导入产物的 `source-manifest.json` 原字节保留该清单。

1、先在统一包管理面板安装 / 更新并勾选导入项；原生动作表更新后需重载 Explorer，单改仓库源码不会改变已安装菜单。在目标 Flutter 工程右键选择“导入Flutter第三方依赖”，打开独立 CMD 后，在提示处输入或拖入本工具导出的完整目录。目录提示处空回车或空白输入会继续询问，直到输入有效路径；按 `Ctrl+C` 或真正输入结束（EOF）退出，不会在 EOF 反复重问。路径支持空格、中文和拖入时的外层引号，按数据读取，不作为命令执行。

2、目录必须同时包含 `manifest.json`、`pubspec.yaml`、`pubspec.lock` 和 `packages/`；清单要求 `formatVersion: 1`、`status: complete`。核心继续校验包目录、名称、版本、文件、依赖闭包及目标冲突，普通目录、单个包、缺文件或损坏导出均停止。压缩包请先解压，选择包含清单的那一层。

3、完整校验通过后，终端显示来源、目标与计划，精确输入 `YES` 才执行；其它输入或输入结束取消。实际导入前再次校验，校验和预览不写项目。`Ctrl+C` 中止；已写入阶段的备份与结果目录保留供核对。

## 二、<span id="files">文件与参数</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文件 | 职责 |
| --- | --- |
| [Action.psm1](./Action.psm1) | 终端自述、路径输入、导出目录初筛、只读校验、精确确认和日志。 |
| [Common.psm1](./Common.psm1) | 随包路径、原生进程 argv 调用和日志辅助。 |
| [ImportFlutterDependencies.dart](./ImportFlutterDependencies.dart) | 完整校验、独立目录复制、备份与覆盖配置。 |
| [ExtractFlutterDependencies.dart](./ExtractFlutterDependencies.dart) | 为导入核心复用已有 YAML 和文件校验；两份 Dart 文件必须同目录交付。 |

运行使用项目 FVM SDK 内健康的原生 [**Dart**](https://dart.dev)，不下载工具或回退全局 SDK。统一调度器传递固定 `import-dependencies` 动作与所选工程路径；可以先直接运行只读检查：

```powershell
dart .\ImportFlutterDependencies.dart `
  --project 'D:\Projects\MyFlutterApp' `
  --source 'D:\Exports\MyFlutterApp-dependencies' `
  --validate-only
```

`--project` 为目标工程根目录，`--source` 为完整依赖导出目录；`--validate-only` 只校验并显示计划。直接调用 Dart 时去掉该参数即执行写入，不包含 wrapper 的确认交互。

## 三、<span id="outputs">产物、边界与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

导入在目标工程 `vendor/flutter_dependencies/` 内创建唯一运行目录，`packages/` 原样保留导出的依赖源码与许可证，并为这些包增量合并 `pubspec_overrides.yaml` 的本地 `path` 覆盖。目标 pubspec.yaml 已有覆盖仅在整个原始覆盖区（含嵌套 Git URL / ref / path）与快照证据完整一致时允许恢复，pubspec.yaml 原字节不改；不同覆盖或目标 pubspec_overrides.yaml 已有同名覆盖仍拒绝。原配置先保存为运行目录中的 `pubspec_overrides.yaml.before-import`；原来不存在时由清单记录创建状态。保留原 `pubspec.yaml`、锁文件、源导出目录和已解析依赖；不运行依赖脚本、不修改第三方源码、不写全局 Pub 缓存、不自动执行 `flutter pub get`。导入完成后根据终端提示手动获取依赖；SDK 与原生 CocoaPods / Gradle 依赖仍须由相应工具准备，导入不保证离线构建。

当前仅支持独立 Flutter 项目，Pub workspace 根和成员均暂不支持导入；不能可靠读取的 YAML、不同的既有覆盖、链接或不完整导出均停止。日志位于当前用户本地应用数据中的统一包 `logs/import-*.log`，运行时显示精确位置，地址凭据及敏感参数脱敏。

从 Windows 仓库根运行 `Tests/FlutterDependencyImporter.Tests.ps1` 验证路径识别、连续空回车重问、真实 stdin EOF 退出、确认取消、预览失败停止、精确 `YES`、参数传递与错误传播；`Tests/FlutterTools.Tests.ps1` 核对 release 的核心文件完整性，`Tests/FlutterFeatureSelection.Tests.ps1` 和 `Tests/FlutterSelectionProbe.cpp` 核对菜单与安装选择。`dart Tests/FlutterDependencyPubResolution.Tests.dart` 用临时导出和真实导入产物、独立空 `PUB_CACHE`，执行 `dart pub get --offline` 核对直接 / 传递依赖与原不冲突覆盖均指向本地路径；验收时仅将临时根声明改为纯 Dart consumer，保留生成配置和 vendor 原字节，不需要 Flutter SDK 或联网。测试只用临时夹具，Windows PowerShell 5.1、MSVC、Explorer 及真实 CMD 拖入仍需目标桌面验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

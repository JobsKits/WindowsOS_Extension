# 一键提取与导入 Flutter 依赖

[FlutterDependencyMigration.psm1](./FlutterDependencyMigration.psm1) 由统一菜单的 `export-all-dependencies` / `import-all-dependencies` 调用；依赖本包上级目录中的 Dart 引擎和已有健康的原生 Dart，优先项目 FVM。不能单独复制此文件夹作为完整工具包，应整体携带 `JobsFlutterTools`。

- 一键提取先说明私库范围。直接回车只提取可识别的私库候选；输入任意字符（包含空格）再回车，才进行全提取。Git、本地 path 和非公共源属于私库候选，不能据此证明仓库访问权限；缺少来源证据的原生缓存会列为缺口。
- 输出父目录可输入或拖入，回车为系统桌面。引擎成功后，回车打包 ZIP、非空不打包；ZIP 完成逐文件 SHA-256 核对后，回车保留提取目录、非空删除。只允许删除本次新建的直属产物；ZIP 损坏、源文件变化或链接会停止删除。
- 一键导入可选迁移产物、原始 Pub / Gradle 缓存，或包含这些目录的父目录。目录名称允许变化，由引擎检查内容；ZIP 先解压。空输入持续询问，输入结束或 Ctrl+C 取消。预检失败停止；只有精确大写 `YES` 才融合，执行前引擎再次校验。同名不同内容拒绝，保留原文件。
- 缓存目标从当前 `PUB_CACHE` / `GRADLE_USER_HOME` 或当前系统默认目录解析；不沿用原机绝对路径。已知认证配置、用户配置、init 脚本、运行锁和 daemon 数据不作为迁移载荷。
- 不下载依赖、不执行项目或包内脚本、不安装 SDK、不修改全局 Flutter/Java。迁移材料不保证完整离线构建；公共库、FVM/Flutter、Java、Android SDK、Apple 工具链、鸿蒙工具链和私库认证须按目标平台另行准备。
- 运行日志为系统临时目录中的 `JobsFlutterMigration-*.log`，来源地址脱敏。Windows 的 ZIP 使用 .NET 压缩流，包含隐藏文件，并检查实际解压数据；不会调用会跳过隐藏文件的通用压缩命令。

隔离验证入口：`pwsh -NoProfile -File ../../../Tests/FlutterDependencyMigration.Tests.ps1/FlutterDependencyMigration.Tests.ps1`。该测试覆盖终端选择、原始目录传递、冲突停止、真实 ZIP 校验和删除范围；来自 MacOS 上的 PowerShell 7 时，不代表 Windows PowerShell 5.1、Explorer 或真实用户缓存已经验收。

迁移快照保留工程声明和锁文件，可能包含私有地址或开发机路径；自行写在源码、声明中的敏感内容不能依靠缓存文件名过滤消除，跨人分享前应检查产物。导入使用预检计划指纹绑定本次源文件与目标状态，确认期间发生变化会停止。

仅一键文件迁移允许在项目 FVM Dart 不可用时复用已有健康的原生系统 `dart.exe`；系统 Flutter 的 `dart.bat` 只用于定位旁边已安装的 `cache/dart-sdk/bin/dart.exe`，不执行 shim，不下载或切换项目 SDK。普通 Pub 提取 / 导入保持原有项目 FVM 约束。

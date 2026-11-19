# SDK 下载前网络预检与当前任务选路

该模块由同目录上级 SDK 获取助手载入，不单独执行安装，不修改系统代理、注册表、Shell 或 Git 配置。

- 显式存储源、Pub 源和代理（包括空值）优先保留；SDK 选路不自动修改 Pub 源。
- AUTO 只对已确认官方公开 SDK 来源与标准公开命名空间比较官方／CFUG 同路径制品，以及当前已配置代理；未知 engine、用户 fork、非空 realm 和自定义 engine override 不向公共镜像探测，读取真实小 Range 的 TLS、DNS、首字节、吞吐和字节证据，不以 HEAD 或错误页当成功。
- 每候选最多 256 KiB、连接 2 秒、传输 6 秒，候选并行；当前任务按版本、engine、架构、源和代理配置缓存 300 秒，获取失败失效，实际下载失败的路线降权 120 秒，优先轮换其它仍在显式约束内的已验证候选，全部失败持续退避重测。
- 优先用官方相同对象样本或官方对象元数据（总长及 MD5／HTTP ETag）核验 CFUG。Google 完全不可达时，允许已授权 CFUG 精确目标路径的 Range、总长、ETag 与制品结构自证，并明确“官方摘要未取得”；不冒称官方 hash 核验。完整归档仍按已取得的可信发布 SHA 或对象 MD5 验证。
- Windows 原生 SDK 的 PowerShell／BITS 通道按实际 WinINET 代理和绕过规则比较来源；PAC 无法有界解析时保留原通道并明确未测速。不把另一条 curl 代理路线冒称已套用到 BITS。
- 下载诊断及来源、版本、路由理由均脱敏；测试只使用假传输与临时元数据，不接触用户 SDK 或真实会话。
- 下载重试统一按本次异常链识别取消、权限及其它确定错误；Windows PowerShell 5.1 在前置取消之后遇到新的传输错误，仍应进入可取消的退避重试，不沿用此前取消的分类。
- `precache --universal` 按当前 engine 的通用缓存、宿主工具与 Pub 配置检查就绪状态；健康缓存不强制联网，缺失时探测实际通用制品，不误用 Android 制品。对象元数据路径解析兼容 Windows PowerShell 5.1。

FVM 使用只读 `api context` 的生效 Git URL 和缓存位置，原始 JSON 不落盘／不写日志；支持时使用 `install --no-setup`，Git 与 Dart 自举分阶段。请求 channel 或 upgrade 时先用发布清单 `current_release` 解析所请求的新版本归档，并在相同子进程环境中预检原 Git 来源；不把已安装旧 SDK 的版本当升级目标。所有选择仅写入请求或子进程环境，取消后不会留下全局代理设置。

文本FVM启动器若通过PATH调用Flutter的`dart.bat`，会在FVM版本/API context/help首次元数据前单独准备该管理器实际SDK的Dart缓存；待安装项目SDK与管理器运行时分开。原生AOT FVM、固定独立Dart及健康缓存不强制调用PATH Flutter；取消时不会继续元数据查询。


<!-- JOBS_TERMINAL_STYLE_V1:BEGIN -->

> Windows 终端配色保护：支持完整颜色查询的交互控制台会先保存当前会话默认前景、背景与16色色表，再临时使用黑底白字和统一强调色；正常结束、业务失败及可捕获中断后恢复。用户运行中自行改动的颜色保留并提示，不修改用户主题、共享 Profile、注册表或全局策略。快照不包含进入前任意叠加的临时文字样式。非控制台、重定向、`NO_COLOR`、Sourcetree 及无法可靠保存／恢复颜色的环境保持原状态或降级为纯文本。

> 强制结束进程或终端崩溃无法保证自动恢复。恢复失败时保留并提示本轮 `%TEMP%\JobsTerminalStyle-<PID>-*.ps1` 恢复脚本，需在原控制台核对后运行；不要通过重置用户配置恢复。`-ExecutionPolicy Bypass` 如被入口使用，仅作用于本次子进程，不持久修改策略。

> 验证范围：已完成 PowerShell 语法、参数／退出与隔离生命周期核验；Windows 原生控制台的显示、按键与 `Ctrl+C` 实机验证尚未完成。

<!-- JOBS_TERMINAL_STYLE_V1:END -->

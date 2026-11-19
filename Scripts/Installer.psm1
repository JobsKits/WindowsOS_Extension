# Installer.psm1 | WindowsOS@Extension 组合选择面板
# Created by Jobs on 2026年10月18日，星期日.
# 面板内后台执行安装事务，实时显示逐项状态和可复制日志；预览、取消不部署。
Set-StrictMode -Version 2.0

# 十语言正文随模块分发，独立包无需访问源码仓库或在线翻译服务。
$script:PanelTranslations = @{}
$panelTextData = @'
{
  "永久删除（不进回收站）": ["永久刪除（不進資源回收筒）", "Permanently delete (skip Recycle Bin)"],
  "直接删除所选文件或文件夹；确认框左红确认、右蓝取消，默认取消，删除后无法从回收站恢复。": ["直接刪除所選檔案或資料夾；確認框左紅確認、右藍取消，預設取消，刪除後無法從資源回收筒復原。", "Directly delete selected files or folders; confirm with the red left button or cancel with the blue right button. Cancellation is the default; deleted items cannot be restored from the Recycle Bin."],
  "🫥 隐藏 / 显示所选项目": ["🫥 隱藏 / 顯示所選項目", "🫥 Hide / show selected items"],
  "设置所选文件或文件夹的隐藏属性，支持多选；不递归、不改名、不改变全局显示偏好。": ["設定所選檔案或資料夾的隱藏屬性，支援多選；不遞迴、不改名、不改變全域顯示偏好。", "Set the Hidden attribute of selected files or folders, including multiple selections; do not recurse, rename, or change global visibility preferences."],
  "关闭管理面板": ["關閉管理面板", "Close management panel"],
  "退到系统托盘": ["退到系統匣", "Minimize to tray"],
  "完全退出": ["完全結束", "Exit completely"],
  "保留窗口": ["保留視窗", "Keep window open"],
  "面板空闲。请选择退到系统托盘继续保留窗口，或完全退出。": ["面板閒置。請選擇退到系統匣保留視窗，或完全結束。", "The manager is idle. Keep it in the system tray, or exit completely."],
  "显示管理面板": ["顯示管理面板", "Show management panel"],
  "当前状态": ["目前狀態", "Current status"],
  "任务进行中，暂时不能完全退出；可恢复窗口查看日志。": ["工作進行中，暫時無法完全結束；可恢復視窗查看日誌。", "A task is running. Exit is unavailable; restore the window to view logs."],
  "无法显示系统托盘，窗口保持打开。": ["無法顯示系統匣，視窗保持開啟。", "The system tray is unavailable. The window will remain open."],
  "💽 磁盘剩余空间": ["💽 磁碟剩餘空間","💽 Disk free space"],
  "显示本机磁盘总剩余 / 总容量和两位小数百分比；点击在独立终端选择清理，确认后才执行。": ["顯示本機磁碟總剩餘 / 總容量和兩位小數百分比；點擊在獨立終端選擇清理，確認後才執行。","Show total local disk free / capacity and a two-decimal percentage. Click to choose cleanup in a separate terminal; changes require confirmation."],
  "🔗 创建脚本快捷入口…": [
    "🔗 建立指令稿快捷入口…",
    "🔗 Create script launcher…"
  ],
  "创建脚本快捷入口…": [
    "建立指令稿快捷入口…",
    "Create script launcher…"
  ],
  "对同名.cmd/.bat/.ps1脚本文件夹，在旁边创建相对路径转发入口；不执行或改写原脚本。": [
    "對同名.cmd/.bat/.ps1指令稿資料夾，在旁邊建立相對路徑轉發入口；不執行或改寫原指令稿。",
    "Create a relative launcher beside a same-name .cmd/.bat/.ps1 script folder; do not run or modify the source script."
  ],
  "自定义Explorer右键菜单" : [
    "自訂Explorer右鍵選單",
    "Custom Explorer context menu"
  ],
  "Jobs Windows · 自定义Explorer右键菜单" : [
    "Jobs Windows · 自訂Explorer右鍵選單",
    "Jobs Windows · Custom Explorer context menu"
  ],
  "单个普通文件在新终端显示 SHA-256，并自动复制纯摘要；不修改或执行文件。" : [
    "單個普通檔案在新終端顯示 SHA-256，並自動複製純摘要；不修改或執行檔案。",
    "Show a regular file's SHA-256 in a new terminal and copy the digest; do not modify or execute the file."
  ],
  "（仅预览）" : [
    "（僅預覽）",
    " (preview)"
  ],
  "⏪ Git 提交回退" : [
    "⏪ Git 提交回退",
    "⏪ Roll back Git commits"
  ],
  "▶️ 从终端运行 Flutter 项目" : [
    "▶️ 從終端運行 Flutter 項目",
    "▶️ Run Flutter project in terminal"
  ],
  "☕ 安装/切换Java SDK" : [
    "☕ 安裝/切換Java SDK",
    "☕ Install / switch Java SDK"
  ],
  "♻️ Flutter清理维护工具" : [
    "♻️ Flutter清理維護工具",
    "♻️ Flutter cleanup and maintenance"
  ],
  "⚙️ Flutter 自动化生产代码" : [
    "⚙️ Flutter 自動化生產代碼",
    "⚙️ Generate Flutter code"
  ],
  "⚙️ Flutter自动化生产代码" : [
    "⚙️ Flutter自動化生產代碼",
    "⚙️ Generate Flutter code"
  ],
  "✅ 安装成功" : [
    "✅ 安裝成功",
    "✅ Installed"
  ],
  "⬇️ 拉取 Git 到最新" : [
    "⬇️ 拉取 Git 到最新",
    "⬇️ Pull latest Git changes"
  ],
  "🌈 新建 Harmony 模拟器" : [
    "🌈 新建 Harmony 模擬器",
    "🌈 Create Harmony emulator"
  ],
  "🌐 打开 Git 远程地址" : [
    "🌐 打開 Git 遠程地址",
    "🌐 Open Git remote URL"
  ],
  "🌐 拉取 Web 工程依赖" : [
    "🌐 拉取 Web 工程依賴",
    "🌐 Fetch Web project dependencies"
  ],
  "🌳 用 Sourcetree 打开" : [
    "🌳 用 Sourcetree 打開",
    "🌳 Open in Sourcetree"
  ],
  "🏥 Flutter 项目体检" : [
    "🏥 Flutter 項目體檢",
    "🏥 Flutter project diagnostics"
  ],
  "🏥 Flutter项目体检" : [
    "🏥 Flutter項目體檢",
    "🏥 Flutter diagnostics"
  ],
  "🏷️ 修复 Flutter 插件 namespace" : [
    "🏷️ 修復 Flutter 插件 namespace",
    "🏷️ Repair Flutter plugin namespaces"
  ],
  "👁️ 显示 / 隐藏文件" : [
    "👁️ 顯示 / 隱藏文件",
    "👁️ Show / hide hidden files"
  ],
  "💓 OpenHarmony Flutter 环境体检" : [
    "💓 OpenHarmony Flutter 環境體檢",
    "💓 OpenHarmony Flutter diagnostics"
  ],
  "💠 用 Visual Studio 打开项目" : [
    "💠 用 Visual Studio 打開項目",
    "💠 Open project in Visual Studio"
  ],
  "💻 用终端打开" : [
    "💻 用終端打開",
    "💻 Open in terminal"
  ],
  "📄 用终端查看文件内容" : [
    "📄 用終端查看文件內容",
    "📄 View file in terminal"
  ],
  "📋 复制绝对路径" : [
    "📋 複製絕對路徑",
    "📋 Copy absolute path"
  ],
  "📚 下载Gradled分发与构建插件" : [
    "📚 下載Gradled分發與構建插件",
    "📚 Download Gradle distributions and build plugins"
  ],
  "📝 用 VSCode 打开项目" : [
    "📝 用 VSCode 打開項目",
    "📝 Open project in VSCode"
  ],
  "📡 配置 Git 动态代理" : [
    "📡 配置 Git 動態代理",
    "📡 Configure Git dynamic proxy"
  ],
  "📤 导入 Flutter Pub 依赖" : [
    "📤 導入 Flutter Pub 依賴",
    "📤 Import Flutter Pub dependencies"
  ],
  "📤 导入 Flutter 平台资源" : [
    "📤 導入 Flutter 平台資源",
    "📤 Import Flutter platform assets"
  ],
  "📤 导入 Gradle 分发与依赖缓存" : [
    "📤 導入 Gradle 分發與依賴緩存",
    "📤 Import Gradle distributions and dependency caches"
  ],
  "📤 导入 OpenHarmony 依赖" : [
    "📤 導入 OpenHarmony 依賴",
    "📤 Import OpenHarmony dependencies"
  ],
  "📤 导入 Web 依赖" : [
    "📤 導入 Web 依賴",
    "📤 Import Web dependencies"
  ],
  "📤 导入 原生构建缓存" : [
    "📤 導入 原生構建緩存",
    "📤 Import native build caches"
  ],
  "📤 导入Flutter项目工程依赖" : [
    "📤 導入Flutter項目工程依賴",
    "📤 Import Flutter project dependencies"
  ],
  "📤 空白 Commit 并 Push" : [
    "📤 空白 Commit 並 Push",
    "📤 Create empty commit and push"
  ],
  "📥 Flutter 安装依赖（pub get）" : [
    "📥 Flutter 安裝依賴（pub get）",
    "📥 Install Flutter dependencies (pub get)"
  ],
  "📥 导入Flutter项目工程私库依赖" : [
    "📥 導入Flutter項目工程私庫依賴",
    "📥 Import private Flutter project dependencies"
  ],
  "📥 拉取 Flutter Pub 依赖" : [
    "📥 拉取 Flutter Pub 依賴",
    "📥 Fetch Flutter Pub dependencies"
  ],
  "📥 拉取Flutter项目工程相关依赖" : [
    "📥 拉取Flutter項目工程相關依賴",
    "📥 Fetch Flutter project dependencies"
  ],
  "📦 Flutter打包" : [
    "📦 Flutter打包",
    "📦 Package Flutter project"
  ],
  "📦 打包鸿蒙（HAP + APP）" : [
    "📦 打包鴻蒙（HAP + APP）",
    "📦 Package HarmonyOS (HAP + APP)"
  ],
  "📱 新建 Android 模拟器" : [
    "📱 新建 Android 模擬器",
    "📱 Create Android emulator"
  ],
  "🔀 Flutter SDK 安装/切换（FVM）" : [
    "🔀 Flutter SDK 安裝/切換（FVM）",
    "🔀 Install / switch Flutter SDK (FVM)"
  ],
  "🔀 安装/切换Flutter SDK" : [
    "🔀 安裝/切換Flutter SDK",
    "🔀 Install / switch Flutter SDK"
  ],
  "🔀 安装/切换Flutter运行环境" : [
    "🔀 安裝/切換Flutter運行環境",
    "🔀 Install / switch Flutter environments"
  ],
  "🔎 查看当前 Flutter SDK 版本" : [
    "🔎 查看當前 Flutter SDK 版本",
    "🔎 Show current Flutter SDK version"
  ],
  "🔎 查看当前Flutter项目工程的SDK版本" : [
    "🔎 查看當前Flutter項目工程的SDK版本",
    "🔎 Show current Flutter project's SDK version"
  ],
  "🔐 提取Flutter项目工程私库依赖" : [
    "🔐 提取Flutter項目工程私庫依賴",
    "🔐 Export private Flutter project dependencies"
  ],
  "🔎 查看文件指纹 Hash（SHA-256）" : [
    "🔎 查看檔案指紋 Hash（SHA-256）",
    "🔎 Show file fingerprint Hash (SHA-256)"
  ],
  "➕ 授予执行权限" : [
    "➕ 授予執行權限",
    "➕ Grant execute permission"
  ],
  "➖ 移除执行权限" : [
    "➖ 移除執行權限",
    "➖ Remove execute permission"
  ],
  "🔒 运行授权" : [
    "🔒 運行授權",
    "🔒 Grant execute permission"
  ],
  "🔓 解除运行授权" : [
    "🔓 解除運行授權",
    "🔓 Remove execute permission"
  ],
  "🔗 复制 Git 远程地址" : [
    "🔗 複製 Git 遠程地址",
    "🔗 Copy Git remote URL"
  ],
  "🔧 Flutter 项目修复" : [
    "🔧 Flutter 項目修復",
    "🔧 Flutter repairs"
  ],
  "🕊️ 安装/切换Flutter@OpenHarmony SDK" : [
    "🕊️ 安裝/切換Flutter@OpenHarmony SDK",
    "🕊️ Install / switch Flutter@OpenHarmony SDK"
  ],
  "🕊️ 拉取 OpenHarmony 依赖" : [
    "🕊️ 拉取 OpenHarmony 依賴",
    "🕊️ Fetch OpenHarmony dependencies"
  ],
  "🗃️ 下载Flutter平台资源" : [
    "🗃️ 下載Flutter平台資源",
    "🗃️ Download Flutter platform assets"
  ],
  "🗺️ 更新代码地图（.codegraph）" : [
    "🗺️ 更新代碼地圖（.codegraph）",
    "🗺️ Update code map (.codegraph)"
  ],
  "🤖 拉取 Android 原生依赖" : [
    "🤖 拉取 Android 原生依賴",
    "🤖 Fetch Android native dependencies"
  ],
  "🦋 Flutter 开发辅助" : [
    "🦋 Flutter 開發輔助",
    "🦋 Flutter development"
  ],
  "🦋 Flutter开发相关辅助工具" : [
    "🦋 Flutter開發相關輔助工具",
    "🦋 Flutter development tools"
  ],
  "🧑‍⚕️ 原生Flutter项目体检" : [
    "🧑‍⚕️ 原生Flutter項目體檢",
    "🧑‍⚕️ Native Flutter diagnostics"
  ],
  "🧩 提取 Flutter Pub 依赖" : [
    "🧩 提取 Flutter Pub 依賴",
    "🧩 Export Flutter Pub dependencies"
  ],
  "🧩 提取 Flutter 平台资源" : [
    "🧩 提取 Flutter 平台資源",
    "🧩 Export Flutter platform assets"
  ],
  "🧩 提取 Flutter 第三方依赖" : [
    "🧩 提取 Flutter 第三方依賴",
    "🧩 Export Flutter third-party dependencies"
  ],
  "🧩 提取 Gradle 分发与依赖缓存" : [
    "🧩 提取 Gradle 分發與依賴緩存",
    "🧩 Export Gradle distributions and dependency caches"
  ],
  "🧩 提取 OpenHarmony 依赖" : [
    "🧩 提取 OpenHarmony 依賴",
    "🧩 Export OpenHarmony dependencies"
  ],
  "🧩 提取 Web 依赖" : [
    "🧩 提取 Web 依賴",
    "🧩 Export Web dependencies"
  ],
  "🧩 提取 原生构建缓存" : [
    "🧩 提取 原生構建緩存",
    "🧩 Export native build caches"
  ],
  "🧩 提取Flutter项目工程依赖" : [
    "🧩 提取Flutter項目工程依賴",
    "🧩 Export Flutter project dependencies"
  ],
  "🧩 文件分卷合并 / ✂️ 拆分" : [
    "🧩 文件分卷合併 / ✂️ 拆分",
    "🧩 Merge file volumes / ✂️ Split file"
  ],
  "🧭 用 Android Studio 打开项目" : [
    "🧭 用 Android Studio 打開項目",
    "🧭 Open project in Android Studio"
  ],
  "🧯 清理构建产物" : [
    "🧯 清理構建產物",
    "🧯 Clean build output"
  ],
  "🧰 Harmony 模拟器检测与修复" : [
    "🧰 Harmony 模擬器檢測與修復",
    "🧰 Diagnose and repair Harmony emulator"
  ],
  "🧱 Flutter 资源与构建依赖" : [
    "🧱 Flutter 資源與構建依賴",
    "🧱 Flutter assets and build dependencies"
  ],
  "🧱 准备原生库与构建依赖（组合操作）" : [
    "🧱 準備原生庫與構建依賴（組合操作）",
    "🧱 Prepare native libraries and build dependencies (combined)"
  ],
  "🧹 清除构建产物" : [
    "🧹 清除構建產物",
    "🧹 Clean build output"
  ],
  "🩹 修复 Android SDK / platforms 缺失" : [
    "🩹 修復 Android SDK / platforms 缺失",
    "🩹 Repair missing Android SDK / platforms"
  ],
  "🩺 Android 模拟器检测与修复" : [
    "🩺 Android 模擬器檢測與修復",
    "🩺 Diagnose and repair Android emulator"
  ],
  "🚀 一键配置 Flutter 项目" : [
    "🚀 一鍵配置 Flutter 項目",
    "🚀 Set up Flutter project"
  ],
  "🚚 一键导入 Flutter 依赖" : [
    "🚚 一鍵導入 Flutter 依賴",
    "🚚 Import all Flutter dependencies"
  ],
  "🚚 一键提取 Flutter 依赖" : [
    "🚚 一鍵提取 Flutter 依賴",
    "🚚 Export all Flutter dependencies"
  ],
  "Jobs Windows · 卸载资源管理器扩展" : [
    "Jobs Windows · 卸載資源管理器擴展",
    "Jobs Windows · Uninstall Explorer extensions"
  ],
  "Jobs Windows · 安装资源管理器扩展" : [
    "Jobs Windows · 安裝資源管理器擴展",
    "Jobs Windows · Install Explorer extensions"
  ],
  "Jobs Windows · 管理资源管理器扩展" : [
    "Jobs Windows · 管理資源管理器擴展",
    "Jobs Windows · Manage Explorer extensions"
  ],
  "Jobs Windows · 配置资源管理器扩展" : [
    "Jobs Windows · 配置資源管理器擴展",
    "Jobs Windows · Configure Explorer extensions"
  ],
  "上下拖动分隔条调节日志高度" : [
    "上下拖動分隔條調節日誌高度",
    "Drag the divider vertically to resize the log"
  ],
  "上下拖动调节日志高度" : [
    "上下拖動調節日誌高度",
    "Drag vertically to resize the log"
  ],
  "严格校验 Flutter 项目，在终端体检工具链并使用 fzf 选择 Flutter SDK 版本。" : [
    "嚴格校驗 Flutter 項目，在終端體檢工具鏈並使用 fzf 選擇 Flutter SDK 版本。",
    "Validate the Flutter project, diagnose the toolchain in terminal, and choose a Flutter SDK version with fzf."
  ],
  "严格校验 Flutter 项目，在终端只读显示当前实际使用的 Flutter SDK 版本（FVM 项目 SDK 或系统 SDK），并与 .fvmrc 和 pubspec environment 约束核对。" : [
    "嚴格校驗 Flutter 項目，在終端只讀顯示當前實際使用的 Flutter SDK 版本（FVM 項目 SDK 或系統 SDK），並與 .fvmrc 和 pubspec environment 約束核對。",
    "Validate the Flutter project, then show the active SDK version (project FVM or system SDK) in terminal and compare it with .fvmrc and pubspec constraints."
  ],
  "主题" : [
    "主題",
    "Theme"
  ],
  "仅 Flutter 根目录显示；CMD 内通过 fzf 选择 Android / iOS / HarmonyOS，支持 APK / AAB 与 HAP / APP。iOS 提示使用 macOS 与 Xcode。" : [
    "僅 Flutter 根目錄顯示；CMD 內通過 fzf 選擇 Android / iOS / HarmonyOS，支持 APK / AAB 與 HAP / APP。iOS 提示使用 macOS 與 Xcode。",
    "Flutter roots only. Choose Android / iOS / HarmonyOS with fzf in CMD. Supports APK / AAB and HAP / APP. iOS requires MacOS and Xcode."
  ],
  "仅 Flutter 根目录显示；在 CMD 选择设备、查看日志，关闭窗口后继续后台运行。" : [
    "僅 Flutter 根目錄顯示；在 CMD 選擇設備、查看日誌，關閉窗口後繼續後台運行。",
    "Flutter roots only. Choose a device and view logs in CMD; the app continues in the background after the window closes."
  ],
  "仅 Flutter 根目录显示；终端只读执行版本与 doctor 诊断，不获取依赖、不清理、不升级工具。" : [
    "僅 Flutter 根目錄顯示；終端只讀執行版本與 doctor 診斷，不獲取依賴、不清理、不升級工具。",
    "Flutter roots only. Read-only version and doctor diagnostics in terminal; no dependency fetching, cleanup, or tool upgrades."
  ],
  "仅 Flutter 根目录显示；预览已配置生成器，确认后获取依赖并生成代码，删除冲突必须另行明确启用。" : [
    "僅 Flutter 根目錄顯示；預覽已配置生成器，確認後獲取依賴並生成代碼，刪除衝突必須另行明確啓用。",
    "Flutter roots only. Preview configured generators, then fetch dependencies and generate code after confirmation. Deleting conflicts requires separate opt-in."
  ],
  "仅 Git 工作树文件夹显示；识别子仓库，soft 保留索引及工作区，hard 必须精确 YES。" : [
    "僅 Git 工作樹文件夾顯示；識別子倉庫，soft 保留索引及工作區，hard 必須精確 YES。",
    "Git worktree folders only. Detect nested repositories. Soft mode preserves the index and worktree; hard mode requires exact YES confirmation."
  ],
  "仅 x64 Windows 系统桌面空白显示；缺工具从 SDL 免登录镜像补齐，缺系统镜像由官方 Emulator 下载；回车选稳定版手机、确认许可、创建唯一实例并启动。" : [
    "僅 x64 Windows 系統桌面空白顯示；缺工具從 SDL 免登錄鏡像補齊，缺系統鏡像由官方 Emulator 下載；回車選穩定版手機、確認許可、創建唯一實例並啓動。",
    "Desktop background on x64 Windows only. Missing tools come from the SDL mirror; missing system images come from the official Emulator. Enter selects a stable phone image; confirm its license to create and start a unique instance."
  ],
  "仅处理本包对应子功能；未选的其它功能在卸载时保留。" : [
    "僅處理本包對應子功能；未選的其它功能在卸載時保留。",
    "Manage only this package's actions. Unselected actions remain when uninstalling."
  ],
  "仅桌面空白；交互配置系统代理优先、失败回退直连的用户级 Git 入口。" : [
    "僅桌面空白；交互配置系統代理優先、失敗回退直連的用戶級 Git 入口。",
    "Desktop background only. Configure user-level Git to prefer the system proxy and fall back to a direct connection."
  ],
  "仅系统桌面空白显示；CMD 体检 SDK，选择机型与系统镜像，创建或启动 Android AVD。" : [
    "僅系統桌面空白顯示；CMD 體檢 SDK，選擇機型與系統鏡像，創建或啓動 Android AVD。",
    "Desktop background only. Diagnose the SDK in CMD, choose a device and system image, then create or start an Android AVD."
  ],
  "仅系统桌面空白显示；检查已有 DevEco Emulator 与实例，按选择启动或确认后无损重启；不清数据。" : [
    "僅系統桌面空白顯示；檢查已有 DevEco Emulator 與實例，按選擇啓動或確認後無損重啓；不清數據。",
    "Desktop background only. Check existing DevEco Emulator instances, then start one or confirm a nondestructive restart. Data is preserved."
  ],
  "仅系统桌面空白显示；检查模拟器安装位置与 /data，可选缓存重置、精确卸载、完整备份 AVD 并冷启动复测。" : [
    "僅系統桌面空白顯示；檢查模擬器安裝位置與 /data，可選緩存重置、精確卸載、完整備份 AVD 並冷啓動復測。",
    "Desktop background only. Check emulator location and /data; optionally reset caches, precisely uninstall, back up the AVD, and retest with a cold boot."
  ],
  "仅系统桌面空白显示下一动作；点击切换当前用户 Explorer 隐藏文件显示，不改受保护系统文件设置。" : [
    "僅系統桌面空白顯示下一動作；點擊切換當前用戶 Explorer 隱藏文件顯示，不改受保護系統文件設置。",
    "Show the next action on the desktop background. Toggle hidden files for the current user's Explorer without changing protected-system-file settings."
  ],
  "仅非空的原生 Android 或有效 Flutter（官方 / 鸿蒙）项目根目录可见，点击前复核。" : [
    "僅非空的原生 Android 或有效 Flutter（官方 / 鴻蒙）項目根目錄可見，點擊前復核。",
    "Visible only for nonempty native Android or valid Flutter (official / HarmonyOS) project roots. Validated again before opening."
  ],
  "仅预览：选择已显示在下方日志，未执行安装或卸载。" : [
    "僅預覽：選擇已顯示在下方日誌，未執行安裝或卸載。",
    "Preview: the selection is shown in the log. No installation or uninstallation was performed."
  ],
  "仅预览功能选择；确认后在底部显示选择，不安装、不卸载、不写入状态或注册表。" : [
    "僅預覽功能選擇；確認後在底部顯示選擇，不安裝、不卸載、不寫入狀態或註冊表。",
    "Preview only. Confirming displays the selection in the log without installing, uninstalling, or writing state or registry entries."
  ],
  "从已部署副本打开时使用当前路线；切换部署位置请从源码目录的管理入口操作。默认模式在当前用户 LocalAppData 独立运行；临时模式登记本包 work 下的运行版本，移动源码目录后失效。" : [
    "從已部署副本打開時使用當前路線；切換部署位置請從源碼目錄的管理入口操作。默認模式在當前用戶 LocalAppData 獨立運行；臨時模式登記本包 work 下的運行版本，移動源碼目錄後失效。",
    "Deployed copies use their bound location. To change it, open the manager from the source directory. Default installations run in the current user's LocalAppData; local builds run under this package's work directory and stop working if it moves."
  ],
  "优先 Windows Terminal，否则系统 PowerShell。" : [
    "優先 Windows Terminal，否則系統 PowerShell。",
    "Prefer Windows Terminal; otherwise use system PowerShell."
  ],
  "保存偏好失败：" : [
    "保存偏好失敗：",
    "Could not save preferences: "
  ],
  "保存配置" : [
    "保存配置",
    "Save settings"
  ],
  "保护本地改动，冲突时选择恢复、放弃改动或提交后重试。" : [
    "保護本地改動，衝突時選擇恢復、放棄改動或提交後重試。",
    "Protect local changes. On conflict, choose to restore, discard changes, or commit and retry."
  ],
  "停止安装" : [
    "停止安裝",
    "Stop installation"
  ],
  "全不选" : [
    "全不選",
    "Clear all"
  ],
  "全选" : [
    "全選",
    "Select all"
  ],
  "全部处理完成；可选择复制日志，或关闭面板。" : [
    "全部處理完成；可選擇複製日誌，或關閉面板。",
    "All operations completed. Copy the log or close the panel."
  ],
  "关闭" : [
    "關閉",
    "Close"
  ],
  "其它右键功能" : [
    "其它右鍵功能",
    "Other context-menu features"
  ],
  "创建或同步当前目录的代码地图。" : [
    "創建或同步當前目錄的代碼地圖。",
    "Create or synchronize the code map for the current directory."
  ],
  "功能与日志分隔条" : [
    "功能與日誌分隔條",
    "Feature and log divider"
  ],
  "勾选功能后确认；未选项保留。悬停可查看当前安装状态。" : [
    "勾選功能後確認；未選項保留。懸停可查看當前安裝狀態。",
    "Select features, then confirm. Unselected features remain. Hover for installation details."
  ],
  "勾选安装，取消勾选卸载；全不选后保存将关闭全部已安装功能。" : [
    "勾選安裝，取消勾選卸載；全不選後保存將關閉全部已安裝功能。",
    "Checked features are installed; unchecked ones are uninstalled. Saving an empty selection disables all installed features."
  ],
  "勾选需要安装的子功能；已启用的兄弟动作与其它未选功能保留。" : [
    "勾選需要安裝的子功能；已啓用的兄弟動作與其它未選功能保留。",
    "Select features to install. Enabled sibling actions and other unselected features remain."
  ],
  "卸载" : [
    "卸載",
    "Uninstall"
  ],
  "卸载总用时" : [
    "卸載總用時",
    "Total uninstall time"
  ],
  "卸载所选" : [
    "卸載所選",
    "Uninstall selected"
  ],
  "卸载所选功能" : [
    "卸載所選功能",
    "Uninstall selected features"
  ],
  "卸载用时" : [
    "卸載用時",
    "Uninstall time"
  ],
  "取消" : [
    "取消",
    "Cancel"
  ],
  "只卸载勾选的已安装功能；未勾选项、日志、备份和工具依赖保留。" : [
    "只卸載勾選的已安裝功能；未勾選項、日誌、備份和工具依賴保留。",
    "Uninstall only selected installed features. Other features, logs, backups and tools remain."
  ],
  "只对一个普通 NTFS 文件修改当前用户 ExecuteFile ACL；确认后执行，不启动目标，不改全局策略。" : [
    "只對一個普通 NTFS 文件修改當前用戶 ExecuteFile ACL；確認後執行，不啓動目標，不改全局策略。",
    "Change only the current user's ExecuteFile ACL for a single regular NTFS file after confirmation. Does not launch the file or change global policy."
  ],
  "只查看单个普通文件；超过 1 MiB 或疑似二进制时终端输入 YES 才继续。" : [
    "只查看單個普通文件；超過 1 MiB 或疑似二進制時終端輸入 YES 才繼續。",
    "View a single regular file. Files over 1 MiB or suspected binary files require YES in the terminal."
  ],
  "只清理所选包专用编译工作区；保留已安装 DLL、运行脚本、配置和注册表。" : [
    "只清理所選包專用編譯工作區；保留已安裝 DLL、運行腳本、配置和註冊表。",
    "Clean only the selected packages' build workspaces. Installed DLLs, scripts, settings and registry entries remain."
  ],
  "复制" : [
    "複製",
    "Copy"
  ],
  "复制全部日志" : [
    "複製全部日誌",
    "Copy full log"
  ],
  "复制当前分支对应的远端原始地址。" : [
    "複製當前分支對應的遠端原始地址。",
    "Copy the original remote URL for the current branch."
  ],
  "复制文件或文件夹的绝对路径。" : [
    "複製文件或文件夾的絕對路徑。",
    "Copy the absolute path of a file or folder."
  ],
  "复制日志失败：" : [
    "複製日誌失敗：",
    "Could not copy the log: "
  ],
  "失败，见日志" : [
    "失敗，見日誌",
    "Failed — open log"
  ],
  "安装" : [
    "安裝",
    "Install"
  ],
  "安装 / 更新" : [
    "安裝 / 更新",
    "Install / update"
  ],
  "安装 / 更新所选功能" : [
    "安裝 / 更新所選功能",
    "Install / update selected features"
  ],
  "安装总用时" : [
    "安裝總用時",
    "Total install time"
  ],
  "安装成功后清除此轮构建产物" : [
    "安裝成功後清除此輪構建產物",
    "Clean this build after successful installation"
  ],
  "安装用时" : [
    "安裝用時",
    "Install time"
  ],
  "完整多选同组分卷才显示合并，单个普通文件显示拆分；始终保留原件。" : [
    "完整多選同組分卷才顯示合併，單個普通文件顯示拆分；始終保留原件。",
    "Merge appears for a complete selected volume set; split appears for one regular file. Originals are always preserved."
  ],
  "实时日志（拖动上方分隔条调节高度）" : [
    "實時日誌（拖動上方分隔條調節高度）",
    "Live log (drag the divider to resize)"
  ],
  "已停止安装；当前包事务已结束，未开始项目显示未执行。" : [
    "已停止安裝；當前包事務已結束，未開始項目顯示未執行。",
    "Installation stopped after the current package transaction. Unstarted items are marked Not run."
  ],
  "已安装" : [
    "已安裝",
    "Installed"
  ],
  "已完成" : [
    "已完成",
    "Completed"
  ],
  "已请求停止安装；等待当前包事务结束，后续项目不再执行。" : [
    "已請求停止安裝；等待當前包事務結束，後續項目不再執行。",
    "Stop requested. Waiting for the current package transaction; later items will not run."
  ],
  "已选 {0} / {1}" : [
    "已選 {0} / {1}",
    "Selected {0} / {1}"
  ],
  "已选 {0} / {1} 项；关闭或取消窗口不执行操作。" : [
    "已選 {0} / {1} 項；關閉或取消窗口不執行操作。",
    "Selected {0} / {1}. Closing or cancelling makes no changes."
  ],
  "悬停查看功能说明；Windows 11：右键 → 显示更多选项。" : [
    "懸停查看功能說明；Windows 11：右鍵 → 顯示更多選項。",
    "Hover for feature details. Windows 11: right-click → Show more options."
  ],
  "打开完整日志失败：" : [
    "打開完整日誌失敗：",
    "Could not open the full log: "
  ],
  "打开当前 Git 工作树对应的仓库网页。" : [
    "打開當前 Git 工作樹對應的倉庫網頁。",
    "Open the repository website for the current Git worktree."
  ],
  "打开当前层级解决方案或项目。" : [
    "打開當前層級解決方案或項目。",
    "Open the solution or project at the current directory level."
  ],
  "按项目锁定清单提取所有已解析的第三方 Pub 源码与许可证，输出目录回车默认桌面。" : [
    "按項目鎖定清單提取所有已解析的第三方 Pub 源碼與許可證，輸出目錄回車默認桌面。",
    "Export resolved third-party Pub sources and licenses from the project lockfile. Press Enter to use the desktop as output."
  ],
  "操作正在执行，请等待事务完成后关闭；下方日志可随时复制。" : [
    "操作正在執行，請等待事務完成後關閉；下方日誌可隨時複製。",
    "An operation is running. Wait for the transaction to finish before closing. Logs can be copied at any time."
  ],
  "无法建立操作计划：" : [
    "無法建立操作計劃：",
    "Could not build the operation plan: "
  ],
  "无法开始执行：" : [
    "無法開始執行：",
    "Could not start the operation: "
  ],
  "日志：" : [
    "日誌：",
    "Log: "
  ],
  "🈶 修复 Flutter 项目中文路径" : [
    "🈶 修復 Flutter 項目中文路徑",
    "🈶 Repair Chinese paths in Flutter project"
  ],
  "未安装，无需卸载" : [
    "未安裝，無需解除安裝",
    "Not installed; nothing to uninstall"
  ],
  "未安装" : [
    "未安裝",
    "Not installed"
  ],
  "未执行" : [
    "未執行",
    "Not run"
  ],
  "本功能" : [
    "本功能",
    "This feature"
  ],
  "本地临时构建目录（移走或清理后失效）" : [
    "本地臨時構建目錄（移走或清理後失效）",
    "Local build directory (moving or cleaning it disables the menu)"
  ],
  "校验分支、暂存区和上游后确认推送。" : [
    "校驗分支、暫存區和上游後確認推送。",
    "Validate the branch, staging area and upstream, then confirm the push."
  ],
  "校验当前 Flutter 工程后获取依赖。" : [
    "校驗當前 Flutter 工程後獲取依賴。",
    "Validate the Flutter project, then fetch dependencies."
  ],
  "正在卸载…" : [
    "正在卸載…",
    "Uninstalling…"
  ],
  "正在安装 / 更新…" : [
    "正在安裝 / 更新…",
    "Installing / updating…"
  ],
  "正在清理…" : [
    "正在清理…",
    "Cleaning…"
  ],
  "此入口已移除；只保留旧安装卸载，不能重新安装。" : [
    "此入口已移除；只保留舊安裝卸載，不能重新安裝。",
    "This entry has been removed. Existing installations can be uninstalled but cannot be reinstalled."
  ],
  "没有需要处理的功能；" : [
    "沒有需要處理的功能；",
    "No features require processing; "
  ],
  "没有需要处理的功能；未更改任何配置。" : [
    "沒有需要處理的功能；未更改任何配置。",
    "No features require processing. No settings were changed."
  ],
  "清理总用时" : [
    "清理總用時",
    "Total cleanup time"
  ],
  "清理用时" : [
    "清理用時",
    "Cleanup time"
  ],
  "点击在新 PowerShell 窗口读取本次完整会话日志；当前任务继续运行。" : [
    "點擊在新 PowerShell 窗口讀取本次完整會話日誌；當前任務繼續運行。",
    "Click to read the full session log in a new PowerShell window. The current task continues."
  ],
  "白天" : [
    "白天",
    "Light"
  ],
  "等待中" : [
    "等待中",
    "Pending"
  ],
  "等待停止…" : [
    "等待停止…",
    "Waiting to stop…"
  ],
  "统一固定顺序的 Flutter 开发辅助、环境体检、修复与维护菜单；常规工具使用项目 FVM，环境配置支持 FVM/系统 Flutter 与 jEnv/系统 Java。" : [
    "統一固定順序的 Flutter 開發輔助、環境體檢、修復與維護菜單；常規工具使用項目 FVM，環境配置支持 FVM/系統 Flutter 與 jEnv/系統 Java。",
    "Ordered Flutter development, diagnostics, repair and maintenance tools. Regular actions use project FVM; environment setup supports FVM / system Flutter and jEnv / system Java."
  ],
  "自动滚动" : [
    "自動滾動",
    "Auto-scroll"
  ],
  "识别当前 Flutter / Android 工程并预览清理范围；Windows 不提供 iOS 清理。" : [
    "識別當前 Flutter / Android 工程並預覽清理範圍；Windows 不提供 iOS 清理。",
    "Detect the Flutter / Android project and preview cleanup scope. iOS cleanup is unavailable on Windows."
  ],
  "语言" : [
    "語言",
    "Language"
  ],
  "读取偏好失败：" : [
    "讀取偏好失敗：",
    "Could not read preferences: "
  ],
  "读取日志失败：" : [
    "讀取日誌失敗：",
    "Could not read the log: "
  ],
  "资源管理器右键扩展 · " : [
    "資源管理器右鍵擴展 · ",
    "Explorer context-menu extensions · "
  ],
  "资源管理器扩展 · 管理" : [
    "資源管理器擴展 · 管理",
    "Explorer extensions · Manage"
  ],
  "跟随系统" : [
    "跟隨系統",
    "Follow system"
  ],
  "返回选择" : [
    "返回選擇",
    "Return selection"
  ],
  "退出码：" : [
    "退出碼：",
    "Exit code: "
  ],
  "选择操作并勾选一个或多个功能；未选功能保留。卸载只处理已安装项。" : [
    "選擇操作並勾選一個或多個功能；未選功能保留。卸載只處理已安裝項。",
    "Choose an operation and select features. Unselected features remain; only installed features can be uninstalled."
  ],
  "部分功能处理失败；其它所选功能已继续处理。点击失败状态查看完整会话日志。" : [
    "部分功能處理失敗；其它所選功能已繼續處理。點擊失敗狀態查看完整會話日誌。",
    "Some features failed; other selected features were still processed. Click a failed status to open the full session log."
  ],
  "非空且非 iOS 工程的普通目录可见；Flutter 根目录保持支持，点击前复核。" : [
    "非空且非 iOS 工程的普通目錄可見；Flutter 根目錄保持支持，點擊前復核。",
    "Available for nonempty regular directories outside iOS projects, including Flutter roots. Validated again before opening."
  ],
  "黑夜" : [
    "黑夜",
    "Dark"
  ],
  "默认程序安装位置（推荐）" : [
    "默認程序安裝位置（推薦）",
    "Default installation location (recommended)"
  ]
}
'@ | ConvertFrom-Json
foreach ($property in $panelTextData.PSObject.Properties) { $script:PanelTranslations[$property.Name] = @($property.Value) }
$script:PanelTextPatterns = @(
    @{ Pattern = '^(.*)；结果：成功 (\d+)；无需卸载 (\d+)；失败 (\d+)；未执行 (\d+)$'; Text = @('{0}；結果：成功 {1}；無需解除安裝 {2}；失敗 {3}；未執行 {4}', '{0}; Results: succeeded {1}; nothing to uninstall {2}; failed {3}; not run {4}') },
    @{ Pattern = '^(.*) 退出码：(-?\d+)。$'; Text = @('{0} 退出碼：{1}。', '{0} Exit code: {1}.') },
    @{ Pattern = '^(已请求停止安装；等待当前包事务结束，后续项目不再执行。) (.*)$'; Text = @('{0} {1}', '{0} {1}') },
    @{ Pattern = '^(没有需要处理的功能；)(安装总用时|卸载总用时|清理总用时) (\d+:\d+:\d+)$'; Text = @('{0}{1} {2}', '{0}{1} {2}') },
    @{ Pattern = '^已选 (\d+) / (\d+) 项；关闭或取消窗口不执行操作。$'; Text = @('已選 {0} / {1} 項；關閉或取消視窗不執行操作。', 'Selected {0} / {1}. Closing or cancelling makes no changes.') },
    @{ Pattern = '^已选 (\d+) / (\d+)$'; Text = @('已選 {0} / {1}', 'Selected {0} / {1}') },
    @{ Pattern = '^(安装 / 更新|卸载|清理)中；已处理 (\d+) / (\d+) 项（([\d.]+)%，按完成项计数）；(安装用时|卸载用时|清理用时) (\d+:\d+:\d+)$'; Text = @('{0}中；已處理 {1} / {2} 項（{3}%，按完成項計數）；{4} {5}', '{0} in progress; completed {1} / {2} ({3}% by completed items); {4} {5}') },
    @{ Pattern = '^(.*) 已处理 (\d+) / (\d+) 项（([\d.]+)%，按完成项计数）；(安装总用时|卸载总用时|清理总用时) (\d+:\d+:\d+)$'; Text = @('{0} 已處理 {1} / {2} 項（{3}%，按完成項計數）；{4} {5}', '{0} Completed {1} / {2} ({3}% by completed items); {4} {5}') }
)

# JOBS_MANAGER_TRANSLATIONS_BEGIN
$panelExtendedJson = @'
{
  "bo": {
    "Close management panel": "དོ་དམ་པང་ལེབ་ཁ་རྒྱག",
    "Minimize to tray": "མ་ལག་རྟགས་སྒྲོམ་ནང་འཇོག",
    "Exit completely": "ཆ་ཚང་ཕྱིར་འཐོན",
    "Keep window open": "སྒེའུ་ཁུང་ཕྱེ་བཞག",
    "The manager is idle. Keep it in the system tray, or exit completely.": "ལས་འགན་མེད། མ་ལག་རྟགས་སྒྲོམ་ནང་བཞག་པའམ་ཆ་ཚང་ཕྱིར་འཐོན་འདེམས།",
    "Show management panel": "དོ་དམ་པང་ལེབ་སྟོན",
    "Current status": "མིག་སྔའི་གནས་སྟངས",
    "A task is running. Exit is unavailable; restore the window to view logs.": "ལས་འགན་འགྲོ་བཞིན་ཡོད། ད་ལྟ་ཆ་ཚང་ཕྱིར་འཐོན་མི་ཐུབ། སྒེའུ་ཁུང་བསྐྱར་སྟོན་ནས་ཟིན་ཐོ་ལྟ།",
    "The system tray is unavailable. The window will remain open.": "མ་ལག་རྟགས་སྒྲོམ་སྟོན་མི་ཐུབ། སྒེའུ་ཁུང་ཕྱེ་བཞག",
    "💽 Disk free space": "💽 སྡུད་སྡེར་ལྷག་མ།",
    "Show total local disk free / capacity and a two-decimal percentage. Click to choose cleanup in a separate terminal; changes require confirmation.": "ས་གནས་སྡུད་སྡེར་ལྷག་མ་དང་ཤོང་ཚད། བརྒྱ་ཆ་ཚག་གྲངས་གཉིས་སྟོན། གནོན་ན་རང་ཚུགས་མཐའ་སྣེར་གཙང་སེལ་འདེམས། གཏན་འཁེལ་རྗེས་ལག་བསྟར།",
    "Create script launcher…": "སྒྲིག་ཡིག་འཕྲལ་འཇུག་བཟོ།…",
    "🔗 Create script launcher…": "🔗 སྒྲིག་ཡིག་འཕྲལ་འཇུག་བཟོ།…",
    "Create a relative launcher beside a same-name .cmd/.bat/.ps1 script folder; do not run or modify the source script.": ".cmd/.bat/.ps1 མིང་མཚུངས་སྣོད་ཀྱི་འགྲམ་དུ་ལྟོས་བཅས་འཕྲལ་འཇུག་བཟོ། མ་ཡིག་མི་འགུལ་ཞིང་མི་བསྒྱུར།",
    "Theme": "མངོན་ཚུལ།",
    "Language": "སྐད་ཡིག",
    "🎨 Theme": "🎨 མངོན་ཚུལ།",
    "🌐 Language": "🌐 སྐད་ཡིག",
    "Follow system": "མ་ལག་དང་བསྟུན་པ།",
    "Dark": "མཚན་མོ།",
    "Light": "ཉིན་མོ།",
    "Jobs Finder Extension Manager": "Jobs Finder རྒྱ་སྐྱེད་དོ་དམ་ཆས།",
    "Customize Finder Context Menu": "Finder གཡས་མཐེབ་འདེམས་ཐོ་སྒྲིག་འགོད།",
    "Close Manager": "དོ་དམ་ཆས་ཁ་རྒྱག",
    "Edit": "རྩོམ་སྒྲིག",
    "Copy": "འདྲ་བཤུས།",
    "Select all": "ཚང་མ་འདེམས།",
    "Clear all": "ཚང་མའི་འདེམས་རྟགས་སེལ།",
    "Close": "ཁ་རྒྱག",
    "OK": "གཏན་འཁེལ།",
    "Install": "སྒྲིག་འཇུག",
    "Install / Update": "སྒྲིག་འཇུག / གསར་བཅོས།",
    "Uninstall": "སྒྲིག་འཇུག་སུབ།",
    "Cleanup": "གཙང་སེལ།",
    "Clean build products": "བཟོ་སྐྲུན་ཐོན་རྫས་སུབ།",
    "🧹 Clean build products": "🧹 བཟོ་སྐྲུན་ཐོན་རྫས་སུབ།",
    "Stop installation": "སྒྲིག་འཇུག་མཚམས་འཇོག",
    "Stopping…": "མཚམས་འཇོག་བཞིན་པ།…",
    "Action: install / update or uninstall": "བྱ་བ། སྒྲིག་འཇུག / གསར་བཅོས་སམ་སྒྲིག་འཇུག་སུབ་པ།",
    "Uninstall removes selected menus only. Group selection affects its own group.": "འདེམས་པའི་འདེམས་ཐོ་ཁོ་ན་སུབ་ཀྱི་ཡོད། ཚོགས་པའི་ནང་གི་འདེམས་ཀས་ཚོགས་པ་དེ་ཁོ་ནར་ཕན་ནུས་ཐོན།",
    "Install / uninstall with the combined App in Applications": "ཉེར་སྤྱོད་དཀར་ཆག་ནང་གི་མཉམ་སྡེབ་ཉེར་སྤྱོད་བརྒྱུད་སྒྲིག་འཇུག / སུབ་པ།",
    "Install or uninstall the combined App in Applications": "ཉེར་སྤྱོད་དཀར་ཆག་ནང་གི་མཉམ་སྡེབ་ཉེར་སྤྱོད་བརྒྱུད་སྒྲིག་འཇུག་གམ་སུབ་པ།",
    "Selected: manage features in /Applications/Jobs自定义右键菜单.app. Otherwise use the build directory.": "འདེམས་རྟགས་ཡོད་ན། /Applications/Jobs自定义右键菜单.app ནང་འདེམས་པའི་བྱེད་ནུས་དོ་དམ་བྱེད། མེད་ན་བཟོ་སྐྲུན་དཀར་ཆག་སྤྱོད།",
    "Clean this build after successful installation": "སྒྲིག་འཇུག་ལེགས་འགྲུབ་རྗེས་ཐེངས་འདིའི་བཟོ་སྐྲུན་ཐོན་རྫས་སུབ།",
    "Clean this build only after the combined App is installed and verified in Applications. Keep failed builds.": "མཉམ་སྡེབ་ཉེར་སྤྱོད་དེ་ཉེར་སྤྱོད་དཀར་ཆག་ནང་སྒྲིག་འཇུག་དང་ར་སྤྲོད་ལེགས་འགྲུབ་རྗེས་ཁོ་ན་ཐེངས་འདིའི་ཐོན་རྫས་སུབ། ཕམ་པའི་བཟོ་སྐྲུན་ཉར།",
    "Clean build products of selected features without installing or uninstalling.": "འདེམས་པའི་བྱེད་ནུས་ཀྱི་བཟོ་སྐྲུན་ཐོན་རྫས་ཁོ་ན་གཙང་སེལ་བྱེད། སྒྲིག་འཇུག་གམ་སུབ་པ་མི་བྱེད།",
    "Clean selected features' build products": "འདེམས་པའི་བྱེད་ནུས་ཀྱི་བཟོ་སྐྲུན་ཐོན་རྫས་གཙང་སེལ།",
    "Open Privacy & Security": "སྒེར་གསང་དང་བདེ་འཇགས་སྒྲིག་འགོད་ཁ་ཕྱེ།",
    "Add and enable Jobs右键菜单管理面板.app in Privacy & Security → App Management. This only opens Settings.": "སྒེར་གསང་དང་བདེ་འཇགས་ → ཉེར་སྤྱོད་དོ་དམ་ནང་ Jobs右键菜单管理面板.app སྣོན་ནས་སྤྱོད་སྒོ་ཕྱེ། མཐེབ་འདིས་སྒྲིག་འགོད་ཁོ་ན་ཁ་ཕྱེ་བ་ཡིན།",
    "Target: build directory. Cleaning these products affects installed features.": "མིག་སྔའི་དམིགས་ཡུལ། བཟོ་སྐྲུན་དཀར་ཆག ཐོན་རྫས་དེ་དག་སུབ་ན་སྒྲིག་འཇུག་ཟིན་པའི་བྱེད་ནུས་ལ་གནོད་སྲིད།",
    "App: Jobs自定义右键菜单.app at /Applications/Jobs自定义右键菜单.app (build products can be cleaned after installation)": "མཉམ་སྡེབ་ཉེར་སྤྱོད། Jobs自定义右键菜单.app། གནས་ཡུལ། /Applications/Jobs自定义右键菜单.app (སྒྲིག་འཇུག་རྗེས་བཟོ་སྐྲུན་ཐོན་རྫས་སུབ་ཆོག)",
    "Drag the divider to resize the log. Features and logs scroll separately.": "མཚམས་འབྱེད་ཐིག་གོང་འོག་ཏུ་འདྲུད་ནས་ཟིན་ཐོའི་མཐོ་ཚད་སྒྱུར། བྱེད་ནུས་ཐོ་དང་ཟིན་ཐོ་སོ་སོར་འདྲིལ་ཆོག",
    "Feature list and live log divider": "བྱེད་ནུས་ཐོ་དང་དུས་ཐོག་ཟིན་ཐོའི་མཚམས་འབྱེད་ཐིག",
    "Live log (select and copy text)": "དུས་ཐོག་ཟིན་ཐོ། (ཡིག་གེ་འདེམས་ནས་འདྲ་བཤུས་བྱེད་ཆོག)",
    "Copy log": "ཟིན་ཐོ་འདྲ་བཤུས།",
    "Log file": "ཟིན་ཐོའི་ཡིག་ཆ།",
    "Auto-scroll": "རང་འགུལ་འདྲིལ་བ།",
    "Ready. Select features and choose an action.": "གྲ་སྒྲིག་ཚར། བྱེད་ནུས་འདེམས་ནས་བྱ་བའི་མཐེབ་གནོན།",
    "A task is running. Wait for it to finish before closing.": "ལས་འགན་འགྲོ་བཞིན་ཡོད། སྒྲིག་འཇུག་མི་ཆད་པའི་ཆེད་དུ་ལས་འགན་ཚར་རྗེས་ཁ་རྒྱག་རོགས།",
    "Unable to view this log": "ཐེངས་འདིའི་ཟིན་ཐོ་ལྟ་མི་ཐུབ།",
    "Log is missing or unreadable: {0}": "ཟིན་ཐོ་མེད་པའམ་ཀློག་མི་ཐུབ། {0}",
    "Unable to open log terminal: {0}": "ཟིན་ཐོའི་མཐའ་སྣེ་ཁ་ཕྱེ་མི་ཐུབ། {0}",
    "Click to show this session's full log in a new terminal: {0}": "ཐེངས་འདིའི་ཟིན་ཐོ་ཆ་ཚང་མཐའ་སྣེ་གསར་པར་སྟོན་པར་མནན། {0}",
    "Selected {0} / {1}. Select at least one. Changing action keeps selection.": "{0} / {1} འདེམས་ཟིན། ཉུང་མཐར་གཅིག་འདེམས་དགོས། བྱ་བ་བརྗེ་སྐབས་འདེམས་ཀ་ཉར།",
    "Selected {0} / {1}": "{0} / {1} འདེམས་ཟིན།",
    "{0}: select all": "{0}། ཚང་མ་འདེམས།",
    "{0}: clear all": "{0}། ཚང་མའི་འདེམས་རྟགས་སེལ།",
    "Waiting": "སྒུག་བཞིན་པ།",
    "Cleaning…": "གཙང་སེལ་བྱེད་བཞིན་པ།…",
    "Uninstalling…": "སྒྲིག་འཇུག་སུབ་བཞིན་པ།…",
    "Installing…": "སྒྲིག་འཇུག་བྱེད་བཞིན་པ།…",
    "Cleaned": "གཙང་སེལ་བྱས་ཟིན།",
    "Uninstalled": "སྒྲིག་འཇུག་སུབ་ཟིན།",
    "Installed": "སྒྲིག་འཇུག་ལེགས་འགྲུབ།",
    "Skipped": "ལག་བསྟར་མ་བྱས།",
    "Not installed; nothing to remove": "སྒྲིག་འཇུག་མ་བྱས་པས་སུབ་དགོས་མེད།",
    "Failed: see log": "ཕམ་པ། ཟིན་ཐོ་ལ་གཟིགས།",
    "Selected": "འདེམས་ཟིན།",
    "Not selected": "འདེམས་མེད།",
    "App Management permission required": "ཉེར་སྤྱོད་དོ་དམ་གྱི་ཆོག་མཆན་དགོས།",
    "Permission check required": "ཆོག་མཆན་ཞིབ་བཤེར་དགོས།",
    "Stopped": "མཚམས་བཞག་ཟིན།",
    "Completed": "ལེགས་འགྲུབ་ཟིན།",
    "Task failed": "ལས་འགན་ཕམ་པ།",
    "{0}: processed {1} / {2} ({3}, completed items); {4} time {5}": "{0} བྱེད་བཞིན་པ། {1} / {2} སྒྲུབ་ཟིན། ({3}། ཚར་བའི་གྲངས་ལྟར།) {4} ཡི་དུས་ཡུན། {5}",
    "{0} ready": "{0} གྲ་སྒྲིག་ཚར།",
    "{0} ready; {1} time {2}": "{0} གྲ་སྒྲིག་ཚར། {1} ཡི་དུས་ཡུན། {2}",
    "Finishing the current feature, then stopping; install time {0}": "མིག་སྔའི་བྱེད་ནུས་ཚར་རྗེས་མཚམས་འཇོག་རྒྱུ་ཡིན། སྒྲིག་འཇུག་དུས་ཡུན། {0}",
    "{0}: {1} succeeded, {2} failed, {3} skipped; exit {4}; {5}; {6} time {7}": "{0}། ལེགས་འགྲུབ་ {1}། ཕམ་པ་ {2}། ལག་བསྟར་མ་བྱས་ {3}། ཕྱིར་ཐོན་ཨང་ {4}། {5}། {6} ཡི་དུས་ཡུན་བསྡོམས་ {7}",
    "{0}: {1} succeeded, {2} failed, {3} not installed, {4} skipped; exit {5}; {6}; {7} time {8}": "{0}། ལེགས་འགྲུབ་ {1}། ཕམ་པ་ {2}། སྒྲིག་འཇུག་མ་བྱས་ {3}། ལག་བསྟར་མ་བྱས་ {4}། ཕྱིར་ཐོན་ཨང་ {5}། {6}། {7} ཡི་དུས་ཡུན་བསྡོམས་ {8}",
    "{0}: {1} succeeded, {2} failed, {3} not installed; exit {4}; {5}; {6} time {7}": "{0}། ལེགས་འགྲུབ་ {1}། ཕམ་པ་ {2}། སྒྲིག་འཇུག་མ་བྱས་ {3}། ཕྱིར་ཐོན་ཨང་ {4}། {5}། {6} ཡི་དུས་ཡུན་བསྡོམས་ {7}",
    "{0}: {1} succeeded, {2} failed; exit {3}; {4}; {5} time {6}": "{0}། ལེགས་འགྲུབ་ {1}། ཕམ་པ་ {2}། ཕྱིར་ཐོན་ཨང་ {3}། {4}། {5} ཡི་དུས་ཡུན་བསྡོམས་ {6}",
    "Open projects in IDEs": "IDE ནང་ལས་གཞི་ཁ་ཕྱེ་བ།",
    "Git tools": "Git ལག་ཆ།",
    "Files and general tools": "ཡིག་ཆ་དང་སྤྱི་སྤྱོད་ལག་ཆ།",
    "Flutter tools · submenu actions": "Flutter ལག་ཆ། · ཡན་ལག་འདེམས་ཐོའི་བྱ་བ།",
    "iOS / CocoaPods tools": "iOS / CocoaPods ལག་ཆ།",
    "Simulator tools": "ལད་ཟློས་ཆས་ཀྱི་ལག་ཆ།",
    "Open project in Android Studio": "Android Studio ནང་ལས་གཞི་ཁ་ཕྱེ།",
    "Open project in VSCode": "VSCode ནང་ལས་གཞི་ཁ་ཕྱེ།",
    "Open project in Xcode": "Xcode ནང་ལས་གཞི་ཁ་ཕྱེ།",
    "Pull latest Git changes": "Git གི་གསར་ཤོས་འགྱུར་བ་ལེན།",
    "Roll back Git commit": "Git འབུལ་བ་ཕྱིར་ལོག",
    "Open Git remote URL": "Git ཐག་རིང་མཛོད་ཀྱི་དྲ་གནས་ཁ་ཕྱེ།",
    "Copy Git remote URL": "Git ཐག་རིང་མཛོད་ཀྱི་དྲ་གནས་འདྲ་བཤུས།",
    "Copy absolute path": "ལྟོས་མེད་ལམ་བུ་འདྲ་བཤུས།",
    "Create file": "ཡིག་ཆ་གསར་བཟོ།",
    "View file fingerprint Hash (SHA-256)": "ཡིག་ཆའི་མཛུབ་རྗེས་ཨང་ (SHA-256) སྟོན།",
    "Grant execute permission (chmod +x)": "ལག་བསྟར་ཆོག་མཆན་སྤྲོད། (chmod +x)",
    "Remove execute permission (chmod -x)": "ལག་བསྟར་ཆོག་མཆན་ཕྱིར་འཐེན། (chmod -x)",
    "Re-sign IPA without building": "སྒྲིག་སྒྱུར་མ་བྱས་པར་ IPA ལ་སླར་མིང་རྟགས་འགོད།",
    "Show / hide files": "ཡིག་ཆ་མངོན་པ་ / སྦེད་པ།",
    "Create iOS simulator": "iOS ལད་ཟློས་ཆས་གསར་བཟོ།",
    "Create Android simulator": "Android ལད་ཟློས་ཆས་གསར་བཟོ།",
    "Create Harmony simulator": "Harmony ལད་ཟློས་ཆས་གསར་བཟོ།",
    "Check / repair Android simulator": "Android ལད་ཟློས་ཆས་ཞིབ་བཤེར་ / ཉམས་གསོ།",
    "Check / repair Harmony simulator": "Harmony ལད་ཟློས་ཆས་ཞིབ་བཤེར་ / ཉམས་གསོ།",
    "Configure Git proxy": "Git གི་འགུལ་རྣམ་ལས་ཚབ་སྒྲིག་འགོད།",
    "Open in terminal": "མཐའ་སྣེ་ནང་ཁ་ཕྱེ།",
    "View file contents in terminal": "མཐའ་སྣེ་ནང་ཡིག་ཆའི་ནང་དོན་ལྟ།",
    "Merge file parts": "ཡིག་ཆའི་ཆ་ཤས་མཉམ་སྡེབ།",
    "Split file": "ཡིག་ཆ་ཁ་གྱེས།",
    "Clean Android / OpenHarmony builds": "Android / OpenHarmony བཟོ་སྐྲུན་ཐོན་རྫས་གཙང་སེལ།",
    "Update code map (.codegraph)": "ཚབ་ཨང་ས་ཁྲ་ (.codegraph) གསར་བཅོས།",
    "Create empty commit and push in terminal": "མཐའ་སྣེ་ནང་འབུལ་བ་སྟོང་པ་བཟོས་ནས་ཡར་སྐྱེལ།",
    "Disable CocoaPods build sandbox": "CocoaPods བཟོ་སྐྲུན་གྱི་ལོགས་འཇོག་ཁོར་ཡུག་སྒོ་རྒྱག",
    "Install CocoaPods": "CocoaPods སྒྲིག་འཇུག",
    "CocoaPods source: CDN → GitHub": "CocoaPods ཁུངས། CDN → GitHub",
    "Export all project Pod files": "ལས་གཞིའི་ Pod འབྲེལ་ཡོད་ཡིག་ཆ་ཚང་མ་ཕྱིར་འདྲེན།",
    "Inspect Xcode project dependencies": "Xcode ལས་གཞིའི་བརྟེན་འབྲེལ་ཞིབ་བཤེར།",
    "Update local CocoaPods repositories": "CocoaPods ཀྱི་རང་གནས་མཛོད་གསར་བཅོས།",
    "Check local Pod builds (.podspec folder)": "རང་གནས་ Pod སྒྲིག་སྒྱུར་ཐུབ་མིན་ཞིབ་བཤེར། (.podspec དཀར་ཆག་ཁོ་ན།)",
    "Install / update JobsCodeSnippets": "JobsCodeSnippets སྒྲིག་འཇུག / གསར་བཅོས།",
    "Clean iOS / Xcode builds": "iOS / Xcode བཟོ་སྐྲུན་ཐོན་རྫས་གཙང་སེལ།",
    "Set up Flutter project": "Flutter ལས་གཞི་སྒྲིག་འགོད།",
    "Run Flutter project in terminal": "མཐའ་སྣེ་ནང་ Flutter ལས་གཞི་ལག་བསྟར།",
    "Fetch Flutter Pub dependencies": "Flutter Pub བརྟེན་འབྲེལ་ལེན།",
    "Fetch native Android dependencies": "Android གི་ཐད་ཀའི་བརྟེན་འབྲེལ་ལེན།",
    "Fetch CocoaPods dependencies": "CocoaPods བརྟེན་འབྲེལ་ལེན།",
    "Fetch Swift Package dependencies": "Swift Package བརྟེན་འབྲེལ་ལེན།",
    "Fetch OpenHarmony dependencies": "OpenHarmony བརྟེན་འབྲེལ་ལེན།",
    "Prepare native libraries and build dependencies": "མ་ལག་ཐད་ཀའི་བྱ་རིམ་མཛོད་དང་བཟོ་སྐྲུན་བརྟེན་འབྲེལ་གྲ་སྒྲིག",
    "Download Flutter platform resources": "Flutter ལས་སྟེགས་ཐོན་ཁུངས་ཕབ་ལེན།",
    "Fetch Web project dependencies": "དྲ་ངོས་ལས་གཞིའི་བརྟེན་འབྲེལ་ལེན།",
    "🧳 Export Flutter dependencies": "🧳 Flutter བརྟེན་འབྲེལ་ཚང་མ་ཕྱིར་འདྲེན།",
    "Export Flutter Pub dependencies": "Flutter Pub བརྟེན་འབྲེལ་ཕྱིར་འདྲེན།",
    "🔐 Export private Flutter dependencies": "🔐 Flutter སྒེར་གྱི་མཛོད་བརྟེན་འབྲེལ་ཕྱིར་འདྲེན།",
    "📥 Import Flutter dependencies": "📥 Flutter བརྟེན་འབྲེལ་ཚང་མ་ནང་འདྲེན།",
    "Import Flutter Pub dependencies": "Flutter Pub བརྟེན་འབྲེལ་ནང་འདྲེན།",
    "📥 Import private Flutter dependencies": "📥 Flutter སྒེར་གྱི་མཛོད་བརྟེན་འབྲེལ་ནང་འདྲེན།",
    "Export Gradle distributions and cache": "Gradle འགྲེམས་སྤེལ་ཐུམ་བུ་དང་གནས་སྐབས་གསོག་འཇོག་ཕྱིར་འདྲེན།",
    "Import Gradle distributions and cache": "Gradle འགྲེམས་སྤེལ་ཐུམ་བུ་དང་གནས་སྐབས་གསོག་འཇོག་ནང་འདྲེན།",
    "Export CocoaPods dependencies": "CocoaPods བརྟེན་འབྲེལ་ཕྱིར་འདྲེན།",
    "Import CocoaPods dependencies": "CocoaPods བརྟེན་འབྲེལ་ནང་འདྲེན།",
    "Export Swift Package dependencies": "Swift Package བརྟེན་འབྲེལ་ཕྱིར་འདྲེན།",
    "Import Swift Package dependencies": "Swift Package བརྟེན་འབྲེལ་ནང་འདྲེན།",
    "Export OpenHarmony dependencies": "OpenHarmony བརྟེན་འབྲེལ་ཕྱིར་འདྲེན།",
    "Import OpenHarmony dependencies": "OpenHarmony བརྟེན་འབྲེལ་ནང་འདྲེན།",
    "Export native build cache": "མ་ལག་ཐད་ཀའི་བཟོ་སྐྲུན་གནས་སྐབས་གསོག་འཇོག་ཕྱིར་འདྲེན།",
    "Import native build cache": "མ་ལག་ཐད་ཀའི་བཟོ་སྐྲུན་གནས་སྐབས་གསོག་འཇོག་ནང་འདྲེན།",
    "Export Flutter platform resources": "Flutter ལས་སྟེགས་ཐོན་ཁུངས་ཕྱིར་འདྲེན།",
    "Import Flutter platform resources": "Flutter ལས་སྟེགས་ཐོན་ཁུངས་ནང་འདྲེན།",
    "Export Web dependencies": "དྲ་ངོས་བརྟེན་འབྲེལ་ཕྱིར་འདྲེན།",
    "Import Web dependencies": "དྲ་ངོས་བརྟེན་འབྲེལ་ནང་འདྲེན།",
    "Show Flutter project SDK version": "Flutter ལས་གཞིའི་ SDK པར་གཞི་སྟོན།",
    "Install / switch Flutter SDK": "Flutter SDK སྒྲིག་འཇུག / བརྗེ་བ།",
    "Install / switch Flutter@OpenHarmony SDK": "Flutter@OpenHarmony SDK སྒྲིག་འཇུག / བརྗེ་བ།",
    "Install / switch Java SDK": "Java SDK སྒྲིག་འཇུག / བརྗེ་བ།",
    "Download Gradle distributions and plugins": "Gradle འགྲེམས་སྤེལ་ཐུམ་བུ་དང་བཟོ་སྐྲུན་བསྒར་ལྷུ་ཕབ་ལེན།",
    "Generate Flutter code": "Flutter ཚབ་ཨང་རང་འགུལ་གསར་བཟོ།",
    "Package iOS": "iOS ཐུམ་བུ་བཟོ།",
    "Package Android": "Android ཐུམ་བུ་བཟོ།",
    "Package Harmony (HAP + APP)": "Harmony ཐུམ་བུ་བཟོ། (HAP + APP)",
    "Check native Flutter project": "ཐད་ཀའི་ Flutter ལས་གཞིའི་བདེ་ཐང་ཞིབ་བཤེར།",
    "Check OpenHarmony Flutter environment": "OpenHarmony Flutter ཁོར་ཡུག་གི་བདེ་ཐང་ཞིབ་བཤེར།",
    "Repair missing Android SDK / platforms": "ཆད་པའི་ Android SDK / ལས་སྟེགས་ཉམས་གསོ།",
    "Repair Chinese Flutter project paths": "Flutter ལས་གཞིའི་རྒྱ་ཡིག་ལམ་བུ་ཉམས་གསོ།",
    "Repair Flutter plugin namespaces": "Flutter བསྒར་ལྷུའི་ namespace ཉམས་གསོ།",
    "Convert relative Dart imports to packages": "Dart འབྲེལ་ལྟོས་ནང་འདྲེན་ package འདྲེན་སྟངས་སུ་སྒྱུར།",
    "Clean current Flutter project builds": "ད་ལྟའི་ Flutter ལས་གཞིའི་བཟོ་སྐྲུན་ཐོན་རྫས་གཙང་སེལ།",
    "Dependency and cache maintenance": "བརྟེན་འབྲེལ་དང་གནས་སྐབས་གསོག་འཇོག་ཉམས་གསོ།",
    "Custom Explorer context menu": "Explorer གཡས་མཐེབ་འདེམས་ཐོ་རང་སྒྲིག",
    "Jobs Windows · Custom Explorer context menu": "Jobs Windows · Explorer གཡས་མཐེབ་འདེམས་ཐོ་རང་སྒྲིག",
    "Show a regular file's SHA-256 in a new terminal and copy the digest; do not modify or execute the file.": "མཐའ་སྣེ་གསར་པའི་ནང་རྒྱུན་ལྡན་ཡིག་ཆ་གཅིག་གི་ SHA-256 སྟོན་ཞིང་དེའི་གནས་ཐང་འདྲ་བཤུས་བྱེད། ཡིག་ཆ་བཟོ་བཅོས་དང་ལག་བསྟར་མི་བྱེད།",
    " (preview)": "（སྔོན་ལྟ་ཙམ）",
    "⏪ Roll back Git commits": "⏪ Git འབུལ་བ་ཕྱིར་ལོག",
    "▶️ Run Flutter project in terminal": "▶️ མཐའ་སྣེ་ནང་ Flutter ལས་གཞི་ལག་བསྟར།",
    "☕ Install / switch Java SDK": "☕ Java SDK སྒྲིག་འཇུག / བརྗེ་བ།",
    "♻️ Flutter cleanup and maintenance": "♻️ Flutter གཙང་སེལ་དང་ཉམས་གསོ།",
    "⚙️ Generate Flutter code": "⚙️ Flutter ཚབ་ཨང་རང་འགུལ་གསར་བཟོ།",
    "✅ Installed": "✅ སྒྲིག་འཇུག་ལེགས་འགྲུབ།",
    "⬇️ Pull latest Git changes": "⬇️ Git གསར་ཤོས་ཀྱི་འགྱུར་བ་ལེན།",
    "🌈 Create Harmony emulator": "🌈 Harmony ལད་མོའི་འཕྲུལ་ཆས་གསར་བཟོ།",
    "🌐 Open Git remote URL": "🌐 Git རྒྱང་སྦྲེལ་དྲ་གནས་ཁ་ཕྱེ།",
    "🌐 Fetch Web project dependencies": "🌐 དྲ་ངོས་ལས་གཞིའི་བརྟེན་འབྲེལ་ལེན།",
    "🌳 Open in Sourcetree": "🌳 Sourcetree ནང་ཁ་ཕྱེ།",
    "🏥 Flutter project diagnostics": "🏥 Flutter ལས་གཞིའི་བདེ་ཐང་ཞིབ་བཤེར།",
    "🏥 Flutter diagnostics": "🏥 Flutter བདེ་ཐང་ཞིབ་བཤེར།",
    "🏷️ Repair Flutter plugin namespaces": "🏷️ Flutter བསྒར་ལྷུའི་ namespace ཉམས་གསོ།",
    "👁️ Show / hide hidden files": "👁️ སྦས་པའི་ཡིག་ཆ་སྟོན / སྦེད།",
    "💓 OpenHarmony Flutter diagnostics": "💓 OpenHarmony Flutter ཁོར་ཡུག་གི་བདེ་ཐང་ཞིབ་བཤེར།",
    "💠 Open project in Visual Studio": "💠 Visual Studio ནང་ལས་གཞི་ཁ་ཕྱེ།",
    "💻 Open in terminal": "💻 མཐའ་སྣེ་ནང་ཁ་ཕྱེ།",
    "📄 View file in terminal": "📄 མཐའ་སྣེ་ནང་ཡིག་ཆ་ལྟ་བ།",
    "📋 Copy absolute path": "📋 ངེས་གཏན་ལམ་བུ་འདྲ་བཤུས།",
    "📚 Download Gradle distributions and build plugins": "📚 Gradle འགྲེམས་སྤེལ་ཐུམ་བུ་དང་བཟོ་སྐྲུན་བསྒར་ལྷུ་ཕབ་ལེན།",
    "📝 Open project in VSCode": "📝 VSCode ནང་ལས་གཞི་ཁ་ཕྱེ།",
    "📡 Configure Git dynamic proxy": "📡 Git འགུལ་རྣམ་ཚབ་སྦྲེལ་སྒྲིག་འགོད།",
    "📤 Import Flutter Pub dependencies": "📤 Flutter Pub བརྟེན་འབྲེལ་ནང་འདྲེན།",
    "📤 Import Flutter platform assets": "📤 Flutter ལས་སྟེགས་ཐོན་ཁུངས་ནང་འདྲེན།",
    "📤 Import Gradle distributions and dependency caches": "📤 Gradle འགྲེམས་སྤེལ་ཐུམ་བུ་དང་བརྟེན་འབྲེལ་གནས་སྐབས་གསོག་འཇོག་ནང་འདྲེན།",
    "📤 Import OpenHarmony dependencies": "📤 OpenHarmony བརྟེན་འབྲེལ་ནང་འདྲེན།",
    "📤 Import Web dependencies": "📤 དྲ་ངོས་བརྟེན་འབྲེལ་ནང་འདྲེན།",
    "📤 Import native build caches": "📤 མ་ལག་ཐད་ཀའི་བཟོ་སྐྲུན་གནས་སྐབས་གསོག་འཇོག་ནང་འདྲེན།",
    "📤 Import Flutter project dependencies": "📤 Flutter ལས་གཞིའི་བརྟེན་འབྲེལ་ནང་འདྲེན།",
    "📤 Create empty commit and push": "📤 ནང་དོན་མེད་པའི་འབུལ་བ་བཟོས་ཏེ་ཕར་སྐྱེལ།",
    "📥 Install Flutter dependencies (pub get)": "📥 Flutter བརྟེན་འབྲེལ་སྒྲིག་འཇུག (pub get)",
    "📥 Import private Flutter project dependencies": "📥 Flutter ལས་གཞིའི་སྒེར་གྱི་མཛོད་བརྟེན་འབྲེལ་ནང་འདྲེན།",
    "📥 Fetch Flutter Pub dependencies": "📥 Flutter Pub བརྟེན་འབྲེལ་ལེན།",
    "📥 Fetch Flutter project dependencies": "📥 Flutter ལས་གཞིའི་བརྟེན་འབྲེལ་ལེན།",
    "📦 Package Flutter project": "📦 Flutter ལས་གཞི་ཐུམ་བུ་བཟོ།",
    "📦 Package HarmonyOS (HAP + APP)": "📦 HarmonyOS ཐུམ་བུ་བཟོ། (HAP + APP)",
    "📱 Create Android emulator": "📱 Android ལད་མོའི་འཕྲུལ་ཆས་གསར་བཟོ།",
    "🔀 Install / switch Flutter SDK (FVM)": "🔀 Flutter SDK སྒྲིག་འཇུག / བརྗེ་བ། (FVM)",
    "🔀 Install / switch Flutter SDK": "🔀 Flutter SDK སྒྲིག་འཇུག / བརྗེ་བ།",
    "🔀 Install / switch Flutter environments": "🔀 Flutter ལག་བསྟར་ཁོར་ཡུག་སྒྲིག་འཇུག / བརྗེ་བ།",
    "🔎 Show current Flutter SDK version": "🔎 ད་ལྟའི་ Flutter SDK པར་གཞི་སྟོན།",
    "🔎 Show current Flutter project's SDK version": "🔎 ད་ལྟའི་ Flutter ལས་གཞིའི་ SDK པར་གཞི་སྟོན།",
    "🔐 Export private Flutter project dependencies": "🔐 Flutter ལས་གཞིའི་སྒེར་གྱི་མཛོད་བརྟེན་འབྲེལ་ཕྱིར་འདྲེན།",
    "🔎 Show file fingerprint Hash (SHA-256)": "🔎 ཡིག་ཆའི་མཛུབ་རྗེས་ Hash སྟོན། (SHA-256)",
    "➕ Grant execute permission": "➕ ལག་བསྟར་ཆོག་མཆན་སྤྲོད།",
    "➖ Remove execute permission": "➖ ལག་བསྟར་ཆོག་མཆན་སེལ།",
    "🔒 Grant execute permission": "🔒 ལག་བསྟར་ཆོག་མཆན་སྤྲོད།",
    "🔓 Remove execute permission": "🔓 ལག་བསྟར་ཆོག་མཆན་སེལ།",
    "🔗 Copy Git remote URL": "🔗 Git རྒྱང་སྦྲེལ་དྲ་གནས་འདྲ་བཤུས།",
    "🔧 Flutter repairs": "🔧 Flutter ལས་གཞི་ཉམས་གསོ།",
    "🕊️ Install / switch Flutter@OpenHarmony SDK": "🕊️ Flutter@OpenHarmony SDK སྒྲིག་འཇུག / བརྗེ་བ།",
    "🕊️ Fetch OpenHarmony dependencies": "🕊️ OpenHarmony བརྟེན་འབྲེལ་ལེན།",
    "🗃️ Download Flutter platform assets": "🗃️ Flutter ལས་སྟེགས་ཐོན་ཁུངས་ཕབ་ལེན།",
    "🗺️ Update code map (.codegraph)": "🗺️ ཚབ་ཨང་ས་ཁྲ་གསར་སྒྱུར། (.codegraph)",
    "🤖 Fetch Android native dependencies": "🤖 Android གི་ཐད་ཀའི་བརྟེན་འབྲེལ་ལེན།",
    "🦋 Flutter development": "🦋 Flutter འཕེལ་བཟོའི་རམ་འདེགས།",
    "🦋 Flutter development tools": "🦋 Flutter འཕེལ་བཟོའི་རམ་འདེགས་ལག་ཆ།",
    "🧑‍⚕️ Native Flutter diagnostics": "🧑‍⚕️ ཐད་ཀའི་ Flutter ལས་གཞིའི་བདེ་ཐང་ཞིབ་བཤེར།",
    "🧩 Export Flutter Pub dependencies": "🧩 Flutter Pub བརྟེན་འབྲེལ་ཕྱིར་འདྲེན།",
    "🧩 Export Flutter platform assets": "🧩 Flutter ལས་སྟེགས་ཐོན་ཁུངས་ཕྱིར་འདྲེན།",
    "🧩 Export Flutter third-party dependencies": "🧩 Flutter ཕྱི་ཕྱོགས་བརྟེན་འབྲེལ་ཕྱིར་འདྲེན།",
    "🧩 Export Gradle distributions and dependency caches": "🧩 Gradle འགྲེམས་སྤེལ་ཐུམ་བུ་དང་བརྟེན་འབྲེལ་གནས་སྐབས་གསོག་འཇོག་ཕྱིར་འདྲེན།",
    "🧩 Export OpenHarmony dependencies": "🧩 OpenHarmony བརྟེན་འབྲེལ་ཕྱིར་འདྲེན།",
    "🧩 Export Web dependencies": "🧩 དྲ་ངོས་བརྟེན་འབྲེལ་ཕྱིར་འདྲེན།",
    "🧩 Export native build caches": "🧩 མ་ལག་ཐད་ཀའི་བཟོ་སྐྲུན་གནས་སྐབས་གསོག་འཇོག་ཕྱིར་འདྲེན།",
    "🧩 Export Flutter project dependencies": "🧩 Flutter ལས་གཞིའི་བརྟེན་འབྲེལ་ཕྱིར་འདྲེན།",
    "🧩 Merge file volumes / ✂️ Split file": "🧩 ཡིག་ཆའི་ཆ་ཤས་ཟླ་སྒྲིལ / ✂️ ཡིག་ཆ་དབྱེ་བ།",
    "🧭 Open project in Android Studio": "🧭 Android Studio ནང་ལས་གཞི་ཁ་ཕྱེ།",
    "🧯 Clean build output": "🧯 བཟོ་སྐྲུན་ཐོན་རྫས་གཙང་སེལ།",
    "🧰 Diagnose and repair Harmony emulator": "🧰 Harmony ལད་མོའི་འཕྲུལ་ཆས་བརྟག་དཔྱད་དང་ཉམས་གསོ།",
    "🧱 Flutter assets and build dependencies": "🧱 Flutter རྒྱུ་ཆ་དང་བཟོ་སྐྲུན་བརྟེན་འབྲེལ།",
    "🧱 Prepare native libraries and build dependencies (combined)": "🧱 གདོད་མའི་དཔེ་མཛོད་དང་བཟོ་སྐྲུན་བརྟེན་འབྲེལ་གྲ་སྒྲིག（མཉམ་སྒྲུབ）།",
    "🧹 Clean build output": "🧹 བཟོ་སྐྲུན་ཐོན་རྫས་གཙང་སེལ།",
    "🩹 Repair missing Android SDK / platforms": "🩹 ཆད་པའི Android SDK / སྟེགས་བུ་ཉམས་གསོ།",
    "🩺 Diagnose and repair Android emulator": "🩺 Android ལད་མོའི་འཕྲུལ་ཆས་བརྟག་དཔྱད་དང་ཉམས་གསོ།",
    "🚀 Set up Flutter project": "🚀 Flutter ལས་གཞི་སྒྲིག་འགོད།",
    "🚚 Import all Flutter dependencies": "🚚 Flutter བརྟེན་འབྲེལ་ཚང་མ་ནང་འདྲེན།",
    "🚚 Export all Flutter dependencies": "🚚 Flutter བརྟེན་འབྲེལ་ཚང་མ་ཕྱིར་འདྲེན།",
    "Jobs Windows · Uninstall Explorer extensions": "Jobs Windows · Explorer རྒྱ་སྐྱེད་སྒྲིག་འཇུག་སུབ།",
    "Jobs Windows · Install Explorer extensions": "Jobs Windows · Explorer རྒྱ་སྐྱེད་སྒྲིག་འཇུག",
    "Jobs Windows · Manage Explorer extensions": "Jobs Windows · Explorer རྒྱ་སྐྱེད་དོ་དམ།",
    "Jobs Windows · Configure Explorer extensions": "Jobs Windows · Explorer རྒྱ་སྐྱེད་སྒྲིག་འགོད།",
    "Drag the divider vertically to resize the log": "དབྱེ་ཐིག་སྟེང་འོག་ཏུ་འདྲུད་ནས་ཟིན་ཐོའི་མཐོ་ཚད་སྒྱུར།",
    "Drag vertically to resize the log": "སྟེང་འོག་ཏུ་འདྲུད་ནས་ཟིན་ཐོའི་མཐོ་ཚད་སྒྱུར།",
    "Validate the Flutter project, diagnose the toolchain in terminal, and choose a Flutter SDK version with fzf.": "Flutter ལས་གཞི་བདེན་དཔང་བྱས་རྗེས་མཐའ་སྣེར་ལག་ཆའི་སྦྲེལ་ཐག་བརྟག་དཔྱད་བྱས་ནས fzf ཡིས Flutter SDK པར་གཞི་འདེམས།",
    "Validate the Flutter project, then show the active SDK version (project FVM or system SDK) in terminal and compare it with .fvmrc and pubspec constraints.": "Flutter ལས་གཞི་བདེན་དཔང་བྱས་རྗེས་མཐའ་སྣེར་ད་ལྟའི SDK པར་གཞི（ལས་གཞིའི FVM ཡང་ན་མ་ལག་གི SDK）མངོན་ནས .fvmrc དང pubspec ཡི་ཚད་བཀག་དང་བསྡུར།",
    "Flutter roots only. Choose Android / iOS / HarmonyOS with fzf in CMD. Supports APK / AAB and HAP / APP. iOS requires MacOS and Xcode.": "Flutter ལས་གཞིའི་རྩ་བའི་དཀར་ཆག་ཁོ་ན། CMD ནང fzf ཡིས Android / iOS / HarmonyOS འདེམས། APK / AAB དང HAP / APP རྒྱབ་སྐྱོར་བྱེད། iOS ལ MacOS དང Xcode དགོས།",
    "Flutter roots only. Choose a device and view logs in CMD; the app continues in the background after the window closes.": "Flutter ལས་གཞིའི་རྩ་བའི་དཀར་ཆག་ཁོ་ན། CMD ནང་སྒྲིག་ཆས་འདེམས་ནས་ཟིན་ཐོ་ལྟ། སྒེའུ་ཁུང་བཀག་རྗེས་ཀྱང་ཉེར་སྤྱོད་རྒྱབ་ལྗོངས་སུ་མུ་མཐུད་ལག་བསྟར་བྱེད།",
    "Flutter roots only. Read-only version and doctor diagnostics in terminal; no dependency fetching, cleanup, or tool upgrades.": "Flutter ལས་གཞིའི་རྩ་བའི་དཀར་ཆག་ཁོ་ན། མཐའ་སྣེར་པར་གཞི་དང doctor ཀློག་ཙམ་གྱི་བརྟག་དཔྱད་བྱེད། བརྟེན་འབྲེལ་ལེན་པ་དང་གཙང་སེལ་དང་ལག་ཆ་རིམ་སྤར་མི་བྱེད།",
    "Flutter roots only. Preview configured generators, then fetch dependencies and generate code after confirmation. Deleting conflicts requires separate opt-in.": "Flutter ལས་གཞིའི་རྩ་བའི་དཀར་ཆག་ཁོ་ན། སྒྲིག་ཟིན་པའི་སྐྱེད་ཆས་སྔོན་ལྟ་བྱས་ནས་གཏན་འཁེལ་རྗེས་བརྟེན་འབྲེལ་ལེན་ཞིང་ཚབ་ཨང་སྐྱེད། འགལ་ཟླའི་ཡིག་ཆ་སུབ་ན་ལོགས་སུ་ཆོག་མཆན་དགོས།",
    "Git worktree folders only. Detect nested repositories. Soft mode preserves the index and worktree; hard mode requires exact YES confirmation.": "Git ལས་ཀའི་སྡོང་པོའི་དཀར་ཆག་ཁོ་ན། ནང་བཅུག་མཛོད་ཁང་འཚོལ། soft ཐབས་ཀྱིས་གནས་སྐབས་ས་ཁུལ་དང་ལས་ཀའི་སྡོང་པོ་ཉར། hard ཐབས་ལ YES ཏག་ཏག་བྲིས་ནས་གཏན་འཁེལ་དགོས།",
    "Desktop background on x64 Windows only. Missing tools come from the SDL mirror; missing system images come from the official Emulator. Enter selects a stable phone image; confirm its license to create and start a unique instance.": "x64 Windows ཡི་ཅོག་ངོས་རྒྱབ་ལྗོངས་ཁོ་ན། ཆད་པའི་ལག་ཆ SDL མེ་ལོང་ནས་ལེན། ཆད་པའི་མ་ལག་གཟུགས་བརྙན་གཞུང་ཕྱོགས Emulator ནས་ལེན། Enter ཡིས་བརྟན་པའི་ཁ་པར་གཟུགས་བརྙན་འདེམས། ཆོག་མཆན་གཏན་འཁེལ་ནས་མིང་མི་འདྲ་བའི་དཔེ་གསར་བཟོ་ཞིང་འགོ་སློང་།",
    "Manage only this package's actions. Unselected actions remain when uninstalling.": "ཐུམ་སྒྲིལ་འདིའི་བྱ་བ་ཁོ་ན་དོ་དམ། སྒྲིག་འཇུག་སུབ་སྐབས་མ་འདེམས་པའི་བྱ་བ་ཉར།",
    "Desktop background only. Configure user-level Git to prefer the system proxy and fall back to a direct connection.": "ཅོག་ངོས་རྒྱབ་ལྗོངས་ཁོ་ན། སྤྱོད་མཁན་རིམ་པའི Git ལ་མ་ལག་གི་ཚབ་སྦྲེལ་སྔོན་འདེམས་བྱས་ནས་མི་འགྲུབ་ཚེ་ཐད་སྦྲེལ་ལ་ཕྱིར་ལོག་པར་སྒྲིག",
    "Desktop background only. Diagnose the SDK in CMD, choose a device and system image, then create or start an Android AVD.": "ཅོག་ངོས་རྒྱབ་ལྗོངས་ཁོ་ན། CMD ནང SDK བརྟག་དཔྱད་བྱས་ནས་སྒྲིག་ཆས་དང་མ་ལག་གཟུགས་བརྙན་འདེམས། དེ་ནས Android AVD གསར་བཟོ་ཡང་ན་འགོ་སློང་།",
    "Desktop background only. Check existing DevEco Emulator instances, then start one or confirm a nondestructive restart. Data is preserved.": "ཅོག་ངོས་རྒྱབ་ལྗོངས་ཁོ་ན། ཡོད་ཟིན་པའི DevEco Emulator དཔེ་བཤེར་ནས་གཅིག་འགོ་སློང་ཡང་ན་གནོད་མེད་བསྐྱར་འགོ་སློང་གཏན་འཁེལ། གཞི་གྲངས་ཉར།",
    "Desktop background only. Check emulator location and /data; optionally reset caches, precisely uninstall, back up the AVD, and retest with a cold boot.": "ཅོག་ངོས་རྒྱབ་ལྗོངས་ཁོ་ན། ལད་མོའི་འཕྲུལ་ཆས་ཀྱི་གནས་ཡུལ་དང /data བཤེར། གདམ་ཀ་ལྟར་གནས་སྐབས་གསོག་འཇོག་བསྐྱར་སྒྲིག་དང་གནད་འཕིགས་སྒྲིག་འཇུག་སུབ་པ་དང AVD གྲབས་ཉར་བྱས་ནས་འཁྱག་འགོ་སློང་གིས་བསྐྱར་ཚོད་བྱེད།",
    "Show the next action on the desktop background. Toggle hidden files for the current user's Explorer without changing protected-system-file settings.": "ཅོག་ངོས་རྒྱབ་ལྗོངས་སུ་རྗེས་མའི་བྱ་བ་མངོན། ད་ལྟའི་སྤྱོད་མཁན་གྱི Explorer ནང་སྦས་པའི་ཡིག་ཆ་མངོན་སྦས་བརྗེ། སྲུང་སྐྱོབ་མ་ལག་ཡིག་ཆའི་སྒྲིག་འགོད་མི་སྒྱུར།",
    "Visible only for nonempty native Android or valid Flutter (official / HarmonyOS) project roots. Validated again before opening.": "ནང་དོན་སྟོང་མིན་པའི་གདོད་མའི Android ཡང་ན་ནུས་ལྡན Flutter（གཞུང་ཕྱོགས / HarmonyOS）ལས་གཞིའི་རྩ་བའི་དཀར་ཆག་ཁོ་ནར་མངོན། ཁ་མ་ཕྱེ་གོང་བསྐྱར་དུ་བདེན་དཔང་བྱེད།",
    "Preview: the selection is shown in the log. No installation or uninstallation was performed.": "སྔོན་ལྟ། འདེམས་པ་ཟིན་ཐོར་མངོན། སྒྲིག་འཇུག་དང་སྒྲིག་འཇུག་སུབ་པ་གང་ཡང་མ་བྱས།",
    "Preview only. Confirming displays the selection in the log without installing, uninstalling, or writing state or registry entries.": "སྔོན་ལྟ་ཁོ་ན། གཏན་འཁེལ་ན་འདེམས་པ་ཟིན་ཐོར་མངོན། སྒྲིག་འཇུག་དང་སྒྲིག་འཇུག་སུབ་པ་མི་བྱེད། གནས་བབ་དང་ཐོ་འགོད་མཛོད་ལའང་མི་འབྲི།",
    "Deployed copies use their bound location. To change it, open the manager from the source directory. Default installations run in the current user's LocalAppData; local builds run under this package's work directory and stop working if it moves.": "བཀྲམ་ཟིན་པའི་འདྲ་བཤུས་ཀྱིས་བསྡམས་པའི་གནས་ཡུལ་སྤྱོད། བརྗེ་ན་འབྱུང་ཁུངས་དཀར་ཆག་ནས་དོ་དམ་ཆས་ཁ་ཕྱེ། སོར་བཞག་སྒྲིག་འཇུག་ད་ལྟའི་སྤྱོད་མཁན་གྱི LocalAppData ནང་ལག་བསྟར། རང་སའི་བཟོ་སྐྲུན་ཐུམ་སྒྲིལ་འདིའི་ལས་ཀའི་དཀར་ཆག་འོག་ལག་བསྟར་ཞིང་དཀར་ཆག་སྤོས་ན་ནུས་པ་ཤོར།",
    "Prefer Windows Terminal; otherwise use system PowerShell.": "Windows Terminal སྔོན་འདེམས་བྱེད། མེད་ན་མ་ལག་གི PowerShell སྤྱོད།",
    "Could not save preferences: ": "འདེམས་སྒྲིག་ཉར་མ་ཐུབ། ",
    "Save settings": "སྒྲིག་འགོད་ཉར།",
    "Protect local changes. On conflict, choose to restore, discard changes, or commit and retry.": "རང་སའི་བསྒྱུར་བཅོས་སྲུང་། འགལ་ཟླ་བྱུང་ན་སླར་གསོ་དང་བསྒྱུར་བཅོས་དོར་བ་ཡང་ན commit བྱས་རྗེས་བསྐྱར་ཚོད་འདེམས།",
    "All operations completed. Copy the log or close the panel.": "བྱ་བ་ཚང་མ་གྲུབ་ཟིན། ཟིན་ཐོ་འདྲ་བཤུས་བྱེད་ཡང་ན་འདེམས་ངོས་ཁ་རྒྱག",
    "Other context-menu features": "གཡས་མཐེབ་འདེམས་ཐོའི་བྱེད་ནུས་གཞན།",
    "Create or synchronize the code map for the current directory.": "ད་ལྟའི་དཀར་ཆག་གི་ཚབ་ཨང་ས་ཁྲ་གསར་བཟོ་ཡང་ན་མཉམ་བགྲོད།",
    "Feature and log divider": "བྱེད་ནུས་དང་ཟིན་ཐོའི་དབྱེ་ཐིག",
    "Select features, then confirm. Unselected features remain. Hover for installation details.": "བྱེད་ནུས་འདེམས་ནས་གཏན་འཁེལ། མ་འདེམས་པའི་བྱེད་ནུས་ཉར། སྟོན་མདའ་སྟེང་དུ་བཞག་ན་སྒྲིག་འཇུག་གི་ཞིབ་ཆ་མངོན།",
    "Checked features are installed; unchecked ones are uninstalled. Saving an empty selection disables all installed features.": "བདམས་པའི་བྱེད་ནུས་སྒྲིག་འཇུག་བྱེད། མ་བདམས་པ་སྒྲིག་འཇུག་སུབ། འདེམས་ཐོ་སྟོང་པ་ཉར་ན་སྒྲིག་འཇུག་ཟིན་པའི་བྱེད་ནུས་ཚང་མ་འགོག",
    "Select features to install. Enabled sibling actions and other unselected features remain.": "སྒྲིག་འཇུག་བྱ་རྒྱུའི་བྱེད་ནུས་འདེམས། མཉམ་རིམ་གྱི་སྤྱོད་འགོ་ཚུགས་པའི་བྱ་བ་དང་མ་འདེམས་པའི་བྱེད་ནུས་གཞན་ཉར།",
    "Total uninstall time": "སྒྲིག་འཇུག་སུབ་པའི་སྤྱིའི་དུས་ཚོད།",
    "Uninstall selected": "བདམས་པ་སྒྲིག་འཇུག་སུབ།",
    "Uninstall selected features": "བདམས་པའི་བྱེད་ནུས་སྒྲིག་འཇུག་སུབ།",
    "Uninstall time": "སྒྲིག་འཇུག་སུབ་པའི་དུས་ཚོད།",
    "Cancel": "མེད་པར་བཟོ།",
    "Uninstall only selected installed features. Other features, logs, backups and tools remain.": "བདམས་པའི་སྒྲིག་འཇུག་ཟིན་པའི་བྱེད་ནུས་ཁོ་ན་སུབ། བྱེད་ནུས་གཞན་དང་ཟིན་ཐོ་དང་གྲབས་ཉར་དང་ལག་ཆ་ཉར།",
    "Change only the current user's ExecuteFile ACL for a single regular NTFS file after confirmation. Does not launch the file or change global policy.": "གཏན་འཁེལ་རྗེས་རྒྱུན་ལྡན NTFS ཡིག་ཆ་གཅིག་ལ་ད་ལྟའི་སྤྱོད་མཁན་གྱི ExecuteFile ACL ཁོ་ན་སྒྱུར། ཡིག་ཆ་མི་འགོ་སློང་ཞིང་སྤྱི་ཡོངས་སྲིད་ཇུས་མི་སྒྱུར།",
    "View a single regular file. Files over 1 MiB or suspected binary files require YES in the terminal.": "རྒྱུན་ལྡན་ཡིག་ཆ་གཅིག་ལྟ། 1 MiB ལས་ཆེ་བ་ཡང་ན་གཉིས་གོང་ཡིག་ཆ་ཡིན་སྙམ་པ་ལ་མཐའ་སྣེར YES འབྲི་དགོས།",
    "Clean only the selected packages' build workspaces. Installed DLLs, scripts, settings and registry entries remain.": "བདམས་པའི་ཐུམ་སྒྲིལ་གྱི་བཟོ་སྐྲུན་ལས་ཁུལ་ཁོ་ན་གཙང་སེལ། སྒྲིག་འཇུག་ཟིན་པའི DLL དང་འཁྲབ་གཞུང་དང་སྒྲིག་འགོད་དང་ཐོ་འགོད་མཛོད་ཀྱི་ཚན་པ་ཉར།",
    "Copy full log": "ཟིན་ཐོ་ཆ་ཚང་འདྲ་བཤུས།",
    "Copy the original remote URL for the current branch.": "ད་ལྟའི་ཡལ་གའི་ཐོག་མའི་རྒྱང་འབྲེལ URL འདྲ་བཤུས།",
    "Copy the absolute path of a file or folder.": "ཡིག་ཆ་ཡང་ན་དཀར་ཆག་གི་ལྟོས་མེད་འགྲོ་ལམ་འདྲ་བཤུས།",
    "Could not copy the log: ": "ཟིན་ཐོ་འདྲ་བཤུས་མ་ཐུབ། ",
    "Failed — open log": "ཕམ་སོང་། — ཟིན་ཐོ་ཁ་ཕྱེ།",
    "Install / update": "སྒྲིག་འཇུག / གསར་སྒྱུར།",
    "Install / update selected features": "བདམས་པའི་བྱེད་ནུས་སྒྲིག་འཇུག / གསར་སྒྱུར།",
    "Total install time": "སྒྲིག་འཇུག་གི་སྤྱིའི་དུས་ཚོད།",
    "Install time": "སྒྲིག་འཇུག་གི་དུས་ཚོད།",
    "Merge appears for a complete selected volume set; split appears for one regular file. Originals are always preserved.": "ཡོངས་ཚང་གི་ཆ་ཤས་ཚང་མ་བདམས་ན་མཉམ་སྒྲིལ་མངོན། རྒྱུན་ལྡན་ཡིག་ཆ་གཅིག་བདམས་ན་ཁ་བྲལ་མངོན། མ་ཡིག་རྟག་ཏུ་ཉར།",
    "Live log (drag the divider to resize)": "དུས་ཐོག་ཟིན་ཐོ（དབྱེ་ཐིག་འདྲུད་ནས་མཐོ་ཚད་སྒྱུར）།",
    "Installation stopped after the current package transaction. Unstarted items are marked Not run.": "ད་ལྟའི་ཐུམ་སྒྲིལ་གྱི་བྱ་ཚན་གྲུབ་རྗེས་སྒྲིག་འཇུག་བཀག་ཟིན། འགོ་མ་ཚུགས་པའི་ཚན་པར་ལག་བསྟར་མ་བྱས་ཞེས་རྟགས་བཀོད།",
    "Stop requested. Waiting for the current package transaction; later items will not run.": "བཀག་འགོག་རེ་ཞུ་བྱས་ཟིན། ད་ལྟའི་ཐུམ་སྒྲིལ་བྱ་ཚན་གྲུབ་པར་སྒུག རྗེས་མའི་ཚན་པ་ལག་བསྟར་མི་བྱེད།",
    "Selected {0} / {1}. Closing or cancelling makes no changes.": "བདམས་པ {0} / {1}། ཁ་རྒྱག་པ་ཡང་ན་མེད་པར་བཟོས་ན་བསྒྱུར་བཅོས་མི་བྱེད།",
    "Hover for feature details. Windows 11: right-click → Show more options.": "སྟོན་མདའ་སྟེང་དུ་བཞག་ན་བྱེད་ནུས་ཀྱི་ཞིབ་ཆ་མངོན། Windows 11: གཡས་མཐེབ → གདམ་ཀ་མང་བ་མངོན།",
    "Could not open the full log: ": "ཟིན་ཐོ་ཆ་ཚང་ཁ་ཕྱེ་མ་ཐུབ། ",
    "Open the repository website for the current Git worktree.": "ད་ལྟའི Git ལས་ཀའི་སྡོང་པོའི་མཛོད་ཁང་དྲ་ཚིགས་ཁ་ཕྱེ།",
    "Open the solution or project at the current directory level.": "ད་ལྟའི་དཀར་ཆག་རིམ་པའི་སྤྱི་ལས་གཞི་ཡང་ན་ལས་གཞི་ཁ་ཕྱེ།",
    "Export resolved third-party Pub sources and licenses from the project lockfile. Press Enter to use the desktop as output.": "ལས་གཞིའི་ཟྭ་ཡིག་ནས་ཐག་ཆོད་ཟིན་པའི་ཕྱོགས་གསུམ་པའི Pub འབྱུང་ཁུངས་དང་ཆོག་མཆན་ཕྱིར་འདྲེན། Enter མནན་ན་ཅོག་ངོས་ཕྱིར་འདོན་གནས་སུ་སྤྱོད།",
    "An operation is running. Wait for the transaction to finish before closing. Logs can be copied at any time.": "བྱ་བ་ཞིག་ལག་བསྟར་བཞིན་ཡོད། བྱ་ཚན་གྲུབ་རྗེས་ད་གཟོད་ཁ་རྒྱག ཟིན་ཐོ་དུས་ནམ་ཡང་འདྲ་བཤུས་བྱས་ཆོག",
    "Could not build the operation plan: ": "བྱ་བའི་འཆར་གཞི་བཟོ་མ་ཐུབ། ",
    "Could not start the operation: ": "བྱ་བ་འགོ་སློང་མ་ཐུབ། ",
    "Log: ": "ཟིན་ཐོ། ",
    "🈶 Repair Chinese paths in Flutter project": "🈶 Flutter ལས་གཞིའི་རྒྱ་ཡིག་འགྲོ་ལམ་ཉམས་གསོ།",
    "Not installed; nothing to uninstall": "སྒྲིག་འཇུག་མ་བྱས། སུབ་རྒྱུ་མེད།",
    "Not installed": "སྒྲིག་འཇུག་མ་བྱས།",
    "Not run": "ལག་བསྟར་མ་བྱས།",
    "This feature": "བྱེད་ནུས་འདི།",
    "Local build directory (moving or cleaning it disables the menu)": "རང་སའི་བཟོ་སྐྲུན་དཀར་ཆག（སྤོ་བ་ཡང་ན་གཙང་སེལ་བྱས་ན་འདེམས་ཐོ་ནུས་མེད་འགྱུར）།",
    "Validate the branch, staging area and upstream, then confirm the push.": "ཡལ་ག་དང་གནས་སྐབས་ས་ཁུལ་དང་གོང་རིམ་བདེན་དཔང་བྱས་རྗེས་སྐྱེལ་འབུལ་གཏན་འཁེལ།",
    "Validate the Flutter project, then fetch dependencies.": "Flutter ལས་གཞི་བདེན་དཔང་བྱས་རྗེས་བརྟེན་འབྲེལ་ལེན།",
    "Installing / updating…": "སྒྲིག་འཇུག / གསར་སྒྱུར་བཞིན…",
    "This entry has been removed. Existing installations can be uninstalled but cannot be reinstalled.": "འཇུག་སྒོ་འདི་བསུབས་ཟིན། ཡོད་ཟིན་པའི་སྒྲིག་འཇུག་སུབ་ཆོག་ཀྱང་བསྐྱར་དུ་སྒྲིག་འཇུག་མི་ཐུབ།",
    "No features require processing; ": "ཐག་གཅོད་དགོས་པའི་བྱེད་ནུས་མེད། ",
    "No features require processing. No settings were changed.": "ཐག་གཅོད་དགོས་པའི་བྱེད་ནུས་མེད། སྒྲིག་འགོད་གང་ཡང་མ་བསྒྱུར།",
    "Total cleanup time": "གཙང་སེལ་གྱི་སྤྱིའི་དུས་ཚོད།",
    "Cleanup time": "གཙང་སེལ་གྱི་དུས་ཚོད།",
    "Click to read the full session log in a new PowerShell window. The current task continues.": "མནན་ནས PowerShell སྒེའུ་ཁུང་གསར་པར་ཐེངས་འདིའི་ཟིན་ཐོ་ཆ་ཚང་ཀློག ད་ལྟའི་ལས་འགན་མུ་མཐུད་ལག་བསྟར་བྱེད།",
    "Pending": "ཐག་གཅོད་ལ་སྒུག་བཞིན།",
    "Waiting to stop…": "བཀག་འགོག་ལ་སྒུག་བཞིན…",
    "Ordered Flutter development, diagnostics, repair and maintenance tools. Regular actions use project FVM; environment setup supports FVM / system Flutter and jEnv / system Java.": "གོ་རིམ་ལྡན་པའི Flutter གསར་སྤེལ་དང་བརྟག་དཔྱད་དང་ཉམས་གསོ་དང་བདག་སྐྱོང་ལག་ཆ། རྒྱུན་ལྡན་བྱ་བར་ལས་གཞིའི FVM སྤྱོད། ཁོར་ཡུག་སྒྲིག་འགོད་ལ FVM / མ་ལག་གི Flutter དང jEnv / མ་ལག་གི Java རྒྱབ་སྐྱོར་བྱེད།",
    "Detect the Flutter / Android project and preview cleanup scope. iOS cleanup is unavailable on Windows.": "Flutter / Android ལས་གཞི་འཚོལ་ནས་གཙང་སེལ་ཁྱབ་ཁོངས་སྔོན་ལྟ། Windows ནང iOS གཙང་སེལ་མི་ཐུབ།",
    "Could not read preferences: ": "འདེམས་སྒྲིག་ཀློག་མ་ཐུབ། ",
    "Could not read the log: ": "ཟིན་ཐོ་ཀློག་མ་ཐུབ། ",
    "Explorer context-menu extensions · ": "Explorer གཡས་མཐེབ་འདེམས་ཐོའི་རྒྱ་སྐྱེད · ",
    "Explorer extensions · Manage": "Explorer རྒྱ་སྐྱེད · དོ་དམ།",
    "Return selection": "འདེམས་པ་ཕྱིར་སྤྲོད།",
    "Exit code: ": "ཕྱིར་ཐོན་ཨང་། ",
    "Choose an operation and select features. Unselected features remain; only installed features can be uninstalled.": "བྱ་བ་དང་བྱེད་ནུས་འདེམས། མ་འདེམས་པའི་བྱེད་ནུས་ཉར། སྒྲིག་འཇུག་ཟིན་པའི་བྱེད་ནུས་ཁོ་ན་སྒྲིག་འཇུག་སུབ་ཆོག",
    "Some features failed; other selected features were still processed. Click a failed status to open the full session log.": "བྱེད་ནུས་ཁ་ཤས་ཕམ་སོང་ཡང་བདམས་པའི་བྱེད་ནུས་གཞན་མུ་མཐུད་ཐག་གཅོད་བྱས། ཕམ་པའི་གནས་བབ་མནན་ནས་ཐེངས་འདིའི་ཟིན་ཐོ་ཆ་ཚང་ཁ་ཕྱེ།",
    "Available for nonempty regular directories outside iOS projects, including Flutter roots. Validated again before opening.": "iOS ལས་གཞི་མིན་པའི་ནང་དོན་སྟོང་མིན་རྒྱུན་ལྡན་དཀར་ཆག་ལ་སྤྱོད་ཆོག Flutter རྩ་བའི་དཀར་ཆག་ཀྱང་ཚུད། ཁ་མ་ཕྱེ་གོང་བསྐྱར་དུ་བདེན་དཔང་བྱེད།",
    "Default installation location (recommended)": "སོར་བཞག་སྒྲིག་འཇུག་གནས་ཡུལ（འོས་སྦྱོར）།",
    "{0}; Results: succeeded {1}; nothing to uninstall {2}; failed {3}; not run {4}": "{0}། འབྲས་བུ། ལེགས་གྲུབ {1}། སུབ་རྒྱུ་མེད {2}། ཕམ་པ {3}། ལག་བསྟར་མ་བྱས {4}",
    "{0} Exit code: {1}.": "{0} ཕྱིར་ཐོན་ཨང་། {1}།",
    "{0} {1}": "{0} {1}",
    "{0}{1} {2}": "{0}{1} {2}",
    "{0} in progress; completed {1} / {2} ({3}% by completed items); {4} {5}": "{0} བྱེད་བཞིན། གྲུབ་པ {1} / {2}（གྲུབ་པའི་ཚན་པ་ལྟར {3}%）། {4} {5}",
    "{0} Completed {1} / {2} ({3}% by completed items); {4} {5}": "{0} གྲུབ་པ {1} / {2}（གྲུབ་པའི་ཚན་པ་ལྟར {3}%）། {4} {5}",
    "🫥 Hide / show selected items": "🫥 བདམས་པའི་རྣམ་གྲངས་སྦེད / སྟོན།",
    "Set the Hidden attribute of selected files or folders, including multiple selections; do not recurse, rename, or change global visibility preferences.": "བདམས་པའི་ཡིག་ཆ་དང་སྣོད་ཀྱི་སྦས་པའི་ཁྱད་ཆོས་སྒྲིག མང་པོ་འདེམས་ཆོག ནང་གསེས་མི་བསྒྱུར། མིང་དང་སྤྱིའི་མངོན་སྟངས་མི་བསྒྱུར།",
    "Permanently delete (skip Recycle Bin)": "རྒྱུན་གཏན་དུ་སུབ་པ།",
    "Directly delete selected files or folders; confirm with the red left button or cancel with the blue right button. Cancellation is the default; deleted items cannot be restored from the Recycle Bin.": "བདམས་པའི་ཡིག་ཆ་དང་ཡིག་སྣོད་ཐད་ཀར་སུབ། གཡོན་གྱི་མཐེབ་དམར་པོས་གཏན་འཁེལ་དང་གཡས་ཀྱི་མཐེབ་སྔོན་པོས་དོར་བ། སོར་བཞག་ནི་དོར་བ་ཡིན། སུབ་ཟིན་པ་གད་སྙིགས་སྒམ་ནས་སླར་གསོ་མི་ཐུབ།"
  },
  "ja": {
    "Close management panel": "管理パネルを閉じる",
    "Minimize to tray": "通知領域に格納",
    "Exit completely": "完全に終了",
    "Keep window open": "ウィンドウを開いたままにする",
    "The manager is idle. Keep it in the system tray, or exit completely.": "現在、処理はありません。通知領域に格納して保持するか、完全に終了してください。",
    "Show management panel": "管理パネルを表示",
    "Current status": "現在の状態",
    "A task is running. Exit is unavailable; restore the window to view logs.": "処理中のため完全には終了できません。ウィンドウを復元するとログを確認できます。",
    "The system tray is unavailable. The window will remain open.": "通知領域を表示できません。ウィンドウは開いたままになります。",
    "💽 Disk free space": "💽 ディスク空き容量",
    "Show total local disk free / capacity and a two-decimal percentage. Click to choose cleanup in a separate terminal; changes require confirmation.": "ローカルディスクの空き容量合計 / 総容量と小数点以下2桁の割合を表示します。クリックすると別のターミナルでクリーンアップを選択でき、確認後に実行します。",
    "Create script launcher…": "スクリプト起動ファイルを作成…",
    "🔗 Create script launcher…": "🔗 スクリプト起動ファイルを作成…",
    "Create a relative launcher beside a same-name .cmd/.bat/.ps1 script folder; do not run or modify the source script.": "同名の .cmd/.bat/.ps1 スクリプトフォルダの横に相対パスの起動ファイルを作成します。元のスクリプトは実行・変更しません。",
    "Theme": "テーマ",
    "Language": "言語",
    "🎨 Theme": "🎨 テーマ",
    "🌐 Language": "🌐 言語",
    "Follow system": "システムに従う",
    "Dark": "ダーク",
    "Light": "ライト",
    "Jobs Finder Extension Manager": "Jobs Finder 拡張機能マネージャー",
    "Customize Finder Context Menu": "Finder コンテキストメニューをカスタマイズ",
    "Close Manager": "マネージャーを閉じる",
    "Edit": "編集",
    "Copy": "コピー",
    "Select all": "すべて選択",
    "Clear all": "選択をすべて解除",
    "Close": "閉じる",
    "OK": "OK",
    "Install": "インストール",
    "Install / Update": "インストール / 更新",
    "Uninstall": "アンインストール",
    "Cleanup": "クリーンアップ",
    "Clean build products": "ビルド生成物を削除",
    "🧹 Clean build products": "🧹 ビルド生成物を削除",
    "Stop installation": "インストールを停止",
    "Stopping…": "停止中…",
    "Action: install / update or uninstall": "操作：インストール / 更新またはアンインストール",
    "Uninstall removes selected menus only. Group selection affects its own group.": "選択したメニューのみを削除します。グループ内の選択はそのグループのみに適用されます。",
    "Install / uninstall with the combined App in Applications": "アプリケーション内の統合 App でインストール / アンインストール",
    "Install or uninstall the combined App in Applications": "アプリケーション内の統合 App をインストールまたはアンインストール",
    "Selected: manage features in /Applications/Jobs自定义右键菜单.app. Otherwise use the build directory.": "選択時は /Applications/Jobs自定义右键菜单.app 内の機能を管理します。未選択時はビルドディレクトリを使用します。",
    "Clean this build after successful installation": "インストール成功後に今回のビルドを削除",
    "Clean this build only after the combined App is installed and verified in Applications. Keep failed builds.": "統合 App をアプリケーションにインストールして検証した後のみ、今回のビルドを削除します。失敗したビルドは保持します。",
    "Clean build products of selected features without installing or uninstalling.": "選択した機能のビルド生成物のみを削除します。インストールやアンインストールは行いません。",
    "Clean selected features' build products": "選択した機能のビルド生成物を削除",
    "Open Privacy & Security": "プライバシーとセキュリティを開く",
    "Add and enable Jobs右键菜单管理面板.app in Privacy & Security → App Management. This only opens Settings.": "「プライバシーとセキュリティ → App 管理」で Jobs右键菜单管理面板.app を追加して有効にしてください。このボタンは設定のみを開きます。",
    "Target: build directory. Cleaning these products affects installed features.": "対象：ビルドディレクトリ。生成物を削除すると、インストール済み機能に影響します。",
    "App: Jobs自定义右键菜单.app at /Applications/Jobs自定义右键菜单.app (build products can be cleaned after installation)": "App：/Applications/Jobs自定义右键菜单.app（インストール後にビルド生成物を削除可能）",
    "Drag the divider to resize the log. Features and logs scroll separately.": "区切り線を上下にドラッグしてログの高さを調整します。機能とログは個別にスクロールできます。",
    "Feature list and live log divider": "機能一覧とリアルタイムログの区切り線",
    "Live log (select and copy text)": "リアルタイムログ（文字を選択してコピー可能）",
    "Copy log": "ログをコピー",
    "Log file": "ログファイル",
    "Auto-scroll": "自動スクロール",
    "Ready. Select features and choose an action.": "準備完了。機能を選択して操作ボタンを押してください。",
    "A task is running. Wait for it to finish before closing.": "タスクを実行中です。完了してから閉じてください。",
    "Unable to view this log": "このログを表示できません",
    "Log is missing or unreadable: {0}": "ログが存在しないか、読み取れません：{0}",
    "Unable to open log terminal: {0}": "ログ用ターミナルを開けません：{0}",
    "Click to show this session's full log in a new terminal: {0}": "クリックすると、このセッションの完全なログを新しいターミナルに表示します：{0}",
    "Selected {0} / {1}. Select at least one. Changing action keeps selection.": "{0} / {1} 件を選択。1 件以上選択してください。操作を切り替えても選択は保持されます。",
    "Selected {0} / {1}": "{0} / {1} 件を選択",
    "{0}: select all": "{0}：すべて選択",
    "{0}: clear all": "{0}：選択をすべて解除",
    "Waiting": "待機中",
    "Cleaning…": "クリーンアップ中…",
    "Uninstalling…": "アンインストール中…",
    "Installing…": "インストール中…",
    "Cleaned": "削除済み",
    "Uninstalled": "アンインストール済み",
    "Installed": "インストール済み",
    "Skipped": "未実行",
    "Not installed; nothing to remove": "未インストール：削除不要",
    "Failed: see log": "失敗：ログを確認",
    "Selected": "選択済み",
    "Not selected": "未選択",
    "App Management permission required": "App 管理権限が必要です",
    "Permission check required": "権限の確認が必要です",
    "Stopped": "停止済み",
    "Completed": "完了",
    "Task failed": "タスク失敗",
    "{0}: processed {1} / {2} ({3}, completed items); {4} time {5}": "{0}：処理済み {1} / {2}（{3}、完了項目基準）；{4}時間 {5}",
    "{0} ready": "{0}の準備完了",
    "{0} ready; {1} time {2}": "{0}の準備完了；{1}時間 {2}",
    "Finishing the current feature, then stopping; install time {0}": "現在の機能を完了してから停止します；インストール時間 {0}",
    "{0}: {1} succeeded, {2} failed, {3} skipped; exit {4}; {5}; {6} time {7}": "{0}：成功 {1}、失敗 {2}、未実行 {3}；終了 {4}；{5}；{6}時間 {7}",
    "{0}: {1} succeeded, {2} failed, {3} not installed, {4} skipped; exit {5}; {6}; {7} time {8}": "{0}：成功 {1}、失敗 {2}、削除不要 {3}、未実行 {4}；終了 {5}；{6}；{7}時間 {8}",
    "{0}: {1} succeeded, {2} failed, {3} not installed; exit {4}; {5}; {6} time {7}": "{0}：成功 {1}、失敗 {2}、削除不要 {3}；終了 {4}；{5}；{6}時間 {7}",
    "{0}: {1} succeeded, {2} failed; exit {3}; {4}; {5} time {6}": "{0}：成功 {1}、失敗 {2}；終了 {3}；{4}；{5}時間 {6}",
    "Open projects in IDEs": "IDE でプロジェクトを開く",
    "Git tools": "Git ツール",
    "Files and general tools": "ファイルと共通ツール",
    "Flutter tools · submenu actions": "Flutter ツール・サブメニュー操作",
    "iOS / CocoaPods tools": "iOS / CocoaPods ツール",
    "Simulator tools": "シミュレーターツール",
    "Open project in Android Studio": "Android Studio でプロジェクトを開く",
    "Open project in VSCode": "VSCode でプロジェクトを開く",
    "Open project in Xcode": "Xcode でプロジェクトを開く",
    "Pull latest Git changes": "Git の最新変更を取得",
    "Roll back Git commit": "Git コミットを巻き戻す",
    "Open Git remote URL": "Git リモート URL を開く",
    "Copy Git remote URL": "Git リモート URL をコピー",
    "Copy absolute path": "絶対パスをコピー",
    "Create file": "ファイルを作成",
    "View file fingerprint Hash (SHA-256)": "ファイルのハッシュを表示（SHA-256）",
    "Grant execute permission (chmod +x)": "実行権限を付与（chmod +x）",
    "Remove execute permission (chmod -x)": "実行権限を削除（chmod -x）",
    "Re-sign IPA without building": "ビルドせずに IPA を再署名",
    "Show / hide files": "ファイルを表示 / 非表示",
    "Create iOS simulator": "iOS シミュレーターを作成",
    "Create Android simulator": "Android シミュレーターを作成",
    "Create Harmony simulator": "Harmony シミュレーターを作成",
    "Check / repair Android simulator": "Android シミュレーターを診断 / 修復",
    "Check / repair Harmony simulator": "Harmony シミュレーターを診断 / 修復",
    "Configure Git proxy": "Git プロキシを設定",
    "Open in terminal": "ターミナルで開く",
    "View file contents in terminal": "ターミナルでファイルの内容を表示",
    "Merge file parts": "分割ファイルを結合",
    "Split file": "ファイルを分割",
    "Clean Android / OpenHarmony builds": "Android / OpenHarmony ビルドを削除",
    "Update code map (.codegraph)": "コードマップを更新（.codegraph）",
    "Create empty commit and push in terminal": "ターミナルで空のコミットを作成して Push",
    "Disable CocoaPods build sandbox": "CocoaPods のビルドサンドボックスを無効化",
    "Install CocoaPods": "CocoaPods をインストール",
    "CocoaPods source: CDN → GitHub": "CocoaPods ソース：CDN → GitHub",
    "Export all project Pod files": "プロジェクトの全 Pod ファイルをエクスポート",
    "Inspect Xcode project dependencies": "Xcode プロジェクトの依存関係を確認",
    "Update local CocoaPods repositories": "ローカル CocoaPods リポジトリを更新",
    "Check local Pod builds (.podspec folder)": "ローカル Pod のビルドを確認（.podspec フォルダ）",
    "Install / update JobsCodeSnippets": "JobsCodeSnippets をインストール / 更新",
    "Clean iOS / Xcode builds": "iOS / Xcode ビルドを削除",
    "Set up Flutter project": "Flutter プロジェクトをセットアップ",
    "Run Flutter project in terminal": "Flutter プロジェクトをターミナルで実行",
    "Fetch Flutter Pub dependencies": "Flutter Pub の依存関係を取得",
    "Fetch native Android dependencies": "Android ネイティブの依存関係を取得",
    "Fetch CocoaPods dependencies": "CocoaPods の依存関係を取得",
    "Fetch Swift Package dependencies": "Swift Package の依存関係を取得",
    "Fetch OpenHarmony dependencies": "OpenHarmony の依存関係を取得",
    "Prepare native libraries and build dependencies": "ネイティブライブラリとビルド依存関係を準備",
    "Download Flutter platform resources": "Flutter プラットフォームリソースをダウンロード",
    "Fetch Web project dependencies": "Web プロジェクトの依存関係を取得",
    "🧳 Export Flutter dependencies": "🧳 Flutter の依存関係をエクスポート",
    "Export Flutter Pub dependencies": "Flutter Pub の依存関係をエクスポート",
    "🔐 Export private Flutter dependencies": "🔐 Flutter の非公開依存関係をエクスポート",
    "📥 Import Flutter dependencies": "📥 Flutter の依存関係をインポート",
    "Import Flutter Pub dependencies": "Flutter Pub の依存関係をインポート",
    "📥 Import private Flutter dependencies": "📥 Flutter の非公開依存関係をインポート",
    "Export Gradle distributions and cache": "Gradle 配布物とキャッシュをエクスポート",
    "Import Gradle distributions and cache": "Gradle 配布物とキャッシュをインポート",
    "Export CocoaPods dependencies": "CocoaPods の依存関係をエクスポート",
    "Import CocoaPods dependencies": "CocoaPods の依存関係をインポート",
    "Export Swift Package dependencies": "Swift Package の依存関係をエクスポート",
    "Import Swift Package dependencies": "Swift Package の依存関係をインポート",
    "Export OpenHarmony dependencies": "OpenHarmony の依存関係をエクスポート",
    "Import OpenHarmony dependencies": "OpenHarmony の依存関係をインポート",
    "Export native build cache": "ネイティブビルドキャッシュをエクスポート",
    "Import native build cache": "ネイティブビルドキャッシュをインポート",
    "Export Flutter platform resources": "Flutter プラットフォームリソースをエクスポート",
    "Import Flutter platform resources": "Flutter プラットフォームリソースをインポート",
    "Export Web dependencies": "Web の依存関係をエクスポート",
    "Import Web dependencies": "Web の依存関係をインポート",
    "Show Flutter project SDK version": "Flutter プロジェクトの SDK バージョンを表示",
    "Install / switch Flutter SDK": "Flutter SDK をインストール / 切り替え",
    "Install / switch Flutter@OpenHarmony SDK": "Flutter@OpenHarmony SDK をインストール / 切り替え",
    "Install / switch Java SDK": "Java SDK をインストール / 切り替え",
    "Download Gradle distributions and plugins": "Gradle 配布物とプラグインをダウンロード",
    "Generate Flutter code": "Flutter コードを生成",
    "Package iOS": "iOS をパッケージ化",
    "Package Android": "Android をパッケージ化",
    "Package Harmony (HAP + APP)": "Harmony をパッケージ化（HAP + APP）",
    "Check native Flutter project": "ネイティブ Flutter プロジェクトを診断",
    "Check OpenHarmony Flutter environment": "OpenHarmony Flutter 環境を診断",
    "Repair missing Android SDK / platforms": "不足している Android SDK / platforms を修復",
    "Repair Chinese Flutter project paths": "Flutter プロジェクトの中国語パスを修復",
    "Repair Flutter plugin namespaces": "Flutter プラグインの namespace を修復",
    "Convert relative Dart imports to packages": "Dart の相対 import を package 参照に変換",
    "Clean current Flutter project builds": "現在の Flutter プロジェクトのビルドを削除",
    "Dependency and cache maintenance": "依存関係とキャッシュのメンテナンス",
    "Custom Explorer context menu": "Explorer コンテキストメニューをカスタマイズ",
    "Jobs Windows · Custom Explorer context menu": "Jobs Windows · Explorer コンテキストメニューをカスタマイズ",
    "Show a regular file's SHA-256 in a new terminal and copy the digest; do not modify or execute the file.": "通常ファイルの SHA-256 を新しいターミナルに表示し、ハッシュ値をコピーします。ファイルの変更や実行は行いません。",
    " (preview)": "（プレビューのみ）",
    "⏪ Roll back Git commits": "⏪ Git コミットを巻き戻す",
    "▶️ Run Flutter project in terminal": "▶️ Flutter プロジェクトをターミナルで実行",
    "☕ Install / switch Java SDK": "☕ Java SDK をインストール / 切り替え",
    "♻️ Flutter cleanup and maintenance": "♻️ Flutter のクリーンアップと保守",
    "⚙️ Generate Flutter code": "⚙️ Flutter コードを生成",
    "✅ Installed": "✅ インストール済み",
    "⬇️ Pull latest Git changes": "⬇️ Git の最新変更を取得",
    "🌈 Create Harmony emulator": "🌈 Harmony エミュレーターを作成",
    "🌐 Open Git remote URL": "🌐 Git リモート URL を開く",
    "🌐 Fetch Web project dependencies": "🌐 Web プロジェクトの依存関係を取得",
    "🌳 Open in Sourcetree": "🌳 Sourcetree で開く",
    "🏥 Flutter project diagnostics": "🏥 Flutter プロジェクトの診断",
    "🏥 Flutter diagnostics": "🏥 Flutter 診断",
    "🏷️ Repair Flutter plugin namespaces": "🏷️ Flutter プラグインの namespace を修復",
    "👁️ Show / hide hidden files": "👁️ 隠しファイルを表示 / 非表示",
    "💓 OpenHarmony Flutter diagnostics": "💓 OpenHarmony Flutter の環境診断",
    "💠 Open project in Visual Studio": "💠 Visual Studio でプロジェクトを開く",
    "💻 Open in terminal": "💻 ターミナルで開く",
    "📄 View file in terminal": "📄 ターミナルでファイルを表示",
    "📋 Copy absolute path": "📋 絶対パスをコピー",
    "📚 Download Gradle distributions and build plugins": "📚 Gradle 配布物とビルドプラグインをダウンロード",
    "📝 Open project in VSCode": "📝 VSCode でプロジェクトを開く",
    "📡 Configure Git dynamic proxy": "📡 Git 動的プロキシを設定",
    "📤 Import Flutter Pub dependencies": "📤 Flutter Pub の依存関係をインポート",
    "📤 Import Flutter platform assets": "📤 Flutter プラットフォームアセットをインポート",
    "📤 Import Gradle distributions and dependency caches": "📤 Gradle 配布物と依存関係キャッシュをインポート",
    "📤 Import OpenHarmony dependencies": "📤 OpenHarmony の依存関係をインポート",
    "📤 Import Web dependencies": "📤 Web の依存関係をインポート",
    "📤 Import native build caches": "📤 ネイティブビルドキャッシュをインポート",
    "📤 Import Flutter project dependencies": "📤 Flutter プロジェクトの依存関係をインポート",
    "📤 Create empty commit and push": "📤 空のコミットを作成して Push",
    "📥 Install Flutter dependencies (pub get)": "📥 Flutter の依存関係をインストール（pub get）",
    "📥 Import private Flutter project dependencies": "📥 Flutter プロジェクトの非公開依存関係をインポート",
    "📥 Fetch Flutter Pub dependencies": "📥 Flutter Pub の依存関係を取得",
    "📥 Fetch Flutter project dependencies": "📥 Flutter プロジェクトの依存関係を取得",
    "📦 Package Flutter project": "📦 Flutter プロジェクトをパッケージ化",
    "📦 Package HarmonyOS (HAP + APP)": "📦 HarmonyOS をパッケージ化（HAP + APP）",
    "📱 Create Android emulator": "📱 Android エミュレーターを作成",
    "🔀 Install / switch Flutter SDK (FVM)": "🔀 Flutter SDK をインストール / 切り替え（FVM）",
    "🔀 Install / switch Flutter SDK": "🔀 Flutter SDK をインストール / 切り替え",
    "🔀 Install / switch Flutter environments": "🔀 Flutter 実行環境をインストール / 切り替え",
    "🔎 Show current Flutter SDK version": "🔎 現在の Flutter SDK バージョンを表示",
    "🔎 Show current Flutter project's SDK version": "🔎 現在の Flutter プロジェクトの SDK バージョンを表示",
    "🔐 Export private Flutter project dependencies": "🔐 Flutter プロジェクトの非公開依存関係をエクスポート",
    "🔎 Show file fingerprint Hash (SHA-256)": "🔎 ファイルのハッシュを表示（SHA-256）",
    "➕ Grant execute permission": "➕ 実行権限を付与",
    "➖ Remove execute permission": "➖ 実行権限を削除",
    "🔒 Grant execute permission": "🔒 実行権限を付与",
    "🔓 Remove execute permission": "🔓 実行権限を削除",
    "🔗 Copy Git remote URL": "🔗 Git リモート URL をコピー",
    "🔧 Flutter repairs": "🔧 Flutter の修復",
    "🕊️ Install / switch Flutter@OpenHarmony SDK": "🕊️ Flutter@OpenHarmony SDK をインストール / 切り替え",
    "🕊️ Fetch OpenHarmony dependencies": "🕊️ OpenHarmony の依存関係を取得",
    "🗃️ Download Flutter platform assets": "🗃️ Flutter プラットフォームアセットをダウンロード",
    "🗺️ Update code map (.codegraph)": "🗺️ コードマップを更新（.codegraph）",
    "🤖 Fetch Android native dependencies": "🤖 Android ネイティブの依存関係を取得",
    "🦋 Flutter development": "🦋 Flutter 開発",
    "🦋 Flutter development tools": "🦋 Flutter 開発ツール",
    "🧑‍⚕️ Native Flutter diagnostics": "🧑‍⚕️ ネイティブ Flutter の診断",
    "🧩 Export Flutter Pub dependencies": "🧩 Flutter Pub の依存関係をエクスポート",
    "🧩 Export Flutter platform assets": "🧩 Flutter プラットフォームアセットをエクスポート",
    "🧩 Export Flutter third-party dependencies": "🧩 Flutter のサードパーティ依存関係をエクスポート",
    "🧩 Export Gradle distributions and dependency caches": "🧩 Gradle 配布物と依存関係キャッシュをエクスポート",
    "🧩 Export OpenHarmony dependencies": "🧩 OpenHarmony の依存関係をエクスポート",
    "🧩 Export Web dependencies": "🧩 Web の依存関係をエクスポート",
    "🧩 Export native build caches": "🧩 ネイティブビルドキャッシュをエクスポート",
    "🧩 Export Flutter project dependencies": "🧩 Flutter プロジェクトの依存関係をエクスポート",
    "🧩 Merge file volumes / ✂️ Split file": "🧩 分割ファイルを結合 / ✂️ ファイルを分割",
    "🧭 Open project in Android Studio": "🧭 Android Studio でプロジェクトを開く",
    "🧯 Clean build output": "🧯 ビルド出力を削除",
    "🧰 Diagnose and repair Harmony emulator": "🧰 Harmony エミュレーターを診断して修復",
    "🧱 Flutter assets and build dependencies": "🧱 Flutter のアセットとビルド依存関係",
    "🧱 Prepare native libraries and build dependencies (combined)": "🧱 ネイティブライブラリとビルド依存関係を準備（組み合わせ）",
    "🧹 Clean build output": "🧹 ビルド出力を削除",
    "🩹 Repair missing Android SDK / platforms": "🩹 不足している Android SDK / platforms を修復",
    "🩺 Diagnose and repair Android emulator": "🩺 Android エミュレーターを診断して修復",
    "🚀 Set up Flutter project": "🚀 Flutter プロジェクトをセットアップ",
    "🚚 Import all Flutter dependencies": "🚚 Flutter の依存関係をすべてインポート",
    "🚚 Export all Flutter dependencies": "🚚 Flutter の依存関係をすべてエクスポート",
    "Jobs Windows · Uninstall Explorer extensions": "Jobs Windows · Explorer 拡張機能をアンインストール",
    "Jobs Windows · Install Explorer extensions": "Jobs Windows · Explorer 拡張機能をインストール",
    "Jobs Windows · Manage Explorer extensions": "Jobs Windows · Explorer 拡張機能を管理",
    "Jobs Windows · Configure Explorer extensions": "Jobs Windows · Explorer 拡張機能を設定",
    "Drag the divider vertically to resize the log": "区切り線を上下にドラッグしてログの高さを調整",
    "Drag vertically to resize the log": "上下にドラッグしてログの高さを調整",
    "Validate the Flutter project, diagnose the toolchain in terminal, and choose a Flutter SDK version with fzf.": "Flutter プロジェクトを検証し、ターミナルでツールチェーンを診断して、fzf で Flutter SDK バージョンを選択します。",
    "Validate the Flutter project, then show the active SDK version (project FVM or system SDK) in terminal and compare it with .fvmrc and pubspec constraints.": "Flutter プロジェクトを検証し、実際に使用中の SDK バージョン（プロジェクト FVM またはシステム SDK）をターミナルに読み取り専用で表示して、.fvmrc と pubspec の制約を確認します。",
    "Flutter roots only. Choose Android / iOS / HarmonyOS with fzf in CMD. Supports APK / AAB and HAP / APP. iOS requires MacOS and Xcode.": "Flutter ルートのみ表示します。CMD の fzf で Android / iOS / HarmonyOS を選択します。APK / AAB と HAP / APP に対応します。iOS には MacOS と Xcode が必要です。",
    "Flutter roots only. Choose a device and view logs in CMD; the app continues in the background after the window closes.": "Flutter ルートのみ表示します。CMD でデバイスを選択してログを表示します。ウィンドウを閉じても App はバックグラウンドで動作します。",
    "Flutter roots only. Read-only version and doctor diagnostics in terminal; no dependency fetching, cleanup, or tool upgrades.": "Flutter ルートのみ表示します。ターミナルでバージョンと doctor 診断を読み取り専用で実行します。依存関係の取得、削除、ツールの更新は行いません。",
    "Flutter roots only. Preview configured generators, then fetch dependencies and generate code after confirmation. Deleting conflicts requires separate opt-in.": "Flutter ルートのみ表示します。設定済みジェネレーターをプレビューし、確認後に依存関係の取得とコード生成を行います。競合ファイルの削除には個別の同意が必要です。",
    "Git worktree folders only. Detect nested repositories. Soft mode preserves the index and worktree; hard mode requires exact YES confirmation.": "Git ワークツリーフォルダのみ表示します。入れ子のリポジトリを認識します。soft はインデックスと作業内容を保持し、hard には正確な YES の確認が必要です。",
    "Desktop background on x64 Windows only. Missing tools come from the SDL mirror; missing system images come from the official Emulator. Enter selects a stable phone image; confirm its license to create and start a unique instance.": "x64 Windows のデスクトップ背景のみ表示します。不足するツールは SDL ミラーから、システムイメージは公式 Emulator から取得します。Enter で安定版の電話イメージを選び、ライセンスを確認して一意のインスタンスを作成・起動します。",
    "Manage only this package's actions. Unselected actions remain when uninstalling.": "このパッケージの操作のみを管理します。アンインストール時も未選択の操作は保持します。",
    "Desktop background only. Configure user-level Git to prefer the system proxy and fall back to a direct connection.": "デスクトップ背景のみ表示します。ユーザーレベルの Git を設定し、システムプロキシを優先して、失敗時は直接接続に切り替えます。",
    "Desktop background only. Diagnose the SDK in CMD, choose a device and system image, then create or start an Android AVD.": "デスクトップ背景のみ表示します。CMD で SDK を診断し、機種とシステムイメージを選択して Android AVD を作成または起動します。",
    "Desktop background only. Check existing DevEco Emulator instances, then start one or confirm a nondestructive restart. Data is preserved.": "デスクトップ背景のみ表示します。既存の DevEco Emulator とインスタンスを確認し、選択したものを起動するか、確認後にデータを保持して再起動します。",
    "Desktop background only. Check emulator location and /data; optionally reset caches, precisely uninstall, back up the AVD, and retest with a cold boot.": "デスクトップ背景のみ表示します。エミュレーターの場所と /data を確認します。任意でキャッシュのリセット、正確なアンインストール、AVD 全体のバックアップとコールドブートでの再テストを行えます。",
    "Show the next action on the desktop background. Toggle hidden files for the current user's Explorer without changing protected-system-file settings.": "デスクトップ背景に次の操作を表示します。現在のユーザーの Explorer で隠しファイルを切り替え、保護されたシステムファイルの設定は変更しません。",
    "Visible only for nonempty native Android or valid Flutter (official / HarmonyOS) project roots. Validated again before opening.": "空でないネイティブ Android または有効な Flutter（公式 / HarmonyOS）のプロジェクトルートのみ表示し、開く前にも検証します。",
    "Preview: the selection is shown in the log. No installation or uninstallation was performed.": "プレビューのみ：選択内容をログに表示しました。インストールやアンインストールは行っていません。",
    "Preview only. Confirming displays the selection in the log without installing, uninstalling, or writing state or registry entries.": "機能選択のプレビューのみです。確認すると下部ログに選択内容を表示します。インストール、アンインストール、状態やレジストリへの書き込みは行いません。",
    "Deployed copies use their bound location. To change it, open the manager from the source directory. Default installations run in the current user's LocalAppData; local builds run under this package's work directory and stop working if it moves.": "配布済みコピーは現在の配置先を使用します。変更するにはソースディレクトリからマネージャーを開いてください。既定では現在のユーザーの LocalAppData で単独実行し、ローカルビルドはパッケージの work 内で動作するため、移動すると機能しなくなります。",
    "Prefer Windows Terminal; otherwise use system PowerShell.": "Windows Terminal を優先し、利用できなければシステム PowerShell を使用します。",
    "Could not save preferences: ": "設定を保存できませんでした： ",
    "Save settings": "設定を保存",
    "Protect local changes. On conflict, choose to restore, discard changes, or commit and retry.": "ローカルの変更を保護します。競合時は復元、変更の破棄、またはコミット後に再試行を選択してください。",
    "All operations completed. Copy the log or close the panel.": "すべての処理が完了しました。ログをコピーするか、パネルを閉じてください。",
    "Other context-menu features": "その他のコンテキストメニュー機能",
    "Create or synchronize the code map for the current directory.": "現在のディレクトリのコードマップを作成または同期します。",
    "Feature and log divider": "機能とログの区切り線",
    "Select features, then confirm. Unselected features remain. Hover for installation details.": "機能を選択して確認してください。未選択の機能は保持されます。インストール状況はポインターを重ねると確認できます。",
    "Checked features are installed; unchecked ones are uninstalled. Saving an empty selection disables all installed features.": "選択した機能はインストールし、未選択の機能はアンインストールします。選択をすべて解除して保存すると、インストール済み機能をすべて無効にします。",
    "Select features to install. Enabled sibling actions and other unselected features remain.": "インストールする機能を選択してください。有効な同梱の操作とその他の未選択機能は保持されます。",
    "Total uninstall time": "アンインストール総時間",
    "Uninstall selected": "選択項目をアンインストール",
    "Uninstall selected features": "選択した機能をアンインストール",
    "Uninstall time": "アンインストール時間",
    "Cancel": "キャンセル",
    "Uninstall only selected installed features. Other features, logs, backups and tools remain.": "選択したインストール済み機能のみを削除します。その他の機能、ログ、バックアップ、ツールは保持します。",
    "Change only the current user's ExecuteFile ACL for a single regular NTFS file after confirmation. Does not launch the file or change global policy.": "確認後、通常の NTFS ファイル 1 個について、現在のユーザーの ExecuteFile ACL のみを変更します。ファイルの起動やグローバルポリシーの変更は行いません。",
    "View a single regular file. Files over 1 MiB or suspected binary files require YES in the terminal.": "通常ファイルを 1 個だけ表示します。1 MiB 超またはバイナリの疑いがある場合、ターミナルで YES の入力が必要です。",
    "Clean only the selected packages' build workspaces. Installed DLLs, scripts, settings and registry entries remain.": "選択したパッケージ専用のビルド作業領域のみを削除します。インストール済み DLL、スクリプト、設定、レジストリエントリは保持します。",
    "Copy full log": "ログ全体をコピー",
    "Copy the original remote URL for the current branch.": "現在のブランチの元のリモート URL をコピーします。",
    "Copy the absolute path of a file or folder.": "ファイルまたはフォルダの絶対パスをコピーします。",
    "Could not copy the log: ": "ログをコピーできませんでした： ",
    "Failed — open log": "失敗 — ログを開く",
    "Install / update": "インストール / 更新",
    "Install / update selected features": "選択した機能をインストール / 更新",
    "Total install time": "インストール総時間",
    "Install time": "インストール時間",
    "Merge appears for a complete selected volume set; split appears for one regular file. Originals are always preserved.": "同じ組の分割ファイルをすべて選択すると結合を表示し、通常ファイル 1 個を選択すると分割を表示します。元のファイルは常に保持します。",
    "Live log (drag the divider to resize)": "リアルタイムログ（上の区切り線で高さを調整）",
    "Installation stopped after the current package transaction. Unstarted items are marked Not run.": "現在のパッケージのトランザクション完了後にインストールを停止しました。未開始の項目は「未実行」と表示します。",
    "Stop requested. Waiting for the current package transaction; later items will not run.": "停止を要求しました。現在のパッケージのトランザクション終了を待っています。以降の項目は実行しません。",
    "Selected {0} / {1}. Closing or cancelling makes no changes.": "{0} / {1} 件を選択。閉じるかキャンセルすると変更は行われません。",
    "Hover for feature details. Windows 11: right-click → Show more options.": "ポインターを重ねると機能の説明を表示します。Windows 11：右クリック → その他のオプションを表示。",
    "Could not open the full log: ": "完全なログを開けませんでした： ",
    "Open the repository website for the current Git worktree.": "現在の Git ワークツリーのリポジトリ Web サイトを開きます。",
    "Open the solution or project at the current directory level.": "現在の階層のソリューションまたはプロジェクトを開きます。",
    "Export resolved third-party Pub sources and licenses from the project lockfile. Press Enter to use the desktop as output.": "プロジェクトのロックファイルに従い、解決済みサードパーティ Pub ソースとライセンスをエクスポートします。出力先は Enter でデスクトップを選べます。",
    "An operation is running. Wait for the transaction to finish before closing. Logs can be copied at any time.": "操作を実行中です。トランザクション完了後に閉じてください。ログはいつでもコピーできます。",
    "Could not build the operation plan: ": "操作計画を作成できませんでした： ",
    "Could not start the operation: ": "操作を開始できませんでした： ",
    "Log: ": "ログ： ",
    "🈶 Repair Chinese paths in Flutter project": "🈶 Flutter プロジェクトの中国語パスを修復",
    "Not installed; nothing to uninstall": "未インストール：削除不要",
    "Not installed": "未インストール",
    "Not run": "未実行",
    "This feature": "この機能",
    "Local build directory (moving or cleaning it disables the menu)": "ローカルビルドディレクトリ（移動や削除でメニューが無効）",
    "Validate the branch, staging area and upstream, then confirm the push.": "ブランチ、ステージング領域、上流を検証してから Push を確認します。",
    "Validate the Flutter project, then fetch dependencies.": "Flutter プロジェクトを検証してから依存関係を取得します。",
    "Installing / updating…": "インストール / 更新中…",
    "This entry has been removed. Existing installations can be uninstalled but cannot be reinstalled.": "この項目は削除済みです。既存のインストールは削除できますが、再インストールはできません。",
    "No features require processing; ": "処理が必要な機能はありません； ",
    "No features require processing. No settings were changed.": "処理が必要な機能はありません。設定は変更されていません。",
    "Total cleanup time": "クリーンアップ総時間",
    "Cleanup time": "クリーンアップ時間",
    "Click to read the full session log in a new PowerShell window. The current task continues.": "クリックすると、新しい PowerShell ウィンドウに今回の完全なセッションログを表示します。現在のタスクは継続します。",
    "Pending": "保留中",
    "Waiting to stop…": "停止を待機中…",
    "Ordered Flutter development, diagnostics, repair and maintenance tools. Regular actions use project FVM; environment setup supports FVM / system Flutter and jEnv / system Java.": "Flutter の開発、診断、修復、保守ツールを固定順で表示します。通常の操作はプロジェクト FVM を使用し、環境設定は FVM / システム Flutter と jEnv / システム Java に対応します。",
    "Detect the Flutter / Android project and preview cleanup scope. iOS cleanup is unavailable on Windows.": "Flutter / Android プロジェクトを検出して削除範囲をプレビューします。Windows では iOS のクリーンアップは利用できません。",
    "Could not read preferences: ": "設定を読み取れませんでした： ",
    "Could not read the log: ": "ログを読み取れませんでした： ",
    "Explorer context-menu extensions · ": "Explorer コンテキストメニュー拡張機能 · ",
    "Explorer extensions · Manage": "Explorer 拡張機能 · 管理",
    "Return selection": "選択内容を返す",
    "Exit code: ": "終了コード： ",
    "Choose an operation and select features. Unselected features remain; only installed features can be uninstalled.": "操作を選び、機能を選択してください。未選択の機能は保持されます。アンインストールはインストール済みの機能のみが対象です。",
    "Some features failed; other selected features were still processed. Click a failed status to open the full session log.": "一部の機能が失敗しましたが、その他の選択した機能は処理しました。失敗状態をクリックすると、完全なセッションログを表示します。",
    "Available for nonempty regular directories outside iOS projects, including Flutter roots. Validated again before opening.": "空ではない、iOS プロジェクト以外の通常ディレクトリで利用できます。Flutter ルートにも対応し、開く前に再検証します。",
    "Default installation location (recommended)": "既定のインストール先（推奨）",
    "{0}; Results: succeeded {1}; nothing to uninstall {2}; failed {3}; not run {4}": "{0}；結果：成功 {1}；削除不要 {2}；失敗 {3}；未実行 {4}",
    "{0} Exit code: {1}.": "{0} 終了コード：{1}。",
    "{0} {1}": "{0} {1}",
    "{0}{1} {2}": "{0}{1} {2}",
    "{0} in progress; completed {1} / {2} ({3}% by completed items); {4} {5}": "{0}を実行中；完了 {1} / {2}（{3}%、完了項目基準）；{4} {5}",
    "{0} Completed {1} / {2} ({3}% by completed items); {4} {5}": "{0} 完了 {1} / {2}（{3}%、完了項目基準）；{4} {5}",
    "🫥 Hide / show selected items": "🫥 選択した項目を非表示 / 表示",
    "Set the Hidden attribute of selected files or folders, including multiple selections; do not recurse, rename, or change global visibility preferences.": "選択したファイルやフォルダーの隠し属性を設定します。複数選択に対応し、再帰処理、名前変更、全体の表示設定の変更は行いません。",
    "Permanently delete (skip Recycle Bin)": "完全に削除（ごみ箱を使わない）",
    "Directly delete selected files or folders; confirm with the red left button or cancel with the blue right button. Cancellation is the default; deleted items cannot be restored from the Recycle Bin.": "選択したファイルやフォルダーを直接削除します。左の赤い確認ボタン、右の青いキャンセルボタンを表示し、既定はキャンセルです。削除後はごみ箱から復元できません。"
  },
  "fr": {
    "Close management panel": "Fermer le panneau de gestion",
    "Minimize to tray": "Réduire dans la zone de notification",
    "Exit completely": "Quitter complètement",
    "Keep window open": "Garder la fenêtre ouverte",
    "The manager is idle. Keep it in the system tray, or exit completely.": "Aucune tâche en cours. Gardez le gestionnaire dans la zone de notification ou quittez complètement.",
    "Show management panel": "Afficher le panneau de gestion",
    "Current status": "État actuel",
    "A task is running. Exit is unavailable; restore the window to view logs.": "Une tâche est en cours. La fermeture complète est désactivée ; restaurez la fenêtre pour voir les journaux.",
    "The system tray is unavailable. The window will remain open.": "La zone de notification est indisponible. La fenêtre reste ouverte.",
    "💽 Disk free space": "💽 Espace disque libre",
    "Show total local disk free / capacity and a two-decimal percentage. Click to choose cleanup in a separate terminal; changes require confirmation.": "Afficher l’espace libre total / la capacité des disques locaux et le pourcentage à deux décimales. Cliquer pour choisir un nettoyage dans un terminal séparé ; une confirmation est requise.",
    "Create script launcher…": "Créer un lanceur de script…",
    "🔗 Create script launcher…": "🔗 Créer un lanceur de script…",
    "Create a relative launcher beside a same-name .cmd/.bat/.ps1 script folder; do not run or modify the source script.": "Créer un lanceur relatif à côté du dossier .cmd/.bat/.ps1 contenant le script du même nom, sans exécuter ni modifier le script source.",
    "Theme": "Thème",
    "Language": "Langue",
    "🎨 Theme": "🎨 Thème",
    "🌐 Language": "🌐 Langue",
    "Follow system": "Suivre le système",
    "Dark": "Sombre",
    "Light": "Clair",
    "Jobs Finder Extension Manager": "Gestionnaire d’extensions Finder Jobs",
    "Customize Finder Context Menu": "Personnaliser le menu contextuel du Finder",
    "Close Manager": "Fermer le gestionnaire",
    "Edit": "Modifier",
    "Copy": "Copier",
    "Select all": "Tout sélectionner",
    "Clear all": "Tout désélectionner",
    "Close": "Fermer",
    "OK": "Valider",
    "Install": "Installer",
    "Install / Update": "Installer / Mettre à jour",
    "Uninstall": "Désinstaller",
    "Cleanup": "Nettoyage",
    "Clean build products": "Nettoyer les produits de compilation",
    "🧹 Clean build products": "🧹 Nettoyer les produits de compilation",
    "Stop installation": "Arrêter l’installation",
    "Stopping…": "Arrêt en cours…",
    "Action: install / update or uninstall": "Action : installer / mettre à jour ou désinstaller",
    "Uninstall removes selected menus only. Group selection affects its own group.": "La désinstallation ne supprime que les menus sélectionnés. La sélection par groupe ne concerne que ce groupe.",
    "Install / uninstall with the combined App in Applications": "Installer / désinstaller avec l’app combinée dans Applications",
    "Install or uninstall the combined App in Applications": "Installer ou désinstaller l’app combinée dans Applications",
    "Selected: manage features in /Applications/Jobs自定义右键菜单.app. Otherwise use the build directory.": "Coché : gérer les fonctions dans /Applications/Jobs自定义右键菜单.app. Sinon, utiliser le dossier de compilation.",
    "Clean this build after successful installation": "Nettoyer cette compilation après une installation réussie",
    "Clean this build only after the combined App is installed and verified in Applications. Keep failed builds.": "Nettoyer cette compilation uniquement après installation et vérification de l’app combinée dans Applications. Conserver les compilations échouées.",
    "Clean build products of selected features without installing or uninstalling.": "Nettoyer les produits de compilation des fonctions sélectionnées, sans installation ni désinstallation.",
    "Clean selected features' build products": "Nettoyer les produits de compilation des fonctions sélectionnées",
    "Open Privacy & Security": "Ouvrir Confidentialité et sécurité",
    "Add and enable Jobs右键菜单管理面板.app in Privacy & Security → App Management. This only opens Settings.": "Ajouter et activer Jobs右键菜单管理面板.app dans Confidentialité et sécurité → Gestion des apps. Ce bouton ouvre uniquement les réglages.",
    "Target: build directory. Cleaning these products affects installed features.": "Cible : dossier de compilation. Nettoyer ces produits affecte les fonctions installées.",
    "App: Jobs自定义右键菜单.app at /Applications/Jobs自定义右键菜单.app (build products can be cleaned after installation)": "App : Jobs自定义右键菜单.app dans /Applications/Jobs自定义右键菜单.app (les produits de compilation peuvent être nettoyés après l’installation)",
    "Drag the divider to resize the log. Features and logs scroll separately.": "Faire glisser le séparateur pour redimensionner le journal. Les fonctions et le journal défilent séparément.",
    "Feature list and live log divider": "Séparateur entre la liste des fonctions et le journal en direct",
    "Live log (select and copy text)": "Journal en direct (texte sélectionnable et copiable)",
    "Copy log": "Copier le journal",
    "Log file": "Fichier journal",
    "Auto-scroll": "Défilement automatique",
    "Ready. Select features and choose an action.": "Prêt. Sélectionner des fonctions et une action.",
    "A task is running. Wait for it to finish before closing.": "Une tâche est en cours. Attendre sa fin avant de fermer.",
    "Unable to view this log": "Impossible d’afficher ce journal",
    "Log is missing or unreadable: {0}": "Journal absent ou illisible : {0}",
    "Unable to open log terminal: {0}": "Impossible d’ouvrir le terminal du journal : {0}",
    "Click to show this session's full log in a new terminal: {0}": "Cliquer pour afficher le journal complet de cette session dans un nouveau terminal : {0}",
    "Selected {0} / {1}. Select at least one. Changing action keeps selection.": "Sélection : {0} / {1}. Sélectionner au moins un élément. Changer d’action conserve la sélection.",
    "Selected {0} / {1}": "Sélection : {0} / {1}",
    "{0}: select all": "{0} : tout sélectionner",
    "{0}: clear all": "{0} : tout désélectionner",
    "Waiting": "En attente",
    "Cleaning…": "Nettoyage…",
    "Uninstalling…": "Désinstallation…",
    "Installing…": "Installation…",
    "Cleaned": "Nettoyé",
    "Uninstalled": "Désinstallé",
    "Installed": "Installé",
    "Skipped": "Ignoré",
    "Not installed; nothing to remove": "Non installé ; rien à supprimer",
    "Failed: see log": "Échec : voir le journal",
    "Selected": "Sélectionné",
    "Not selected": "Non sélectionné",
    "App Management permission required": "Autorisation de gestion des apps requise",
    "Permission check required": "Vérification des autorisations requise",
    "Stopped": "Arrêté",
    "Completed": "Terminé",
    "Task failed": "Échec de la tâche",
    "{0}: processed {1} / {2} ({3}, completed items); {4} time {5}": "{0} : traité {1} / {2} ({3}, éléments terminés) ; durée de {4} : {5}",
    "{0} ready": "{0} prêt",
    "{0} ready; {1} time {2}": "{0} prêt ; durée de {1} : {2}",
    "Finishing the current feature, then stopping; install time {0}": "Fin de la fonction en cours, puis arrêt ; durée d’installation : {0}",
    "{0}: {1} succeeded, {2} failed, {3} skipped; exit {4}; {5}; {6} time {7}": "{0} : {1} réussis, {2} échoués, {3} ignorés ; code {4} ; {5} ; durée de {6} : {7}",
    "{0}: {1} succeeded, {2} failed, {3} not installed, {4} skipped; exit {5}; {6}; {7} time {8}": "{0} : {1} réussis, {2} échoués, {3} non installés, {4} ignorés ; code {5} ; {6} ; durée de {7} : {8}",
    "{0}: {1} succeeded, {2} failed, {3} not installed; exit {4}; {5}; {6} time {7}": "{0} : {1} réussis, {2} échoués, {3} non installés ; code {4} ; {5} ; durée de {6} : {7}",
    "{0}: {1} succeeded, {2} failed; exit {3}; {4}; {5} time {6}": "{0} : {1} réussis, {2} échoués ; code {3} ; {4} ; durée de {5} : {6}",
    "Open projects in IDEs": "Ouvrir les projets dans les IDE",
    "Git tools": "Outils Git",
    "Files and general tools": "Fichiers et outils généraux",
    "Flutter tools · submenu actions": "Outils Flutter · actions du sous-menu",
    "iOS / CocoaPods tools": "Outils iOS / CocoaPods",
    "Simulator tools": "Outils de simulateur",
    "Open project in Android Studio": "Ouvrir le projet dans Android Studio",
    "Open project in VSCode": "Ouvrir le projet dans VSCode",
    "Open project in Xcode": "Ouvrir le projet dans Xcode",
    "Pull latest Git changes": "Récupérer les dernières modifications Git",
    "Roll back Git commit": "Revenir à un commit Git",
    "Open Git remote URL": "Ouvrir l’URL distante Git",
    "Copy Git remote URL": "Copier l’URL distante Git",
    "Copy absolute path": "Copier le chemin absolu",
    "Create file": "Créer un fichier",
    "View file fingerprint Hash (SHA-256)": "Afficher l’empreinte du fichier (SHA-256)",
    "Grant execute permission (chmod +x)": "Accorder le droit d’exécution (chmod +x)",
    "Remove execute permission (chmod -x)": "Retirer le droit d’exécution (chmod -x)",
    "Re-sign IPA without building": "Signer à nouveau l’IPA sans compiler",
    "Show / hide files": "Afficher / masquer les fichiers",
    "Create iOS simulator": "Créer un simulateur iOS",
    "Create Android simulator": "Créer un simulateur Android",
    "Create Harmony simulator": "Créer un simulateur Harmony",
    "Check / repair Android simulator": "Vérifier / réparer le simulateur Android",
    "Check / repair Harmony simulator": "Vérifier / réparer le simulateur Harmony",
    "Configure Git proxy": "Configurer le proxy Git",
    "Open in terminal": "Ouvrir dans le terminal",
    "View file contents in terminal": "Afficher le contenu du fichier dans le terminal",
    "Merge file parts": "Fusionner les parties du fichier",
    "Split file": "Scinder le fichier",
    "Clean Android / OpenHarmony builds": "Nettoyer les compilations Android / OpenHarmony",
    "Update code map (.codegraph)": "Mettre à jour la carte du code (.codegraph)",
    "Create empty commit and push in terminal": "Créer un commit vide et pousser dans le terminal",
    "Disable CocoaPods build sandbox": "Désactiver le bac à sable de compilation CocoaPods",
    "Install CocoaPods": "Installer CocoaPods",
    "CocoaPods source: CDN → GitHub": "Source CocoaPods : CDN → GitHub",
    "Export all project Pod files": "Exporter tous les fichiers Pod du projet",
    "Inspect Xcode project dependencies": "Inspecter les dépendances du projet Xcode",
    "Update local CocoaPods repositories": "Mettre à jour les dépôts CocoaPods locaux",
    "Check local Pod builds (.podspec folder)": "Vérifier les compilations Pod locales (dossier .podspec)",
    "Install / update JobsCodeSnippets": "Installer / mettre à jour JobsCodeSnippets",
    "Clean iOS / Xcode builds": "Nettoyer les compilations iOS / Xcode",
    "Set up Flutter project": "Configurer le projet Flutter",
    "Run Flutter project in terminal": "Exécuter le projet Flutter dans le terminal",
    "Fetch Flutter Pub dependencies": "Récupérer les dépendances Flutter Pub",
    "Fetch native Android dependencies": "Récupérer les dépendances Android natives",
    "Fetch CocoaPods dependencies": "Récupérer les dépendances CocoaPods",
    "Fetch Swift Package dependencies": "Récupérer les dépendances Swift Package",
    "Fetch OpenHarmony dependencies": "Récupérer les dépendances OpenHarmony",
    "Prepare native libraries and build dependencies": "Préparer les bibliothèques natives et les dépendances de compilation",
    "Download Flutter platform resources": "Télécharger les ressources de plateforme Flutter",
    "Fetch Web project dependencies": "Récupérer les dépendances du projet Web",
    "🧳 Export Flutter dependencies": "🧳 Exporter les dépendances Flutter",
    "Export Flutter Pub dependencies": "Exporter les dépendances Flutter Pub",
    "🔐 Export private Flutter dependencies": "🔐 Exporter les dépendances Flutter privées",
    "📥 Import Flutter dependencies": "📥 Importer les dépendances Flutter",
    "Import Flutter Pub dependencies": "Importer les dépendances Flutter Pub",
    "📥 Import private Flutter dependencies": "📥 Importer les dépendances Flutter privées",
    "Export Gradle distributions and cache": "Exporter les distributions et le cache Gradle",
    "Import Gradle distributions and cache": "Importer les distributions et le cache Gradle",
    "Export CocoaPods dependencies": "Exporter les dépendances CocoaPods",
    "Import CocoaPods dependencies": "Importer les dépendances CocoaPods",
    "Export Swift Package dependencies": "Exporter les dépendances Swift Package",
    "Import Swift Package dependencies": "Importer les dépendances Swift Package",
    "Export OpenHarmony dependencies": "Exporter les dépendances OpenHarmony",
    "Import OpenHarmony dependencies": "Importer les dépendances OpenHarmony",
    "Export native build cache": "Exporter le cache de compilation natif",
    "Import native build cache": "Importer le cache de compilation natif",
    "Export Flutter platform resources": "Exporter les ressources de plateforme Flutter",
    "Import Flutter platform resources": "Importer les ressources de plateforme Flutter",
    "Export Web dependencies": "Exporter les dépendances Web",
    "Import Web dependencies": "Importer les dépendances Web",
    "Show Flutter project SDK version": "Afficher la version du SDK du projet Flutter",
    "Install / switch Flutter SDK": "Installer / changer de SDK Flutter",
    "Install / switch Flutter@OpenHarmony SDK": "Installer / changer de SDK Flutter@OpenHarmony",
    "Install / switch Java SDK": "Installer / changer de SDK Java",
    "Download Gradle distributions and plugins": "Télécharger les distributions et plugins Gradle",
    "Generate Flutter code": "Générer le code Flutter",
    "Package iOS": "Créer le paquet iOS",
    "Package Android": "Créer le paquet Android",
    "Package Harmony (HAP + APP)": "Créer le paquet Harmony (HAP + APP)",
    "Check native Flutter project": "Vérifier le projet Flutter natif",
    "Check OpenHarmony Flutter environment": "Vérifier l’environnement Flutter OpenHarmony",
    "Repair missing Android SDK / platforms": "Réparer les SDK / plateformes Android manquants",
    "Repair Chinese Flutter project paths": "Réparer les chemins chinois du projet Flutter",
    "Repair Flutter plugin namespaces": "Réparer les espaces de noms des plugins Flutter",
    "Convert relative Dart imports to packages": "Convertir les imports Dart relatifs en imports de paquets",
    "Clean current Flutter project builds": "Nettoyer les compilations du projet Flutter actuel",
    "Dependency and cache maintenance": "Maintenance des dépendances et des caches",
    "Custom Explorer context menu": "Menu contextuel Explorer personnalisé",
    "Jobs Windows · Custom Explorer context menu": "Jobs Windows · Menu contextuel Explorer personnalisé",
    "Show a regular file's SHA-256 in a new terminal and copy the digest; do not modify or execute the file.": "Afficher le SHA-256 d’un fichier ordinaire dans un nouveau terminal et copier son empreinte ; ne pas modifier ni exécuter le fichier.",
    " (preview)": " (aperçu)",
    "⏪ Roll back Git commits": "⏪ Revenir à des commits Git",
    "▶️ Run Flutter project in terminal": "▶️ Exécuter le projet Flutter dans le terminal",
    "☕ Install / switch Java SDK": "☕ Installer / changer de SDK Java",
    "♻️ Flutter cleanup and maintenance": "♻️ Nettoyage et maintenance Flutter",
    "⚙️ Generate Flutter code": "⚙️ Générer le code Flutter",
    "✅ Installed": "✅ Installé",
    "⬇️ Pull latest Git changes": "⬇️ Récupérer les dernières modifications Git",
    "🌈 Create Harmony emulator": "🌈 Créer un émulateur Harmony",
    "🌐 Open Git remote URL": "🌐 Ouvrir l’URL distante Git",
    "🌐 Fetch Web project dependencies": "🌐 Récupérer les dépendances du projet Web",
    "🌳 Open in Sourcetree": "🌳 Ouvrir dans Sourcetree",
    "🏥 Flutter project diagnostics": "🏥 Diagnostic du projet Flutter",
    "🏥 Flutter diagnostics": "🏥 Diagnostic Flutter",
    "🏷️ Repair Flutter plugin namespaces": "🏷️ Réparer les espaces de noms des plugins Flutter",
    "👁️ Show / hide hidden files": "👁️ Afficher / masquer les fichiers cachés",
    "💓 OpenHarmony Flutter diagnostics": "💓 Diagnostic Flutter OpenHarmony",
    "💠 Open project in Visual Studio": "💠 Ouvrir le projet dans Visual Studio",
    "💻 Open in terminal": "💻 Ouvrir dans le terminal",
    "📄 View file in terminal": "📄 Afficher le fichier dans le terminal",
    "📋 Copy absolute path": "📋 Copier le chemin absolu",
    "📚 Download Gradle distributions and build plugins": "📚 Télécharger les distributions et plugins de compilation Gradle",
    "📝 Open project in VSCode": "📝 Ouvrir le projet dans VSCode",
    "📡 Configure Git dynamic proxy": "📡 Configurer le proxy dynamique Git",
    "📤 Import Flutter Pub dependencies": "📤 Importer les dépendances Flutter Pub",
    "📤 Import Flutter platform assets": "📤 Importer les ressources de plateforme Flutter",
    "📤 Import Gradle distributions and dependency caches": "📤 Importer les distributions et caches de dépendances Gradle",
    "📤 Import OpenHarmony dependencies": "📤 Importer les dépendances OpenHarmony",
    "📤 Import Web dependencies": "📤 Importer les dépendances Web",
    "📤 Import native build caches": "📤 Importer les caches de compilation natifs",
    "📤 Import Flutter project dependencies": "📤 Importer les dépendances du projet Flutter",
    "📤 Create empty commit and push": "📤 Créer un commit vide et pousser",
    "📥 Install Flutter dependencies (pub get)": "📥 Installer les dépendances Flutter (pub get)",
    "📥 Import private Flutter project dependencies": "📥 Importer les dépendances privées du projet Flutter",
    "📥 Fetch Flutter Pub dependencies": "📥 Récupérer les dépendances Flutter Pub",
    "📥 Fetch Flutter project dependencies": "📥 Récupérer les dépendances du projet Flutter",
    "📦 Package Flutter project": "📦 Créer le paquet du projet Flutter",
    "📦 Package HarmonyOS (HAP + APP)": "📦 Créer le paquet HarmonyOS (HAP + APP)",
    "📱 Create Android emulator": "📱 Créer un émulateur Android",
    "🔀 Install / switch Flutter SDK (FVM)": "🔀 Installer / changer de SDK Flutter (FVM)",
    "🔀 Install / switch Flutter SDK": "🔀 Installer / changer de SDK Flutter",
    "🔀 Install / switch Flutter environments": "🔀 Installer / changer d’environnement Flutter",
    "🔎 Show current Flutter SDK version": "🔎 Afficher la version du SDK Flutter actuel",
    "🔎 Show current Flutter project's SDK version": "🔎 Afficher la version du SDK du projet Flutter actuel",
    "🔐 Export private Flutter project dependencies": "🔐 Exporter les dépendances privées du projet Flutter",
    "🔎 Show file fingerprint Hash (SHA-256)": "🔎 Afficher l’empreinte du fichier (SHA-256)",
    "➕ Grant execute permission": "➕ Accorder le droit d’exécution",
    "➖ Remove execute permission": "➖ Retirer le droit d’exécution",
    "🔒 Grant execute permission": "🔒 Accorder le droit d’exécution",
    "🔓 Remove execute permission": "🔓 Retirer le droit d’exécution",
    "🔗 Copy Git remote URL": "🔗 Copier l’URL distante Git",
    "🔧 Flutter repairs": "🔧 Réparations Flutter",
    "🕊️ Install / switch Flutter@OpenHarmony SDK": "🕊️ Installer / changer de SDK Flutter@OpenHarmony",
    "🕊️ Fetch OpenHarmony dependencies": "🕊️ Récupérer les dépendances OpenHarmony",
    "🗃️ Download Flutter platform assets": "🗃️ Télécharger les ressources de plateforme Flutter",
    "🗺️ Update code map (.codegraph)": "🗺️ Mettre à jour la carte du code (.codegraph)",
    "🤖 Fetch Android native dependencies": "🤖 Récupérer les dépendances Android natives",
    "🦋 Flutter development": "🦋 Développement Flutter",
    "🦋 Flutter development tools": "🦋 Outils de développement Flutter",
    "🧑‍⚕️ Native Flutter diagnostics": "🧑‍⚕️ Diagnostic Flutter natif",
    "🧩 Export Flutter Pub dependencies": "🧩 Exporter les dépendances Flutter Pub",
    "🧩 Export Flutter platform assets": "🧩 Exporter les ressources de plateforme Flutter",
    "🧩 Export Flutter third-party dependencies": "🧩 Exporter les dépendances tierces Flutter",
    "🧩 Export Gradle distributions and dependency caches": "🧩 Exporter les distributions et caches de dépendances Gradle",
    "🧩 Export OpenHarmony dependencies": "🧩 Exporter les dépendances OpenHarmony",
    "🧩 Export Web dependencies": "🧩 Exporter les dépendances Web",
    "🧩 Export native build caches": "🧩 Exporter les caches de compilation natifs",
    "🧩 Export Flutter project dependencies": "🧩 Exporter les dépendances du projet Flutter",
    "🧩 Merge file volumes / ✂️ Split file": "🧩 Fusionner les volumes / ✂️ Scinder le fichier",
    "🧭 Open project in Android Studio": "🧭 Ouvrir le projet dans Android Studio",
    "🧯 Clean build output": "🧯 Nettoyer les sorties de compilation",
    "🧰 Diagnose and repair Harmony emulator": "🧰 Diagnostiquer et réparer l’émulateur Harmony",
    "🧱 Flutter assets and build dependencies": "🧱 Ressources Flutter et dépendances de compilation",
    "🧱 Prepare native libraries and build dependencies (combined)": "🧱 Préparer les bibliothèques natives et les dépendances de compilation (combiné)",
    "🧹 Clean build output": "🧹 Nettoyer les sorties de compilation",
    "🩹 Repair missing Android SDK / platforms": "🩹 Réparer les SDK / plateformes Android manquants",
    "🩺 Diagnose and repair Android emulator": "🩺 Diagnostiquer et réparer l’émulateur Android",
    "🚀 Set up Flutter project": "🚀 Configurer le projet Flutter",
    "🚚 Import all Flutter dependencies": "🚚 Importer toutes les dépendances Flutter",
    "🚚 Export all Flutter dependencies": "🚚 Exporter toutes les dépendances Flutter",
    "Jobs Windows · Uninstall Explorer extensions": "Jobs Windows · Désinstaller les extensions Explorer",
    "Jobs Windows · Install Explorer extensions": "Jobs Windows · Installer les extensions Explorer",
    "Jobs Windows · Manage Explorer extensions": "Jobs Windows · Gérer les extensions Explorer",
    "Jobs Windows · Configure Explorer extensions": "Jobs Windows · Configurer les extensions Explorer",
    "Drag the divider vertically to resize the log": "Faire glisser le séparateur verticalement pour redimensionner le journal",
    "Drag vertically to resize the log": "Faire glisser verticalement pour redimensionner le journal",
    "Validate the Flutter project, diagnose the toolchain in terminal, and choose a Flutter SDK version with fzf.": "Valider le projet Flutter, diagnostiquer la chaîne d’outils dans le terminal et choisir une version du SDK Flutter avec fzf.",
    "Validate the Flutter project, then show the active SDK version (project FVM or system SDK) in terminal and compare it with .fvmrc and pubspec constraints.": "Valider le projet Flutter, puis afficher la version du SDK actif (FVM du projet ou SDK système) dans le terminal et la comparer à .fvmrc et aux contraintes du pubspec.",
    "Flutter roots only. Choose Android / iOS / HarmonyOS with fzf in CMD. Supports APK / AAB and HAP / APP. iOS requires MacOS and Xcode.": "Racines de projets Flutter uniquement. Choisir Android / iOS / HarmonyOS avec fzf dans CMD. Prend en charge APK / AAB et HAP / APP. iOS nécessite MacOS et Xcode.",
    "Flutter roots only. Choose a device and view logs in CMD; the app continues in the background after the window closes.": "Racines de projets Flutter uniquement. Choisir un appareil et consulter les journaux dans CMD ; l’app continue en arrière-plan après la fermeture de la fenêtre.",
    "Flutter roots only. Read-only version and doctor diagnostics in terminal; no dependency fetching, cleanup, or tool upgrades.": "Racines de projets Flutter uniquement. Diagnostic en lecture seule de la version et de doctor dans le terminal ; sans récupération de dépendances, nettoyage ni mise à niveau d’outils.",
    "Flutter roots only. Preview configured generators, then fetch dependencies and generate code after confirmation. Deleting conflicts requires separate opt-in.": "Racines de projets Flutter uniquement. Prévisualiser les générateurs configurés, puis récupérer les dépendances et générer le code après confirmation. La suppression des conflits exige un accord distinct.",
    "Git worktree folders only. Detect nested repositories. Soft mode preserves the index and worktree; hard mode requires exact YES confirmation.": "Dossiers d’arbres de travail Git uniquement. Détecter les dépôts imbriqués. Le mode soft préserve l’index et l’arbre de travail ; le mode hard exige la saisie exacte de YES.",
    "Desktop background on x64 Windows only. Missing tools come from the SDL mirror; missing system images come from the official Emulator. Enter selects a stable phone image; confirm its license to create and start a unique instance.": "Arrière-plan du bureau sur Windows x64 uniquement. Les outils manquants proviennent du miroir SDL ; les images système manquantes proviennent de l’Emulator officiel. Entrée choisit une image de téléphone stable ; confirmer sa licence pour créer et démarrer une instance unique.",
    "Manage only this package's actions. Unselected actions remain when uninstalling.": "Gérer uniquement les actions de ce paquet. Les actions non sélectionnées sont conservées lors de la désinstallation.",
    "Desktop background only. Configure user-level Git to prefer the system proxy and fall back to a direct connection.": "Arrière-plan du bureau uniquement. Configurer Git au niveau utilisateur pour privilégier le proxy système et utiliser une connexion directe en repli.",
    "Desktop background only. Diagnose the SDK in CMD, choose a device and system image, then create or start an Android AVD.": "Arrière-plan du bureau uniquement. Diagnostiquer le SDK dans CMD, choisir un appareil et une image système, puis créer ou démarrer un AVD Android.",
    "Desktop background only. Check existing DevEco Emulator instances, then start one or confirm a nondestructive restart. Data is preserved.": "Arrière-plan du bureau uniquement. Vérifier les instances DevEco Emulator existantes, puis en démarrer une ou confirmer un redémarrage sans destruction. Les données sont préservées.",
    "Desktop background only. Check emulator location and /data; optionally reset caches, precisely uninstall, back up the AVD, and retest with a cold boot.": "Arrière-plan du bureau uniquement. Vérifier l’emplacement de l’émulateur et /data ; proposer la réinitialisation des caches, une désinstallation ciblée, la sauvegarde de l’AVD et un nouveau test avec démarrage à froid.",
    "Show the next action on the desktop background. Toggle hidden files for the current user's Explorer without changing protected-system-file settings.": "Afficher l’action suivante sur l’arrière-plan du bureau. Basculer l’affichage des fichiers cachés dans l’Explorer de l’utilisateur actuel sans changer les paramètres des fichiers système protégés.",
    "Visible only for nonempty native Android or valid Flutter (official / HarmonyOS) project roots. Validated again before opening.": "Visible uniquement pour les racines non vides de projets Android natifs ou Flutter valides (officiel / HarmonyOS). Nouvelle validation avant ouverture.",
    "Preview: the selection is shown in the log. No installation or uninstallation was performed.": "Aperçu : la sélection apparaît dans le journal. Aucune installation ni désinstallation n’a été effectuée.",
    "Preview only. Confirming displays the selection in the log without installing, uninstalling, or writing state or registry entries.": "Aperçu uniquement. La confirmation affiche la sélection dans le journal sans installation, désinstallation ni écriture d’état ou du registre.",
    "Deployed copies use their bound location. To change it, open the manager from the source directory. Default installations run in the current user's LocalAppData; local builds run under this package's work directory and stop working if it moves.": "Les copies déployées utilisent leur emplacement lié. Pour le modifier, ouvrir le gestionnaire depuis le dossier source. Les installations par défaut s’exécutent dans LocalAppData de l’utilisateur actuel ; les compilations locales s’exécutent dans le dossier de travail du paquet et cessent de fonctionner s’il est déplacé.",
    "Prefer Windows Terminal; otherwise use system PowerShell.": "Privilégier Windows Terminal ; sinon, utiliser PowerShell système.",
    "Could not save preferences: ": "Impossible d’enregistrer les préférences : ",
    "Save settings": "Enregistrer les paramètres",
    "Protect local changes. On conflict, choose to restore, discard changes, or commit and retry.": "Protéger les modifications locales. En cas de conflit, choisir de restaurer, d’abandonner les modifications ou de créer un commit puis réessayer.",
    "All operations completed. Copy the log or close the panel.": "Toutes les opérations sont terminées. Copier le journal ou fermer le panneau.",
    "Other context-menu features": "Autres fonctions du menu contextuel",
    "Create or synchronize the code map for the current directory.": "Créer ou synchroniser la carte du code du dossier actuel.",
    "Feature and log divider": "Séparateur entre fonctions et journal",
    "Select features, then confirm. Unselected features remain. Hover for installation details.": "Sélectionner des fonctions, puis confirmer. Les fonctions non sélectionnées sont conservées. Survoler pour voir les détails d’installation.",
    "Checked features are installed; unchecked ones are uninstalled. Saving an empty selection disables all installed features.": "Les fonctions cochées sont installées ; celles décochées sont désinstallées. Enregistrer une sélection vide désactive toutes les fonctions installées.",
    "Select features to install. Enabled sibling actions and other unselected features remain.": "Sélectionner les fonctions à installer. Les actions voisines activées et les autres fonctions non sélectionnées sont conservées.",
    "Total uninstall time": "Durée totale de désinstallation",
    "Uninstall selected": "Désinstaller la sélection",
    "Uninstall selected features": "Désinstaller les fonctions sélectionnées",
    "Uninstall time": "Durée de désinstallation",
    "Cancel": "Annuler",
    "Uninstall only selected installed features. Other features, logs, backups and tools remain.": "Désinstaller uniquement les fonctions installées sélectionnées. Les autres fonctions, journaux, sauvegardes et outils sont conservés.",
    "Change only the current user's ExecuteFile ACL for a single regular NTFS file after confirmation. Does not launch the file or change global policy.": "Après confirmation, modifier uniquement l’ACL ExecuteFile de l’utilisateur actuel pour un seul fichier NTFS ordinaire. Ne lance pas le fichier et ne modifie pas la stratégie globale.",
    "View a single regular file. Files over 1 MiB or suspected binary files require YES in the terminal.": "Afficher un seul fichier ordinaire. Les fichiers de plus de 1 Mio ou potentiellement binaires exigent YES dans le terminal.",
    "Clean only the selected packages' build workspaces. Installed DLLs, scripts, settings and registry entries remain.": "Nettoyer uniquement les espaces de compilation des paquets sélectionnés. Les DLL, scripts, paramètres et entrées de registre installés sont conservés.",
    "Copy full log": "Copier le journal complet",
    "Copy the original remote URL for the current branch.": "Copier l’URL distante d’origine de la branche actuelle.",
    "Copy the absolute path of a file or folder.": "Copier le chemin absolu d’un fichier ou dossier.",
    "Could not copy the log: ": "Impossible de copier le journal : ",
    "Failed — open log": "Échec — ouvrir le journal",
    "Install / update": "Installer / mettre à jour",
    "Install / update selected features": "Installer / mettre à jour les fonctions sélectionnées",
    "Total install time": "Durée totale d’installation",
    "Install time": "Durée d’installation",
    "Merge appears for a complete selected volume set; split appears for one regular file. Originals are always preserved.": "La fusion apparaît pour un ensemble complet de volumes sélectionnés ; la scission apparaît pour un seul fichier ordinaire. Les originaux sont toujours conservés.",
    "Live log (drag the divider to resize)": "Journal en direct (faire glisser le séparateur pour redimensionner)",
    "Installation stopped after the current package transaction. Unstarted items are marked Not run.": "Installation arrêtée après la transaction du paquet actuel. Les éléments non commencés sont marqués Non exécuté.",
    "Stop requested. Waiting for the current package transaction; later items will not run.": "Arrêt demandé. Attente de la transaction du paquet actuel ; les éléments suivants ne seront pas exécutés.",
    "Selected {0} / {1}. Closing or cancelling makes no changes.": "Sélection : {0} / {1}. Fermer ou annuler n’apporte aucune modification.",
    "Hover for feature details. Windows 11: right-click → Show more options.": "Survoler pour voir les détails. Windows 11 : clic droit → Afficher plus d’options.",
    "Could not open the full log: ": "Impossible d’ouvrir le journal complet : ",
    "Open the repository website for the current Git worktree.": "Ouvrir le site web du dépôt de l’arbre de travail Git actuel.",
    "Open the solution or project at the current directory level.": "Ouvrir la solution ou le projet au niveau du dossier actuel.",
    "Export resolved third-party Pub sources and licenses from the project lockfile. Press Enter to use the desktop as output.": "Exporter les sources Pub tierces résolues et leurs licences depuis le verrou du projet. Appuyer sur Entrée pour utiliser le bureau comme destination.",
    "An operation is running. Wait for the transaction to finish before closing. Logs can be copied at any time.": "Une opération est en cours. Attendre la fin de la transaction avant de fermer. Les journaux peuvent être copiés à tout moment.",
    "Could not build the operation plan: ": "Impossible de créer le plan d’opération : ",
    "Could not start the operation: ": "Impossible de démarrer l’opération : ",
    "Log: ": "Journal : ",
    "🈶 Repair Chinese paths in Flutter project": "🈶 Réparer les chemins chinois du projet Flutter",
    "Not installed; nothing to uninstall": "Non installé ; rien à désinstaller",
    "Not installed": "Non installé",
    "Not run": "Non exécuté",
    "This feature": "Cette fonction",
    "Local build directory (moving or cleaning it disables the menu)": "Dossier de compilation local (déplacer ou nettoyer ce dossier désactive le menu)",
    "Validate the branch, staging area and upstream, then confirm the push.": "Valider la branche, l’index et le dépôt amont, puis confirmer le push.",
    "Validate the Flutter project, then fetch dependencies.": "Valider le projet Flutter, puis récupérer les dépendances.",
    "Installing / updating…": "Installation / mise à jour…",
    "This entry has been removed. Existing installations can be uninstalled but cannot be reinstalled.": "Cette entrée a été supprimée. Les installations existantes peuvent être désinstallées, mais pas réinstallées.",
    "No features require processing; ": "Aucune fonction à traiter ; ",
    "No features require processing. No settings were changed.": "Aucune fonction à traiter. Aucun paramètre n’a été modifié.",
    "Total cleanup time": "Durée totale de nettoyage",
    "Cleanup time": "Durée de nettoyage",
    "Click to read the full session log in a new PowerShell window. The current task continues.": "Cliquer pour lire le journal complet de la session dans une nouvelle fenêtre PowerShell. La tâche actuelle continue.",
    "Pending": "En attente de traitement",
    "Waiting to stop…": "Attente de l’arrêt…",
    "Ordered Flutter development, diagnostics, repair and maintenance tools. Regular actions use project FVM; environment setup supports FVM / system Flutter and jEnv / system Java.": "Outils Flutter ordonnés de développement, diagnostic, réparation et maintenance. Les actions courantes utilisent le FVM du projet ; la configuration prend en charge FVM / Flutter système et jEnv / Java système.",
    "Detect the Flutter / Android project and preview cleanup scope. iOS cleanup is unavailable on Windows.": "Détecter le projet Flutter / Android et prévisualiser le périmètre de nettoyage. Le nettoyage iOS est indisponible sous Windows.",
    "Could not read preferences: ": "Impossible de lire les préférences : ",
    "Could not read the log: ": "Impossible de lire le journal : ",
    "Explorer context-menu extensions · ": "Extensions du menu contextuel Explorer · ",
    "Explorer extensions · Manage": "Extensions Explorer · Gestion",
    "Return selection": "Renvoyer la sélection",
    "Exit code: ": "Code de sortie : ",
    "Choose an operation and select features. Unselected features remain; only installed features can be uninstalled.": "Choisir une opération et sélectionner des fonctions. Les fonctions non sélectionnées sont conservées ; seules les fonctions installées peuvent être désinstallées.",
    "Some features failed; other selected features were still processed. Click a failed status to open the full session log.": "Certaines fonctions ont échoué ; les autres fonctions sélectionnées ont tout de même été traitées. Cliquer sur un état d’échec pour ouvrir le journal complet de la session.",
    "Available for nonempty regular directories outside iOS projects, including Flutter roots. Validated again before opening.": "Disponible pour les dossiers ordinaires non vides hors projets iOS, y compris les racines Flutter. Nouvelle validation avant ouverture.",
    "Default installation location (recommended)": "Emplacement d’installation par défaut (recommandé)",
    "{0}; Results: succeeded {1}; nothing to uninstall {2}; failed {3}; not run {4}": "{0} ; résultats : réussis {1} ; rien à désinstaller {2} ; échoués {3} ; non exécutés {4}",
    "{0} Exit code: {1}.": "{0} Code de sortie : {1}.",
    "{0} {1}": "{0} {1}",
    "{0}{1} {2}": "{0}{1} {2}",
    "{0} in progress; completed {1} / {2} ({3}% by completed items); {4} {5}": "{0} en cours ; terminés {1} / {2} ({3}% par éléments terminés) ; {4} {5}",
    "{0} Completed {1} / {2} ({3}% by completed items); {4} {5}": "{0} Terminés {1} / {2} ({3}% par éléments terminés) ; {4} {5}",
    "🫥 Hide / show selected items": "🫥 Masquer / afficher la sélection",
    "Set the Hidden attribute of selected files or folders, including multiple selections; do not recurse, rename, or change global visibility preferences.": "Définir l’attribut caché des fichiers ou dossiers sélectionnés, y compris en sélection multiple ; sans récursion, renommage ni changement des préférences globales.",
    "Permanently delete (skip Recycle Bin)": "Supprimer définitivement (sans Corbeille)",
    "Directly delete selected files or folders; confirm with the red left button or cancel with the blue right button. Cancellation is the default; deleted items cannot be restored from the Recycle Bin.": "Supprime directement les fichiers ou dossiers sélectionnés. Confirmation rouge à gauche, annulation bleue à droite ; annulation par défaut. Restauration depuis la Corbeille impossible."
  },
  "es": {
    "Close management panel": "Cerrar el panel de gestión",
    "Minimize to tray": "Minimizar a la bandeja",
    "Exit completely": "Salir por completo",
    "Keep window open": "Mantener la ventana abierta",
    "The manager is idle. Keep it in the system tray, or exit completely.": "No hay tareas en curso. Mantenga el gestor en la bandeja del sistema o salga por completo.",
    "Show management panel": "Mostrar el panel de gestión",
    "Current status": "Estado actual",
    "A task is running. Exit is unavailable; restore the window to view logs.": "Hay una tarea en curso. No se puede salir; restaure la ventana para ver los registros.",
    "The system tray is unavailable. The window will remain open.": "La bandeja del sistema no está disponible. La ventana permanecerá abierta.",
    "💽 Disk free space": "💽 Espacio libre en disco",
    "Show total local disk free / capacity and a two-decimal percentage. Click to choose cleanup in a separate terminal; changes require confirmation.": "Mostrar espacio libre total / capacidad local y porcentaje con dos decimales. Pulsar para elegir la limpieza en una terminal independiente; requiere confirmación.",
    "Create script launcher…": "Crear acceso al script…",
    "🔗 Create script launcher…": "🔗 Crear acceso al script…",
    "Create a relative launcher beside a same-name .cmd/.bat/.ps1 script folder; do not run or modify the source script.": "Crea un acceso relativo junto a la carpeta .cmd/.bat/.ps1 del mismo nombre, sin ejecutar ni modificar el script original.",
    "Theme": "Tema",
    "Language": "Idioma",
    "🎨 Theme": "🎨 Tema",
    "🌐 Language": "🌐 Idioma",
    "Follow system": "Seguir el sistema",
    "Dark": "Oscuro",
    "Light": "Claro",
    "Jobs Finder Extension Manager": "Gestor de extensiones de Finder de Jobs",
    "Customize Finder Context Menu": "Personalizar el menú contextual de Finder",
    "Close Manager": "Cerrar el gestor",
    "Edit": "Editar",
    "Copy": "Copiar",
    "Select all": "Seleccionar todo",
    "Clear all": "Desmarcar todo",
    "Close": "Cerrar",
    "OK": "Aceptar",
    "Install": "Instalar",
    "Install / Update": "Instalar / Actualizar",
    "Uninstall": "Desinstalar",
    "Cleanup": "Limpieza",
    "Clean build products": "Limpiar los productos de compilación",
    "🧹 Clean build products": "🧹 Limpiar los productos de compilación",
    "Stop installation": "Detener la instalación",
    "Stopping…": "Deteniendo…",
    "Action: install / update or uninstall": "Operación: instalar / actualizar o desinstalar",
    "Uninstall removes selected menus only. Group selection affects its own group.": "La desinstalación solo elimina los menús seleccionados. La selección de un grupo solo afecta a ese grupo.",
    "Install / uninstall with the combined App in Applications": "Instalar / desinstalar con la app unificada en Aplicaciones",
    "Install or uninstall the combined App in Applications": "Instalar o desinstalar la app unificada en Aplicaciones",
    "Selected: manage features in /Applications/Jobs自定义右键菜单.app. Otherwise use the build directory.": "Marcado: gestionar funciones en /Applications/Jobs自定义右键菜单.app. En caso contrario, usar el directorio de compilación.",
    "Clean this build after successful installation": "Limpiar esta compilación tras una instalación correcta",
    "Clean this build only after the combined App is installed and verified in Applications. Keep failed builds.": "Limpiar esta compilación solo después de instalar y verificar la app unificada en Aplicaciones. Conservar las compilaciones fallidas.",
    "Clean build products of selected features without installing or uninstalling.": "Limpiar los productos de compilación de las funciones seleccionadas sin instalar ni desinstalar.",
    "Clean selected features' build products": "Limpiar los productos de compilación de las funciones seleccionadas",
    "Open Privacy & Security": "Abrir Privacidad y seguridad",
    "Add and enable Jobs右键菜单管理面板.app in Privacy & Security → App Management. This only opens Settings.": "Añadir y activar Jobs右键菜单管理面板.app en Privacidad y seguridad → Gestión de apps. Esto solo abre Ajustes.",
    "Target: build directory. Cleaning these products affects installed features.": "Destino: directorio de compilación. Limpiar estos productos afecta a las funciones instaladas.",
    "App: Jobs自定义右键菜单.app at /Applications/Jobs自定义右键菜单.app (build products can be cleaned after installation)": "App: Jobs自定义右键菜单.app en /Applications/Jobs自定义右键菜单.app (los productos de compilación se pueden limpiar tras la instalación)",
    "Drag the divider to resize the log. Features and logs scroll separately.": "Arrastrar el separador para cambiar la altura del registro. Las funciones y el registro se desplazan por separado.",
    "Feature list and live log divider": "Separador entre la lista de funciones y el registro en directo",
    "Live log (select and copy text)": "Registro en directo (seleccionar y copiar texto)",
    "Copy log": "Copiar el registro",
    "Log file": "Archivo de registro",
    "Auto-scroll": "Desplazamiento automático",
    "Ready. Select features and choose an action.": "Listo. Seleccionar funciones y una operación.",
    "A task is running. Wait for it to finish before closing.": "Hay una tarea en curso. Esperar a que termine antes de cerrar.",
    "Unable to view this log": "No se puede ver este registro",
    "Log is missing or unreadable: {0}": "El registro no existe o no se puede leer: {0}",
    "Unable to open log terminal: {0}": "No se puede abrir el terminal del registro: {0}",
    "Click to show this session's full log in a new terminal: {0}": "Pulsar para mostrar el registro completo de esta sesión en un nuevo terminal: {0}",
    "Selected {0} / {1}. Select at least one. Changing action keeps selection.": "Seleccionados {0} / {1}. Seleccionar al menos uno. Cambiar de operación conserva la selección.",
    "Selected {0} / {1}": "Seleccionados {0} / {1}",
    "{0}: select all": "{0}: seleccionar todo",
    "{0}: clear all": "{0}: desmarcar todo",
    "Waiting": "En espera",
    "Cleaning…": "Limpiando…",
    "Uninstalling…": "Desinstalando…",
    "Installing…": "Instalando…",
    "Cleaned": "Limpiado",
    "Uninstalled": "Desinstalado",
    "Installed": "Instalado",
    "Skipped": "Omitido",
    "Not installed; nothing to remove": "No instalado; nada que eliminar",
    "Failed: see log": "Error: ver el registro",
    "Selected": "Seleccionado",
    "Not selected": "No seleccionado",
    "App Management permission required": "Se requiere permiso de gestión de apps",
    "Permission check required": "Se requiere comprobar los permisos",
    "Stopped": "Detenido",
    "Completed": "Completado",
    "Task failed": "La tarea ha fallado",
    "{0}: processed {1} / {2} ({3}, completed items); {4} time {5}": "{0}: procesados {1} / {2} ({3}, elementos completados); tiempo de {4}: {5}",
    "{0} ready": "{0} listo",
    "{0} ready; {1} time {2}": "{0} listo; tiempo de {1}: {2}",
    "Finishing the current feature, then stopping; install time {0}": "Terminando la función actual antes de detenerse; tiempo de instalación: {0}",
    "{0}: {1} succeeded, {2} failed, {3} skipped; exit {4}; {5}; {6} time {7}": "{0}: {1} correctos, {2} fallidos, {3} omitidos; código {4}; {5}; tiempo de {6}: {7}",
    "{0}: {1} succeeded, {2} failed, {3} not installed, {4} skipped; exit {5}; {6}; {7} time {8}": "{0}: {1} correctos, {2} fallidos, {3} no instalados, {4} omitidos; código {5}; {6}; tiempo de {7}: {8}",
    "{0}: {1} succeeded, {2} failed, {3} not installed; exit {4}; {5}; {6} time {7}": "{0}: {1} correctos, {2} fallidos, {3} no instalados; código {4}; {5}; tiempo de {6}: {7}",
    "{0}: {1} succeeded, {2} failed; exit {3}; {4}; {5} time {6}": "{0}: {1} correctos, {2} fallidos; código {3}; {4}; tiempo de {5}: {6}",
    "Open projects in IDEs": "Abrir proyectos en los IDE",
    "Git tools": "Herramientas Git",
    "Files and general tools": "Archivos y herramientas generales",
    "Flutter tools · submenu actions": "Herramientas Flutter · acciones del submenú",
    "iOS / CocoaPods tools": "Herramientas iOS / CocoaPods",
    "Simulator tools": "Herramientas de simuladores",
    "Open project in Android Studio": "Abrir proyecto en Android Studio",
    "Open project in VSCode": "Abrir proyecto en VSCode",
    "Open project in Xcode": "Abrir proyecto en Xcode",
    "Pull latest Git changes": "Obtener los últimos cambios de Git",
    "Roll back Git commit": "Revertir a un commit de Git",
    "Open Git remote URL": "Abrir URL remota de Git",
    "Copy Git remote URL": "Copiar URL remota de Git",
    "Copy absolute path": "Copiar ruta absoluta",
    "Create file": "Crear archivo",
    "View file fingerprint Hash (SHA-256)": "Ver la huella del archivo (SHA-256)",
    "Grant execute permission (chmod +x)": "Conceder permiso de ejecución (chmod +x)",
    "Remove execute permission (chmod -x)": "Quitar permiso de ejecución (chmod -x)",
    "Re-sign IPA without building": "Volver a firmar el IPA sin compilar",
    "Show / hide files": "Mostrar / ocultar archivos",
    "Create iOS simulator": "Crear simulador iOS",
    "Create Android simulator": "Crear simulador Android",
    "Create Harmony simulator": "Crear simulador Harmony",
    "Check / repair Android simulator": "Comprobar / reparar simulador Android",
    "Check / repair Harmony simulator": "Comprobar / reparar simulador Harmony",
    "Configure Git proxy": "Configurar proxy de Git",
    "Open in terminal": "Abrir en el terminal",
    "View file contents in terminal": "Ver contenido del archivo en el terminal",
    "Merge file parts": "Unir partes del archivo",
    "Split file": "Dividir archivo",
    "Clean Android / OpenHarmony builds": "Limpiar compilaciones de Android / OpenHarmony",
    "Update code map (.codegraph)": "Actualizar mapa del código (.codegraph)",
    "Create empty commit and push in terminal": "Crear commit vacío y enviar desde el terminal",
    "Disable CocoaPods build sandbox": "Desactivar el aislamiento de compilación de CocoaPods",
    "Install CocoaPods": "Instalar CocoaPods",
    "CocoaPods source: CDN → GitHub": "Fuente de CocoaPods: CDN → GitHub",
    "Export all project Pod files": "Exportar todos los archivos Pod del proyecto",
    "Inspect Xcode project dependencies": "Inspeccionar dependencias del proyecto Xcode",
    "Update local CocoaPods repositories": "Actualizar repositorios locales de CocoaPods",
    "Check local Pod builds (.podspec folder)": "Comprobar compilaciones de Pods locales (carpeta .podspec)",
    "Install / update JobsCodeSnippets": "Instalar / actualizar JobsCodeSnippets",
    "Clean iOS / Xcode builds": "Limpiar compilaciones de iOS / Xcode",
    "Set up Flutter project": "Configurar proyecto Flutter",
    "Run Flutter project in terminal": "Ejecutar proyecto Flutter en el terminal",
    "Fetch Flutter Pub dependencies": "Obtener dependencias de Flutter Pub",
    "Fetch native Android dependencies": "Obtener dependencias nativas de Android",
    "Fetch CocoaPods dependencies": "Obtener dependencias de CocoaPods",
    "Fetch Swift Package dependencies": "Obtener dependencias de Swift Package",
    "Fetch OpenHarmony dependencies": "Obtener dependencias de OpenHarmony",
    "Prepare native libraries and build dependencies": "Preparar bibliotecas nativas y dependencias de compilación",
    "Download Flutter platform resources": "Descargar recursos de plataformas Flutter",
    "Fetch Web project dependencies": "Obtener dependencias del proyecto Web",
    "🧳 Export Flutter dependencies": "🧳 Exportar dependencias de Flutter",
    "Export Flutter Pub dependencies": "Exportar dependencias de Flutter Pub",
    "🔐 Export private Flutter dependencies": "🔐 Exportar dependencias privadas de Flutter",
    "📥 Import Flutter dependencies": "📥 Importar dependencias de Flutter",
    "Import Flutter Pub dependencies": "Importar dependencias de Flutter Pub",
    "📥 Import private Flutter dependencies": "📥 Importar dependencias privadas de Flutter",
    "Export Gradle distributions and cache": "Exportar distribuciones y caché de Gradle",
    "Import Gradle distributions and cache": "Importar distribuciones y caché de Gradle",
    "Export CocoaPods dependencies": "Exportar dependencias de CocoaPods",
    "Import CocoaPods dependencies": "Importar dependencias de CocoaPods",
    "Export Swift Package dependencies": "Exportar dependencias de Swift Package",
    "Import Swift Package dependencies": "Importar dependencias de Swift Package",
    "Export OpenHarmony dependencies": "Exportar dependencias de OpenHarmony",
    "Import OpenHarmony dependencies": "Importar dependencias de OpenHarmony",
    "Export native build cache": "Exportar caché de compilación nativa",
    "Import native build cache": "Importar caché de compilación nativa",
    "Export Flutter platform resources": "Exportar recursos de plataformas Flutter",
    "Import Flutter platform resources": "Importar recursos de plataformas Flutter",
    "Export Web dependencies": "Exportar dependencias Web",
    "Import Web dependencies": "Importar dependencias Web",
    "Show Flutter project SDK version": "Mostrar versión del SDK del proyecto Flutter",
    "Install / switch Flutter SDK": "Instalar / cambiar SDK de Flutter",
    "Install / switch Flutter@OpenHarmony SDK": "Instalar / cambiar SDK de Flutter@OpenHarmony",
    "Install / switch Java SDK": "Instalar / cambiar SDK de Java",
    "Download Gradle distributions and plugins": "Descargar distribuciones y complementos de Gradle",
    "Generate Flutter code": "Generar código Flutter",
    "Package iOS": "Empaquetar iOS",
    "Package Android": "Empaquetar Android",
    "Package Harmony (HAP + APP)": "Empaquetar Harmony (HAP + APP)",
    "Check native Flutter project": "Comprobar proyecto Flutter nativo",
    "Check OpenHarmony Flutter environment": "Comprobar entorno Flutter de OpenHarmony",
    "Repair missing Android SDK / platforms": "Reparar SDK / plataformas Android que faltan",
    "Repair Chinese Flutter project paths": "Reparar rutas chinas del proyecto Flutter",
    "Repair Flutter plugin namespaces": "Reparar espacios de nombres de complementos Flutter",
    "Convert relative Dart imports to packages": "Convertir imports relativos de Dart en imports de paquetes",
    "Clean current Flutter project builds": "Limpiar compilaciones del proyecto Flutter actual",
    "Dependency and cache maintenance": "Mantenimiento de dependencias y cachés",
    "Custom Explorer context menu": "Menú contextual de Explorer personalizado",
    "Jobs Windows · Custom Explorer context menu": "Jobs Windows · Menú contextual de Explorer personalizado",
    "Show a regular file's SHA-256 in a new terminal and copy the digest; do not modify or execute the file.": "Mostrar el SHA-256 de un archivo normal en un nuevo terminal y copiar su huella; no modificar ni ejecutar el archivo.",
    " (preview)": " (vista previa)",
    "⏪ Roll back Git commits": "⏪ Revertir a commits de Git",
    "▶️ Run Flutter project in terminal": "▶️ Ejecutar proyecto Flutter en el terminal",
    "☕ Install / switch Java SDK": "☕ Instalar / cambiar SDK de Java",
    "♻️ Flutter cleanup and maintenance": "♻️ Limpieza y mantenimiento de Flutter",
    "⚙️ Generate Flutter code": "⚙️ Generar código Flutter",
    "✅ Installed": "✅ Instalado",
    "⬇️ Pull latest Git changes": "⬇️ Obtener los últimos cambios de Git",
    "🌈 Create Harmony emulator": "🌈 Crear emulador Harmony",
    "🌐 Open Git remote URL": "🌐 Abrir URL remota de Git",
    "🌐 Fetch Web project dependencies": "🌐 Obtener dependencias del proyecto Web",
    "🌳 Open in Sourcetree": "🌳 Abrir en Sourcetree",
    "🏥 Flutter project diagnostics": "🏥 Diagnóstico del proyecto Flutter",
    "🏥 Flutter diagnostics": "🏥 Diagnóstico de Flutter",
    "🏷️ Repair Flutter plugin namespaces": "🏷️ Reparar espacios de nombres de complementos Flutter",
    "👁️ Show / hide hidden files": "👁️ Mostrar / ocultar archivos ocultos",
    "💓 OpenHarmony Flutter diagnostics": "💓 Diagnóstico Flutter de OpenHarmony",
    "💠 Open project in Visual Studio": "💠 Abrir proyecto en Visual Studio",
    "💻 Open in terminal": "💻 Abrir en el terminal",
    "📄 View file in terminal": "📄 Ver archivo en el terminal",
    "📋 Copy absolute path": "📋 Copiar ruta absoluta",
    "📚 Download Gradle distributions and build plugins": "📚 Descargar distribuciones y complementos de compilación de Gradle",
    "📝 Open project in VSCode": "📝 Abrir proyecto en VSCode",
    "📡 Configure Git dynamic proxy": "📡 Configurar proxy dinámico de Git",
    "📤 Import Flutter Pub dependencies": "📤 Importar dependencias de Flutter Pub",
    "📤 Import Flutter platform assets": "📤 Importar recursos de plataformas Flutter",
    "📤 Import Gradle distributions and dependency caches": "📤 Importar distribuciones y cachés de dependencias de Gradle",
    "📤 Import OpenHarmony dependencies": "📤 Importar dependencias de OpenHarmony",
    "📤 Import Web dependencies": "📤 Importar dependencias Web",
    "📤 Import native build caches": "📤 Importar cachés de compilación nativa",
    "📤 Import Flutter project dependencies": "📤 Importar dependencias del proyecto Flutter",
    "📤 Create empty commit and push": "📤 Crear commit vacío y enviar",
    "📥 Install Flutter dependencies (pub get)": "📥 Instalar dependencias de Flutter (pub get)",
    "📥 Import private Flutter project dependencies": "📥 Importar dependencias privadas del proyecto Flutter",
    "📥 Fetch Flutter Pub dependencies": "📥 Obtener dependencias de Flutter Pub",
    "📥 Fetch Flutter project dependencies": "📥 Obtener dependencias del proyecto Flutter",
    "📦 Package Flutter project": "📦 Empaquetar proyecto Flutter",
    "📦 Package HarmonyOS (HAP + APP)": "📦 Empaquetar HarmonyOS (HAP + APP)",
    "📱 Create Android emulator": "📱 Crear emulador Android",
    "🔀 Install / switch Flutter SDK (FVM)": "🔀 Instalar / cambiar SDK de Flutter (FVM)",
    "🔀 Install / switch Flutter SDK": "🔀 Instalar / cambiar SDK de Flutter",
    "🔀 Install / switch Flutter environments": "🔀 Instalar / cambiar entornos de Flutter",
    "🔎 Show current Flutter SDK version": "🔎 Mostrar versión del SDK de Flutter actual",
    "🔎 Show current Flutter project's SDK version": "🔎 Mostrar versión del SDK del proyecto Flutter actual",
    "🔐 Export private Flutter project dependencies": "🔐 Exportar dependencias privadas del proyecto Flutter",
    "🔎 Show file fingerprint Hash (SHA-256)": "🔎 Mostrar huella del archivo (SHA-256)",
    "➕ Grant execute permission": "➕ Conceder permiso de ejecución",
    "➖ Remove execute permission": "➖ Quitar permiso de ejecución",
    "🔒 Grant execute permission": "🔒 Conceder permiso de ejecución",
    "🔓 Remove execute permission": "🔓 Quitar permiso de ejecución",
    "🔗 Copy Git remote URL": "🔗 Copiar URL remota de Git",
    "🔧 Flutter repairs": "🔧 Reparaciones de Flutter",
    "🕊️ Install / switch Flutter@OpenHarmony SDK": "🕊️ Instalar / cambiar SDK de Flutter@OpenHarmony",
    "🕊️ Fetch OpenHarmony dependencies": "🕊️ Obtener dependencias de OpenHarmony",
    "🗃️ Download Flutter platform assets": "🗃️ Descargar recursos de plataformas Flutter",
    "🗺️ Update code map (.codegraph)": "🗺️ Actualizar mapa del código (.codegraph)",
    "🤖 Fetch Android native dependencies": "🤖 Obtener dependencias nativas de Android",
    "🦋 Flutter development": "🦋 Desarrollo Flutter",
    "🦋 Flutter development tools": "🦋 Herramientas de desarrollo Flutter",
    "🧑‍⚕️ Native Flutter diagnostics": "🧑‍⚕️ Diagnóstico de Flutter nativo",
    "🧩 Export Flutter Pub dependencies": "🧩 Exportar dependencias de Flutter Pub",
    "🧩 Export Flutter platform assets": "🧩 Exportar recursos de plataformas Flutter",
    "🧩 Export Flutter third-party dependencies": "🧩 Exportar dependencias de terceros de Flutter",
    "🧩 Export Gradle distributions and dependency caches": "🧩 Exportar distribuciones y cachés de dependencias de Gradle",
    "🧩 Export OpenHarmony dependencies": "🧩 Exportar dependencias de OpenHarmony",
    "🧩 Export Web dependencies": "🧩 Exportar dependencias Web",
    "🧩 Export native build caches": "🧩 Exportar cachés de compilación nativa",
    "🧩 Export Flutter project dependencies": "🧩 Exportar dependencias del proyecto Flutter",
    "🧩 Merge file volumes / ✂️ Split file": "🧩 Unir volúmenes / ✂️ Dividir archivo",
    "🧭 Open project in Android Studio": "🧭 Abrir proyecto en Android Studio",
    "🧯 Clean build output": "🧯 Limpiar resultados de compilación",
    "🧰 Diagnose and repair Harmony emulator": "🧰 Diagnosticar y reparar emulador Harmony",
    "🧱 Flutter assets and build dependencies": "🧱 Recursos de Flutter y dependencias de compilación",
    "🧱 Prepare native libraries and build dependencies (combined)": "🧱 Preparar bibliotecas nativas y dependencias de compilación (combinado)",
    "🧹 Clean build output": "🧹 Limpiar resultados de compilación",
    "🩹 Repair missing Android SDK / platforms": "🩹 Reparar SDK / plataformas Android que faltan",
    "🩺 Diagnose and repair Android emulator": "🩺 Diagnosticar y reparar emulador Android",
    "🚀 Set up Flutter project": "🚀 Configurar proyecto Flutter",
    "🚚 Import all Flutter dependencies": "🚚 Importar todas las dependencias de Flutter",
    "🚚 Export all Flutter dependencies": "🚚 Exportar todas las dependencias de Flutter",
    "Jobs Windows · Uninstall Explorer extensions": "Jobs Windows · Desinstalar extensiones de Explorer",
    "Jobs Windows · Install Explorer extensions": "Jobs Windows · Instalar extensiones de Explorer",
    "Jobs Windows · Manage Explorer extensions": "Jobs Windows · Gestionar extensiones de Explorer",
    "Jobs Windows · Configure Explorer extensions": "Jobs Windows · Configurar extensiones de Explorer",
    "Drag the divider vertically to resize the log": "Arrastrar el separador verticalmente para cambiar la altura del registro",
    "Drag vertically to resize the log": "Arrastrar verticalmente para cambiar la altura del registro",
    "Validate the Flutter project, diagnose the toolchain in terminal, and choose a Flutter SDK version with fzf.": "Validar el proyecto Flutter, diagnosticar la cadena de herramientas en el terminal y elegir una versión del SDK de Flutter con fzf.",
    "Validate the Flutter project, then show the active SDK version (project FVM or system SDK) in terminal and compare it with .fvmrc and pubspec constraints.": "Validar el proyecto Flutter y mostrar en el terminal la versión del SDK activo (FVM del proyecto o SDK del sistema) para compararla con .fvmrc y las restricciones de pubspec.",
    "Flutter roots only. Choose Android / iOS / HarmonyOS with fzf in CMD. Supports APK / AAB and HAP / APP. iOS requires MacOS and Xcode.": "Solo raíces de proyectos Flutter. Elegir Android / iOS / HarmonyOS con fzf en CMD. Admite APK / AAB y HAP / APP. iOS requiere MacOS y Xcode.",
    "Flutter roots only. Choose a device and view logs in CMD; the app continues in the background after the window closes.": "Solo raíces de proyectos Flutter. Elegir un dispositivo y ver los registros en CMD; la app sigue en segundo plano al cerrar la ventana.",
    "Flutter roots only. Read-only version and doctor diagnostics in terminal; no dependency fetching, cleanup, or tool upgrades.": "Solo raíces de proyectos Flutter. Diagnóstico de versión y doctor de solo lectura en el terminal; sin obtener dependencias, limpiar ni actualizar herramientas.",
    "Flutter roots only. Preview configured generators, then fetch dependencies and generate code after confirmation. Deleting conflicts requires separate opt-in.": "Solo raíces de proyectos Flutter. Previsualizar los generadores configurados y, tras confirmar, obtener dependencias y generar código. Eliminar conflictos requiere autorización adicional.",
    "Git worktree folders only. Detect nested repositories. Soft mode preserves the index and worktree; hard mode requires exact YES confirmation.": "Solo carpetas de árboles de trabajo Git. Detectar repositorios anidados. El modo soft conserva el índice y el árbol de trabajo; el modo hard exige confirmar exactamente con YES.",
    "Desktop background on x64 Windows only. Missing tools come from the SDL mirror; missing system images come from the official Emulator. Enter selects a stable phone image; confirm its license to create and start a unique instance.": "Solo fondo del escritorio en Windows x64. Las herramientas que faltan se obtienen del espejo SDL; las imágenes del sistema que faltan, del Emulator oficial. Intro selecciona una imagen estable de teléfono; confirmar su licencia para crear e iniciar una instancia única.",
    "Manage only this package's actions. Unselected actions remain when uninstalling.": "Gestionar solo las acciones de este paquete. Las acciones no seleccionadas se conservan al desinstalar.",
    "Desktop background only. Configure user-level Git to prefer the system proxy and fall back to a direct connection.": "Solo fondo del escritorio. Configurar Git para el usuario de modo que prefiera el proxy del sistema y use conexión directa como alternativa.",
    "Desktop background only. Diagnose the SDK in CMD, choose a device and system image, then create or start an Android AVD.": "Solo fondo del escritorio. Diagnosticar el SDK en CMD, elegir un dispositivo y una imagen del sistema y crear o iniciar un AVD Android.",
    "Desktop background only. Check existing DevEco Emulator instances, then start one or confirm a nondestructive restart. Data is preserved.": "Solo fondo del escritorio. Comprobar las instancias existentes de DevEco Emulator y luego iniciar una o confirmar un reinicio no destructivo. Se conservan los datos.",
    "Desktop background only. Check emulator location and /data; optionally reset caches, precisely uninstall, back up the AVD, and retest with a cold boot.": "Solo fondo del escritorio. Comprobar la ubicación del emulador y /data; opcionalmente restablecer cachés, desinstalar de forma precisa, respaldar el AVD y repetir la prueba con arranque en frío.",
    "Show the next action on the desktop background. Toggle hidden files for the current user's Explorer without changing protected-system-file settings.": "Mostrar la siguiente acción en el fondo del escritorio. Alternar los archivos ocultos del Explorer del usuario actual sin cambiar la configuración de archivos protegidos del sistema.",
    "Visible only for nonempty native Android or valid Flutter (official / HarmonyOS) project roots. Validated again before opening.": "Visible solo para raíces no vacías de proyectos Android nativos o Flutter válidos (oficial / HarmonyOS). Se valida otra vez antes de abrir.",
    "Preview: the selection is shown in the log. No installation or uninstallation was performed.": "Vista previa: la selección aparece en el registro. No se ha instalado ni desinstalado nada.",
    "Preview only. Confirming displays the selection in the log without installing, uninstalling, or writing state or registry entries.": "Solo vista previa. Confirmar muestra la selección en el registro sin instalar, desinstalar ni escribir el estado o el registro del sistema.",
    "Deployed copies use their bound location. To change it, open the manager from the source directory. Default installations run in the current user's LocalAppData; local builds run under this package's work directory and stop working if it moves.": "Las copias desplegadas usan su ubicación vinculada. Para cambiarla, abrir el gestor desde el directorio de fuentes. Las instalaciones predeterminadas se ejecutan en LocalAppData del usuario actual; las compilaciones locales, en el directorio de trabajo del paquete, y dejan de funcionar si se mueve.",
    "Prefer Windows Terminal; otherwise use system PowerShell.": "Preferir Windows Terminal; si no está disponible, usar PowerShell del sistema.",
    "Could not save preferences: ": "No se han podido guardar las preferencias: ",
    "Save settings": "Guardar configuración",
    "Protect local changes. On conflict, choose to restore, discard changes, or commit and retry.": "Proteger los cambios locales. En caso de conflicto, elegir restaurar, descartar los cambios o crear un commit y reintentar.",
    "All operations completed. Copy the log or close the panel.": "Todas las operaciones han terminado. Copiar el registro o cerrar el panel.",
    "Other context-menu features": "Otras funciones del menú contextual",
    "Create or synchronize the code map for the current directory.": "Crear o sincronizar el mapa del código del directorio actual.",
    "Feature and log divider": "Separador entre funciones y registro",
    "Select features, then confirm. Unselected features remain. Hover for installation details.": "Seleccionar funciones y confirmar. Las no seleccionadas se conservan. Pasar el cursor para ver detalles de instalación.",
    "Checked features are installed; unchecked ones are uninstalled. Saving an empty selection disables all installed features.": "Las funciones marcadas se instalan; las desmarcadas se desinstalan. Guardar una selección vacía desactiva todas las funciones instaladas.",
    "Select features to install. Enabled sibling actions and other unselected features remain.": "Seleccionar las funciones que se van a instalar. Las acciones relacionadas habilitadas y las demás funciones no seleccionadas se conservan.",
    "Total uninstall time": "Tiempo total de desinstalación",
    "Uninstall selected": "Desinstalar selección",
    "Uninstall selected features": "Desinstalar funciones seleccionadas",
    "Uninstall time": "Tiempo de desinstalación",
    "Cancel": "Cancelar",
    "Uninstall only selected installed features. Other features, logs, backups and tools remain.": "Desinstalar solo las funciones instaladas seleccionadas. Las demás funciones, registros, copias de seguridad y herramientas se conservan.",
    "Change only the current user's ExecuteFile ACL for a single regular NTFS file after confirmation. Does not launch the file or change global policy.": "Tras confirmar, cambiar solo la ACL ExecuteFile del usuario actual para un único archivo normal NTFS. No ejecuta el archivo ni cambia la directiva global.",
    "View a single regular file. Files over 1 MiB or suspected binary files require YES in the terminal.": "Ver un único archivo normal. Los archivos de más de 1 MiB o sospechosos de ser binarios requieren YES en el terminal.",
    "Clean only the selected packages' build workspaces. Installed DLLs, scripts, settings and registry entries remain.": "Limpiar solo los espacios de compilación de los paquetes seleccionados. Se conservan las DLL, scripts, configuraciones y entradas del registro instalados.",
    "Copy full log": "Copiar registro completo",
    "Copy the original remote URL for the current branch.": "Copiar la URL remota original de la rama actual.",
    "Copy the absolute path of a file or folder.": "Copiar la ruta absoluta de un archivo o carpeta.",
    "Could not copy the log: ": "No se ha podido copiar el registro: ",
    "Failed — open log": "Error — abrir registro",
    "Install / update": "Instalar / actualizar",
    "Install / update selected features": "Instalar / actualizar funciones seleccionadas",
    "Total install time": "Tiempo total de instalación",
    "Install time": "Tiempo de instalación",
    "Merge appears for a complete selected volume set; split appears for one regular file. Originals are always preserved.": "Unir aparece al seleccionar un conjunto completo de volúmenes; dividir aparece para un único archivo normal. Los originales siempre se conservan.",
    "Live log (drag the divider to resize)": "Registro en directo (arrastrar el separador para cambiar su altura)",
    "Installation stopped after the current package transaction. Unstarted items are marked Not run.": "Instalación detenida tras la transacción del paquete actual. Los elementos no iniciados se marcan como No ejecutado.",
    "Stop requested. Waiting for the current package transaction; later items will not run.": "Se ha solicitado detener. Esperando la transacción del paquete actual; los elementos siguientes no se ejecutarán.",
    "Selected {0} / {1}. Closing or cancelling makes no changes.": "Seleccionados {0} / {1}. Cerrar o cancelar no realiza cambios.",
    "Hover for feature details. Windows 11: right-click → Show more options.": "Pasar el cursor para ver detalles. Windows 11: clic derecho → Mostrar más opciones.",
    "Could not open the full log: ": "No se ha podido abrir el registro completo: ",
    "Open the repository website for the current Git worktree.": "Abrir el sitio web del repositorio del árbol de trabajo Git actual.",
    "Open the solution or project at the current directory level.": "Abrir la solución o el proyecto del nivel de directorio actual.",
    "Export resolved third-party Pub sources and licenses from the project lockfile. Press Enter to use the desktop as output.": "Exportar fuentes de terceros de Pub resueltas y sus licencias desde el archivo de bloqueo del proyecto. Pulsar Intro para usar el escritorio como destino.",
    "An operation is running. Wait for the transaction to finish before closing. Logs can be copied at any time.": "Hay una operación en curso. Esperar a que termine la transacción antes de cerrar. Los registros se pueden copiar en cualquier momento.",
    "Could not build the operation plan: ": "No se ha podido crear el plan de operación: ",
    "Could not start the operation: ": "No se ha podido iniciar la operación: ",
    "Log: ": "Registro: ",
    "🈶 Repair Chinese paths in Flutter project": "🈶 Reparar rutas chinas del proyecto Flutter",
    "Not installed; nothing to uninstall": "No instalado; nada que desinstalar",
    "Not installed": "No instalado",
    "Not run": "No ejecutado",
    "This feature": "Esta función",
    "Local build directory (moving or cleaning it disables the menu)": "Directorio de compilación local (moverlo o limpiarlo desactiva el menú)",
    "Validate the branch, staging area and upstream, then confirm the push.": "Validar la rama, el área de preparación y el remoto de seguimiento y confirmar el envío.",
    "Validate the Flutter project, then fetch dependencies.": "Validar el proyecto Flutter y obtener las dependencias.",
    "Installing / updating…": "Instalando / actualizando…",
    "This entry has been removed. Existing installations can be uninstalled but cannot be reinstalled.": "Esta entrada se ha eliminado. Las instalaciones existentes se pueden desinstalar, pero no reinstalar.",
    "No features require processing; ": "No hay funciones que procesar; ",
    "No features require processing. No settings were changed.": "No hay funciones que procesar. No se ha cambiado ninguna configuración.",
    "Total cleanup time": "Tiempo total de limpieza",
    "Cleanup time": "Tiempo de limpieza",
    "Click to read the full session log in a new PowerShell window. The current task continues.": "Pulsar para leer el registro completo de la sesión en una nueva ventana de PowerShell. La tarea actual continúa.",
    "Pending": "Pendiente",
    "Waiting to stop…": "Esperando para detenerse…",
    "Ordered Flutter development, diagnostics, repair and maintenance tools. Regular actions use project FVM; environment setup supports FVM / system Flutter and jEnv / system Java.": "Herramientas ordenadas de desarrollo, diagnóstico, reparación y mantenimiento de Flutter. Las acciones habituales usan el FVM del proyecto; la configuración admite FVM / Flutter del sistema y jEnv / Java del sistema.",
    "Detect the Flutter / Android project and preview cleanup scope. iOS cleanup is unavailable on Windows.": "Detectar el proyecto Flutter / Android y previsualizar el alcance de la limpieza. La limpieza de iOS no está disponible en Windows.",
    "Could not read preferences: ": "No se han podido leer las preferencias: ",
    "Could not read the log: ": "No se ha podido leer el registro: ",
    "Explorer context-menu extensions · ": "Extensiones del menú contextual de Explorer · ",
    "Explorer extensions · Manage": "Extensiones de Explorer · Gestionar",
    "Return selection": "Devolver selección",
    "Exit code: ": "Código de salida: ",
    "Choose an operation and select features. Unselected features remain; only installed features can be uninstalled.": "Elegir una operación y seleccionar funciones. Las no seleccionadas se conservan; solo se pueden desinstalar funciones instaladas.",
    "Some features failed; other selected features were still processed. Click a failed status to open the full session log.": "Algunas funciones han fallado; las demás seleccionadas se han procesado igualmente. Pulsar un estado de error para abrir el registro completo de la sesión.",
    "Available for nonempty regular directories outside iOS projects, including Flutter roots. Validated again before opening.": "Disponible para directorios normales no vacíos fuera de proyectos iOS, incluidas las raíces Flutter. Se valida otra vez antes de abrir.",
    "Default installation location (recommended)": "Ubicación de instalación predeterminada (recomendada)",
    "{0}; Results: succeeded {1}; nothing to uninstall {2}; failed {3}; not run {4}": "{0}; resultados: correctos {1}; nada que desinstalar {2}; fallidos {3}; no ejecutados {4}",
    "{0} Exit code: {1}.": "{0} Código de salida: {1}.",
    "{0} {1}": "{0} {1}",
    "{0}{1} {2}": "{0}{1} {2}",
    "{0} in progress; completed {1} / {2} ({3}% by completed items); {4} {5}": "{0} en curso; completados {1} / {2} ({3}% por elementos completados); {4} {5}",
    "{0} Completed {1} / {2} ({3}% by completed items); {4} {5}": "{0} Completados {1} / {2} ({3}% por elementos completados); {4} {5}",
    "🫥 Hide / show selected items": "🫥 Ocultar / mostrar la selección",
    "Set the Hidden attribute of selected files or folders, including multiple selections; do not recurse, rename, or change global visibility preferences.": "Configura el atributo oculto de los archivos o carpetas seleccionados, con selección múltiple; sin recursión, cambio de nombre ni cambios en las preferencias globales.",
    "Permanently delete (skip Recycle Bin)": "Eliminar permanentemente (sin Papelera)",
    "Directly delete selected files or folders; confirm with the red left button or cancel with the blue right button. Cancellation is the default; deleted items cannot be restored from the Recycle Bin.": "Elimina directamente los archivos o carpetas seleccionados. Confirmación roja a la izquierda, cancelación azul a la derecha; cancelar es la opción predeterminada. No se puede restaurar desde la Papelera."
  },
  "de": {
    "Close management panel": "Verwaltungsfenster schließen",
    "Minimize to tray": "In den Infobereich minimieren",
    "Exit completely": "Vollständig beenden",
    "Keep window open": "Fenster geöffnet lassen",
    "The manager is idle. Keep it in the system tray, or exit completely.": "Es läuft keine Aufgabe. Behalten Sie das Fenster im Infobereich oder beenden Sie das Programm vollständig.",
    "Show management panel": "Verwaltungsfenster anzeigen",
    "Current status": "Aktueller Status",
    "A task is running. Exit is unavailable; restore the window to view logs.": "Eine Aufgabe läuft. Vollständiges Beenden ist gesperrt; stellen Sie das Fenster wieder her, um Protokolle zu sehen.",
    "The system tray is unavailable. The window will remain open.": "Der Infobereich ist nicht verfügbar. Das Fenster bleibt geöffnet.",
    "💽 Disk free space": "💽 Freier Speicherplatz",
    "Show total local disk free / capacity and a two-decimal percentage. Click to choose cleanup in a separate terminal; changes require confirmation.": "Freien lokalen Speicher / Gesamtkapazität und den Anteil mit zwei Dezimalstellen anzeigen. Ein Klick öffnet die Bereinigungsauswahl in einem eigenen Terminal; Änderungen müssen bestätigt werden.",
    "Create script launcher…": "Skriptstarter erstellen…",
    "🔗 Create script launcher…": "🔗 Skriptstarter erstellen…",
    "Create a relative launcher beside a same-name .cmd/.bat/.ps1 script folder; do not run or modify the source script.": "Erstellt einen relativen Starter neben dem gleichnamigen .cmd/.bat/.ps1-Skriptordner, ohne das Originalskript auszuführen oder zu ändern.",
    "Theme": "Design",
    "Language": "Sprache",
    "🎨 Theme": "🎨 Design",
    "🌐 Language": "🌐 Sprache",
    "Follow system": "Systemeinstellung",
    "Dark": "Dunkel",
    "Light": "Hell",
    "Jobs Finder Extension Manager": "Jobs Finder-Erweiterungsverwaltung",
    "Customize Finder Context Menu": "Finder-Kontextmenü anpassen",
    "Close Manager": "Verwaltung schließen",
    "Edit": "Bearbeiten",
    "Copy": "Kopieren",
    "Select all": "Alle auswählen",
    "Clear all": "Auswahl aufheben",
    "Close": "Schließen",
    "OK": "Bestätigen",
    "Install": "Installieren",
    "Install / Update": "Installieren / Aktualisieren",
    "Uninstall": "Deinstallieren",
    "Cleanup": "Bereinigung",
    "Clean build products": "Build-Erzeugnisse bereinigen",
    "🧹 Clean build products": "🧹 Build-Erzeugnisse bereinigen",
    "Stop installation": "Installation stoppen",
    "Stopping…": "Wird gestoppt…",
    "Action: install / update or uninstall": "Aktion: installieren / aktualisieren oder deinstallieren",
    "Uninstall removes selected menus only. Group selection affects its own group.": "Die Deinstallation entfernt nur ausgewählte Menüs. Eine Gruppenauswahl betrifft nur die jeweilige Gruppe.",
    "Install / uninstall with the combined App in Applications": "Mit der kombinierten App unter Programme installieren / deinstallieren",
    "Install or uninstall the combined App in Applications": "Die kombinierte App unter Programme installieren oder deinstallieren",
    "Selected: manage features in /Applications/Jobs自定义右键菜单.app. Otherwise use the build directory.": "Ausgewählt: Funktionen in /Applications/Jobs自定义右键菜单.app verwalten. Andernfalls das Build-Verzeichnis verwenden.",
    "Clean this build after successful installation": "Diesen Build nach erfolgreicher Installation bereinigen",
    "Clean this build only after the combined App is installed and verified in Applications. Keep failed builds.": "Diesen Build erst bereinigen, nachdem die kombinierte App unter Programme installiert und geprüft wurde. Fehlgeschlagene Builds behalten.",
    "Clean build products of selected features without installing or uninstalling.": "Build-Erzeugnisse der ausgewählten Funktionen bereinigen, ohne zu installieren oder zu deinstallieren.",
    "Clean selected features' build products": "Build-Erzeugnisse ausgewählter Funktionen bereinigen",
    "Open Privacy & Security": "Datenschutz & Sicherheit öffnen",
    "Add and enable Jobs右键菜单管理面板.app in Privacy & Security → App Management. This only opens Settings.": "Jobs右键菜单管理面板.app unter Datenschutz & Sicherheit → App-Verwaltung hinzufügen und aktivieren. Hiermit werden nur die Einstellungen geöffnet.",
    "Target: build directory. Cleaning these products affects installed features.": "Ziel: Build-Verzeichnis. Die Bereinigung dieser Erzeugnisse beeinträchtigt installierte Funktionen.",
    "App: Jobs自定义右键菜单.app at /Applications/Jobs自定义右键菜单.app (build products can be cleaned after installation)": "App: Jobs自定义右键菜单.app unter /Applications/Jobs自定义右键菜单.app (Build-Erzeugnisse können nach der Installation bereinigt werden)",
    "Drag the divider to resize the log. Features and logs scroll separately.": "Trennleiste ziehen, um die Protokollgröße zu ändern. Funktionen und Protokoll lassen sich getrennt scrollen.",
    "Feature list and live log divider": "Trennleiste zwischen Funktionsliste und Live-Protokoll",
    "Live log (select and copy text)": "Live-Protokoll (Text auswählen und kopieren)",
    "Copy log": "Protokoll kopieren",
    "Log file": "Protokolldatei",
    "Auto-scroll": "Automatisch scrollen",
    "Ready. Select features and choose an action.": "Bereit. Funktionen und eine Aktion auswählen.",
    "A task is running. Wait for it to finish before closing.": "Eine Aufgabe läuft. Vor dem Schließen auf ihren Abschluss warten.",
    "Unable to view this log": "Dieses Protokoll kann nicht angezeigt werden",
    "Log is missing or unreadable: {0}": "Protokoll fehlt oder ist nicht lesbar: {0}",
    "Unable to open log terminal: {0}": "Protokollterminal konnte nicht geöffnet werden: {0}",
    "Click to show this session's full log in a new terminal: {0}": "Klicken, um das vollständige Sitzungsprotokoll in einem neuen Terminal anzuzeigen: {0}",
    "Selected {0} / {1}. Select at least one. Changing action keeps selection.": "Ausgewählt: {0} / {1}. Mindestens einen Eintrag auswählen. Die Auswahl bleibt beim Aktionswechsel erhalten.",
    "Selected {0} / {1}": "Ausgewählt: {0} / {1}",
    "{0}: select all": "{0}: alle auswählen",
    "{0}: clear all": "{0}: Auswahl aufheben",
    "Waiting": "Warten",
    "Cleaning…": "Wird bereinigt…",
    "Uninstalling…": "Wird deinstalliert…",
    "Installing…": "Wird installiert…",
    "Cleaned": "Bereinigt",
    "Uninstalled": "Deinstalliert",
    "Installed": "Installiert",
    "Skipped": "Übersprungen",
    "Not installed; nothing to remove": "Nicht installiert; nichts zu entfernen",
    "Failed: see log": "Fehlgeschlagen: siehe Protokoll",
    "Selected": "Ausgewählt",
    "Not selected": "Nicht ausgewählt",
    "App Management permission required": "Berechtigung für App-Verwaltung erforderlich",
    "Permission check required": "Berechtigungsprüfung erforderlich",
    "Stopped": "Gestoppt",
    "Completed": "Abgeschlossen",
    "Task failed": "Aufgabe fehlgeschlagen",
    "{0}: processed {1} / {2} ({3}, completed items); {4} time {5}": "{0}: {1} / {2} bearbeitet ({3}, abgeschlossene Einträge); Zeit für {4}: {5}",
    "{0} ready": "{0} bereit",
    "{0} ready; {1} time {2}": "{0} bereit; Zeit für {1}: {2}",
    "Finishing the current feature, then stopping; install time {0}": "Aktuelle Funktion wird abgeschlossen, danach Stopp; Installationszeit: {0}",
    "{0}: {1} succeeded, {2} failed, {3} skipped; exit {4}; {5}; {6} time {7}": "{0}: {1} erfolgreich, {2} fehlgeschlagen, {3} übersprungen; Exit-Code {4}; {5}; Zeit für {6}: {7}",
    "{0}: {1} succeeded, {2} failed, {3} not installed, {4} skipped; exit {5}; {6}; {7} time {8}": "{0}: {1} erfolgreich, {2} fehlgeschlagen, {3} nicht installiert, {4} übersprungen; Exit-Code {5}; {6}; Zeit für {7}: {8}",
    "{0}: {1} succeeded, {2} failed, {3} not installed; exit {4}; {5}; {6} time {7}": "{0}: {1} erfolgreich, {2} fehlgeschlagen, {3} nicht installiert; Exit-Code {4}; {5}; Zeit für {6}: {7}",
    "{0}: {1} succeeded, {2} failed; exit {3}; {4}; {5} time {6}": "{0}: {1} erfolgreich, {2} fehlgeschlagen; Exit-Code {3}; {4}; Zeit für {5}: {6}",
    "Open projects in IDEs": "Projekte in Entwicklungsumgebungen öffnen",
    "Git tools": "Git-Werkzeuge",
    "Files and general tools": "Dateien und allgemeine Werkzeuge",
    "Flutter tools · submenu actions": "Flutter-Werkzeuge · Untermenüaktionen",
    "iOS / CocoaPods tools": "iOS-/CocoaPods-Werkzeuge",
    "Simulator tools": "Simulatorwerkzeuge",
    "Open project in Android Studio": "Projekt in Android Studio öffnen",
    "Open project in VSCode": "Projekt in VSCode öffnen",
    "Open project in Xcode": "Projekt in Xcode öffnen",
    "Pull latest Git changes": "Neueste Git-Änderungen abrufen",
    "Roll back Git commit": "Git-Commit zurücksetzen",
    "Open Git remote URL": "Git-Remote-URL öffnen",
    "Copy Git remote URL": "Git-Remote-URL kopieren",
    "Copy absolute path": "Absoluten Pfad kopieren",
    "Create file": "Datei erstellen",
    "View file fingerprint Hash (SHA-256)": "Dateiprüfsumme anzeigen (SHA-256)",
    "Grant execute permission (chmod +x)": "Ausführungsrecht erteilen (chmod +x)",
    "Remove execute permission (chmod -x)": "Ausführungsrecht entziehen (chmod -x)",
    "Re-sign IPA without building": "IPA ohne Build erneut signieren",
    "Show / hide files": "Dateien ein-/ausblenden",
    "Create iOS simulator": "iOS-Simulator erstellen",
    "Create Android simulator": "Android-Simulator erstellen",
    "Create Harmony simulator": "Harmony-Simulator erstellen",
    "Check / repair Android simulator": "Android-Simulator prüfen / reparieren",
    "Check / repair Harmony simulator": "Harmony-Simulator prüfen / reparieren",
    "Configure Git proxy": "Git-Proxy konfigurieren",
    "Open in terminal": "Im Terminal öffnen",
    "View file contents in terminal": "Dateiinhalt im Terminal anzeigen",
    "Merge file parts": "Dateiteile zusammenführen",
    "Split file": "Datei aufteilen",
    "Clean Android / OpenHarmony builds": "Android-/OpenHarmony-Builds bereinigen",
    "Update code map (.codegraph)": "Codekarte aktualisieren (.codegraph)",
    "Create empty commit and push in terminal": "Leeren Commit erstellen und im Terminal pushen",
    "Disable CocoaPods build sandbox": "CocoaPods-Build-Sandbox deaktivieren",
    "Install CocoaPods": "CocoaPods installieren",
    "CocoaPods source: CDN → GitHub": "CocoaPods-Quelle: CDN → GitHub",
    "Export all project Pod files": "Alle Pod-Dateien des Projekts exportieren",
    "Inspect Xcode project dependencies": "Xcode-Projektabhängigkeiten untersuchen",
    "Update local CocoaPods repositories": "Lokale CocoaPods-Repositories aktualisieren",
    "Check local Pod builds (.podspec folder)": "Lokale Pod-Builds prüfen (.podspec-Ordner)",
    "Install / update JobsCodeSnippets": "JobsCodeSnippets installieren / aktualisieren",
    "Clean iOS / Xcode builds": "iOS-/Xcode-Builds bereinigen",
    "Set up Flutter project": "Flutter-Projekt einrichten",
    "Run Flutter project in terminal": "Flutter-Projekt im Terminal ausführen",
    "Fetch Flutter Pub dependencies": "Flutter-Pub-Abhängigkeiten abrufen",
    "Fetch native Android dependencies": "Native Android-Abhängigkeiten abrufen",
    "Fetch CocoaPods dependencies": "CocoaPods-Abhängigkeiten abrufen",
    "Fetch Swift Package dependencies": "Swift-Package-Abhängigkeiten abrufen",
    "Fetch OpenHarmony dependencies": "OpenHarmony-Abhängigkeiten abrufen",
    "Prepare native libraries and build dependencies": "Native Bibliotheken und Build-Abhängigkeiten vorbereiten",
    "Download Flutter platform resources": "Flutter-Plattformressourcen herunterladen",
    "Fetch Web project dependencies": "Web-Projektabhängigkeiten abrufen",
    "🧳 Export Flutter dependencies": "🧳 Flutter-Abhängigkeiten exportieren",
    "Export Flutter Pub dependencies": "Flutter-Pub-Abhängigkeiten exportieren",
    "🔐 Export private Flutter dependencies": "🔐 Private Flutter-Abhängigkeiten exportieren",
    "📥 Import Flutter dependencies": "📥 Flutter-Abhängigkeiten importieren",
    "Import Flutter Pub dependencies": "Flutter-Pub-Abhängigkeiten importieren",
    "📥 Import private Flutter dependencies": "📥 Private Flutter-Abhängigkeiten importieren",
    "Export Gradle distributions and cache": "Gradle-Distributionen und -Cache exportieren",
    "Import Gradle distributions and cache": "Gradle-Distributionen und -Cache importieren",
    "Export CocoaPods dependencies": "CocoaPods-Abhängigkeiten exportieren",
    "Import CocoaPods dependencies": "CocoaPods-Abhängigkeiten importieren",
    "Export Swift Package dependencies": "Swift-Package-Abhängigkeiten exportieren",
    "Import Swift Package dependencies": "Swift-Package-Abhängigkeiten importieren",
    "Export OpenHarmony dependencies": "OpenHarmony-Abhängigkeiten exportieren",
    "Import OpenHarmony dependencies": "OpenHarmony-Abhängigkeiten importieren",
    "Export native build cache": "Nativen Build-Cache exportieren",
    "Import native build cache": "Nativen Build-Cache importieren",
    "Export Flutter platform resources": "Flutter-Plattformressourcen exportieren",
    "Import Flutter platform resources": "Flutter-Plattformressourcen importieren",
    "Export Web dependencies": "Web-Abhängigkeiten exportieren",
    "Import Web dependencies": "Web-Abhängigkeiten importieren",
    "Show Flutter project SDK version": "SDK-Version des Flutter-Projekts anzeigen",
    "Install / switch Flutter SDK": "Flutter-SDK installieren / wechseln",
    "Install / switch Flutter@OpenHarmony SDK": "Flutter@OpenHarmony-SDK installieren / wechseln",
    "Install / switch Java SDK": "Java-SDK installieren / wechseln",
    "Download Gradle distributions and plugins": "Gradle-Distributionen und -Plugins herunterladen",
    "Generate Flutter code": "Flutter-Code generieren",
    "Package iOS": "iOS-Paket erstellen",
    "Package Android": "Android-Paket erstellen",
    "Package Harmony (HAP + APP)": "Harmony-Paket erstellen (HAP + APP)",
    "Check native Flutter project": "Natives Flutter-Projekt prüfen",
    "Check OpenHarmony Flutter environment": "OpenHarmony-Flutter-Umgebung prüfen",
    "Repair missing Android SDK / platforms": "Fehlendes Android-SDK / fehlende Plattformen reparieren",
    "Repair Chinese Flutter project paths": "Chinesische Pfade im Flutter-Projekt reparieren",
    "Repair Flutter plugin namespaces": "Namespaces von Flutter-Plugins reparieren",
    "Convert relative Dart imports to packages": "Relative Dart-Importe in Paketimporte umwandeln",
    "Clean current Flutter project builds": "Builds des aktuellen Flutter-Projekts bereinigen",
    "Dependency and cache maintenance": "Abhängigkeiten und Caches warten",
    "Custom Explorer context menu": "Explorer-Kontextmenü anpassen",
    "Jobs Windows · Custom Explorer context menu": "Jobs Windows · Explorer-Kontextmenü anpassen",
    "Show a regular file's SHA-256 in a new terminal and copy the digest; do not modify or execute the file.": "SHA-256 einer regulären Datei in einem neuen Terminal anzeigen und die Prüfsumme kopieren; die Datei weder ändern noch ausführen.",
    " (preview)": " (Vorschau)",
    "⏪ Roll back Git commits": "⏪ Git-Commits zurücksetzen",
    "▶️ Run Flutter project in terminal": "▶️ Flutter-Projekt im Terminal ausführen",
    "☕ Install / switch Java SDK": "☕ Java-SDK installieren / wechseln",
    "♻️ Flutter cleanup and maintenance": "♻️ Flutter bereinigen und warten",
    "⚙️ Generate Flutter code": "⚙️ Flutter-Code generieren",
    "✅ Installed": "✅ Installiert",
    "⬇️ Pull latest Git changes": "⬇️ Neueste Git-Änderungen abrufen",
    "🌈 Create Harmony emulator": "🌈 Harmony-Emulator erstellen",
    "🌐 Open Git remote URL": "🌐 Git-Remote-URL öffnen",
    "🌐 Fetch Web project dependencies": "🌐 Web-Projektabhängigkeiten abrufen",
    "🌳 Open in Sourcetree": "🌳 In Sourcetree öffnen",
    "🏥 Flutter project diagnostics": "🏥 Flutter-Projektdiagnose",
    "🏥 Flutter diagnostics": "🏥 Flutter-Diagnose",
    "🏷️ Repair Flutter plugin namespaces": "🏷️ Namespaces von Flutter-Plugins reparieren",
    "👁️ Show / hide hidden files": "👁️ Versteckte Dateien ein-/ausblenden",
    "💓 OpenHarmony Flutter diagnostics": "💓 OpenHarmony-Flutter-Diagnose",
    "💠 Open project in Visual Studio": "💠 Projekt in Visual Studio öffnen",
    "💻 Open in terminal": "💻 Im Terminal öffnen",
    "📄 View file in terminal": "📄 Datei im Terminal anzeigen",
    "📋 Copy absolute path": "📋 Absoluten Pfad kopieren",
    "📚 Download Gradle distributions and build plugins": "📚 Gradle-Distributionen und Build-Plugins herunterladen",
    "📝 Open project in VSCode": "📝 Projekt in VSCode öffnen",
    "📡 Configure Git dynamic proxy": "📡 Dynamischen Git-Proxy konfigurieren",
    "📤 Import Flutter Pub dependencies": "📤 Flutter-Pub-Abhängigkeiten importieren",
    "📤 Import Flutter platform assets": "📤 Flutter-Plattformressourcen importieren",
    "📤 Import Gradle distributions and dependency caches": "📤 Gradle-Distributionen und Abhängigkeitscaches importieren",
    "📤 Import OpenHarmony dependencies": "📤 OpenHarmony-Abhängigkeiten importieren",
    "📤 Import Web dependencies": "📤 Web-Abhängigkeiten importieren",
    "📤 Import native build caches": "📤 Native Build-Caches importieren",
    "📤 Import Flutter project dependencies": "📤 Flutter-Projektabhängigkeiten importieren",
    "📤 Create empty commit and push": "📤 Leeren Commit erstellen und pushen",
    "📥 Install Flutter dependencies (pub get)": "📥 Flutter-Abhängigkeiten installieren (pub get)",
    "📥 Import private Flutter project dependencies": "📥 Private Flutter-Projektabhängigkeiten importieren",
    "📥 Fetch Flutter Pub dependencies": "📥 Flutter-Pub-Abhängigkeiten abrufen",
    "📥 Fetch Flutter project dependencies": "📥 Flutter-Projektabhängigkeiten abrufen",
    "📦 Package Flutter project": "📦 Flutter-Projektpaket erstellen",
    "📦 Package HarmonyOS (HAP + APP)": "📦 HarmonyOS-Paket erstellen (HAP + APP)",
    "📱 Create Android emulator": "📱 Android-Emulator erstellen",
    "🔀 Install / switch Flutter SDK (FVM)": "🔀 Flutter-SDK installieren / wechseln (FVM)",
    "🔀 Install / switch Flutter SDK": "🔀 Flutter-SDK installieren / wechseln",
    "🔀 Install / switch Flutter environments": "🔀 Flutter-Umgebungen installieren / wechseln",
    "🔎 Show current Flutter SDK version": "🔎 Aktuelle Flutter-SDK-Version anzeigen",
    "🔎 Show current Flutter project's SDK version": "🔎 SDK-Version des aktuellen Flutter-Projekts anzeigen",
    "🔐 Export private Flutter project dependencies": "🔐 Private Flutter-Projektabhängigkeiten exportieren",
    "🔎 Show file fingerprint Hash (SHA-256)": "🔎 Dateiprüfsumme anzeigen (SHA-256)",
    "➕ Grant execute permission": "➕ Ausführungsrecht erteilen",
    "➖ Remove execute permission": "➖ Ausführungsrecht entziehen",
    "🔒 Grant execute permission": "🔒 Ausführungsrecht erteilen",
    "🔓 Remove execute permission": "🔓 Ausführungsrecht entziehen",
    "🔗 Copy Git remote URL": "🔗 Git-Remote-URL kopieren",
    "🔧 Flutter repairs": "🔧 Flutter-Reparaturen",
    "🕊️ Install / switch Flutter@OpenHarmony SDK": "🕊️ Flutter@OpenHarmony-SDK installieren / wechseln",
    "🕊️ Fetch OpenHarmony dependencies": "🕊️ OpenHarmony-Abhängigkeiten abrufen",
    "🗃️ Download Flutter platform assets": "🗃️ Flutter-Plattformressourcen herunterladen",
    "🗺️ Update code map (.codegraph)": "🗺️ Codekarte aktualisieren (.codegraph)",
    "🤖 Fetch Android native dependencies": "🤖 Native Android-Abhängigkeiten abrufen",
    "🦋 Flutter development": "🦋 Flutter-Entwicklung",
    "🦋 Flutter development tools": "🦋 Flutter-Entwicklungswerkzeuge",
    "🧑‍⚕️ Native Flutter diagnostics": "🧑‍⚕️ Native Flutter-Diagnose",
    "🧩 Export Flutter Pub dependencies": "🧩 Flutter-Pub-Abhängigkeiten exportieren",
    "🧩 Export Flutter platform assets": "🧩 Flutter-Plattformressourcen exportieren",
    "🧩 Export Flutter third-party dependencies": "🧩 Flutter-Drittanbieterabhängigkeiten exportieren",
    "🧩 Export Gradle distributions and dependency caches": "🧩 Gradle-Distributionen und Abhängigkeitscaches exportieren",
    "🧩 Export OpenHarmony dependencies": "🧩 OpenHarmony-Abhängigkeiten exportieren",
    "🧩 Export Web dependencies": "🧩 Web-Abhängigkeiten exportieren",
    "🧩 Export native build caches": "🧩 Native Build-Caches exportieren",
    "🧩 Export Flutter project dependencies": "🧩 Flutter-Projektabhängigkeiten exportieren",
    "🧩 Merge file volumes / ✂️ Split file": "🧩 Dateivolumes zusammenführen / ✂️ Datei aufteilen",
    "🧭 Open project in Android Studio": "🧭 Projekt in Android Studio öffnen",
    "🧯 Clean build output": "🧯 Build-Ausgaben bereinigen",
    "🧰 Diagnose and repair Harmony emulator": "🧰 Harmony-Emulator diagnostizieren und reparieren",
    "🧱 Flutter assets and build dependencies": "🧱 Flutter-Ressourcen und Build-Abhängigkeiten",
    "🧱 Prepare native libraries and build dependencies (combined)": "🧱 Native Bibliotheken und Build-Abhängigkeiten vorbereiten (kombiniert)",
    "🧹 Clean build output": "🧹 Build-Ausgaben bereinigen",
    "🩹 Repair missing Android SDK / platforms": "🩹 Fehlendes Android-SDK / fehlende Plattformen reparieren",
    "🩺 Diagnose and repair Android emulator": "🩺 Android-Emulator diagnostizieren und reparieren",
    "🚀 Set up Flutter project": "🚀 Flutter-Projekt einrichten",
    "🚚 Import all Flutter dependencies": "🚚 Alle Flutter-Abhängigkeiten importieren",
    "🚚 Export all Flutter dependencies": "🚚 Alle Flutter-Abhängigkeiten exportieren",
    "Jobs Windows · Uninstall Explorer extensions": "Jobs Windows · Explorer-Erweiterungen deinstallieren",
    "Jobs Windows · Install Explorer extensions": "Jobs Windows · Explorer-Erweiterungen installieren",
    "Jobs Windows · Manage Explorer extensions": "Jobs Windows · Explorer-Erweiterungen verwalten",
    "Jobs Windows · Configure Explorer extensions": "Jobs Windows · Explorer-Erweiterungen konfigurieren",
    "Drag the divider vertically to resize the log": "Trennleiste vertikal ziehen, um die Protokollgröße zu ändern",
    "Drag vertically to resize the log": "Vertikal ziehen, um die Protokollgröße zu ändern",
    "Validate the Flutter project, diagnose the toolchain in terminal, and choose a Flutter SDK version with fzf.": "Flutter-Projekt prüfen, die Werkzeugkette im Terminal diagnostizieren und mit fzf eine Flutter-SDK-Version wählen.",
    "Validate the Flutter project, then show the active SDK version (project FVM or system SDK) in terminal and compare it with .fvmrc and pubspec constraints.": "Flutter-Projekt prüfen, dann die aktive SDK-Version (Projekt-FVM oder System-SDK) im Terminal anzeigen und mit .fvmrc und den pubspec-Vorgaben vergleichen.",
    "Flutter roots only. Choose Android / iOS / HarmonyOS with fzf in CMD. Supports APK / AAB and HAP / APP. iOS requires MacOS and Xcode.": "Nur Flutter-Projektwurzeln. Android / iOS / HarmonyOS mit fzf in CMD wählen. Unterstützt APK / AAB und HAP / APP. iOS benötigt MacOS und Xcode.",
    "Flutter roots only. Choose a device and view logs in CMD; the app continues in the background after the window closes.": "Nur Flutter-Projektwurzeln. Gerät wählen und Protokolle in CMD anzeigen; die App läuft nach dem Schließen des Fensters im Hintergrund weiter.",
    "Flutter roots only. Read-only version and doctor diagnostics in terminal; no dependency fetching, cleanup, or tool upgrades.": "Nur Flutter-Projektwurzeln. Schreibgeschützte Versions- und doctor-Diagnose im Terminal; kein Abruf von Abhängigkeiten, keine Bereinigung und keine Werkzeug-Upgrades.",
    "Flutter roots only. Preview configured generators, then fetch dependencies and generate code after confirmation. Deleting conflicts requires separate opt-in.": "Nur Flutter-Projektwurzeln. Konfigurierte Generatoren anzeigen, dann nach Bestätigung Abhängigkeiten abrufen und Code generieren. Das Löschen von Konflikten erfordert eine gesonderte Zustimmung.",
    "Git worktree folders only. Detect nested repositories. Soft mode preserves the index and worktree; hard mode requires exact YES confirmation.": "Nur Git-Arbeitsverzeichnisse. Verschachtelte Repositories erkennen. Der Modus soft erhält Index und Arbeitsverzeichnis; der Modus hard verlangt die exakte Bestätigung YES.",
    "Desktop background on x64 Windows only. Missing tools come from the SDL mirror; missing system images come from the official Emulator. Enter selects a stable phone image; confirm its license to create and start a unique instance.": "Nur Desktop-Hintergrund unter Windows x64. Fehlende Werkzeuge kommen vom SDL-Mirror; fehlende Systemabbilder vom offiziellen Emulator. Eingabe wählt ein stabiles Telefonabbild; dessen Lizenz bestätigen, um eine eindeutig benannte Instanz zu erstellen und zu starten.",
    "Manage only this package's actions. Unselected actions remain when uninstalling.": "Nur Aktionen dieses Pakets verwalten. Nicht ausgewählte Aktionen bleiben bei der Deinstallation erhalten.",
    "Desktop background only. Configure user-level Git to prefer the system proxy and fall back to a direct connection.": "Nur Desktop-Hintergrund. Git für den Benutzer so konfigurieren, dass der Systemproxy bevorzugt und bei Bedarf eine direkte Verbindung verwendet wird.",
    "Desktop background only. Diagnose the SDK in CMD, choose a device and system image, then create or start an Android AVD.": "Nur Desktop-Hintergrund. SDK in CMD diagnostizieren, Gerät und Systemabbild wählen, dann ein Android-AVD erstellen oder starten.",
    "Desktop background only. Check existing DevEco Emulator instances, then start one or confirm a nondestructive restart. Data is preserved.": "Nur Desktop-Hintergrund. Vorhandene DevEco-Emulator-Instanzen prüfen, dann eine starten oder einen Neustart ohne Datenverlust bestätigen. Daten bleiben erhalten.",
    "Desktop background only. Check emulator location and /data; optionally reset caches, precisely uninstall, back up the AVD, and retest with a cold boot.": "Nur Desktop-Hintergrund. Emulatorpfad und /data prüfen; optional Caches zurücksetzen, gezielt deinstallieren, das AVD sichern und mit einem Kaltstart erneut prüfen.",
    "Show the next action on the desktop background. Toggle hidden files for the current user's Explorer without changing protected-system-file settings.": "Nächste Aktion auf dem Desktop-Hintergrund anzeigen. Versteckte Dateien im Explorer des aktuellen Benutzers umschalten, ohne die Einstellung für geschützte Systemdateien zu ändern.",
    "Visible only for nonempty native Android or valid Flutter (official / HarmonyOS) project roots. Validated again before opening.": "Nur für nicht leere native Android- oder gültige Flutter-Projektwurzeln (offiziell / HarmonyOS) sichtbar. Vor dem Öffnen erneut geprüft.",
    "Preview: the selection is shown in the log. No installation or uninstallation was performed.": "Vorschau: Die Auswahl wird im Protokoll angezeigt. Es wurde nichts installiert oder deinstalliert.",
    "Preview only. Confirming displays the selection in the log without installing, uninstalling, or writing state or registry entries.": "Nur Vorschau. Die Bestätigung zeigt die Auswahl im Protokoll an, ohne Installation, Deinstallation oder Änderungen an Status und Registrierung.",
    "Deployed copies use their bound location. To change it, open the manager from the source directory. Default installations run in the current user's LocalAppData; local builds run under this package's work directory and stop working if it moves.": "Bereitgestellte Kopien verwenden ihren gebundenen Speicherort. Zum Ändern die Verwaltung aus dem Quellverzeichnis öffnen. Standardinstallationen laufen unter LocalAppData des aktuellen Benutzers; lokale Builds im Arbeitsverzeichnis dieses Pakets und funktionieren nach dessen Verschieben nicht mehr.",
    "Prefer Windows Terminal; otherwise use system PowerShell.": "Windows Terminal bevorzugen; andernfalls System-PowerShell verwenden.",
    "Could not save preferences: ": "Einstellungen konnten nicht gespeichert werden: ",
    "Save settings": "Einstellungen speichern",
    "Protect local changes. On conflict, choose to restore, discard changes, or commit and retry.": "Lokale Änderungen schützen. Bei Konflikten Wiederherstellen, Änderungen verwerfen oder Commit erstellen und erneut versuchen wählen.",
    "All operations completed. Copy the log or close the panel.": "Alle Vorgänge abgeschlossen. Protokoll kopieren oder Fenster schließen.",
    "Other context-menu features": "Weitere Kontextmenüfunktionen",
    "Create or synchronize the code map for the current directory.": "Codekarte für das aktuelle Verzeichnis erstellen oder synchronisieren.",
    "Feature and log divider": "Trennleiste zwischen Funktionen und Protokoll",
    "Select features, then confirm. Unselected features remain. Hover for installation details.": "Funktionen auswählen und bestätigen. Nicht ausgewählte Funktionen bleiben erhalten. Für Installationsdetails den Mauszeiger darüber bewegen.",
    "Checked features are installed; unchecked ones are uninstalled. Saving an empty selection disables all installed features.": "Markierte Funktionen werden installiert, nicht markierte deinstalliert. Das Speichern einer leeren Auswahl deaktiviert alle installierten Funktionen.",
    "Select features to install. Enabled sibling actions and other unselected features remain.": "Zu installierende Funktionen auswählen. Aktivierte benachbarte Aktionen und andere nicht ausgewählte Funktionen bleiben erhalten.",
    "Total uninstall time": "Gesamte Deinstallationszeit",
    "Uninstall selected": "Auswahl deinstallieren",
    "Uninstall selected features": "Ausgewählte Funktionen deinstallieren",
    "Uninstall time": "Deinstallationszeit",
    "Cancel": "Abbrechen",
    "Uninstall only selected installed features. Other features, logs, backups and tools remain.": "Nur ausgewählte installierte Funktionen deinstallieren. Andere Funktionen, Protokolle, Sicherungen und Werkzeuge bleiben erhalten.",
    "Change only the current user's ExecuteFile ACL for a single regular NTFS file after confirmation. Does not launch the file or change global policy.": "Nach Bestätigung nur die ExecuteFile-ACL des aktuellen Benutzers für eine einzelne reguläre NTFS-Datei ändern. Die Datei wird nicht gestartet und die globale Richtlinie bleibt unverändert.",
    "View a single regular file. Files over 1 MiB or suspected binary files require YES in the terminal.": "Eine einzelne reguläre Datei anzeigen. Dateien über 1 MiB oder vermutlich binäre Dateien erfordern YES im Terminal.",
    "Clean only the selected packages' build workspaces. Installed DLLs, scripts, settings and registry entries remain.": "Nur Build-Arbeitsbereiche ausgewählter Pakete bereinigen. Installierte DLLs, Skripte, Einstellungen und Registrierungseinträge bleiben erhalten.",
    "Copy full log": "Vollständiges Protokoll kopieren",
    "Copy the original remote URL for the current branch.": "Ursprüngliche Remote-URL des aktuellen Branches kopieren.",
    "Copy the absolute path of a file or folder.": "Absoluten Pfad einer Datei oder eines Ordners kopieren.",
    "Could not copy the log: ": "Protokoll konnte nicht kopiert werden: ",
    "Failed — open log": "Fehlgeschlagen — Protokoll öffnen",
    "Install / update": "Installieren / aktualisieren",
    "Install / update selected features": "Ausgewählte Funktionen installieren / aktualisieren",
    "Total install time": "Gesamte Installationszeit",
    "Install time": "Installationszeit",
    "Merge appears for a complete selected volume set; split appears for one regular file. Originals are always preserved.": "Zusammenführen erscheint für einen vollständig ausgewählten Volumesatz; Aufteilen für eine einzelne reguläre Datei. Originale bleiben immer erhalten.",
    "Live log (drag the divider to resize)": "Live-Protokoll (Trennleiste zum Ändern der Größe ziehen)",
    "Installation stopped after the current package transaction. Unstarted items are marked Not run.": "Installation nach der aktuellen Pakettransaktion gestoppt. Nicht begonnene Einträge sind als Nicht ausgeführt markiert.",
    "Stop requested. Waiting for the current package transaction; later items will not run.": "Stopp angefordert. Warten auf die aktuelle Pakettransaktion; nachfolgende Einträge werden nicht ausgeführt.",
    "Selected {0} / {1}. Closing or cancelling makes no changes.": "Ausgewählt: {0} / {1}. Schließen oder Abbrechen nimmt keine Änderungen vor.",
    "Hover for feature details. Windows 11: right-click → Show more options.": "Für Funktionsdetails den Mauszeiger darüber bewegen. Windows 11: Rechtsklick → Weitere Optionen anzeigen.",
    "Could not open the full log: ": "Vollständiges Protokoll konnte nicht geöffnet werden: ",
    "Open the repository website for the current Git worktree.": "Repository-Website des aktuellen Git-Arbeitsverzeichnisses öffnen.",
    "Open the solution or project at the current directory level.": "Projektmappe oder Projekt auf der aktuellen Verzeichnisebene öffnen.",
    "Export resolved third-party Pub sources and licenses from the project lockfile. Press Enter to use the desktop as output.": "Aufgelöste Pub-Drittanbieterquellen und Lizenzen aus der Sperrdatei des Projekts exportieren. Eingabe drücken, um den Desktop als Ausgabeziel zu verwenden.",
    "An operation is running. Wait for the transaction to finish before closing. Logs can be copied at any time.": "Ein Vorgang läuft. Vor dem Schließen auf den Abschluss der Transaktion warten. Protokolle können jederzeit kopiert werden.",
    "Could not build the operation plan: ": "Vorgangsplan konnte nicht erstellt werden: ",
    "Could not start the operation: ": "Vorgang konnte nicht gestartet werden: ",
    "Log: ": "Protokoll: ",
    "🈶 Repair Chinese paths in Flutter project": "🈶 Chinesische Pfade im Flutter-Projekt reparieren",
    "Not installed; nothing to uninstall": "Nicht installiert; nichts zu deinstallieren",
    "Not installed": "Nicht installiert",
    "Not run": "Nicht ausgeführt",
    "This feature": "Diese Funktion",
    "Local build directory (moving or cleaning it disables the menu)": "Lokales Build-Verzeichnis (Verschieben oder Bereinigen deaktiviert das Menü)",
    "Validate the branch, staging area and upstream, then confirm the push.": "Branch, Staging-Bereich und Upstream prüfen und danach den Push bestätigen.",
    "Validate the Flutter project, then fetch dependencies.": "Flutter-Projekt prüfen und anschließend Abhängigkeiten abrufen.",
    "Installing / updating…": "Wird installiert / aktualisiert…",
    "This entry has been removed. Existing installations can be uninstalled but cannot be reinstalled.": "Dieser Eintrag wurde entfernt. Vorhandene Installationen können deinstalliert, aber nicht erneut installiert werden.",
    "No features require processing; ": "Keine Funktionen zu bearbeiten; ",
    "No features require processing. No settings were changed.": "Keine Funktionen zu bearbeiten. Es wurden keine Einstellungen geändert.",
    "Total cleanup time": "Gesamte Bereinigungszeit",
    "Cleanup time": "Bereinigungszeit",
    "Click to read the full session log in a new PowerShell window. The current task continues.": "Klicken, um das vollständige Sitzungsprotokoll in einem neuen PowerShell-Fenster zu lesen. Die aktuelle Aufgabe läuft weiter.",
    "Pending": "Ausstehend",
    "Waiting to stop…": "Warten auf Stopp…",
    "Ordered Flutter development, diagnostics, repair and maintenance tools. Regular actions use project FVM; environment setup supports FVM / system Flutter and jEnv / system Java.": "Geordnete Flutter-Werkzeuge für Entwicklung, Diagnose, Reparatur und Wartung. Reguläre Aktionen verwenden Projekt-FVM; die Einrichtung unterstützt FVM / System-Flutter und jEnv / System-Java.",
    "Detect the Flutter / Android project and preview cleanup scope. iOS cleanup is unavailable on Windows.": "Flutter-/Android-Projekt erkennen und den Bereinigungsumfang anzeigen. iOS-Bereinigung ist unter Windows nicht verfügbar.",
    "Could not read preferences: ": "Einstellungen konnten nicht gelesen werden: ",
    "Could not read the log: ": "Protokoll konnte nicht gelesen werden: ",
    "Explorer context-menu extensions · ": "Explorer-Kontextmenüerweiterungen · ",
    "Explorer extensions · Manage": "Explorer-Erweiterungen · Verwalten",
    "Return selection": "Auswahl zurückgeben",
    "Exit code: ": "Exit-Code: ",
    "Choose an operation and select features. Unselected features remain; only installed features can be uninstalled.": "Vorgang und Funktionen auswählen. Nicht ausgewählte Funktionen bleiben erhalten; nur installierte Funktionen können deinstalliert werden.",
    "Some features failed; other selected features were still processed. Click a failed status to open the full session log.": "Einige Funktionen sind fehlgeschlagen; andere ausgewählte Funktionen wurden dennoch bearbeitet. Auf einen Fehlerstatus klicken, um das vollständige Sitzungsprotokoll zu öffnen.",
    "Available for nonempty regular directories outside iOS projects, including Flutter roots. Validated again before opening.": "Für nicht leere reguläre Verzeichnisse außerhalb von iOS-Projekten verfügbar, einschließlich Flutter-Projektwurzeln. Vor dem Öffnen erneut geprüft.",
    "Default installation location (recommended)": "Standard-Installationsort (empfohlen)",
    "{0}; Results: succeeded {1}; nothing to uninstall {2}; failed {3}; not run {4}": "{0}; Ergebnisse: erfolgreich {1}; nichts zu deinstallieren {2}; fehlgeschlagen {3}; nicht ausgeführt {4}",
    "{0} Exit code: {1}.": "{0} Exit-Code: {1}.",
    "{0} {1}": "{0} {1}",
    "{0}{1} {2}": "{0}{1} {2}",
    "{0} in progress; completed {1} / {2} ({3}% by completed items); {4} {5}": "{0} läuft; abgeschlossen {1} / {2} ({3}% nach abgeschlossenen Einträgen); {4} {5}",
    "{0} Completed {1} / {2} ({3}% by completed items); {4} {5}": "{0} Abgeschlossen {1} / {2} ({3}% nach abgeschlossenen Einträgen); {4} {5}",
    "🫥 Hide / show selected items": "🫥 Ausgewählte Objekte ausblenden / anzeigen",
    "Set the Hidden attribute of selected files or folders, including multiple selections; do not recurse, rename, or change global visibility preferences.": "Setzt das Versteckt-Attribut ausgewählter Dateien oder Ordner, auch bei Mehrfachauswahl; ohne Rekursion, Umbenennen oder Änderung globaler Anzeigeeinstellungen.",
    "Permanently delete (skip Recycle Bin)": "Endgültig löschen (ohne Papierkorb)",
    "Directly delete selected files or folders; confirm with the red left button or cancel with the blue right button. Cancellation is the default; deleted items cannot be restored from the Recycle Bin.": "Löscht ausgewählte Dateien oder Ordner direkt. Links rot bestätigen, rechts blau abbrechen; Standard ist Abbrechen. Eine Wiederherstellung aus dem Papierkorb ist nicht möglich."
  },
  "ru": {
    "Close management panel": "Закрыть панель управления",
    "Minimize to tray": "Свернуть в системный трей",
    "Exit completely": "Полностью выйти",
    "Keep window open": "Оставить окно открытым",
    "The manager is idle. Keep it in the system tray, or exit completely.": "Задачи не выполняются. Оставьте менеджер в системном трее или полностью выйдите.",
    "Show management panel": "Показать панель управления",
    "Current status": "Текущее состояние",
    "A task is running. Exit is unavailable; restore the window to view logs.": "Выполняется задача. Выход недоступен; восстановите окно для просмотра журнала.",
    "The system tray is unavailable. The window will remain open.": "Системный трей недоступен. Окно останется открытым.",
    "💽 Disk free space": "💽 Свободное место на дисках",
    "Show total local disk free / capacity and a two-decimal percentage. Click to choose cleanup in a separate terminal; changes require confirmation.": "Показывать суммарное свободное место / ёмкость локальных дисков и процент с двумя знаками. Нажатие открывает выбор очистки в отдельном терминале; изменения требуют подтверждения.",
    "Create script launcher…": "Создать ярлык скрипта…",
    "🔗 Create script launcher…": "🔗 Создать ярлык скрипта…",
    "Create a relative launcher beside a same-name .cmd/.bat/.ps1 script folder; do not run or modify the source script.": "Создать относительный ярлык рядом с одноимённой папкой скрипта .cmd/.bat/.ps1, не запуская и не изменяя исходный скрипт.",
    "Theme": "Тема",
    "Language": "Язык",
    "🎨 Theme": "🎨 Тема",
    "🌐 Language": "🌐 Язык",
    "Follow system": "Как в системе",
    "Dark": "Тёмная",
    "Light": "Светлая",
    "Jobs Finder Extension Manager": "Диспетчер расширений Finder Jobs",
    "Customize Finder Context Menu": "Настройка контекстного меню Finder",
    "Close Manager": "Закрыть диспетчер",
    "Edit": "Правка",
    "Copy": "Копировать",
    "Select all": "Выбрать все",
    "Clear all": "Снять все",
    "Close": "Закрыть",
    "OK": "ОК",
    "Install": "Установить",
    "Install / Update": "Установить / обновить",
    "Uninstall": "Удалить",
    "Cleanup": "Очистить",
    "Clean build products": "Удалить результаты сборки",
    "🧹 Clean build products": "🧹 Удалить результаты сборки",
    "Stop installation": "Остановить установку",
    "Stopping…": "Остановка…",
    "Action: install / update or uninstall": "Действие: установка / обновление или удаление",
    "Uninstall removes selected menus only. Group selection affects its own group.": "Удаляются только выбранные пункты меню. Выбор внутри группы действует только на эту группу.",
    "Install / uninstall with the combined App in Applications": "Устанавливать / удалять через объединённое приложение в «Программах»",
    "Install or uninstall the combined App in Applications": "Установить или удалить через объединённое приложение в «Программах»",
    "Selected: manage features in /Applications/Jobs自定义右键菜单.app. Otherwise use the build directory.": "Включено: управлять выбранными функциями в /Applications/Jobs自定义右键菜单.app. Иначе использовать каталог сборки.",
    "Clean this build after successful installation": "Удалить результаты этой сборки после успешной установки",
    "Clean this build only after the combined App is installed and verified in Applications. Keep failed builds.": "Очищать эту сборку только после установки и проверки объединённого приложения в «Программах». Не удалять неудачные сборки.",
    "Clean build products of selected features without installing or uninstalling.": "Очистить результаты сборки выбранных функций без установки или удаления.",
    "Clean selected features' build products": "Очистить результаты сборки выбранных функций",
    "Open Privacy & Security": "Открыть «Конфиденциальность и безопасность»",
    "Add and enable Jobs右键菜单管理面板.app in Privacy & Security → App Management. This only opens Settings.": "Добавьте и разрешите Jobs右键菜单管理面板.app в «Конфиденциальность и безопасность → Управление приложениями». Кнопка только открывает настройки.",
    "Target: build directory. Cleaning these products affects installed features.": "Цель: каталог сборки. Его очистка нарушит работу установленных функций.",
    "App: Jobs自定义右键菜单.app at /Applications/Jobs自定义右键菜单.app (build products can be cleaned after installation)": "Приложение: Jobs自定义右键菜单.app в /Applications/Jobs自定义右键菜单.app (после установки результаты сборки можно удалить)",
    "Drag the divider to resize the log. Features and logs scroll separately.": "Перетащите разделитель вверх или вниз, чтобы изменить высоту журнала. Список функций и журнал прокручиваются отдельно.",
    "Feature list and live log divider": "Разделитель списка функций и текущего журнала",
    "Live log (select and copy text)": "Текущий журнал (текст можно выделять и копировать)",
    "Copy log": "Копировать журнал",
    "Log file": "Файл журнала",
    "Auto-scroll": "Автопрокрутка",
    "Ready. Select features and choose an action.": "Готово. Выберите функции и действие.",
    "A task is running. Wait for it to finish before closing.": "Задача выполняется. Дождитесь завершения перед закрытием, чтобы не прервать установку.",
    "Unable to view this log": "Не удалось просмотреть этот журнал",
    "Log is missing or unreadable: {0}": "Журнал отсутствует или недоступен для чтения: {0}",
    "Unable to open log terminal: {0}": "Не удалось открыть терминал журнала: {0}",
    "Click to show this session's full log in a new terminal: {0}": "Нажмите, чтобы показать полный журнал этого сеанса в новом терминале: {0}",
    "Selected {0} / {1}. Select at least one. Changing action keeps selection.": "Выбрано {0} из {1}. Выберите хотя бы один пункт. При смене действия выбор сохраняется.",
    "Selected {0} / {1}": "Выбрано {0} из {1}",
    "{0}: select all": "{0}: выбрать все",
    "{0}: clear all": "{0}: снять все",
    "Waiting": "Ожидание",
    "Cleaning…": "Очистка…",
    "Uninstalling…": "Удаление…",
    "Installing…": "Установка…",
    "Cleaned": "Очищено",
    "Uninstalled": "Удалено",
    "Installed": "Установлено",
    "Skipped": "Не выполнено",
    "Not installed; nothing to remove": "Не установлено; удаление не требуется",
    "Failed: see log": "Ошибка: см. журнал",
    "Selected": "Выбрано",
    "Not selected": "Не выбрано",
    "App Management permission required": "Требуется разрешение на управление приложениями",
    "Permission check required": "Требуется проверка разрешений",
    "Stopped": "Остановлено",
    "Completed": "Завершено",
    "Task failed": "Задача завершилась ошибкой",
    "{0}: processed {1} / {2} ({3}, completed items); {4} time {5}": "{0}: обработано {1} из {2} ({3}, по завершённым пунктам); время операции «{4}»: {5}",
    "{0} ready": "{0}: готово",
    "{0} ready; {1} time {2}": "{0}: готово; время операции «{1}»: {2}",
    "Finishing the current feature, then stopping; install time {0}": "Завершается текущая функция, затем установка остановится; время установки: {0}",
    "{0}: {1} succeeded, {2} failed, {3} skipped; exit {4}; {5}; {6} time {7}": "{0}: успешно {1}, ошибок {2}, не выполнено {3}; код завершения {4}; {5}; общее время операции «{6}»: {7}",
    "{0}: {1} succeeded, {2} failed, {3} not installed, {4} skipped; exit {5}; {6}; {7} time {8}": "{0}: успешно {1}, ошибок {2}, не установлено {3}, не выполнено {4}; код завершения {5}; {6}; общее время операции «{7}»: {8}",
    "{0}: {1} succeeded, {2} failed, {3} not installed; exit {4}; {5}; {6} time {7}": "{0}: успешно {1}, ошибок {2}, не установлено {3}; код завершения {4}; {5}; общее время операции «{6}»: {7}",
    "{0}: {1} succeeded, {2} failed; exit {3}; {4}; {5} time {6}": "{0}: успешно {1}, ошибок {2}; код завершения {3}; {4}; общее время операции «{5}»: {6}",
    "Open projects in IDEs": "Открытие проектов в IDE",
    "Git tools": "Инструменты Git",
    "Files and general tools": "Файлы и общие инструменты",
    "Flutter tools · submenu actions": "Инструменты Flutter · действия подменю",
    "iOS / CocoaPods tools": "Инструменты iOS / CocoaPods",
    "Simulator tools": "Инструменты эмуляторов",
    "Open project in Android Studio": "Открыть проект в Android Studio",
    "Open project in VSCode": "Открыть проект в VSCode",
    "Open project in Xcode": "Открыть проект в Xcode",
    "Pull latest Git changes": "Получить последние изменения Git",
    "Roll back Git commit": "Откатить коммит Git",
    "Open Git remote URL": "Открыть адрес удалённого репозитория Git",
    "Copy Git remote URL": "Копировать адрес удалённого репозитория Git",
    "Copy absolute path": "Копировать абсолютный путь",
    "Create file": "Создать файл",
    "View file fingerprint Hash (SHA-256)": "Показать хеш файла (SHA-256)",
    "Grant execute permission (chmod +x)": "Разрешить выполнение (chmod +x)",
    "Remove execute permission (chmod -x)": "Запретить выполнение (chmod -x)",
    "Re-sign IPA without building": "Повторно подписать IPA без сборки",
    "Show / hide files": "Показать / скрыть скрытые файлы",
    "Create iOS simulator": "Создать эмулятор iOS",
    "Create Android simulator": "Создать эмулятор Android",
    "Create Harmony simulator": "Создать эмулятор Harmony",
    "Check / repair Android simulator": "Проверить / восстановить эмулятор Android",
    "Check / repair Harmony simulator": "Проверить / восстановить эмулятор Harmony",
    "Configure Git proxy": "Настроить динамический прокси Git",
    "Open in terminal": "Открыть в терминале",
    "View file contents in terminal": "Просмотреть содержимое файла в терминале",
    "Merge file parts": "Объединить части файла",
    "Split file": "Разделить файл",
    "Clean Android / OpenHarmony builds": "Очистить результаты сборки Android / OpenHarmony",
    "Update code map (.codegraph)": "Обновить карту кода (.codegraph)",
    "Create empty commit and push in terminal": "Создать пустой коммит и отправить в терминале",
    "Disable CocoaPods build sandbox": "Отключить песочницу сборки CocoaPods",
    "Install CocoaPods": "Установить CocoaPods",
    "CocoaPods source: CDN → GitHub": "Источник CocoaPods: CDN → GitHub",
    "Export all project Pod files": "Экспортировать все файлы Pod проекта",
    "Inspect Xcode project dependencies": "Проверить зависимости проекта Xcode",
    "Update local CocoaPods repositories": "Обновить локальные репозитории CocoaPods",
    "Check local Pod builds (.podspec folder)": "Проверить сборку локального Pod (каталог .podspec)",
    "Install / update JobsCodeSnippets": "Установить / обновить JobsCodeSnippets",
    "Clean iOS / Xcode builds": "Очистить результаты сборки iOS / Xcode",
    "Set up Flutter project": "Настроить проект Flutter",
    "Run Flutter project in terminal": "Запустить проект Flutter в терминале",
    "Fetch Flutter Pub dependencies": "Получить зависимости Flutter Pub",
    "Fetch native Android dependencies": "Получить нативные зависимости Android",
    "Fetch CocoaPods dependencies": "Получить зависимости CocoaPods",
    "Fetch Swift Package dependencies": "Получить зависимости Swift Package",
    "Fetch OpenHarmony dependencies": "Получить зависимости OpenHarmony",
    "Prepare native libraries and build dependencies": "Подготовить нативные библиотеки и зависимости сборки",
    "Download Flutter platform resources": "Загрузить ресурсы платформ Flutter",
    "Fetch Web project dependencies": "Получить зависимости веб-проекта",
    "🧳 Export Flutter dependencies": "🧳 Экспортировать все зависимости Flutter",
    "Export Flutter Pub dependencies": "Экспортировать зависимости Flutter Pub",
    "🔐 Export private Flutter dependencies": "🔐 Экспортировать закрытые зависимости Flutter",
    "📥 Import Flutter dependencies": "📥 Импортировать все зависимости Flutter",
    "Import Flutter Pub dependencies": "Импортировать зависимости Flutter Pub",
    "📥 Import private Flutter dependencies": "📥 Импортировать закрытые зависимости Flutter",
    "Export Gradle distributions and cache": "Экспортировать дистрибутивы и кэш Gradle",
    "Import Gradle distributions and cache": "Импортировать дистрибутивы и кэш Gradle",
    "Export CocoaPods dependencies": "Экспортировать зависимости CocoaPods",
    "Import CocoaPods dependencies": "Импортировать зависимости CocoaPods",
    "Export Swift Package dependencies": "Экспортировать зависимости Swift Package",
    "Import Swift Package dependencies": "Импортировать зависимости Swift Package",
    "Export OpenHarmony dependencies": "Экспортировать зависимости OpenHarmony",
    "Import OpenHarmony dependencies": "Импортировать зависимости OpenHarmony",
    "Export native build cache": "Экспортировать кэш нативной сборки",
    "Import native build cache": "Импортировать кэш нативной сборки",
    "Export Flutter platform resources": "Экспортировать ресурсы платформ Flutter",
    "Import Flutter platform resources": "Импортировать ресурсы платформ Flutter",
    "Export Web dependencies": "Экспортировать зависимости веб-проекта",
    "Import Web dependencies": "Импортировать зависимости веб-проекта",
    "Show Flutter project SDK version": "Показать версию SDK проекта Flutter",
    "Install / switch Flutter SDK": "Установить / сменить Flutter SDK",
    "Install / switch Flutter@OpenHarmony SDK": "Установить / сменить Flutter@OpenHarmony SDK",
    "Install / switch Java SDK": "Установить / сменить Java SDK",
    "Download Gradle distributions and plugins": "Загрузить дистрибутивы и плагины сборки Gradle",
    "Generate Flutter code": "Сгенерировать код Flutter",
    "Package iOS": "Собрать пакет iOS",
    "Package Android": "Собрать пакет Android",
    "Package Harmony (HAP + APP)": "Собрать пакет Harmony (HAP + APP)",
    "Check native Flutter project": "Диагностика нативного проекта Flutter",
    "Check OpenHarmony Flutter environment": "Диагностика среды Flutter для OpenHarmony",
    "Repair missing Android SDK / platforms": "Восстановить отсутствующие Android SDK / платформы",
    "Repair Chinese Flutter project paths": "Исправить китайские пути проекта Flutter",
    "Repair Flutter plugin namespaces": "Исправить пространства имён плагинов Flutter",
    "Convert relative Dart imports to packages": "Преобразовать относительные импорты Dart в ссылки package",
    "Clean current Flutter project builds": "Очистить результаты сборки текущего проекта Flutter",
    "Dependency and cache maintenance": "Обслуживание зависимостей и кэша",
    "Custom Explorer context menu": "Настройка контекстного меню Explorer",
    "Jobs Windows · Custom Explorer context menu": "Jobs Windows · Настройка контекстного меню Explorer",
    "Show a regular file's SHA-256 in a new terminal and copy the digest; do not modify or execute the file.": "Показать SHA-256 одного обычного файла в новом терминале и скопировать хеш, не изменяя и не запуская файл.",
    " (preview)": " (предпросмотр)",
    "⏪ Roll back Git commits": "⏪ Откатить коммиты Git",
    "▶️ Run Flutter project in terminal": "▶️ Запустить проект Flutter в терминале",
    "☕ Install / switch Java SDK": "☕ Установить / переключить Java SDK",
    "♻️ Flutter cleanup and maintenance": "♻️ Очистка и обслуживание Flutter",
    "⚙️ Generate Flutter code": "⚙️ Сгенерировать код Flutter",
    "✅ Installed": "✅ Установлено",
    "⬇️ Pull latest Git changes": "⬇️ Получить последние изменения Git",
    "🌈 Create Harmony emulator": "🌈 Создать эмулятор Harmony",
    "🌐 Open Git remote URL": "🌐 Открыть URL удалённого репозитория Git",
    "🌐 Fetch Web project dependencies": "🌐 Загрузить зависимости веб-проекта",
    "🌳 Open in Sourcetree": "🌳 Открыть в Sourcetree",
    "🏥 Flutter project diagnostics": "🏥 Диагностика проекта Flutter",
    "🏥 Flutter diagnostics": "🏥 Диагностика проекта Flutter",
    "🏷️ Repair Flutter plugin namespaces": "🏷️ Исправить пространства имён плагинов Flutter",
    "👁️ Show / hide hidden files": "👁️ Показать / скрыть скрытые файлы",
    "💓 OpenHarmony Flutter diagnostics": "💓 Диагностика Flutter OpenHarmony",
    "💠 Open project in Visual Studio": "💠 Открыть проект в Visual Studio",
    "💻 Open in terminal": "💻 Открыть в терминале",
    "📄 View file in terminal": "📄 Просмотреть файл в терминале",
    "📋 Copy absolute path": "📋 Копировать абсолютный путь",
    "📚 Download Gradle distributions and build plugins": "📚 Загрузить дистрибутивы Gradle и плагины сборки",
    "📝 Open project in VSCode": "📝 Открыть проект в VSCode",
    "📡 Configure Git dynamic proxy": "📡 Настроить динамический прокси Git",
    "📤 Import Flutter Pub dependencies": "📤 Импортировать зависимости Flutter Pub",
    "📤 Import Flutter platform assets": "📤 Импортировать ресурсы платформ Flutter",
    "📤 Import Gradle distributions and dependency caches": "📤 Импортировать дистрибутивы Gradle и кеши зависимостей",
    "📤 Import OpenHarmony dependencies": "📤 Импортировать зависимости OpenHarmony",
    "📤 Import Web dependencies": "📤 Импортировать веб-зависимости",
    "📤 Import native build caches": "📤 Импортировать кеши нативных сборок",
    "📤 Import Flutter project dependencies": "📤 Импортировать зависимости проекта Flutter",
    "📤 Create empty commit and push": "📤 Создать пустой коммит и отправить",
    "📥 Install Flutter dependencies (pub get)": "📥 Установить зависимости Flutter (pub get)",
    "📥 Import private Flutter project dependencies": "📥 Импортировать приватные зависимости проекта Flutter",
    "📥 Fetch Flutter Pub dependencies": "📥 Загрузить зависимости Flutter Pub",
    "📥 Fetch Flutter project dependencies": "📥 Получить зависимости проекта Flutter",
    "📦 Package Flutter project": "📦 Собрать пакет проекта Flutter",
    "📦 Package HarmonyOS (HAP + APP)": "📦 Собрать HarmonyOS (HAP + APP)",
    "📱 Create Android emulator": "📱 Создать эмулятор Android",
    "🔀 Install / switch Flutter SDK (FVM)": "🔀 Установить / сменить Flutter SDK (FVM)",
    "🔀 Install / switch Flutter SDK": "🔀 Установить / переключить Flutter SDK",
    "🔀 Install / switch Flutter environments": "🔀 Установить / сменить среду выполнения Flutter",
    "🔎 Show current Flutter SDK version": "🔎 Показать версию текущего Flutter SDK",
    "🔎 Show current Flutter project's SDK version": "🔎 Показать версию SDK текущего проекта Flutter",
    "🔐 Export private Flutter project dependencies": "🔐 Экспортировать приватные зависимости проекта Flutter",
    "🔎 Show file fingerprint Hash (SHA-256)": "🔎 Показать хеш файла (SHA-256)",
    "➕ Grant execute permission": "➕ Разрешить выполнение",
    "➖ Remove execute permission": "➖ Запретить выполнение",
    "🔒 Grant execute permission": "🔒 Разрешить выполнение",
    "🔓 Remove execute permission": "🔓 Запретить выполнение",
    "🔗 Copy Git remote URL": "🔗 Копировать URL удалённого репозитория Git",
    "🔧 Flutter repairs": "🔧 Исправление проекта Flutter",
    "🕊️ Install / switch Flutter@OpenHarmony SDK": "🕊️ Установить / переключить Flutter@OpenHarmony SDK",
    "🕊️ Fetch OpenHarmony dependencies": "🕊️ Загрузить зависимости OpenHarmony",
    "🗃️ Download Flutter platform assets": "🗃️ Загрузить ресурсы платформ Flutter",
    "🗺️ Update code map (.codegraph)": "🗺️ Обновить карту кода (.codegraph)",
    "🤖 Fetch Android native dependencies": "🤖 Загрузить нативные зависимости Android",
    "🦋 Flutter development": "🦋 Разработка на Flutter",
    "🦋 Flutter development tools": "🦋 Инструменты разработки Flutter",
    "🧑‍⚕️ Native Flutter diagnostics": "🧑‍⚕️ Диагностика нативного Flutter",
    "🧩 Export Flutter Pub dependencies": "🧩 Экспортировать зависимости Flutter Pub",
    "🧩 Export Flutter platform assets": "🧩 Экспортировать ресурсы платформ Flutter",
    "🧩 Export Flutter third-party dependencies": "🧩 Экспортировать сторонние зависимости Flutter",
    "🧩 Export Gradle distributions and dependency caches": "🧩 Экспортировать дистрибутивы Gradle и кеши зависимостей",
    "🧩 Export OpenHarmony dependencies": "🧩 Экспортировать зависимости OpenHarmony",
    "🧩 Export Web dependencies": "🧩 Экспортировать веб-зависимости",
    "🧩 Export native build caches": "🧩 Экспортировать кеши нативных сборок",
    "🧩 Export Flutter project dependencies": "🧩 Экспортировать зависимости проекта Flutter",
    "🧩 Merge file volumes / ✂️ Split file": "🧩 Объединить части файла / ✂️ Разделить файл",
    "🧭 Open project in Android Studio": "🧭 Открыть проект в Android Studio",
    "🧯 Clean build output": "🧯 Очистить результаты сборки",
    "🧰 Diagnose and repair Harmony emulator": "🧰 Диагностика и восстановление эмулятора Harmony",
    "🧱 Flutter assets and build dependencies": "🧱 Ресурсы Flutter и зависимости сборки",
    "🧱 Prepare native libraries and build dependencies (combined)": "🧱 Подготовить нативные библиотеки и зависимости сборки (комплексно)",
    "🧹 Clean build output": "🧹 Очистить результаты сборки",
    "🩹 Repair missing Android SDK / platforms": "🩹 Исправить отсутствующие Android SDK / платформы",
    "🩺 Diagnose and repair Android emulator": "🩺 Диагностика и восстановление эмулятора Android",
    "🚀 Set up Flutter project": "🚀 Настроить проект Flutter",
    "🚚 Import all Flutter dependencies": "🚚 Импортировать все зависимости Flutter",
    "🚚 Export all Flutter dependencies": "🚚 Экспортировать все зависимости Flutter",
    "Jobs Windows · Uninstall Explorer extensions": "Jobs Windows · Удаление расширений Explorer",
    "Jobs Windows · Install Explorer extensions": "Jobs Windows · Установка расширений Explorer",
    "Jobs Windows · Manage Explorer extensions": "Jobs Windows · Управление расширениями Explorer",
    "Jobs Windows · Configure Explorer extensions": "Jobs Windows · Настройка расширений Explorer",
    "Drag the divider vertically to resize the log": "Перетащите разделитель вверх или вниз, чтобы изменить высоту журнала",
    "Drag vertically to resize the log": "Перетащите вверх или вниз, чтобы изменить высоту журнала",
    "Validate the Flutter project, diagnose the toolchain in terminal, and choose a Flutter SDK version with fzf.": "Проверить проект Flutter, выполнить диагностику инструментов в терминале и выбрать версию Flutter SDK через fzf.",
    "Validate the Flutter project, then show the active SDK version (project FVM or system SDK) in terminal and compare it with .fvmrc and pubspec constraints.": "Проверить проект Flutter, показать текущую версию SDK в терминале (проектный FVM или системный SDK) и сверить её с .fvmrc и ограничениями pubspec.",
    "Flutter roots only. Choose Android / iOS / HarmonyOS with fzf in CMD. Supports APK / AAB and HAP / APP. iOS requires MacOS and Xcode.": "Только для корней проектов Flutter. В CMD выберите Android / iOS / HarmonyOS через fzf. Поддерживаются APK / AAB и HAP / APP. Для iOS нужны MacOS и Xcode.",
    "Flutter roots only. Choose a device and view logs in CMD; the app continues in the background after the window closes.": "Только для корней проектов Flutter. Выберите устройство и просматривайте журнал в CMD; после закрытия окна приложение продолжит работать в фоне.",
    "Flutter roots only. Read-only version and doctor diagnostics in terminal; no dependency fetching, cleanup, or tool upgrades.": "Только для корней проектов Flutter. В терминале выполняются только чтение версии и диагностика doctor; без загрузки зависимостей, очистки и обновления инструментов.",
    "Flutter roots only. Preview configured generators, then fetch dependencies and generate code after confirmation. Deleting conflicts requires separate opt-in.": "Только для корней проектов Flutter. Просмотрите настроенные генераторы, затем после подтверждения загрузите зависимости и сгенерируйте код. Удаление конфликтующих файлов требует отдельного согласия.",
    "Git worktree folders only. Detect nested repositories. Soft mode preserves the index and worktree; hard mode requires exact YES confirmation.": "Только для каталогов рабочих деревьев Git. Распознаются вложенные репозитории. Режим soft сохраняет индекс и рабочие файлы; hard требует точного подтверждения YES.",
    "Desktop background on x64 Windows only. Missing tools come from the SDL mirror; missing system images come from the official Emulator. Enter selects a stable phone image; confirm its license to create and start a unique instance.": "Только в контекстном меню рабочего стола x64 Windows. Недостающие инструменты загружаются с зеркала SDL, образы системы — через официальный Emulator. Нажмите Enter для выбора стабильного образа телефона, подтвердите лицензию, чтобы создать и запустить уникальный экземпляр.",
    "Manage only this package's actions. Unselected actions remain when uninstalling.": "Управлять только действиями этого пакета. При удалении невыбранные действия сохраняются.",
    "Desktop background only. Configure user-level Git to prefer the system proxy and fall back to a direct connection.": "Только в контекстном меню рабочего стола. Настроить Git текущего пользователя: сначала системный прокси, при сбое — прямое соединение.",
    "Desktop background only. Diagnose the SDK in CMD, choose a device and system image, then create or start an Android AVD.": "Только в контекстном меню рабочего стола. Проверить SDK в CMD, выбрать модель и образ системы, затем создать или запустить Android AVD.",
    "Desktop background only. Check existing DevEco Emulator instances, then start one or confirm a nondestructive restart. Data is preserved.": "Только в контекстном меню рабочего стола. Проверить существующие экземпляры DevEco Emulator, затем запустить выбранный или подтвердить перезапуск без потери данных.",
    "Desktop background only. Check emulator location and /data; optionally reset caches, precisely uninstall, back up the AVD, and retest with a cold boot.": "Только в контекстном меню рабочего стола. Проверить расположение эмулятора и /data; при необходимости сбросить кэш, точно удалить выбранный эмулятор, создать полную копию AVD и проверить холодный запуск.",
    "Show the next action on the desktop background. Toggle hidden files for the current user's Explorer without changing protected-system-file settings.": "В контекстном меню рабочего стола показано следующее действие. Переключает отображение скрытых файлов в Explorer текущего пользователя, не меняя настройки защищённых системных файлов.",
    "Visible only for nonempty native Android or valid Flutter (official / HarmonyOS) project roots. Validated again before opening.": "Доступно только для непустых корней нативных проектов Android или допустимых проектов Flutter (официальных / HarmonyOS). Перед открытием выполняется повторная проверка.",
    "Preview: the selection is shown in the log. No installation or uninstallation was performed.": "Предпросмотр: выбранные пункты показаны в журнале. Установка и удаление не выполнялись.",
    "Preview only. Confirming displays the selection in the log without installing, uninstalling, or writing state or registry entries.": "Только предпросмотр. Подтверждение показывает выбор в журнале, без установки, удаления и записи состояния или реестра.",
    "Deployed copies use their bound location. To change it, open the manager from the source directory. Default installations run in the current user's LocalAppData; local builds run under this package's work directory and stop working if it moves.": "Установленные копии используют закреплённое расположение. Чтобы изменить его, откройте диспетчер из исходного каталога. При обычной установке приложение работает в LocalAppData текущего пользователя; локальная сборка — в каталоге work этого пакета и перестаёт работать при его перемещении.",
    "Prefer Windows Terminal; otherwise use system PowerShell.": "Предпочитать Windows Terminal; иначе использовать системный PowerShell.",
    "Could not save preferences: ": "Не удалось сохранить настройки: ",
    "Save settings": "Сохранить настройки",
    "Protect local changes. On conflict, choose to restore, discard changes, or commit and retry.": "Защитить локальные изменения. При конфликте выберите восстановление, отмену изменений или создание коммита с повторной попыткой.",
    "All operations completed. Copy the log or close the panel.": "Все операции завершены. Можно скопировать журнал или закрыть панель.",
    "Other context-menu features": "Другие функции контекстного меню",
    "Create or synchronize the code map for the current directory.": "Создать или синхронизировать карту кода текущего каталога.",
    "Feature and log divider": "Разделитель функций и журнала",
    "Select features, then confirm. Unselected features remain. Hover for installation details.": "Выберите функции и подтвердите. Невыбранные сохраняются. Наведите указатель, чтобы узнать состояние установки.",
    "Checked features are installed; unchecked ones are uninstalled. Saving an empty selection disables all installed features.": "Выбранные функции устанавливаются, невыбранные удаляются. Сохранение пустого выбора отключает все установленные функции.",
    "Select features to install. Enabled sibling actions and other unselected features remain.": "Выберите функции для установки. Уже включённые соседние действия и другие невыбранные функции сохраняются.",
    "Total uninstall time": "Общее время удаления",
    "Uninstall selected": "Удалить выбранное",
    "Uninstall selected features": "Удалить выбранные функции",
    "Uninstall time": "Время удаления",
    "Cancel": "Отмена",
    "Uninstall only selected installed features. Other features, logs, backups and tools remain.": "Удалить только выбранные установленные функции. Остальные функции, журналы, резервные копии и инструменты сохраняются.",
    "Change only the current user's ExecuteFile ACL for a single regular NTFS file after confirmation. Does not launch the file or change global policy.": "После подтверждения изменить только ExecuteFile ACL текущего пользователя для одного обычного файла NTFS. Не запускает файл и не меняет глобальную политику.",
    "View a single regular file. Files over 1 MiB or suspected binary files require YES in the terminal.": "Просмотреть один обычный файл. Для файлов больше 1 MiB или предположительно двоичных файлов требуется ввести YES в терминале.",
    "Clean only the selected packages' build workspaces. Installed DLLs, scripts, settings and registry entries remain.": "Очистить только рабочие каталоги сборки выбранных пакетов. Установленные DLL, скрипты, настройки и записи реестра сохраняются.",
    "Copy full log": "Копировать полный журнал",
    "Copy the original remote URL for the current branch.": "Копировать исходный удалённый адрес текущей ветки.",
    "Copy the absolute path of a file or folder.": "Копировать абсолютный путь файла или папки.",
    "Could not copy the log: ": "Не удалось скопировать журнал: ",
    "Failed — open log": "Ошибка — открыть журнал",
    "Install / update": "Установить / обновить",
    "Install / update selected features": "Установить / обновить выбранные функции",
    "Total install time": "Общее время установки",
    "Install time": "Время установки",
    "Merge appears for a complete selected volume set; split appears for one regular file. Originals are always preserved.": "Объединение доступно при выборе полного набора частей файла; разделение — для одного обычного файла. Оригиналы всегда сохраняются.",
    "Live log (drag the divider to resize)": "Текущий журнал (высота изменяется перетаскиванием разделителя)",
    "Installation stopped after the current package transaction. Unstarted items are marked Not run.": "Установка остановлена после завершения операции с текущим пакетом. Не начатые пункты отмечены как «Не выполнено».",
    "Stop requested. Waiting for the current package transaction; later items will not run.": "Запрошена остановка. Ожидание завершения операции с текущим пакетом; последующие пункты выполняться не будут.",
    "Selected {0} / {1}. Closing or cancelling makes no changes.": "Выбрано {0} из {1}. Закрытие или отмена не вносят изменений.",
    "Hover for feature details. Windows 11: right-click → Show more options.": "Наведите указатель для описания функции. Windows 11: щелчок правой кнопкой → Показать дополнительные параметры.",
    "Could not open the full log: ": "Не удалось открыть полный журнал: ",
    "Open the repository website for the current Git worktree.": "Открыть сайт репозитория текущего рабочего дерева Git.",
    "Open the solution or project at the current directory level.": "Открыть решение или проект на текущем уровне каталога.",
    "Export resolved third-party Pub sources and licenses from the project lockfile. Press Enter to use the desktop as output.": "Экспортировать исходники сторонних зависимостей Pub с определёнными версиями и их лицензии по файлу блокировки проекта. Нажмите Enter, чтобы сохранить на рабочий стол.",
    "An operation is running. Wait for the transaction to finish before closing. Logs can be copied at any time.": "Операция выполняется. Дождитесь завершения транзакции перед закрытием. Журнал можно скопировать в любое время.",
    "Could not build the operation plan: ": "Не удалось составить план операции: ",
    "Could not start the operation: ": "Не удалось запустить операцию: ",
    "Log: ": "Журнал: ",
    "🈶 Repair Chinese paths in Flutter project": "🈶 Исправить китайские пути проекта Flutter",
    "Not installed; nothing to uninstall": "Не установлено; удаление не требуется",
    "Not installed": "Не установлено",
    "Not run": "Не выполнено",
    "This feature": "Эта функция",
    "Local build directory (moving or cleaning it disables the menu)": "Локальный каталог сборки (перемещение или очистка отключает меню)",
    "Validate the branch, staging area and upstream, then confirm the push.": "Проверить ветку, индекс и вышестоящую ветку, затем подтвердить отправку.",
    "Validate the Flutter project, then fetch dependencies.": "Проверить текущий проект Flutter, затем получить зависимости.",
    "Installing / updating…": "Установка / обновление…",
    "This entry has been removed. Existing installations can be uninstalled but cannot be reinstalled.": "Этот пункт удалён. Существующую установку можно удалить, но повторная установка недоступна.",
    "No features require processing; ": "Нет функций для обработки; ",
    "No features require processing. No settings were changed.": "Нет функций для обработки. Настройки не изменены.",
    "Total cleanup time": "Общее время очистки",
    "Cleanup time": "Время очистки",
    "Click to read the full session log in a new PowerShell window. The current task continues.": "Нажмите, чтобы прочитать полный журнал этого сеанса в новом окне PowerShell. Текущая задача продолжит работу.",
    "Pending": "В ожидании",
    "Waiting to stop…": "Ожидание остановки…",
    "Ordered Flutter development, diagnostics, repair and maintenance tools. Regular actions use project FVM; environment setup supports FVM / system Flutter and jEnv / system Java.": "Меню разработки, диагностики, исправления и обслуживания Flutter в едином порядке. Обычные действия используют FVM проекта; настройка среды поддерживает FVM / системный Flutter и jEnv / системную Java.",
    "Detect the Flutter / Android project and preview cleanup scope. iOS cleanup is unavailable on Windows.": "Определить проект Flutter / Android и показать область очистки. Очистка iOS в Windows недоступна.",
    "Could not read preferences: ": "Не удалось прочитать настройки: ",
    "Could not read the log: ": "Не удалось прочитать журнал: ",
    "Explorer context-menu extensions · ": "Расширения контекстного меню Explorer · ",
    "Explorer extensions · Manage": "Расширения Explorer · Управление",
    "Return selection": "Вернуть выбранное",
    "Exit code: ": "Код завершения: ",
    "Choose an operation and select features. Unselected features remain; only installed features can be uninstalled.": "Выберите действие и одну или несколько функций. Невыбранные сохраняются; удаляются только установленные функции.",
    "Some features failed; other selected features were still processed. Click a failed status to open the full session log.": "Некоторые функции завершились ошибкой; остальные выбранные функции были обработаны. Нажмите на статус ошибки, чтобы открыть полный журнал сеанса.",
    "Available for nonempty regular directories outside iOS projects, including Flutter roots. Validated again before opening.": "Доступно для непустых обычных каталогов вне проектов iOS, включая корни Flutter. Перед открытием выполняется повторная проверка.",
    "Default installation location (recommended)": "Стандартное расположение установки (рекомендуется)",
    "{0}; Results: succeeded {1}; nothing to uninstall {2}; failed {3}; not run {4}": "{0}; результаты: успешно {1}; удаление не требуется {2}; ошибок {3}; не выполнено {4}",
    "{0} Exit code: {1}.": "{0} Код завершения: {1}.",
    "{0} {1}": "{0} {1}",
    "{0}{1} {2}": "{0}{1} {2}",
    "{0} in progress; completed {1} / {2} ({3}% by completed items); {4} {5}": "Выполняется {0}; завершено {1} из {2} ({3}% по завершённым пунктам); {4} {5}",
    "{0} Completed {1} / {2} ({3}% by completed items); {4} {5}": "{0} Завершено {1} из {2} ({3}% по завершённым пунктам); {4} {5}",
    "🫥 Hide / show selected items": "🫥 Скрыть / показать выбранное",
    "Set the Hidden attribute of selected files or folders, including multiple selections; do not recurse, rename, or change global visibility preferences.": "Устанавливает атрибут скрытия выбранных файлов или папок, включая множественный выбор; без рекурсии, переименования и изменения общих настроек отображения.",
    "Permanently delete (skip Recycle Bin)": "Удалить навсегда (минуя корзину)",
    "Directly delete selected files or folders; confirm with the red left button or cancel with the blue right button. Cancellation is the default; deleted items cannot be restored from the Recycle Bin.": "Удаляет выбранные файлы и папки напрямую. Слева красное подтверждение, справа синяя отмена; по умолчанию отмена. Восстановление из корзины невозможно."
  },
  "ko": {
    "Close management panel": "관리 패널 닫기",
    "Minimize to tray": "시스템 트레이로 최소화",
    "Exit completely": "완전히 종료",
    "Keep window open": "창 열린 상태 유지",
    "The manager is idle. Keep it in the system tray, or exit completely.": "실행 중인 작업이 없습니다. 시스템 트레이에 유지하거나 완전히 종료하세요.",
    "Show management panel": "관리 패널 표시",
    "Current status": "현재 상태",
    "A task is running. Exit is unavailable; restore the window to view logs.": "작업 실행 중에는 완전히 종료할 수 없습니다. 창을 복원하여 로그를 확인하세요.",
    "The system tray is unavailable. The window will remain open.": "시스템 트레이를 사용할 수 없습니다. 창을 열린 상태로 유지합니다.",
    "💽 Disk free space": "💽 디스크 여유 공간",
    "Show total local disk free / capacity and a two-decimal percentage. Click to choose cleanup in a separate terminal; changes require confirmation.": "로컬 디스크의 총 여유 공간 / 용량과 소수점 둘째 자리 비율을 표시합니다. 클릭하면 별도 터미널에서 정리를 선택하며 확인 후에만 실행합니다.",
    "Create script launcher…": "스크립트 실행 파일 만들기…",
    "🔗 Create script launcher…": "🔗 스크립트 실행 파일 만들기…",
    "Create a relative launcher beside a same-name .cmd/.bat/.ps1 script folder; do not run or modify the source script.": "같은 이름의 .cmd/.bat/.ps1 스크립트 폴더 옆에 상대 경로 실행 파일을 만듭니다. 원본 스크립트를 실행하거나 수정하지 않습니다.",
    "Theme": "테마",
    "Language": "언어",
    "🎨 Theme": "🎨 테마",
    "🌐 Language": "🌐 언어",
    "Follow system": "시스템 설정 따름",
    "Dark": "어둡게",
    "Light": "밝게",
    "Jobs Finder Extension Manager": "Jobs Finder 확장 관리자",
    "Customize Finder Context Menu": "Finder 오른쪽 클릭 메뉴 사용자화",
    "Close Manager": "관리자 닫기",
    "Edit": "편집",
    "Copy": "복사",
    "Select all": "모두 선택",
    "Clear all": "모두 선택 해제",
    "Close": "닫기",
    "OK": "확인",
    "Install": "설치",
    "Install / Update": "설치 / 업데이트",
    "Uninstall": "제거",
    "Cleanup": "정리",
    "Clean build products": "빌드 결과물 정리",
    "🧹 Clean build products": "🧹 빌드 결과물 정리",
    "Stop installation": "설치 중지",
    "Stopping…": "중지 중…",
    "Action: install / update or uninstall": "작업: 설치 / 업데이트 또는 제거",
    "Uninstall removes selected menus only. Group selection affects its own group.": "선택한 메뉴만 제거합니다. 그룹 선택은 해당 그룹에만 적용됩니다.",
    "Install / uninstall with the combined App in Applications": "응용 프로그램의 통합 App으로 설치 / 제거",
    "Install or uninstall the combined App in Applications": "응용 프로그램의 통합 App 설치 또는 제거",
    "Selected: manage features in /Applications/Jobs自定义右键菜单.app. Otherwise use the build directory.": "선택하면 /Applications/Jobs自定义右键菜单.app의 기능을 관리합니다. 선택하지 않으면 빌드 디렉터리를 사용합니다.",
    "Clean this build after successful installation": "설치 성공 후 이번 빌드 정리",
    "Clean this build only after the combined App is installed and verified in Applications. Keep failed builds.": "통합 App을 응용 프로그램에 설치하고 검증한 뒤에만 이번 빌드를 정리합니다. 실패한 빌드는 유지합니다.",
    "Clean build products of selected features without installing or uninstalling.": "선택한 기능의 빌드 결과물만 정리합니다. 설치하거나 제거하지 않습니다.",
    "Clean selected features' build products": "선택한 기능의 빌드 결과물 정리",
    "Open Privacy & Security": "개인정보 보호 및 보안 열기",
    "Add and enable Jobs右键菜单管理面板.app in Privacy & Security → App Management. This only opens Settings.": "개인정보 보호 및 보안 → App 관리에서 Jobs右键菜单管理面板.app을 추가하고 활성화하세요. 이 버튼은 설정만 엽니다.",
    "Target: build directory. Cleaning these products affects installed features.": "대상: 빌드 디렉터리. 결과물을 정리하면 설치된 기능에 영향을 줍니다.",
    "App: Jobs自定义右键菜单.app at /Applications/Jobs自定义右键菜单.app (build products can be cleaned after installation)": "App: /Applications/Jobs自定义右键菜单.app (설치 후 빌드 결과물 정리 가능)",
    "Drag the divider to resize the log. Features and logs scroll separately.": "구분선을 위아래로 드래그해 로그 높이를 조절하세요. 기능과 로그는 각각 스크롤됩니다.",
    "Feature list and live log divider": "기능 목록과 실시간 로그 구분선",
    "Live log (select and copy text)": "실시간 로그 (텍스트 선택 및 복사 가능)",
    "Copy log": "로그 복사",
    "Log file": "로그 파일",
    "Auto-scroll": "자동 스크롤",
    "Ready. Select features and choose an action.": "준비되었습니다. 기능을 선택하고 작업 버튼을 누르세요.",
    "A task is running. Wait for it to finish before closing.": "작업이 실행 중입니다. 완료된 후 닫으세요.",
    "Unable to view this log": "이 로그를 볼 수 없습니다",
    "Log is missing or unreadable: {0}": "로그가 없거나 읽을 수 없습니다: {0}",
    "Unable to open log terminal: {0}": "로그 터미널을 열 수 없습니다: {0}",
    "Click to show this session's full log in a new terminal: {0}": "클릭하면 새 터미널에서 이번 세션의 전체 로그를 표시합니다: {0}",
    "Selected {0} / {1}. Select at least one. Changing action keeps selection.": "{0} / {1}개 선택됨. 하나 이상 선택하세요. 작업을 전환해도 선택은 유지됩니다.",
    "Selected {0} / {1}": "{0} / {1}개 선택됨",
    "{0}: select all": "{0}: 모두 선택",
    "{0}: clear all": "{0}: 모두 선택 해제",
    "Waiting": "대기 중",
    "Cleaning…": "정리 중…",
    "Uninstalling…": "제거 중…",
    "Installing…": "설치 중…",
    "Cleaned": "정리됨",
    "Uninstalled": "제거됨",
    "Installed": "설치됨",
    "Skipped": "실행 안 함",
    "Not installed; nothing to remove": "미설치: 제거할 항목 없음",
    "Failed: see log": "실패: 로그 확인",
    "Selected": "선택됨",
    "Not selected": "선택 안 됨",
    "App Management permission required": "App 관리 권한 필요",
    "Permission check required": "권한 확인 필요",
    "Stopped": "중지됨",
    "Completed": "완료",
    "Task failed": "작업 실패",
    "{0}: processed {1} / {2} ({3}, completed items); {4} time {5}": "{0}: 처리됨 {1} / {2} ({3}, 완료 항목 기준); {4} 시간 {5}",
    "{0} ready": "{0} 준비됨",
    "{0} ready; {1} time {2}": "{0} 준비됨; {1} 시간 {2}",
    "Finishing the current feature, then stopping; install time {0}": "현재 기능을 완료한 후 중지합니다; 설치 시간 {0}",
    "{0}: {1} succeeded, {2} failed, {3} skipped; exit {4}; {5}; {6} time {7}": "{0}: 성공 {1}, 실패 {2}, 실행 안 함 {3}; 종료 {4}; {5}; {6} 시간 {7}",
    "{0}: {1} succeeded, {2} failed, {3} not installed, {4} skipped; exit {5}; {6}; {7} time {8}": "{0}: 성공 {1}, 실패 {2}, 제거 불필요 {3}, 실행 안 함 {4}; 종료 {5}; {6}; {7} 시간 {8}",
    "{0}: {1} succeeded, {2} failed, {3} not installed; exit {4}; {5}; {6} time {7}": "{0}: 성공 {1}, 실패 {2}, 제거 불필요 {3}; 종료 {4}; {5}; {6} 시간 {7}",
    "{0}: {1} succeeded, {2} failed; exit {3}; {4}; {5} time {6}": "{0}: 성공 {1}, 실패 {2}; 종료 {3}; {4}; {5} 시간 {6}",
    "Open projects in IDEs": "IDE에서 프로젝트 열기",
    "Git tools": "Git 도구",
    "Files and general tools": "파일 및 일반 도구",
    "Flutter tools · submenu actions": "Flutter 도구 · 하위 메뉴 작업",
    "iOS / CocoaPods tools": "iOS / CocoaPods 도구",
    "Simulator tools": "시뮬레이터 도구",
    "Open project in Android Studio": "Android Studio에서 프로젝트 열기",
    "Open project in VSCode": "VSCode에서 프로젝트 열기",
    "Open project in Xcode": "Xcode에서 프로젝트 열기",
    "Pull latest Git changes": "최신 Git 변경 사항 가져오기",
    "Roll back Git commit": "Git 커밋 되돌리기",
    "Open Git remote URL": "Git 원격 URL 열기",
    "Copy Git remote URL": "Git 원격 URL 복사",
    "Copy absolute path": "절대 경로 복사",
    "Create file": "파일 만들기",
    "View file fingerprint Hash (SHA-256)": "파일 해시 보기 (SHA-256)",
    "Grant execute permission (chmod +x)": "실행 권한 부여 (chmod +x)",
    "Remove execute permission (chmod -x)": "실행 권한 제거 (chmod -x)",
    "Re-sign IPA without building": "빌드 없이 IPA 다시 서명",
    "Show / hide files": "파일 표시 / 숨기기",
    "Create iOS simulator": "iOS 시뮬레이터 만들기",
    "Create Android simulator": "Android 시뮬레이터 만들기",
    "Create Harmony simulator": "Harmony 시뮬레이터 만들기",
    "Check / repair Android simulator": "Android 시뮬레이터 진단 / 복구",
    "Check / repair Harmony simulator": "Harmony 시뮬레이터 진단 / 복구",
    "Configure Git proxy": "Git 프록시 설정",
    "Open in terminal": "터미널에서 열기",
    "View file contents in terminal": "터미널에서 파일 내용 보기",
    "Merge file parts": "분할 파일 합치기",
    "Split file": "파일 분할",
    "Clean Android / OpenHarmony builds": "Android / OpenHarmony 빌드 정리",
    "Update code map (.codegraph)": "코드 맵 업데이트 (.codegraph)",
    "Create empty commit and push in terminal": "터미널에서 빈 커밋을 만들고 Push",
    "Disable CocoaPods build sandbox": "CocoaPods 빌드 샌드박스 비활성화",
    "Install CocoaPods": "CocoaPods 설치",
    "CocoaPods source: CDN → GitHub": "CocoaPods 소스: CDN → GitHub",
    "Export all project Pod files": "프로젝트의 모든 Pod 파일 내보내기",
    "Inspect Xcode project dependencies": "Xcode 프로젝트 의존성 확인",
    "Update local CocoaPods repositories": "로컬 CocoaPods 저장소 업데이트",
    "Check local Pod builds (.podspec folder)": "로컬 Pod 빌드 확인 (.podspec 폴더)",
    "Install / update JobsCodeSnippets": "JobsCodeSnippets 설치 / 업데이트",
    "Clean iOS / Xcode builds": "iOS / Xcode 빌드 정리",
    "Set up Flutter project": "Flutter 프로젝트 설정",
    "Run Flutter project in terminal": "터미널에서 Flutter 프로젝트 실행",
    "Fetch Flutter Pub dependencies": "Flutter Pub 의존성 가져오기",
    "Fetch native Android dependencies": "Android 네이티브 의존성 가져오기",
    "Fetch CocoaPods dependencies": "CocoaPods 의존성 가져오기",
    "Fetch Swift Package dependencies": "Swift Package 의존성 가져오기",
    "Fetch OpenHarmony dependencies": "OpenHarmony 의존성 가져오기",
    "Prepare native libraries and build dependencies": "네이티브 라이브러리와 빌드 의존성 준비",
    "Download Flutter platform resources": "Flutter 플랫폼 리소스 다운로드",
    "Fetch Web project dependencies": "Web 프로젝트 의존성 가져오기",
    "🧳 Export Flutter dependencies": "🧳 Flutter 의존성 내보내기",
    "Export Flutter Pub dependencies": "Flutter Pub 의존성 내보내기",
    "🔐 Export private Flutter dependencies": "🔐 Flutter 비공개 의존성 내보내기",
    "📥 Import Flutter dependencies": "📥 Flutter 의존성 가져오기",
    "Import Flutter Pub dependencies": "Flutter Pub 의존성 가져오기",
    "📥 Import private Flutter dependencies": "📥 Flutter 비공개 의존성 가져오기",
    "Export Gradle distributions and cache": "Gradle 배포 파일과 캐시 내보내기",
    "Import Gradle distributions and cache": "Gradle 배포 파일과 캐시 가져오기",
    "Export CocoaPods dependencies": "CocoaPods 의존성 내보내기",
    "Import CocoaPods dependencies": "CocoaPods 의존성 가져오기",
    "Export Swift Package dependencies": "Swift Package 의존성 내보내기",
    "Import Swift Package dependencies": "Swift Package 의존성 가져오기",
    "Export OpenHarmony dependencies": "OpenHarmony 의존성 내보내기",
    "Import OpenHarmony dependencies": "OpenHarmony 의존성 가져오기",
    "Export native build cache": "네이티브 빌드 캐시 내보내기",
    "Import native build cache": "네이티브 빌드 캐시 가져오기",
    "Export Flutter platform resources": "Flutter 플랫폼 리소스 내보내기",
    "Import Flutter platform resources": "Flutter 플랫폼 리소스 가져오기",
    "Export Web dependencies": "Web 의존성 내보내기",
    "Import Web dependencies": "Web 의존성 가져오기",
    "Show Flutter project SDK version": "Flutter 프로젝트 SDK 버전 보기",
    "Install / switch Flutter SDK": "Flutter SDK 설치 / 전환",
    "Install / switch Flutter@OpenHarmony SDK": "Flutter@OpenHarmony SDK 설치 / 전환",
    "Install / switch Java SDK": "Java SDK 설치 / 전환",
    "Download Gradle distributions and plugins": "Gradle 배포 파일과 플러그인 다운로드",
    "Generate Flutter code": "Flutter 코드 생성",
    "Package iOS": "iOS 패키징",
    "Package Android": "Android 패키징",
    "Package Harmony (HAP + APP)": "Harmony 패키징 (HAP + APP)",
    "Check native Flutter project": "네이티브 Flutter 프로젝트 진단",
    "Check OpenHarmony Flutter environment": "OpenHarmony Flutter 환경 진단",
    "Repair missing Android SDK / platforms": "누락된 Android SDK / platforms 복구",
    "Repair Chinese Flutter project paths": "Flutter 프로젝트 중국어 경로 복구",
    "Repair Flutter plugin namespaces": "Flutter 플러그인 namespace 복구",
    "Convert relative Dart imports to packages": "Dart 상대 import를 package 참조로 변환",
    "Clean current Flutter project builds": "현재 Flutter 프로젝트 빌드 정리",
    "Dependency and cache maintenance": "의존성 및 캐시 유지 관리",
    "Custom Explorer context menu": "Explorer 오른쪽 클릭 메뉴 사용자화",
    "Jobs Windows · Custom Explorer context menu": "Jobs Windows · Explorer 오른쪽 클릭 메뉴 사용자화",
    "Show a regular file's SHA-256 in a new terminal and copy the digest; do not modify or execute the file.": "새 터미널에서 일반 파일의 SHA-256을 표시하고 해시를 복사합니다. 파일을 수정하거나 실행하지 않습니다.",
    " (preview)": " (미리 보기)",
    "⏪ Roll back Git commits": "⏪ Git 커밋 되돌리기",
    "▶️ Run Flutter project in terminal": "▶️ 터미널에서 Flutter 프로젝트 실행",
    "☕ Install / switch Java SDK": "☕ Java SDK 설치 / 전환",
    "♻️ Flutter cleanup and maintenance": "♻️ Flutter 정리 및 유지 관리",
    "⚙️ Generate Flutter code": "⚙️ Flutter 코드 생성",
    "✅ Installed": "✅ 설치됨",
    "⬇️ Pull latest Git changes": "⬇️ 최신 Git 변경 사항 가져오기",
    "🌈 Create Harmony emulator": "🌈 Harmony 에뮬레이터 만들기",
    "🌐 Open Git remote URL": "🌐 Git 원격 URL 열기",
    "🌐 Fetch Web project dependencies": "🌐 Web 프로젝트 의존성 가져오기",
    "🌳 Open in Sourcetree": "🌳 Sourcetree에서 열기",
    "🏥 Flutter project diagnostics": "🏥 Flutter 프로젝트 진단",
    "🏥 Flutter diagnostics": "🏥 Flutter 진단",
    "🏷️ Repair Flutter plugin namespaces": "🏷️ Flutter 플러그인 namespace 복구",
    "👁️ Show / hide hidden files": "👁️ 숨김 파일 표시 / 숨기기",
    "💓 OpenHarmony Flutter diagnostics": "💓 OpenHarmony Flutter 환경 진단",
    "💠 Open project in Visual Studio": "💠 Visual Studio에서 프로젝트 열기",
    "💻 Open in terminal": "💻 터미널에서 열기",
    "📄 View file in terminal": "📄 터미널에서 파일 보기",
    "📋 Copy absolute path": "📋 절대 경로 복사",
    "📚 Download Gradle distributions and build plugins": "📚 Gradle 배포 파일과 빌드 플러그인 다운로드",
    "📝 Open project in VSCode": "📝 VSCode에서 프로젝트 열기",
    "📡 Configure Git dynamic proxy": "📡 Git 동적 프록시 설정",
    "📤 Import Flutter Pub dependencies": "📤 Flutter Pub 의존성 가져오기",
    "📤 Import Flutter platform assets": "📤 Flutter 플랫폼 에셋 가져오기",
    "📤 Import Gradle distributions and dependency caches": "📤 Gradle 배포 파일과 의존성 캐시 가져오기",
    "📤 Import OpenHarmony dependencies": "📤 OpenHarmony 의존성 가져오기",
    "📤 Import Web dependencies": "📤 Web 의존성 가져오기",
    "📤 Import native build caches": "📤 네이티브 빌드 캐시 가져오기",
    "📤 Import Flutter project dependencies": "📤 Flutter 프로젝트 의존성 가져오기",
    "📤 Create empty commit and push": "📤 빈 커밋을 만들고 Push",
    "📥 Install Flutter dependencies (pub get)": "📥 Flutter 의존성 설치 (pub get)",
    "📥 Import private Flutter project dependencies": "📥 Flutter 프로젝트 비공개 의존성 가져오기",
    "📥 Fetch Flutter Pub dependencies": "📥 Flutter Pub 의존성 가져오기",
    "📥 Fetch Flutter project dependencies": "📥 Flutter 프로젝트 의존성 가져오기",
    "📦 Package Flutter project": "📦 Flutter 프로젝트 패키징",
    "📦 Package HarmonyOS (HAP + APP)": "📦 HarmonyOS 패키징 (HAP + APP)",
    "📱 Create Android emulator": "📱 Android 에뮬레이터 만들기",
    "🔀 Install / switch Flutter SDK (FVM)": "🔀 Flutter SDK 설치 / 전환 (FVM)",
    "🔀 Install / switch Flutter SDK": "🔀 Flutter SDK 설치 / 전환",
    "🔀 Install / switch Flutter environments": "🔀 Flutter 실행 환경 설치 / 전환",
    "🔎 Show current Flutter SDK version": "🔎 현재 Flutter SDK 버전 보기",
    "🔎 Show current Flutter project's SDK version": "🔎 현재 Flutter 프로젝트 SDK 버전 보기",
    "🔐 Export private Flutter project dependencies": "🔐 Flutter 프로젝트 비공개 의존성 내보내기",
    "🔎 Show file fingerprint Hash (SHA-256)": "🔎 파일 해시 보기 (SHA-256)",
    "➕ Grant execute permission": "➕ 실행 권한 부여",
    "➖ Remove execute permission": "➖ 실행 권한 제거",
    "🔒 Grant execute permission": "🔒 실행 권한 부여",
    "🔓 Remove execute permission": "🔓 실행 권한 제거",
    "🔗 Copy Git remote URL": "🔗 Git 원격 URL 복사",
    "🔧 Flutter repairs": "🔧 Flutter 복구",
    "🕊️ Install / switch Flutter@OpenHarmony SDK": "🕊️ Flutter@OpenHarmony SDK 설치 / 전환",
    "🕊️ Fetch OpenHarmony dependencies": "🕊️ OpenHarmony 의존성 가져오기",
    "🗃️ Download Flutter platform assets": "🗃️ Flutter 플랫폼 에셋 다운로드",
    "🗺️ Update code map (.codegraph)": "🗺️ 코드 맵 업데이트 (.codegraph)",
    "🤖 Fetch Android native dependencies": "🤖 Android 네이티브 의존성 가져오기",
    "🦋 Flutter development": "🦋 Flutter 개발",
    "🦋 Flutter development tools": "🦋 Flutter 개발 도구",
    "🧑‍⚕️ Native Flutter diagnostics": "🧑‍⚕️ 네이티브 Flutter 진단",
    "🧩 Export Flutter Pub dependencies": "🧩 Flutter Pub 의존성 내보내기",
    "🧩 Export Flutter platform assets": "🧩 Flutter 플랫폼 에셋 내보내기",
    "🧩 Export Flutter third-party dependencies": "🧩 Flutter 서드 파티 의존성 내보내기",
    "🧩 Export Gradle distributions and dependency caches": "🧩 Gradle 배포 파일과 의존성 캐시 내보내기",
    "🧩 Export OpenHarmony dependencies": "🧩 OpenHarmony 의존성 내보내기",
    "🧩 Export Web dependencies": "🧩 Web 의존성 내보내기",
    "🧩 Export native build caches": "🧩 네이티브 빌드 캐시 내보내기",
    "🧩 Export Flutter project dependencies": "🧩 Flutter 프로젝트 의존성 내보내기",
    "🧩 Merge file volumes / ✂️ Split file": "🧩 분할 파일 합치기 / ✂️ 파일 분할",
    "🧭 Open project in Android Studio": "🧭 Android Studio에서 프로젝트 열기",
    "🧯 Clean build output": "🧯 빌드 출력 정리",
    "🧰 Diagnose and repair Harmony emulator": "🧰 Harmony 에뮬레이터 진단 및 복구",
    "🧱 Flutter assets and build dependencies": "🧱 Flutter 에셋 및 빌드 의존성",
    "🧱 Prepare native libraries and build dependencies (combined)": "🧱 네이티브 라이브러리와 빌드 의존성 준비 (통합)",
    "🧹 Clean build output": "🧹 빌드 출력 정리",
    "🩹 Repair missing Android SDK / platforms": "🩹 누락된 Android SDK / platforms 복구",
    "🩺 Diagnose and repair Android emulator": "🩺 Android 에뮬레이터 진단 및 복구",
    "🚀 Set up Flutter project": "🚀 Flutter 프로젝트 설정",
    "🚚 Import all Flutter dependencies": "🚚 모든 Flutter 의존성 가져오기",
    "🚚 Export all Flutter dependencies": "🚚 모든 Flutter 의존성 내보내기",
    "Jobs Windows · Uninstall Explorer extensions": "Jobs Windows · Explorer 확장 제거",
    "Jobs Windows · Install Explorer extensions": "Jobs Windows · Explorer 확장 설치",
    "Jobs Windows · Manage Explorer extensions": "Jobs Windows · Explorer 확장 관리",
    "Jobs Windows · Configure Explorer extensions": "Jobs Windows · Explorer 확장 설정",
    "Drag the divider vertically to resize the log": "구분선을 위아래로 드래그해 로그 높이 조절",
    "Drag vertically to resize the log": "위아래로 드래그해 로그 높이 조절",
    "Validate the Flutter project, diagnose the toolchain in terminal, and choose a Flutter SDK version with fzf.": "Flutter 프로젝트를 검증하고 터미널에서 도구 체인을 진단한 뒤 fzf로 Flutter SDK 버전을 선택합니다.",
    "Validate the Flutter project, then show the active SDK version (project FVM or system SDK) in terminal and compare it with .fvmrc and pubspec constraints.": "Flutter 프로젝트를 검증하고 실제 사용 중인 SDK 버전(프로젝트 FVM 또는 시스템 SDK)을 터미널에서 읽기 전용으로 표시한 뒤 .fvmrc 및 pubspec 제약과 비교합니다.",
    "Flutter roots only. Choose Android / iOS / HarmonyOS with fzf in CMD. Supports APK / AAB and HAP / APP. iOS requires MacOS and Xcode.": "Flutter 루트에만 표시됩니다. CMD의 fzf로 Android / iOS / HarmonyOS를 선택합니다. APK / AAB 및 HAP / APP을 지원하며 iOS에는 MacOS와 Xcode가 필요합니다.",
    "Flutter roots only. Choose a device and view logs in CMD; the app continues in the background after the window closes.": "Flutter 루트에만 표시됩니다. CMD에서 기기를 선택하고 로그를 확인합니다. 창을 닫아도 앱은 백그라운드에서 계속 실행됩니다.",
    "Flutter roots only. Read-only version and doctor diagnostics in terminal; no dependency fetching, cleanup, or tool upgrades.": "Flutter 루트에만 표시됩니다. 터미널에서 버전 및 doctor 진단만 읽기 전용으로 실행합니다. 의존성 가져오기, 정리 또는 도구 업그레이드는 수행하지 않습니다.",
    "Flutter roots only. Preview configured generators, then fetch dependencies and generate code after confirmation. Deleting conflicts requires separate opt-in.": "Flutter 루트에만 표시됩니다. 설정된 생성기를 미리 본 뒤 확인하면 의존성을 가져오고 코드를 생성합니다. 충돌 파일 삭제는 별도의 명시적 동의가 필요합니다.",
    "Git worktree folders only. Detect nested repositories. Soft mode preserves the index and worktree; hard mode requires exact YES confirmation.": "Git 작업 트리 폴더에만 표시됩니다. 중첩 저장소를 인식합니다. soft는 인덱스와 작업 내용을 유지하고 hard는 정확한 YES 확인이 필요합니다.",
    "Desktop background on x64 Windows only. Missing tools come from the SDL mirror; missing system images come from the official Emulator. Enter selects a stable phone image; confirm its license to create and start a unique instance.": "x64 Windows 바탕 화면 배경에만 표시됩니다. 누락 도구는 SDL 미러에서, 시스템 이미지는 공식 Emulator에서 가져옵니다. Enter로 안정 버전 휴대전화 이미지를 선택하고 라이선스를 확인한 후 고유 인스턴스를 만들고 실행합니다.",
    "Manage only this package's actions. Unselected actions remain when uninstalling.": "이 패키지의 작업만 관리합니다. 제거할 때 선택하지 않은 작업은 유지합니다.",
    "Desktop background only. Configure user-level Git to prefer the system proxy and fall back to a direct connection.": "바탕 화면 배경에만 표시됩니다. 사용자 수준 Git이 시스템 프록시를 우선 사용하고 실패하면 직접 연결로 전환하도록 설정합니다.",
    "Desktop background only. Diagnose the SDK in CMD, choose a device and system image, then create or start an Android AVD.": "바탕 화면 배경에만 표시됩니다. CMD에서 SDK를 진단하고 기종과 시스템 이미지를 선택하여 Android AVD를 만들거나 실행합니다.",
    "Desktop background only. Check existing DevEco Emulator instances, then start one or confirm a nondestructive restart. Data is preserved.": "바탕 화면 배경에만 표시됩니다. 기존 DevEco Emulator와 인스턴스를 확인한 뒤 선택한 항목을 실행하거나 확인 후 데이터를 유지하며 다시 시작합니다.",
    "Desktop background only. Check emulator location and /data; optionally reset caches, precisely uninstall, back up the AVD, and retest with a cold boot.": "바탕 화면 배경에만 표시됩니다. 에뮬레이터 위치와 /data를 확인합니다. 필요하면 캐시 초기화, 정확한 제거, 전체 AVD 백업 및 콜드 부팅 재검사를 수행할 수 있습니다.",
    "Show the next action on the desktop background. Toggle hidden files for the current user's Explorer without changing protected-system-file settings.": "바탕 화면 배경에 다음 작업을 표시합니다. 현재 사용자의 Explorer 숨김 파일 표시를 전환하며 보호된 시스템 파일 설정은 변경하지 않습니다.",
    "Visible only for nonempty native Android or valid Flutter (official / HarmonyOS) project roots. Validated again before opening.": "비어 있지 않은 네이티브 Android 또는 유효한 Flutter(공식 / HarmonyOS) 프로젝트 루트에만 표시되며 열기 전에 다시 검증합니다.",
    "Preview: the selection is shown in the log. No installation or uninstallation was performed.": "미리 보기 전용: 선택 내용이 로그에 표시되었습니다. 설치하거나 제거하지 않았습니다.",
    "Preview only. Confirming displays the selection in the log without installing, uninstalling, or writing state or registry entries.": "기능 선택 미리 보기 전용입니다. 확인하면 아래 로그에 선택 내용만 표시하며 설치, 제거, 상태 또는 레지스트리 쓰기는 수행하지 않습니다.",
    "Deployed copies use their bound location. To change it, open the manager from the source directory. Default installations run in the current user's LocalAppData; local builds run under this package's work directory and stop working if it moves.": "배포된 복사본은 현재 연결된 위치를 사용합니다. 위치를 바꾸려면 소스 디렉터리에서 관리자를 여세요. 기본 설치는 현재 사용자의 LocalAppData에서 독립 실행되며 로컬 빌드는 이 패키지의 work에서 실행되어 경로를 옮기면 작동하지 않습니다.",
    "Prefer Windows Terminal; otherwise use system PowerShell.": "Windows Terminal을 우선 사용하고 없으면 시스템 PowerShell을 사용합니다.",
    "Could not save preferences: ": "설정을 저장할 수 없습니다: ",
    "Save settings": "설정 저장",
    "Protect local changes. On conflict, choose to restore, discard changes, or commit and retry.": "로컬 변경을 보호합니다. 충돌하면 복원, 변경 취소 또는 커밋 후 다시 시도를 선택하세요.",
    "All operations completed. Copy the log or close the panel.": "모든 작업이 완료되었습니다. 로그를 복사하거나 패널을 닫으세요.",
    "Other context-menu features": "기타 오른쪽 클릭 메뉴 기능",
    "Create or synchronize the code map for the current directory.": "현재 디렉터리의 코드 맵을 생성하거나 동기화합니다.",
    "Feature and log divider": "기능 및 로그 구분선",
    "Select features, then confirm. Unselected features remain. Hover for installation details.": "기능을 선택하고 확인하세요. 선택하지 않은 기능은 유지됩니다. 마우스를 올리면 설치 상태를 볼 수 있습니다.",
    "Checked features are installed; unchecked ones are uninstalled. Saving an empty selection disables all installed features.": "선택한 기능은 설치하고 선택 해제한 기능은 제거합니다. 모두 선택 해제한 상태로 저장하면 설치된 모든 기능이 비활성화됩니다.",
    "Select features to install. Enabled sibling actions and other unselected features remain.": "설치할 기능을 선택하세요. 활성화된 같은 패키지의 다른 작업과 선택하지 않은 기능은 유지됩니다.",
    "Total uninstall time": "총 제거 시간",
    "Uninstall selected": "선택 항목 제거",
    "Uninstall selected features": "선택한 기능 제거",
    "Uninstall time": "제거 시간",
    "Cancel": "취소",
    "Uninstall only selected installed features. Other features, logs, backups and tools remain.": "선택한 설치된 기능만 제거합니다. 다른 기능, 로그, 백업 및 도구는 유지합니다.",
    "Change only the current user's ExecuteFile ACL for a single regular NTFS file after confirmation. Does not launch the file or change global policy.": "확인 후 일반 NTFS 파일 하나의 현재 사용자 ExecuteFile ACL만 변경합니다. 파일을 실행하거나 전역 정책을 변경하지 않습니다.",
    "View a single regular file. Files over 1 MiB or suspected binary files require YES in the terminal.": "일반 파일 하나만 표시합니다. 1 MiB를 넘거나 바이너리로 의심되면 터미널에 YES를 입력해야 합니다.",
    "Clean only the selected packages' build workspaces. Installed DLLs, scripts, settings and registry entries remain.": "선택한 패키지의 전용 빌드 작업 영역만 정리합니다. 설치된 DLL, 스크립트, 설정 및 레지스트리 항목은 유지합니다.",
    "Copy full log": "전체 로그 복사",
    "Copy the original remote URL for the current branch.": "현재 브랜치의 원래 원격 URL을 복사합니다.",
    "Copy the absolute path of a file or folder.": "파일 또는 폴더의 절대 경로를 복사합니다.",
    "Could not copy the log: ": "로그를 복사할 수 없습니다: ",
    "Failed — open log": "실패 — 로그 열기",
    "Install / update": "설치 / 업데이트",
    "Install / update selected features": "선택한 기능 설치 / 업데이트",
    "Total install time": "총 설치 시간",
    "Install time": "설치 시간",
    "Merge appears for a complete selected volume set; split appears for one regular file. Originals are always preserved.": "같은 그룹의 모든 분할 파일을 선택하면 합치기를 표시하고 일반 파일 하나를 선택하면 분할을 표시합니다. 원본은 항상 유지합니다.",
    "Live log (drag the divider to resize)": "실시간 로그 (위 구분선을 드래그해 높이 조절)",
    "Installation stopped after the current package transaction. Unstarted items are marked Not run.": "현재 패키지 트랜잭션이 끝난 뒤 설치가 중지되었습니다. 시작하지 않은 항목은 실행 안 함으로 표시됩니다.",
    "Stop requested. Waiting for the current package transaction; later items will not run.": "중지를 요청했습니다. 현재 패키지 트랜잭션이 끝나기를 기다리고 있으며 이후 항목은 실행하지 않습니다.",
    "Selected {0} / {1}. Closing or cancelling makes no changes.": "{0} / {1}개 선택됨. 닫거나 취소하면 변경하지 않습니다.",
    "Hover for feature details. Windows 11: right-click → Show more options.": "마우스를 올리면 기능 설명이 표시됩니다. Windows 11: 오른쪽 클릭 → 더 많은 옵션 표시.",
    "Could not open the full log: ": "전체 로그를 열 수 없습니다: ",
    "Open the repository website for the current Git worktree.": "현재 Git 작업 트리의 저장소 웹사이트를 엽니다.",
    "Open the solution or project at the current directory level.": "현재 디렉터리 수준의 솔루션이나 프로젝트를 엽니다.",
    "Export resolved third-party Pub sources and licenses from the project lockfile. Press Enter to use the desktop as output.": "프로젝트 잠금 파일에 따라 확인된 서드 파티 Pub 소스와 라이선스를 내보냅니다. 출력 위치에서 Enter를 누르면 바탕 화면을 사용합니다.",
    "An operation is running. Wait for the transaction to finish before closing. Logs can be copied at any time.": "작업이 실행 중입니다. 트랜잭션이 끝난 후 닫으세요. 로그는 언제든 복사할 수 있습니다.",
    "Could not build the operation plan: ": "작업 계획을 만들 수 없습니다: ",
    "Could not start the operation: ": "작업을 시작할 수 없습니다: ",
    "Log: ": "로그: ",
    "🈶 Repair Chinese paths in Flutter project": "🈶 Flutter 프로젝트 중국어 경로 복구",
    "Not installed; nothing to uninstall": "미설치: 제거할 항목 없음",
    "Not installed": "설치되지 않음",
    "Not run": "실행 안 함",
    "This feature": "이 기능",
    "Local build directory (moving or cleaning it disables the menu)": "로컬 빌드 디렉터리 (이동하거나 정리하면 메뉴 비활성화)",
    "Validate the branch, staging area and upstream, then confirm the push.": "브랜치, 스테이징 영역 및 업스트림을 검증한 뒤 Push를 확인합니다.",
    "Validate the Flutter project, then fetch dependencies.": "Flutter 프로젝트를 검증한 후 의존성을 가져옵니다.",
    "Installing / updating…": "설치 / 업데이트 중…",
    "This entry has been removed. Existing installations can be uninstalled but cannot be reinstalled.": "이 항목은 삭제되었습니다. 기존 설치 항목은 제거할 수 있지만 다시 설치할 수는 없습니다.",
    "No features require processing; ": "처리할 기능이 없습니다; ",
    "No features require processing. No settings were changed.": "처리할 기능이 없습니다. 설정을 변경하지 않았습니다.",
    "Total cleanup time": "총 정리 시간",
    "Cleanup time": "정리 시간",
    "Click to read the full session log in a new PowerShell window. The current task continues.": "클릭하면 새 PowerShell 창에서 이번 전체 세션 로그를 표시합니다. 현재 작업은 계속 실행됩니다.",
    "Pending": "대기 중",
    "Waiting to stop…": "중지 대기 중…",
    "Ordered Flutter development, diagnostics, repair and maintenance tools. Regular actions use project FVM; environment setup supports FVM / system Flutter and jEnv / system Java.": "Flutter 개발, 진단, 복구 및 유지 관리 도구를 정해진 순서로 표시합니다. 일반 작업에는 프로젝트 FVM을 사용하며 환경 설정에는 FVM / 시스템 Flutter 및 jEnv / 시스템 Java를 지원합니다.",
    "Detect the Flutter / Android project and preview cleanup scope. iOS cleanup is unavailable on Windows.": "Flutter / Android 프로젝트를 감지하고 정리 범위를 미리 봅니다. Windows에서는 iOS 정리를 사용할 수 없습니다.",
    "Could not read preferences: ": "설정을 읽을 수 없습니다: ",
    "Could not read the log: ": "로그를 읽을 수 없습니다: ",
    "Explorer context-menu extensions · ": "Explorer 오른쪽 클릭 메뉴 확장 · ",
    "Explorer extensions · Manage": "Explorer 확장 · 관리",
    "Return selection": "선택 내용 반환",
    "Exit code: ": "종료 코드: ",
    "Choose an operation and select features. Unselected features remain; only installed features can be uninstalled.": "작업을 고르고 기능을 선택하세요. 선택하지 않은 기능은 유지됩니다. 설치된 기능만 제거할 수 있습니다.",
    "Some features failed; other selected features were still processed. Click a failed status to open the full session log.": "일부 기능이 실패했지만 선택한 다른 기능은 계속 처리했습니다. 실패 상태를 클릭하면 전체 세션 로그를 볼 수 있습니다.",
    "Available for nonempty regular directories outside iOS projects, including Flutter roots. Validated again before opening.": "iOS 프로젝트가 아닌 비어 있지 않은 일반 디렉터리에서 사용할 수 있습니다. Flutter 루트를 지원하며 열기 전에 다시 검증합니다.",
    "Default installation location (recommended)": "기본 설치 위치 (권장)",
    "{0}; Results: succeeded {1}; nothing to uninstall {2}; failed {3}; not run {4}": "{0}; 결과: 성공 {1}; 제거 불필요 {2}; 실패 {3}; 실행 안 함 {4}",
    "{0} Exit code: {1}.": "{0} 종료 코드: {1}.",
    "{0} {1}": "{0} {1}",
    "{0}{1} {2}": "{0}{1} {2}",
    "{0} in progress; completed {1} / {2} ({3}% by completed items); {4} {5}": "{0} 진행 중; 완료 {1} / {2} ({3}%, 완료 항목 기준); {4} {5}",
    "{0} Completed {1} / {2} ({3}% by completed items); {4} {5}": "{0} 완료 {1} / {2} ({3}%, 완료 항목 기준); {4} {5}",
    "🫥 Hide / show selected items": "🫥 선택 항목 숨기기 / 표시",
    "Set the Hidden attribute of selected files or folders, including multiple selections; do not recurse, rename, or change global visibility preferences.": "선택한 파일이나 폴더의 숨김 특성을 설정합니다. 다중 선택을 지원하며 하위 항목, 이름 및 전체 표시 설정은 변경하지 않습니다.",
    "Permanently delete (skip Recycle Bin)": "영구 삭제 (휴지통 건너뛰기)",
    "Directly delete selected files or folders; confirm with the red left button or cancel with the blue right button. Cancellation is the default; deleted items cannot be restored from the Recycle Bin.": "선택한 파일이나 폴더를 직접 삭제합니다. 왼쪽 빨간색 확인, 오른쪽 파란색 취소 버튼을 표시하며 기본값은 취소입니다. 휴지통에서 복원할 수 없습니다."
  }
}
'@
# JOBS_MANAGER_TRANSLATIONS_END
# 英文键大小写有业务区别，PS5 的 PSCustomObject 不支持；使用 ordinal 字典保存完整键。
Add-Type -AssemblyName System.Runtime.Serialization
$translationType = [Collections.Generic.Dictionary[string,Collections.Generic.Dictionary[string,string]]]
$translationSettings = New-Object Runtime.Serialization.Json.DataContractJsonSerializerSettings
$translationSettings.UseSimpleDictionaryFormat = $true
$translationSerializer = New-Object Runtime.Serialization.Json.DataContractJsonSerializer($translationType, $translationSettings)
$translationStream = New-Object IO.MemoryStream(,[Text.Encoding]::UTF8.GetBytes($panelExtendedJson))
try { $script:PanelExtendedTranslations = $translationSerializer.ReadObject($translationStream) }
finally { $translationStream.Dispose() }
$script:PanelLanguageCodes = @('zh-Hans', 'zh-Hant', 'bo', 'en', 'ja', 'fr', 'es', 'de', 'ru', 'ko', 'system')
$script:PanelLanguageNames = @('简体中文', '繁體中文', 'བོད་ཡིག', 'English', '日本語', 'Français', 'Español', 'Deutsch', 'Русский', '한국어', '跟随系统')

function Get-JobsPanelLocalizedTemplate {
    param([string]$English, [string]$Language)
    if ($Language -ceq 'en') { return $English }
    if (-not $script:PanelExtendedTranslations.ContainsKey($Language) -or -not $script:PanelExtendedTranslations[$Language].ContainsKey($English)) { throw ('Missing panel translation: ' + $Language + ': ' + $English) }
    return $script:PanelExtendedTranslations[$Language][$English]
}

# 藏文优先使用Windows自带字体；只选择已安装字体，不下载或修改系统字体。
function Get-JobsPanelFontName {
    param([string]$Language, [string[]]$Available)
    $candidates = switch ($Language) {
        'bo' { @('Microsoft Himalaya', 'Noto Sans Tibetan', 'Nirmala UI', 'Segoe UI') }
        'ja' { @('Yu Gothic UI', 'Meiryo UI', 'Segoe UI') }
        'ko' { @('Malgun Gothic', 'Segoe UI') }
        { $_ -in @('zh-Hans','zh-Hant') } { @('Microsoft YaHei UI', 'Microsoft JhengHei UI', 'Segoe UI') }
        default { @('Segoe UI', 'Microsoft YaHei UI') }
    }
    foreach ($candidate in $candidates) { if ($candidate -in $Available) { return $candidate } }
    if ($Available.Count) { return $Available[0] }
    return 'Segoe UI'
}

function Set-JobsPanelLanguageFont {
    param($State, [string]$Language)
    $installed = New-Object Drawing.Text.InstalledFontCollection
    try { $family = Get-JobsPanelFontName $Language @($installed.Families | ForEach-Object { $_.Name }) }
    finally { $installed.Dispose() }
    $size = if ($Language -ceq 'bo') { 11 } else { 10 }
    if ($State.Font.Name -ceq $family -and [Math]::Abs($State.Font.SizeInPoints-$size) -lt 0.01) { return }
    $font = New-Object Drawing.Font($family, $size)
    $previous = $State.Font
    $controls = New-Object 'Collections.Generic.Queue[object]'
    $controls.Enqueue($State.Form)
    while ($controls.Count) {
        $control = $controls.Dequeue()
        if ([object]::ReferenceEquals($control, $State.LogView)) { continue }
        $control.Font = $font
        foreach ($child in $control.Controls) { $controls.Enqueue($child) }
    }
    $State.LogMenu.Font = $font
    $State.Font = $font
    $previous.Dispose()
}

# 偏好只影响管理面板；独立包与总面板共用当前用户设置。
function Get-JobsPanelPreferencesPath {
    param([string]$Path)
    if (-not [string]::IsNullOrWhiteSpace($Path)) { return $Path }
    return Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Jobs/WindowsExtension/panel-preferences.json'
}
# 坏文件或未知枚举回退到系统，不写回覆盖原文件。
function Read-JobsPanelPreferences {
    param([string]$Path)
    $result = [pscustomobject]@{ Theme = 'system'; Language = 'system'; Error = '' }
    try {
        $target = Get-JobsPanelPreferencesPath $Path
        if ([IO.File]::Exists($target)) {
            $data = [IO.File]::ReadAllText($target) | ConvertFrom-Json
            if ($null -ne $data.PSObject.Properties['Theme'] -and $data.Theme -cin @('system', 'dark', 'light')) { $result.Theme = [string]$data.Theme }
            if ($null -ne $data.PSObject.Properties['Language'] -and $data.Language -cin $script:PanelLanguageCodes) { $result.Language = [string]$data.Language }
        }
    } catch { $result.Error = $_.Exception.Message }
    return $result
}
# 同目录临时文件原子提交；失败保留旧偏好并由调用者显示原因。
function Save-JobsPanelPreferences {
    param([string]$Theme, [string]$Language, [string]$Path)
    if ($Theme -cnotin @('system', 'dark', 'light') -or $Language -cnotin $script:PanelLanguageCodes) { throw 'Invalid panel preference.' }
    $target = Get-JobsPanelPreferencesPath $Path
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
    $temporary = $target + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $data = [ordered]@{ Version = 1; Theme = $Theme; Language = $Language }
        [IO.File]::WriteAllText($temporary, (ConvertTo-Json -InputObject $data), (New-Object Text.UTF8Encoding($false)))
        if ([IO.File]::Exists($target)) { [IO.File]::Replace($temporary, $target, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $target) }
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}
# 汉字脚本优先于地区，未支持的系统语言使用英文。
function Resolve-JobsPanelLanguage {
    param([string]$Preference = 'system', [string]$SystemLanguage)
    if ($Preference -cne 'system' -and $Preference -cin $script:PanelLanguageCodes) { return $Preference }
    if ([string]::IsNullOrWhiteSpace($SystemLanguage)) {
        $SystemLanguage = [Globalization.CultureInfo]::CurrentUICulture.Name
        if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
            try { $SystemLanguage = [Globalization.CultureInfo]::GetCultureInfo([JobsPanelNative]::GetUserDefaultUILanguage()).Name } catch { }
        }
    }
    if ($SystemLanguage -match '^zh[-_](Hant|TW|HK|MO)([-_]|$)') { return 'zh-Hant' }
    if ($SystemLanguage -match '^zh($|[-_])') { return 'zh-Hans' }
    if ($SystemLanguage -match '^(bo|en|ja|fr|es|de|ru|ko)($|[-_])') { return $Matches[1].ToLowerInvariant() }
    return 'en'
}
# 只读系统应用外观，不修改系统主题或注册表。
function Resolve-JobsPanelTheme {
    param([string]$Preference = 'system', [Nullable[bool]]$SystemDark)
    if ($Preference -cin @('dark', 'light')) { return $Preference }
    if ($null -ne $SystemDark) { if ($SystemDark) { return 'dark' }; return 'light' }
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        try {
            $value = Get-ItemPropertyValue -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction Stop
            if ([int]$value -eq 0) { return 'dark' }
        } catch { }
    }
    return 'light'
}
# 统一语言入口兼容没有面板偏好字段的隔离事务夹具。
function Get-JobsPanelLanguage {
    param($State)
    if ($null -ne $State -and $null -ne $State.PSObject.Properties['Language']) { return [string]$State.Language }
    return 'zh-Hans'
}
# 字典只翻译面板正文；后台工具输出和未知诊断原样保留。
function Get-JobsPanelText {
    param([AllowEmptyString()][string]$Text, [string]$Language = 'zh-Hans')
    if ($Language -eq 'zh-Hans' -or [string]::IsNullOrEmpty($Text)) { return $Text }
    $index = 1
    if ($Language -eq 'zh-Hant') { $index = 0 }
    if ($script:PanelTranslations.ContainsKey($Text)) {
        if ($Language -cin @('zh-Hant','en')) { return [string]$script:PanelTranslations[$Text][$index] }
        return Get-JobsPanelLocalizedTemplate ([string]$script:PanelTranslations[$Text][1]) $Language
    }
    # 动态计数和计时共用模板，数值/路径/外部错误消息不会被当成翻译键。
    foreach ($rule in $script:PanelTextPatterns) {
        $match = [regex]::Match($Text, $rule.Pattern)
        if (-not $match.Success) { continue }
        $values = @()
        for ($i = 1; $i -lt $match.Groups.Count; $i++) { $values += Get-JobsPanelText $match.Groups[$i].Value $Language }
        $template = if ($Language -cin @('zh-Hant','en')) { [string]$rule.Text[$index] } else { Get-JobsPanelLocalizedTemplate ([string]$rule.Text[1]) $Language }
        return ($template -f $values)
    }
    if ($Text.Contains("`r`n")) { return (@($Text -split "`r`n" | ForEach-Object { Get-JobsPanelText $_ $Language }) -join "`r`n") }
    if ($Text.EndsWith('（仅预览）')) { return (Get-JobsPanelText $Text.Substring(0, $Text.Length - 5) $Language) + (Get-JobsPanelText '（仅预览）' $Language) }
    $prefix = '资源管理器右键扩展 · '
    if ($Text.StartsWith($prefix)) { return (Get-JobsPanelText $prefix $Language) + (Get-JobsPanelText $Text.Substring($prefix.Length) $Language) }
    # 外部诊断、日志路径不再拆字替换，避免改变文件名或工具错误原文。
    foreach ($prefix in @('保存偏好失败：', '读取偏好失败：', '复制日志失败：', '打开完整日志失败：', '无法建立操作计划：', '无法开始执行：', '读取日志失败：')) {
        if ($Text.StartsWith($prefix)) { return (Get-JobsPanelText $prefix $Language) + $Text.Substring($prefix.Length) }
    }
    return $Text
}
# 内嵌日志解析、明暗配色和原生视口保护；不加载外部脚本或修改终端样式。
function Initialize-JobsManagementLogFormat {
    if ('JobsManagementLog.AnsiParser' -as [type]) { return }
    $source = @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
namespace JobsManagementLog {
    public sealed class Span {
        public string Text, Style;
        public Span(string text, string style) { Text = text; Style = style; }
    }
    public sealed class Parsed {
        public string Plain;
        public Span[] Spans;
    }
    public static class Navigation {
        public static bool IsInput(int message, int key) {
            if (message == 0x20a || message == 0x20e || message == 0x24e || message == 0x24f || message == 0x119 || message == 0x115 || message == 0x114 || message == 0x201) return true;
            return message == 0x100 && (key == 33 || key == 34 || key == 35 || key == 36 || key == 37 || key == 38 || key == 39 || key == 40);
        }
    }
    public static class Palette {
        public static int Background(bool dark) { return dark ? 0x101821 : 0xf4f7fa; }
        public static string Level(string text) {
            if (Regex.IsMatch(text ?? "", @"^\s*(?:\[\d{4}[^\]]*\]\s*)?(?:\[?(?:ERROR|FAILED|FAIL)\]?\b|错误[:：]|失败[:：]|✖|❌)", RegexOptions.IgnoreCase)) return "error";
            if (Regex.IsMatch(text ?? "", @"^\s*[^\r\n]+(?:\(\d+(?:,\d+)?\)|:\d+(?::\d+)?)\s*:\s*warning\b", RegexOptions.IgnoreCase)) return "warning";
            if (Regex.IsMatch(text ?? "", @"^\s*(?:\[?(?:WARN|WARNING)\]?\b|警告[:：]|⚠)", RegexOptions.IgnoreCase)) return "warning";
            if (Regex.IsMatch(text ?? "", @"^\s*(?:\[?(?:SUCCESS|PASS|OK)\]?\b|成功[:：]|已完成|全部处理完成|✅|✔)", RegexOptions.IgnoreCase)) return "success";
            if (Regex.IsMatch(text ?? "", @"^\s*(?:\[?INFO\]?\b|信息[:：]|来源[:：]|➤|ℹ)", RegexOptions.IgnoreCase)) return "info";
            return "normal";
        }
        private static double Channel(int value) { double n = value / 255.0; return n <= .04045 ? n / 12.92 : Math.Pow((n + .055) / 1.055, 2.4); }
        private static double Luminance(int rgb) { return .2126 * Channel((rgb >> 16) & 255) + .7152 * Channel((rgb >> 8) & 255) + .0722 * Channel(rgb & 255); }
        public static double Contrast(int a, int b) { double x = Luminance(a), y = Luminance(b); return (Math.Max(x,y) + .05) / (Math.Min(x,y) + .05); }
        public static int Color(string style, bool dark) {
            int rgb = dark ? 0xdfe7f1 : 0x243244;
            switch (style) {
                case "error": rgb = dark ? 0xffa39b : 0xa51f19; break;
                case "warning": rgb = dark ? 0xf7cf7b : 0x805600; break;
                case "success": rgb = dark ? 0x8cdeb0 : 0x14643a; break;
                case "info": rgb = dark ? 0x94c9ff : 0x155991; break;
                case "accent": rgb = dark ? 0xdcb5f6 : 0x7d3591; break;
                case "cyan": rgb = dark ? 0x85d8df : 0x006574; break;
                default:
                    int parsed;
                    if (style != null && style.StartsWith("rgb:", StringComparison.Ordinal) && style.Length == 10 && int.TryParse(style.Substring(4), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out parsed)) rgb = parsed;
                    break;
            }
            int background = Background(dark);
            while (Contrast(rgb, background) < 4.5) {
                int r = (rgb >> 16) & 255, g = (rgb >> 8) & 255, b = rgb & 255;
                if (dark) { r = Math.Min(255, r + 8); g = Math.Min(255, g + 8); b = Math.Min(255, b + 8); }
                else { r = Math.Max(0, r - 8); g = Math.Max(0, g - 8); b = Math.Max(0, b - 8); }
                int next = (r << 16) | (g << 8) | b;
                if (next == rgb) break;
                rgb = next;
            }
            return unchecked((int)0xff000000) | rgb;
        }
    }
    public sealed class AnsiParser {
        private int state;
        private string foreground;
        private readonly StringBuilder parameters = new StringBuilder();
        private bool overflow;
        private static readonly string[] Basic = { "normal", "error", "success", "warning", "info", "accent", "cyan", "normal" };
        private static string Indexed(int n) {
            if (n < 0 || n > 255) return null;
            if (n < 16) return Basic[n % 8];
            int r, g, b;
            if (n >= 232) { r = g = b = 8 + (n - 232) * 10; }
            else { int v = n - 16; int[] cube = { 0, 95, 135, 175, 215, 255 }; r = cube[v / 36]; g = cube[(v / 6) % 6]; b = cube[v % 6]; }
            return "rgb:" + ((r << 16) | (g << 8) | b).ToString("x6", CultureInfo.InvariantCulture);
        }
        private void Sgr() {
            if (overflow) return;
            string[] parts = parameters.ToString().Split(';');
            var values = new List<int>();
            foreach (string p in parts) { int n; if (!int.TryParse(p.Length == 0 ? "0" : p, out n)) return; values.Add(n); }
            for (int i = 0; i < values.Count; i++) {
                int v = values[i];
                if (v == 0 || v == 39) foreground = null;
                else if (v >= 30 && v <= 37) foreground = Basic[v - 30];
                else if (v >= 90 && v <= 97) foreground = Basic[v - 90];
                else if (v == 38 || v == 48 || v == 58) {
                    if (i + 2 < values.Count && values[i + 1] == 5) { if (v == 38) foreground = Indexed(values[i + 2]); i += 2; }
                    else if (i + 4 < values.Count && values[i + 1] == 2) {
                        int r = values[i + 2], g = values[i + 3], b = values[i + 4];
                        if (v == 38 && r >= 0 && r <= 255 && g >= 0 && g <= 255 && b >= 0 && b <= 255) foreground = "rgb:" + ((r << 16) | (g << 8) | b).ToString("x6", CultureInfo.InvariantCulture);
                        i += 4;
                    } else return;
                }
            }
        }
        public Parsed Push(string text, string level) {
            var spans = new List<Span>(); var plain = new StringBuilder(); var pending = new StringBuilder(); string style = null;
            Action flush = delegate { if (pending.Length > 0) { spans.Add(new Span(pending.ToString(), style)); pending.Clear(); } };
            foreach (char ch in text ?? "") {
                if (state == 1) {
                    if (ch == '[') { state = 2; parameters.Clear(); overflow = false; }
                    else if (ch == ']') state = 3;
                    else if (ch == 'P' || ch == '^' || ch == '_' || ch == 'X') state = 4;
                    else state = 0;
                    continue;
                }
                if (state == 2) {
                    if (ch >= '@' && ch <= '~') { if (ch == 'm') Sgr(); state = 0; }
                    else if (ch == 27) state = 1;
                    else if (ch == '\r' || ch == '\n') state = 0;
                    else { if (parameters.Length < 128) parameters.Append(ch); else overflow = true; continue; }
                    if (ch != '\r' && ch != '\n') continue;
                }
                if (state == 3 || state == 4) {
                    if (ch == '\u009c' || (state == 3 && ch == '\a')) state = 0;
                    else if (ch == 27) state += 2;
                    continue;
                }
                if (state == 5 || state == 6) { if (ch == '\\' || ch == '\u009c') state = 0; else if (ch != 27) state -= 2; continue; }
                if (ch == 27) { state = 1; continue; }
                if (ch == '\u009b') { state = 2; parameters.Clear(); overflow = false; continue; }
                if (ch == '\u009d') { state = 3; continue; }
                if (ch == '\u0090' || ch == '\u0098' || ch == '\u009e' || ch == '\u009f') { state = 4; continue; }
                if ((ch < 32 && ch != '\r' && ch != '\n' && ch != '\t') || (ch >= 127 && ch <= 159)) continue;
                string next = foreground ?? level;
                if (style != next) { flush(); style = next; }
                pending.Append(ch); plain.Append(ch);
            }
            flush(); return new Parsed { Plain = plain.ToString(), Spans = spans.ToArray() };
        }
    }
    public sealed class Buffer {
        private readonly List<Span> runs = new List<Span>();
        private bool carriage;
        public int Length { get; private set; }
        public Span[] Runs { get { return runs.ToArray(); } }
        public void Reset(string text) { runs.Clear(); Length = 0; carriage = false; if (!String.IsNullOrEmpty(text)) { runs.Add(new Span(text, "normal")); Length = text.Length; } }
        public int Append(Span[] spans) {
            foreach (Span span in spans) {
                string text = span.Text;
                if (carriage && text.StartsWith("\n", StringComparison.Ordinal)) text = text.Substring(1);
                carriage = span.Text.EndsWith("\r", StringComparison.Ordinal);
                text = text.Replace("\r\n", "\n").Replace('\r', '\n');
                span.Text = text;
                if (text.Length == 0) continue;
                runs.Add(new Span(text, span.Style)); Length += text.Length;
            }
            int remove = Length > 1000000 ? Length - 700000 : 0;
            int rest = remove;
            while (rest > 0 && runs.Count > 0) {
                Span first = runs[0];
                if (rest >= first.Text.Length) { rest -= first.Text.Length; runs.RemoveAt(0); }
                else { first.Text = first.Text.Substring(rest); rest = 0; }
            }
            Length -= remove; return remove;
        }
    }
}
'@
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $source += @'
namespace JobsManagementLog {
    public sealed class View : System.Windows.Forms.RichTextBox {
        [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
        private struct Point { public int X, Y; }
        [System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint="SendMessageW")]
        private static extern System.IntPtr Send(System.IntPtr window, int message, System.IntPtr word, ref Point point);
        [System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint="SendMessageW")]
        private static extern System.IntPtr Redraw(System.IntPtr window, int message, System.IntPtr word, System.IntPtr value);
        private bool updating;
        public event System.EventHandler UserNavigation;
        protected override void WndProc(ref System.Windows.Forms.Message message) {
            if (!updating && Navigation.IsInput(message.Msg, unchecked((int)message.WParam.ToInt64())) && UserNavigation != null) UserNavigation(this, System.EventArgs.Empty);
            base.WndProc(ref message);
        }
        private Point Position() { var p = new Point(); if (IsHandleCreated) Send(Handle, 0x4dd, System.IntPtr.Zero, ref p); return p; }
        private int FirstLine() { return IsHandleCreated ? Redraw(Handle, 0xce, System.IntPtr.Zero, System.IntPtr.Zero).ToInt32() : 0; }
        private void Restore(Point position, int line) {
            if (!IsHandleCreated) return;
            Send(Handle, 0x4de, System.IntPtr.Zero, ref position);
            // EM_GETSCROLLPOS reports 16-bit pixel values; a line anchor also protects long logs.
            int difference = System.Math.Max(0, line) - FirstLine();
            if (difference != 0) Redraw(Handle, 0xb6, System.IntPtr.Zero, new System.IntPtr(difference));
        }
        private void StartUpdate() { updating = true; if (IsHandleCreated) Redraw(Handle, 11, System.IntPtr.Zero, System.IntPtr.Zero); }
        private void EndUpdate() { if (IsHandleCreated) { Redraw(Handle, 11, new System.IntPtr(1), System.IntPtr.Zero); Invalidate(); } updating = false; }
        public void AppendColored(string[] text, int[] colors, int remove, bool follow) {
            int start = SelectionStart, length = SelectionLength, line = FirstLine(); var position = Position();
            StartUpdate();
            try {
                for (int i = 0; i < text.Length; i++) { Select(TextLength, 0); SelectionColor = System.Drawing.Color.FromArgb(colors[i]); AppendText(text[i]); }
                remove = System.Math.Min(remove, TextLength);
                if (remove > 0) { line = System.Math.Max(0, line - GetLineFromCharIndex(remove)); position.Y = System.Math.Max(0, position.Y - (GetPositionFromCharIndex(remove).Y - GetPositionFromCharIndex(0).Y)); Select(0, remove); SelectedText = ""; }
                if (follow && length == 0) { Select(TextLength, 0); ScrollToCaret(); }
                else { int a = System.Math.Min(TextLength, System.Math.Max(0, start - remove)); int b = System.Math.Min(TextLength, System.Math.Max(a, start + length - remove)); Select(a, b - a); Restore(position, line); }
            } finally { EndUpdate(); }
        }
        public void Recolor(int[] lengths, int[] colors, int background, int foreground) {
            int start = SelectionStart, length = SelectionLength, line = FirstLine(); var position = Position();
            StartUpdate();
            try {
                BackColor = System.Drawing.Color.FromArgb(background); ForeColor = System.Drawing.Color.FromArgb(foreground);
                int offset = 0;
                for (int i = 0; i < lengths.Length; i++) { Select(offset, lengths[i]); SelectionColor = System.Drawing.Color.FromArgb(colors[i]); offset += lengths[i]; }
                Select(System.Math.Min(start, TextLength), System.Math.Min(length, System.Math.Max(0, TextLength - start)));
                Restore(position, line);
            } finally { EndUpdate(); }
        }
        public void FollowTail() { updating = true; try { Select(TextLength, 0); ScrollToCaret(); } finally { updating = false; } }
    }
}
'@
        Add-Type -TypeDefinition $source -ReferencedAssemblies @('System.dll', 'System.Core.dll', 'System.Windows.Forms.dll', 'System.Drawing.dll')
    } else { Add-Type -TypeDefinition $source }
}
# 兼容旧夹具或直接赋值的日志正文，保留其原文并按普通级别接管。
function Get-JobsManagementLogBuffer {
    param($State)
    Initialize-JobsManagementLogFormat
    if ($null -eq $State.PSObject.Properties['LogBuffer']) { $State | Add-Member NoteProperty LogBuffer (New-Object JobsManagementLog.Buffer) }
    if ($null -eq $State.PSObject.Properties['LogParsers']) { $State | Add-Member NoteProperty LogParsers @{} }
    if ($State.LogBuffer.Length -ne $State.LogView.TextLength) { $State.LogBuffer.Reset([string]$State.LogView.Text) }
    return $State.LogBuffer
}
# 系统高对比度及其颜色一起作为外观签名，不改系统设置。
function Get-JobsPanelContrastKey {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Windows.Forms.SystemInformation]::HighContrast) { return 'normal' }
    return ('high|{0}|{1}|{2}|{3}' -f [Drawing.SystemColors]::Window.ToArgb(), [Drawing.SystemColors]::WindowText.ToArgb(), [Drawing.SystemColors]::Control.ToArgb(), [Drawing.SystemColors]::ControlText.ToArgb())
}
# ANSI 前景色只作用于显示；高对比度采用系统正文色，其余按独立明暗日志底色校验对比度。
function Get-JobsManagementLogColors {
    param($State, [object[]]$Runs, $ContrastForeground = $null)
    foreach ($run in $Runs) {
        if ($null -ne $ContrastForeground) { [int]$ContrastForeground }
        else { [JobsManagementLog.Palette]::Color([string]$run.Style, ($State.Theme -eq 'dark')) }
    }
}
# 换主题只重着色现有分段，原生控件恢复原选区与像素滚动位置。
function Set-JobsManagementLogTheme {
    param($State, [string]$ContrastKey = '')
    $buffer = Get-JobsManagementLogBuffer $State
    $runs = @($buffer.Runs)
    if (-not $ContrastKey) { $ContrastKey = Get-JobsPanelContrastKey }
    $back = [JobsManagementLog.Palette]::Background(($State.Theme -eq 'dark')) -bor [int]::MinValue -bor 0x7f000000
    $front = [JobsManagementLog.Palette]::Color('normal', ($State.Theme -eq 'dark'))
    $contrastForeground = $null
    if ($ContrastKey.StartsWith('high|')) { $parts = $ContrastKey.Split('|'); $back = [int]$parts[1]; $front = [int]$parts[2]; $contrastForeground = $front }
    $State.LogView.Recolor([int[]]@($runs | ForEach-Object { $_.Text.Length }), [int[]]@(Get-JobsManagementLogColors $State $runs $contrastForeground), $back, $front)
    $State | Add-Member NoteProperty LogContrastKey $ContrastKey -Force
    $State | Add-Member NoteProperty LogContrastForeground $contrastForeground -Force
}

# 仅使用公开 DWM 和 UI 语言 API；旧系统不支持暗色标题栏时保留系统标题栏。
function Initialize-JobsPanelNative {
    if ($null -ne ('JobsPanelNative' -as [type])) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class JobsPanelNative {
    [DllImport("kernel32.dll")] public static extern ushort GetUserDefaultUILanguage();
    [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
}
'@
}
# 原始后台消息和日志路径逐字保留，仅重算面板自己的失败提示。
function Set-JobsPanelFeatureToolTip {
    param($State, [string]$Id, [string]$Message)
    $tip = $Message
    if ($State.FeatureStates.ContainsKey($Id) -and $State.FeatureStates[$Id] -eq 'Failed') {
        $tip += "`r`n" + (Get-JobsPanelText '点击在新 PowerShell 窗口读取本次完整会话日志；当前任务继续运行。' (Get-JobsPanelLanguage $State)) + "`r`n" + $State.LogPath
    }
    $State.ToolTip.SetToolTip($State.FeatureLabels[$Id], $tip)
}
# 对同一个控件树改色，失败链接/成功状态与清理按钮保留语义颜色。
function Set-JobsPanelControlTheme {
    param($Control, $State)
    if ([object]::ReferenceEquals($Control, $State.LogView)) { Set-JobsManagementLogTheme $State; return }
    $dark = $State.Theme -eq 'dark'
    $back = [Drawing.Color]::FromArgb(246, 247, 249)
    $front = [Drawing.Color]::FromArgb(30, 35, 42)
    $surface = [Drawing.Color]::White
    if ($dark) { $back = [Drawing.Color]::FromArgb(30, 33, 39); $front = [Drawing.Color]::FromArgb(235, 237, 240); $surface = [Drawing.Color]::FromArgb(45, 49, 57) }
    if ([Windows.Forms.SystemInformation]::HighContrast) { $back = [Drawing.SystemColors]::Control; $front = [Drawing.SystemColors]::ControlText; $surface = [Drawing.SystemColors]::Window }
    $Control.BackColor = $back
    $Control.ForeColor = $front
    if ($Control -is [Windows.Forms.Button] -or $Control -is [Windows.Forms.ComboBox]) { $Control.BackColor = $surface; $Control.FlatStyle = 'Flat' }
    if ([object]::ReferenceEquals($Control, $State.CleanupButton)) { $Control.BackColor = [Drawing.Color]::Firebrick; $Control.ForeColor = [Drawing.Color]::White }
    if ($Control -is [Windows.Forms.LinkLabel]) {
        $failed = [Drawing.Color]::Firebrick
        $success = [Drawing.Color]::ForestGreen
        if ($dark) { $failed = [Drawing.Color]::FromArgb(255, 135, 135); $success = [Drawing.Color]::FromArgb(123, 220, 158) }
        $Control.LinkColor = $failed; $Control.ActiveLinkColor = $failed; $Control.VisitedLinkColor = $failed
        if ($State.FeatureStates.ContainsKey([string]$Control.Tag)) {
            if ($State.FeatureStates[[string]$Control.Tag] -eq 'Failed') { $Control.ForeColor = $failed }
            elseif ($State.FeatureStates[[string]$Control.Tag] -eq 'Succeeded') { $Control.ForeColor = $success }
        }
    }
    foreach ($child in $Control.Controls) { Set-JobsPanelControlTheme $child $State }
}
# 保存每个静态控件的简体源文本，反复切换不会把译文再次翻译。
function Add-JobsPanelTextBindings {
    param($Control, $State)
    $excluded = @($State.StatusLabel, $State.ConfirmButton, $State.CancelButton, $State.LogView, $State.ThemeBox, $State.LanguageBox)
    $excluded += @($State.FeatureLabels.Values) + @($State.Groups | ForEach-Object { $_.Counter })
    if ($null -ne $State.PSObject.Properties['FeatureRows']) { foreach ($row in $State.FeatureRows.Values) { $excluded += @($row.Icon, $row.Title) } }
    if ($Control -isnot [Windows.Forms.ComboBox] -and $Control.Text -and $Control -notin $excluded) {
        $State.TextBindings.Add([pscustomobject]@{ Control = $Control; Source = [string]$Control.Text })
    }
    $tip = $State.ToolTip.GetToolTip($Control)
    if ($tip) { $State.ToolTipBindings.Add([pscustomobject]@{ Control = $Control; Source = $tip }) }
    foreach ($child in $Control.Controls) { Add-JobsPanelTextBindings $child $State }
}
# 卡片身份取清单原始组名，显示译文、视觉顺序与执行清单互不影响。
function Get-JobsPanelDefaultGroupLayout {
    param([object[]]$Groups)
    $orders = @(0, 0)
    foreach ($group in $Groups) {
        $column = 0
        if ($group.IsFlutter) { $column = 1 }
        [pscustomobject]@{ Key = [string]$group.Key; Column = $column; Order = $orders[$column] }
        $orders[$column]++
    }
}
function Get-JobsPanelGroupLayoutPath {
    param([string]$PreferencesPath, [object[]]$Groups)
    $keys = @($Groups | ForEach-Object { [string]$_.Key } | Sort-Object -CaseSensitive)
    $hash = [Security.Cryptography.SHA256]::Create()
    try { $scope = ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes(($keys -join "`n"))))).Replace('-', '').Substring(0,16) }
    finally { $hash.Dispose() }
    return Join-Path ([IO.Path]::GetDirectoryName((Get-JobsPanelPreferencesPath $PreferencesPath))) ('panel-group-layout-' + $scope + '.json')
}
function Read-JobsPanelGroupLayout {
    param([object[]]$Groups, [string]$Path)
    $defaults = @(Get-JobsPanelDefaultGroupLayout $Groups)
    $result = [pscustomobject]@{ Entries = $defaults; Error = '' }
    if (-not [IO.File]::Exists($Path)) { return $result }
    try {
        $data = [IO.File]::ReadAllText($Path) | ConvertFrom-Json
        if ($data.Version -ne 1 -or $null -eq $data.PSObject.Properties['Groups']) { throw 'Invalid card layout version.' }
        $entries = @($data.Groups)
        if ($entries.Count -ne $defaults.Count) { throw 'Card layout scope changed.' }
        $seen = @{}
        foreach ($entry in $entries) {
            if ($entry.Key -cnotin @($defaults.Key) -or $seen.ContainsKey([string]$entry.Key) -or $entry.Column -notin @(0,1) -or ($entry.Order -isnot [int] -and $entry.Order -isnot [long]) -or $entry.Order -lt 0 -or $entry.Order -gt 1024) { throw 'Invalid card layout entry.' }
            $seen[[string]$entry.Key] = $true
        }
        $result.Entries = @($entries | Sort-Object Column, Order)
    } catch { $result.Error = $_.Exception.Message }
    return $result
}
function Save-JobsPanelGroupLayout {
    param([object[]]$Entries, [string]$Path)
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $data = [ordered]@{ Version = 1; Groups = @($Entries | Select-Object Key, Column, Order) }
        [IO.File]::WriteAllText($temporary, (ConvertTo-Json $data -Depth 4), (New-Object Text.UTF8Encoding($false)))
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $Path) }
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}
# 只重排卡片记录；不改动State.Groups、Checks或任务ID顺序。
function Move-JobsPanelGroup {
    param([object[]]$Entries, [string]$Key, [int]$Column, [string]$BeforeKey = '')
    if ($Column -notin @(0,1) -or $Key -cnotin @($Entries.Key)) { throw 'Invalid card move.' }
    if ($Key -ceq $BeforeKey) { return $Entries }
    $rest = @($Entries | Where-Object { $_.Key -cne $Key })
    $destination = @($rest | Where-Object { $_.Column -eq $Column } | Sort-Object Order)
    if ($BeforeKey -and $BeforeKey -cnotin @($destination.Key)) { throw 'Invalid card destination.' }
    $keys = @()
    foreach ($entry in $destination) {
        if ($entry.Key -ceq $BeforeKey) { $keys += $Key }
        $keys += [string]$entry.Key
    }
    if (-not $BeforeKey) { $keys += $Key }
    foreach ($side in @(0,1)) {
        $sideKeys = @($rest | Where-Object { $_.Column -eq $side } | Sort-Object Order | ForEach-Object { [string]$_.Key })
        if ($side -eq $Column) { $sideKeys = $keys }
        for ($i=0; $i -lt $sideKeys.Count; $i++) { [pscustomobject]@{ Key=$sideKeys[$i]; Column=$side; Order=$i } }
    }
}
function Set-JobsPanelGroupLayout {
    param($State)
    if ($State.GroupLayoutUpdating) { return }
    $State.GroupLayoutUpdating = $true
    $panel = $State.ContentPanel
    $scroll = New-Object Drawing.Point((-$panel.AutoScrollPosition.X), (-$panel.AutoScrollPosition.Y))
    $panel.SuspendLayout()
    try {
        $panel.AutoScrollPosition = New-Object Drawing.Point(0,0)
        $gap = [int][Math]::Ceiling(12*$State.Scale)
        $available = [int][Math]::Max(1, $panel.ClientSize.Width-2*$State.Padding-[Windows.Forms.SystemInformation]::VerticalScrollBarWidth)
        $columns = 1
        if ($State.Groups.Count -gt 1 -and @($State.Groups | Where-Object { $_.IsFlutter }).Count -gt 0 -and $State.Layout.Columns -ge 2 -and $available -ge 2*$State.GroupPanelWidth+$gap) { $columns=2 }
        $State.GroupColumns = $columns
        $width = [int][Math]::Max($State.GroupPanelWidth, [Math]::Floor(($available-$gap*($columns-1))/$columns))
        $tops = @(0,0)
        foreach ($entry in @($State.GroupLayout | Sort-Object Column,Order)) {
            $group = @($State.Groups | Where-Object { $_.Key -ceq $entry.Key })[0]
            $column = 0
            if ($columns -eq 2) { $column = [int]$entry.Column }
            $group.Box.SetBounds(($State.Padding+$column*($width+$gap)), $tops[$column], $width, $group.Box.Height)
            $statusWidth = 0
            foreach ($text in @('未安装','未安装，无需卸载','已安装','等待中','正在安装 / 更新…','正在卸载…','正在清理…','✅ 安装成功','已完成','失败，见日志','未执行')) {
                $statusWidth = [Math]::Max($statusWidth,(Measure-JobsFeatureText (Get-JobsPanelText $text $State.Language) $State.Font).Width+10*$State.Scale)
            }
            $statusWidth = [int][Math]::Min($statusWidth,[Math]::Max(90*$State.Scale,$width*0.34))
            $top = [int][Math]::Max(66*$State.Scale,[Math]::Max($group.All.Bottom,$group.Counter.Bottom)+8*$State.Scale)
            foreach ($check in $group.Checks) {
                $label=$State.FeatureLabels[[string]$check.Tag]
                $label.Width=$statusWidth; $label.Left=$width-$statusWidth-[int](8*$State.Scale)
                $row=$State.FeatureRows[[string]$check.Tag]
                $columnsForRow=Get-JobsFeatureRowColumns -Left $check.Left -Width ($label.Left-$check.Left-[int](8*$State.Scale)) -Scale $State.Scale
                $height=[int][Math]::Max(34*$State.Scale,(Measure-JobsFeatureText $row.Title.Text $State.Font $columnsForRow.TitleWidth).Height+8*$State.Scale)
                $height=[int][Math]::Max($height,(Measure-JobsFeatureText $label.Text $State.Font $label.Width).Height+8*$State.Scale)
                $check.SetBounds($columnsForRow.CheckLeft,$top,$columnsForRow.CheckWidth,$height)
                $row.Icon.SetBounds($columnsForRow.IconLeft,$top,$columnsForRow.IconWidth,$height)
                $row.Title.SetBounds($columnsForRow.TitleLeft,$top,$columnsForRow.TitleWidth,$height)
                $label.Top=$top; $label.Height=$height; $top+=$height
            }
            $group.Box.Height=$top+[int](10*$State.Scale)
            $tops[$column] += $group.Box.Height+$gap
        }
        $panel.AutoScrollMinSize = New-Object Drawing.Size(($columns*$width+($columns-1)*$gap+2*$State.Padding), ([int][Math]::Max($tops[0],$tops[1])))
        $panel.AutoScrollPosition = $scroll
    } finally { $panel.ResumeLayout($true); $State.GroupLayoutUpdating=$false }
}
# 展开列表保留完整语言名称；收起时在扣除箭头的区域居中，过长文字用省略号。
function Initialize-JobsPanelCenteredChoice {
    param($Box)
    $Box.DrawMode = 'OwnerDrawFixed'
    $Box.Add_DrawItem({
        param($sender, $eventArgs)
        $eventArgs.DrawBackground()
        $text = [string]$sender.Text
        if ($eventArgs.Index -ge 0) { $text = [string]$sender.Items[$eventArgs.Index] }
        $flags = [Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [Windows.Forms.TextFormatFlags]::VerticalCenter -bor [Windows.Forms.TextFormatFlags]::SingleLine -bor [Windows.Forms.TextFormatFlags]::NoPrefix -bor [Windows.Forms.TextFormatFlags]::EndEllipsis
        [Windows.Forms.TextRenderer]::DrawText($eventArgs.Graphics, $text, $sender.Font, $eventArgs.Bounds, $eventArgs.ForeColor, $flags)
        $eventArgs.DrawFocusRectangle()
    })
}
function Get-JobsPanelGroupDrop {
    param($State, [int]$X, [int]$Y, [string]$Key)
    $column = 0
    if ($State.GroupColumns -eq 2 -and $X -ge $State.ContentPanel.ClientSize.Width/2) { $column=1 }
    # 窄屏视觉合并为一列，落点仍继承目标卡片原来的持久列。
    $candidates = @($State.GroupLayout | Sort-Object Column,Order | Where-Object { ($State.GroupColumns -eq 1 -or $_.Column -eq $column) -and $_.Key -cne $Key })
    $before = ''; $markerTop = 0
    foreach ($entry in $candidates) {
        $group = @($State.Groups | Where-Object { $_.Key -ceq $entry.Key })[0]
        $band = [int][Math]::Max(24*$State.Scale,$State.Font.Height+8*$State.Scale)
        if ($Y -le $group.Box.Top+$band/2) {
            $before=[string]$entry.Key; $column=[int]$entry.Column; $markerTop=$group.Box.Top
            break
        }
        if ($Y -le $group.Box.Top+$band) {
            $column=[int]$entry.Column; $markerTop=$group.Box.Top+$band
            $same = @($State.GroupLayout | Where-Object { $_.Column -eq $column -and $_.Key -cne $Key } | Sort-Object Order)
            $index=[array]::IndexOf(@($same.Key),[string]$entry.Key)
            if ($index+1 -lt $same.Count) { $before=[string]$same[$index+1].Key }
            return [pscustomobject]@{ Column=$column; BeforeKey=$before; MarkerTop=$markerTop }
        }
        if ($Y -lt $group.Box.Top+$group.Box.Height/2) {
            $before=[string]$entry.Key; $column=[int]$entry.Column; $markerTop=$group.Box.Top
            break
        }
        $markerTop=$group.Box.Bottom
        if ($State.GroupColumns -eq 1) { $column=[int]$entry.Column }
    }
    return [pscustomobject]@{ Column=$column; BeforeKey=$before; MarkerTop=$markerTop }
}
function Initialize-JobsPanelGroupDrag {
    param($State)
    $State.GroupLayoutPath = Get-JobsPanelGroupLayoutPath $State.PreferencesPath $State.Groups
    $saved = Read-JobsPanelGroupLayout $State.Groups $State.GroupLayoutPath
    $State.GroupLayout = @($saved.Entries)
    if ($saved.Error) { Add-JobsManagementLog $State ('Card layout: '+$saved.Error) }
    $marker = New-Object Windows.Forms.Panel
    $marker.Height = [int][Math]::Max(3,3*$State.Scale)
    $marker.Visible = $false
    $marker.Enabled = $false
    $State.ContentPanel.Controls.Add($marker)
    $State.GroupDropMarker = $marker
    $over = {
        param($sender,$eventArgs)
        $payload=[string]$eventArgs.Data.GetData('Jobs.ExtensionGroup')
        if (-not $payload.StartsWith($State.GroupDragToken+':',[StringComparison]::Ordinal)) { $eventArgs.Effect='None'; return }
        $key=$payload.Substring($State.GroupDragToken.Length+1)
        if ($key -cnotin @($State.Groups.Key)) { $eventArgs.Effect='None'; return }
        $eventArgs.Effect='Move'
        $point=$State.ContentPanel.PointToClient((New-Object Drawing.Point($eventArgs.X,$eventArgs.Y)))
        $position=-$State.ContentPanel.AutoScrollPosition.Y
        if ($point.Y -lt 28*$State.Scale) { $State.ContentPanel.AutoScrollPosition=New-Object Drawing.Point(0,([Math]::Max(0,$position-18*$State.Scale))) }
        elseif ($point.Y -gt $State.ContentPanel.ClientSize.Height-28*$State.Scale) { $State.ContentPanel.AutoScrollPosition=New-Object Drawing.Point(0,([Math]::Min([Math]::Max(0,$State.ContentPanel.VerticalScroll.Maximum-$State.ContentPanel.ClientSize.Height+1),$position+18*$State.Scale))) }
        $State.GroupDrop=Get-JobsPanelGroupDrop $State $point.X $point.Y $key
        $width=[int][Math]::Max(10,($State.ContentPanel.ClientSize.Width-2*$State.Padding-12*$State.Scale)/$State.GroupColumns)
        $State.GroupDropMarker.SetBounds(($State.Padding+$State.GroupDrop.Column*($width+12*$State.Scale)*[int]($State.GroupColumns -eq 2)), ([Math]::Max(0,[Math]::Min($State.ContentPanel.ClientSize.Height-4,$State.GroupDrop.MarkerTop))), $width, ([int][Math]::Max(3,3*$State.Scale)))
        $State.GroupDropMarker.BackColor=[Drawing.Color]::DodgerBlue
        $State.GroupDropMarker.Visible=$true
        $State.GroupDropMarker.BringToFront()
    }.GetNewClosure()
    $drop = {
        param($sender,$eventArgs)
        $payload=[string]$eventArgs.Data.GetData('Jobs.ExtensionGroup')
        if (-not $payload.StartsWith($State.GroupDragToken+':',[StringComparison]::Ordinal) -or $null -eq $State.GroupDrop) { return }
        $key=$payload.Substring($State.GroupDragToken.Length+1)
        $State.GroupLayout=@(Move-JobsPanelGroup $State.GroupLayout $key $State.GroupDrop.Column $State.GroupDrop.BeforeKey)
        $State.GroupDropMarker.Visible=$false
        Set-JobsPanelGroupLayout $State
        if (-not $State.Preview) {
            try { Save-JobsPanelGroupLayout $State.GroupLayout $State.GroupLayoutPath }
            catch { Add-JobsManagementLog $State ('Card layout: '+$_.Exception.Message) }
        }
    }.GetNewClosure()
    foreach ($control in @($State.ContentPanel)+@($State.Groups | ForEach-Object { $_.Box })) {
        $control.AllowDrop=$true
        $control.Add_DragEnter($over); $control.Add_DragOver($over); $control.Add_DragDrop($drop)
    }
    foreach ($group in $State.Groups) {
        $localGroup=$group
        $group.Box.Add_MouseDown({
            param($sender,$eventArgs)
            if ($eventArgs.Button -eq [Windows.Forms.MouseButtons]::Left -and $eventArgs.Y -le [Math]::Max(24*$State.Scale,$State.Font.Height+8*$State.Scale)) { $State.GroupDragKey=$localGroup.Key; $State.GroupDragOrigin=$eventArgs.Location }
        }.GetNewClosure())
        $group.Box.Add_MouseMove({
            param($sender,$eventArgs)
            $title=$eventArgs.Y -le [Math]::Max(24*$State.Scale,$State.Font.Height+8*$State.Scale)
            $sender.Cursor=if ($title) { [Windows.Forms.Cursors]::SizeAll } else { [Windows.Forms.Cursors]::Default }
            if ($eventArgs.Button -ne [Windows.Forms.MouseButtons]::Left -or $State.GroupDragKey -cne $localGroup.Key -or $null -eq $State.GroupDragOrigin) { return }
            if ([Math]::Abs($eventArgs.X-$State.GroupDragOrigin.X)+[Math]::Abs($eventArgs.Y-$State.GroupDragOrigin.Y) -lt 8*$State.Scale) { return }
            $data=New-Object Windows.Forms.DataObject
            $data.SetData('Jobs.ExtensionGroup',($State.GroupDragToken+':'+$localGroup.Key))
            try { [void]$sender.DoDragDrop($data,[Windows.Forms.DragDropEffects]::Move) }
            finally { $State.GroupDragKey=''; $State.GroupDragOrigin=$null; $State.GroupDrop=$null; $State.GroupDropMarker.Visible=$false }
        }.GetNewClosure())
        $group.Box.Add_MouseUp({ $State.GroupDragKey=''; $State.GroupDragOrigin=$null }.GetNewClosure())
    }
    $State.ContentPanel.Add_SizeChanged({ Set-JobsPanelGroupLayout $State }.GetNewClosure())
    Set-JobsPanelGroupLayout $State
}

# 右上工具组优先与标题同排；空间不足时右对齐换行，正文仍使用完整宽度。
function Get-JobsPanelHeaderLayout {
    param(
        [int]$Width, [int]$Padding, [double]$Scale = 1,
        [int]$TitleWidth, [int]$TitleHeight,
        [int]$ThemeLabelWidth, [int]$LanguageLabelWidth,
        [int]$ChoiceWidth, [int]$ControlHeight
    )
    $gap = [int][Math]::Ceiling(8 * $Scale)
    $labelGap = [int][Math]::Ceiling(6 * $Scale)
    $groupGap = [int][Math]::Ceiling(16 * $Scale)
    $available = $Width - 2 * $Padding
    $themeWidth = $ThemeLabelWidth + $labelGap + $ChoiceWidth
    $languageWidth = $LanguageLabelWidth + $labelGap + $ChoiceWidth
    $panelWidth = $themeWidth + $groupGap + $languageWidth
    $stacked = $panelWidth -gt $available
    $panelHeight = $ControlHeight
    $themeLeft = 0; $languageLeft = $themeWidth + $groupGap; $languageTop = 0
    if ($stacked) {
        $panelWidth = [Math]::Max($themeWidth, $languageWidth)
        if ($panelWidth -gt $available) { throw '当前窗口太窄，无法完整显示主题和语言选择。' }
        $panelHeight = 2 * $ControlHeight + $gap
        $themeLeft = $panelWidth - $themeWidth
        $languageLeft = $panelWidth - $languageWidth
        $languageTop = $ControlHeight + $gap
    }
    $inline = -not $stacked -and $TitleWidth + $groupGap + $panelWidth -le $available
    $titleTop = $Padding
    $preferenceTop = $Padding + $TitleHeight + $gap
    $titleArea = $available
    if ($inline) {
        $preferenceTop = $Padding
        $titleTop = $Padding + [int][Math]::Max(0, [Math]::Floor(($ControlHeight - $TitleHeight) / 2.0))
        $titleArea = $available - $panelWidth - $groupGap
    }
    return [pscustomobject]@{
        Inline = $inline; Stacked = $stacked
        PreferenceLeft = $Width - $Padding - $panelWidth; PreferenceTop = $preferenceTop
        PreferenceWidth = $panelWidth; PreferenceHeight = $panelHeight
        ThemeLabelLeft = $themeLeft; ThemeChoiceLeft = $themeLeft + $ThemeLabelWidth + $labelGap
        LanguageLabelLeft = $languageLeft; LanguageChoiceLeft = $languageLeft + $LanguageLabelWidth + $labelGap; LanguageTop = $languageTop
        TitleTop = $titleTop; TitleWidth = $titleArea
        DetailsTop = [Math]::Max($titleTop + $TitleHeight, $preferenceTop + $panelHeight) + $gap
    }
}
# 部署位置与自动清理复选框紧邻；独立清理按钮位于底部操作区。
function Get-JobsPanelDeploymentRowLayout {
    param(
        [int]$AvailableWidth, [double]$Scale = 1, [bool]$CleanupVisible = $true,
        [int]$RouteWidth, [int]$RouteHeight, [int]$AutoCleanupWidth, [int]$AutoCleanupHeight,
        [int]$CleanupButtonWidth, [int]$CleanupButtonHeight
    )
    $gap = [int][Math]::Ceiling(12 * $Scale)
    $sideWidth = 0
    if ($CleanupVisible) { $sideWidth = $AutoCleanupWidth }
    $actualRouteWidth = $RouteWidth
    $contentWidth = $actualRouteWidth + $sideWidth + $(if ($CleanupVisible) { $gap } else { 0 })
    $rowHeight = $RouteHeight
    if ($CleanupVisible) { $rowHeight = [int][Math]::Max($rowHeight, $AutoCleanupHeight) }
    return [pscustomobject]@{
        ContentWidth = $contentWidth; RowHeight = $rowHeight; ScrollRequired = $contentWidth -gt $AvailableWidth
        RouteWidth = $actualRouteWidth; RouteTop = [int][Math]::Floor(($rowHeight - $RouteHeight) / 2.0)
        CleanupLeft = $actualRouteWidth + $gap; CleanupWidth = $sideWidth
        AutoCleanupTop = [int][Math]::Floor(($rowHeight - $AutoCleanupHeight) / 2.0)
        CleanupButtonLeft = $AutoCleanupWidth + $gap; CleanupButtonTop = [int][Math]::Floor(($rowHeight - $CleanupButtonHeight) / 2.0)
    }
}
# 按当前语言实测完整文案，位置下拉与复选框共用垂直中心线。
function Set-JobsPanelDeploymentRowLayout {
    param($State, [int]$Top, [int]$Width)
    $scale = [double]$State.Scale
    $routeWidth = [int][Math]::Max(220 * $scale, (Measure-JobsFeatureText $State.RouteBox.Text $State.Font).Width + 32 * $scale)
    $dropDownWidth = $routeWidth
    foreach ($text in $State.RouteBox.Items) { $dropDownWidth = [int][Math]::Max($dropDownWidth, (Measure-JobsFeatureText ([string]$text) $State.Font).Width + 32 * $scale) }
    $autoWidth = [int][Math]::Ceiling((Measure-JobsFeatureText $State.AutoCleanup.Text $State.Font).Width + 26 * $scale)
    $autoHeight = [int][Math]::Max(30 * $scale, (Measure-JobsFeatureText $State.AutoCleanup.Text $State.Font).Height + 6 * $scale)
    $buttonWidth = [int][Math]::Ceiling((Measure-JobsFeatureText $State.CleanupButton.Text $State.Font).Width + 24 * $scale)
    $buttonHeight = [int][Math]::Max(32 * $scale, (Measure-JobsFeatureText $State.CleanupButton.Text $State.Font).Height + 8 * $scale)
    $cleanupVisible = $State.DeploymentMode -eq 'installed'
    $layout = Get-JobsPanelDeploymentRowLayout -AvailableWidth $Width -Scale $scale -CleanupVisible $cleanupVisible -RouteWidth $routeWidth -RouteHeight $State.RouteBox.PreferredHeight -AutoCleanupWidth $autoWidth -AutoCleanupHeight $autoHeight -CleanupButtonWidth $buttonWidth -CleanupButtonHeight $buttonHeight
    $height = $layout.RowHeight
    if ($layout.ScrollRequired) { $height += [Windows.Forms.SystemInformation]::HorizontalScrollBarHeight }
    $State.DeploymentRow.AutoScrollPosition = New-Object Drawing.Point(0, 0)
    $State.DeploymentRow.SetBounds($State.Padding, $Top, $Width, $height)
    $State.RouteBox.SetBounds(0, $layout.RouteTop, $layout.RouteWidth, $State.RouteBox.PreferredHeight)
    $State.RouteBox.DropDownWidth = $dropDownWidth
    $State.CleanupPanel.SetBounds($layout.CleanupLeft, 0, $layout.CleanupWidth, $layout.RowHeight)
    $State.AutoCleanup.SetBounds(0, $layout.AutoCleanupTop, $autoWidth, $autoHeight)
    $State.DeploymentRow.AutoScrollMinSize = New-Object Drawing.Size($layout.ContentWidth, $layout.RowHeight)
    $State.DeploymentRowLayout = $layout
}
# 字体实测决定工具组尺寸；仅调整已有控件位置，不触发操作选择变化。
function Set-JobsPanelHeaderLayout {
    param($State)
    $scale = [double]$State.Scale
    $padding = [int]$State.Padding
    $width = $State.Form.ClientSize.Width
    $themeWidth = (Measure-JobsFeatureText $State.ThemeLabel.Text $State.Font).Width
    $languageWidth = (Measure-JobsFeatureText $State.LanguageLabel.Text $State.Font).Width
    $choiceWidth = [int][Math]::Ceiling(112 * $scale)
    foreach ($box in @($State.ThemeBox, $State.LanguageBox)) {
        $dropWidth = $choiceWidth
        foreach ($text in $box.Items) { $dropWidth = [int][Math]::Max($dropWidth, (Measure-JobsFeatureText ([string]$text) $State.Font).Width + 32 * $scale) }
        $box.DropDownWidth = $dropWidth
        $State.ToolTip.SetToolTip($box, $box.Text)
        $box.ItemHeight = [int][Math]::Max(20 * $scale, $State.Font.Height + 4 * $scale)
        $box.Height = $box.PreferredHeight
    }
    # 原生下拉可能约束请求高度，布局以实际高度对齐标签。
    $controlHeight = [Math]::Max($State.ThemeBox.Height, $State.LanguageBox.Height)
    # Label 的原生内边距与字体回退纳入实测，避免通用 TextRenderer 高度裁字。
    $title = $State.HeaderLabel.GetPreferredSize([Drawing.Size]::Empty)
    $layout = Get-JobsPanelHeaderLayout -Width $width -Padding $padding -Scale $scale -TitleWidth $title.Width -TitleHeight $title.Height -ThemeLabelWidth $themeWidth -LanguageLabelWidth $languageWidth -ChoiceWidth $choiceWidth -ControlHeight $controlHeight
    $State.PreferencePanel.SetBounds($layout.PreferenceLeft, $layout.PreferenceTop, $layout.PreferenceWidth, $layout.PreferenceHeight)
    $State.ThemeLabel.SetBounds($layout.ThemeLabelLeft, 0, $themeWidth, $controlHeight)
    $State.ThemeBox.SetBounds($layout.ThemeChoiceLeft, 0, $choiceWidth, $controlHeight)
    $State.LanguageLabel.SetBounds($layout.LanguageLabelLeft, $layout.LanguageTop, $languageWidth, $controlHeight)
    $State.LanguageBox.SetBounds($layout.LanguageChoiceLeft, $layout.LanguageTop, $choiceWidth, $controlHeight)
    $wrappedTitle = $State.HeaderLabel.GetPreferredSize((New-Object Drawing.Size($layout.TitleWidth, 0)))
    if ($wrappedTitle.Height -gt $title.Height) {
        $layout = Get-JobsPanelHeaderLayout -Width $width -Padding $padding -Scale $scale -TitleWidth $title.Width -TitleHeight $wrappedTitle.Height -ThemeLabelWidth $themeWidth -LanguageLabelWidth $languageWidth -ChoiceWidth $choiceWidth -ControlHeight $controlHeight
        $State.PreferencePanel.Top = $layout.PreferenceTop
    }
    $State.HeaderLabel.SetBounds($padding, $layout.TitleTop, $layout.TitleWidth, $wrappedTitle.Height)
    $detailsWidth = $width - 2 * $padding
    $detailsHeight = $State.HeaderDetailsLabel.GetPreferredSize((New-Object Drawing.Size($detailsWidth, 0))).Height
    $State.HeaderDetailsLabel.SetBounds($padding, $layout.DetailsTop, $detailsWidth, $detailsHeight)
    $next = $State.HeaderDetailsLabel.Bottom + [int](8 * $scale)
    if ($State.OperationBox) {
        $State.OperationBox.Top = $next
        $operationWidth = 0
        foreach ($item in $State.OperationBox.Items) { $operationWidth = [Math]::Max($operationWidth, (Measure-JobsFeatureText ([string]$item) $State.Font).Width + 40 * $scale) }
        $State.OperationBox.Width = [int][Math]::Min($detailsWidth, $operationWidth)
        $State.OperationBox.DropDownWidth = [int]$operationWidth
        $next = $State.OperationBox.Bottom + [int](8 * $scale)
    }
    Set-JobsPanelDeploymentRowLayout $State -Top $next -Width $detailsWidth
    $State.PreferredHeaderHeight = $State.DeploymentRow.Bottom + [int](12 * $scale)
    $State.Header.Height = $State.PreferredHeaderHeight
    $State.LogToolbar.MaximumSize = New-Object Drawing.Size($width, 0)
    $State.LogToolbar.Size = $State.LogToolbar.GetPreferredSize((New-Object Drawing.Size($width, 0)))
    $State.HeaderTopLayout = $layout
}
# 语言切换只重排既有控件，不重建窗口、清空勾选或重启后台任务。
function Update-JobsPanelPresentation {
    param($State, [switch]$Force)
    $language = Resolve-JobsPanelLanguage $State.Preferences.Language
    $theme = Resolve-JobsPanelTheme $State.Preferences.Theme
    $contrastKey = Get-JobsPanelContrastKey
    if (-not $Force -and $State.Language -ceq $language -and $State.Theme -ceq $theme -and $null -ne $State.PSObject.Properties['ContrastKey'] -and $State.ContrastKey -ceq $contrastKey) { return }
    $State | Add-Member NoteProperty ContrastKey $contrastKey -Force
    $State.Language = $language; $State.Theme = $theme; $State.PreferenceUpdating = $true
    $State.Form.SuspendLayout()
    try {
        Set-JobsPanelLanguageFont $State $language
        foreach ($binding in $State.TextBindings) { $binding.Control.Text = Get-JobsPanelText $binding.Source $language }
        $State.ThemeLabel.Text = '🎨 ' + (Get-JobsPanelText '主题' $language)
        $State.LanguageLabel.Text = '🌐 ' + (Get-JobsPanelText '语言' $language)
        $State.ThemeBox.AccessibleName = Get-JobsPanelText '主题' $language
        $State.LanguageBox.AccessibleName = Get-JobsPanelText '语言' $language
        foreach ($binding in $State.ToolTipBindings) { $State.ToolTip.SetToolTip($binding.Control, (Get-JobsPanelText $binding.Source $language)) }
        $State.CopySelectionItem.Text = Get-JobsPanelText '复制' $language
        $State.SelectLogItem.Text = Get-JobsPanelText '全选' $language
        $State.ThemeBox.Items[0] = Get-JobsPanelText '黑夜' $language
        $State.ThemeBox.Items[1] = Get-JobsPanelText '白天' $language
        $State.ThemeBox.Items[2] = Get-JobsPanelText '跟随系统' $language
        $State.LanguageBox.Items[$script:PanelLanguageCodes.Count-1] = Get-JobsPanelText '跟随系统' $language
        if ($State.OperationBox) {
            $State.OperationBox.Items[0] = Get-JobsPanelText '安装 / 更新所选功能' $language
            $State.OperationBox.Items[1] = Get-JobsPanelText '卸载所选功能' $language
        }
        $State.RouteBox.Items[0] = Get-JobsPanelText '默认程序安装位置（推荐）' $language
        $State.RouteBox.Items[1] = Get-JobsPanelText '本地临时构建目录（移走或清理后失效）' $language
        $confirm = '安装 / 更新'
        if ($State.Operation -eq 'Uninstall') { $confirm = '卸载所选' }
        if ($State.Mode -eq 'Configure') { $confirm = '保存配置' }
        if ($State.Preview) { $confirm = '返回选择' }
        if ($State.Running -and $State.Operation -eq 'Install') { $confirm = '停止安装'; if ($State.StopRequested) { $confirm = '等待停止…' } }
        $State.ConfirmButton.Text = Get-JobsPanelText $confirm $language
        $State.CancelButton.Text = Get-JobsPanelText $State.CancelText $language
        Set-JobsPanelGroupLayout $State
        foreach ($group in $State.Groups) {
            $count = @($group.Checks | Where-Object { $_.Checked }).Count
            $group.Counter.Text = (Get-JobsPanelText '已选 {0} / {1}' $language) -f $count, $group.Checks.Count
            $groupTop = [int][Math]::Max(22*$State.Scale, $State.Font.Height+8*$State.Scale)
            foreach ($button in @($group.All, $group.None)) {
                $metrics = Measure-JobsFeatureText $button.Text $State.Font
                $button.Width = [int][Math]::Max(74*$State.Scale, $metrics.Width+16*$State.Scale)
                $button.Height = [int][Math]::Max(30*$State.Scale, $metrics.Height+10*$State.Scale)
                $button.Top = $groupTop
            }
            $group.Counter.Top = $groupTop
            $group.Counter.Height = [int][Math]::Max(26*$State.Scale, $State.Font.Height+8*$State.Scale)
            $group.None.Left = $group.All.Right + [int](6 * $State.Scale)
            $group.Counter.Left = $group.None.Right + [int](6 * $State.Scale)
            $group.Counter.Width = (Measure-JobsFeatureText ((Get-JobsPanelText '已选 {0} / {1}' $language) -f $group.Checks.Count, $group.Checks.Count) $State.Font).Width + [int](8 * $State.Scale)
            $statusWidth = 0
            foreach ($text in @('未安装', '未安装，无需卸载', '已安装', '等待中', '正在安装 / 更新…', '正在卸载…', '正在清理…', '✅ 安装成功', '已完成', '失败，见日志', '未执行')) {
                $statusWidth = [Math]::Max($statusWidth, (Measure-JobsFeatureText (Get-JobsPanelText $text $language) $State.Font).Width + 10 * $State.Scale)
            }
            $statusWidth = [int][Math]::Min($statusWidth, [Math]::Max(90*$State.Scale, $group.Box.ClientSize.Width*0.34))
            $top = [int][Math]::Max(66 * $State.Scale, [Math]::Max($group.All.Bottom, $group.Counter.Bottom) + 8 * $State.Scale)
            foreach ($check in $group.Checks) {
                $label = $State.FeatureLabels[[string]$check.Tag]
                $source = $(if ([string]$check.Tag -in $State.Installed) { '已安装' } else { '未安装' })
                if ($State.FeatureStatusSources.ContainsKey([string]$check.Tag)) { $source = $State.FeatureStatusSources[[string]$check.Tag] }
                $label.Text = Get-JobsPanelText $source $language
                if ($State.FeatureMessages.ContainsKey([string]$check.Tag)) { Set-JobsPanelFeatureToolTip $State ([string]$check.Tag) $State.FeatureMessages[[string]$check.Tag] }
                if ($State.FeatureStates.ContainsKey([string]$check.Tag) -and $State.FeatureStates[[string]$check.Tag] -eq 'Failed') { $label.LinkArea = New-Object Windows.Forms.LinkArea(0, $label.Text.Length) }
                $label.Width = $statusWidth; $label.Left = $group.Box.ClientSize.Width - $statusWidth - [int](8 * $State.Scale)
                $row = $State.FeatureRows[[string]$check.Tag]
                $parts = Split-JobsFeatureLabel (Get-JobsPanelText $row.Source $language)
                $row.Icon.Text = $parts.Icon; $row.Title.Text = $parts.Title; $check.AccessibleName = $parts.Title
                $columns = Get-JobsFeatureRowColumns -Left $check.Left -Width ($label.Left-$check.Left-[int](8*$State.Scale)) -Scale $State.Scale
                $height = [int][Math]::Max(34 * $State.Scale, (Measure-JobsFeatureText $row.Title.Text $State.Font $columns.TitleWidth).Height + 8 * $State.Scale)
                $height = [int][Math]::Max($height, (Measure-JobsFeatureText $label.Text $State.Font $label.Width).Height + 8 * $State.Scale)
                $check.SetBounds($columns.CheckLeft, $top, $columns.CheckWidth, $height)
                $row.Icon.SetBounds($columns.IconLeft, $top, $columns.IconWidth, $height)
                $row.Title.SetBounds($columns.TitleLeft, $top, $columns.TitleWidth, $height)
                $label.Top = $top; $label.Height = $height; $top += $height
            }
            $group.Box.Height = $top + [int](10 * $State.Scale)
        }
        foreach ($button in @($State.SelectAllButton, $State.ClearButton, $State.ConfirmButton, $State.CancelButton)) {
            $button.Width = [int][Math]::Max(104 * $State.Scale, (Measure-JobsFeatureText $button.Text $State.Font).Width + 24 * $State.Scale)
        }
        Set-JobsPanelGroupLayout $State
        Set-JobsPanelHeaderLayout $State
        Set-JobsFeatureStatusText $State $State.StatusSource
        Set-JobsPanelControlTheme $State.Form $State
        $State.LogMenu.BackColor = $State.Form.BackColor; $State.LogMenu.ForeColor = $State.Form.ForeColor
        foreach ($item in $State.LogMenu.Items) { $item.BackColor = $State.Form.BackColor; $item.ForeColor = $State.Form.ForeColor }
        # 日志由独立明暗palette逐段重着色，递归改色时保留选区与原生视口。
        if ($State.Form.IsHandleCreated) {
            try { $value = [int]($theme -eq 'dark'); [void][JobsPanelNative]::DwmSetWindowAttribute($State.Form.Handle, 20, [ref]$value, 4) } catch { }
        }
        $State.LogSplit.AccessibleName = Get-JobsPanelText '功能与日志分隔条' $language
        $State.LogSplit.AccessibleDescription = Get-JobsPanelText '上下拖动调节日志高度' $language
    } finally { $State.Form.ResumeLayout($true); $State.PreferenceUpdating = $false }
}

function Get-JobsFeatureSelectionLayout {
    param(
        [ValidateRange(1, 1000)][int]$ItemCount,
        [int]$WorkingWidth,
        [int]$WorkingHeight,
        [ValidateRange(1, 1000)][int]$RowHeight = 34,
        [ValidateRange(0.5, 4.0)][double]$Scale = 1
    )
    $maxHeight = $WorkingHeight - [int][Math]::Ceiling(80 * $Scale)
    $maxExpandedHeight = $WorkingHeight - [int][Math]::Ceiling(44 * $Scale)
    $columns = 0
    $width = 0
    $rows = 0
    $height = 0
    $header = 0
    $footer = 0
    foreach ($candidateColumns in @(1, 2, 3)) {
        $candidateHeader = [int][Math]::Ceiling(118 * $Scale)
        $candidateFooter = [int][Math]::Ceiling(104 * $Scale)
        $candidateRows = [int][Math]::Ceiling($ItemCount / [double]$candidateColumns)
        $candidateHeight = $candidateRows * $RowHeight + $candidateHeader + $candidateFooter
        $limit = $maxHeight
        if ($candidateColumns -gt 1 -and $candidateHeight -gt $maxHeight) {
            $candidateHeader = [int][Math]::Ceiling(96 * $Scale)
            $candidateFooter = [int][Math]::Ceiling(92 * $Scale)
            $candidateHeight = $candidateRows * $RowHeight + $candidateHeader + $candidateFooter
            if ($candidateHeight -gt $maxHeight) { $limit = $maxExpandedHeight }
        }
        $preferredWidth = 680
        $minimumWidth = 500
        if ($candidateColumns -eq 2) { $preferredWidth = 1020; $minimumWidth = 720 }
        if ($candidateColumns -eq 3) { $preferredWidth = 1320; $minimumWidth = 1080 }
        $candidateWidth = [int][Math]::Min([Math]::Ceiling($preferredWidth * $Scale), $WorkingWidth - [Math]::Ceiling(48 * $Scale))
        if ($candidateHeight -gt $limit -or $candidateWidth -lt $minimumWidth * $Scale) { continue }
        $columns = $candidateColumns
        $rows = $candidateRows
        $height = $candidateHeight
        $width = $candidateWidth
        $header = $candidateHeader
        $footer = $candidateFooter
        break
    }
    if ($columns -eq 0) {
        if ($WorkingWidth -lt 500 * $Scale -or $WorkingHeight -lt 360 * $Scale) {
            throw '当前桌面工作区过小，无法显示固定操作按钮；请降低显示缩放或提高屏幕分辨率后重试。'
        }
        $columns = 1
        if ($WorkingWidth -ge 900 * $Scale) { $columns = 2 }
        $rows = [int][Math]::Ceiling($ItemCount / [double]$columns)
        $width = [int][Math]::Min(1020 * $Scale, $WorkingWidth - 48 * $Scale)
        $height = $maxHeight
        $header = [int][Math]::Ceiling(118 * $Scale)
        $footer = [int][Math]::Ceiling(104 * $Scale)
    }
    return [pscustomobject]@{
        Columns = $columns; Rows = $rows; ClientWidth = $width; ClientHeight = $height
        RowHeight = $RowHeight; HeaderHeight = $header; FooterHeight = $footer
    }
}

function Get-JobsFeatureContentLayout {
    param(
        [int]$WorkingWidth,
        [ValidateRange(1, 3)][int]$PreferredColumns = 1,
        [int]$MinimumPanelWidth = 500,
        [int]$MinimumCheckWidth = 120,
        [int]$StatusWidth = 120,
        [int]$GroupControlsWidth = 260,
        [ValidateRange(0.5, 4.0)][double]$Scale = 1
    )
    $padding = [int][Math]::Ceiling(20 * $Scale)
    $gap = [int][Math]::Ceiling(8 * $Scale)
    $scrollbar = [int][Math]::Ceiling(24 * $Scale)
    $rowPadding = [int][Math]::Ceiling(28 * $Scale)
    $availableWidth = $WorkingWidth - [int][Math]::Ceiling(48 * $Scale)
    $requiredPanel = [Math]::Max($MinimumPanelWidth, [Math]::Max($GroupControlsWidth, $MinimumCheckWidth + $StatusWidth + $rowPadding))
    for ($columns = $PreferredColumns; $columns -ge 1; $columns--) {
        $preferredWidth = @(0, 680, 1020, 1320)[$columns] * $Scale
        $requiredWidth = $columns * ($requiredPanel + $gap) + 2 * $padding + $scrollbar
        $width = [int][Math]::Min($availableWidth, [Math]::Max($preferredWidth, $requiredWidth))
        $panelWidth = [int][Math]::Floor(($width - 2 * $padding - $scrollbar) / [double]$columns) - $gap
        if ($panelWidth -ge $requiredPanel) {
            return [pscustomobject]@{ Columns = $columns; ClientWidth = $width; PanelWidth = $panelWidth; CheckWidth = $panelWidth - $StatusWidth - $rowPadding; StatusWidth = $StatusWidth; Wrapped = $false }
        }
    }
    $panelWidth = $availableWidth - 2 * $padding - $scrollbar - $gap
    if ($panelWidth -lt [Math]::Max($GroupControlsWidth, $MinimumCheckWidth + $StatusWidth + $rowPadding)) {
        throw '当前工作区太窄，无法完整显示选择按钮、计数和状态；请降低缩放或提高分辨率。'
    }
    return [pscustomobject]@{ Columns = 1; ClientWidth = $availableWidth; PanelWidth = $panelWidth; CheckWidth = $panelWidth - $StatusWidth - $rowPadding; StatusWidth = $StatusWidth; Wrapped = $true }
}

# 留出固定操作按钮、至少一行功能和可读日志，再约束拖动范围。
function Get-JobsManagementLogLayout {
    param(
        [int]$Height,
        [int]$FooterHeight,
        [int]$ToolbarHeight,
        [int]$RowHeight,
        [int]$SplitterWidth,
        [int]$LogHeight,
        [ValidateRange(0.5, 4.0)][double]$Scale = 1
    )
    $upperMinimum = $FooterHeight + $RowHeight
    $lowerMinimum = $ToolbarHeight + [int][Math]::Ceiling(60 * $Scale)
    $available = $Height - $SplitterWidth
    if ($upperMinimum + $lowerMinimum -gt $available) {
        throw '当前窗口高度不足以同时显示操作按钮和日志，请提高分辨率或降低缩放。'
    }
    $lowerHeight = [int][Math]::Min($available - $upperMinimum, [Math]::Max($lowerMinimum, $LogHeight))
    return [pscustomobject]@{
        UpperMinimum = $upperMinimum; LowerMinimum = $lowerMinimum
        Distance = $available - $lowerHeight; LogHeight = $lowerHeight
    }
}

function Set-JobsManagementLogLayout {
    param($State)
    if ($null -eq $State.PSObject.Properties['LogSplit']) { return }
    $split = $State.LogSplit
    $layout = Get-JobsManagementLogLayout -Height $split.ClientSize.Height -FooterHeight $State.Footer.Height -ToolbarHeight $State.LogToolbar.Height -RowHeight $State.Layout.RowHeight -SplitterWidth $split.SplitterWidth -LogHeight $split.Panel2.Height -Scale $State.Scale
    $split.SuspendLayout()
    try {
        $split.Panel1MinSize = 0
        $split.Panel2MinSize = 0
        $split.SplitterDistance = $layout.Distance
        $split.Panel1MinSize = $layout.UpperMinimum
        $split.Panel2MinSize = $layout.LowerMinimum
    } finally { $split.ResumeLayout() }
}

function Measure-JobsFeatureText {
    param([string]$Text, [object]$Font, [int]$Width = 0)
    $flags = [Windows.Forms.TextFormatFlags]::NoPrefix -bor [Windows.Forms.TextFormatFlags]::TextBoxControl
    if ($Width -gt 0) {
        $flags = $flags -bor [Windows.Forms.TextFormatFlags]::WordBreak
        $size = New-Object Drawing.Size($Width, [int]::MaxValue)
    } else {
        $flags = $flags -bor [Windows.Forms.TextFormatFlags]::SingleLine
        $size = New-Object Drawing.Size([int]::MaxValue, [int]::MaxValue)
    }
    return [Windows.Forms.TextRenderer]::MeasureText($Text, $Font, $size, $flags)
}

# 动态状态按当前宽度换行，操作按钮始终位于完整说明下方。
function Set-JobsFeatureStatusText {
    param([object]$State, [string]$Text)
    if ($null -ne $State.PSObject.Properties['StatusSource']) { $State.StatusSource = $Text }
    $State.StatusLabel.Text = Get-JobsPanelText $Text (Get-JobsPanelLanguage $State)
    if ($null -eq $State.PSObject.Properties['Padding']) { return }
    $padding = [int]$State.Padding
    $scale = [double]$State.Scale
    $width = $State.Form.ClientSize.Width - 2 * $padding
    $preferred = $State.StatusLabel.GetPreferredSize((New-Object Drawing.Size($width, 0)))
    $height = [int][Math]::Max(26 * $scale, $preferred.Height)
    $State.StatusLabel.SetBounds($padding, ([int](10 * $scale)), $width, $height)
    $State.Progress.SetBounds($padding, ($State.StatusLabel.Bottom + [int](5 * $scale)), $width, ([int](6 * $scale)))
    $buttonsTop = $State.Progress.Bottom + [int](6 * $scale)
    $gap = [int](10 * $scale)
    $buttons = @($State.SelectAllButton, $State.ClearButton, $State.ConfirmButton, $State.CancelButton)
    foreach ($button in $buttons) {
        $metrics = Measure-JobsFeatureText $button.Text $State.Font
        $button.Width = [int][Math]::Max(104*$scale, $metrics.Width+24*$scale)
        $button.Height = [int][Math]::Max(34*$scale, $metrics.Height+12*$scale)
        $button.Top = $buttonsTop
    }
    $State.SelectAllButton.Left = $padding
    $State.ClearButton.Left = $State.SelectAllButton.Right + $gap
    $cleanup = $State.CleanupButton
    $cleanupVisible = $State.DeploymentMode -eq 'installed'
    $cleanup.Visible = $cleanupVisible
    $cleanup.Width = [int][Math]::Max(104*$scale, (Measure-JobsFeatureText $cleanup.Text $State.Font).Width + 24*$scale)
    $cleanup.Height = [int][Math]::Max(34*$scale, (Measure-JobsFeatureText $cleanup.Text $State.Font).Height + 12*$scale)
    $actions = @($State.CancelButton, $State.ConfirmButton)
    if ($cleanupVisible) { $actions += $cleanup }
    $clusterWidth = ($actions | Measure-Object -Property Width -Sum).Sum + $gap*($actions.Count-1)
    $left = [int][Math]::Max($padding, $State.Form.ClientSize.Width-$padding-$clusterWidth)
    $top = $buttonsTop
    if ($State.ClearButton.Right+$gap -gt $left) { $top = [Math]::Max($State.ClearButton.Bottom, $State.SelectAllButton.Bottom)+$gap }
    $bottom = $top
    foreach ($button in $actions) {
        if ($left+$button.Width -gt $State.Form.ClientSize.Width-$padding -and $left -gt $padding) { $left=$padding; $top=$bottom+$gap }
        $button.Left=$left; $button.Top=$top; $left=$button.Right+$gap
        $bottom=[Math]::Max($bottom, $button.Bottom)
    }
    $State.Footer.Height = $bottom + [int](20 * $scale)
    $State.Layout.FooterHeight = $State.Footer.Height
    if ($null -ne $State.PSObject.Properties['PreferredHeaderHeight']) {
        $maximumHeader = $State.Form.ClientSize.Height - $State.Footer.Height - $State.Layout.RowHeight - $State.LogToolbar.Height - [int](60 * $scale) - $State.LogSplit.SplitterWidth
        $State.Header.AutoScroll = $State.PreferredHeaderHeight -gt $maximumHeader
        $State.Header.Height = [int][Math]::Min($State.PreferredHeaderHeight, [Math]::Max(48 * $scale, $maximumHeader))
        $State.Form.PerformLayout()
    }
    Set-JobsManagementLogLayout $State
}

# 成功、无需卸载和失败均计已处理；无需卸载单独统计，未执行不计进度。
function Get-JobsManagementProgress {
    param($State)
    $succeeded = @($State.FeatureStates.Values | Where-Object { $_ -ceq 'Succeeded' }).Count
    $notInstalled = @($State.FeatureStates.Values | Where-Object { $_ -ceq 'NotInstalled' }).Count
    $failed = @($State.FeatureStates.Values | Where-Object { $_ -ceq 'Failed' }).Count
    $skipped = @($State.FeatureStates.Values | Where-Object { $_ -ceq 'Skipped' }).Count
    $finished = $succeeded + $notInstalled + $failed
    $total = $State.FeatureStates.Count
    $percent = 0.0
    if ($total -gt 0) { $percent = 100.0 * $finished / $total }
    return [pscustomobject]@{ Finished = $finished; Total = $total; Succeeded = $succeeded; NotInstalled = $notInstalled; Failed = $failed; Skipped = $skipped; Percent = $percent.ToString('F1', [Globalization.CultureInfo]::InvariantCulture) }
}

# 小时累计不按天回卷，计时来源由 Stopwatch 保持单调。
function Format-JobsManagementElapsedTime {
    param([TimeSpan]$Elapsed)
    $seconds = [long][Math]::Floor([Math]::Max(0, $Elapsed.TotalSeconds))
    return '{0:00}:{1:00}:{2:00}' -f [long][Math]::Floor($seconds / 3600.0), [long][Math]::Floor(($seconds % 3600) / 60.0), ($seconds % 60)
}

# 安装和卸载各自保有计时状态，切换操作只选择对应时钟。
function Get-JobsManagementClock {
    param($State)
    if ($State.Operation -eq 'Cleanup' -and $State.RunClocks.ContainsKey('Cleanup')) { return $State.RunClocks.Cleanup }
    if ($State.Operation -eq 'Uninstall') { return $State.RunClocks.Uninstall }
    return $State.RunClocks.Install
}

# 无新输出时也刷新耗时，只在显示值变化时重排底栏。
function Update-JobsManagementProgress {
    param($State)
    $progress = Get-JobsManagementProgress $State
    $State.Progress.Value = [Math]::Min($progress.Finished, $State.Progress.Maximum)
    $action = '安装 / 更新'
    $clockLabel = '安装用时'
    if ($State.Operation -eq 'Uninstall') { $action = '卸载'; $clockLabel = '卸载用时' }
    if ($State.Operation -eq 'Cleanup') { $action = '清理'; $clockLabel = '清理用时' }
    $clock = Get-JobsManagementClock $State
    $text = '{0}中；已处理 {1} / {2} 项（{3}%，按完成项计数）；{4} {5}' -f $action, $progress.Finished, $progress.Total, $progress.Percent, $clockLabel, (Format-JobsManagementElapsedTime $clock.Elapsed)
    if ($null -ne $State.PSObject.Properties['StopRequested'] -and $State.StopRequested) { $text = '已请求停止安装；等待当前包事务结束，后续项目不再执行。 ' + $text }
    if ($State.StatusLabel.Text -cne (Get-JobsPanelText $text (Get-JobsPanelLanguage $State))) { Set-JobsFeatureStatusText $State $text }
}

# 把现有首个图形字素与名称分开，缺少图标时只保留空图标列。
function Split-JobsFeatureLabel {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return [pscustomobject]@{ Icon=''; Title='' } }
    $category = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($Text, 0)
    if ($category -notin @([Globalization.UnicodeCategory]::OtherSymbol, [Globalization.UnicodeCategory]::ModifierSymbol, [Globalization.UnicodeCategory]::MathSymbol)) { return [pscustomobject]@{ Icon=''; Title=$Text } }
    $icon = [Globalization.StringInfo]::GetNextTextElement($Text)
    return [pscustomobject]@{ Icon=$icon; Title=$Text.Substring($icon.Length).TrimStart() }
}

function Get-JobsFeatureRowColumns {
    param([int]$Left, [int]$Width, [double]$Scale=1)
    $checkWidth = [int][Math]::Ceiling(26 * $Scale)
    $iconWidth = [int][Math]::Ceiling(32 * $Scale)
    $gap = [int][Math]::Ceiling(6 * $Scale)
    $iconLeft = $Left + $checkWidth
    $titleLeft = $iconLeft + $iconWidth + $gap
    return [pscustomobject]@{ CheckLeft=$Left; CheckWidth=$checkWidth; IconLeft=$iconLeft; IconWidth=$iconWidth; TitleLeft=$titleLeft; TitleWidth=[Math]::Max(1,$Width-($titleLeft-$Left)) }
}

# 切换操作只改变可执行范围，原勾选始终保留；未安装项不能进入卸载计划。
function Set-JobsPanelOperation {
    param($State, [ValidateSet('Install','Uninstall')][string]$Operation)
    $State.Operation = $Operation
    $text = if ($Operation -eq 'Uninstall') { '卸载所选' } else { '安装 / 更新' }
    if ($State.Preview) { $text = '返回选择' }
    $State.ConfirmButton.Text = Get-JobsPanelText $text (Get-JobsPanelLanguage $State)
    foreach ($check in $State.Checks) { $check.Enabled = $Operation -ne 'Uninstall' -or [string]$check.Tag -in $State.Installed }
}

function Get-JobsPanelActiveSelection {
    param($State)
    return @($State.Checks | Where-Object { $_.Checked -and $_.Enabled } | ForEach-Object { [string]$_.Tag })
}

# Running包含安装、卸载和清理；已完成后的Started不是后台任务。输出未排空时仍保全句柄。
function Test-JobsPanelWorkActive {
    param($State)
    if ($State.Running) { return $true }
    if ($null -ne $State.PSObject.Properties['Pump'] -and $null -ne $State.Pump) {
        try { return (-not $State.Pump.Process.HasExited -or -not $State.Pump.Drained -or -not $State.Pump.Lines.IsEmpty) }
        catch { return $true }
    }
    return $false
}
# 旧版NotifyIcon限63个UTF16字符，截断保留完整代理对；完整状态留在菜单提示和原窗口。
function Get-JobsPanelTrayText {
    param([string]$Text, [int]$Maximum = 63)
    $value = [regex]::Replace($Text, '[\r\n\t]+', ' ')
    if ($value.Length -le $Maximum) { return $value }
    $length = $Maximum - 1
    if ($length -gt 0 -and [char]::IsHighSurrogate($value[$length - 1])) { $length-- }
    return $value.Substring(0, [Math]::Max(0, $length)) + '…'
}
# 托盘只显示当前状态；不启动、停止或重排任何后台计划。
function Update-JobsPanelTray {
    param($State)
    if ($null -eq $State.PSObject.Properties['TrayIcon'] -or $null -eq $State.TrayIcon -or $State.TrayDisposed) { return }
    $language = Get-JobsPanelLanguage $State
    $status = [string]$State.StatusLabel.Text
    $State.TrayRestore.Text = Get-JobsPanelText '显示管理面板' $language
    $State.TrayExit.Text = Get-JobsPanelText '完全退出' $language
    $State.TrayStatus.Text = ((Get-JobsPanelText '当前状态' $language) + ': ' + (Get-JobsPanelTrayText $status 160)).Replace('&','&&')
    $State.TrayStatus.ToolTipText = $status
    $busy = Test-JobsPanelWorkActive $State
    $State.TrayExit.Enabled = -not $busy
    $State.TrayExit.ToolTipText = ''
    if ($busy) { $State.TrayExit.ToolTipText = Get-JobsPanelText '任务进行中，暂时不能完全退出；可恢复窗口查看日志。' $language }
    $State.TrayIcon.Text = Get-JobsPanelTrayText ((Get-JobsPanelText '自定义Explorer右键菜单' $language) + ' — ' + $status)
    $State.TrayMenu.BackColor = $State.Form.BackColor
    $State.TrayMenu.ForeColor = $State.Form.ForeColor
    foreach ($item in @($State.TrayRestore, $State.TrayStatus, $State.TrayExit)) { $item.BackColor = $State.Form.BackColor; $item.ForeColor = $State.Form.ForeColor }
}
# 复用当前窗口的应用图标；事件显式回到所属模块，避免GetNewClosure丢失私有函数。
function Initialize-JobsPanelTray {
    param($State)
    $panelModule = $ExecutionContext.SessionState.Module
    $menu = New-Object Windows.Forms.ContextMenuStrip
    $icon = New-Object Windows.Forms.NotifyIcon
    $ownedIcon = $null
    try {
        $ownedIcon = $State.Form.Icon.Clone()
        $icon.Icon = $ownedIcon
        $restore = New-Object Windows.Forms.ToolStripMenuItem
        $status = New-Object Windows.Forms.ToolStripMenuItem
        $status.Enabled = $false
        $exit = New-Object Windows.Forms.ToolStripMenuItem
        $menu.ShowItemToolTips = $true
        [void]$menu.Items.Add($restore); [void]$menu.Items.Add($status); [void]$menu.Items.Add($exit)
        $icon.ContextMenuStrip = $menu
        $State.TrayIcon = $icon; $State.TrayMenu = $menu; $State.TrayRestore = $restore; $State.TrayStatus = $status; $State.TrayExit = $exit; $State.TrayOwnedIcon = $ownedIcon
        $restore.Add_Click({ & $panelModule { param($s) Show-JobsPanelFromTray $s } $State }.GetNewClosure())
        $exit.Add_Click({ & $panelModule { param($s) Request-JobsPanelClose $s -Exit } $State }.GetNewClosure())
        $icon.Add_MouseDoubleClick({ param($sender,$e) if ($e.Button -eq [Windows.Forms.MouseButtons]::Left) { & $panelModule { param($s) Show-JobsPanelFromTray $s } $State } }.GetNewClosure())
        $menu.Add_Opening({ & $panelModule { param($s) Update-JobsPanelTray $s } $State }.GetNewClosure())
        Update-JobsPanelTray $State
    } catch {
        $icon.Dispose(); $menu.Dispose()
        if ($null -ne $ownedIcon) { $ownedIcon.Dispose() }
        $State.TrayIcon = $null; $State.TrayMenu = $null; $State.TrayOwnedIcon = $null
        $State.TrayError = $_.Exception.Message
    }
}
# 隐藏只改变窗口与托盘可见性；Timer、输出泵和后台工作进程继续运行。
function Hide-JobsPanelToTray {
    param($State)
    try {
        if ($null -eq $State.TrayIcon -or $State.TrayDisposed) { throw 'NotifyIcon unavailable' }
        Update-JobsPanelTray $State
        $State.TrayIcon.Visible = $true
        if (-not $State.TrayHidden) { $State.TrayWindowState = [string]$State.Form.WindowState }
        $State.Form.ShowInTaskbar = $false
        $State.Form.Hide()
        $State.TrayHidden = $true
        return $true
    } catch {
        $State.TrayError = $_.Exception.Message
        $State.Form.ShowInTaskbar = $true
        $State.Form.Show()
        $State.TrayHidden = $false
        Set-JobsFeatureStatusText $State '无法显示系统托盘，窗口保持打开。'
        return $false
    }
}
# 恢复原窗口及其选区/勾选/日志，不重新构造管理器或执行计划。
function Show-JobsPanelFromTray {
    param($State)
    if ($State.Form.IsDisposed) { return }
    $State.Form.ShowInTaskbar = $true
    $State.Form.Show()
    $State.Form.WindowState = $(if ($State.TrayWindowState -eq 'Maximized') { 'Maximized' } else { 'Normal' })
    $State.Form.Activate()
    $State.Form.BringToFront()
    $State.TrayHidden = $false
    Update-JobsPanelTray $State
}
# 关闭选择框继承主面板主题/语言，系统跟随变化由自己的短周期UI计时器同步。
function Update-JobsPanelCloseChoice {
    param($Choice, $State)
    $language = Get-JobsPanelLanguage $State
    if ($null -eq $Choice.Font -or $Choice.Font.Name -cne $State.Font.Name -or $Choice.Font.SizeInPoints -ne $State.Font.SizeInPoints) {
        $previous = $Choice.Font
        $Choice.Font = $State.Font.Clone()
        $Choice.Form.Font = $Choice.Font
        if ($null -ne $previous) { $previous.Dispose() }
    }
    $Choice.Form.Text = Get-JobsPanelText '关闭管理面板' $language
    $Choice.Label.Text = Get-JobsPanelText '面板空闲。请选择退到系统托盘继续保留窗口，或完全退出。' $language
    $Choice.Tray.Text = Get-JobsPanelText '退到系统托盘' $language
    $Choice.Exit.Text = Get-JobsPanelText '完全退出' $language
    $Choice.Keep.Text = Get-JobsPanelText '保留窗口' $language
    Set-JobsPanelControlTheme $Choice.Form $State
}
# 默认回车进入托盘，Esc/关闭选择框保留原窗；只有明确退出才结束会话。
function Show-JobsPanelCloseChoice {
    param($State)
    $dialog = New-Object Windows.Forms.Form
    $timer = New-Object Windows.Forms.Timer
    $panelModule = $ExecutionContext.SessionState.Module
    $choice = $null
    try {
        $dialog.StartPosition = 'CenterParent'; $dialog.FormBorderStyle = 'FixedDialog'; $dialog.AutoScaleMode = 'None'
        $dialog.MaximizeBox = $false; $dialog.MinimizeBox = $false; $dialog.ShowInTaskbar = $false
        $dialog.Icon = $State.Form.Icon
        $dialog.AutoSize = $true; $dialog.AutoSizeMode = 'GrowAndShrink'
        $layout = New-Object Windows.Forms.FlowLayoutPanel
        $layout.FlowDirection = 'TopDown'; $layout.WrapContents = $false; $layout.AutoSize = $true; $layout.AutoSizeMode = 'GrowAndShrink'; $layout.Dock = 'Fill'
        $layout.Padding = New-Object Windows.Forms.Padding(20)
        $label = New-Object Windows.Forms.Label
        $label.AutoSize = $true; $label.MaximumSize = New-Object Drawing.Size([int](480*$State.Scale),0)
        $buttons = New-Object Windows.Forms.FlowLayoutPanel
        $buttons.AutoSize = $true; $buttons.AutoSizeMode = 'GrowAndShrink'; $buttons.WrapContents = $true; $buttons.MaximumSize = New-Object Drawing.Size([int](500*$State.Scale),0)
        $tray = New-Object Windows.Forms.Button; $exit = New-Object Windows.Forms.Button; $keep = New-Object Windows.Forms.Button
        foreach ($button in @($tray,$exit,$keep)) { $button.AutoSize = $true; $button.Padding = New-Object Windows.Forms.Padding(10,6,10,6); [void]$buttons.Controls.Add($button) }
        $tray.DialogResult = [Windows.Forms.DialogResult]::Yes
        $exit.DialogResult = [Windows.Forms.DialogResult]::No
        $keep.DialogResult = [Windows.Forms.DialogResult]::Cancel
        $dialog.AcceptButton = $tray; $dialog.CancelButton = $keep
        [void]$layout.Controls.Add($label); [void]$layout.Controls.Add($buttons); [void]$dialog.Controls.Add($layout)
        $choice = [pscustomobject]@{Form=$dialog;Label=$label;Tray=$tray;Exit=$exit;Keep=$keep;Font=$null}
        Update-JobsPanelCloseChoice $choice $State
        $timer.Interval = 1000
        $timer.Add_Tick({ & $panelModule { param($c,$s) Update-JobsPanelCloseChoice $c $s } $choice $State }.GetNewClosure())
        $timer.Start()
        $result = $dialog.ShowDialog($State.Form)
        if ($result -eq [Windows.Forms.DialogResult]::Yes) { return 'Tray' }
        if ($result -eq [Windows.Forms.DialogResult]::No) { return 'Exit' }
        return 'Cancel'
    } finally { $timer.Stop(); $timer.Dispose(); $dialog.Dispose(); if ($null -ne $choice -and $null -ne $choice.Font) { $choice.Font.Dispose() } }
}
# 红X、Escape/关闭按钮和托盘退出共用此门禁；忙碌优先于任何退出标记。
function Request-JobsPanelClose {
    param($State, $EventArgs = $null, [switch]$Exit)
    if ($null -ne $EventArgs) { $EventArgs.Cancel = $true }
    if (Test-JobsPanelWorkActive $State) {
        $State.ExitRequested = $false
        $State.Form.DialogResult = 'None'
        [void](Hide-JobsPanelToTray $State)
        return
    }
    if ($Exit -or $State.ExitRequested -or $State.SelectionAccepted) {
        $State.ExitRequested = $true
        if (-not $State.SelectionAccepted) { $State.Form.DialogResult = 'Cancel' }
        if ($null -ne $EventArgs) { $EventArgs.Cancel = $false }
        else { $State.Form.Close() }
        return
    }
    if ($State.ClosePromptOpen) { return }
    $State.ClosePromptOpen = $true
    try { $choice = Show-JobsPanelCloseChoice $State }
    finally { $State.ClosePromptOpen = $false }
    # 模态选择框期间仍有消息循环，执行退出前再检查后台状态。
    if (Test-JobsPanelWorkActive $State) { $State.Form.DialogResult = 'None'; [void](Hide-JobsPanelToTray $State); return }
    if ($choice -eq 'Exit') {
        $State.ExitRequested = $true
        if (-not $State.SelectionAccepted) { $State.Form.DialogResult = 'Cancel' }
        if ($null -ne $EventArgs) { $EventArgs.Cancel = $false }
        else { $State.Form.Close() }
    } else {
        $State.Form.DialogResult = 'None'
        if ($choice -eq 'Tray') { [void](Hide-JobsPanelToTray $State) }
    }
}
# 只在真实窗口释放时移除通知图标；重复释放安全，图标克隆归本窗口所有。
function Stop-JobsPanelTray {
    param($State)
    if ($null -eq $State.PSObject.Properties['TrayDisposed'] -or $State.TrayDisposed) { return }
    $State.TrayDisposed = $true
    foreach ($name in @('TrayIcon','TrayMenu','TrayOwnedIcon')) {
        $resource = $State.PSObject.Properties[$name].Value
        $State.PSObject.Properties[$name].Value = $null
        if ($null -eq $resource) { continue }
        try {
            try { if ($name -eq 'TrayIcon') { $resource.Visible = $false } }
            finally { $resource.Dispose() }
        } catch { $State.TrayError = $_.Exception.Message }
    }
}

# 控件均为GroupBox直接子项；按当前边界命中真实功能行，排除组头/组尾和独立动作。
function Get-JobsFeatureRowHit {
    param($State, $Group, $Source, $EventArgs)
    $x = [int]$EventArgs.X; $y = [int]$EventArgs.Y
    if (-not [object]::ReferenceEquals($Source, $Group.Box)) { $x += $Source.Left; $y += $Source.Top }
    if ($x -lt 0 -or $x -ge $Group.Box.ClientSize.Width) { return $null }
    foreach ($check in $Group.Checks) {
        if ($y -lt $check.Top -or $y -ge $check.Bottom) { continue }
        $id = [string]$check.Tag
        $row = $State.FeatureRows[$id]
        $status = $State.FeatureLabels[$id]
        $ordinary = @($row.Icon, $row.Title, $status)
        if (-not [object]::ReferenceEquals($Source, $Group.Box) -and $Source -notin $ordinary) { return $null }
        $child = $Group.Box.GetChildAtPoint((New-Object Drawing.Point($x,$y)))
        if ($null -ne $child -and $child -notin $ordinary) { return $null }
        if (($Source -eq $status -or $child -eq $status) -and $status.LinkArea.Length -gt 0) { return $null }
        return [pscustomobject]@{ Id=$id; Row=$row; X=$x; Y=$y }
    }
    return $null
}
# 只记住一次左键按下；原生CheckBox不经此通道，不改其AutoCheck/Tab/Space事件。
function Start-JobsFeatureRowPointer {
    param($State, $Group, $Source, $EventArgs)
    $State.FeatureRowPress = $null
    if ([string]$EventArgs.Button -cne 'Left' -or (Test-JobsPanelWorkActive $State) -or $State.GroupDragKey) { return }
    $hit = Get-JobsFeatureRowHit $State $Group $Source $EventArgs
    if ($null -eq $hit -or -not $hit.Row.Check.Enabled) { return }
    $scroll = $State.ContentPanel.AutoScrollPosition
    $State.FeatureRowPress = [pscustomobject]@{ Id=$hit.Id; Group=$Group; Source=$Source; X=$hit.X; Y=$hit.Y; ScrollX=$scroll.X; ScrollY=$scroll.Y }
}
# 移动超过DPI容差即取消，即使随后回到原点，也不把拖动/触控滑动当点击。
function Move-JobsFeatureRowPointer {
    param($State, $Group, $Source, $EventArgs)
    $press = $State.FeatureRowPress
    if ($null -eq $press) { return }
    if ([string]$EventArgs.Button -cne 'Left' -or -not [object]::ReferenceEquals($press.Group,$Group) -or -not [object]::ReferenceEquals($press.Source,$Source)) { $State.FeatureRowPress=$null; return }
    $hit = Get-JobsFeatureRowHit $State $Group $Source $EventArgs
    $limit = [Math]::Max(4, 8*$State.Scale)
    if ($null -eq $hit -or $hit.Id -cne $press.Id -or [Math]::Abs($hit.X-$press.X)+[Math]::Abs($hit.Y-$press.Y) -ge $limit) { $State.FeatureRowPress=$null }
}
# 先消费候选再触发原CheckedChanged，避免重复MouseUp、重入或父子控件双切换。
function Complete-JobsFeatureRowPointer {
    param($State, $Group, $Source, $EventArgs)
    $press = $State.FeatureRowPress
    $State.FeatureRowPress = $null
    if ($null -eq $press -or [string]$EventArgs.Button -cne 'Left' -or (Test-JobsPanelWorkActive $State) -or $State.GroupDragKey) { return }
    if (-not [object]::ReferenceEquals($press.Group,$Group) -or -not [object]::ReferenceEquals($press.Source,$Source)) { return }
    $scroll = $State.ContentPanel.AutoScrollPosition
    if ($scroll.X -ne $press.ScrollX -or $scroll.Y -ne $press.ScrollY) { return }
    $hit = Get-JobsFeatureRowHit $State $Group $Source $EventArgs
    $limit = [Math]::Max(4, 8*$State.Scale)
    if ($null -eq $hit -or $hit.Id -cne $press.Id -or -not $hit.Row.Check.Enabled -or [Math]::Abs($hit.X-$press.X)+[Math]::Abs($hit.Y-$press.Y) -ge $limit) { return }
    $hit.Row.Check.Checked = -not $hit.Row.Check.Checked
    [void]$hit.Row.Check.Focus()
}
# 闭包回到所属模块调用私有控制器；不截获或改写原生滚动/触控消息。
function New-JobsFeatureRowPointerCallback {
    param($State, $Group, [string]$Phase)
    $panelModule = $ExecutionContext.SessionState.Module
    return {
        param($sender,$eventArgs)
        & $panelModule {
            param($s,$g,$source,$e,$phaseName)
            switch ($phaseName) {
                'Down' { Start-JobsFeatureRowPointer $s $g $source $e }
                'Move' { Move-JobsFeatureRowPointer $s $g $source $e }
                'Up' { Complete-JobsFeatureRowPointer $s $g $source $e }
                default { $s.FeatureRowPress=$null }
            }
        } $State $Group $sender $eventArgs $Phase
    }.GetNewClosure()
}
# 仅给已知普通行区域装配命中；checkbox、日志链接和独立按钮保留自身动作。
function Initialize-JobsFeatureRowSelection {
    param($State)
    $State | Add-Member NoteProperty FeatureRowPress $null -Force
    $cancel = New-JobsFeatureRowPointerCallback $State $null 'Cancel'
    $State.ContentPanel.Add_Scroll($cancel)
    $State.ContentPanel.Add_MouseWheel($cancel)
    $State.Form.Add_Deactivate($cancel)
    foreach ($group in $State.Groups) {
        $down = New-JobsFeatureRowPointerCallback $State $group 'Down'
        $move = New-JobsFeatureRowPointerCallback $State $group 'Move'
        $up = New-JobsFeatureRowPointerCallback $State $group 'Up'
        $controls = @($group.Box)
        foreach ($check in $group.Checks) {
            $row = $State.FeatureRows[[string]$check.Tag]
            $controls += @($row.Icon,$row.Title,$State.FeatureLabels[[string]$check.Tag])
            $check.Add_MouseDown($cancel)
            $check.Add_MouseWheel($cancel)
        }
        foreach ($control in $controls) {
            $control.Add_MouseDown($down); $control.Add_MouseMove($move); $control.Add_MouseUp($up)
            $control.Add_MouseLeave($cancel); $control.Add_MouseWheel($cancel)
        }
    }
}

function New-JobsFeatureSelectionForm {
    param(
        [object[]]$Packages,
        [string[]]$Selected,
        [string[]]$Installed = @(),
        [ValidateSet('Manage', 'Install', 'Configure', 'Uninstall')][string]$Mode = 'Manage',
        [switch]$Preview,
        [scriptblock]$BuildPlan,
        [string]$WorkerPath,
        [string]$PreferencesPath
    )
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    Initialize-JobsPanelNative
    $preferences = Read-JobsPanelPreferences $PreferencesPath
    $languageCodes = $script:PanelLanguageCodes
    $features = @($Packages)
    if ($features.Count -eq 0) { throw '没有可供选择的功能包。' }
    $form = New-Object System.Windows.Forms.Form
    $font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
    $toolTip = New-Object System.Windows.Forms.ToolTip
    try {
        $form.Font = $font
        # 所有尺寸使用同一桌面坐标系，避免高 DPI 下窗口再次自动缩放。
        $form.AutoScaleMode = 'None'
        $area = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position).WorkingArea
        $form.StartPosition = 'Manual'
        $form.Location = $area.Location
        $graphics = $form.CreateGraphics()
        try { $scale = $graphics.DpiY / 96.0 } finally { $graphics.Dispose() }
        $rowHeight = [int][Math]::Ceiling(34 * $scale)
        $layout = Get-JobsFeatureSelectionLayout -ItemCount $features.Count -WorkingWidth $area.Width -WorkingHeight $area.Height -RowHeight $rowHeight -Scale $scale
        $form.Text = 'Jobs Windows · 自定义Explorer右键菜单'
        $action = '安装'
        $description = '勾选需要安装的子功能；已启用的兄弟动作与其它未选功能保留。'
        if ($Mode -eq 'Manage') {
            $form.Text = 'Jobs Windows · 自定义Explorer右键菜单'
            $action = '安装 / 更新'
            $description = '选择操作并勾选一个或多个功能；未选功能保留。卸载只处理已安装项。'
        } elseif ($Mode -eq 'Configure') {
            $form.Text = 'Jobs Windows · 自定义Explorer右键菜单'
            $action = '保存配置'
            $description = '勾选安装，取消勾选卸载；全不选后保存将关闭全部已安装功能。'
        } elseif ($Mode -eq 'Uninstall') {
            $form.Text = 'Jobs Windows · 自定义Explorer右键菜单'
            $action = '卸载'
            $description = '只卸载勾选的已安装功能；未勾选项、日志、备份和工具依赖保留。'
        }
        if ($Preview) {
            $form.Text += '（仅预览）'
            $action = '返回选择'
            $description = '仅预览功能选择；确认后在底部显示选择，不安装、不卸载、不写入状态或注册表。'
        }
        $allButtonWidth = [int][Math]::Max(74 * $scale, (Measure-JobsFeatureText '全选' $font).Width + 16 * $scale)
        $noneButtonWidth = [int][Math]::Max(80 * $scale, (Measure-JobsFeatureText '全不选' $font).Width + 16 * $scale)
        $counterWidth = 0
        $statusWidth = 0
        $titleWidth = 0
        $groupTitleWidth = 0
        $groupTotals = @{}
        foreach ($feature in $features) {
            $groupName = '其它右键功能'
            if ($null -ne $feature.PSObject.Properties['Group']) { $groupName = [string]$feature.Group }
            if (-not $groupTotals.ContainsKey($groupName)) { $groupTotals[$groupName] = 0 }
            $groupTotals[$groupName]++
            $titleWidth = [Math]::Max($titleWidth, (Measure-JobsFeatureText (Split-JobsFeatureLabel $feature.Label).Title $font).Width + 64 * $scale)
            $groupTitleWidth = [Math]::Max($groupTitleWidth, (Measure-JobsFeatureText $groupName $font).Width + 20 * $scale)
        }
        foreach ($total in $groupTotals.Values) {
            foreach ($count in 0..$total) { $counterWidth = [Math]::Max($counterWidth, (Measure-JobsFeatureText ('已选 {0} / {1}' -f $count, $total) $font).Width + 4 * $scale) }
        }
        foreach ($text in @('未安装', '未安装，无需卸载', '已安装', '等待中', '正在安装 / 更新…', '正在卸载…', '✅ 安装成功', '已完成', '失败，见日志', '未执行')) {
            $statusWidth = [Math]::Max($statusWidth, (Measure-JobsFeatureText $text $font).Width + 10 * $scale)
        }
        $statusWidth = [int][Math]::Max(90 * $scale, $statusWidth)
        $groupControlsWidth = [int][Math]::Ceiling($allButtonWidth + $noneButtonWidth + $counterWidth + 32 * $scale)
        $minimumPanelWidth = [int][Math]::Ceiling([Math]::Max($groupTitleWidth, [Math]::Max($groupControlsWidth, $titleWidth + $statusWidth + 28 * $scale)))
        $contentLayout = Get-JobsFeatureContentLayout -WorkingWidth $area.Width -PreferredColumns $layout.Columns -MinimumPanelWidth $minimumPanelWidth -MinimumCheckWidth ([int](120 * $scale)) -StatusWidth $statusWidth -GroupControlsWidth $groupControlsWidth -Scale $scale
        $layout.Columns = [Math]::Min(2, $contentLayout.Columns)
        $layout.Rows = [int][Math]::Ceiling($features.Count / [double]$layout.Columns)
        $layout.ClientWidth = $contentLayout.ClientWidth
        $layout.ClientHeight = [int][Math]::Min($area.Height - 60 * $scale, [Math]::Max($layout.ClientHeight, 560 * $scale))
        if ($layout.ClientHeight -lt 400 * $scale) { throw '当前工作区太矮，无法同时显示选择、操作按钮和实时日志；请提高分辨率或降低缩放。' }
        $form.ClientSize = New-Object System.Drawing.Size($layout.ClientWidth, $layout.ClientHeight)
        $form.FormBorderStyle = 'FixedDialog'
        $form.MaximizeBox = $false
        $form.MinimizeBox = $false
        $form.StartPosition = 'Manual'
        $form.Location = New-Object System.Drawing.Point(
            ([int]($area.Left + ($area.Width - $form.Width) / 2)),
            ([int]($area.Top + ($area.Height - $form.Height) / 2)))
        $padding = [int][Math]::Ceiling(20 * $scale)
        $header = New-Object System.Windows.Forms.Panel
        $header.Dock = 'Top'
        $preferencePanel = New-Object Windows.Forms.Panel
        $preferencePanel.Font = $font
        $preferencePanel.Anchor = 'Top, Right'
        $themeLabel = New-Object Windows.Forms.Label
        $themeLabel.Text = '主题'; $themeLabel.AutoSize = $false; $themeLabel.TextAlign = 'MiddleLeft'
        $themeLabel.Margin = New-Object Windows.Forms.Padding(0, ([int](6 * $scale)), ([int](6 * $scale)), 0)
        $themeBox = New-Object Windows.Forms.ComboBox
        $themeBox.DropDownStyle = 'DropDownList'
        $themeBox.Width = [int](150 * $scale)
        [void]$themeBox.Items.AddRange(@('黑夜', '白天', '跟随系统'))
        $themeBox.SelectedIndex = [array]::IndexOf(@('dark', 'light', 'system'), $preferences.Theme)
        $languageLabel = New-Object Windows.Forms.Label
        $languageLabel.Text = '语言'; $languageLabel.AutoSize = $false; $languageLabel.TextAlign = 'MiddleLeft'
        $languageLabel.Margin = New-Object Windows.Forms.Padding(([int](12 * $scale)), ([int](6 * $scale)), ([int](6 * $scale)), 0)
        $languageBox = New-Object Windows.Forms.ComboBox
        $languageBox.DropDownStyle = 'DropDownList'
        $languageBox.MaxDropDownItems = $script:PanelLanguageCodes.Count
        $languageBox.Width = [int](150 * $scale)
        [void]$languageBox.Items.AddRange($script:PanelLanguageNames)
        $languageBox.SelectedIndex = [array]::IndexOf($script:PanelLanguageCodes, $preferences.Language)
        $preferencePanel.Controls.AddRange(@($themeLabel, $themeBox, $languageLabel, $languageBox))
        $header.Controls.Add($preferencePanel)
        $headerLabel = New-Object System.Windows.Forms.Label
        $headerLabel.Font = $font
        $headerLabel.AutoEllipsis = $false
        $headerLabel.Text = "自定义Explorer右键菜单`r`n$description`r`n悬停查看功能说明；Windows 11：右键 → 显示更多选项。"

        if ($Mode -eq 'Manage') {
            $headerLabel.Text = "自定义Explorer右键菜单`r`n勾选功能后确认；未选项保留。悬停可查看当前安装状态。"
        }
        $headerParts = $headerLabel.Text -split "`r`n", 2
        $headerLabel.Text = $headerParts[0]
        $headerDetails = New-Object Windows.Forms.Label
        $headerDetails.Font = $font
        $headerDetails.AutoEllipsis = $false
        $headerDetails.Text = $headerParts[1]
        $headerTextWidth = $layout.ClientWidth - 2 * $padding
        $headerTextHeight = $headerLabel.GetPreferredSize((New-Object Drawing.Size($headerTextWidth, 0))).Height
        $headerLabel.SetBounds($padding, $padding, $headerTextWidth, $headerTextHeight)
        $header.Controls.Add($headerLabel)
        $detailsHeight = $headerDetails.GetPreferredSize((New-Object Drawing.Size($headerTextWidth, 0))).Height
        $headerDetails.SetBounds($padding, ($headerLabel.Bottom + [int](8 * $scale)), $headerTextWidth, $detailsHeight)
        $header.Controls.Add($headerDetails)
        $header.Height = $headerDetails.Bottom + [int](14 * $scale)
        $operationBox = $null
        if ($Mode -eq 'Manage') {
            $operationBox = New-Object System.Windows.Forms.ComboBox
            $operationBox.Font = $font
            $operationBox.DropDownStyle = 'DropDownList'
            $operationBox.SetBounds($padding, ($headerDetails.Bottom + [int](8 * $scale)), ([int](230 * $scale)), ([int](28 * $scale)))
            [void]$operationBox.Items.AddRange(@('安装 / 更新所选功能', '卸载所选功能'))
            $operationBox.SelectedIndex = 0
            $header.Controls.Add($operationBox)
            $header.Height = $operationBox.Bottom + [int](14 * $scale)
        }
        $layout.HeaderHeight = $header.Height
        $deploymentRow = New-Object Windows.Forms.Panel
        $deploymentRow.AutoScroll = $true
        $deploymentRow.SetBounds($padding, ($header.Height + [int](4 * $scale)), ($layout.ClientWidth - 2 * $padding), ([int](34 * $scale)))
        $header.Controls.Add($deploymentRow)
        $routeBox = New-Object Windows.Forms.ComboBox
        $routeBox.Font = $font
        $routeBox.DropDownStyle = 'DropDownList'
        [void]$routeBox.Items.AddRange(@('默认程序安装位置（推荐）', '本地临时构建目录（移走或清理后失效）'))
        $initialRoute = 'installed'
        $deploymentLocked = $false
        foreach ($feature in $Packages) {
            if ($null -eq $feature.PSObject.Properties['PackagePath']) { continue }
            $binding = Join-Path $feature.PackagePath 'deployment.json'
            if (Test-Path -LiteralPath $binding -PathType Leaf) {
                $deployed = Get-Content -LiteralPath $binding -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($deployed.Mode -notin @('installed', 'build')) { throw '已部署包的位置绑定无效。' }
                $initialRoute = [string]$deployed.Mode
                $deploymentLocked = $true
                break
            }
        }
        $routeBox.SelectedIndex = $(if ($initialRoute -eq 'build') { 1 } else { 0 })
        $routeBox.Enabled = -not $deploymentLocked
        $routeBox.SetBounds(0, 0, ([int](220 * $scale)), ([int](28 * $scale)))
        $deploymentRow.Controls.Add($routeBox)
        $cleanupPanel = New-Object Windows.Forms.Panel
        $cleanupPanel.Font = $font
        $autoCleanup = New-Object Windows.Forms.CheckBox
        $autoCleanup.Font = $font
        $autoCleanup.Text = '安装成功后清除此轮构建产物'
        $autoCleanup.Checked = $false
        $autoCleanup.AutoSize = $false
        $cleanupButton = New-Object Windows.Forms.Button
        $cleanupButton.Font = $font
        $cleanupButton.Text = '🧹 清除构建产物'
        $cleanupButton.AutoSize = $false
        $cleanupButton.BackColor = [Drawing.Color]::Firebrick
        $cleanupButton.ForeColor = [Drawing.Color]::White
        $cleanupButton.UseVisualStyleBackColor = $false
        $cleanupPanel.Controls.Add($autoCleanup)
        $deploymentRow.Controls.Add($cleanupPanel)
        $cleanupPanel.Visible = $initialRoute -eq 'installed'
        $header.Height = $deploymentRow.Bottom + [int](12 * $scale)
        $toolTip.SetToolTip($routeBox, '从已部署副本打开时使用当前路线；切换部署位置请从源码目录的管理入口操作。默认模式在当前用户 LocalAppData 独立运行；临时模式登记本包 work 下的运行版本，移动源码目录后失效。')
        $toolTip.SetToolTip($cleanupButton, '只清理所选包专用编译工作区；保留已安装 DLL、运行脚本、配置和注册表。')
        $grid = New-Object System.Windows.Forms.Panel
        $grid.Dock = 'Fill'
        $grid.Padding = New-Object System.Windows.Forms.Padding($padding, 0, $padding, 0)
        $grid.AutoScroll = $true
        $groupStates = @()
        $groupNames = @()
        foreach ($feature in $features) {
            $groupName = '其它右键功能'
            if ($null -ne $feature.PSObject.Properties['Group']) { $groupName = [string]$feature.Group }
            if ($groupName -cnotin $groupNames) { $groupNames += $groupName }
        }
        $panelWidth = $contentLayout.PanelWidth
        $groupForId = @{}
        foreach ($groupName in $groupNames) {
            $items = @($features | Where-Object {
                $name = '其它右键功能'
                if ($null -ne $_.PSObject.Properties['Group']) { $name = [string]$_.Group }
                $name -ceq $groupName
            })
            $box = New-Object System.Windows.Forms.GroupBox
            $box.Font = $font
            $box.Text = $groupName
            $box.Size = New-Object System.Drawing.Size($panelWidth, ([int](76 * $scale) + $items.Count * $rowHeight))
            $box.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 10)
            $all = New-Object System.Windows.Forms.Button
            $all.Font = $font
            $all.Text = '全选'
            $all.SetBounds(([int](8 * $scale)), ([int](24 * $scale)), $allButtonWidth, ([int](30 * $scale)))
            $none = New-Object System.Windows.Forms.Button
            $none.Font = $font
            $none.Text = '全不选'
            $none.SetBounds(($all.Right + [int](6 * $scale)), ([int](24 * $scale)), $noneButtonWidth, ([int](30 * $scale)))
            $counter = New-Object System.Windows.Forms.Label
            $counter.Font = $font
            $counter.AutoEllipsis = $false
            $counterHeight = [int][Math]::Max(24 * $scale, (Measure-JobsFeatureText ('已选 {0} / {0}' -f $items.Count) $font).Height)
            $counter.SetBounds(($none.Right + [int](6 * $scale)), ([int](29 * $scale)), $counterWidth, $counterHeight)
            $box.Controls.AddRange(@($all, $none, $counter))
            $group = [pscustomobject]@{ Name = $groupName; Key = $groupName; IsFlutter = @($items | Where-Object { $_.Id -cnotlike 'flutter-*' }).Count -eq 0; Box = $box; Checks = @(); All = $all; None = $none; Counter = $counter; RowHeight = $rowHeight }
            foreach ($item in $items) { $groupForId[$item.Id] = $group }
            $groupStates += $group
            $grid.Controls.Add($box)
        }
        $checks = @()
        $featureLabels = @{}
        $featureRows = @{}
        for ($index = 0; $index -lt $features.Count; $index++) {
            $feature = $features[$index]
            $check = New-Object System.Windows.Forms.CheckBox
            $check.Font = $font
            $parts = Split-JobsFeatureLabel $feature.Label
            $check.Text = ''
            $check.CheckAlign = 'MiddleCenter'
            $check.AccessibleName = $parts.Title
            $check.AccessibleDescription = $feature.Description
            $check.Tag = $feature.Id
            $check.AutoEllipsis = $false
            $check.Margin = New-Object System.Windows.Forms.Padding(4, 0, 4, 0)
            $check.Checked = $feature.Id -in $Selected
            $installationStatus = '未安装'
            if ($feature.Id -in $Installed) { $installationStatus = '已安装' }
            $toolTip.SetToolTip($check, ($feature.Label + "`r`n" + $installationStatus + "`r`n" + $feature.Description))
            $group = $groupForId[$feature.Id]
            $columns = Get-JobsFeatureRowColumns -Left ([int](8 * $scale)) -Width $contentLayout.CheckWidth -Scale $scale
            $check.SetBounds($columns.CheckLeft, 0, $columns.CheckWidth, $rowHeight)
            $icon = New-Object Windows.Forms.Label
            $icon.Font = $font; $icon.Text = $parts.Icon; $icon.AutoSize = $false; $icon.TextAlign = 'MiddleCenter'
            $icon.SetBounds($columns.IconLeft, 0, $columns.IconWidth, $rowHeight)
            $title = New-Object Windows.Forms.Label
            $title.Font = $font; $title.Text = $parts.Title; $title.AutoSize = $false; $title.TextAlign = 'MiddleLeft'
            $title.SetBounds($columns.TitleLeft, 0, $columns.TitleWidth, $rowHeight)
            $row = [pscustomobject]@{ Check=$check; Icon=$icon; Title=$title; Source=[string]$feature.Label }
            $featureRows[$feature.Id] = $row
            $localRow = $row
            $check.Add_EnabledChanged({ $localRow.Icon.Enabled=$localRow.Check.Enabled; $localRow.Title.Enabled=$localRow.Check.Enabled }.GetNewClosure())
            $toolTip.SetToolTip($icon, $toolTip.GetToolTip($check)); $toolTip.SetToolTip($title, $toolTip.GetToolTip($check))
            $group.Box.Controls.AddRange(@($icon, $title))
            $featureStatus = New-Object System.Windows.Forms.LinkLabel
            $featureStatus.Font = $font
            $featureStatus.Text = $installationStatus
            $featureStatus.Tag = [string]$feature.Id
            $featureStatus.LinkArea = New-Object Windows.Forms.LinkArea(0, 0)
            $featureStatus.LinkColor = [Drawing.Color]::Firebrick
            $featureStatus.ActiveLinkColor = [Drawing.Color]::Firebrick
            $featureStatus.VisitedLinkColor = [Drawing.Color]::Firebrick
            $featureStatus.LinkBehavior = 'HoverUnderline'
            $featureStatus.AutoEllipsis = $false
            $featureStatus.TextAlign = 'MiddleRight'
            $featureStatus.SetBounds(($panelWidth - $statusWidth - [int](8 * $scale)), 0, $statusWidth, $rowHeight)
            $preferredHeight = $check.GetPreferredSize((New-Object Drawing.Size($check.Width, 0))).Height
            $wrappedHeight = (Measure-JobsFeatureText $title.Text $font $title.Width).Height + [int](8 * $scale)
            $group.RowHeight = [int][Math]::Max($group.RowHeight, [Math]::Max($preferredHeight, $wrappedHeight))
            $group.Box.Controls.Add($featureStatus)
            $featureLabels[$feature.Id] = $featureStatus
            $check.TabIndex = $index
            $group.Box.Controls.Add($check)
            $group.Checks += $check
            $checks += $check
        }
        foreach ($group in $groupStates) {
            $top = [int][Math]::Max(66 * $scale, [Math]::Max($group.All.Bottom, $group.Counter.Bottom) + 8 * $scale)
            foreach ($check in $group.Checks) {
                $check.Top = $top
                $check.Height = $group.RowHeight
                $row = $featureRows[[string]$check.Tag]
                $row.Icon.Top = $top; $row.Icon.Height = $group.RowHeight
                $row.Title.Top = $top; $row.Title.Height = $group.RowHeight
                $featureLabels[[string]$check.Tag].Top = $top
                $featureLabels[[string]$check.Tag].Height = $group.RowHeight
                $top += $group.RowHeight
            }
            $group.Box.Height = $top + [int](10 * $scale)
        }

        $footer = New-Object System.Windows.Forms.Panel
        $footer.Dock = 'Bottom'
        $footer.Height = $layout.FooterHeight
        $status = New-Object System.Windows.Forms.Label
        $status.Font = $font
        $status.AutoEllipsis = $false
        $status.Location = New-Object System.Drawing.Point($padding, ([int](10 * $scale)))
        $status.Size = New-Object System.Drawing.Size(($layout.ClientWidth - 2 * $padding), ([int](26 * $scale)))
        $footer.Controls.Add($status)
        $footer.Controls.Add($cleanupButton)
        $buttons = @()
        foreach ($text in @('全选', '全不选', $action, '取消')) {
            $button = New-Object System.Windows.Forms.Button
            $button.Font = $font
            $button.Text = $text
            $button.Size = New-Object System.Drawing.Size(([int](104 * $scale)), ([int](34 * $scale)))
            $buttons += $button
            $footer.Controls.Add($button)
        }
        $buttons[0].Location = New-Object System.Drawing.Point($padding, ([int](46 * $scale)))
        $buttons[1].Location = New-Object System.Drawing.Point(($padding + [int](114 * $scale)), ([int](46 * $scale)))
        $buttons[2].Location = New-Object System.Drawing.Point(($layout.ClientWidth - $padding - [int](218 * $scale)), ([int](46 * $scale)))
        $buttons[3].Location = New-Object System.Drawing.Point(($layout.ClientWidth - $padding - [int](104 * $scale)), ([int](46 * $scale)))
        $progress = New-Object System.Windows.Forms.ProgressBar
        $progress.SetBounds($padding, ([int](36 * $scale)), ($layout.ClientWidth - 2 * $padding), ([int](6 * $scale)))
        $footer.Controls.Add($progress)
        $logPanel = New-Object System.Windows.Forms.Panel
        $logPanel.Dock = 'Fill'
        $logPanel.Height = [int][Math]::Min(180 * $scale, [Math]::Max(100 * $scale, $layout.ClientHeight * 0.25))
        $logToolbar = New-Object System.Windows.Forms.FlowLayoutPanel
        $logToolbar.Font = $font
        $logToolbar.Dock = 'Top'
        $logToolbar.AutoSize = $true
        $logToolbar.AutoSizeMode = 'GrowAndShrink'
        $logToolbar.WrapContents = $true
        $logToolbar.MaximumSize = New-Object Drawing.Size($layout.ClientWidth, 0)
        $logTitle = New-Object System.Windows.Forms.Label
        $logTitle.Font = $font
        $logTitle.Text = '实时日志（拖动上方分隔条调节高度）'
        $logTitle.AutoSize = $true
        $logTitle.TextAlign = 'MiddleLeft'
        $copyLog = New-Object System.Windows.Forms.Button
        $copyLog.Font = $font
        $copyLog.Text = '复制全部日志'
        $copyLog.AutoSize = $true
        $followLog = New-Object System.Windows.Forms.CheckBox
        $followLog.Font = $font
        $followLog.Text = '自动滚动'
        $followLog.Checked = $true
        $followLog.AutoSize = $true
        $logToolbar.Controls.AddRange(@($logTitle, $copyLog, $followLog))
        $logToolbar.Size = $logToolbar.GetPreferredSize((New-Object Drawing.Size($layout.ClientWidth, 0)))
        $logPanel.Height = [int][Math]::Max($logPanel.Height, $logToolbar.Height + 80 * $scale)
        Initialize-JobsManagementLogFormat
        $logView = New-Object JobsManagementLog.View
        $logView.Dock = 'Fill'
        $logView.ReadOnly = $true
        $logView.WordWrap = $false
        $logView.DetectUrls = $false
        $logView.BackColor = [Drawing.Color]::FromArgb(24, 28, 34)
        $logView.ForeColor = [Drawing.Color]::Gainsboro
        $logView.Font = New-Object Drawing.Font('Consolas', 9)
        $logView.ScrollBars = 'Both'
        $logView.ShortcutsEnabled = $true
        $logView.HideSelection = $false
        $logMenu = New-Object System.Windows.Forms.ContextMenuStrip
        $copySelection = New-Object System.Windows.Forms.ToolStripMenuItem('复制')
        $copySelection.ShortcutKeys = [Windows.Forms.Keys]::Control -bor [Windows.Forms.Keys]::C
        $selectLog = New-Object System.Windows.Forms.ToolStripMenuItem('全选')
        $selectLog.ShortcutKeys = [Windows.Forms.Keys]::Control -bor [Windows.Forms.Keys]::A
        [void]$logMenu.Items.Add($copySelection)
        [void]$logMenu.Items.Add($selectLog)
        $logView.ContextMenuStrip = $logMenu
        $logPanel.Controls.Add($logView)
        $logPanel.Controls.Add($logToolbar)
        $buttons[3].DialogResult = [System.Windows.Forms.DialogResult]::None
        $form.CancelButton = $buttons[3]
        $logSplit = New-Object System.Windows.Forms.SplitContainer
        $logSplit.Size = New-Object Drawing.Size($layout.ClientWidth, ($layout.ClientHeight - $header.Height))
        $logSplit.Orientation = 'Horizontal'
        $logSplit.Dock = 'Fill'
        $logSplit.FixedPanel = 'Panel2'
        $logSplit.SplitterWidth = [int][Math]::Max(7, [Math]::Ceiling(7 * $scale))
        $logSplit.IsSplitterFixed = $false
        $logSplit.AccessibleName = '功能与日志分隔条'
        $logSplit.AccessibleDescription = '上下拖动调节日志高度'
        $initialLogLayout = Get-JobsManagementLogLayout -Height $logSplit.Height -FooterHeight $footer.Height -ToolbarHeight $logToolbar.Height -RowHeight $rowHeight -SplitterWidth $logSplit.SplitterWidth -LogHeight $logPanel.Height -Scale $scale
        $logSplit.SplitterDistance = $initialLogLayout.Distance
        $logSplit.Panel1MinSize = $initialLogLayout.UpperMinimum
        $logSplit.Panel2MinSize = $initialLogLayout.LowerMinimum
        $logSplit.Panel1.Controls.Add($grid)
        $logSplit.Panel1.Controls.Add($footer)
        $logSplit.Panel2.Controls.Add($logPanel)
        $toolTip.SetToolTip($logSplit, '上下拖动分隔条调节日志高度')
        $form.Controls.Add($logSplit)
        $form.Controls.Add($header)
        $state = [pscustomobject]@{
            Preferences = $preferences; PreferencesPath = (Get-JobsPanelPreferencesPath $PreferencesPath)
            Language = 'zh-Hans'; Theme = ''; ThemeBox = $themeBox; LanguageBox = $languageBox; PreferencePanel = $preferencePanel; ThemeLabel = $themeLabel; LanguageLabel = $languageLabel; PreferenceUpdating = $false
            HeaderLayoutUpdating = $false; HeaderTopLayout = $null
            PreferenceTimer = (New-Object Windows.Forms.Timer); TextBindings = (New-Object 'Collections.Generic.List[object]'); ToolTipBindings = (New-Object 'Collections.Generic.List[object]')
            StatusSource = ''; CancelText = '取消'; FeatureStatusSources = @{}; FeatureMessages = @{}; PreferredHeaderHeight = $header.Height
            Form = $form; Checks = $checks; ConfirmButton = $buttons[2]
            SelectAllButton = $buttons[0]; ClearButton = $buttons[1]; CancelButton = $buttons[3]
            StatusLabel = $status; Layout = $layout; Mode = $Mode; ToolTip = $toolTip; Font = $font
            Groups = $groupStates; ContentPanel = $grid; Footer = $footer
            GroupLayout = @(); GroupLayoutPath = ''; GroupColumns = 1; GroupPanelWidth = $panelWidth
            GroupLayoutUpdating = $false; GroupDragToken = [guid]::NewGuid().ToString('N'); GroupDragKey = ''; GroupDragOrigin = $null; GroupDrop = $null; GroupDropMarker = $null
            Header = $header; HeaderLabel = $headerLabel; HeaderDetailsLabel = $headerDetails; LogToolbar = $logToolbar; Padding = $padding; Scale = $scale
            Packages = @($Packages); RouteBox = $routeBox; DeploymentRow = $deploymentRow; DeploymentRowLayout = $null; CleanupPanel = $cleanupPanel; AutoCleanup = $autoCleanup; CleanupButton = $cleanupButton
            DeploymentMode = $initialRoute; DeploymentLocked = $deploymentLocked; StopRequestPath = $null; StopRequested = $false; Stopped = $false
            BuildPlan = $BuildPlan; WorkerPath = $WorkerPath; Running = $false; Started = $false
            ExitRequested = $false; SelectionAccepted = $false; ClosePromptOpen = $false; TrayHidden = $false; TrayWindowState = 'Normal'; TrayDisposed = $false; TrayError = ''
            TrayIcon = $null; TrayMenu = $null; TrayRestore = $null; TrayStatus = $null; TrayExit = $null; TrayOwnedIcon = $null
            FeatureRows = $featureRows; FeatureLabels = $featureLabels; FeatureStates = @{}; FeatureOperations = @{}; Progress = $progress
            LogView = $logView; FollowLog = $followLog; CopyLogButton = $copyLog
            LogSplit = $logSplit; LogMenu = $logMenu; CopySelectionItem = $copySelection; SelectLogItem = $selectLog
            LogPath = (Join-Path ([IO.Path]::GetTempPath()) ('JobsExtensionManager-' + [guid]::NewGuid().ToString('N') + '.log'))
            Pump = $null; Timer = (New-Object Windows.Forms.Timer); RequestPath = $null
            RunClocks = @{ Install = (New-Object Diagnostics.Stopwatch); Uninstall = (New-Object Diagnostics.Stopwatch); Cleanup = (New-Object Diagnostics.Stopwatch) }
            Preview = [bool]$Preview; OperationBox = $operationBox; Operation = $(if ($Mode -eq 'Manage') { 'Install' } else { $Mode }); Installed = @($Installed)
        }
        Initialize-JobsPanelGroupDrag $state
        Initialize-JobsFeatureRowSelection $state
        Initialize-JobsPanelCenteredChoice $themeBox
        Initialize-JobsPanelCenteredChoice $languageBox
        # 闭包保留表单状态，事件不依赖已返回的构造函数局部作用域。
        # 动态闭包模块只能按已捕获的函数体调用私有选择门禁。
        $getActiveSelection = ${function:Get-JobsPanelActiveSelection}
        $setPanelOperation = ${function:Set-JobsPanelOperation}
        $refresh = {
            if ($state.Running -or $state.Started) { return }
            $count = @($state.Checks | Where-Object { $_.Checked }).Count
            Set-JobsFeatureStatusText $state ('已选 {0} / {1} 项；关闭或取消窗口不执行操作。' -f $count, $state.Checks.Count)
            $activeCount = @(& $getActiveSelection $state).Count
            $state.ConfirmButton.Enabled = $activeCount -gt 0 -or $state.Mode -eq 'Configure'
            $state.CleanupButton.Enabled = $activeCount -gt 0 -and -not $state.Running -and $state.DeploymentMode -eq 'installed'
            $state.AutoCleanup.Enabled = -not $state.Running -and $state.DeploymentMode -eq 'installed'
            $state.Form.AcceptButton = $null
            if ($state.ConfirmButton.Enabled) { $state.Form.AcceptButton = $state.ConfirmButton }
            foreach ($group in $state.Groups) {
                $groupCount = @($group.Checks | Where-Object { $_.Checked }).Count
                $group.Counter.Text = (Get-JobsPanelText '已选 {0} / {1}' $state.Language) -f $groupCount, $group.Checks.Count
                $group.All.Enabled = $groupCount -lt $group.Checks.Count
                $group.None.Enabled = $groupCount -gt 0
            }
        }.GetNewClosure()
        $state | Add-Member -NotePropertyName Refresh -NotePropertyValue $refresh
        foreach ($check in $checks) { $check.Add_CheckedChanged($refresh) }
        foreach ($group in $groupStates) {
            $localGroup = $group
            $group.All.Add_Click({ foreach ($check in $localGroup.Checks) { if ($check.Enabled) { $check.Checked = $true } } }.GetNewClosure())
            $group.None.Add_Click({ foreach ($check in $localGroup.Checks) { $check.Checked = $false } }.GetNewClosure())
        }
        $buttons[0].Add_Click({ foreach ($check in $state.Checks) { if ($check.Enabled) { $check.Checked = $true } } }.GetNewClosure())
        $buttons[1].Add_Click({ foreach ($check in $state.Checks) { $check.Checked = $false } }.GetNewClosure())
        $buttons[2].Add_Click({
            if ($state.Running) { Request-JobsManagementStop $state; return }
            $ids = @(& $getActiveSelection $state)
            # 即使事件被程序直接调用，也不能绕过空选门禁。
            if ($ids.Count -eq 0 -and $state.Mode -ne 'Configure') { return }
            $choice = [pscustomobject]@{ Features = $ids; Mode = $state.Operation; DeploymentMode = $state.DeploymentMode; AutoCleanup = [bool]$state.AutoCleanup.Checked }
            if ($state.BuildPlan -and $state.Preview) {
                Add-JobsManagementLog $state ('仅预览：' + (ConvertTo-Json -InputObject $choice -Compress -Depth 3))
                Set-JobsFeatureStatusText $state '仅预览：选择已显示在下方日志，未执行安装或卸载。'
                return
            }
            if ($state.BuildPlan -and -not $state.Preview) {
                try { Start-JobsManagementRun $state $choice }
                catch { Add-JobsManagementLog $state ('无法建立操作计划：' + $_.Exception.Message) -Level error }
                return
            }
            $state.Form.Tag = $choice
            $state.SelectionAccepted = $true
            $state.Form.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $state.Form.Close()
        }.GetNewClosure())
        $routeBox.Add_SelectedIndexChanged({
            if ($state.PreferenceUpdating -or $state.Running -or $state.Started) { return }
            $state.DeploymentMode = 'installed'
            if ($state.RouteBox.SelectedIndex -eq 1) { $state.DeploymentMode = 'build' }
            $state.CleanupPanel.Visible = $state.DeploymentMode -eq 'installed'
            Set-JobsFeatureStatusText $state $state.StatusSource
            Set-JobsPanelHeaderLayout $state
            $state.Installed = @(Get-JobsManagementRouteInstalled -Packages $state.Packages -DeploymentMode $state.DeploymentMode)
            foreach ($check in $state.Checks) {
                $check.Checked = $false
                $check.Enabled = $state.Operation -ne 'Uninstall' -or [string]$check.Tag -in $state.Installed
                $state.FeatureStatusSources.Remove([string]$check.Tag)
                $state.FeatureLabels[[string]$check.Tag].Text = Get-JobsPanelText $(if ([string]$check.Tag -in $state.Installed) { '已安装' } else { '未安装' }) $state.Language
            }
            & $refresh
        }.GetNewClosure())
        $cleanupButton.Add_Click({
            if ($state.Running -or $state.Started -or $state.DeploymentMode -ne 'installed') { return }
            $ids = @(& $getActiveSelection $state)
            if ($ids.Count -eq 0) { return }
            $choice = [pscustomobject]@{ Features = $ids; Mode = 'Cleanup'; DeploymentMode = 'installed'; AutoCleanup = $false }
            if ($state.Preview) { Add-JobsManagementLog $state ('仅预览清理：' + ($ids -join ', ')); return }
            Start-JobsManagementRun $state $choice
        }.GetNewClosure())
        if ($operationBox) {
            $operationBox.Add_SelectedIndexChanged({
                if ($state.PreferenceUpdating) { return }
                & $setPanelOperation $state $(if ($state.OperationBox.SelectedIndex -eq 1) { 'Uninstall' } else { 'Install' })
                & $refresh
            }.GetNewClosure())
        }
        $state.Timer.Interval = 100
        $state.Timer.Add_Tick((New-JobsManagementTimerCallback $state))
        $panelModule = $ExecutionContext.SessionState.Module
        $buttons[3].Add_Click({ $state.Form.Close() }.GetNewClosure())
        $form.Add_FormClosing({ param($sender,$eventArgs) & $panelModule { param($s,$e) Request-JobsPanelClose $s $e } $state $eventArgs }.GetNewClosure())
        $logView.Add_UserNavigation({ $state.FollowLog.Checked = $false }.GetNewClosure())
        $followLog.Add_CheckedChanged({ if ($state.FollowLog.Checked) { $state.LogView.FollowTail() } }.GetNewClosure())
        $copySelection.Add_Click({ if ($state.LogView.SelectionLength -gt 0) { [Windows.Forms.Clipboard]::SetText($state.LogView.SelectedText) } }.GetNewClosure())
        $selectLog.Add_Click({
            [void]$state.LogView.Focus()
            $state.FollowLog.Checked = $false
            $state.LogView.SelectAll()
        }.GetNewClosure())
        $logMenu.Add_Opening({
            $state.CopySelectionItem.Enabled = $state.LogView.SelectionLength -gt 0
            $state.SelectLogItem.Enabled = $state.LogView.TextLength -gt 0
        }.GetNewClosure())
        $logView.Add_KeyDown({
            param($sender, $eventArgs)
            if ($eventArgs.Control -and -not $eventArgs.Alt -and $eventArgs.KeyCode -eq [Windows.Forms.Keys]::A) {
                $state.FollowLog.Checked = $false
                $sender.SelectAll()
                $eventArgs.Handled = $true
                $eventArgs.SuppressKeyPress = $true
            } elseif ($eventArgs.Control -and -not $eventArgs.Alt -and $eventArgs.KeyCode -eq [Windows.Forms.Keys]::C -and $sender.SelectionLength -gt 0) {
                [Windows.Forms.Clipboard]::SetText($sender.SelectedText)
                $eventArgs.Handled = $true
                $eventArgs.SuppressKeyPress = $true
            }
        }.GetNewClosure())
        $copyLog.Add_Click({
            try { [Windows.Forms.Clipboard]::SetText([IO.File]::ReadAllText($state.LogPath)) }
            catch { Set-JobsFeatureStatusText $state ('复制日志失败：' + $_.Exception.Message) }
        }.GetNewClosure())
        foreach ($label in $state.FeatureLabels.Values) {
            $label.Add_LinkClicked({
                param($sender, $eventArgs)
                $id = [string]$sender.Tag
                if (-not $state.FeatureStates.ContainsKey($id) -or $state.FeatureStates[$id] -ne 'Failed') { return }
                try { Open-JobsManagementLog -LogPath $state.LogPath }
                catch { Set-JobsFeatureStatusText $state ('打开完整日志失败：' + $_.Exception.Message) }
            }.GetNewClosure())
        }
        Add-JobsManagementLog $state '勾选功能并点击安装 / 更新或卸载，任务将在本面板执行；取消、关闭或空选不执行。'
        Add-JobsManagementLog $state '影响范围：当前用户的菜单、运行文件和功能配置；安装会构建与注册所选包，卸载保留程序、日志、备份和工具。'
        Add-JobsManagementLog $state ('来源：' + $WorkerPath + '；日志：' + $state.LogPath)
        & $refresh
        Add-JobsPanelTextBindings $form $state
        $preferenceChanged = {
            if ($state.PreferenceUpdating) { return }
            $state.Preferences.Theme = @('dark', 'light', 'system')[$state.ThemeBox.SelectedIndex]
            $state.Preferences.Language = $languageCodes[$state.LanguageBox.SelectedIndex]
            Update-JobsPanelPresentation $state -Force
            try { Save-JobsPanelPreferences -Theme $state.Preferences.Theme -Language $state.Preferences.Language -Path $state.PreferencesPath }
            catch { Set-JobsFeatureStatusText $state ('保存偏好失败：' + $_.Exception.Message) }
        }.GetNewClosure()
        $themeBox.Add_SelectedIndexChanged($preferenceChanged)
        $languageBox.Add_SelectedIndexChanged($preferenceChanged)
        $state.PreferenceTimer.Interval = 1000
        $state.PreferenceTimer.Add_Tick({ Update-JobsPanelPresentation $state; & $panelModule { param($s) Update-JobsPanelTray $s } $state }.GetNewClosure())
        $form.Add_Shown({ Update-JobsPanelPresentation $state -Force; $state.PreferenceTimer.Start() }.GetNewClosure())
        $form.Add_Disposed({ $state.PreferenceTimer.Stop(); $state.PreferenceTimer.Dispose(); & $panelModule { param($s) Stop-JobsPanelTray $s } $state }.GetNewClosure())
        $form.Add_ClientSizeChanged({
            if ($state.HeaderLayoutUpdating -or $state.Form.IsDisposed) { return }
            $state.HeaderLayoutUpdating = $true
            try {
                Set-JobsPanelGroupLayout $state
                Set-JobsPanelHeaderLayout $state
                Set-JobsFeatureStatusText $state $state.StatusSource
            } finally { $state.HeaderLayoutUpdating = $false }
        }.GetNewClosure())
        Update-JobsPanelPresentation $state -Force
        Initialize-JobsPanelTray $state
        if ($preferences.Error) { Set-JobsFeatureStatusText $state ('读取偏好失败：' + $preferences.Error) }
        return $state
    } catch {
        $form.Dispose()
        $toolTip.Dispose()
        $font.Dispose()
        throw
    }
}

# 捕获原模块的函数体；GetNewClosure 的动态模块不能按名称访问私有进度函数。
function New-JobsManagementTimerCallback {
    param($State)
    $readOutput = ${function:Read-JobsManagementOutput}
    $updateProgress = ${function:Update-JobsManagementProgress}
    return {
        if ($State.Running) { & $readOutput $State }
        if ($State.Running) { & $updateProgress $State }
    }.GetNewClosure()
}

# 只展示 Catalog 传入的 Id/Label/Group 并返回选择；业务门禁写在对应包，不写进 UI 文案或点击回调。
function Show-JobsFeatureSelection {
    param(
        [object[]]$Packages,
        [string[]]$Selected,
        [string[]]$Installed = @(),
        [ValidateSet('Manage', 'Install', 'Configure', 'Uninstall')][string]$Mode = 'Manage',
        [switch]$Preview,
        [scriptblock]$BuildPlan,
        [string]$WorkerPath,
        [string]$PreferencesPath
    )
    $state = New-JobsFeatureSelectionForm -Packages $Packages -Selected $Selected -Installed $Installed -Mode $Mode -Preview:$Preview -BuildPlan $BuildPlan -WorkerPath $WorkerPath -PreferencesPath $PreferencesPath
    try {
        [System.Windows.Forms.Application]::Run($state.Form)
        if ($state.SelectionAccepted) { return $state.Form.Tag }
        return $null
    } finally {
        Stop-JobsPanelTray $state
        if ($null -ne $state.Pump) { $state.Pump.Dispose(); $state.Pump = $null }
        $state.Timer.Dispose()
        $state.LogView.Font.Dispose()
        $state.LogMenu.Dispose()
        $state.Form.Dispose()
        $state.ToolTip.Dispose()
        $state.Font.Dispose()
    }
}

# Process 事件只在 .NET 线程里入队，UI 线程定时取走，避免 PowerShell 回调跨 runspace 崩溃。
function Initialize-JobsManagementProcess {
    if ('JobsManagement.OutputPump' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO;
using System.Threading;
namespace JobsManagement {
    public sealed class OutputChunk {
        public string Text;
        public bool IsEvent;
        public bool IsError;
        public OutputChunk(string text, bool isEvent) : this(text, isEvent, false) { }
        public OutputChunk(string text, bool isEvent, bool isError) { Text = text; IsEvent = isEvent; IsError = isError; }
    }
    public sealed class OutputPump : IDisposable {
        private const string Marker = "@@JOBS-MANAGER@@";
        public readonly ConcurrentQueue<OutputChunk> Lines = new ConcurrentQueue<OutputChunk>();
        public Process Process { get; private set; }
        private int closed;
        public bool Drained { get { return Volatile.Read(ref closed) == 2; } }
        private void Read(StreamReader reader, bool events) {
            char[] buffer = new char[1024];
            string pending = "";
            bool atLineStart = true;
            try {
                int count;
                while ((count = reader.Read(buffer, 0, buffer.Length)) > 0) {
                    pending += new string(buffer, 0, count);
                    while (pending.Length > 0) {
                        int newline = pending.IndexOf('\n');
                        bool marker = events && atLineStart && pending.StartsWith(Marker, StringComparison.Ordinal);
                        if (events && atLineStart && Marker.StartsWith(pending, StringComparison.Ordinal)) break;
                        if (marker && newline < 0) break;
                        if (newline >= 0) {
                            string line = pending.Substring(0, newline + 1);
                            Lines.Enqueue(new OutputChunk(marker ? line.TrimEnd('\r', '\n') : line, marker, !events));
                            pending = pending.Substring(newline + 1);
                            atLineStart = true;
                        } else {
                            Lines.Enqueue(new OutputChunk(pending, false, !events));
                            pending = "";
                            atLineStart = false;
                        }
                    }
                }
                if (pending.Length > 0) Lines.Enqueue(new OutputChunk(pending, events && atLineStart && pending.StartsWith(Marker, StringComparison.Ordinal), !events));
            } catch (Exception error) {
                Lines.Enqueue(new OutputChunk("\n读取后台输出失败：" + error.Message + "\n", false, true));
            } finally { Interlocked.Increment(ref closed); }
        }
        public void Start(ProcessStartInfo info) {
            info.UseShellExecute = false;
            info.CreateNoWindow = true;
            info.RedirectStandardOutput = true;
            info.RedirectStandardError = true;
            Process = new Process { StartInfo = info };
            if (!Process.Start()) throw new InvalidOperationException("无法启动后台管理进程。");
            Thread output = new Thread(() => Read(Process.StandardOutput, true));
            Thread error = new Thread(() => Read(Process.StandardError, false));
            output.IsBackground = true;
            error.IsBackground = true;
            output.Start();
            error.Start();
        }
        public OutputChunk Take() { OutputChunk chunk; return Lines.TryDequeue(out chunk) ? chunk : null; }
        public void Dispose() { if (Process != null) Process.Dispose(); }
    }
}
'@
}

# 仅根据真实步骤状态着色；无需卸载保持信息色，最终失败不能显示成功色。
function Get-JobsManagementLogLevel {
    param([string]$Status, [string]$Message, $FeatureStates)
    switch ($Status) {
        'Failed' { return 'error' }
        'Succeeded' { return 'success' }
        'Skipped' { return 'warning' }
        'Stopped' { return 'warning' }
        'Finished' {
            if (@($FeatureStates.Values | Where-Object { $_ -eq 'Failed' }).Count -gt 0) { return 'error' }
            if (@($FeatureStates.Values | Where-Object { $_ -eq 'Skipped' }).Count -gt 0) { return 'warning' }
            return [JobsManagementLog.Palette]::Level($Message)
        }
        default { return 'info' }
    }
}

# 后台原文仅过滤终端控制码；保存完整纯文本，再按级别及ANSI分段追加到彩色视图。
function Add-JobsManagementLog {
    param($State, [string]$Text, [switch]$NoNewline, [ValidateSet('panel','output','error')][string]$Channel = 'panel', [string]$Level = '')
    $buffer = Get-JobsManagementLogBuffer $State
    $contrastKey = Get-JobsPanelContrastKey
    if ($null -eq $State.PSObject.Properties['LogContrastKey'] -or $State.LogContrastKey -cne $contrastKey) { Set-JobsManagementLogTheme $State -ContrastKey $contrastKey }
    if (-not $State.LogParsers.ContainsKey($Channel)) { $State.LogParsers[$Channel] = New-Object JobsManagementLog.AnsiParser }
    if (-not $Level) { $Level = [JobsManagementLog.Palette]::Level($Text); if ($Level -eq 'normal' -and $Channel -eq 'error') { $Level = 'error' } }
    $ending = [Environment]::NewLine
    if ($NoNewline) { $ending = '' }
    $parsed = $State.LogParsers[$Channel].Push($Text + $ending, $Level)
    [IO.File]::AppendAllText($State.LogPath, $parsed.Plain, (New-Object Text.UTF8Encoding($false)))
    $remove = $buffer.Append($parsed.Spans)
    $runs = @($parsed.Spans)
    $State.LogView.AppendColored([string[]]@($runs | ForEach-Object { $_.Text }), [int[]]@(Get-JobsManagementLogColors $State $runs $State.LogContrastForeground), $remove, [bool]$State.FollowLog.Checked)
}

# 路径与日志正文都只作为数据；新终端仅用 LiteralPath 读取完整会话文件。
function New-JobsManagementLogStartInfo {
    param([Parameter(Mandatory = $true)][string]$LogPath)
    if ([string]::IsNullOrWhiteSpace($LogPath) -or $LogPath -match '[\x00\r\n]') { throw '会话日志路径无效。' }
    $item = Get-Item -LiteralPath $LogPath -Force -ErrorAction Stop
    if ($item.PSIsContainer) { throw ('会话日志不是文件：' + $LogPath) }
    $stream = [IO.File]::Open($item.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    $stream.Dispose()
    $encodedPath = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($item.FullName))
    $command = @'
$logPath = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('__JOBS_LOG_PATH__'))
try {
    Write-Host ('完整会话日志：' + $logPath) -ForegroundColor Cyan
    Get-Content -LiteralPath $logPath -Encoding UTF8 -ReadCount 256 -ErrorAction Stop
} catch {
    Write-Host ('读取会话日志失败：' + $_.Exception.Message) -ForegroundColor Red
}
'@
    $command = $command.Replace('__JOBS_LOG_PATH__', $encodedPath)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = Join-Path $PSHOME 'powershell.exe'
    $start.Arguments = '-NoLogo -NoProfile -NoExit -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $start.UseShellExecute = $true
    $start.WindowStyle = 'Normal'
    return $start
}

# 启动独立日志终端，不等待其退出或改变当前后台事务。
function Open-JobsManagementLog {
    param([Parameter(Mandatory = $true)][string]$LogPath)
    $start = New-JobsManagementLogStartInfo -LogPath $LogPath
    $process = [Diagnostics.Process]::Start($start)
    if ($null -eq $process) { throw '系统未能启动日志终端。' }
    $process.Dispose()
}

function Set-JobsManagementFeatureState {
    param($State, [string[]]$FeatureIds, [string]$Status, [string]$Message)
    foreach ($id in $FeatureIds) {
        if (-not $State.FeatureStates.ContainsKey($id)) { continue }
        if ($Status -ceq 'NotInstalled') {
            $operation = $State.Operation
            if ($null -ne $State.PSObject.Properties['FeatureOperations'] -and $State.FeatureOperations.ContainsKey($id)) { $operation = $State.FeatureOperations[$id] }
            if ($operation -cne 'Uninstall') { throw '只有对应叶功能的卸载操作可以报告“未安装，无需卸载”。' }
        }
        $State.FeatureStates[$id] = $Status
        $label = $State.FeatureLabels[$id]
        $label.ForeColor = [Drawing.SystemColors]::ControlText
        $label.Links.Clear()
        $label.Cursor = [Windows.Forms.Cursors]::Default
        $label.Text = switch ($Status) {
            'Pending' { '等待中' }
            'Running' { if ($State.Operation -eq 'Cleanup') { '正在清理…' } elseif ($State.Operation -eq 'Uninstall') { '正在卸载…' } else { '正在安装 / 更新…' } }
            'Succeeded' {
                $label.ForeColor = [Drawing.Color]::ForestGreen
                if ($State.Operation -in @('Uninstall', 'Cleanup')) { '已完成' } else { '✅ 安装成功' }
            }
            'Failed' { $label.ForeColor = [Drawing.Color]::Firebrick; '失败，见日志' }
            'NotInstalled' { '未安装，无需卸载' }
            'Skipped' { '未执行' }
        }
        if ($null -ne $State.PSObject.Properties['FeatureStatusSources']) { $State.FeatureStatusSources[$id] = $label.Text }
        $label.Text = Get-JobsPanelText $label.Text (Get-JobsPanelLanguage $State)
        if ($null -ne $State.PSObject.Properties['Theme']) { Set-JobsPanelControlTheme $label $State }
        $label.LinkArea = New-Object Windows.Forms.LinkArea(0, 0)
        if ($Status -eq 'Failed') {
            [void]$label.Links.Add(0, $label.Text.Length)
            $label.Cursor = [Windows.Forms.Cursors]::Hand
        }
        if ($null -ne $State.PSObject.Properties['FeatureMessages']) { $State.FeatureMessages[$id] = $Message }
        Set-JobsPanelFeatureToolTip $State $id $Message
    }
    Update-JobsManagementProgress $State
}

function Complete-JobsManagementRun {
    param($State, [bool]$Success, [string]$Message)
    $clock = Get-JobsManagementClock $State
    $clock.Stop()
    $State.Timer.Stop()
    $State.Running = $false
    $State.Progress.Style = 'Continuous'
    foreach ($id in @($State.FeatureStates.Keys)) {
        if ($State.FeatureStates[$id] -eq 'Running' -or $State.FeatureStates[$id] -eq 'Pending') {
            $status = 'Skipped'
            if ($State.FeatureStates[$id] -eq 'Running') { $status = 'Failed' }
            Set-JobsManagementFeatureState $State @($id) $status $Message
        }
    }
    $progress = Get-JobsManagementProgress $State
    $clockLabel = '安装总用时'
    if ($State.Operation -eq 'Uninstall') { $clockLabel = '卸载总用时' }
    if ($State.Operation -eq 'Cleanup') { $clockLabel = '清理总用时' }
    $messageWithProgress = '{0} 已处理 {1} / {2} 项（{3}%，按完成项计数）；{4} {5}' -f $Message, $progress.Finished, $progress.Total, $progress.Percent, $clockLabel, (Format-JobsManagementElapsedTime $clock.Elapsed)
    $messageWithProgress += '；结果：成功 {0}；无需卸载 {1}；失败 {2}；未执行 {3}' -f $progress.Succeeded, $progress.NotInstalled, $progress.Failed, $progress.Skipped
    Set-JobsFeatureStatusText $State $messageWithProgress
    if ($null -ne $State.Pump) { $State.Pump.Dispose(); $State.Pump = $null }
    if ($State.RequestPath -and [IO.File]::Exists($State.RequestPath)) { [IO.File]::Delete($State.RequestPath) }
    if ($null -ne $State.PSObject.Properties['StopRequestPath'] -and $State.StopRequestPath -and [IO.File]::Exists($State.StopRequestPath)) { [IO.File]::Delete($State.StopRequestPath) }
    $State.CancelButton.Enabled = $true
    if ($null -ne $State.PSObject.Properties['CancelText']) { $State.CancelText = '关闭' }
    $State.CancelButton.Text = Get-JobsPanelText '关闭' (Get-JobsPanelLanguage $State)
    $State.Form.CancelButton = $State.CancelButton
    if ($null -ne $State.PSObject.Properties['Refresh']) {
        $State.Started = $false
        $State.RouteBox.Enabled = -not $State.DeploymentLocked
        $State.Installed = @(Get-JobsManagementRouteInstalled -Packages $State.Packages -DeploymentMode $State.DeploymentMode)
        $State.Operation = $(if ($State.OperationBox -and $State.OperationBox.SelectedIndex -eq 1) { 'Uninstall' } elseif ($State.Mode -eq 'Uninstall') { 'Uninstall' } else { 'Install' })
        $State.ConfirmButton.Text = Get-JobsPanelText $(if ($State.Operation -eq 'Uninstall') { '卸载所选' } else { '安装 / 更新' }) (Get-JobsPanelLanguage $State)
        foreach ($check in $State.Checks) { $check.Enabled = $State.Operation -ne 'Uninstall' -or [string]$check.Tag -in $State.Installed }
        & $State.Refresh
        Set-JobsFeatureStatusText $State $messageWithProgress
    }
    $level = 'error'
    if ($Success) { $level = 'success' }
    if ($null -ne $State.PSObject.Properties['Stopped'] -and $State.Stopped) { $level = 'warning' }
    Add-JobsManagementLog $State ($messageWithProgress + ' 日志：' + $State.LogPath) -Level $level
}

function Read-JobsManagementOutput {
    param($State)
    try {
        # 单次限量以便大量编译输出时仍及时响应复制和拖动。
        for ($index = 0; $index -lt 300; $index++) {
            $chunk = $State.Pump.Take()
            if ($null -eq $chunk) { break }
            $line = $chunk.Text
            if ($chunk.IsEvent -and $line.StartsWith('@@JOBS-MANAGER@@')) {
                try {
                    $event = $line.Substring(16) | ConvertFrom-Json
                    if ($event.State -eq 'Stopped') { $State.Stopped = $true; continue }
                    if ($event.State -ne 'Finished') { Set-JobsManagementFeatureState $State @($event.FeatureIds) $event.State $event.Message }
                    $level = Get-JobsManagementLogLevel $event.State $event.Message $State.FeatureStates
                    Add-JobsManagementLog $State $event.Message -Level $level
                } catch { Add-JobsManagementLog $State $line }
            } else {
                $channel = 'output'
                if ($null -ne $chunk.PSObject.Properties['IsError'] -and $chunk.IsError) { $channel = 'error' }
                Add-JobsManagementLog $State $line -NoNewline -Channel $channel
            }
        }
        if ($State.Pump.Process.HasExited -and $State.Pump.Drained -and $State.Pump.Lines.IsEmpty) {
            $success = $State.Pump.Process.ExitCode -eq 0 -and @($State.FeatureStates.Values | Where-Object { $_ -cnotin @('Succeeded', 'NotInstalled') }).Count -eq 0
            $message = '部分功能处理失败；其它所选功能已继续处理。点击失败状态查看完整会话日志。'
            if ($success) { $message = '全部处理完成；可选择复制日志，或关闭面板。' }
            if ($null -ne $State.PSObject.Properties['Stopped'] -and $State.Stopped) { $message = '已停止安装；当前包事务已结束，未开始项目显示未执行。' }
            $message += ' 退出码：' + $State.Pump.Process.ExitCode + '。'
            Complete-JobsManagementRun $State $success $message
        }
    } catch {
        # 日志/面板错误也保持进程生命周期，不能在事务仍运行时放开关闭。
        Set-JobsFeatureStatusText $State ('读取日志失败：' + $_.Exception.Message)
        if ($State.Pump.Process.HasExited) { Complete-JobsManagementRun $State $false $State.StatusLabel.Text }
    }
}

# 停止只发出请求，等待当前包事务提交或回滚；不终止子进程。
function Request-JobsManagementStop {
    param($State)
    if (-not $State.Running -or $State.Operation -ne 'Install' -or $State.StopRequested -or [string]::IsNullOrWhiteSpace($State.StopRequestPath)) { return }
    [IO.File]::WriteAllText($State.StopRequestPath, 'stop-after-current-package', (New-Object Text.UTF8Encoding($false)))
    $State.StopRequested = $true
    $State.ConfirmButton.Enabled = $false
    $State.ConfirmButton.Text = Get-JobsPanelText '等待停止…' (Get-JobsPanelLanguage $State)
    Add-JobsManagementLog $State '已请求停止安装；当前包事务继续完成，随后不再开始其它包。' -Level warning
    Update-JobsManagementProgress $State
}
# 当前路线独立读取状态，不能让 installed 的选择掩盖 build 路线。
function Get-JobsManagementRouteInstalled {
    param([object[]]$Packages, [ValidateSet('installed', 'build')][string]$DeploymentMode = 'installed')
    $seen = @{}
    foreach ($feature in $Packages) {
        if ($null -eq $feature.PSObject.Properties['PackagePath']) { continue }
        $path = [string]$feature.PackagePath
        if ($seen.ContainsKey($path)) { continue }
        $seen[$path] = $true
        try {
            $module = Import-Module (Join-Path $path 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
            $current = & $module { param($Path, $Route) Get-JobsPackageState -PackagePath $Path -DeploymentMode $Route } $path $DeploymentMode
            if ($current.Enabled) {
                if ($current.Id -eq 'flutter-tools') {
                    if ($null -ne $feature.PSObject.Properties['LocalActions'] -and $feature.LocalActions) { $current.ActionIds }
                    else { $current.ActionIds | ForEach-Object { 'flutter-' + $_ } }
                }
                else { $current.Id }
            }
        } catch { Write-Warning ('当前路线状态不可读：' + $path + '；' + $_.Exception.Message) }
    }
}

function Start-JobsManagementRun {
    param($State, $Choice)
    if ($State.Running -or $State.Started) { return }
    $State.Operation = $Choice.Mode
    $clock = Get-JobsManagementClock $State
    $clock.Restart()
    if ($null -eq $Choice.PSObject.Properties['DeploymentMode']) { $Choice | Add-Member -NotePropertyName DeploymentMode -NotePropertyValue 'installed' }
    if ($null -eq $Choice.PSObject.Properties['AutoCleanup']) { $Choice | Add-Member -NotePropertyName AutoCleanup -NotePropertyValue $false }
    try { $plan = @(& $State.BuildPlan $Choice) }
    catch { Complete-JobsManagementRun $State $false ('无法建立操作计划：' + $_.Exception.Message); return }
    if ($plan.Count -eq 0) {
        $clock.Stop()
        Add-JobsManagementLog $State '没有需要处理的功能；未更改任何配置。'
        $clockLabel = '安装总用时'
        if ($State.Operation -eq 'Uninstall') { $clockLabel = '卸载总用时' }
    if ($State.Operation -eq 'Cleanup') { $clockLabel = '清理总用时' }
        Set-JobsFeatureStatusText $State ('没有需要处理的功能；' + $clockLabel + ' ' + (Format-JobsManagementElapsedTime $clock.Elapsed))
        return
    }
    $State.FeatureStates.Clear()
    if ($null -eq $State.PSObject.Properties['FeatureOperations']) { $State | Add-Member -NotePropertyName FeatureOperations -NotePropertyValue @{} }
    $State.FeatureOperations.Clear()
    $State.StopRequested = $false
    $State.Stopped = $false
    $State.Started = $true
    $State.Running = $true
    $State.CancelButton.Enabled = $true
    if ($null -ne $State.PSObject.Properties['CancelText']) { $State.CancelText = '退到系统托盘' }
    $State.CancelButton.Text = Get-JobsPanelText '退到系统托盘' (Get-JobsPanelLanguage $State)
    $State.Form.CancelButton = $State.CancelButton
    $State.Form.AcceptButton = $null
    $State.ConfirmButton.Enabled = $State.Operation -eq 'Install'
    if ($State.Operation -eq 'Install') { $State.ConfirmButton.Text = Get-JobsPanelText '停止安装' (Get-JobsPanelLanguage $State) }
    $State.RouteBox.Enabled = $false
    $State.AutoCleanup.Enabled = $false
    $State.CleanupButton.Enabled = $false
    $State.SelectAllButton.Enabled = $false
    $State.ClearButton.Enabled = $false
    if ($State.OperationBox) { $State.OperationBox.Enabled = $false }
    foreach ($check in $State.Checks) { $check.Enabled = $false }
    foreach ($group in $State.Groups) { $group.All.Enabled = $false; $group.None.Enabled = $false }
    foreach ($operation in $plan) {
        foreach ($id in @($operation.FeatureIds)) { $State.FeatureStates[$id] = 'Pending'; $State.FeatureOperations[$id] = [string]$operation.Mode }
    }
    $State.Progress.Maximum = [Math]::Max(1, $State.FeatureStates.Count)
    Set-JobsManagementFeatureState $State @($State.FeatureStates.Keys) Pending '等待处理。'
    Add-JobsManagementLog $State ('开始执行：' + $Choice.Mode + '；进程输出将在此实时显示。')
    try {
        Initialize-JobsManagementProcess
        $State.RequestPath = Join-Path ([IO.Path]::GetTempPath()) ('JobsExtensionPlan-' + [guid]::NewGuid().ToString('N') + '.json')
        $State.StopRequestPath = $State.RequestPath + '.stop'
        $request = [ordered]@{ Plan = @($plan); DeploymentMode = $Choice.DeploymentMode; AutoCleanup = [bool]$Choice.AutoCleanup; StopRequestPath = $State.StopRequestPath }
        [IO.File]::WriteAllText($State.RequestPath, (ConvertTo-Json -InputObject $request -Depth 8), (New-Object Text.UTF8Encoding($false)))
        $start = New-Object Diagnostics.ProcessStartInfo
        $start.FileName = Join-Path $PSHOME 'powershell.exe'
        # -File 参数只包含两个本地文件路径，拒绝命令行引号/换行，避免解释用户选择为代码。
        if (($State.WorkerPath + $State.RequestPath) -match '["\r\n]') { throw '后台脚本路径包含不支持的字符。' }
        $start.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $State.WorkerPath + '" -RequestPath "' + $State.RequestPath + '"'
        $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
        $start.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
        $start.EnvironmentVariables['JOBS_MANAGEMENT_GUI'] = '1'
        $State.Pump = New-Object JobsManagement.OutputPump
        $State.Pump.Start($start)
        $State.Timer.Start()
    } catch { Complete-JobsManagementRun $State $false ('无法开始执行：' + $_.Exception.Message) }
}

function Invoke-JobsManagementNativeProcess {
    param([Diagnostics.ProcessStartInfo]$StartInfo, [int]$TimeoutMilliseconds = 120000)
    Initialize-JobsManagementProcess
    $pump = New-Object JobsManagement.OutputPump
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        $pump.Start($StartInfo)
        do {
            while ($null -ne ($chunk = $pump.Take())) { [Console]::Out.Write($chunk.Text); [Console]::Out.Flush() }
            if ($clock.ElapsedMilliseconds -gt $TimeoutMilliseconds) {
                if (-not $pump.Process.HasExited) { $pump.Process.Kill() }
                throw '原生菜单编译超时。'
            }
            [void]$pump.Process.WaitForExit(50)
        } until ($pump.Process.HasExited -and $pump.Drained -and $pump.Lines.IsEmpty)
        return $pump.Process.ExitCode
    } finally { $pump.Dispose() }
}

Export-ModuleMember -Function Get-JobsPanelDefaultGroupLayout, Get-JobsPanelGroupLayoutPath, Read-JobsPanelGroupLayout, Save-JobsPanelGroupLayout, Move-JobsPanelGroup, Set-JobsPanelGroupLayout, Get-JobsPanelGroupDrop, Get-JobsPanelDeploymentRowLayout, Get-JobsPanelHeaderLayout, Set-JobsPanelHeaderLayout, Get-JobsPanelText, Get-JobsPanelLanguage, Update-JobsPanelPresentation, Save-JobsPanelPreferences, Read-JobsPanelPreferences, Resolve-JobsPanelLanguage, Resolve-JobsPanelTheme, Request-JobsManagementStop, Get-JobsManagementRouteInstalled, Open-JobsManagementLog, Show-JobsFeatureSelection, Get-JobsFeatureSelectionLayout, Get-JobsFeatureContentLayout, Set-JobsFeatureStatusText, Initialize-JobsManagementProcess, Start-JobsManagementRun, Read-JobsManagementOutput, Add-JobsManagementLog, Set-JobsManagementFeatureState, Complete-JobsManagementRun, Invoke-JobsManagementNativeProcess

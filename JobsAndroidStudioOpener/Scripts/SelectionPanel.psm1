# Installer.psm1 | WindowsOS@Extension 组合选择面板
# Created by Jobs on 2026年10月18日，星期日.
# 面板内后台执行安装事务，实时显示逐项状态和可复制日志；预览、取消不部署。
Set-StrictMode -Version 2.0

# 三语文本随模块分发，独立包无需访问源码仓库或在线翻译服务。
$script:PanelTranslations = @{}
$panelTextData = @'
{
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
  "🔒 运行授权" : [
    "🔒 運行授權",
    "🔒 Grant execution permission"
  ],
  "🔓 解除运行授权" : [
    "🔓 解除運行授權",
    "🔓 Revoke execution permission"
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
    @{ Pattern = '^(.*) 退出码：(-?\d+)。$'; Text = @('{0} 退出碼：{1}。', '{0} Exit code: {1}.') },
    @{ Pattern = '^(已请求停止安装；等待当前包事务结束，后续项目不再执行。) (.*)$'; Text = @('{0} {1}', '{0} {1}') },
    @{ Pattern = '^(没有需要处理的功能；)(安装总用时|卸载总用时|清理总用时) (\d+:\d+:\d+)$'; Text = @('{0}{1} {2}', '{0}{1} {2}') },
    @{ Pattern = '^已选 (\d+) / (\d+) 项；关闭或取消窗口不执行操作。$'; Text = @('已選 {0} / {1} 項；關閉或取消視窗不執行操作。', 'Selected {0} / {1}. Closing or cancelling makes no changes.') },
    @{ Pattern = '^已选 (\d+) / (\d+)$'; Text = @('已選 {0} / {1}', 'Selected {0} / {1}') },
    @{ Pattern = '^(安装 / 更新|卸载|清理)中；已处理 (\d+) / (\d+) 项（([\d.]+)%，按完成项计数）；(安装用时|卸载用时|清理用时) (\d+:\d+:\d+)$'; Text = @('{0}中；已處理 {1} / {2} 項（{3}%，按完成項計數）；{4} {5}', '{0} in progress; completed {1} / {2} ({3}% by completed items); {4} {5}') },
    @{ Pattern = '^(.*) 已处理 (\d+) / (\d+) 项（([\d.]+)%，按完成项计数）；(安装总用时|卸载总用时|清理总用时) (\d+:\d+:\d+)$'; Text = @('{0} 已處理 {1} / {2} 項（{3}%，按完成項計數）；{4} {5}', '{0} Completed {1} / {2} ({3}% by completed items); {4} {5}') }
)

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
            if ($null -ne $data.PSObject.Properties['Language'] -and $data.Language -cin @('system', 'zh-Hans', 'zh-Hant', 'en')) { $result.Language = [string]$data.Language }
        }
    } catch { $result.Error = $_.Exception.Message }
    return $result
}
# 同目录临时文件原子提交；失败保留旧偏好并由调用者显示原因。
function Save-JobsPanelPreferences {
    param([string]$Theme, [string]$Language, [string]$Path)
    if ($Theme -cnotin @('system', 'dark', 'light') -or $Language -cnotin @('system', 'zh-Hans', 'zh-Hant', 'en')) { throw 'Invalid panel preference.' }
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
    if ($Preference -cin @('zh-Hans', 'zh-Hant', 'en')) { return $Preference }
    if ([string]::IsNullOrWhiteSpace($SystemLanguage)) {
        $SystemLanguage = [Globalization.CultureInfo]::CurrentUICulture.Name
        if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
            try { $SystemLanguage = [Globalization.CultureInfo]::GetCultureInfo([JobsPanelNative]::GetUserDefaultUILanguage()).Name } catch { }
        }
    }
    if ($SystemLanguage -match '^zh[-_](Hant|TW|HK|MO)([-_]|$)') { return 'zh-Hant' }
    if ($SystemLanguage -match '^zh($|[-_])') { return 'zh-Hans' }
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
    if ($script:PanelTranslations.ContainsKey($Text)) { return [string]$script:PanelTranslations[$Text][$index] }
    # 动态计数和计时共用模板，数值/路径/外部错误消息不会被当成翻译键。
    foreach ($rule in $script:PanelTextPatterns) {
        $match = [regex]::Match($Text, $rule.Pattern)
        if (-not $match.Success) { continue }
        $values = @()
        for ($i = 1; $i -lt $match.Groups.Count; $i++) { $values += Get-JobsPanelText $match.Groups[$i].Value $Language }
        return ([string]$rule.Text[$index] -f $values)
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
    if ($Control -isnot [Windows.Forms.ComboBox] -and $Control.Text -and $Control -notin $excluded) {
        $State.TextBindings.Add([pscustomobject]@{ Control = $Control; Source = [string]$Control.Text })
    }
    $tip = $State.ToolTip.GetToolTip($Control)
    if ($tip) { $State.ToolTipBindings.Add([pscustomobject]@{ Control = $Control; Source = $tip }) }
    foreach ($child in $Control.Controls) { Add-JobsPanelTextBindings $child $State }
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
    $groupGap = [int][Math]::Ceiling(16 * $Scale)
    $available = $Width - 2 * $Padding
    $themeWidth = $ThemeLabelWidth + $gap + $ChoiceWidth
    $languageWidth = $LanguageLabelWidth + $gap + $ChoiceWidth
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
        ThemeLabelLeft = $themeLeft; ThemeChoiceLeft = $themeLeft + $ThemeLabelWidth + $gap
        LanguageLabelLeft = $languageLeft; LanguageChoiceLeft = $languageLeft + $LanguageLabelWidth + $gap; LanguageTop = $languageTop
        TitleTop = $titleTop; TitleWidth = $titleArea
        DetailsTop = [Math]::Max($titleTop + $TitleHeight, $preferenceTop + $panelHeight) + $gap
    }
}
# 部署位置和清理控件保持一行；窄窗仅横向滚动，不截短标题或相互覆盖。
function Get-JobsPanelDeploymentRowLayout {
    param(
        [int]$AvailableWidth, [double]$Scale = 1, [bool]$CleanupVisible = $true,
        [int]$RouteWidth, [int]$RouteHeight, [int]$AutoCleanupWidth, [int]$AutoCleanupHeight,
        [int]$CleanupButtonWidth, [int]$CleanupButtonHeight
    )
    $gap = [int][Math]::Ceiling(12 * $Scale)
    $sideWidth = 0
    if ($CleanupVisible) { $sideWidth = $AutoCleanupWidth + $gap + $CleanupButtonWidth }
    $actualRouteWidth = [int][Math]::Max($RouteWidth, $AvailableWidth - $sideWidth - $(if ($CleanupVisible) { $gap } else { 0 }))
    $contentWidth = $actualRouteWidth + $sideWidth + $(if ($CleanupVisible) { $gap } else { 0 })
    $rowHeight = $RouteHeight
    if ($CleanupVisible) { $rowHeight = [int][Math]::Max($rowHeight, [Math]::Max($AutoCleanupHeight, $CleanupButtonHeight)) }
    return [pscustomobject]@{
        ContentWidth = $contentWidth; RowHeight = $rowHeight; ScrollRequired = $contentWidth -gt $AvailableWidth
        RouteWidth = $actualRouteWidth; RouteTop = [int][Math]::Floor(($rowHeight - $RouteHeight) / 2.0)
        CleanupLeft = $actualRouteWidth + $gap; CleanupWidth = $sideWidth
        AutoCleanupTop = [int][Math]::Floor(($rowHeight - $AutoCleanupHeight) / 2.0)
        CleanupButtonLeft = $AutoCleanupWidth + $gap; CleanupButtonTop = [int][Math]::Floor(($rowHeight - $CleanupButtonHeight) / 2.0)
    }
}
# 按当前语言实测完整文案，位置下拉、复选框和按钮共用垂直中心线。
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
    $State.CleanupButton.SetBounds($layout.CleanupButtonLeft, $layout.CleanupButtonTop, $buttonWidth, $buttonHeight)
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
    $choiceWidth = [int][Math]::Ceiling(110 * $scale)
    foreach ($text in @($State.ThemeBox.Items) + @($State.LanguageBox.Items)) {
        $choiceWidth = [int][Math]::Max($choiceWidth, (Measure-JobsFeatureText ([string]$text) $State.Font).Width + 32 * $scale)
    }
    $controlHeight = [Math]::Max($State.ThemeBox.PreferredHeight, $State.LanguageBox.PreferredHeight)
    $title = Measure-JobsFeatureText $State.HeaderLabel.Text $State.Font
    $layout = Get-JobsPanelHeaderLayout -Width $width -Padding $padding -Scale $scale -TitleWidth $title.Width -TitleHeight $title.Height -ThemeLabelWidth $themeWidth -LanguageLabelWidth $languageWidth -ChoiceWidth $choiceWidth -ControlHeight $controlHeight
    $State.PreferencePanel.SetBounds($layout.PreferenceLeft, $layout.PreferenceTop, $layout.PreferenceWidth, $layout.PreferenceHeight)
    $State.ThemeLabel.SetBounds($layout.ThemeLabelLeft, 0, $themeWidth, $controlHeight)
    $State.ThemeBox.SetBounds($layout.ThemeChoiceLeft, 0, $choiceWidth, $controlHeight)
    $State.LanguageLabel.SetBounds($layout.LanguageLabelLeft, $layout.LanguageTop, $languageWidth, $controlHeight)
    $State.LanguageBox.SetBounds($layout.LanguageChoiceLeft, $layout.LanguageTop, $choiceWidth, $controlHeight)
    $State.HeaderLabel.SetBounds($padding, $layout.TitleTop, $layout.TitleWidth, $title.Height)
    $detailsWidth = $width - 2 * $padding
    $detailsHeight = $State.HeaderDetailsLabel.GetPreferredSize((New-Object Drawing.Size($detailsWidth, 0))).Height
    $State.HeaderDetailsLabel.SetBounds($padding, $layout.DetailsTop, $detailsWidth, $detailsHeight)
    $next = $State.HeaderDetailsLabel.Bottom + [int](8 * $scale)
    if ($State.OperationBox) {
        $State.OperationBox.Top = $next
        $State.OperationBox.Width = [int][Math]::Min($detailsWidth, (Measure-JobsFeatureText (Get-JobsPanelText '安装 / 更新所选功能' $State.Language) $State.Font).Width + 40 * $scale)
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
    if (-not $Force -and $State.Language -ceq $language -and $State.Theme -ceq $theme) { return }
    $State.Language = $language; $State.Theme = $theme; $State.PreferenceUpdating = $true
    $State.Form.SuspendLayout()
    try {
        foreach ($binding in $State.TextBindings) { $binding.Control.Text = Get-JobsPanelText $binding.Source $language }
        foreach ($binding in $State.ToolTipBindings) { $State.ToolTip.SetToolTip($binding.Control, (Get-JobsPanelText $binding.Source $language)) }
        $State.CopySelectionItem.Text = Get-JobsPanelText '复制' $language
        $State.SelectLogItem.Text = Get-JobsPanelText '全选' $language
        $State.ThemeBox.Items[0] = Get-JobsPanelText '黑夜' $language
        $State.ThemeBox.Items[1] = Get-JobsPanelText '白天' $language
        $State.ThemeBox.Items[2] = Get-JobsPanelText '跟随系统' $language
        $State.LanguageBox.Items[3] = Get-JobsPanelText '跟随系统' $language
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
        foreach ($group in $State.Groups) {
            $count = @($group.Checks | Where-Object { $_.Checked }).Count
            $group.Counter.Text = (Get-JobsPanelText '已选 {0} / {1}' $language) -f $count, $group.Checks.Count
            foreach ($button in @($group.All, $group.None)) { $button.Width = [int][Math]::Max(74 * $State.Scale, (Measure-JobsFeatureText $button.Text $State.Font).Width + 16 * $State.Scale) }
            $group.None.Left = $group.All.Right + [int](6 * $State.Scale)
            $group.Counter.Left = $group.None.Right + [int](6 * $State.Scale)
            $group.Counter.Width = (Measure-JobsFeatureText ((Get-JobsPanelText '已选 {0} / {1}' $language) -f $group.Checks.Count, $group.Checks.Count) $State.Font).Width + [int](8 * $State.Scale)
            $statusWidth = 0
            foreach ($text in @('未安装', '已安装', '等待中', '正在安装 / 更新…', '正在卸载…', '正在清理…', '✅ 安装成功', '已完成', '失败，见日志', '未执行')) {
                $statusWidth = [Math]::Max($statusWidth, (Measure-JobsFeatureText (Get-JobsPanelText $text $language) $State.Font).Width + 10 * $State.Scale)
            }
            $top = [int][Math]::Max(66 * $State.Scale, [Math]::Max($group.All.Bottom, $group.Counter.Bottom) + 8 * $State.Scale)
            foreach ($check in $group.Checks) {
                $label = $State.FeatureLabels[[string]$check.Tag]
                $source = $(if ([string]$check.Tag -in $State.Installed) { '已安装' } else { '未安装' })
                if ($State.FeatureStatusSources.ContainsKey([string]$check.Tag)) { $source = $State.FeatureStatusSources[[string]$check.Tag] }
                $label.Text = Get-JobsPanelText $source $language
                if ($State.FeatureMessages.ContainsKey([string]$check.Tag)) { Set-JobsPanelFeatureToolTip $State ([string]$check.Tag) $State.FeatureMessages[[string]$check.Tag] }
                if ($State.FeatureStates.ContainsKey([string]$check.Tag) -and $State.FeatureStates[[string]$check.Tag] -eq 'Failed') { $label.LinkArea = New-Object Windows.Forms.LinkArea(0, $label.Text.Length) }
                $label.Width = $statusWidth; $label.Left = $group.Box.ClientSize.Width - $statusWidth - [int](8 * $State.Scale)
                $check.Width = $label.Left - $check.Left - [int](8 * $State.Scale)
                $height = [int][Math]::Max(34 * $State.Scale, (Measure-JobsFeatureText $check.Text $State.Font ([Math]::Max(1, $check.Width - 26 * $State.Scale))).Height + 8 * $State.Scale)
                $height = [int][Math]::Max($height, (Measure-JobsFeatureText $label.Text $State.Font $label.Width).Height + 8 * $State.Scale)
                $check.Top = $top; $label.Top = $top; $check.Height = $height; $label.Height = $height; $top += $height
            }
            $group.Box.Height = $top + [int](10 * $State.Scale)
        }
        foreach ($button in @($State.SelectAllButton, $State.ClearButton, $State.ConfirmButton, $State.CancelButton)) {
            $button.Width = [int][Math]::Max(104 * $State.Scale, (Measure-JobsFeatureText $button.Text $State.Font).Width + 24 * $State.Scale)
        }
        Set-JobsPanelHeaderLayout $State
        Set-JobsFeatureStatusText $State $State.StatusSource
        Set-JobsPanelControlTheme $State.Form $State
        $State.LogMenu.BackColor = $State.Form.BackColor; $State.LogMenu.ForeColor = $State.Form.ForeColor
        foreach ($item in $State.LogMenu.Items) { $item.BackColor = $State.Form.BackColor; $item.ForeColor = $State.Form.ForeColor }
        # RichTextBox 的旧文字已有颜色，整段重着色并恢复选择，不清空已有日志。
        $start = $State.LogView.SelectionStart; $length = $State.LogView.SelectionLength
        $State.LogView.SelectAll(); $State.LogView.SelectionColor = $State.LogView.ForeColor
        $State.LogView.Select($start, $length)
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
        $button.Width = [int][Math]::Max(104 * $scale, (Measure-JobsFeatureText $button.Text $State.Font).Width + 24 * $scale)
        $button.Top = $buttonsTop
    }
    $State.SelectAllButton.Left = $padding
    $State.ClearButton.Left = $State.SelectAllButton.Right + $gap
    $State.CancelButton.Left = $State.Form.ClientSize.Width - $padding - $State.CancelButton.Width
    $State.ConfirmButton.Left = $State.CancelButton.Left - $gap - $State.ConfirmButton.Width
    if ($State.ClearButton.Right + $gap -gt $State.ConfirmButton.Left) {
        $State.ConfirmButton.Top = $State.ClearButton.Bottom + $gap
        $State.CancelButton.Top = $State.ConfirmButton.Top
    }
    $State.Footer.Height = $State.CancelButton.Bottom + [int](20 * $scale)
    $State.Layout.FooterHeight = $State.Footer.Height
    if ($null -ne $State.PSObject.Properties['PreferredHeaderHeight']) {
        $maximumHeader = $State.Form.ClientSize.Height - $State.Footer.Height - $State.Layout.RowHeight - $State.LogToolbar.Height - [int](60 * $scale) - $State.LogSplit.SplitterWidth
        $State.Header.AutoScroll = $State.PreferredHeaderHeight -gt $maximumHeader
        $State.Header.Height = [int][Math]::Min($State.PreferredHeaderHeight, [Math]::Max(48 * $scale, $maximumHeader))
        $State.Form.PerformLayout()
    }
    Set-JobsManagementLogLayout $State
}

# 完成项包含成功与失败；未执行项不计进度，避免把异常结束显示为全部完成。
function Get-JobsManagementProgress {
    param($State)
    $finished = @($State.FeatureStates.Values | Where-Object { $_ -eq 'Succeeded' -or $_ -eq 'Failed' }).Count
    $total = $State.FeatureStates.Count
    $percent = 0.0
    if ($total -gt 0) { $percent = 100.0 * $finished / $total }
    return [pscustomobject]@{ Finished = $finished; Total = $total; Percent = $percent.ToString('F1', [Globalization.CultureInfo]::InvariantCulture) }
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
        $form.Text = 'Jobs Windows · 安装资源管理器扩展'
        $action = '安装'
        $description = '勾选需要安装的子功能；已启用的兄弟动作与其它未选功能保留。'
        if ($Mode -eq 'Manage') {
            $form.Text = 'Jobs Windows · 管理资源管理器扩展'
            $action = '安装 / 更新'
            $description = '选择操作并勾选一个或多个功能；未选功能保留。卸载只处理已安装项。'
        } elseif ($Mode -eq 'Configure') {
            $form.Text = 'Jobs Windows · 配置资源管理器扩展'
            $action = '保存配置'
            $description = '勾选安装，取消勾选卸载；全不选后保存将关闭全部已安装功能。'
        } elseif ($Mode -eq 'Uninstall') {
            $form.Text = 'Jobs Windows · 卸载资源管理器扩展'
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
            $titleWidth = [Math]::Max($titleWidth, (Measure-JobsFeatureText $feature.Label $font).Width + 26 * $scale)
            $groupTitleWidth = [Math]::Max($groupTitleWidth, (Measure-JobsFeatureText $groupName $font).Width + 20 * $scale)
        }
        foreach ($total in $groupTotals.Values) {
            foreach ($count in 0..$total) { $counterWidth = [Math]::Max($counterWidth, (Measure-JobsFeatureText ('已选 {0} / {1}' -f $count, $total) $font).Width + 4 * $scale) }
        }
        foreach ($text in @('未安装', '已安装', '等待中', '正在安装 / 更新…', '正在卸载…', '✅ 安装成功', '已完成', '失败，见日志', '未执行')) {
            $statusWidth = [Math]::Max($statusWidth, (Measure-JobsFeatureText $text $font).Width + 10 * $scale)
        }
        $statusWidth = [int][Math]::Max(90 * $scale, $statusWidth)
        $groupControlsWidth = [int][Math]::Ceiling($allButtonWidth + $noneButtonWidth + $counterWidth + 32 * $scale)
        $minimumPanelWidth = [int][Math]::Ceiling([Math]::Max($groupTitleWidth, [Math]::Max($groupControlsWidth, $titleWidth + $statusWidth + 28 * $scale)))
        $contentLayout = Get-JobsFeatureContentLayout -WorkingWidth $area.Width -PreferredColumns $layout.Columns -MinimumPanelWidth $minimumPanelWidth -MinimumCheckWidth ([int](120 * $scale)) -StatusWidth $statusWidth -GroupControlsWidth $groupControlsWidth -Scale $scale
        $layout.Columns = $contentLayout.Columns
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
        $languageBox.Width = [int](150 * $scale)
        [void]$languageBox.Items.AddRange(@('简体中文', '繁體中文', 'English', '跟随系统'))
        $languageBox.SelectedIndex = [array]::IndexOf(@('zh-Hans', 'zh-Hant', 'en', 'system'), $preferences.Language)
        $preferencePanel.Controls.AddRange(@($themeLabel, $themeBox, $languageLabel, $languageBox))
        $header.Controls.Add($preferencePanel)
        $headerLabel = New-Object System.Windows.Forms.Label
        $headerLabel.Font = $font
        $headerLabel.AutoEllipsis = $false
        $headerLabel.Text = "资源管理器右键扩展 · $action`r`n$description`r`n悬停查看功能说明；Windows 11：右键 → 显示更多选项。"

        if ($Mode -eq 'Manage') {
            $headerLabel.Text = "资源管理器扩展 · 管理`r`n勾选功能后确认；未选项保留。悬停可查看当前安装状态。"
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
        $cleanupPanel.Controls.AddRange(@($autoCleanup, $cleanupButton))
        $deploymentRow.Controls.Add($cleanupPanel)
        $cleanupPanel.Visible = $initialRoute -eq 'installed'
        $header.Height = $deploymentRow.Bottom + [int](12 * $scale)
        $toolTip.SetToolTip($routeBox, '从已部署副本打开时使用当前路线；切换部署位置请从源码目录的管理入口操作。默认模式在当前用户 LocalAppData 独立运行；临时模式登记本包 work 下的运行版本，移动源码目录后失效。')
        $toolTip.SetToolTip($cleanupButton, '只清理所选包专用编译工作区；保留已安装 DLL、运行脚本、配置和注册表。')
        $grid = New-Object System.Windows.Forms.FlowLayoutPanel
        $grid.Dock = 'Fill'
        $grid.Padding = New-Object System.Windows.Forms.Padding($padding, 0, $padding, 0)
        $grid.AutoScroll = $true
        $grid.WrapContents = $true
        $grid.FlowDirection = 'LeftToRight'
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
            $group = [pscustomobject]@{ Name = $groupName; Box = $box; Checks = @(); All = $all; None = $none; Counter = $counter; RowHeight = $rowHeight }
            foreach ($item in $items) { $groupForId[$item.Id] = $group }
            $groupStates += $group
            $grid.Controls.Add($box)
        }
        $checks = @()
        $featureLabels = @{}
        for ($index = 0; $index -lt $features.Count; $index++) {
            $feature = $features[$index]
            $check = New-Object System.Windows.Forms.CheckBox
            $check.Font = $font
            $check.Text = $feature.Label
            $check.Tag = $feature.Id
            $check.AutoEllipsis = $false
            $check.Margin = New-Object System.Windows.Forms.Padding(4, 0, 4, 0)
            $check.Checked = $feature.Id -in $Selected
            $installationStatus = '未安装'
            if ($feature.Id -in $Installed) { $installationStatus = '已安装' }
            $toolTip.SetToolTip($check, ($feature.Label + "`r`n" + $installationStatus + "`r`n" + $feature.Description))
            $group = $groupForId[$feature.Id]
            $check.SetBounds(([int](8 * $scale)), 0, $contentLayout.CheckWidth, $rowHeight)
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
            $wrappedHeight = (Measure-JobsFeatureText $check.Text $font ([Math]::Max(1, $check.Width - [int](26 * $scale)))).Height + [int](8 * $scale)
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
        $logView = New-Object System.Windows.Forms.RichTextBox
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
        $buttons[3].DialogResult = [System.Windows.Forms.DialogResult]::Cancel
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
            Header = $header; HeaderLabel = $headerLabel; HeaderDetailsLabel = $headerDetails; LogToolbar = $logToolbar; Padding = $padding; Scale = $scale
            Packages = @($Packages); RouteBox = $routeBox; DeploymentRow = $deploymentRow; DeploymentRowLayout = $null; CleanupPanel = $cleanupPanel; AutoCleanup = $autoCleanup; CleanupButton = $cleanupButton
            DeploymentMode = $initialRoute; DeploymentLocked = $deploymentLocked; StopRequestPath = $null; StopRequested = $false; Stopped = $false
            BuildPlan = $BuildPlan; WorkerPath = $WorkerPath; Running = $false; Started = $false
            FeatureLabels = $featureLabels; FeatureStates = @{}; Progress = $progress
            LogView = $logView; FollowLog = $followLog; CopyLogButton = $copyLog
            LogSplit = $logSplit; LogMenu = $logMenu; CopySelectionItem = $copySelection; SelectLogItem = $selectLog
            LogPath = (Join-Path ([IO.Path]::GetTempPath()) ('JobsExtensionManager-' + [guid]::NewGuid().ToString('N') + '.log'))
            Pump = $null; Timer = (New-Object Windows.Forms.Timer); RequestPath = $null
            RunClocks = @{ Install = (New-Object Diagnostics.Stopwatch); Uninstall = (New-Object Diagnostics.Stopwatch); Cleanup = (New-Object Diagnostics.Stopwatch) }
            Preview = [bool]$Preview; OperationBox = $operationBox; Operation = $(if ($Mode -eq 'Manage') { 'Install' } else { $Mode }); Installed = @($Installed)
        }
        # 闭包保留表单状态，事件不依赖已返回的构造函数局部作用域。
        $refresh = {
            if ($state.Running -or $state.Started) { return }
            $count = @($state.Checks | Where-Object { $_.Checked }).Count
            Set-JobsFeatureStatusText $state ('已选 {0} / {1} 项；关闭或取消窗口不执行操作。' -f $count, $state.Checks.Count)
            $state.ConfirmButton.Enabled = $count -gt 0 -or $state.Mode -eq 'Configure'
            $state.CleanupButton.Enabled = $count -gt 0 -and -not $state.Running -and $state.DeploymentMode -eq 'installed'
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
            $ids = @($state.Checks | Where-Object { $_.Checked } | ForEach-Object { [string]$_.Tag })
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
                catch { Add-JobsManagementLog $state ('无法建立操作计划：' + $_.Exception.Message) }
                return
            }
            $state.Form.Tag = $choice
            $state.Form.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $state.Form.Close()
        }.GetNewClosure())
        $routeBox.Add_SelectedIndexChanged({
            if ($state.PreferenceUpdating -or $state.Running -or $state.Started) { return }
            $state.DeploymentMode = 'installed'
            if ($state.RouteBox.SelectedIndex -eq 1) { $state.DeploymentMode = 'build' }
            $state.CleanupPanel.Visible = $state.DeploymentMode -eq 'installed'
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
            $ids = @($state.Checks | Where-Object { $_.Checked } | ForEach-Object { [string]$_.Tag })
            if ($ids.Count -eq 0) { return }
            $choice = [pscustomobject]@{ Features = $ids; Mode = 'Cleanup'; DeploymentMode = 'installed'; AutoCleanup = $false }
            if ($state.Preview) { Add-JobsManagementLog $state ('仅预览清理：' + ($ids -join ', ')); return }
            Start-JobsManagementRun $state $choice
        }.GetNewClosure())
        if ($operationBox) {
            $operationBox.Add_SelectedIndexChanged({
                if ($state.PreferenceUpdating) { return }
                $state.Operation = 'Install'
                $state.ConfirmButton.Text = Get-JobsPanelText '安装 / 更新' $state.Language
                if ($state.OperationBox.SelectedIndex -eq 1) {
                    $state.Operation = 'Uninstall'
                    $state.ConfirmButton.Text = Get-JobsPanelText '卸载所选' $state.Language
                }
                if ($state.Preview) { $state.ConfirmButton.Text = Get-JobsPanelText '返回选择' $state.Language }
                foreach ($check in $state.Checks) {
                    $check.Checked = $false
                    $check.Enabled = $state.Operation -ne 'Uninstall' -or [string]$check.Tag -in $state.Installed
                }
                & $refresh
            }.GetNewClosure())
        }
        $state.Timer.Interval = 100
        $state.Timer.Add_Tick((New-JobsManagementTimerCallback $state))
        $form.Add_FormClosing({
            param($sender, $eventArgs)
            if ($state.Running) {
                $eventArgs.Cancel = $true
                Set-JobsFeatureStatusText $state '操作正在执行，请等待事务完成后关闭；下方日志可随时复制。'
            }
        }.GetNewClosure())
        $copySelection.Add_Click({ $state.LogView.Copy() }.GetNewClosure())
        $selectLog.Add_Click({
            [void]$state.LogView.Focus()
            $state.LogView.SelectAll()
        }.GetNewClosure())
        $logMenu.Add_Opening({
            $state.CopySelectionItem.Enabled = $state.LogView.SelectionLength -gt 0
            $state.SelectLogItem.Enabled = $state.LogView.TextLength -gt 0
        }.GetNewClosure())
        $logView.Add_KeyDown({
            param($sender, $eventArgs)
            if ($eventArgs.Control -and -not $eventArgs.Alt -and $eventArgs.KeyCode -eq [Windows.Forms.Keys]::A) {
                $sender.SelectAll()
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
            $state.Preferences.Language = @('zh-Hans', 'zh-Hant', 'en', 'system')[$state.LanguageBox.SelectedIndex]
            Update-JobsPanelPresentation $state -Force
            try { Save-JobsPanelPreferences -Theme $state.Preferences.Theme -Language $state.Preferences.Language -Path $state.PreferencesPath }
            catch { Set-JobsFeatureStatusText $state ('保存偏好失败：' + $_.Exception.Message) }
        }.GetNewClosure()
        $themeBox.Add_SelectedIndexChanged($preferenceChanged)
        $languageBox.Add_SelectedIndexChanged($preferenceChanged)
        $state.PreferenceTimer.Interval = 1000
        $state.PreferenceTimer.Add_Tick({ Update-JobsPanelPresentation $state }.GetNewClosure())
        $form.Add_Shown({ Update-JobsPanelPresentation $state -Force; $state.PreferenceTimer.Start() }.GetNewClosure())
        $form.Add_Disposed({ $state.PreferenceTimer.Stop(); $state.PreferenceTimer.Dispose() }.GetNewClosure())
        $form.Add_ClientSizeChanged({
            if ($state.HeaderLayoutUpdating -or $state.Form.IsDisposed) { return }
            $state.HeaderLayoutUpdating = $true
            try {
                Set-JobsPanelHeaderLayout $state
                Set-JobsFeatureStatusText $state $state.StatusSource
            } finally { $state.HeaderLayoutUpdating = $false }
        }.GetNewClosure())
        Update-JobsPanelPresentation $state -Force
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
        if ($state.Form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
        return $state.Form.Tag
    } finally {
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
        public OutputChunk(string text, bool isEvent) { Text = text; IsEvent = isEvent; }
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
                            Lines.Enqueue(new OutputChunk(marker ? line.TrimEnd('\r', '\n') : line, marker));
                            pending = pending.Substring(newline + 1);
                            atLineStart = true;
                        } else {
                            Lines.Enqueue(new OutputChunk(pending, false));
                            pending = "";
                            atLineStart = false;
                        }
                    }
                }
                if (pending.Length > 0) Lines.Enqueue(new OutputChunk(pending, events && atLineStart && pending.StartsWith(Marker, StringComparison.Ordinal)));
            } catch (Exception error) {
                Lines.Enqueue(new OutputChunk("\n读取后台输出失败：" + error.Message + "\n", false));
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

function Add-JobsManagementLog {
    param($State, [string]$Text, [switch]$NoNewline)
    # 环形显示控制内存，完整输出追加到本次独立日志文件。
    $ending = [Environment]::NewLine
    if ($NoNewline) { $ending = '' }
    $clean = [regex]::Replace($Text, "\x1b\[[0-?]*[ -/]*[@-~]", '')
    [IO.File]::AppendAllText($State.LogPath, $clean + $ending, (New-Object Text.UTF8Encoding($false)))
    $view = $State.LogView
    $start = $view.SelectionStart
    $length = $view.SelectionLength
    if ($view.TextLength -gt 1000000 -and $length -eq 0) { $view.Text = $view.Text.Substring($view.TextLength - 700000) }
    $view.AppendText($clean + $ending)
    if ($State.FollowLog.Checked -and $length -eq 0) {
        $view.SelectionStart = $view.TextLength
        $view.ScrollToCaret()
    } else {
        $view.SelectionStart = [Math]::Min($start, $view.TextLength)
        $view.SelectionLength = [Math]::Min($length, $view.TextLength - $view.SelectionStart)
    }
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
    Add-JobsManagementLog $State ($messageWithProgress + ' 日志：' + $State.LogPath)
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
                    Add-JobsManagementLog $State $event.Message
                } catch { Add-JobsManagementLog $State $line }
            } else { Add-JobsManagementLog $State $line -NoNewline }
        }
        if ($State.Pump.Process.HasExited -and $State.Pump.Drained -and $State.Pump.Lines.IsEmpty) {
            $success = $State.Pump.Process.ExitCode -eq 0 -and @($State.FeatureStates.Values | Where-Object { $_ -ne 'Succeeded' }).Count -eq 0
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
    Add-JobsManagementLog $State '已请求停止安装；当前包事务继续完成，随后不再开始其它包。'
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
    $State.StopRequested = $false
    $State.Stopped = $false
    $State.Started = $true
    $State.Running = $true
    $State.CancelButton.Enabled = $false
    $State.Form.CancelButton = $null
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
        foreach ($id in @($operation.FeatureIds)) { $State.FeatureStates[$id] = 'Pending' }
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

Export-ModuleMember -Function Get-JobsPanelDeploymentRowLayout, Get-JobsPanelHeaderLayout, Set-JobsPanelHeaderLayout, Get-JobsPanelText, Get-JobsPanelLanguage, Update-JobsPanelPresentation, Save-JobsPanelPreferences, Read-JobsPanelPreferences, Resolve-JobsPanelLanguage, Resolve-JobsPanelTheme, Request-JobsManagementStop, Get-JobsManagementRouteInstalled, Open-JobsManagementLog, Show-JobsFeatureSelection, Get-JobsFeatureSelectionLayout, Get-JobsFeatureContentLayout, Set-JobsFeatureStatusText, Initialize-JobsManagementProcess, Start-JobsManagementRun, Read-JobsManagementOutput, Add-JobsManagementLog, Set-JobsManagementFeatureState, Complete-JobsManagementRun, Invoke-JobsManagementNativeProcess

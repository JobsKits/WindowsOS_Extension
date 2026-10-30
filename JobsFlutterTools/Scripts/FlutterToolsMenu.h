#pragma once
#include <array>
#include <string>
#include <vector>
namespace JobsFlutterTools {
struct Entry { const wchar_t* action; const wchar_t* label; };
static const Entry Entries[] = {
    {L"run", L"▶️ 从终端运行 Flutter 项目"},
    {L"pub-get", L"📥 拉取 Flutter Pub 依赖"},
    {L"android-dependencies", L"🤖 拉取 Android 原生依赖"},
    {L"ohos-dependencies", L"🕊️ 拉取 OpenHarmony 依赖"},
    {L"native-dependencies", L"🧱 准备原生库与构建依赖（组合操作）"},
    {L"flutter-precache", L"🗃️ 下载Flutter平台资源"},
    {L"web-dependencies", L"🌐 拉取 Web 工程依赖"},
    {L"extract", L"🧩 提取 Flutter Pub 依赖"},
    {L"import-dependencies", L"📤 导入 Flutter Pub 依赖"},
    {L"export-gradle-dependencies", L"🧩 提取 Gradle 分发与依赖缓存"},
    {L"import-gradle-dependencies", L"📤 导入 Gradle 分发与依赖缓存"},
    {L"export-ohos-dependencies", L"🧩 提取 OpenHarmony 依赖"},
    {L"import-ohos-dependencies", L"📤 导入 OpenHarmony 依赖"},
    {L"export-native-dependencies", L"🧩 提取 原生构建缓存"},
    {L"import-native-dependencies", L"📤 导入 原生构建缓存"},
    {L"export-precache-dependencies", L"🧩 提取 Flutter 平台资源"},
    {L"import-precache-dependencies", L"📤 导入 Flutter 平台资源"},
    {L"export-web-dependencies", L"🧩 提取 Web 依赖"},
    {L"import-web-dependencies", L"📤 导入 Web 依赖"},
    {L"sdk-version", L"🔎 查看当前Flutter项目工程的SDK版本"},
    {L"sdk-manage", L"🔀 安装/切换Flutter SDK"},
    {L"ohos-sdk-manage", L"🕊️ 安装/切换Flutter@OpenHarmony SDK"},
    {L"java-manage", L"☕ 安装/切换Java SDK"},
    {L"gradle-download", L"📚 下载Gradled分发与构建插件"},
    {L"project-setup", L"🚀 一键配置 Flutter 项目"},
    {L"package", L"📦 Flutter打包"},
    {L"build-harmony", L"📦 打包鸿蒙（HAP + APP）"},
    {L"codegen", L"⚙️ Flutter自动化生产代码"},
    {L"native-doctor", L"🧑‍⚕️ 原生Flutter项目体检"},
    {L"harmony-doctor", L"💓 OpenHarmony Flutter 环境体检"},
    {L"maintenance", L"♻️ Flutter清理维护工具"},
    {L"repair-android", L"🩹 修复 Android SDK / platforms 缺失"},
    {L"repair-imports", L"🈶 修复 Flutter 项目中文路径"},
    {L"repair-namespace", L"🏷️ 修复 Flutter 插件 namespace"},
    {L"export-private-dependencies", L"🔐 提取Flutter项目工程私库依赖"},
    {L"import-private-dependencies", L"📥 导入Flutter项目工程私库依赖"},
};
static const unsigned Count = sizeof(Entries) / sizeof(Entries[0]);
using Selection = std::array<bool, Count>;
// 菜单对合法 Flutter 根目录展示已选动作；鸿蒙适配检查保留在点击和构建层。
inline bool IsActionVisible(unsigned index) {
    return index < Count;
}
inline bool IsActionAvailable(unsigned index, bool harmonyProject) {
    return index < Count && (std::wstring(Entries[index].action) != L"build-harmony" || harmonyProject);
}
enum MenuGroup : unsigned {
    Development = 0, Doctors = 1, Repairs = 2, FetchDependencies = 3,
    ExportDependencies = 4, ImportDependencies = 5, Runtime = 6, Resources = 7,
    GroupCount = 8
};
inline const wchar_t* GroupLabel(unsigned group) {
    static const wchar_t* labels[] = {
        L"🦋 Flutter 开发辅助", L"🏥 Flutter项目体检", L"🔧 Flutter 项目修复",
        L"📥 拉取Flutter项目工程相关依赖", L"🧩 提取Flutter项目工程依赖",
        L"📤 导入Flutter项目工程依赖", L"🔀 安装/切换Flutter运行环境", L"🧱 Flutter 资源与构建依赖"
    };
    return group < GroupCount ? labels[group] : L"";
}
inline unsigned ActionIndex(const std::wstring& action) {
    for (unsigned index = 0; index < Count; ++index) {
        if (action == Entries[index].action) return index;
    }
    return Count;
}
inline unsigned ActionGroup(unsigned index) {
    if (index >= Count) return GroupCount;
    const std::wstring action(Entries[index].action);
    if (action == L"pub-get" || action == L"android-dependencies" || action == L"ohos-dependencies" || action == L"web-dependencies") return FetchDependencies;
    if (action == L"extract" || action.compare(0, 7, L"export-") == 0) return ExportDependencies;
    if (action == L"import-dependencies" || action.compare(0, 7, L"import-") == 0) return ImportDependencies;
    if (action == L"sdk-manage" || action == L"ohos-sdk-manage" || action == L"java-manage") return Runtime;
    if (action == L"gradle-download" || action == L"flutter-precache" || action == L"native-dependencies") return Resources;
    if (action == L"sdk-version" || action == L"native-doctor" || action == L"harmony-doctor") return Doctors;
    return action.compare(0, 7, L"repair-") == 0 ? Repairs : Development;
}
// 显示排序独立于原 command offset；已安装动作和旧 URL 的标识保持稳定。
inline std::vector<unsigned> SelectedGroupEntries(unsigned group, const Selection& selected) {
    std::vector<unsigned> result;
    if (group == ExportDependencies || group == ImportDependencies) {
        const auto first = ActionIndex(group == ExportDependencies ? L"extract" : L"import-dependencies");
        const auto second = ActionIndex(group == ExportDependencies ? L"export-private-dependencies" : L"import-private-dependencies");
        for (const auto index : {first, second}) {
            if (index < Count && selected[index]) result.push_back(index);
        }
        for (unsigned index = 0; index < Count; ++index) {
            if (index != first && index != second && selected[index] && ActionGroup(index) == group) result.push_back(index);
        }
    } else if (group == Resources) {
        for (const auto action : {L"gradle-download", L"flutter-precache", L"native-dependencies"}) {
            const auto index = ActionIndex(action);
            if (index < Count && selected[index] && IsActionVisible(index)) result.push_back(index);
        }
    } else {
        for (unsigned index = 0; index < Count; ++index) {
            if (selected[index] && IsActionVisible(index) && ActionGroup(index) == group) result.push_back(index);
        }
    }
    return result;
}
struct MenuNode { bool group; unsigned value; };
inline std::vector<MenuNode> DevelopmentLayout(const Selection& selected) {
    std::vector<MenuNode> result;
    const auto leaf = [&](const wchar_t* action) {
        const auto index = ActionIndex(action);
        if (index < Count && selected[index] && IsActionVisible(index)) result.push_back({false, index});
    };
    const auto parent = [&](unsigned group) {
        if (!SelectedGroupEntries(group, selected).empty()) result.push_back({true, group});
    };
    leaf(L"run");
    parent(FetchDependencies);
    parent(ExportDependencies);
    parent(ImportDependencies);
    parent(Runtime);
    parent(Resources);
    leaf(L"project-setup");
    leaf(L"package");
    leaf(L"build-harmony");
    leaf(L"codegen");
    parent(Doctors);
    leaf(L"maintenance");
    return result;
}
// 安装器写入固定 ASCII 动作表；损坏配置不回退为全部启用。
inline bool ParseSelection(const std::string& text, Selection& selected) {
    selected.fill(false);
    if (text.empty() || text.size() > 4096) return false;
    size_t start = 0;
    while (start < text.size()) {
        const size_t end = text.find('\n', start);
        std::string token = text.substr(start, end == std::string::npos ? end : end - start);
        if (!token.empty() && token.back() == '\r') token.pop_back();
        bool found = false;
        for (unsigned index = 0; index < Count; ++index) {
            const std::wstring wide(Entries[index].action);
            if (token == std::string(wide.begin(), wide.end())) {
                if (selected[index]) return false;
                selected[index] = true;
                found = true;
                break;
            }
        }
        if (!found) return false;
        if (end == std::string::npos) break;
        start = end + 1;
    }
    return true;
}
inline bool ParseMenuState(const std::string& text, std::string& release, Selection& selected) {
    selected.fill(false);
    release.clear();
    const std::string version = "JobsFlutterTools-v1\n";
    if (text.size() > 65536 || text.compare(0, version.size(), version) != 0) return false;
    const auto end = text.find('\n', version.size());
    if (end == std::string::npos || end == version.size()) return false;
    release = text.substr(version.size(), end - version.size());
    for (unsigned char c : release) { if (c < 32) return false; }
    return ParseSelection(text.substr(end + 1), selected);
}
}

// FlutterSelectionProbe.cpp | 纯动作白名单回归，不依赖 Windows API。
// Created by Jobs on 2026年10月24日，星期六.
#include "../JobsFlutterTools/Scripts/FlutterToolsMenu.h"
#include <cassert>
int main() {
    using namespace JobsFlutterTools;
    assert(Count == 36);
    const auto emoji = [](wchar_t c) { return (c >= 0x2300 && c <= 0x27ff) || (c >= 0x1f000 && c <= 0x1ffff) || (c >= 0xd800 && c <= 0xdbff); };
    for (const auto& entry : Entries) assert(emoji(entry.label[0]));
    for (unsigned group = 0; group < GroupCount; ++group) assert(emoji(GroupLabel(group)[0]));
    auto indexOf = [](const wchar_t* wanted) {
        for (unsigned i = 0; i < Count; ++i) {
            if (std::wstring(Entries[i].action) == wanted) return i;
        }
        return Count;
    };
    Selection selected;
    for (unsigned i = 0; i < Count; ++i) {
        const std::wstring action(Entries[i].action);
        assert(ParseSelection(std::string(action.begin(), action.end()) + "\r\n", selected));
        for (unsigned j = 0; j < Count; ++j) assert(selected[j] == (i == j));
    }
    assert(ParseSelection("import-dependencies\n", selected));
    const auto importIndex = indexOf(L"import-dependencies");
    assert(importIndex < Count && selected[importIndex] && std::wstring(Entries[importIndex].label) == L"📤 导入 Flutter Pub 依赖");
    for (const auto action : {L"extract", L"export-private-dependencies", L"export-gradle-dependencies", L"export-ohos-dependencies", L"export-native-dependencies", L"export-precache-dependencies", L"export-web-dependencies"}) {
        assert(indexOf(action) < Count && ActionGroup(indexOf(action)) == ExportDependencies);
    }
    for (const auto action : {L"import-dependencies", L"import-private-dependencies", L"import-gradle-dependencies", L"import-ohos-dependencies", L"import-native-dependencies", L"import-precache-dependencies", L"import-web-dependencies"}) {
        assert(indexOf(action) < Count && ActionGroup(indexOf(action)) == ImportDependencies);
    }
    assert(indexOf(L"export-pods-dependencies") == Count && indexOf(L"import-spm-dependencies") == Count);
    for (const auto action : {L"pub-get", L"android-dependencies", L"ohos-dependencies", L"web-dependencies"}) {
        const auto index = indexOf(action);
        assert(index < Count && ActionGroup(index) == FetchDependencies);
    }
    assert(indexOf(L"pods-dependencies") == Count && indexOf(L"spm-dependencies") == Count);
    assert(ParseSelection("run\npub-get\nrepair-namespace", selected));
    assert(selected[0] && selected[1] && selected[indexOf(L"repair-namespace")]);
    for (auto text : {"", "unknown\n", "run\nrun\n", "run\n\n", "Run\n", "run\r\r\n", "pods-dependencies\n", "spm-dependencies\n"}) assert(!ParseSelection(text, selected));
    assert(ParseSelection("build-harmony\n", selected));
    for (unsigned i = 0; i < Count; ++i) {
        const std::wstring action(Entries[i].action);
        assert(IsActionVisible(i));
        assert(IsActionAvailable(i, true));
        assert(IsActionAvailable(i, false) == (action != L"build-harmony"));
        assert(ActionGroup(i) < GroupCount);
    }
    assert(!IsActionAvailable(Count, true));
    assert(!IsActionVisible(Count));
    assert(ActionGroup(Count) == GroupCount);
    assert(std::wstring(GroupLabel(FetchDependencies)) == L"📥 拉取Flutter项目工程相关依赖");
    assert(std::wstring(GroupLabel(ExportDependencies)) == L"🧩 提取Flutter项目工程依赖");
    assert(std::wstring(GroupLabel(ImportDependencies)) == L"📤 导入Flutter项目工程依赖");
    assert(std::wstring(GroupLabel(Runtime)) == L"🔀 安装/切换Flutter运行环境");
    assert(std::wstring(GroupLabel(Resources)) == L"🧱 Flutter 资源与构建依赖");
    assert(std::wstring(GroupLabel(Doctors)) == L"🏥 Flutter项目体检");
    assert(ActionGroup(indexOf(L"native-dependencies")) == Resources);
    assert(std::wstring(Entries[indexOf(L"native-dependencies")].label) == L"🧱 准备原生库与构建依赖（组合操作）");
    for (const auto action : {L"sdk-manage", L"ohos-sdk-manage", L"java-manage"}) assert(ActionGroup(indexOf(action)) == Runtime);
    for (const auto action : {L"gradle-download", L"flutter-precache", L"native-dependencies"}) assert(ActionGroup(indexOf(action)) == Resources);
    for (const auto action : {L"sdk-version", L"native-doctor", L"harmony-doctor"}) assert(ActionGroup(indexOf(action)) == Doctors);
    assert(std::wstring(Entries[indexOf(L"sdk-manage")].label) == L"🔀 安装/切换Flutter SDK");
    assert(std::wstring(Entries[indexOf(L"ohos-sdk-manage")].label) == L"🕊️ 安装/切换Flutter@OpenHarmony SDK");
    assert(std::wstring(Entries[indexOf(L"java-manage")].label) == L"☕ 安装/切换Java SDK");
    assert(std::wstring(Entries[indexOf(L"gradle-download")].label) == L"📚 下载Gradled分发与构建插件");
    assert(std::wstring(Entries[indexOf(L"flutter-precache")].label) == L"🗃️ 下载Flutter平台资源");
    assert(std::wstring(Entries[indexOf(L"sdk-version")].label) == L"🔎 查看当前Flutter项目工程的SDK版本");
    selected.fill(false);
    assert(DevelopmentLayout(selected).empty());
    for (unsigned group = 1; group < GroupCount; ++group) assert(SelectedGroupEntries(group, selected).empty());
    // 每个已选叶只挂在一个真实父层；仅修复项不复活开发组，空父组不出现。
    for (unsigned index = 0; index < Count; ++index) {
        selected.fill(false); selected[index] = true;
        const auto layout = DevelopmentLayout(selected);
        const auto group = ActionGroup(index);
        if (group == Repairs) { assert(layout.empty()); continue; }
        assert(layout.size() == 1);
        assert(layout[0].group == (group != Development));
        assert(layout[0].value == (group == Development ? index : group));
        if (group != Development) {
            const auto children = SelectedGroupEntries(group, selected);
            assert(children.size() == 1 && children[0] == index);
        }
    }
    selected.fill(true);
    const auto layout = DevelopmentLayout(selected);
    const std::vector<unsigned> expectedParents = {FetchDependencies, ExportDependencies, ImportDependencies, Runtime, Resources, Doctors};
    std::vector<unsigned> parents;
    std::array<unsigned, Count> seen{};
    for (const auto& node : layout) {
        if (node.group) {
            parents.push_back(node.value);
            for (const auto index : SelectedGroupEntries(node.value, selected)) ++seen[index];
        } else { ++seen[node.value]; }
    }
    assert(parents == expectedParents);
    for (const auto index : SelectedGroupEntries(Repairs, selected)) ++seen[index];
    for (const auto count : seen) assert(count == 1);
    const auto resources = SelectedGroupEntries(Resources, selected);
    assert(resources.size() == 3 && resources[0] == indexOf(L"gradle-download") && resources[1] == indexOf(L"flutter-precache") && resources[2] == indexOf(L"native-dependencies"));
    selected.fill(false); selected[indexOf(L"build-harmony")] = true;
    const auto harmonyLayout = DevelopmentLayout(selected);
    assert(harmonyLayout.size() == 1 && !harmonyLayout[0].group && harmonyLayout[0].value == indexOf(L"build-harmony"));
    assert(!IsActionAvailable(harmonyLayout[0].value, false));
    std::string release;
    assert(ParseMenuState("JobsFlutterTools-v1\nC:\\项目\\new-release\nrun\n", release, selected));
    assert(release == "C:\\项目\\new-release" && selected[0] && !selected[1]);
    assert(ParseMenuState("JobsFlutterTools-v1\nC:\\项目\\next-release\ncodegen\n", release, selected));
    assert(release == "C:\\项目\\next-release" && !selected[0] && selected[indexOf(L"codegen")]);
    for (auto text : {"JobsFlutterTools-v1\nC:\\release\n", "JobsFlutterTools-v2\nC:\\release\nrun", "JobsFlutterTools-v1\n\nrun", "JobsFlutterTools-v1\nC:\\bad\r\nrun"}) assert(!ParseMenuState(text, release, selected));
}

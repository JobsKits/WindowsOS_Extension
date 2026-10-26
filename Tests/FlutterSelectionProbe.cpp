// FlutterSelectionProbe.cpp | 纯动作白名单回归，不依赖 Windows API。
// Created by Jobs on 2026年10月24日，星期六.
#include "../JobsFlutterTools/Scripts/FlutterToolsMenu.h"
#include <cassert>
int main() {
    using namespace JobsFlutterTools;
    Selection selected;
    for (unsigned i = 0; i < Count; ++i) {
        const std::wstring action(Entries[i].action);
        assert(ParseSelection(std::string(action.begin(), action.end()) + "\r\n", selected));
        for (unsigned j = 0; j < Count; ++j) assert(selected[j] == (i == j));
    }
    assert(ParseSelection("run\npub-get\nrepair-namespace", selected));
    assert(selected[0] && selected[1] && selected[Count - 1]);
    for (auto text : {"", "unknown\n", "run\nrun\n", "run\n\n", "Run\n", "run\r\r\n"}) assert(!ParseSelection(text, selected));
    std::string release;
    assert(ParseMenuState("JobsFlutterTools-v1\nC:\\项目\\new-release\nrun\n", release, selected));
    assert(release == "C:\\项目\\new-release" && selected[0] && !selected[1]);
    assert(ParseMenuState("JobsFlutterTools-v1\nC:\\项目\\next-release\ncodegen\n", release, selected));
    assert(release == "C:\\项目\\next-release" && !selected[0] && selected[7]);
    for (auto text : {"JobsFlutterTools-v1\nC:\\release\n", "JobsFlutterTools-v2\nC:\\release\nrun", "JobsFlutterTools-v1\n\nrun", "JobsFlutterTools-v1\nC:\\bad\r\nrun"}) assert(!ParseMenuState(text, release, selected));
}

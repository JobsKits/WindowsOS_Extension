// FlutterRunTarget.h | JobsFlutterRunner
// Created by Jobs on 2026年11月17日，星期二.
// 最近 pubspec 是包边界；回调由原生文件系统实现，隔离夹具复用同一判定。
#pragma once
#include <cwctype>
#include <string>

namespace JobsFlutter {
inline std::wstring RunTargetParent(const std::wstring& path) {
    const size_t slash = path.find_last_of(L"\\/");
    if (slash == std::wstring::npos) return L"";
    if (slash == 2 && path.size() > 2 && path[1] == L':') return path.substr(0, 3);
    return path.substr(0, slash);
}
template<class HasPubspec, class IsProject>
std::wstring DartRunProject(const std::wstring& target, bool plainFile, HasPubspec hasPubspec, IsProject isProject) {
    if (!plainFile || target.size() < 5) return L"";
    std::wstring extension = target.substr(target.size() - 5);
    for (auto& value : extension) value = static_cast<wchar_t>(std::towlower(value));
    if (extension != L".dart") return L"";
    std::wstring directory = RunTargetParent(target);
    while (!directory.empty()) {
        if (hasPubspec(directory)) return isProject(directory) ? directory : L"";
        const std::wstring parent = RunTargetParent(directory);
        if (parent == directory) break;
        directory = parent;
    }
    return L"";
}
}

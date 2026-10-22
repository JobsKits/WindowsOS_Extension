// DesktopScope.h | JobsAndroidSimulatorCreator
// Created by Jobs on 2026年10月22日，星期四.
#pragma once
#include <string>
#include <cwctype>
namespace JobsAndroid {
inline std::wstring NormalizeDesktopPath(std::wstring path) {
    for (auto& character : path) { if (character == L'/') character = L'\\'; character = std::towlower(character); }
    while (path.size() > 3 && path.back() == L'\\') path.pop_back();
    return path;
}
inline bool IsDesktopContext(bool hasSelection, const std::wstring& path, const std::wstring& desktop) {
    return !hasSelection && !path.empty() && !desktop.empty() && NormalizeDesktopPath(path) == NormalizeDesktopPath(desktop);
}
}

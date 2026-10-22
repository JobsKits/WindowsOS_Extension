// DesktopScope.h | JobsHarmonySimulatorCreator
// Created by Jobs on 2026年10月23日，星期五.
#pragma once
#include <string>
#include <cwctype>
namespace JobsHarmony {
inline std::wstring NormalizeDesktopPath(std::wstring path) {
    for (auto& character : path) { if (character == L'/') character = L'\\'; character = std::towlower(character); }
    while (path.size() > 3 && path.back() == L'\\') path.pop_back();
    return path;
}
inline bool IsDesktopContext(bool hasSelection, const std::wstring& path, const std::wstring& desktop, bool nativeX64 = true) {
    return nativeX64 && !hasSelection && !path.empty() && !desktop.empty() && NormalizeDesktopPath(path) == NormalizeDesktopPath(desktop);
}
}

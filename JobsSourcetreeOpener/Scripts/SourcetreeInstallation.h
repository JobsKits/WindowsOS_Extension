// SourcetreeInstallation.h | JobsSourcetreeOpener
// Created by Jobs on 2026年10月26日，星期一.
// 候选必须指向真实可用的 SourceTree.exe；陈旧注册信息不能留下菜单。
#pragma once
#include <functional>
#include <string>
#include <vector>

namespace JobsSourcetree {
inline std::wstring Find(const std::vector<std::wstring>& candidates,
                         const std::function<bool(const std::wstring&)>& exists) {
    for (const auto& path : candidates) {
        const auto slash = path.find_last_of(L"\\/");
        auto name = path.substr(slash == std::wstring::npos ? 0 : slash + 1);
        for (auto& c : name) if (c >= L'A' && c <= L'Z') c += L'a' - L'A';
        if (name == L"sourcetree.exe" && exists(path)) return path;
    }
    return L"";
}
}

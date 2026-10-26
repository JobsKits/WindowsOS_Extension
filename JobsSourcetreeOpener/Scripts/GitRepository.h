// GitRepository.h | JobsSourcetreeOpener
// Created by Jobs on 2026年10月26日，星期一.
// 菜单只读本地元数据；内层 .git 无效时立即拒绝，不回落父仓。
#pragma once
#include <functional>
#include <string>
#include <vector>

namespace JobsGit {
struct Files {
    // -1 不存在；0 普通文件；1 普通目录；2 链接、不安全或不可读。
    std::function<int(const std::wstring&)> kind;
    std::function<bool(const std::wstring&, std::wstring&)> read;
    std::function<std::wstring(const std::wstring&)> absolute;
};
inline std::wstring Join(const std::wstring& parent, const std::wstring& child) {
    return parent + (parent.back() == L'\\' ? L"" : L"\\") + child;
}
inline std::wstring Parent(const std::wstring& value) {
    const auto slash = value.find_last_of(L"\\/");
    if (slash == std::wstring::npos || value.size() <= 3) return L"";
    return value.substr(0, slash < 3 ? 3 : slash);
}
inline bool IsGitName(std::wstring name) {
    for (auto& c : name) if (c >= L'A' && c <= L'Z') c += L'a' - L'A';
    return name == L".git";
}
inline bool SingleLine(std::wstring& value) {
    while (!value.empty() && (value.back() == L'\r' || value.back() == L'\n')) value.pop_back();
    return !value.empty() && value.find_first_of(L"\r\n\0", 0, 3) == std::wstring::npos;
}
inline bool ValidHead(const std::wstring& head) {
    if (head.compare(0, 10, L"ref: refs/") == 0) {
        if (head.size() <= 10 || head.back() == L'/' || head.back() == L'.' || head.find(L"..") != std::wstring::npos || head.find(L"@{") != std::wstring::npos) return false;
        return head.substr(5).find_first_of(L" ~^:?*[\\\t") == std::wstring::npos;
    }
    if (head.size() != 40 && head.size() != 64) return false;
    for (auto c : head) if (!((c >= L'0' && c <= L'9') || (c >= L'a' && c <= L'f') || (c >= L'A' && c <= L'F'))) return false;
    return true;
}
inline std::wstring ResolveMetadataPath(const Files& files, const std::wstring& base, const std::wstring& value) {
    if (value.empty()) return L"";
    if (value[0] == L'\\' || value[0] == L'/') return L"";
    if (value.size() > 1 && value[1] == L':') {
        if (value.size() < 3 || (value[2] != L'\\' && value[2] != L'/')) return L"";
        return files.absolute(value);
    }
    return files.absolute(Join(base, value));
}
inline bool Metadata(const Files& files, const std::wstring& directory) {
    if (files.kind(directory) != 1) return false;
    std::wstring head;
    if (files.kind(Join(directory, L"HEAD")) != 0 || !files.read(Join(directory, L"HEAD"), head) || !SingleLine(head) || !ValidHead(head)) return false;
    auto common = directory;
    const auto commonFile = Join(directory, L"commondir");
    if (files.kind(commonFile) != -1) {
        std::wstring relative;
        if (files.kind(commonFile) != 0 || !files.read(commonFile, relative) || !SingleLine(relative)) return false;
        common = ResolveMetadataPath(files, directory, relative);
    }
    return !common.empty() && files.kind(common) == 1 && files.kind(Join(common, L"objects")) == 1 && (files.kind(Join(common, L"refs")) == 1 || files.kind(Join(common, L"reftable")) == 1) && files.kind(Join(common, L"config")) == 0;
}
inline bool WorkingTree(const Files& files, const std::wstring& selected) {
    if (selected.empty() || files.kind(selected) != 1) return false;
    auto cursor = selected;
    for (int depth = 0; !cursor.empty() && depth < 256; ++depth, cursor = Parent(cursor)) {
        const auto slash = cursor.find_last_of(L"\\/");
        if (IsGitName(cursor.substr(slash == std::wstring::npos ? 0 : slash + 1))) return false;
        // 裸仓和独立元数据目录内部没有工作树菜单。
        if (Metadata(files, cursor)) return false;
        const auto marker = Join(cursor, L".git");
        const auto type = files.kind(marker);
        if (type == -1) continue;
        if (type == 1) return Metadata(files, marker);
        if (type != 0) return false;
        std::wstring text;
        if (!files.read(marker, text) || !SingleLine(text) || text.compare(0, 8, L"gitdir: ") != 0) return false;
        text.erase(0, 8);
        if (text.empty()) return false;
        const auto metadata = ResolveMetadataPath(files, cursor, text);
        return !metadata.empty() && Metadata(files, metadata);
    }
    return false;
}
}

// CommandShortcutTarget.h | JobsCommandShortcutCreator
// Created by Jobs on 2026年11月13日，星期五.
#pragma once
#include <string>
#include <cwctype>

namespace JobsCommandShortcut {
inline bool IsEligibleDirectory(const std::wstring& path) {
    if (path.empty() || path.back() == L'\\' || path.back() == L'/') return false;
    const DWORD attributes = GetFileAttributesW(path.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES || !(attributes & FILE_ATTRIBUTE_DIRECTORY) ||
        (attributes & FILE_ATTRIBUTE_REPARSE_POINT)) return false;
    const size_t slash = path.find_last_of(L"\\/");
    const std::wstring name = path.substr(slash == std::wstring::npos ? 0 : slash + 1);
    const size_t dot = name.find_last_of(L'.');
    if (dot == std::wstring::npos) return false;
    std::wstring extension = name.substr(dot);
    for (wchar_t& value : extension) value = static_cast<wchar_t>(std::towlower(value));
    if (extension != L".cmd" && extension != L".bat" && extension != L".ps1") return false;
    const DWORD script = GetFileAttributesW((path + L"\\" + name).c_str());
    return script != INVALID_FILE_ATTRIBUTES &&
        !(script & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DEVICE));
}
inline bool IsSingleDirectory(unsigned count, const std::wstring& path) {
    return count == 1 && IsEligibleDirectory(path);
}
}

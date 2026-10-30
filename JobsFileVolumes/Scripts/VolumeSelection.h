// VolumeSelection.h | JobsFileVolumes
// Created by Jobs on 2026年10月28日，星期三.
#pragma once
#include <string>
#include <vector>
#include <set>
#include <cwctype>

namespace JobsFileVolumes {
inline bool IsFile(const std::wstring& path) {
    if (path.empty()) return false;
    const DWORD attrs = GetFileAttributesW(path.c_str());
    return attrs != INVALID_FILE_ATTRIBUTES && !(attrs & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DEVICE));
}
inline bool IsNonEmptyFile(const std::wstring& path) {
    WIN32_FILE_ATTRIBUTE_DATA data = {};
    return GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &data) &&
        data.dwFileAttributes != INVALID_FILE_ATTRIBUTES &&
        !(data.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DEVICE)) &&
        (data.nFileSizeHigh != 0 || data.nFileSizeLow != 0);
}
inline bool Number(const std::wstring& text, unsigned& result) {
    if (text.empty() || text.size() > 9) return false;
    result = 0;
    for (auto c : text) {
        if (c < L'0' || c > L'9') return false;
        result = result * 10 + (c - L'0');
    }
    return result > 0;
}
inline bool Parse(const std::wstring& filename, std::wstring& name, unsigned& index, unsigned& total) {
    const auto at = filename.find_last_of(L'@');
    if (at == std::wstring::npos || at == 0) return false;
    const auto of = filename.find(L"of", at + 1);
    if (of == std::wstring::npos) return false;
    name = filename.substr(0, at);
    if (name == L"." || name == L".." || name.back() == L'.' || name.back() == L' ') return false;
    if (name.find_first_of(L"<>:\"/\\|?*") != std::wstring::npos) return false;
    for (auto c : name) if (c < 32) return false;
    auto stem = name.substr(0, name.find(L'.'));
    for (auto& c : stem) c = static_cast<wchar_t>(std::towupper(c));
    if (stem == L"CON" || stem == L"PRN" || stem == L"AUX" || stem == L"NUL") return false;
    if (stem.size() == 4 && (stem.substr(0, 3) == L"COM" || stem.substr(0, 3) == L"LPT") && stem[3] >= L'1' && stem[3] <= L'9') return false;
    return Number(filename.substr(at + 1, of - at - 1), index) && Number(filename.substr(of + 2), total) && index <= total;
}
// 仅验证传入的精确集合，不枚举同目录文件补齐缺卷。
inline bool CanMerge(const std::vector<std::wstring>& paths) {
    if (paths.size() < 2 || paths.size() > 10000) return false;
    std::wstring directory, original;
    unsigned expected = 0;
    std::set<unsigned> indices;
    for (const auto& path : paths) {
        if (!IsNonEmptyFile(path)) return false;
        const auto slash = path.find_last_of(L"/\\");
        if (slash == std::wstring::npos) return false;
        std::wstring name;
        unsigned index = 0, total = 0;
        if (!Parse(path.substr(slash + 1), name, index, total) || total != paths.size()) return false;
        const auto parent = path.substr(0, slash);
        if (expected == 0) { expected = total; original = name; directory = parent; }
        if (total != expected || name != original || parent != directory || !indices.insert(index).second) return false;
    }
    return indices.size() == expected;
}
inline bool CanSplit(const std::vector<std::wstring>& paths) { return paths.size() == 1 && IsFile(paths[0]); }
}

// FileViewerTarget.h | JobsFileContentViewer
// Created by Jobs on 2026年10月27日，星期二.
#pragma once
#include <string>

namespace JobsFileViewer {
inline bool IsEligibleFile(const std::wstring& path) {
    if (path.empty()) return false;
    const DWORD attributes = GetFileAttributesW(path.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES &&
        !(attributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DEVICE));
}
inline bool IsSingleFile(unsigned count, const std::wstring& path) {
    return count == 1 && IsEligibleFile(path);
}
}

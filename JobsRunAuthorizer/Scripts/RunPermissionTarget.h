// RunPermissionTarget.h | Jobs Windows execution-permission menu policy
// Created by Jobs on 2026年10月26日，星期一.
#pragma once
#include <string>

namespace JobsRunPermission {
enum class ExecutionState { Unknown, Denied, Allowed };
inline bool IsActionEnabled(ExecutionState state, bool grant) {
    return state == (grant ? ExecutionState::Denied : ExecutionState::Allowed);
}

#ifdef _WIN32
inline bool IsEligibleFile(const std::wstring& path) {
    if (path.empty()) return false;
    const DWORD attributes = GetFileAttributesW(path.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES &&
        !(attributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DEVICE));
}

inline ExecutionState ReadExecutionState(const std::wstring& path) {
    if (!IsEligibleFile(path)) return ExecutionState::Unknown;
    // 只检查当前 Explorer 用户的 ExecuteFile，不启动目标或修改 DACL。
    HANDLE file = CreateFileW(path.c_str(), FILE_EXECUTE,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING,
        FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        return GetLastError() == ERROR_ACCESS_DENIED ? ExecutionState::Denied : ExecutionState::Unknown;
    }
    BY_HANDLE_FILE_INFORMATION information = {};
    const bool regular = GetFileInformationByHandle(file, &information) && information.nNumberOfLinks == 1 &&
        !(information.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DEVICE));
    CloseHandle(file);
    return regular ? ExecutionState::Allowed : ExecutionState::Unknown;
}
#endif
}

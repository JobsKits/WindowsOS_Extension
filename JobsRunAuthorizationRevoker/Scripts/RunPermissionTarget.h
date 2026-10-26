// RunPermissionTarget.h | Jobs Windows execution-permission menu policy
// Created by Jobs on 2026年10月26日，星期一.
#pragma once
#include <string>

namespace JobsRunPermission {
enum class ExecutionState { Unknown, Denied, Allowed };
inline bool IsActionEnabled(ExecutionState state, bool grant) {
    return state == (grant ? ExecutionState::Denied : ExecutionState::Allowed);
}

inline bool IsExecutableName(const std::wstring& path) {
    const auto separator = path.find_last_of(L"\\/");
    const auto dot = path.find_last_of(L'.');
    if (dot == std::wstring::npos || (separator != std::wstring::npos && dot < separator)) return false;
    std::wstring extension = path.substr(dot);
    for (auto& value : extension) {
        if (value >= L'A' && value <= L'Z') value += L'a' - L'A';
    }
    const wchar_t* extensions[] = {
        L".exe", L".com", L".scr", L".cpl", L".bat", L".cmd", L".ps1",
        L".vbs", L".vbe", L".js", L".jse", L".wsf", L".wsh", L".hta",
        L".py", L".pyw", L".pl", L".rb", L".sh", L".bash", L".zsh",
        L".fish", L".ksh", L".csh", L".tcsh", L".php", L".lua", L".command"
    };
    for (const auto candidate : extensions) {
        if (extension == candidate) return true;
    }
    return false;
}

#ifdef _WIN32
inline bool IsEligibleFile(const std::wstring& path) {
    if (!IsExecutableName(path)) return false;
    const DWORD attributes = GetFileAttributesW(path.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES &&
        !(attributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT));
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
        !(information.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT));
    CloseHandle(file);
    return regular ? ExecutionState::Allowed : ExecutionState::Unknown;
}
#endif
}

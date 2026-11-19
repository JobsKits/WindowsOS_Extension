// FileVisibility.h | JobsFileVisibility
// Created by Jobs on 2026年11月18日，星期三.
#pragma once
#include <string>
#include <vector>

namespace JobsFileVisibility {
struct Identity {
    DWORD volume = 0, high = 0, low = 0;
    bool operator==(const Identity& other) const {
        return volume == other.volume && high == other.high && low == other.low;
    }
};
struct Target {
    std::wstring path;
    Identity identity;
    bool hidden = false;
};
// A handle addresses the selected object itself, including during path replacement.
class Handle {
    HANDLE value;
public:
    Handle(const std::wstring& path, bool write, DWORD extraAccess = 0) : value(CreateFileW(path.c_str(),
        FILE_READ_ATTRIBUTES | (write ? FILE_WRITE_ATTRIBUTES : 0) | extraAccess,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING,
        FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr)) {}
    ~Handle() { if (value != INVALID_HANDLE_VALUE) CloseHandle(value); }
    operator HANDLE() const { return value; }
    Handle(const Handle&) = delete;
    Handle& operator=(const Handle&) = delete;
};
// Links, devices and volume roots never become attribute-change targets.
inline bool IsPathEligible(const std::wstring& path) {
    if (path.size() <= 3 || path.find(L'\0') != std::wstring::npos) return false;
    // Device / extended namespaces are outside this Explorer selection contract.
    if (path.compare(0, 4, L"\\\\.\\") == 0 || path.compare(0, 4, L"\\\\?\\") == 0) return false;
    const bool drive = path[1] == L':' && (path[2] == L'\\' || path[2] == L'/');
    if (!drive && !(path[0] == L'\\' && path[1] == L'\\')) return false;
    if (path.find(L':', drive ? 2 : 0) != std::wstring::npos) return false;
    const DWORD length = GetFullPathNameW(path.c_str(), 0, nullptr, nullptr);
    if (!length) return false;
    std::vector<wchar_t> full(length + 1), volume(length + 1);
    const DWORD copied = GetFullPathNameW(path.c_str(), static_cast<DWORD>(full.size()), full.data(), nullptr);
    if (!copied || copied >= full.size() ||
        !GetVolumePathNameW(full.data(), volume.data(), static_cast<DWORD>(volume.size()))) return false;
    std::wstring resolved(full.data()), root(volume.data());
    while (!resolved.empty() && (resolved.back() == L'\\' || resolved.back() == L'/')) resolved.pop_back();
    while (!root.empty() && (root.back() == L'\\' || root.back() == L'/')) root.pop_back();
    return _wcsicmp(resolved.c_str(), root.c_str()) != 0;
}
// Read both file identity and current attributes without following a selected link.
inline DWORD Read(HANDLE handle, Target& target, DWORD& attributes) {
    BY_HANDLE_FILE_INFORMATION info = {};
    if (!GetFileInformationByHandle(handle, &info)) return GetLastError();
    if (info.dwFileAttributes & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DEVICE)) return ERROR_NOT_SUPPORTED;
    target.identity.volume = info.dwVolumeSerialNumber;
    target.identity.high = info.nFileIndexHigh;
    target.identity.low = info.nFileIndexLow;
    attributes = info.dwFileAttributes;
    target.hidden = (attributes & FILE_ATTRIBUTE_HIDDEN) != 0;
    return ERROR_SUCCESS;
}
// Capture identity while constructing the menu, then verify it again on click.
inline DWORD Snapshot(const std::wstring& path, Target& target) {
    if (!IsPathEligible(path)) return ERROR_INVALID_NAME;
    Handle handle(path, false);
    if (handle == INVALID_HANDLE_VALUE) return GetLastError();
    DWORD attributes = 0;
    target.path = path;
    return Read(handle, target, attributes);
}
// All other attribute bits and timestamps retain their current values.
inline DWORD Apply(const Target& expected, bool hidden) {
    if (!IsPathEligible(expected.path)) return ERROR_INVALID_NAME;
    Handle handle(expected.path, true);
    if (handle == INVALID_HANDLE_VALUE) return GetLastError();
    Target current;
    DWORD attributes = 0;
    DWORD error = Read(handle, current, attributes);
    if (error != ERROR_SUCCESS) return error;
    if (!(current.identity == expected.identity)) return ERROR_FILE_INVALID;
    if (current.hidden == hidden) return ERROR_SUCCESS;
    FILE_BASIC_INFO update = {};
    update.FileAttributes = hidden ? (attributes | FILE_ATTRIBUTE_HIDDEN) : (attributes & ~FILE_ATTRIBUTE_HIDDEN);
    update.FileAttributes &= ~FILE_ATTRIBUTE_NORMAL;
    if (update.FileAttributes == 0) update.FileAttributes = FILE_ATTRIBUTE_NORMAL;
    const DWORD otherAttributes = attributes & ~(FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_NORMAL);
    if (!SetFileInformationByHandle(handle, FileBasicInfo, &update, sizeof(update))) return GetLastError();
    error = Read(handle, current, attributes);
    if (error != ERROR_SUCCESS) return error;
    if (current.hidden != hidden || !(current.identity == expected.identity) ||
        (attributes & ~(FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_NORMAL)) != otherAttributes) return ERROR_WRITE_FAULT;
    Target pathTarget;
    error = Snapshot(expected.path, pathTarget);
    if (error != ERROR_SUCCESS) return error;
    if (!(pathTarget.identity == expected.identity)) return ERROR_FILE_INVALID;
    SHChangeNotify(SHCNE_UPDATEITEM | SHCNE_ATTRIBUTES, SHCNF_PATHW, expected.path.c_str(), nullptr);
    return ERROR_SUCCESS;
}
}

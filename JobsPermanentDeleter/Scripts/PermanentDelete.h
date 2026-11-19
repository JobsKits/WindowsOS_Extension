// PermanentDelete.h | JobsPermanentDeleter
// Created by Jobs on 2026年11月18日，星期三.
#pragma once
#include <algorithm>
#include <memory>
#include <string>
#include <vector>

namespace JobsPermanentDeleter {
constexpr size_t MaximumItems = 4096;
struct Identity {
    DWORD volume = 0, high = 0, low = 0;
    bool operator==(const Identity& other) const {
        return volume == other.volume && high == other.high && low == other.low;
    }
};
struct Target { std::wstring path; Identity identity; };
struct Handle {
    HANDLE value = INVALID_HANDLE_VALUE;
    Handle() = default;
    ~Handle() { Close(); }
    Handle(const Handle&) = delete;
    Handle& operator=(const Handle&) = delete;
    // Release only this object's pinned handle, including on a cancelled dialog.
    void Close() {
        if (value != INVALID_HANDLE_VALUE) { CloseHandle(value); value = INVALID_HANDLE_VALUE; }
    }
};
struct Entry { Target target; Handle handle; bool directory = false; };
struct Plan {
    bool ready = false;
    std::vector<Target> roots;
    std::vector<std::unique_ptr<Handle>> ancestors;
    std::vector<std::unique_ptr<Entry>> entries;
};
// Boundary-aware case-insensitive comparison also handles a protected directory itself.
inline bool Contains(const std::wstring& parent, const std::wstring& path) {
    return path.size() >= parent.size() &&
        _wcsnicmp(parent.c_str(), path.c_str(), parent.size()) == 0 &&
        (path.size() == parent.size() || path[parent.size()] == L'\\');
}
// Only ordinary local absolute Explorer paths enter this destructive operation.
inline DWORD Normalize(const std::wstring& input, std::wstring& output) {
    if (input.size() < 4 || input.size() >= 248 || input.find(L'\0') != std::wstring::npos ||
        !((input[0] >= L'A' && input[0] <= L'Z') || (input[0] >= L'a' && input[0] <= L'z')) ||
        input[1] != L':' || (input[2] != L'\\' && input[2] != L'/') || input.find(L':', 2) != std::wstring::npos) return ERROR_INVALID_NAME;
    wchar_t full[32768] = {};
    DWORD copied = GetFullPathNameW(input.c_str(), 32768, full, nullptr);
    if (!copied || copied >= 248) return ERROR_INVALID_NAME;
    output.assign(full, copied);
    std::replace(output.begin(), output.end(), L'/', L'\\');
    while (output.size() > 3 && output.back() == L'\\') output.pop_back();
    if (output.size() <= 3) return ERROR_ACCESS_DENIED;
    size_t start = 3;
    while (start < output.size()) {
        size_t end = output.find(L'\\', start);
        std::wstring part = output.substr(start, end == std::wstring::npos ? end : end - start);
        if (part.empty() || part.back() == L'.' || part.back() == L' ' || part == L"." || part == L"..") return ERROR_INVALID_NAME;
        if (end == std::wstring::npos) break;
        start = end + 1;
    }
    return ERROR_SUCCESS;
}
// Protect OS/program trees and every ancestor of the current user's profile.
inline bool Protected(const std::wstring& path) {
    wchar_t windows[32768] = {};
    UINT length = GetWindowsDirectoryW(windows, 32768);
    if (!length || length >= 32768) return true;
    const std::wstring system(windows, length);
    if (Contains(system, path) || Contains(path, system)) return true;
    for (const auto* name : {L"ProgramFiles", L"ProgramFiles(x86)", L"ProgramW6432", L"ProgramData", L"USERPROFILE"}) {
        wchar_t buffer[32768] = {};
        DWORD count = GetEnvironmentVariableW(name, buffer, 32768);
        if (count >= 32768) return true;
        if (!count) { if (std::wstring(name) == L"USERPROFILE") return true; continue; }
        std::wstring protectedPath(buffer, count);
        while (protectedPath.size() > 3 && protectedPath.back() == L'\\') protectedPath.pop_back();
        if (Contains(path, protectedPath)) return true;
        if (std::wstring(name) != L"USERPROFILE" && Contains(protectedPath, path)) return true;
    }
    return false;
}
// Reject short-name and SUBST aliases instead of trusting a string-only protection check.
inline DWORD ValidateFinalPath(HANDLE handle, const std::wstring& expected) {
    std::vector<wchar_t> buffer(32768);
    DWORD length = GetFinalPathNameByHandleW(handle, buffer.data(), static_cast<DWORD>(buffer.size()), FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
    if (!length || length >= buffer.size()) return ERROR_INVALID_NAME;
    std::wstring finalPath(buffer.data(), length);
    if (finalPath.compare(0,4,L"\\\\?\\") != 0) return ERROR_INVALID_NAME;
    finalPath.erase(0,4);
    while (finalPath.size() > 3 && finalPath.back() == L'\\') finalPath.pop_back();
    return _wcsicmp(finalPath.c_str(), expected.c_str()) == 0 ? ERROR_SUCCESS : ERROR_INVALID_NAME;
}
// Read the object addressed by the handle without following a reparse target.
inline DWORD Read(HANDLE handle, Identity& identity, DWORD& attributes) {
    BY_HANDLE_FILE_INFORMATION info = {};
    if (!GetFileInformationByHandle(handle, &info)) return GetLastError();
    attributes = info.dwFileAttributes;
    if (attributes & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DEVICE)) return ERROR_NOT_SUPPORTED;
    identity.volume = info.dwVolumeSerialNumber;
    identity.high = info.nFileIndexHigh;
    identity.low = info.nFileIndexLow;
    return ERROR_SUCCESS;
}
// Menu discovery is read-only; the click path must acquire its own pinned plan.
inline DWORD Snapshot(const std::wstring& input, Target& target) {
    DWORD error = Normalize(input, target.path);
    if (error || Protected(target.path)) return error ? error : ERROR_ACCESS_DENIED;
    Handle handle;
    handle.value = CreateFileW(target.path.c_str(), FILE_READ_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        nullptr, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    if (handle.value == INVALID_HANDLE_VALUE) return GetLastError();
    error = ValidateFinalPath(handle.value, target.path);
    if (error) return error;
    DWORD attributes = 0;
    return Read(handle.value, target.identity, attributes);
}
// Pin every path ancestor before enumeration so junction swaps and renames cannot redirect it.
inline DWORD PinAncestors(const std::wstring& path, Plan& plan) {
    size_t end = 2;
    while (end != std::wstring::npos) {
        const std::wstring parent = end == 2 ? path.substr(0, 3) : path.substr(0, end);
        std::unique_ptr<Handle> handle(new Handle());
        handle->value = CreateFileW(parent.c_str(), FILE_READ_ATTRIBUTES, FILE_SHARE_READ, nullptr, OPEN_EXISTING,
            FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
        if (handle->value == INVALID_HANDLE_VALUE) return GetLastError();
        DWORD pathError = ValidateFinalPath(handle->value, parent);
        if (pathError) return pathError;
        Identity identity;
        DWORD attributes = 0;
        DWORD error = Read(handle->value, identity, attributes);
        if (error || !(attributes & FILE_ATTRIBUTE_DIRECTORY)) return error ? error : ERROR_DIRECTORY;
        plan.ancestors.push_back(std::move(handle));
        end = path.find(L'\\', end + 1);
    }
    return ERROR_SUCCESS;
}
// Hold all approved nodes, including descendants, until explicit confirmation or cancellation.
inline DWORD PinTree(const Target& expected, bool compareIdentity, Plan& plan, unsigned depth = 0) {
    if (plan.entries.size() >= MaximumItems || depth > 64) return ERROR_BUFFER_OVERFLOW;
    std::wstring canonical;
    DWORD error = Normalize(expected.path, canonical);
    if (error || Protected(canonical)) return error ? error : ERROR_ACCESS_DENIED;
    std::unique_ptr<Entry> entry(new Entry());
    entry->target.path = canonical;
    entry->handle.value = CreateFileW(canonical.c_str(), DELETE | FILE_READ_ATTRIBUTES | FILE_LIST_DIRECTORY,
        FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    if (entry->handle.value == INVALID_HANDLE_VALUE) return GetLastError();
    error = ValidateFinalPath(entry->handle.value, canonical);
    if (error) return error;
    DWORD attributes = 0;
    error = Read(entry->handle.value, entry->target.identity, attributes);
    if (error) return error;
    if (compareIdentity && !(entry->target.identity == expected.identity)) return ERROR_FILE_INVALID;
    if (attributes & FILE_ATTRIBUTE_READONLY) return ERROR_ACCESS_DENIED;
    entry->directory = (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
    const bool directory = entry->directory;
    plan.entries.push_back(std::move(entry));
    if (!directory) return ERROR_SUCCESS;
    WIN32_FIND_DATAW data = {};
    HANDLE search = FindFirstFileW((canonical + L"\\*").c_str(), &data);
    if (search == INVALID_HANDLE_VALUE) {
        error = GetLastError();
        return error == ERROR_FILE_NOT_FOUND ? ERROR_SUCCESS : error;
    }
    do {
        const std::wstring name(data.cFileName);
        if (name == L"." || name == L"..") continue;
        if (data.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) { error = ERROR_NOT_SUPPORTED; break; }
        Target child;
        child.path = canonical + L"\\" + name;
        error = PinTree(child, false, plan, depth + 1);
        if (error) break;
    } while (FindNextFileW(search, &data));
    if (!error && GetLastError() != ERROR_NO_MORE_FILES) error = GetLastError();
    FindClose(search);
    return error;
}
// Parent/child selections collapse to their outermost roots before preview and locking.
inline DWORD Prepare(const std::vector<Target>& selected, Plan& plan) {
    if (selected.empty() || selected.size() > 128 || !plan.entries.empty()) return ERROR_INVALID_PARAMETER;
    std::vector<Target> roots;
    for (const auto& target : selected) {
        bool covered = false;
        for (const auto& other : selected) {
            if (other.path.size() < target.path.size() && Contains(other.path, target.path)) { covered = true; break; }
        }
        for (const auto& other : roots) if (_wcsicmp(other.path.c_str(), target.path.c_str()) == 0) covered = true;
        if (!covered) roots.push_back(target);
    }
    for (const auto& target : roots) {
        DWORD error = PinAncestors(target.path, plan);
        if (error) return error;
        error = PinTree(target, true, plan);
        if (error) return error;
    }
    plan.roots = std::move(roots);
    plan.ready = true;
    return ERROR_SUCCESS;
}
struct Result { size_t deleted = 0; DWORD error = ERROR_SUCCESS; std::wstring failedPath; };
// Never accept an implicit default; newly created children are never part of this handle plan.
inline Result Commit(Plan& plan, bool explicitlyConfirmed) {
    Result result;
    if (!explicitlyConfirmed) return result;
    if (!plan.ready) { result.error = ERROR_INVALID_PARAMETER; return result; }
    plan.ready = false;
    for (auto it = plan.entries.rbegin(); it != plan.entries.rend(); ++it) {
        Entry& entry = **it;
        Identity current;
        DWORD attributes = 0;
        DWORD error = Read(entry.handle.value, current, attributes);
        if (!error && !(current == entry.target.identity)) error = ERROR_FILE_INVALID;
        FILE_DISPOSITION_INFO disposition = { TRUE };
        if (!error && !SetFileInformationByHandle(entry.handle.value, FileDispositionInfo, &disposition, sizeof(disposition))) error = GetLastError();
        if (error) { result.error = error; result.failedPath = entry.target.path; break; }
        entry.handle.Close();
        ++result.deleted;
    }
    return result;
}
}

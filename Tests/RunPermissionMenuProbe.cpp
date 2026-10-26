// RunPermissionMenuProbe.cpp | Jobs Windows menu policy regression
// Created by Jobs on 2026年10月26日，星期一.
// Portable Win32 read-only fixtures; no registry, process execution or real ACL writes.
#include <cassert>
#include <cstdint>
#include <iostream>
#include <string>
using DWORD = std::uint32_t;
using HANDLE = void*;
constexpr DWORD INVALID_FILE_ATTRIBUTES = 0xffffffff;
constexpr DWORD FILE_ATTRIBUTE_DIRECTORY = 0x10, FILE_ATTRIBUTE_REPARSE_POINT = 0x400;
constexpr DWORD FILE_EXECUTE = 0x20, FILE_SHARE_READ = 1, FILE_SHARE_WRITE = 2, FILE_SHARE_DELETE = 4;
constexpr DWORD OPEN_EXISTING = 3, FILE_FLAG_OPEN_REPARSE_POINT = 0x00200000;
constexpr DWORD ERROR_ACCESS_DENIED = 5;
static HANDLE const INVALID_HANDLE_VALUE = reinterpret_cast<HANDLE>(static_cast<std::intptr_t>(-1));
struct BY_HANDLE_FILE_INFORMATION { DWORD dwFileAttributes; DWORD nNumberOfLinks; };
static DWORD attributes = 0, lastError = 0, links = 1, handleAttributes = 0;
static DWORD desiredAccess = 0, sharing = 0, disposition = 0, openFlags = 0;
static bool openSucceeds = true, informationSucceeds = true;
static int opens = 0, closes = 0;
static DWORD GetFileAttributesW(const wchar_t*) { return attributes; }
static DWORD GetLastError() { return lastError; }
static HANDLE CreateFileW(const wchar_t*, DWORD access, DWORD share, void*, DWORD creation, DWORD flags, void*) {
    ++opens;
    desiredAccess = access; sharing = share; disposition = creation; openFlags = flags;
    return openSucceeds ? reinterpret_cast<HANDLE>(1) : INVALID_HANDLE_VALUE;
}
static bool GetFileInformationByHandle(HANDLE, BY_HANDLE_FILE_INFORMATION* information) {
    information->dwFileAttributes = handleAttributes;
    information->nNumberOfLinks = links;
    return informationSucceeds;
}
static void CloseHandle(HANDLE) { ++closes; }
#define _WIN32 1
#include "../JobsRunAuthorizer/Scripts/RunPermissionTarget.h"
int main() {
    using namespace JobsRunPermission;
    unsigned count = 0;
    auto check = [&count](bool value) { assert(value); ++count; };
    for (const auto path : {L"C:\\测试 & !\\app.EXE", L"C:\\dir\\start.cmd", L"C:\\dir\\script.ps1", L"C:\\dir\\worker.py", L"C:\\dir\\script.sh"}) check(IsExecutableName(path));
    for (const auto path : {L"C:\\dir\\README.md", L"C:\\dir\\notes.txt", L"C:\\dir\\app.exe.txt", L"C:\\dir.exe\\README", L"C:\\dir\\settings.psd1", L"C:\\dir\\archive.zip", L""}) check(!IsExecutableName(path));
    check(!IsActionEnabled(ExecutionState::Unknown, true));
    check(!IsActionEnabled(ExecutionState::Unknown, false));
    check(IsActionEnabled(ExecutionState::Denied, true));
    check(!IsActionEnabled(ExecutionState::Denied, false));
    check(!IsActionEnabled(ExecutionState::Allowed, true));
    check(IsActionEnabled(ExecutionState::Allowed, false));
    check(ReadExecutionState(L"C:\\dir\\app.exe") == ExecutionState::Allowed);
    check(desiredAccess == FILE_EXECUTE && sharing == 7 && disposition == OPEN_EXISTING && openFlags == FILE_FLAG_OPEN_REPARSE_POINT);
    check(opens == closes);
    const int before = opens;
    check(ReadExecutionState(L"C:\\dir\\README.md") == ExecutionState::Unknown && opens == before);
    attributes = FILE_ATTRIBUTE_DIRECTORY;
    check(!IsEligibleFile(L"C:\\dir\\folder.exe"));
    attributes = FILE_ATTRIBUTE_REPARSE_POINT;
    check(!IsEligibleFile(L"C:\\dir\\link.exe"));
    attributes = INVALID_FILE_ATTRIBUTES;
    check(!IsEligibleFile(L"C:\\dir\\missing.exe"));
    attributes = 0; openSucceeds = false; lastError = ERROR_ACCESS_DENIED;
    check(ReadExecutionState(L"C:\\dir\\app.exe") == ExecutionState::Denied);
    lastError = 32;
    check(ReadExecutionState(L"C:\\dir\\app.exe") == ExecutionState::Unknown);
    openSucceeds = true; informationSucceeds = false;
    check(ReadExecutionState(L"C:\\dir\\app.exe") == ExecutionState::Unknown);
    informationSucceeds = true; links = 2;
    check(ReadExecutionState(L"C:\\dir\\app.exe") == ExecutionState::Unknown);
    links = 1; handleAttributes = FILE_ATTRIBUTE_REPARSE_POINT;
    check(ReadExecutionState(L"C:\\dir\\app.exe") == ExecutionState::Unknown);
    std::cout << "PASS: RunPermissionMenuProbe (" << count << " assertions)\n";
}

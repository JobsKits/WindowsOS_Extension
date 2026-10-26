// HiddenFilesMenuProbe.cpp | JobsHiddenFilesToggler isolated policy regression
// Created by Jobs on 2026年10月26日，星期一.
#include <cassert>
#include <cstdint>
#include <cwchar>
#include <iostream>
#include <string>
using DWORD = std::uint32_t;
using LSTATUS = long;
static void* const HKEY_CURRENT_USER = reinterpret_cast<void*>(1);
constexpr DWORD RRF_RT_REG_DWORD = 0x10;
constexpr LSTATUS ERROR_SUCCESS = 0, ERROR_FILE_NOT_FOUND = 2;
static LSTATUS readResult = ERROR_SUCCESS;
static DWORD preference = 2;
static unsigned reads = 0;
static LSTATUS RegGetValueW(void* hive, const wchar_t* path, const wchar_t* name, DWORD flags, void*, void* result, DWORD* size) {
    assert(hive == HKEY_CURRENT_USER);
    assert(std::wstring(path) == L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced");
    assert(std::wstring(name) == L"Hidden" && flags == RRF_RT_REG_DWORD && *size == sizeof(DWORD));
    *static_cast<DWORD*>(result) = preference;
    ++reads;
    return readResult;
}
#ifndef _WIN32
#define _WIN32 1
#endif
#include "../JobsHiddenFilesToggler/Scripts/HiddenFilesMenu.h"
#include "../JobsHiddenFilesToggler/Scripts/DesktopScope.h"
int main() {
    using namespace JobsHiddenFiles;
    unsigned count = 0;
    auto check = [&count](bool value) { assert(value); ++count; };
    check(ReadState() == State::Hidden);
    check(std::wstring(ActionTitle(ReadState())) == L"👁️ 显示文件");
    preference = 1;
    check(ReadState() == State::Visible);
    check(std::wstring(ActionTitle(ReadState())) == L"🙈 隐藏文件");
    readResult = ERROR_FILE_NOT_FOUND;
    check(ReadState() == State::Hidden);
    readResult = 5;
    check(ReadState() == State::Unknown);
    readResult = 1630;
    check(ReadState() == State::Unknown);
    readResult = ERROR_SUCCESS; preference = 0;
    check(ReadState() == State::Unknown);
    preference = 3;
    check(ReadState() == State::Unknown);
    check(std::wstring(ActionTitle(State::Unknown)) == L"⚠️ 隐藏文件状态不可用");
    check(IsDesktopContext(false, L"C:\\Users\\Jobs\\Desktop", L"c:/users/jobs/desktop/"));
    check(!IsDesktopContext(true, L"C:\\Users\\Jobs\\Desktop", L"C:\\Users\\Jobs\\Desktop"));
    check(!IsDesktopContext(false, L"C:\\Users\\Jobs\\Desktop\\child", L"C:\\Users\\Jobs\\Desktop"));
    check(!IsDesktopContext(false, L"C:\\work", L"C:\\Users\\Jobs\\Desktop"));
    check(!IsDesktopContext(false, L"", L"C:\\Users\\Jobs\\Desktop"));
    check(reads == 9);
    std::cout << "PASS: HiddenFilesMenuProbe (" << count << " assertions)\n";
}

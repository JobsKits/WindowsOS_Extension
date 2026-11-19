// windows.h | desktop menu isolated boundary
// Created by Jobs on 2026年11月18日，星期三.
#pragma once
#include "../../../JobsDiskSpaceInfo/Tests/ContextMenuFreshnessTests.cpp/Win32Stubs/windows.h"
using PWSTR = wchar_t*;
using LSTATUS = long;
#define SUCCEEDED(value) ((value) >= 0)
constexpr DWORD CREATE_NO_WINDOW = 0x08000000, KF_FLAG_DONT_VERIFY = 0x4000;
constexpr UINT GPFIDL_DEFAULT = 0;
constexpr unsigned short PROCESSOR_ARCHITECTURE_AMD64 = 9, PROCESSOR_ARCHITECTURE_ARM64 = 12;
constexpr DWORD RRF_RT_REG_DWORD = 0x10;
constexpr LSTATUS ERROR_SUCCESS = 0;
static HKEY const HKEY_CURRENT_USER = reinterpret_cast<HKEY>(1);
struct SYSTEM_INFO { unsigned short wProcessorArchitecture; };
void GetNativeSystemInfo(SYSTEM_INFO*);
LSTATUS RegGetValueW(HKEY, LPCWSTR, LPCWSTR, DWORD, DWORD*, void*, DWORD*);


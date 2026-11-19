// windows.h | JobsDiskSpaceInfo isolated test boundary
// Created by Jobs on 2026年11月16日，星期一.
#pragma once
#include <cstddef>
#include <cstdint>
#include <cwchar>
#include <cstring>

#define WINAPI
#define STDMETHODCALLTYPE
#define __stdcall
using BOOL = int;
using DWORD = std::uint32_t;
using UINT = unsigned;
using ULONG = std::uint32_t;
using ULONGLONG = std::uint64_t;
using UINT_PTR = std::uintptr_t;
using ULONG_PTR = std::uintptr_t;
using HRESULT = std::int32_t;
using LANGID = std::uint16_t;
using LPVOID = void*;
using HANDLE = void*;
using HMODULE = void*;
using HINSTANCE = void*;
using HKEY = void*;
using HMENU = void*;
using LPCWSTR = const wchar_t*;
using LPCSTR = const char*;
using LPSTR = char*;
using FARPROC = void (*)();
struct GUID { std::uint32_t a; std::uint16_t b, c; std::uint8_t d[8]; };
using CLSID = GUID;
using REFIID = const GUID&;
using REFCLSID = const GUID&;
inline bool IsEqualIID(REFIID a, REFIID b) { return std::memcmp(&a, &b, sizeof(GUID)) == 0; }
inline bool IsEqualCLSID(REFCLSID a, REFCLSID b) { return IsEqualIID(a, b); }
constexpr HRESULT S_OK = 0, S_FALSE = 1;
constexpr HRESULT E_POINTER = static_cast<HRESULT>(0x80004003u);
constexpr HRESULT E_NOINTERFACE = static_cast<HRESULT>(0x80004002u);
constexpr HRESULT E_OUTOFMEMORY = static_cast<HRESULT>(0x8007000eu);
constexpr HRESULT E_INVALIDARG = static_cast<HRESULT>(0x80070057u);
constexpr HRESULT E_FAIL = static_cast<HRESULT>(0x80004005u);
constexpr HRESULT E_NOTIMPL = static_cast<HRESULT>(0x80004001u);
constexpr HRESULT CLASS_E_NOAGGREGATION = static_cast<HRESULT>(0x80040110u);
constexpr HRESULT CLASS_E_CLASSNOTAVAILABLE = static_cast<HRESULT>(0x80040111u);
#define FAILED(value) ((value) < 0)
#define MAKE_HRESULT(severity, facility, code) static_cast<HRESULT>((static_cast<std::uint32_t>(severity) << 31) | ((facility) << 16) | (code))
#define HRESULT_FROM_WIN32(value) static_cast<HRESULT>((value) ? 0x80070000u | (value) : 0)
#define LOWORD(value) (static_cast<std::uintptr_t>(reinterpret_cast<std::uintptr_t>(value)) & 0xffffu)
#define HIWORD(value) ((reinterpret_cast<std::uintptr_t>(value) >> 16) & 0xffffu)
#define INVALID_HANDLE_VALUE reinterpret_cast<HANDLE>(static_cast<std::intptr_t>(-1))
constexpr BOOL FALSE = 0, TRUE = 1;
constexpr DWORD MAX_PATH = 260, SEM_FAILCRITICALERRORS = 1;
constexpr DWORD ERROR_ACCESS_DENIED = 5, ERROR_FILE_NOT_FOUND = 2, ERROR_BAD_LENGTH = 24;
constexpr DWORD ERROR_MORE_DATA = 234, ERROR_NO_MORE_FILES = 18;
constexpr UINT DRIVE_FIXED = 3, DRIVE_REMOVABLE = 2, DRIVE_REMOTE = 4, DRIVE_CDROM = 5;
constexpr DWORD FILE_READ_ONLY_VOLUME = 0x80000, FILE_ATTRIBUTE_DIRECTORY = 0x10, FILE_ATTRIBUTE_REPARSE_POINT = 0x400;
constexpr DWORD INVALID_FILE_ATTRIBUTES = 0xffffffffu, CREATE_NEW_CONSOLE = 0x10;
constexpr UINT MF_BYPOSITION = 0x400, MF_STRING = 0, MF_ENABLED = 0, SEVERITY_SUCCESS = 0;
constexpr UINT MIIM_STATE = 1, MIIM_ID = 2, MIIM_DATA = 0x20, MIIM_STRING = 0x40;
constexpr UINT MFS_ENABLED = 0, MFS_DISABLED = 3;
constexpr DWORD DLL_PROCESS_ATTACH = 1;
constexpr LANGID LANG_CHINESE = 4, LANG_TIBETAN = 0x51, LANG_JAPANESE = 0x11, LANG_FRENCH = 0x0c;
constexpr LANGID LANG_SPANISH = 0x0a, LANG_GERMAN = 7, LANG_RUSSIAN = 0x19, LANG_KOREAN = 0x12;
constexpr LANGID SUBLANG_CHINESE_TRADITIONAL = 1, SUBLANG_CHINESE_HONGKONG = 3, SUBLANG_CHINESE_MACAU = 5;
#define PRIMARYLANGID(value) ((value) & 0x3ff)
#define SUBLANGID(value) ((value) >> 10)
struct STARTUPINFOW { DWORD cb; };
struct PROCESS_INFORMATION { HANDLE hProcess, hThread; };
struct MENUITEMINFOW {
    UINT cbSize, fMask, fType, fState, wID;
    HMENU hSubMenu;
    void* hbmpChecked;
    void* hbmpUnchecked;
    ULONG_PTR dwItemData;
    wchar_t* dwTypeData;
    UINT cch;
    void* hbmpItem;
};
BOOL SetThreadErrorMode(DWORD, DWORD*);
HMODULE GetModuleHandleW(LPCWSTR);
FARPROC GetProcAddress(HMODULE, const char*);
HANDLE FindFirstVolumeW(wchar_t*, DWORD);
BOOL FindNextVolumeW(HANDLE, wchar_t*, DWORD);
BOOL FindVolumeClose(HANDLE);
UINT GetDriveTypeW(LPCWSTR);
BOOL GetVolumePathNamesForVolumeNameW(LPCWSTR, wchar_t*, DWORD, DWORD*);
DWORD GetLastError();
BOOL GetVolumeInformationW(LPCWSTR, wchar_t*, DWORD, DWORD*, DWORD*, DWORD*, wchar_t*, DWORD);
LANGID GetUserDefaultUILanguage();
BOOL InsertMenuW(HMENU, UINT, UINT, UINT_PTR, LPCWSTR);
int GetMenuItemCount(HMENU);
BOOL GetMenuItemInfoW(HMENU, UINT, BOOL, MENUITEMINFOW*);
BOOL InsertMenuItemW(HMENU, UINT, BOOL, const MENUITEMINFOW*);
DWORD GetModuleFileNameW(HMODULE, wchar_t*, DWORD);
UINT GetSystemDirectoryW(wchar_t*, UINT);
DWORD GetFileAttributesW(LPCWSTR);
BOOL CreateProcessW(LPCWSTR, wchar_t*, void*, void*, BOOL, DWORD, void*, LPCWSTR, STARTUPINFOW*, PROCESS_INFORMATION*);
BOOL CloseHandle(HANDLE);

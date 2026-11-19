// ContextMenu.cpp | JobsDiskSpaceInfo
// Created by Jobs on 2026年11月15日，星期日.
// 容量显示始终可点击；仅打开独立终端，清理范围与确认由随包脚本负责。
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <shlobj.h>
#include <atomic>
#include <new>
#include <vector>
#include "DiskSpaceSummary.h"
#include "DesktopMenuOrder.h"

const CLSID CLSID_JobsDiskSpaceInfo = {0xe10272dd, 0x32af, 0x4bd0, {0x97, 0xd2, 0xb7, 0x4d, 0x20, 0x1f, 0xa6, 0xf1}};
static std::atomic<long> objects(0);
static HMODULE moduleHandle = nullptr;

// 按 CommandLineToArgvW 规则引用本包脚本路径，不把路径拼成可执行表达式。
static std::wstring QuoteArgument(const std::wstring& value) {
    std::wstring result = L"\"";
    size_t slashes = 0;
    for (wchar_t character : value) {
        if (character == L'\\') { ++slashes; continue; }
        result.append(character == L'"' ? slashes * 2 + 1 : slashes, L'\\');
        result += character;
        slashes = 0;
    }
    result.append(slashes * 2, L'\\');
    return result + L"\"";
}

namespace JobsDiskSpaceInfo {
// SDK 旧头文件也能编译；结构布局对应微软公开 DISK_SPACE_INFORMATION。
struct DiskSpaceInformation {
    ULONGLONG actualTotal, actualAvailable, actualPoolUnavailable;
    ULONGLONG callerTotal, callerAvailable, callerPoolUnavailable;
    ULONGLONG used, reserved, storageReserve, committed, poolAvailable;
    DWORD sectorsPerUnit, bytesPerSector;
};
static_assert(sizeof(DiskSpaceInformation) == 96, "DISK_SPACE_INFORMATION layout");
using ReadDiskSpace = HRESULT (WINAPI*)(LPCWSTR, DiskSpaceInformation*);

// 仅更改当前查询线程的错误对话框策略，退出查询后恢复，不改变 Explorer 进程全局策略。
class ErrorMode final {
    DWORD previous = 0;
    bool changed = false;
public:
    ErrorMode() { changed = SetThreadErrorMode(SEM_FAILCRITICALERRORS, &previous) != FALSE; }
    ~ErrorMode() { if (changed) SetThreadErrorMode(previous, nullptr); }
};

class VolumeSearch final {
public:
    HANDLE handle;
    explicit VolumeSearch(HANDLE value) : handle(value) {}
    ~VolumeSearch() { if (handle != INVALID_HANDLE_VALUE) FindVolumeClose(handle); }
};

// GUID 枚举不随盘符、SUBST 或挂载别名重复；网络盘不会进入本地卷查询。
static Summary ReadSummary() {
    ErrorMode errorMode;
    Summary result;
    // 1809+ 的公开 API 区分真实容量与用户配额，旧系统不伪装成全盘总量。
    const auto readSpace = reinterpret_cast<ReadDiskSpace>(GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "GetDiskSpaceInformationW"));
    if (!readSpace) {
        result.complete = false;
        return result;
    }
    wchar_t volume[MAX_PATH] = {};
    VolumeSearch search(FindFirstVolumeW(volume, MAX_PATH));
    if (search.handle == INVALID_HANDLE_VALUE) {
        result.complete = false;
        return result;
    }
    for (;;) {
        const UINT type = GetDriveTypeW(volume);
        if (type == DRIVE_FIXED || type == DRIVE_REMOVABLE) {
            DWORD needed = 0;
            std::vector<wchar_t> paths(32768);
            bool mounted = GetVolumePathNamesForVolumeNameW(volume, paths.data(), static_cast<DWORD>(paths.size()), &needed) != FALSE;
            if (!mounted && GetLastError() == ERROR_MORE_DATA && needed <= 1024 * 1024) {
                paths.resize(needed);
                mounted = GetVolumePathNamesForVolumeNameW(volume, paths.data(), static_cast<DWORD>(paths.size()), &needed) != FALSE;
            }
            // 隐藏恢复/EFI 分区没有用户挂载路径，不属于可用存储总量。
            if (!mounted) result.complete = false;
            else if (!paths.empty() && paths[0]) {
                DWORD fileSystemFlags = 0;
                if (!GetVolumeInformationW(volume, nullptr, 0, nullptr, nullptr, &fileSystemFlags, nullptr, 0)) {
                    result.complete = false;
                } else if (!(fileSystemFlags & FILE_READ_ONLY_VOLUME)) {
                    DiskSpaceInformation space = {};
                    if (FAILED(readSpace(volume, &space))) result.complete = false;
                    else result.AddAllocationUnits(volume, space.actualTotal, space.actualAvailable,
                                                   space.actualPoolUnavailable, space.sectorsPerUnit, space.bytesPerSector);
                }
            }
        }
        if (!FindNextVolumeW(search.handle, volume, MAX_PATH)) {
            if (GetLastError() != ERROR_NO_MORE_FILES) result.complete = false;
            break;
        }
    }
    return result;
}

// 菜单跟随 Windows 显示语言；管理面板仍使用既有独立语言选择与主题设置。
static std::string SystemLanguage() {
    const LANGID language = GetUserDefaultUILanguage();
    switch (PRIMARYLANGID(language)) {
        case LANG_CHINESE:
            switch (SUBLANGID(language)) {
                case SUBLANG_CHINESE_TRADITIONAL:
                case SUBLANG_CHINESE_HONGKONG:
                case SUBLANG_CHINESE_MACAU: return "zh-Hant";
                default: return "zh-Hans";
            }
        case LANG_TIBETAN: return "bo";
        case LANG_JAPANESE: return "ja";
        case LANG_FRENCH: return "fr";
        case LANG_SPANISH: return "es";
        case LANG_GERMAN: return "de";
        case LANG_RUSSIAN: return "ru";
        case LANG_KOREAN: return "ko";
        default: return "en";
    }
}
}

class Menu final : public IShellExtInit, public IContextMenu {
    std::atomic<ULONG> references;
public:
    Menu() : references(1) { ++objects; }
    ~Menu() { --objects; }
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** output) override {
        if (!output) return E_POINTER;
        *output = nullptr;
        if (IsEqualIID(iid, IID_IUnknown) || IsEqualIID(iid, IID_IShellExtInit)) *output = static_cast<IShellExtInit*>(this);
        else if (IsEqualIID(iid, IID_IContextMenu)) *output = static_cast<IContextMenu*>(this);
        else return E_NOINTERFACE;
        AddRef();
        return S_OK;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++references; }
    ULONG STDMETHODCALLTYPE Release() override {
        const ULONG count = --references;
        if (!count) delete this;
        return count;
    }
    HRESULT STDMETHODCALLTYPE Initialize(PCIDLIST_ABSOLUTE, IDataObject*, HKEY) override { return S_OK; }
    HRESULT STDMETHODCALLTYPE QueryContextMenu(HMENU menu, UINT position, UINT first, UINT last, UINT flags) override {
        if ((flags & CMF_DEFAULTONLY) || first > last) return MAKE_HRESULT(SEVERITY_SUCCESS, 0, 0);
        try {
            const std::wstring title = JobsDiskSpaceInfo::FormatTitle(JobsDiskSpaceInfo::ReadSummary(), JobsDiskSpaceInfo::SystemLanguage());
            if (!JobsDesktopMenuOrder::Insert(menu, position, first, JobsDesktopMenuOrder::Rank::DiskSpace, title.c_str())) return HRESULT_FROM_WIN32(GetLastError());
            return MAKE_HRESULT(SEVERITY_SUCCESS, 0, 1);
        } catch (...) {
            return E_OUTOFMEMORY;
        }
    }
    HRESULT STDMETHODCALLTYPE InvokeCommand(CMINVOKECOMMANDINFO* info) override {
        if (!info || HIWORD(info->lpVerb) || LOWORD(info->lpVerb) != 0 || !moduleHandle) return E_INVALIDARG;
        wchar_t path[32768] = {}, system[32768] = {};
        const DWORD length = GetModuleFileNameW(moduleHandle, path, 32768);
        const UINT systemLength = GetSystemDirectoryW(system, 32768);
        if (!length || length >= 32768 || !systemLength || systemLength >= 32768) return E_FAIL;
        std::wstring folder(path);
        folder.resize(folder.find_last_of(L"\\/")); // bin
        folder.resize(folder.find_last_of(L"\\/")); // release
        const std::wstring script = folder + L"\\Scripts\\Clean.ps1\\Clean.ps1";
        const DWORD attributes = GetFileAttributesW(script.c_str());
        if (attributes == INVALID_FILE_ATTRIBUTES || (attributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT))) return HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND);
        const std::wstring powershell = std::wstring(system) + L"\\WindowsPowerShell\\v1.0\\powershell.exe";
        std::wstring command = QuoteArgument(powershell) + L" -NoLogo -NoProfile -NoExit -STA -ExecutionPolicy Bypass -File " + QuoteArgument(script);
        if (command.size() >= 32767) return HRESULT_FROM_WIN32(ERROR_BAD_LENGTH);
        STARTUPINFOW startup = {};
        startup.cb = sizeof(startup);
        PROCESS_INFORMATION process = {};
        if (!CreateProcessW(powershell.c_str(), &command[0], nullptr, nullptr, FALSE, CREATE_NEW_CONSOLE, nullptr, folder.c_str(), &startup, &process)) return HRESULT_FROM_WIN32(GetLastError());
        CloseHandle(process.hThread);
        CloseHandle(process.hProcess);
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetCommandString(UINT_PTR, UINT, UINT*, LPSTR, UINT) override { return E_NOTIMPL; }
};

class Factory final : public IClassFactory {
    std::atomic<ULONG> references;
public:
    Factory() : references(1) { ++objects; }
    ~Factory() { --objects; }
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** output) override {
        if (!output) return E_POINTER;
        *output = nullptr;
        if (!IsEqualIID(iid, IID_IUnknown) && !IsEqualIID(iid, IID_IClassFactory)) return E_NOINTERFACE;
        *output = static_cast<IClassFactory*>(this);
        AddRef();
        return S_OK;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++references; }
    ULONG STDMETHODCALLTYPE Release() override {
        const ULONG count = --references;
        if (!count) delete this;
        return count;
    }
    HRESULT STDMETHODCALLTYPE CreateInstance(IUnknown* outer, REFIID iid, void** output) override {
        if (outer) return CLASS_E_NOAGGREGATION;
        Menu* instance = new (std::nothrow) Menu();
        if (!instance) return E_OUTOFMEMORY;
        const HRESULT result = instance->QueryInterface(iid, output);
        instance->Release();
        return result;
    }
    HRESULT STDMETHODCALLTYPE LockServer(BOOL lock) override {
        if (lock) ++objects;
        else --objects;
        return S_OK;
    }
};
extern "C" HRESULT __stdcall DllGetClassObject(REFCLSID clsid, REFIID iid, void** output) {
    if (!IsEqualCLSID(clsid, CLSID_JobsDiskSpaceInfo)) return CLASS_E_CLASSNOTAVAILABLE;
    Factory* factory = new (std::nothrow) Factory();
    if (!factory) return E_OUTOFMEMORY;
    const HRESULT result = factory->QueryInterface(iid, output);
    factory->Release();
    return result;
}
extern "C" HRESULT __stdcall DllCanUnloadNow() { return objects.load() == 0 ? S_OK : S_FALSE; }
BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) moduleHandle = instance;
    return TRUE;
}

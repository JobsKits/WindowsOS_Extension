// ContextMenu.cpp | JobsFlutterTools
// Created by Jobs on 2026年10月20日，星期二.
// 原生桥接只检查本地 pubspec；Flutter / PowerShell / CLR 不进入 Explorer 进程。
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <shlobj.h>
#include <shellapi.h>
#include <shlwapi.h>
#include <atomic>
#include <fstream>
#include <iterator>
#include <new>
#include "FlutterProject.h"
#include "FlutterToolsMenu.h"

const CLSID CLSID_JobsFlutterTools = {0x55c8c7a9,0x8625,0x4af0,{0x85,0x98,0xdf,0xa9,0x75,0x06,0x4f,0x0c}};
static HMODULE moduleHandle;
static std::atomic<long> objects(0);

static std::wstring ReleaseFolder() {
    wchar_t path[32768];
    const DWORD length = GetModuleFileNameW(moduleHandle, path, 32768);
    if (!length || length >= 32768) return L"";
    std::wstring folder(path);
    folder.resize(folder.find_last_of(L"\\/"));
    folder.resize(folder.find_last_of(L"\\/"));
    return folder;
}
static bool ReadSelection(JobsFlutterTools::Selection& selected, std::wstring* currentRelease = nullptr) {
    selected.fill(false);
    auto folder = ReleaseFolder();
    if (folder.empty()) return false;
    wchar_t local[32768];
    DWORD localLength = GetEnvironmentVariableW(L"LOCALAPPDATA", local, 32768);
    if (!localLength || localLength >= 32768) {
        if (FAILED(SHGetFolderPathW(nullptr, CSIDL_LOCAL_APPDATA, nullptr, SHGFP_TYPE_CURRENT, local))) return false;
    }
    const auto statePath = std::wstring(local) + L"\\Jobs\\WindowsExtension\\extensions\\flutter-tools\\menu-state.txt";
    WIN32_FILE_ATTRIBUTE_DATA data;
    if (GetFileAttributesExW(statePath.c_str(), GetFileExInfoStandard, &data)) {
        if ((data.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) || data.nFileSizeHigh || data.nFileSizeLow > 65536) return false;
        std::ifstream state(statePath.c_str(), std::ios::binary);
        if (!state) return false;
        const std::string stateText((std::istreambuf_iterator<char>(state)), std::istreambuf_iterator<char>());
        std::string release;
        if (!JobsFlutterTools::ParseMenuState(stateText, release, selected)) return false;
        const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, release.data(), static_cast<int>(release.size()), nullptr, 0);
        if (!length || release.find('\0') != std::string::npos) return false;
        folder.resize(length);
        if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, release.data(), static_cast<int>(release.size()), &folder[0], length) || PathIsRelativeW(folder.c_str()) || PathIsUNCW(folder.c_str())) return false;
        if (currentRelease) *currentRelease = folder;
        return true;
    }
    if (GetLastError() != ERROR_FILE_NOT_FOUND && GetLastError() != ERROR_PATH_NOT_FOUND) return false;
    const auto path = folder + L"\\menu-actions.txt";
    if (!GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &data)) {
        if (GetLastError() != ERROR_FILE_NOT_FOUND) return false;
        selected.fill(true); // 旧 release 没有子功能白名单，保持全开兼容。
        if (currentRelease) *currentRelease = folder;
        return true;
    }
    if ((data.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) || data.nFileSizeHigh || data.nFileSizeLow > 4096) return false;
    std::ifstream input(path.c_str(), std::ios::binary);
    if (!input) return false;
    const std::string text((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
    if (!JobsFlutterTools::ParseSelection(text, selected)) return false;
    if (currentRelease) *currentRelease = folder;
    return true;
}

static bool IsPlainPath(const std::wstring& path, bool directory) {
    const DWORD attributes = GetFileAttributesW(path.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES || (attributes & FILE_ATTRIBUTE_REPARSE_POINT)) return false;
    if (!!(attributes & FILE_ATTRIBUTE_DIRECTORY) != directory) return false;
    // 拒绝目录祖先中的 junction / symlink，和点击后的验证保持相同边界。
    std::wstring parent = path;
    while (parent.size() > 3) {
        const size_t slash = parent.find_last_of(L"\\/");
        if (slash == std::wstring::npos || slash < 3) break;
        parent.resize(slash);
        const DWORD flags = GetFileAttributesW(parent.c_str());
        if (flags == INVALID_FILE_ATTRIBUTES || (flags & FILE_ATTRIBUTE_REPARSE_POINT)) return false;
    }
    return true;
}
static bool IsProject(const std::wstring& path) {
    if (path.empty() || PathIsUNCW(path.c_str()) || !IsPlainPath(path, true)) return false;
    const int drive = PathGetDriveNumberW(path.c_str());
    if (drive < 0) return false;
    const wchar_t root[] = { static_cast<wchar_t>(L'A' + drive), L':', L'\\', 0 };
    if (GetDriveTypeW(root) == DRIVE_REMOTE) return false;
    const std::wstring pubspec = path + L"\\pubspec.yaml";
    if (!IsPlainPath(pubspec, false)) return false;
    WIN32_FILE_ATTRIBUTE_DATA data;
    if (!GetFileAttributesExW(pubspec.c_str(), GetFileExInfoStandard, &data) || data.nFileSizeHigh || data.nFileSizeLow > 1024 * 1024) return false;
    std::ifstream input(pubspec.c_str(), std::ios::binary);
    if (!input) return false;
    const std::string text((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
    return JobsFlutter::IsFlutterPubspec(text);
}
static std::wstring Quote(const std::wstring& value) {
    std::wstring result = L"\"";
    size_t slashes = 0;
    for (wchar_t c : value) {
        if (c == L'\\') { ++slashes; continue; }
        result.append(c == L'"' ? slashes * 2 + 1 : slashes, L'\\');
        result += c;
        slashes = 0;
    }
    result.append(slashes * 2, L'\\');
    return result + L"\"";
}
class Menu final : public IShellExtInit, public IContextMenu {
    std::atomic<ULONG> references;
    std::wstring target;
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
    ULONG STDMETHODCALLTYPE Release() override { ULONG count = --references; if (!count) delete this; return count; }
    HRESULT STDMETHODCALLTYPE Initialize(PCIDLIST_ABSOLUTE folder, IDataObject* selection, HKEY) override {
        target.clear();
        if (selection) {
            FORMATETC format = {CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
            STGMEDIUM medium = {};
            if (FAILED(selection->GetData(&format, &medium))) return S_OK;
            HDROP drop = static_cast<HDROP>(medium.hGlobal);
            if (drop) {
                if (DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0) == 1) {
                    const UINT length = DragQueryFileW(drop, 0, nullptr, 0);
                    std::vector<wchar_t> path(length + 1);
                    if (DragQueryFileW(drop, 0, path.data(), length + 1)) target.assign(path.data());
                }
            }
            ReleaseStgMedium(&medium);
        } else if (folder) {
            std::vector<wchar_t> path(32768);
            if (SHGetPathFromIDListEx(folder, path.data(), static_cast<DWORD>(path.size()), GPFIDL_DEFAULT)) target.assign(path.data());
        }
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE QueryContextMenu(HMENU menu, UINT position, UINT first, UINT last, UINT flags) override {
        if ((flags & CMF_DEFAULTONLY) || first > last || last - first + 1 < JobsFlutterTools::Count || !IsProject(target)) return MAKE_HRESULT(SEVERITY_SUCCESS, 0, 0);
        JobsFlutterTools::Selection selected;
        if (!ReadSelection(selected)) return MAKE_HRESULT(SEVERITY_SUCCESS, 0, 0);
        HMENU development = CreatePopupMenu(), doctors = CreatePopupMenu(), repairs = CreatePopupMenu();
        if (!development || !doctors || !repairs) {
            if (development) DestroyMenu(development); if (doctors) DestroyMenu(doctors); if (repairs) DestroyMenu(repairs);
            return E_OUTOFMEMORY;
        }
        for (UINT i = 0; i < JobsFlutterTools::Count; ++i) {
            if (!selected[i]) continue;
            HMENU parent = i < 8 || i == 10 ? development : (i < 10 ? doctors : repairs);
            if (!AppendMenuW(parent, MF_STRING, first + i, JobsFlutterTools::Entries[i].label)) {
                DestroyMenu(development); DestroyMenu(doctors); DestroyMenu(repairs); return E_FAIL;
            }
        }
        if (GetMenuItemCount(doctors) > 0) {
            if (!AppendMenuW(development, MF_POPUP, reinterpret_cast<UINT_PTR>(doctors), L"🏥 Flutter项目体检")) {
                DestroyMenu(development); DestroyMenu(doctors); DestroyMenu(repairs); return E_FAIL;
            }
        } else { DestroyMenu(doctors); }
        bool insertedDevelopment = false;
        if (GetMenuItemCount(development) > 0) {
            if (!InsertMenuW(menu, position, MF_BYPOSITION | MF_POPUP, reinterpret_cast<UINT_PTR>(development), L"🦋 Flutter开发相关辅助工具")) { DestroyMenu(development); DestroyMenu(repairs); return E_FAIL; }
            insertedDevelopment = true;
        } else { DestroyMenu(development); }
        if (GetMenuItemCount(repairs) > 0) {
            if (!InsertMenuW(menu, position + (insertedDevelopment ? 1 : 0), MF_BYPOSITION | MF_POPUP, reinterpret_cast<UINT_PTR>(repairs), L"🔧 Flutter项目修复")) {
                if (insertedDevelopment) { RemoveMenu(menu, position, MF_BYPOSITION); DestroyMenu(development); }
                DestroyMenu(repairs); return E_FAIL;
            }
        } else { DestroyMenu(repairs); }
        return MAKE_HRESULT(SEVERITY_SUCCESS, 0, JobsFlutterTools::Count);
    }

    HRESULT STDMETHODCALLTYPE InvokeCommand(CMINVOKECOMMANDINFO* info) override {
        if (!info || HIWORD(info->lpVerb) || LOWORD(info->lpVerb) >= JobsFlutterTools::Count || !IsProject(target)) return E_INVALIDARG;
        JobsFlutterTools::Selection selected;
        std::wstring folder;
        if (!ReadSelection(selected, &folder) || !selected[LOWORD(info->lpVerb)]) return E_ACCESSDENIED;
        const std::wstring script = folder + L"\\Scripts\\OpenCmd.ps1";
        wchar_t system[32768];
        if (!GetSystemDirectoryW(system, 32768)) return E_FAIL;
        const std::wstring powershell = std::wstring(system) + L"\\WindowsPowerShell\\v1.0\\powershell.exe";
        std::wstring command = Quote(powershell) + L" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File " + Quote(script) + L" -Target " + Quote(target) + L" -Action " + Quote(JobsFlutterTools::Entries[LOWORD(info->lpVerb)].action);
        STARTUPINFOW startup = {};
        startup.cb = sizeof(startup);
        PROCESS_INFORMATION process = {};
        if (!CreateProcessW(powershell.c_str(), &command[0], nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, folder.c_str(), &startup, &process)) return HRESULT_FROM_WIN32(GetLastError());
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
        *output = static_cast<IClassFactory*>(this); AddRef(); return S_OK;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++references; }
    ULONG STDMETHODCALLTYPE Release() override { ULONG count = --references; if (!count) delete this; return count; }
    HRESULT STDMETHODCALLTYPE CreateInstance(IUnknown* outer, REFIID iid, void** output) override {
        if (outer) return CLASS_E_NOAGGREGATION;
        Menu* instance = new (std::nothrow) Menu();
        if (!instance) return E_OUTOFMEMORY;
        const HRESULT result = instance->QueryInterface(iid, output);
        instance->Release();
        return result;
    }
    HRESULT STDMETHODCALLTYPE LockServer(BOOL lock) override { if (lock) ++objects; else --objects; return S_OK; }
};
extern "C" HRESULT __stdcall DllGetClassObject(REFCLSID clsid, REFIID iid, void** output) {
    if (!IsEqualCLSID(clsid, CLSID_JobsFlutterTools)) return CLASS_E_CLASSNOTAVAILABLE;
    Factory* factory = new (std::nothrow) Factory();
    if (!factory) return E_OUTOFMEMORY;
    const HRESULT result = factory->QueryInterface(iid, output);
    factory->Release();
    return result;
}
extern "C" HRESULT __stdcall DllCanUnloadNow() { return objects.load() == 0 ? S_OK : S_FALSE; }
BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) { moduleHandle = instance; }
    return TRUE;
}

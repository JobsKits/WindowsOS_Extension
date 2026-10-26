// ContextMenu.cpp | JobsSourcetreeOpener
// Created by Jobs on 2026年10月26日，星期一.
// 原生桥接只读 Git 元数据；Git / PowerShell / CLR 不进入 Explorer 进程。
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
#include <vector>
#include "GitRepository.h"
#include "SourcetreeInstallation.h"

const CLSID CLSID_JobsSourcetreeOpener = {0xcf4d4697,0x749b,0x4c37,{0x98,0xec,0x09,0x52,0xb2,0xef,0x1e,0x16}};
static HMODULE moduleHandle;
static std::atomic<long> objects(0);

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
// 包含元数据路径的所有祖先也必须是普通目录。
static int PathKind(const std::wstring& path) {
    const DWORD flags = GetFileAttributesW(path.c_str());
    if (flags == INVALID_FILE_ATTRIBUTES) {
        const DWORD error = GetLastError();
        return (error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND) ? -1 : 2;
    }
    const bool directory = (flags & FILE_ATTRIBUTE_DIRECTORY) != 0;
    if (!IsPlainPath(path, directory)) return 2;
    return directory ? 1 : 0;
}
static bool ReadMetadata(const std::wstring& path, std::wstring& output) {
    WIN32_FILE_ATTRIBUTE_DATA data;
    if (PathKind(path) != 0 || !GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &data) || data.nFileSizeHigh || data.nFileSizeLow > 8192) return false;
    std::ifstream input(path.c_str(), std::ios::binary);
    const std::string bytes((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
    if (!input || bytes.empty()) return false;
    const int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, bytes.data(), static_cast<int>(bytes.size()), nullptr, 0);
    if (count <= 0) return false;
    output.resize(count);
    return MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, bytes.data(), static_cast<int>(bytes.size()), &output[0], count) == count;
}
static std::wstring Absolute(const std::wstring& path) {
    if (path.empty() || PathIsUNCW(path.c_str())) return L"";
    std::vector<wchar_t> buffer(32768);
    const DWORD length = GetFullPathNameW(path.c_str(), static_cast<DWORD>(buffer.size()), buffer.data(), nullptr);
    if (!length || length >= buffer.size()) return L"";
    const std::wstring result(buffer.data());
    const int drive = PathGetDriveNumberW(result.c_str());
    if (drive < 0) return L"";
    const wchar_t root[] = { static_cast<wchar_t>(L'A' + drive), L':', L'\\', 0 };
    return GetDriveTypeW(root) == DRIVE_REMOTE ? L"" : result;
}
static bool IsProject(const std::wstring& path) {
    if (path.empty() || Absolute(path).empty()) return false;
    JobsGit::Files files { PathKind, ReadMetadata, Absolute };
    return JobsGit::WorkingTree(files, path);
}
static std::wstring Environment(const wchar_t* name) {
    wchar_t buffer[32768];
    const DWORD length = GetEnvironmentVariableW(name, buffer, 32768);
    return length && length < 32768 ? std::wstring(buffer, length) : L"";
}
static std::wstring FindApplication() {
    std::vector<std::wstring> candidates;
    for (HKEY hive : {HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE}) {
        wchar_t value[32768];
        DWORD size = sizeof(value);
        if (RegGetValueW(hive, L"Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\SourceTree.exe", nullptr,
                         RRF_RT_REG_SZ | RRF_RT_REG_EXPAND_SZ, nullptr, value, &size) != ERROR_SUCCESS) continue;
        std::wstring path(value);
        if (path.size() >= 2 && path.front() == L'"' && path.back() == L'"') path = path.substr(1, path.size() - 2);
        candidates.push_back(path);
    }
    for (const auto name : {L"LOCALAPPDATA", L"ProgramFiles", L"ProgramFiles(x86)"}) {
        const auto base = Environment(name);
        if (base.empty()) continue;
        candidates.push_back(base + L"\\SourceTree\\SourceTree.exe");
        candidates.push_back(base + L"\\Atlassian\\SourceTree\\SourceTree.exe");
    }
    return JobsSourcetree::Find(candidates, [](const std::wstring& path) {
        const DWORD flags = GetFileAttributesW(path.c_str());
        return !PathIsRelativeW(path.c_str()) && flags != INVALID_FILE_ATTRIBUTES && !(flags & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT));
    });
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
// 多个独立 Git handler 共享已插入的父菜单，调用顺序不产生重复分组。
static HMENU ExistingGitMenu(HMENU menu) {
    for (int index = 0; index < GetMenuItemCount(menu); ++index) {
        wchar_t title[128];
        MENUITEMINFOW item = {};
        item.cbSize = sizeof(item);
        item.fMask = MIIM_STRING | MIIM_SUBMENU;
        item.dwTypeData = title;
        item.cch = 128;
        if (GetMenuItemInfoW(menu, index, TRUE, &item) && item.hSubMenu && std::wstring(title) == L"🌿 Git操作") return item.hSubMenu;
    }
    return nullptr;
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
        if ((flags & CMF_DEFAULTONLY) || first > last || (!IsProject(target) || FindApplication().empty())) return MAKE_HRESULT(SEVERITY_SUCCESS, 0, 0);
        HMENU group = ExistingGitMenu(menu);
        const bool created = !group;
        if (created) group = CreatePopupMenu();
        if (!group) return HRESULT_FROM_WIN32(GetLastError());
        if (!InsertMenuW(group, 0, MF_BYPOSITION | MF_STRING, first, L"🌳 用 Sourcetree 打开") ||
            (created && !InsertMenuW(menu, position, MF_BYPOSITION | MF_POPUP, reinterpret_cast<UINT_PTR>(group), L"🌿 Git操作"))) {
            if (created) DestroyMenu(group);
            return E_FAIL;
        }
        return MAKE_HRESULT(SEVERITY_SUCCESS, 0, 1);
    }
    HRESULT STDMETHODCALLTYPE InvokeCommand(CMINVOKECOMMANDINFO* info) override {
        if (!info || HIWORD(info->lpVerb) || LOWORD(info->lpVerb) != 0 || (!IsProject(target) || FindApplication().empty())) return E_INVALIDARG;
        wchar_t modulePath[32768];
        if (!GetModuleFileNameW(moduleHandle, modulePath, 32768)) return E_FAIL;
        std::wstring folder(modulePath);
        folder.resize(folder.find_last_of(L"\\/"));
        folder.resize(folder.find_last_of(L"\\/"));
        const std::wstring script = folder + L"\\Scripts\\Invoke.ps1";
        wchar_t system[32768];
        if (!GetSystemDirectoryW(system, 32768)) return E_FAIL;
        const std::wstring powershell = std::wstring(system) + L"\\WindowsPowerShell\\v1.0\\powershell.exe";
        std::wstring command = Quote(powershell) + L" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File " + Quote(script) + L" -Target " + Quote(target);
        STARTUPINFOW startup = {};
        startup.cb = sizeof(startup);
        startup.dwFlags = STARTF_USESHOWWINDOW;
        startup.wShowWindow = SW_HIDE;
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
    if (!IsEqualCLSID(clsid, CLSID_JobsSourcetreeOpener)) return CLASS_E_CLASSNOTAVAILABLE;
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

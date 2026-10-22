// ContextMenu.cpp | JobsFlutterDoctor
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

const CLSID CLSID_JobsFlutterDoctor = {0xa41e939f,0x64e7,0x49dd,{0x85,0xfa,0x81,0xf9,0xb8,0xcf,0xd5,0xe2}};
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
        if ((flags & CMF_DEFAULTONLY) || first > last || !IsProject(target)) return MAKE_HRESULT(SEVERITY_SUCCESS, 0, 0);
        if (!InsertMenuW(menu, position, MF_BYPOSITION | MF_STRING, first, L"Flutter 项目体检")) return HRESULT_FROM_WIN32(GetLastError());
        return MAKE_HRESULT(SEVERITY_SUCCESS, 0, 1);
    }
    HRESULT STDMETHODCALLTYPE InvokeCommand(CMINVOKECOMMANDINFO* info) override {
        if (!info || HIWORD(info->lpVerb) || LOWORD(info->lpVerb) != 0 || !IsProject(target)) return E_INVALIDARG;
        wchar_t modulePath[32768];
        if (!GetModuleFileNameW(moduleHandle, modulePath, 32768)) return E_FAIL;
        std::wstring folder(modulePath);
        folder.resize(folder.find_last_of(L"\\/"));
        folder.resize(folder.find_last_of(L"\\/"));
        const std::wstring script = folder + L"\\Scripts\\OpenCmd.ps1";
        wchar_t system[32768];
        if (!GetSystemDirectoryW(system, 32768)) return E_FAIL;
        const std::wstring powershell = std::wstring(system) + L"\\WindowsPowerShell\\v1.0\\powershell.exe";
        std::wstring command = Quote(powershell) + L" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File " + Quote(script) + L" -Target " + Quote(target);
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
    if (!IsEqualCLSID(clsid, CLSID_JobsFlutterDoctor)) return CLASS_E_CLASSNOTAVAILABLE;
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

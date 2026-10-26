// ContextMenu.cpp | JobsAndroidSimulatorRepairer
// Created by Jobs on 2026年10月22日，星期四.
// 原生桥接只识别系统桌面背景；ADB / PowerShell 不进入 Explorer 进程。
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
#include <string>
#include "DesktopScope.h"

const CLSID CLSID_JobsAndroidSimulatorRepairer = {0xa6d8dce0,0xb691,0x4cc9,{0xa3,0xc5,0xf0,0x2b,0x8b,0xc7,0x04,0xe5}};
static HMODULE moduleHandle;
static std::atomic<long> objects(0);

static bool IsDesktop(const std::wstring& path) {
    PWSTR desktop = nullptr;
    if (FAILED(SHGetKnownFolderPath(FOLDERID_Desktop, KF_FLAG_DONT_VERIFY, nullptr, &desktop))) return false;
    const bool result = JobsAndroid::IsDesktopContext(false, path, desktop);
    CoTaskMemFree(desktop);
    return result;
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
        // DesktopBackground handler also receives selected items on some shell versions.
        // Both Explorer's selection state and the exact known Desktop path must agree.
        if (selection) return S_OK;
        if (folder && !ILIsEmpty(folder)) {
            std::vector<wchar_t> path(32768);
            if (SHGetPathFromIDListEx(folder, path.data(), static_cast<DWORD>(path.size()), GPFIDL_DEFAULT)) target.assign(path.data());
        } else {
            PWSTR desktop = nullptr;
            if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Desktop, KF_FLAG_DONT_VERIFY, nullptr, &desktop))) {
                target.assign(desktop);
                CoTaskMemFree(desktop);
            }
        }
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE QueryContextMenu(HMENU menu, UINT position, UINT first, UINT last, UINT flags) override {
        if ((flags & CMF_DEFAULTONLY) || first > last || !IsDesktop(target)) return MAKE_HRESULT(SEVERITY_SUCCESS, 0, 0);
        if (!InsertMenuW(menu, position, MF_BYPOSITION | MF_STRING, first, L"🩺 Android 模拟器检测与修复")) return HRESULT_FROM_WIN32(GetLastError());
        return MAKE_HRESULT(SEVERITY_SUCCESS, 0, 1);
    }
    HRESULT STDMETHODCALLTYPE InvokeCommand(CMINVOKECOMMANDINFO* info) override {
        if (!info || HIWORD(info->lpVerb) || LOWORD(info->lpVerb) != 0 || !IsDesktop(target)) return E_INVALIDARG;
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
    if (!IsEqualCLSID(clsid, CLSID_JobsAndroidSimulatorRepairer)) return CLASS_E_CLASSNOTAVAILABLE;
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

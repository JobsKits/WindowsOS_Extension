// ContextMenu.cpp | JobsFileVisibility
// Created by Jobs on 2026年11月18日，星期三.
// CF_HDROP retains the full selection; native handles avoid shell command interpolation.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#define _WIN32_WINNT 0x0602
#include <windows.h>
#include <shlobj.h>
#include <shellapi.h>
#include <atomic>
#include <new>
#include <vector>
#include <string>
#include "FileVisibility.h"
#include "VisibilityRuntime.h"

const CLSID CLSID_JobsFileVisibility = {0xf667a0a8,0xc7a6,0x4c79,{0xa4,0x20,0x12,0xda,0x30,0xeb,0xf9,0x81}};
static HMODULE moduleHandle;
static std::atomic<long> objects(0);

class Menu final : public IShellExtInit, public IContextMenu {
    std::atomic<ULONG> references;
    std::vector<JobsFileVisibility::Target> targets;
    bool readFailed = false;
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
    HRESULT STDMETHODCALLTYPE Initialize(PCIDLIST_ABSOLUTE, IDataObject* selection, HKEY) override try {
        targets.clear(); readFailed = false;
        if (!selection) return S_OK;
        FORMATETC format = {CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
        struct Storage {
            STGMEDIUM value = {};
            bool acquired = false;
            ~Storage() { if (acquired) ReleaseStgMedium(&value); }
        } storage;
        if (FAILED(selection->GetData(&format, &storage.value))) return S_OK;
        storage.acquired = true;
        STGMEDIUM& medium = storage.value;
        HDROP drop = static_cast<HDROP>(medium.hGlobal);
        bool unsupported = false;
        if (drop) {
            const UINT count = DragQueryFileW(drop, 0xffffffff, nullptr, 0);
            if (count > 128) return S_OK;
            for (UINT index = 0; index < count; ++index) {
                const UINT length = DragQueryFileW(drop, index, nullptr, 0);
                std::vector<wchar_t> path(length + 1);
                if (!length || DragQueryFileW(drop, index, path.data(), length + 1) != length) { readFailed = true; break; }
                JobsFileVisibility::Target target;
                target.path.assign(path.data());
                DWORD error = JobsFileVisibility::Snapshot(target.path, target);
                if (error == ERROR_NOT_SUPPORTED || error == ERROR_INVALID_NAME) { unsupported = true; break; }
                if (error != ERROR_SUCCESS) readFailed = true;
                targets.push_back(target);
            }
        }
        if (unsupported) targets.clear();
        return S_OK;
    } catch (const std::bad_alloc&) { targets.clear(); return E_OUTOFMEMORY; }
      catch (...) { targets.clear(); return E_FAIL; }
    HRESULT STDMETHODCALLTYPE QueryContextMenu(HMENU menu, UINT position, UINT first, UINT last, UINT flags) override try {
        if ((flags & CMF_DEFAULTONLY) || first >= last || targets.empty() || !JobsFileVisibility::IsActiveRegistration(moduleHandle)) return MAKE_HRESULT(SEVERITY_SUCCESS, 0, 0);
        bool anyHidden = false, anyVisible = false;
        for (const auto& target : targets) {
            JobsFileVisibility::Target current;
            if (JobsFileVisibility::Snapshot(target.path, current) != ERROR_SUCCESS || !(target.identity == current.identity)) readFailed = true;
            anyHidden = anyHidden || current.hidden;
            anyVisible = anyVisible || !current.hidden;
        }
        const UINT hideFlags = MF_BYPOSITION | MF_STRING | ((!readFailed && anyVisible) ? MF_ENABLED : MF_GRAYED);
        const UINT showFlags = MF_BYPOSITION | MF_STRING | ((!readFailed && anyHidden) ? MF_ENABLED : MF_GRAYED);
        const auto& text = JobsFileVisibility::TextFor(JobsFileVisibility::PreferredLanguage());
        if (!InsertMenuW(menu, position, hideFlags, first, text.hide)) return HRESULT_FROM_WIN32(GetLastError());
        if (!InsertMenuW(menu, position + 1, showFlags, first + 1, text.show)) {
            const DWORD error = GetLastError();
            RemoveMenu(menu, position, MF_BYPOSITION);
            return HRESULT_FROM_WIN32(error);
        }
        return MAKE_HRESULT(SEVERITY_SUCCESS, 0, 2);
    } catch (const std::bad_alloc&) { return E_OUTOFMEMORY; }
      catch (...) { return E_FAIL; }
    HRESULT STDMETHODCALLTYPE InvokeCommand(CMINVOKECOMMANDINFO* info) override try {
        if (!info || HIWORD(info->lpVerb) || LOWORD(info->lpVerb) > 1 || targets.empty() || readFailed || !JobsFileVisibility::IsActiveRegistration(moduleHandle)) return E_INVALIDARG;
        const bool hidden = LOWORD(info->lpVerb) == 0;
        const auto& text = JobsFileVisibility::TextFor(JobsFileVisibility::PreferredLanguage());
        size_t failed = 0;
        std::wstring errors;
        for (const auto& target : targets) {
            const DWORD error = JobsFileVisibility::Apply(target, hidden);
            if (error == ERROR_SUCCESS) continue;
            ++failed;
            // Keep the error dialog bounded for very large selections.
            if (failed <= 8) errors += target.path + L"\n" + text.error + std::to_wstring(error) + L"\n\n";
        }
        if (failed != 0) {
            const std::wstring message = JobsFileVisibility::Summary(text, failed, targets.size()) + L"\n" + errors + text.retry;
            MessageBoxW(info->hwnd, message.c_str(), text.title, MB_OK | MB_ICONERROR);
            return E_FAIL;
        }
        return S_OK;
    } catch (const std::bad_alloc&) { return E_OUTOFMEMORY; }
      catch (...) { return E_FAIL; }
    HRESULT STDMETHODCALLTYPE GetCommandString(UINT_PTR, UINT, UINT*, LPSTR, UINT) override { return E_NOTIMPL; }
};
// PowerShell and Explorer share this exact implementation instead of duplicating attribute writes.
extern "C" DWORD __stdcall JobsSetFileVisibility(LPCWSTR path, BOOL hidden) {
    if (!path) return ERROR_INVALID_PARAMETER;
    try {
        if (!JobsFileVisibility::IsActiveRegistration(moduleHandle)) return ERROR_ACCESS_DENIED;
        JobsFileVisibility::Target target;
        const DWORD error = JobsFileVisibility::Snapshot(path, target);
        return error == ERROR_SUCCESS ? JobsFileVisibility::Apply(target, hidden != FALSE) : error;
    } catch (...) { return ERROR_NOT_ENOUGH_MEMORY; }
}
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
    if (!IsEqualCLSID(clsid, CLSID_JobsFileVisibility)) return CLASS_E_CLASSNOTAVAILABLE;
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

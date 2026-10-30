// ContextMenu.cpp | JobsFileVolumes
// Created by Jobs on 2026年10月28日，星期三.
// 单文件拆分、完整多选合并；只传递精确选择，不扫描目录。
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
#include "VolumeSelection.h"


const CLSID CLSID_JobsFileVolumes = {0x6f7ba84c,0x324c,0x472c,{0xb6,0x18,0xb0,0xe3,0xd4,0x42,0x44,0xdb}};
static HMODULE moduleHandle;
static std::atomic<long> objects(0);

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
// 独占请求文件避开命令行长度上限；只保存路径，不保存内容。
static bool WriteSelection(const std::vector<std::wstring>& paths, std::wstring& request) {
    size_t units = 0;
    for (const auto& path : paths) {
        if (path.size() > (16 * 1024 * 1024 - 2) / 6 || units > (16 * 1024 * 1024 - 2) / 6 - path.size()) return false;
        units += path.size();
    }
    wchar_t temporary[32768];
    const DWORD length = GetTempPathW(32768, temporary);
    if (!length || length >= 32768) return false;
    const std::wstring directory = std::wstring(temporary) + L"JobsFileVolumes";
    if (!CreateDirectoryW(directory.c_str(), nullptr) && GetLastError() != ERROR_ALREADY_EXISTS) return false;
    const DWORD attrs = GetFileAttributesW(directory.c_str());
    if (attrs == INVALID_FILE_ATTRIBUTES || !(attrs & FILE_ATTRIBUTE_DIRECTORY) || (attrs & FILE_ATTRIBUTE_REPARSE_POINT)) return false;
    GUID id;
    wchar_t guid[40];
    if (FAILED(CoCreateGuid(&id)) || !StringFromGUID2(id, guid, 40)) return false;
    std::wstring token(guid);
    token = token.substr(1, token.size() - 2);
    request = directory + L"\\selection-" + token + L".json";
    const HANDLE file = CreateFileW(request.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW, FILE_ATTRIBUTE_TEMPORARY, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;
    std::string json = "[";
    const char* hex = "0123456789abcdef";
    for (size_t index = 0; index < paths.size(); ++index) {
        if (index) json += ',';
        json += '"';
        for (wchar_t c : paths[index]) {
            // 每个UTF-16 code unit使用JSON转义，代理对自然保持完整。
            json += "\\u";
            const unsigned value = static_cast<unsigned>(c);
            for (int shift = 12; shift >= 0; shift -= 4) json += hex[(value >> shift) & 15];
        }
        json += '"';
    }
    json += ']';
    DWORD written = 0;
    const bool success = json.size() <= 16 * 1024 * 1024 && WriteFile(file, json.data(), static_cast<DWORD>(json.size()), &written, nullptr) && written == json.size();
    CloseHandle(file);
    if (!success) DeleteFileW(request.c_str());
    return success;
}
class Menu final : public IShellExtInit, public IContextMenu {
    std::atomic<ULONG> references;
    std::vector<std::wstring> targets;
    bool mergeAction = false;
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
    HRESULT STDMETHODCALLTYPE Initialize(PCIDLIST_ABSOLUTE, IDataObject* selection, HKEY) override {
        targets.clear();
        if (!selection) return S_OK;
        FORMATETC format = {CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
        STGMEDIUM medium = {};
        if (FAILED(selection->GetData(&format, &medium))) return S_OK;
        HDROP drop = static_cast<HDROP>(medium.hGlobal);
        if (drop) {
            const UINT count = DragQueryFileW(drop, 0xffffffff, nullptr, 0);
            if (count > 0 && count <= 10000) {
                for (UINT index = 0; index < count; ++index) {
                    const UINT length = DragQueryFileW(drop, index, nullptr, 0);
                    std::vector<wchar_t> path(length + 1);
                    if (!length || DragQueryFileW(drop, index, path.data(), length + 1) != length) { targets.clear(); break; }
                    targets.emplace_back(path.data());
                }
            }
        }
        ReleaseStgMedium(&medium);

        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE QueryContextMenu(HMENU menu, UINT position, UINT first, UINT last, UINT flags) override {
        mergeAction = JobsFileVolumes::CanMerge(targets);
        if ((flags & CMF_DEFAULTONLY) || first > last || (!mergeAction && !JobsFileVolumes::CanSplit(targets))) return MAKE_HRESULT(SEVERITY_SUCCESS, 0, 0);
        if (!InsertMenuW(menu, position, MF_BYPOSITION | MF_STRING | MF_ENABLED, first, (mergeAction ? L"🧩 合并分卷" : L"✂️ 拆分文件"))) return HRESULT_FROM_WIN32(GetLastError());
        return MAKE_HRESULT(SEVERITY_SUCCESS, 0, 1);
    }
    HRESULT STDMETHODCALLTYPE InvokeCommand(CMINVOKECOMMANDINFO* info) override {
        if (!info || HIWORD(info->lpVerb) || LOWORD(info->lpVerb) != 0 || (mergeAction ? !JobsFileVolumes::CanMerge(targets) : !JobsFileVolumes::CanSplit(targets))) return E_INVALIDARG;
        wchar_t modulePath[32768];
        if (!GetModuleFileNameW(moduleHandle, modulePath, 32768)) return E_FAIL;
        std::wstring folder(modulePath);
        folder.resize(folder.find_last_of(L"\\/"));
        folder.resize(folder.find_last_of(L"\\/"));
        const std::wstring script = folder + L"\\Scripts\\Invoke.ps1";
        wchar_t system[32768];
        if (!GetSystemDirectoryW(system, 32768)) return E_FAIL;
        const std::wstring powershell = std::wstring(system) + L"\\WindowsPowerShell\\v1.0\\powershell.exe";
        std::wstring request;
        if (!WriteSelection(targets, request)) return E_FAIL;
        std::wstring command = Quote(powershell) + L" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Normal -File " + Quote(script) + L" -Mode " + (mergeAction ? L"Merge" : L"Split") + L" -Request " + Quote(request);
        STARTUPINFOW startup = {};
        startup.cb = sizeof(startup);
        PROCESS_INFORMATION process = {};
        if (command.size() >= 32767 || !CreateProcessW(powershell.c_str(), &command[0], nullptr, nullptr, FALSE, CREATE_NEW_CONSOLE, nullptr, folder.c_str(), &startup, &process)) {
            const DWORD error = GetLastError();
            DeleteFileW(request.c_str());
            return HRESULT_FROM_WIN32(error ? error : ERROR_BAD_LENGTH);
        }
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
    if (!IsEqualCLSID(clsid, CLSID_JobsFileVolumes)) return CLASS_E_CLASSNOTAVAILABLE;
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

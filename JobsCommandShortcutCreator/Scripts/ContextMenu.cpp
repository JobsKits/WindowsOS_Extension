// ContextMenu.cpp | JobsCommandShortcutCreator
// Created by Jobs on 2026年11月13日，星期五.
// 只在单个同名原生脚本文件夹上提供快捷入口；不处理文件、多选、背景或重解析点。
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
#include <regex>
#include "CommandShortcutTarget.h"


const CLSID CLSID_JobsCommandShortcutCreator = {0xa29030c5,0x2c96,0x48bf,{0xbb,0xf2,0x75,0xd8,0x0c,0xc8,0xaf,0x80}};
static HMODULE moduleHandle;
static std::atomic<long> objects(0);

static bool IsDirectory(const std::wstring& path) {
    return JobsCommandShortcut::IsEligibleDirectory(path);
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

// Read only the shared panel language; malformed or unknown settings follow the system.
static std::wstring MenuTitle() {
    std::string language;
    wchar_t localAppData[32768];
    const DWORD size = GetEnvironmentVariableW(L"LOCALAPPDATA", localAppData, 32768);
    if (size && size < 32768) {
        try {
            std::ifstream file(std::wstring(localAppData) + L"\\Jobs\\WindowsExtension\\panel-preferences.json", std::ios::binary);
            const std::string contents((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
            if (contents.size() < 65536) {
                std::smatch match;
                if (std::regex_search(contents, match, std::regex("\\\"Language\\\"\\s*:\\s*\\\"([^\\\"]+)\\\""))) language = match[1].str();
            }
        } catch (...) { language.clear(); }
    }
    if (language.empty() || language == "system") {
        const LANGID system = GetUserDefaultUILanguage();
        switch (PRIMARYLANGID(system)) {
            case 0x04: language = (system == 0x0404 || system == 0x0c04 || system == 0x1404) ? "zh-Hant" : "zh-Hans"; break;
            case 0x51: language = "bo"; break;
            case 0x11: language = "ja"; break;
            case 0x0c: language = "fr"; break;
            case 0x0a: language = "es"; break;
            case 0x07: language = "de"; break;
            case 0x19: language = "ru"; break;
            case 0x12: language = "ko"; break;
            default: language = "en"; break;
        }
    }
    if (language == "zh-Hans") return L"🔗 创建脚本快捷入口…";
    if (language == "zh-Hant") return L"🔗 建立指令稿快捷入口…";
    if (language == "bo") return L"🔗 འཕྲལ་འཇུག་ཡིག་ཆ་བཟོ།…";
    if (language == "ja") return L"🔗 スクリプト起動ファイルを作成…";
    if (language == "fr") return L"🔗 Créer un lanceur de script…";
    if (language == "es") return L"🔗 Crear acceso al script…";
    if (language == "de") return L"🔗 Skriptstarter erstellen…";
    if (language == "ru") return L"🔗 Создать ярлык скрипта…";
    if (language == "ko") return L"🔗 스크립트 실행 파일 만들기…";
    return L"🔗 Create Script Launcher…";
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
    HRESULT STDMETHODCALLTYPE Initialize(PCIDLIST_ABSOLUTE, IDataObject* selection, HKEY) override {
        target.clear();
        if (!selection) return S_OK;
        FORMATETC format = {CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
        STGMEDIUM medium = {};
        if (FAILED(selection->GetData(&format, &medium))) return S_OK;
        HDROP drop = static_cast<HDROP>(medium.hGlobal);
        if (drop) {
            if (DragQueryFileW(drop, 0xffffffff, nullptr, 0) == 1) {
                const UINT length = DragQueryFileW(drop, 0, nullptr, 0);
                std::vector<wchar_t> path(length + 1);
                if (length && DragQueryFileW(drop, 0, path.data(), length + 1) == length) target.assign(path.data());
            }
        }
        ReleaseStgMedium(&medium);
        if (!JobsCommandShortcut::IsSingleDirectory(1, target)) target.clear();
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE QueryContextMenu(HMENU menu, UINT position, UINT first, UINT last, UINT flags) override {
        if ((flags & CMF_DEFAULTONLY) || first > last || !IsDirectory(target)) return MAKE_HRESULT(SEVERITY_SUCCESS, 0, 0);
        if (!InsertMenuW(menu, position, MF_BYPOSITION | MF_STRING | MF_ENABLED, first, MenuTitle().c_str())) return HRESULT_FROM_WIN32(GetLastError());
        return MAKE_HRESULT(SEVERITY_SUCCESS, 0, 1);
    }
    HRESULT STDMETHODCALLTYPE InvokeCommand(CMINVOKECOMMANDINFO* info) override {
        if (!info || HIWORD(info->lpVerb) || LOWORD(info->lpVerb) != 0 || !IsDirectory(target)) return E_INVALIDARG;
        wchar_t modulePath[32768];
        if (!GetModuleFileNameW(moduleHandle, modulePath, 32768)) return E_FAIL;
        std::wstring folder(modulePath);
        folder.resize(folder.find_last_of(L"\\/"));
        folder.resize(folder.find_last_of(L"\\/"));
        const std::wstring script = folder + L"\\Scripts\\Invoke.ps1";
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
    if (!IsEqualCLSID(clsid, CLSID_JobsCommandShortcutCreator)) return CLASS_E_CLASSNOTAVAILABLE;
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

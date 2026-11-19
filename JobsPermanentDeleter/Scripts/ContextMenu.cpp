// ContextMenu.cpp | JobsPermanentDeleter
// Created by Jobs on 2026年11月18日，星期三.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0602
#endif
#include <windows.h>
#include <shlobj.h>
#include <shellapi.h>
#include <atomic>
#include <new>
#include <vector>
#include <string>
#include "PermanentDelete.h"
#include "DeleteDialog.h"

const CLSID CLSID_JobsPermanentDeleter = {0x79022a9c,0x59cf,0x485a,{0x90,0xd8,0x67,0xc6,0x7e,0xe7,0xce,0x33}};
static HMODULE moduleHandle;
static std::atomic<long> objects(0);
// Keep preparation, explicit confirmation and handle deletion in one shared execution path.
static DWORD ConfirmAndDelete(HWND owner, const std::vector<JobsPermanentDeleter::Target>& targets) {
    using namespace JobsPermanentDeleter;
    if (!IsActiveRegistration(moduleHandle)) return ERROR_ACCESS_DENIED;
    Plan plan;
    DWORD error = Prepare(targets,plan);
    DialogState state;
    if (!error) {
        state.count = plan.entries.size();
        for (const auto& root : plan.roots) state.details += root.path + L"\r\n";
        if (!ShowDeleteDialog(moduleHandle,owner,state)) return ERROR_CANCELLED;
        if (!IsActiveRegistration(moduleHandle)) return ERROR_ACCESS_DENIED;
        const Result result = Commit(plan,true);
        error = result.error;
        for (const auto& root : plan.roots) {
            const size_t separator = root.path.find_last_of(L'\\');
            const std::wstring parent = root.path.substr(0,separator == 2 ? 3 : separator);
            SHChangeNotify(SHCNE_UPDATEDIR,SHCNF_PATHW,parent.c_str(),nullptr);
        }
        if (!error) return ERROR_SUCCESS;
        state.deleted = result.deleted;
        state.details = result.failedPath;
    } else {
        state.details.clear();
        for (const auto& target : targets) state.details += target.path + L"\r\n";
    }
    state.error = error;
    state.confirmation = false;
    ShowDeleteDialog(moduleHandle,owner,state);
    return error;
}
class Menu final : public IShellExtInit, public IContextMenu {
    std::atomic<ULONG> references;
    std::vector<JobsPermanentDeleter::Target> targets;
public:
    Menu() : references(1) { ++objects; }
    ~Menu() { --objects; }
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** output) override {
        if (!output) return E_POINTER;
        *output=nullptr;
        if (IsEqualIID(iid,IID_IUnknown)||IsEqualIID(iid,IID_IShellExtInit)) *output=static_cast<IShellExtInit*>(this);
        else if (IsEqualIID(iid,IID_IContextMenu)) *output=static_cast<IContextMenu*>(this);
        else return E_NOINTERFACE;
        AddRef(); return S_OK;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++references; }
    ULONG STDMETHODCALLTYPE Release() override { ULONG count=--references; if (!count) delete this; return count; }
    // CF_HDROP preserves all paths as data, without command strings or shell interpolation.
    HRESULT STDMETHODCALLTYPE Initialize(PCIDLIST_ABSOLUTE,IDataObject* selection,HKEY) override try {
        targets.clear();
        if (!selection) return S_OK;
        FORMATETC format={CF_HDROP,nullptr,DVASPECT_CONTENT,-1,TYMED_HGLOBAL};
        struct Storage {
            STGMEDIUM value={}; bool acquired=false;
            ~Storage() { if (acquired) ReleaseStgMedium(&value); }
        } storage;
        if (FAILED(selection->GetData(&format,&storage.value))) return S_OK;
        storage.acquired=true;
        HDROP drop=static_cast<HDROP>(storage.value.hGlobal);
        if (!drop) return S_OK;
        UINT count=DragQueryFileW(drop,0xffffffff,nullptr,0);
        if (!count||count>128) return S_OK;
        for (UINT i=0;i<count;++i) {
            UINT length=DragQueryFileW(drop,i,nullptr,0);
            std::vector<wchar_t> path(length+1);
            if (!length||DragQueryFileW(drop,i,path.data(),length+1)!=length) { targets.clear(); break; }
            JobsPermanentDeleter::Target target;
            if (JobsPermanentDeleter::Snapshot(path.data(),target)!=ERROR_SUCCESS) { targets.clear(); break; }
            targets.push_back(target);
        }
        return S_OK;
    } catch (...) { targets.clear(); return E_FAIL; }
    // Only file/directory selections receive the one destructive menu command.
    HRESULT STDMETHODCALLTYPE QueryContextMenu(HMENU menu,UINT position,UINT first,UINT last,UINT flags) override try {
        if ((flags&CMF_DEFAULTONLY)||first>last||targets.empty()||!JobsPermanentDeleter::IsActiveRegistration(moduleHandle)) return MAKE_HRESULT(SEVERITY_SUCCESS,0,0);
        bool valid=true;
        for (const auto& target : targets) {
            JobsPermanentDeleter::Target current;
            if (JobsPermanentDeleter::Snapshot(target.path,current)!=ERROR_SUCCESS||!(target.identity==current.identity)) valid=false;
        }
        const auto& text=JobsPermanentDeleter::TextFor(JobsPermanentDeleter::PreferredLanguage());
        if (!InsertMenuW(menu,position,MF_BYPOSITION|MF_STRING|(valid?MF_ENABLED:MF_GRAYED),first,text.menu)) return HRESULT_FROM_WIN32(GetLastError());
        return MAKE_HRESULT(SEVERITY_SUCCESS,0,1);
    } catch (...) { return E_FAIL; }
    // Clicking the menu only opens a review dialog; cancellation has no deletion side effects.
    HRESULT STDMETHODCALLTYPE InvokeCommand(CMINVOKECOMMANDINFO* info) override try {
        if (!info||HIWORD(info->lpVerb)||LOWORD(info->lpVerb)!=0||targets.empty()) return E_INVALIDARG;
        DWORD error=ConfirmAndDelete(info->hwnd,targets);
        return error==ERROR_CANCELLED?S_OK:HRESULT_FROM_WIN32(error);
    } catch (...) { return E_FAIL; }
    HRESULT STDMETHODCALLTYPE GetCommandString(UINT_PTR,UINT,UINT*,LPSTR,UINT) override { return E_NOTIMPL; }
};
// Optional CLI entry uses the exact same GUI gate; there is no force/quiet deletion export.
extern "C" DWORD __stdcall JobsConfirmPermanentDelete(LPCWSTR const* paths,DWORD count) {
    try {
        if (!paths||!count||count>128) return ERROR_INVALID_PARAMETER;
        std::vector<JobsPermanentDeleter::Target> targets;
        for (DWORD i=0;i<count;++i) {
            if (!paths[i]) return ERROR_INVALID_PARAMETER;
            JobsPermanentDeleter::Target target;
            DWORD error=JobsPermanentDeleter::Snapshot(paths[i],target);
            if (error) return error;
            targets.push_back(target);
        }
        return ConfirmAndDelete(nullptr,targets);
    } catch (...) { return ERROR_NOT_ENOUGH_MEMORY; }
}
class Factory final : public IClassFactory {
    std::atomic<ULONG> references;
public:
    Factory() : references(1) { ++objects; }
    ~Factory() { --objects; }
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid,void** output) override {
        if (!output) return E_POINTER;
        *output=nullptr;
        if (!IsEqualIID(iid,IID_IUnknown)&&!IsEqualIID(iid,IID_IClassFactory)) return E_NOINTERFACE;
        *output=static_cast<IClassFactory*>(this); AddRef(); return S_OK;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++references; }
    ULONG STDMETHODCALLTYPE Release() override { ULONG count=--references; if (!count) delete this; return count; }
    HRESULT STDMETHODCALLTYPE CreateInstance(IUnknown* outer,REFIID iid,void** output) override {
        if (outer) return CLASS_E_NOAGGREGATION;
        Menu* instance=new(std::nothrow) Menu();
        if (!instance) return E_OUTOFMEMORY;
        HRESULT result=instance->QueryInterface(iid,output); instance->Release(); return result;
    }
    HRESULT STDMETHODCALLTYPE LockServer(BOOL lock) override { if (lock) ++objects; else --objects; return S_OK; }
};
extern "C" HRESULT __stdcall DllGetClassObject(REFCLSID clsid,REFIID iid,void** output) {
    if (!IsEqualCLSID(clsid,CLSID_JobsPermanentDeleter)) return CLASS_E_CLASSNOTAVAILABLE;
    Factory* factory=new(std::nothrow) Factory();
    if (!factory) return E_OUTOFMEMORY;
    HRESULT result=factory->QueryInterface(iid,output); factory->Release(); return result;
}
extern "C" HRESULT __stdcall DllCanUnloadNow() { return objects.load()==0?S_OK:S_FALSE; }
BOOL WINAPI DllMain(HINSTANCE instance,DWORD reason,LPVOID) {
    if (reason==DLL_PROCESS_ATTACH) moduleHandle=instance;
    return TRUE;
}

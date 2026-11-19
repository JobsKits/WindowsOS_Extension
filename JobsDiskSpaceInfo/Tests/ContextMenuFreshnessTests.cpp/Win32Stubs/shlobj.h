// shlobj.h | JobsDiskSpaceInfo isolated COM boundary
// Created by Jobs on 2026年11月16日，星期一.
#pragma once
#include "windows.h"
struct IDataObject {};
using PCIDLIST_ABSOLUTE = const void*;
struct CMINVOKECOMMANDINFO { LPCSTR lpVerb; };
struct IUnknown {
    virtual HRESULT QueryInterface(REFIID, void**) = 0;
    virtual ULONG AddRef() = 0;
    virtual ULONG Release() = 0;
};
struct IShellExtInit : IUnknown { virtual HRESULT Initialize(PCIDLIST_ABSOLUTE, IDataObject*, HKEY) = 0; };
struct IContextMenu : IUnknown {
    virtual HRESULT QueryContextMenu(HMENU, UINT, UINT, UINT, UINT) = 0;
    virtual HRESULT InvokeCommand(CMINVOKECOMMANDINFO*) = 0;
    virtual HRESULT GetCommandString(UINT_PTR, UINT, UINT*, LPSTR, UINT) = 0;
};
struct IClassFactory : IUnknown {
    virtual HRESULT CreateInstance(IUnknown*, REFIID, void**) = 0;
    virtual HRESULT LockServer(BOOL) = 0;
};
static const GUID IID_IUnknown = {0, 0, 0, {0}};
static const GUID IID_IShellExtInit = {1, 0, 0, {0}};
static const GUID IID_IContextMenu = {2, 0, 0, {0}};
static const GUID IID_IClassFactory = {3, 0, 0, {0}};
constexpr UINT CMF_DEFAULTONLY = 1;

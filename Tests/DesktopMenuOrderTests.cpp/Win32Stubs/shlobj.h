// shlobj.h | desktop menu isolated boundary
// Created by Jobs on 2026年11月18日，星期三.
#pragma once
#include "windows.h"
#include "../../../JobsDiskSpaceInfo/Tests/ContextMenuFreshnessTests.cpp/Win32Stubs/shlobj.h"
static const GUID FOLDERID_Desktop = {4, 0, 0, {0}};
BOOL ILIsEmpty(PCIDLIST_ABSOLUTE);
HRESULT SHGetKnownFolderPath(REFIID, DWORD, HANDLE, PWSTR*);
BOOL SHGetPathFromIDListEx(PCIDLIST_ABSOLUTE, wchar_t*, DWORD, UINT);
void CoTaskMemFree(void*);


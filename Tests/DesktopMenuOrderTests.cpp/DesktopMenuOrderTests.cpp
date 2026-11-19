// DesktopMenuOrderTests.cpp | WindowsOS@Extension
// Created by Jobs on 2026年11月18日，星期三.
// Compile all six real handlers; only Win32 menu, disk and desktop boundaries are synthetic.
#include <windows.h>
#include <shlobj.h>
#include <algorithm>
#include <array>
#include <atomic>
#include <fstream>
#include <iterator>
#include <new>
#include <vector>
#include <string>
#include <cwctype>
#include <iostream>
#include <stdexcept>
#include <set>
#include <limits>
#include <sstream>
#include <iomanip>
#include "../../JobsDiskSpaceInfo/Scripts/DesktopMenuOrder.h"
#ifndef _WIN32
#define _WIN32 1
#endif

#define DllGetClassObject MenuOrderGetClass0
#define DllCanUnloadNow MenuOrderCanUnload0
namespace Handler0 {
#include "../../JobsAndroidSimulatorCreator/Scripts/ContextMenu.cpp"
}
#undef DllGetClassObject
#undef DllCanUnloadNow
#define DllGetClassObject MenuOrderGetClass1
#define DllCanUnloadNow MenuOrderCanUnload1
namespace Handler1 {
#include "../../JobsHarmonySimulatorCreator/Scripts/ContextMenu.cpp"
}
#undef DllGetClassObject
#undef DllCanUnloadNow
#define DllGetClassObject MenuOrderGetClass2
#define DllCanUnloadNow MenuOrderCanUnload2
namespace Handler2 {
#include "../../JobsAndroidSimulatorRepairer/Scripts/ContextMenu.cpp"
}
#undef DllGetClassObject
#undef DllCanUnloadNow
#define DllGetClassObject MenuOrderGetClass3
#define DllCanUnloadNow MenuOrderCanUnload3
namespace Handler3 {
#include "../../JobsHarmonySimulatorRepairer/Scripts/ContextMenu.cpp"
}
#undef DllGetClassObject
#undef DllCanUnloadNow
#define DllGetClassObject MenuOrderGetClass4
#define DllCanUnloadNow MenuOrderCanUnload4
namespace Handler4 {
#include "../../JobsHiddenFilesToggler/Scripts/ContextMenu.cpp"
}
#undef DllGetClassObject
#undef DllCanUnloadNow
#define DllGetClassObject MenuOrderGetClass5
#define DllCanUnloadNow MenuOrderCanUnload5
namespace Handler5 {
#include "../../JobsDiskSpaceInfo/Scripts/ContextMenu.cpp"
}
#undef DllGetClassObject
#undef DllCanUnloadNow

struct Row {
    UINT command;
    ULONG_PTR data;
    UINT state;
    std::wstring title;
};
struct FakeMenu { std::vector<Row> rows; };
static DWORD lastError = ERROR_ACCESS_DENIED;
static bool failCount = false, failRead = false, failInsert = false;
static DWORD hiddenPreference = 2;
static LSTATUS hiddenResult = ERROR_SUCCESS;
static unsigned short architecture = PROCESSOR_ARCHITECTURE_AMD64;
static unsigned checks = 0, processStarts = 0, cases = 0;
static void Require(bool value, const char* message) {
    if (!value) throw std::runtime_error(message);
    ++checks;
}
int GetMenuItemCount(HMENU value) {
    if (failCount || !value) return -1;
    return static_cast<int>(static_cast<FakeMenu*>(value)->rows.size());
}
BOOL GetMenuItemInfoW(HMENU value, UINT index, BOOL byPosition, MENUITEMINFOW* item) {
    Require(byPosition && item->cbSize == sizeof(*item) && item->fMask == MIIM_DATA, "scan only opaque item data by position");
    if (failRead || !value) return FALSE;
    const auto& rows = static_cast<FakeMenu*>(value)->rows;
    if (index >= rows.size()) return FALSE;
    item->dwItemData = rows[index].data;
    return TRUE;
}
BOOL InsertMenuItemW(HMENU value, UINT index, BOOL byPosition, const MENUITEMINFOW* item) {
    Require(byPosition && item->cbSize == sizeof(*item), "native insertion uses structure size and positional indexing");
    Require(item->fMask == (MIIM_DATA | MIIM_STRING | MIIM_ID | MIIM_STATE), "insert transfers title, command, state and integer ordering data");
    if (failInsert || !value) return FALSE;
    auto& rows = static_cast<FakeMenu*>(value)->rows;
    if (index > rows.size()) return FALSE;
    rows.insert(rows.begin() + index, {item->wID, item->dwItemData, item->fState, item->dwTypeData});
    return TRUE;
}
DWORD GetLastError() { return lastError; }
void GetNativeSystemInfo(SYSTEM_INFO* info) { info->wProcessorArchitecture = architecture; }
BOOL ILIsEmpty(PCIDLIST_ABSOLUTE folder) { return !folder || !*static_cast<const wchar_t*>(folder); }
HRESULT SHGetKnownFolderPath(REFIID, DWORD, HANDLE, PWSTR* output) {
    const wchar_t* desktop = L"C:\\Users\\Jobs\\Desktop";
    *output = new wchar_t[std::wcslen(desktop) + 1];
    std::wcscpy(*output, desktop);
    return S_OK;
}
BOOL SHGetPathFromIDListEx(PCIDLIST_ABSOLUTE folder, wchar_t* output, DWORD length, UINT) {
    const auto path = static_cast<const wchar_t*>(folder);
    if (!path || std::wcslen(path) >= length) return FALSE;
    std::wcscpy(output, path);
    return TRUE;
}
void CoTaskMemFree(void* value) { delete[] static_cast<wchar_t*>(value); }
LSTATUS RegGetValueW(HKEY, LPCWSTR, LPCWSTR, DWORD, DWORD*, void* value, DWORD*) {
    *static_cast<DWORD*>(value) = hiddenPreference;
    return hiddenResult;
}
BOOL SetThreadErrorMode(DWORD, DWORD* previous) { if (previous) *previous = 0; return TRUE; }
HMODULE GetModuleHandleW(LPCWSTR) { return reinterpret_cast<HMODULE>(1); }
FARPROC GetProcAddress(HMODULE, const char*) { return nullptr; }
HANDLE FindFirstVolumeW(wchar_t*, DWORD) { throw std::runtime_error("unavailable synthetic API must avoid enumeration"); }
BOOL FindNextVolumeW(HANDLE, wchar_t*, DWORD) { return FALSE; }
BOOL FindVolumeClose(HANDLE) { return TRUE; }
UINT GetDriveTypeW(LPCWSTR) { return DRIVE_FIXED; }
BOOL GetVolumePathNamesForVolumeNameW(LPCWSTR, wchar_t*, DWORD, DWORD*) { return FALSE; }
BOOL GetVolumeInformationW(LPCWSTR, wchar_t*, DWORD, DWORD*, DWORD*, DWORD*, wchar_t*, DWORD) { return FALSE; }
LANGID GetUserDefaultUILanguage() { return 0x804; }
DWORD GetModuleFileNameW(HMODULE, wchar_t*, DWORD) { throw std::runtime_error("menu generation must not route a process"); }
UINT GetSystemDirectoryW(wchar_t*, UINT) { throw std::runtime_error("menu generation must not route a process"); }
DWORD GetFileAttributesW(LPCWSTR) { throw std::runtime_error("menu generation must not inspect business scripts"); }
BOOL CreateProcessW(LPCWSTR, wchar_t*, void*, void*, BOOL, DWORD, void*, LPCWSTR, STARTUPINFOW*, PROCESS_INFORMATION*) {
    ++processStarts;
    throw std::runtime_error("menu generation must not execute business");
}
BOOL CloseHandle(HANDLE) { return TRUE; }

static const std::array<UINT, 6> ranks = {{10, 20, 30, 40, 50, 60}};
static std::vector<UINT> OrderedRanks(const FakeMenu& menu) {
    std::vector<UINT> result;
    for (const auto& row : menu.rows) {
        UINT rank = 0;
        if (JobsDesktopMenuOrder::ReadRank(row.data, rank)) result.push_back(rank);
    }
    return result;
}
static std::vector<Row> ForeignRows(const FakeMenu& menu) {
    std::vector<Row> result;
    for (const auto& row : menu.rows) {
        UINT rank = 0;
        if (!JobsDesktopMenuOrder::ReadRank(row.data, rank)) result.push_back(row);
    }
    return result;
}

int main() {
    const auto make = [] {
        return std::array<IContextMenu*, 6> {{new Handler0::Menu(), new Handler1::Menu(),
            new Handler2::Menu(), new Handler3::Menu(), new Handler4::Menu(), new Handler5::Menu()}};
    };
    auto handlers = make();
    const auto initialize = [&](PCIDLIST_ABSOLUTE folder, IDataObject* selection) {
        for (auto* handler : handlers) {
            void* init = nullptr;
            Require(handler->QueryInterface(IID_IShellExtInit, &init) == S_OK, "production handler retains initialization interface");
            auto* shellInit = static_cast<IShellExtInit*>(init);
            Require(shellInit->Initialize(folder, selection, nullptr) == S_OK, "production initialization succeeds");
            shellInit->Release();
        }
    };
    initialize(nullptr, nullptr);
    // Every subset and callback permutation, with shell positions at either edge or between unrelated rows.
    for (unsigned mask = 0; mask < 64; ++mask) {
        std::vector<int> permutation;
        for (unsigned feature = 0; feature < 6; ++feature) if (mask & (1u << feature)) permutation.push_back(static_cast<int>(feature));
        do {
            for (unsigned mode = 0; mode < 3; ++mode) {
                FakeMenu menu {{{7, 0, MFS_ENABLED, L"System before"}, {9, 0x4a4f4211u, MFS_ENABLED, L"Not a known Jobs rank"},
                                {11, static_cast<ULONG_PTR>(0x4a4f430au), MFS_DISABLED, L"Foreign namespace"}}};
                const auto foreign = menu.rows;
                std::vector<UINT> expected;
                for (const int feature : permutation) {
                    const UINT suggested = mode == 0 ? 0 : mode == 1 ? static_cast<UINT>(menu.rows.size()) : 1;
                    const UINT command = 100 + static_cast<UINT>(feature) * 13;
                    Require(handlers[feature]->QueryContextMenu(&menu, suggested, command, command, 0) == 1, "each real handler consumes exactly one command even in shuffled callbacks");
                    expected.push_back(ranks[feature]);
                    std::sort(expected.begin(), expected.end());
                    Require(OrderedRanks(menu) == expected, "every partial callback sequence is already ordered");
                    const auto inserted = std::find_if(menu.rows.begin(), menu.rows.end(), [command](const Row& row) { return row.command == command; });
                    Require(inserted != menu.rows.end() && inserted->data == JobsDesktopMenuOrder::ItemData(static_cast<JobsDesktopMenuOrder::Rank>(ranks[feature])), "command id remains mapped to its original handler");
                }
                const auto preserved = ForeignRows(menu);
                Require(preserved.size() == foreign.size(), "does not consume another handler's rows");
                for (size_t i = 0; i < preserved.size(); ++i) {
                    Require(preserved[i].command == foreign[i].command && preserved[i].data == foreign[i].data &&
                            preserved[i].state == foreign[i].state && preserved[i].title == foreign[i].title, "preserves all third party fields and relative order");
                }
                ++cases;
            }
        } while (std::next_permutation(permutation.begin(), permutation.end()));
    }
    FakeMenu menu;
    for (auto* handler : handlers) {
        Require(handler->QueryContextMenu(&menu, 0, 1, 1, CMF_DEFAULTONLY) == 0, "default-action probes add no row");
        Require(handler->QueryContextMenu(&menu, 0, 2, 1, 0) == 0, "invalid command range adds no row");
        Require(handler->InvokeCommand(nullptr) == E_INVALIDARG, "invalid invocation remains rejected");
    }
    Require(menu.rows.empty(), "rejected probes do not alter menu");
    initialize(L"C:\\Other", nullptr);
    for (size_t feature = 0; feature < 5; ++feature) {
        Require(handlers[feature]->QueryContextMenu(&menu, 0, 1, 1, 0) == 0, "desktop-specific actions stay hidden outside Desktop");
    }
    IDataObject selection;
    initialize(nullptr, &selection);
    for (size_t feature = 0; feature < 5; ++feature) {
        Require(handlers[feature]->QueryContextMenu(&menu, 0, 1, 1, 0) == 0, "desktop-specific actions stay hidden on selected objects");
    }
    initialize(nullptr, nullptr);
    architecture = PROCESSOR_ARCHITECTURE_ARM64;
    Require(handlers[1]->QueryContextMenu(&menu, 0, 1, 1, 0) == 0, "Harmony creation retains original native x64 gate");
    architecture = PROCESSOR_ARCHITECTURE_AMD64;
    hiddenResult = ERROR_ACCESS_DENIED;
    Require(handlers[4]->QueryContextMenu(&menu, 0, 1, 1, 0) == 1, "unknown hidden-file preference still produces ranked disabled row");
    Require(menu.rows.back().state == MFS_DISABLED, "unknown hidden-file state cannot be invoked");
    Require(handlers[4]->InvokeCommand(nullptr) == E_INVALIDARG, "unknown preference does not route business");
    hiddenResult = ERROR_SUCCESS;
    for (unsigned failure = 0; failure < 3; ++failure) {
        menu.rows = {{7, 0, MFS_ENABLED, L"System"}};
        failCount = failure == 0; failRead = failure == 1; failInsert = failure == 2;
        for (auto* handler : handlers) {
            Require(handler->QueryContextMenu(&menu, 0, 1, 1, 0) == HRESULT_FROM_WIN32(ERROR_ACCESS_DENIED), "native menu failure propagates exact failure, not successful command count");
            Require(menu.rows.size() == 1 && menu.rows[0].command == 7, "failed menu mutation preserves prior rows");
        }
        failCount = failRead = failInsert = false;
    }
    UINT rank = 0;
    Require(!JobsDesktopMenuOrder::ReadRank(static_cast<ULONG_PTR>(0x4a4f420bu), rank), "unknown rank is foreign data");
    if (sizeof(ULONG_PTR) > 4) {
        Require(!JobsDesktopMenuOrder::ReadRank(static_cast<ULONG_PTR>(0x100000000ull | 0x4a4f420aull), rank), "upper pointer bits must also match the integer namespace");
    }
    Require(processStarts == 0, "every permutation and failure stays read only");
    for (auto* handler : handlers) Require(handler->Release() == 0, "releases all production handlers");
    std::cout << "PASS: DesktopMenuOrderTests (" << cases << " subset/callback/position cases, " << checks << " assertions)\n";
}


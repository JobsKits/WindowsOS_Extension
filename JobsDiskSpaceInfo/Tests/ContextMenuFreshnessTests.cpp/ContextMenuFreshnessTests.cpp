// ContextMenuFreshnessTests.cpp | JobsDiskSpaceInfo
// Created by Jobs on 2026年11月16日，星期一.
// Run the real COM handler repeatedly against a synthetic Win32 boundary only.
#include "../../Scripts/ContextMenu.cpp"
#include <algorithm>
#include <iostream>
#include <stdexcept>

struct Volume {
    std::wstring id;
    std::uint64_t total, available;
    bool readable = true, mounted = true, writable = true;
    UINT type = DRIVE_FIXED;
};
struct SystemState {
    std::vector<Volume> volumes;
    size_t index = 0;
    DWORD lastError = 0, errorMode = 32;
    LANGID language = 0x409;
    bool apiAvailable = true, enumerationWorks = true, failEnumerationEnd = false;
    unsigned lookups = 0, enumerations = 0, samples = 0, closes = 0, inserts = 0, processStarts = 0;
    std::wstring title;
} systemState;
static unsigned checks = 0;
static void Require(bool result, const char* message) {
    if (!result) throw std::runtime_error(message);
    ++checks;
}
static Volume& FindVolume(LPCWSTR name) {
    auto found = std::find_if(systemState.volumes.begin(), systemState.volumes.end(), [name](const Volume& v) { return v.id == name; });
    if (found == systemState.volumes.end()) throw std::runtime_error("unknown synthetic volume");
    return *found;
}
static HRESULT WINAPI Sample(LPCWSTR volume, JobsDiskSpaceInfo::DiskSpaceInformation* value) {
    ++systemState.samples;
    const auto& disk = FindVolume(volume);
    if (!disk.readable) return E_FAIL;
    value->actualTotal = disk.total;
    value->actualAvailable = disk.available;
    value->actualPoolUnavailable = 0;
    value->sectorsPerUnit = 8;
    value->bytesPerSector = 512;
    return S_OK;
}
BOOL SetThreadErrorMode(DWORD value, DWORD* previous) {
    if (previous) *previous = systemState.errorMode;
    systemState.errorMode = value;
    return TRUE;
}
HMODULE GetModuleHandleW(LPCWSTR) { return reinterpret_cast<HMODULE>(1); }
FARPROC GetProcAddress(HMODULE, const char* name) {
    ++systemState.lookups;
    Require(std::string(name) == "GetDiskSpaceInformationW", "production samples the expected disk API");
    return systemState.apiAvailable ? reinterpret_cast<FARPROC>(&Sample) : nullptr;
}
HANDLE FindFirstVolumeW(wchar_t* output, DWORD length) {
    ++systemState.enumerations;
    systemState.index = 0;
    if (!systemState.enumerationWorks || systemState.volumes.empty()) {
        systemState.lastError = ERROR_ACCESS_DENIED;
        return INVALID_HANDLE_VALUE;
    }
    Require(systemState.volumes.front().id.size() < length, "synthetic volume fits buffer");
    std::wcscpy(output, systemState.volumes.front().id.c_str());
    return reinterpret_cast<HANDLE>(1);
}
BOOL FindNextVolumeW(HANDLE, wchar_t* output, DWORD) {
    if (++systemState.index >= systemState.volumes.size()) {
        systemState.lastError = systemState.failEnumerationEnd ? ERROR_ACCESS_DENIED : ERROR_NO_MORE_FILES;
        return FALSE;
    }
    std::wcscpy(output, systemState.volumes[systemState.index].id.c_str());
    return TRUE;
}
BOOL FindVolumeClose(HANDLE) { ++systemState.closes; return TRUE; }
UINT GetDriveTypeW(LPCWSTR name) { return FindVolume(name).type; }
BOOL GetVolumePathNamesForVolumeNameW(LPCWSTR name, wchar_t* output, DWORD, DWORD*) {
    output[0] = FindVolume(name).mounted ? L'C' : 0;
    output[1] = 0;
    return TRUE;
}
DWORD GetLastError() { return systemState.lastError; }
BOOL GetVolumeInformationW(LPCWSTR name, wchar_t*, DWORD, DWORD*, DWORD*, DWORD* flags, wchar_t*, DWORD) {
    *flags = FindVolume(name).writable ? 0 : FILE_READ_ONLY_VOLUME;
    return TRUE;
}
LANGID GetUserDefaultUILanguage() { return systemState.language; }
int GetMenuItemCount(HMENU) { return 0; }
BOOL GetMenuItemInfoW(HMENU, UINT, BOOL, MENUITEMINFOW*) {
    throw std::runtime_error("synthetic fresh menu has no earlier rows");
}
BOOL InsertMenuItemW(HMENU, UINT position, BOOL byPosition, const MENUITEMINFOW* item) {
    Require(byPosition && position == 0, "inserts at requested menu position");
    Require(item->wID == 1 && item->dwItemData == JobsDesktopMenuOrder::ItemData(JobsDesktopMenuOrder::Rank::DiskSpace), "preserves command id and declares disk menu rank");
    systemState.title = item->dwTypeData;
    ++systemState.inserts;
    return TRUE;
}
DWORD GetModuleFileNameW(HMODULE, wchar_t*, DWORD) { throw std::runtime_error("unexpected cleaner routing"); }
UINT GetSystemDirectoryW(wchar_t*, UINT) { throw std::runtime_error("unexpected cleaner routing"); }
DWORD GetFileAttributesW(LPCWSTR) { throw std::runtime_error("unexpected cleaner routing"); }
BOOL CreateProcessW(LPCWSTR, wchar_t*, void*, void*, BOOL, DWORD, void*, LPCWSTR, STARTUPINFOW*, PROCESS_INFORMATION*) {
    ++systemState.processStarts;
    throw std::runtime_error("opening a menu must never launch a process");
}
BOOL CloseHandle(HANDLE) { throw std::runtime_error("unexpected process handle"); }

int main() {
    Menu* menu = new Menu();
    const auto open = [&] {
        const unsigned before = systemState.lookups;
        Require(menu->QueryContextMenu(reinterpret_cast<HMENU>(1), 0, 1, 100, 0) == 1, "normal popup adds one current row");
        Require(systemState.lookups == before + 1, "same COM instance resolves and invokes a new system query each popup");
        Require(systemState.errorMode == 32, "restores thread error policy after every sample");
        return systemState.title;
    };
    systemState.volumes = {{L"volume-A", 1000000, 500000}};
    Require(open() == L"💽 Disk free: 2.05 GB / 4.10 GB (50.00%)", "first menu reflects current volume");
    const unsigned firstSamples = systemState.samples;
    systemState.volumes[0].available = 750000;
    Require(open() == L"💽 Disk free: 3.07 GB / 4.10 GB (75.00%)", "reopened same handler samples changed remaining bytes");
    Require(systemState.samples == firstSamples + 1, "repeated identical volume GUID is sampled again");
    systemState.volumes[0].total = 2000000;
    systemState.volumes[0].available = 1500000;
    Require(open() == L"💽 Disk free: 6.14 GB / 8.19 GB (75.00%)", "total capacity changes are not cached");
    systemState.volumes = {{L"volume-A", 1000000, 250000}, {L"volume-B", 500000, 200000}};
    Require(open() == L"💽 Disk free: 1.84 GB / 6.14 GB (30.00%)", "newly mounted volumes enter current aggregate");
    systemState.volumes[1].readable = false;
    Require(open() == L"💽 Disk space unavailable", "failed volume discards previous successful aggregate and partial values");
    systemState.volumes = {{L"volume-A", 1000000, 900000}};
    Require(open() == L"💽 Disk free: 3.69 GB / 4.10 GB (90.00%)", "recovery and unmounted volumes use a new full sample");
    systemState.enumerationWorks = false;
    Require(open() == L"💽 Disk space unavailable", "enumeration failure never reuses successful title");
    systemState.enumerationWorks = true;
    systemState.apiAvailable = false;
    Require(open() == L"💽 Disk space unavailable", "missing API never reuses successful title");
    systemState.apiAvailable = true;
    systemState.failEnumerationEnd = true;
    Require(open() == L"💽 Disk space unavailable", "incomplete enumeration is not a cached or partial result");
    systemState.failEnumerationEnd = false;
    systemState.volumes[0].available = 0;
    Require(open() == L"💽 Disk free: 0.00 B / 4.10 GB (0.00%)", "genuine zero free differs from query failure");
    systemState.language = 0x804;
    Require(open() == L"💽 磁盘剩余：0.00 B / 4.10 GB (0.00%)", "language is also sampled for each popup");
    const auto beforeLookups = systemState.lookups, beforeInserts = systemState.inserts;
    Require(menu->QueryContextMenu(reinterpret_cast<HMENU>(1), 0, 1, 100, CMF_DEFAULTONLY) == 0, "default-command probe does not add popup row");
    Require(menu->QueryContextMenu(reinterpret_cast<HMENU>(1), 0, 2, 1, 0) == 0, "invalid command range does not add popup row");
    Require(systemState.lookups == beforeLookups && systemState.inserts == beforeInserts, "non-popup probes do not query or display old values");
    Require(systemState.closes == systemState.enumerations - 1, "all successfully opened enumerations close");
    Require(systemState.processStarts == 0, "capacity reads do not start cleanup or a process");
    Require(menu->Release() == 0, "release reused COM instance");
    std::cout << "PASS: ContextMenuFreshnessTests (" << checks << " assertions)\n";
}

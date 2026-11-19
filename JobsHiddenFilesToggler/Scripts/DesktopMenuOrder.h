// DesktopMenuOrder.h | Jobs Windows desktop menu infrastructure
// Created by Jobs on 2026年11月18日，星期三.
#ifndef JOBS_DESKTOP_MENU_ORDER_V1_H
#define JOBS_DESKTOP_MENU_ORDER_V1_H
#include <windows.h>

namespace JobsDesktopMenuOrder {
enum class Rank : UINT {
    CreateAndroid = 10,
    CreateHarmony = 20,
    RepairAndroid = 30,
    RepairHarmony = 40,
    HiddenFiles = 50,
    DiskSpace = 60
};

// 只交换整数标记；独立 DLL 不保存其它 handler 的地址或命令映射。
inline ULONG_PTR ItemData(Rank rank) {
    return static_cast<ULONG_PTR>(0x4a4f4200u) | static_cast<UINT>(rank);
}

inline bool ReadRank(ULONG_PTR data, UINT& rank) {
    if ((data & ~static_cast<ULONG_PTR>(0xffu)) != static_cast<ULONG_PTR>(0x4a4f4200u)) return false;
    rank = static_cast<UINT>(data & 0xffu);
    return rank == 10 || rank == 20 || rank == 30 || rank == 40 || rank == 50 || rank == 60;
}

inline BOOL Insert(HMENU menu, UINT suggestedPosition, UINT command, Rank rank,
                   LPCWSTR title, UINT state = MFS_ENABLED) {
    const int count = GetMenuItemCount(menu);
    if (count < 0) return FALSE;
    UINT position = suggestedPosition;
    for (int index = 0; index < count; ++index) {
        MENUITEMINFOW existing = {};
        existing.cbSize = sizeof(existing);
        existing.fMask = MIIM_DATA;
        if (!GetMenuItemInfoW(menu, static_cast<UINT>(index), TRUE, &existing)) return FALSE;
        UINT otherRank = 0;
        if (!ReadRank(existing.dwItemData, otherRank)) continue;
        if (otherRank > static_cast<UINT>(rank)) {
            position = static_cast<UINT>(index);
            break;
        }
        position = static_cast<UINT>(index) + 1;
    }
    MENUITEMINFOW item = {};
    item.cbSize = sizeof(item);
    item.fMask = MIIM_ID | MIIM_STRING | MIIM_STATE | MIIM_DATA;
    item.wID = command;
    item.fState = state;
    item.dwItemData = ItemData(rank);
    item.dwTypeData = const_cast<wchar_t*>(title);
    return InsertMenuItemW(menu, position, TRUE, &item);
}
}
#endif


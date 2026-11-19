// DiskSpaceSummary.h | JobsDiskSpaceInfo
// Created by Jobs on 2026年11月15日，星期日.
#pragma once
#include <cstdint>
#include <iomanip>
#include <limits>
#include <locale>
#include <set>
#include <sstream>
#include <string>

namespace JobsDiskSpaceInfo {
struct Summary {
    std::uint64_t total = 0;
    std::uint64_t free = 0;
    bool complete = true;
    std::set<std::wstring> volumes;

    // 同一卷的盘符和文件夹挂载点只累计一次；异常值不能变成看似有效的部分总量。
    bool Add(const std::wstring& volume, std::uint64_t capacity, std::uint64_t remaining) {
        if (volumes.count(volume)) return true;
        if (volume.empty() || !capacity || remaining > capacity ||
            total > (std::numeric_limits<std::uint64_t>::max)() - capacity ||
            free > (std::numeric_limits<std::uint64_t>::max)() - remaining) {
            complete = false;
            return false;
        }
        volumes.insert(volume);
        total += capacity;
        free += remaining;
        return true;
    }
    // API 的实际分配单元转换成字节；存储池不足的单元不计为剩余空间。
    bool AddAllocationUnits(const std::wstring& volume, std::uint64_t totalUnits,
                            std::uint64_t availableUnits, std::uint64_t poolUnavailable,
                            std::uint32_t sectorsPerUnit, std::uint32_t bytesPerSector) {
        const std::uint64_t unit = static_cast<std::uint64_t>(sectorsPerUnit) * bytesPerSector;
        const auto maximum = (std::numeric_limits<std::uint64_t>::max)();
        if (!unit || totalUnits > maximum / unit || availableUnits > maximum / unit || poolUnavailable > availableUnits) {
            complete = false;
            return false;
        }
        return Add(volume, totalUnits * unit, (availableUnits - poolUnavailable) * unit);
    }
};

// 十进制容量与未舍入字节比值分别格式化，百分比固定保留两位小数。
inline std::wstring FormatBytes(std::uint64_t bytes) {
    static const wchar_t* units[] = {L"B", L"KB", L"MB", L"GB", L"TB", L"PB", L"EB"};
    long double value = static_cast<long double>(bytes);
    unsigned unit = 0;
    while (value >= 1000 && unit < 6) {
        value /= 1000;
        ++unit;
    }
    std::wostringstream output;
    output.imbue(std::locale::classic());
    output << std::fixed << std::setprecision(2) << value << L' ' << units[unit];
    return output.str();
}

inline std::wstring FormatTitle(const Summary& summary, const std::string& language) {
    std::wstring prefix = L"Disk free: ";
    std::wstring unavailable = L"Disk space unavailable";
    if (language == "zh-Hans") { prefix = L"磁盘剩余："; unavailable = L"磁盘空间暂不可用"; }
    else if (language == "zh-Hant") { prefix = L"磁碟剩餘："; unavailable = L"磁碟空間暫不可用"; }
    else if (language == "bo") { prefix = L"སྡུད་སྡེར་ལྷག་མ། "; unavailable = L"སྡུད་སྡེར་གྱི་བར་སྟོང་འཐོབ་མི་ཐུབ།"; }
    else if (language == "ja") { prefix = L"ディスク空き："; unavailable = L"ディスク容量を取得できません"; }
    else if (language == "fr") { prefix = L"Espace libre : "; unavailable = L"Espace disque indisponible"; }
    else if (language == "es") { prefix = L"Espacio libre: "; unavailable = L"Espacio en disco no disponible"; }
    else if (language == "de") { prefix = L"Freier Speicher: "; unavailable = L"Speicherplatz nicht verfügbar"; }
    else if (language == "ru") { prefix = L"Свободно: "; unavailable = L"Данные о диске недоступны"; }
    else if (language == "ko") { prefix = L"디스크 여유: "; unavailable = L"디스크 공간을 확인할 수 없습니다"; }
    if (!summary.complete || !summary.total || summary.volumes.empty()) return L"💽 " + unavailable;
    std::wostringstream percentage;
    percentage.imbue(std::locale::classic());
    percentage << std::fixed << std::setprecision(2)
               << static_cast<long double>(summary.free) / static_cast<long double>(summary.total) * 100;
    return L"💽 " + prefix + FormatBytes(summary.free) + L" / " + FormatBytes(summary.total) + L" (" + percentage.str() + L"%)";
}
}

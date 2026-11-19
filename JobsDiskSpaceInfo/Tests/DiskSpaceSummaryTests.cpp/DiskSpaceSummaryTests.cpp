// DiskSpaceSummaryTests.cpp | JobsDiskSpaceInfo
// Created by Jobs on 2026年11月15日，星期日.
// 只测试合计、去重、异常与显示精度；不查询真实磁盘或注册菜单。
#include "../../Scripts/DiskSpaceSummary.h"
#include <iostream>
#include <stdexcept>

static unsigned checks = 0;
static void Require(bool result, const char* message) {
    if (!result) throw std::runtime_error(message);
    ++checks;
}
int main() {
    using namespace JobsDiskSpaceInfo;
    Summary summary;
    Require(FormatTitle(summary, "en") == L"💽 Disk space unavailable", "empty is unavailable");
    Require(summary.Add(L"volume-A", 750000000000ULL, 250000000000ULL), "first volume");
    Require(summary.Add(L"volume-B", 250000000000ULL, 0), "second volume includes full disk");
    Require(summary.Add(L"volume-A", 750000000000ULL, 250000000000ULL), "mount alias is harmless");
    Require(summary.total == 1000000000000ULL && summary.free == 250000000000ULL, "deduplicated aggregate");
    Require(FormatTitle(summary, "en") == L"💽 Disk free: 250.00 GB / 1.00 TB (25.00%)", "free capacity percentage");
    Require(FormatTitle(summary, "zh-Hans") == L"💽 磁盘剩余：250.00 GB / 1.00 TB (25.00%)", "Chinese title");
    std::set<std::wstring> titles;
    for (const std::string language : {"zh-Hans", "zh-Hant", "bo", "en", "ja", "fr", "es", "de", "ru", "ko"}) {
        const auto title = FormatTitle(summary, language);
        Require(title.find(L"250.00 GB / 1.00 TB (25.00%)") != std::wstring::npos, "ten languages keep values");
        Require(title.find(L'\n') == std::wstring::npos, "single line");
        titles.insert(title);
        Summary unavailable;
        Require(!FormatTitle(unavailable, language).empty(), "localized unavailable");
    }
    Require(titles.size() == 10, "ten distinct titles");
    Summary zeroCapacity;
    Require(!zeroCapacity.Add(L"zero", 0, 0), "zero capacity rejected");
    Summary fraction;
    Require(fraction.Add(L"fraction", 3, 1), "fraction total");
    Require(FormatTitle(fraction, "en").find(L"33.33%") != std::wstring::npos, "two decimal percentage");
    Summary allFree;
    Require(allFree.Add(L"free", 1000, 1000), "all free");
    Require(FormatTitle(allFree, "en").find(L"100.00%") != std::wstring::npos, "100 percent");
    Summary full;
    Require(full.Add(L"full", 1000, 0), "zero free is valid");
    Require(FormatTitle(full, "en").find(L"0.00%") != std::wstring::npos, "zero percent");
    Summary invalid;
    Require(!invalid.Add(L"invalid", 1, 2), "invalid free rejected");
    Require(FormatTitle(invalid, "en") == L"💽 Disk space unavailable", "invalid is unavailable");
    Summary overflow;
    Require(overflow.Add(L"max", (std::numeric_limits<std::uint64_t>::max)(), 0), "max volume");
    Require(!overflow.Add(L"extra", 1, 0), "sum overflow rejected");
    Require(FormatTitle(overflow, "en") == L"💽 Disk space unavailable", "no partial sum after overflow");
    summary.complete = false;
    Require(FormatTitle(summary, "en") == L"💽 Disk space unavailable", "query failure hides partial totals");
    Require(FormatBytes(0) == L"0.00 B", "zero bytes");
    Require(FormatTitle(allFree, "unsupported") == FormatTitle(allFree, "en"), "fallback English");
    Summary allocation;
    Require(allocation.AddAllocationUnits(L"pool", 1000, 500, 100, 8, 512), "allocation units");
    Require(allocation.total == 4096000 && allocation.free == 1638400, "unit conversion and pool unavailable subtraction");
    Require(FormatTitle(allocation, "en").find(L"40.00%") != std::wstring::npos, "actual units ratio");
    Summary invalidUnit;
    Require(!invalidUnit.AddAllocationUnits(L"invalid", 1000, 500, 0, 0, 512), "zero unit rejected");
    Summary invalidPool;
    Require(!invalidPool.AddAllocationUnits(L"invalid", 1000, 500, 501, 8, 512), "invalid pool count rejected");
    Summary unitOverflow;
    Require(!unitOverflow.AddAllocationUnits(L"overflow", (std::numeric_limits<std::uint64_t>::max)(), 1, 0, 8, 512), "unit multiplication overflow rejected");
    std::cout << "PASS: DiskSpaceSummaryTests (" << checks << " assertions)\n";
}

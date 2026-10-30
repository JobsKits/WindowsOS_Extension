// FileVolumesMenuProbe.cpp | JobsFileVolumes
// Created by Jobs on 2026年10月28日，星期三.
#include <cassert>
#include <cstdint>
#include <iostream>
#include <map>
#include <string>
using DWORD = std::uint32_t;
constexpr DWORD INVALID_FILE_ATTRIBUTES = 0xffffffff;
constexpr DWORD FILE_ATTRIBUTE_DIRECTORY = 0x10;
constexpr DWORD FILE_ATTRIBUTE_REPARSE_POINT = 0x400;
constexpr DWORD FILE_ATTRIBUTE_DEVICE = 0x40;
constexpr int GetFileExInfoStandard = 0;
struct WIN32_FILE_ATTRIBUTE_DATA { DWORD dwFileAttributes = 0, nFileSizeHigh = 0, nFileSizeLow = 1; };
static std::map<std::wstring, DWORD> attributes;
static bool empty = false;
static DWORD GetFileAttributesW(const wchar_t* path) { return attributes[path]; }
static bool GetFileAttributesExW(const wchar_t* path, int, WIN32_FILE_ATTRIBUTE_DATA* data) {
    data->dwFileAttributes = attributes[path]; data->nFileSizeLow = empty ? 0 : 1; return true;
}
#include "../JobsFileVolumes/Scripts/VolumeSelection.h"
int main() {
    using namespace JobsFileVolumes;
    unsigned count = 0;
    auto check = [&count](bool value) { assert(value); ++count; };
    const std::wstring folder = L"C:\\中文 & %TEMP%\\";
    const std::wstring first = folder + L"test@extra.iso@01of02", second = folder + L"test@extra.iso@2of2";
    check(CanSplit({first})); check(!CanMerge({first})); check(!CanSplit({first, second}));
    check(CanMerge({second, first})); check(!CanMerge({})); check(!CanSplit({}));
    for (const auto& bad : {L"test@extra.iso@1of2", L"test@extra.iso@03of03", L"test@extra.iso@0of2", L"test@extra.iso@3of2", L"test@extra.iso@2of3", L"other.iso@2of2", L"readme.txt", L"test@extra.iso@2of2.partial"}) {
        check(!CanMerge({first, folder + bad}));
    }
    check(!CanMerge({first, L"C:\\other\\test@extra.iso@2of2"}));
    for (const auto attr : {FILE_ATTRIBUTE_DIRECTORY, FILE_ATTRIBUTE_REPARSE_POINT, FILE_ATTRIBUTE_DEVICE, INVALID_FILE_ATTRIBUTES}) {
        attributes[first] = attr; check(!CanSplit({first})); check(!CanMerge({first, second}));
    }
    attributes[first] = 0; empty = true; check(!CanMerge({first, second})); check(CanSplit({first})); empty = false;
    std::wstring name; unsigned index = 0, total = 0;
    for (const auto& bad : {L"CON@1of2", L"com1.iso@1of2", L"NUL.txt@1of2", L"bad\nname@1of2", L"foo.@1of2", L"..@1of2", L"abc@0000000001of2"}) {
        check(!Parse(bad, name, index, total));
    }
    std::vector<std::wstring> numeric;
    for (unsigned i = 12; i > 0; --i) numeric.push_back(folder + L"large.bin@" + std::to_wstring(i) + L"of12");
    check(CanMerge(numeric));
    std::cout << "PASS: FileVolumesMenuProbe (" << count << " assertions)\n";
}

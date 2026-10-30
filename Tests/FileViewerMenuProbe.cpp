// FileViewerMenuProbe.cpp | Windows single-file scope regression
// Created by Jobs on 2026年10月27日，星期二.
#include <cassert>
#include <cstdint>
#include <iostream>
#include <string>
using DWORD = std::uint32_t;
constexpr DWORD INVALID_FILE_ATTRIBUTES = 0xffffffff;
constexpr DWORD FILE_ATTRIBUTE_DIRECTORY = 0x10;
constexpr DWORD FILE_ATTRIBUTE_REPARSE_POINT = 0x400;
constexpr DWORD FILE_ATTRIBUTE_DEVICE = 0x40;
static DWORD attributes = 0;
static unsigned probes = 0;
static DWORD GetFileAttributesW(const wchar_t*) { ++probes; return attributes; }
#include "../JobsFileContentViewer/Scripts/FileViewerTarget.h"
int main() {
    using namespace JobsFileViewer;
    unsigned count = 0;
    auto check = [&count](bool result) { assert(result); ++count; };
    check(IsSingleFile(1, L"C:\\中文 & %TEMP%\\file.txt"));
    const auto before = probes;
    check(!IsSingleFile(0, L"C:\\file.txt"));
    check(!IsSingleFile(2, L"C:\\file.txt"));
    check(probes == before);
    check(!IsSingleFile(1, L""));
    for (const auto value : {FILE_ATTRIBUTE_DIRECTORY, FILE_ATTRIBUTE_REPARSE_POINT, FILE_ATTRIBUTE_DEVICE, INVALID_FILE_ATTRIBUTES}) {
        attributes = value;
        check(!IsSingleFile(1, L"C:\\target"));
    }
    attributes = 0x2 | 0x1;
    check(IsSingleFile(1, L"C:\\hidden-readonly.md"));
    std::cout << "PASS: FileViewerMenuProbe (" << count << " assertions)\n";
}

// CommandShortcutTargetTests.cpp | JobsCommandShortcutCreator
// Created by Jobs on 2026年11月13日，星期五.
// Portable attribute-boundary fixtures; no real shell registration or filesystem mutation.
#include <map>
#include <string>
#include <iostream>
#include <stdexcept>
using DWORD = unsigned long;
constexpr DWORD INVALID_FILE_ATTRIBUTES = 0xffffffff;
constexpr DWORD FILE_ATTRIBUTE_DIRECTORY = 0x10;
constexpr DWORD FILE_ATTRIBUTE_REPARSE_POINT = 0x400;
constexpr DWORD FILE_ATTRIBUTE_DEVICE = 0x40;
static std::map<std::wstring, DWORD> attributes;
static DWORD GetFileAttributesW(const wchar_t* path) {
    const auto found = attributes.find(path);
    return found == attributes.end() ? INVALID_FILE_ATTRIBUTES : found->second;
}
#include "../../Scripts/CommandShortcutTarget.h"
int main() {
    unsigned assertions = 0;
    const auto expect = [&](bool value, const char* reason) {
        ++assertions;
        if (!value) throw std::runtime_error(reason);
    };
    for (const std::wstring extension : {L".cmd", L".bat", L".ps1", L".CMD"}) {
        const std::wstring directory = L"C:\\原生 %!&() ' 包\\demo" + extension;
        const std::wstring script = directory + L"\\demo" + extension;
        attributes[directory] = FILE_ATTRIBUTE_DIRECTORY;
        attributes[script] = 0;
        expect(JobsCommandShortcut::IsSingleDirectory(1, directory), "one eligible native package");
        expect(!JobsCommandShortcut::IsSingleDirectory(0, directory), "empty selection rejected");
        expect(!JobsCommandShortcut::IsSingleDirectory(2, directory), "multiple selection rejected");
        attributes[directory] |= FILE_ATTRIBUTE_REPARSE_POINT;
        expect(!JobsCommandShortcut::IsEligibleDirectory(directory), "linked directory rejected");
        attributes[directory] = FILE_ATTRIBUTE_DIRECTORY;
        attributes[script] = FILE_ATTRIBUTE_REPARSE_POINT;
        expect(!JobsCommandShortcut::IsEligibleDirectory(directory), "linked script rejected");
        attributes[script] = FILE_ATTRIBUTE_DIRECTORY;
        expect(!JobsCommandShortcut::IsEligibleDirectory(directory), "directory instead of script rejected");
        attributes.erase(script);
        expect(!JobsCommandShortcut::IsEligibleDirectory(directory), "missing script rejected");
    }
    for (const std::wstring path : {L"", L"C:\\ordinary", L"C:\\Mac.command", L"C:\\unknown.txt", L"C:\\folder.cmd\\"}) {
        attributes[path] = FILE_ATTRIBUTE_DIRECTORY;
        expect(!JobsCommandShortcut::IsEligibleDirectory(path), "non-native package rejected");
    }
    std::cout << "PASS: " << assertions << " native target assertions\n";
}

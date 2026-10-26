// SourcetreeInstallationProbe.cpp | JobsSourcetreeOpener
// Created by Jobs on 2026年10月26日，星期一.
#include "../JobsSourcetreeOpener/Scripts/SourcetreeInstallation.h"
#include <iostream>
#include <set>
#include <stdexcept>
int main() {
    std::set<std::wstring> installed;
    auto exists = [&installed](const std::wstring& path) { return installed.count(path) != 0; };
    const std::wstring first = L"C:\\User 中文 & [x]\\SourceTree\\SourceTree.exe";
    const std::wstring second = L"D:\\Tools\\SourceTree.exe";
    const std::vector<std::wstring> paths {first, second};
    if (!JobsSourcetree::Find(paths, exists).empty()) throw std::runtime_error("missing installation hidden");
    installed.insert(second);
    if (JobsSourcetree::Find(paths, exists) != second) throw std::runtime_error("stale registry path skipped");
    installed.insert(first);
    if (JobsSourcetree::Find(paths, exists) != first) throw std::runtime_error("candidate priority and unicode preserved");
    installed.clear();
    installed.insert(L"C:\\Update.exe");
    if (!JobsSourcetree::Find({L"C:\\Update.exe"}, exists).empty()) throw std::runtime_error("other executable rejected");
    installed.insert(L"C:\\SOURCETREE.EXE");
    if (JobsSourcetree::Find({L"C:\\SOURCETREE.EXE"}, exists).empty()) throw std::runtime_error("case-insensitive application name");
    std::cout << "PASS: SourcetreeInstallationProbe (5 assertions)\n";
}

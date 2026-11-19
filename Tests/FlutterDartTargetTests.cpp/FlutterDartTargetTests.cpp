// FlutterDartTargetTests.cpp | WindowsOS@Extension
// Created by Jobs on 2026年11月17日，星期二.
// 仅验证原生菜单共享的包边界算法，不连接 Explorer 或注册菜单。
#include "../../JobsFlutterRunner/Scripts/FlutterRunTarget.h"
#include <cassert>
#include <iostream>
#include <map>

int main() {
    std::map<std::wstring, bool> packages{{L"C:\\Demo 中文 & 100%", true}};
    const auto exists = [&](const std::wstring& path) { return packages.count(path) != 0; };
    const auto flutter = [&](const std::wstring& path) { return packages.count(path) && packages.at(path); };
    const std::wstring root = L"C:\\Demo 中文 & 100%";
    const auto resolve = [&](const std::wstring& path, bool plain = true) {
        return JobsFlutter::DartRunProject(path, plain, exists, flutter);
    };
    assert(resolve(root + L"\\lib\\页面 !^.dart") == root);
    assert(resolve(root + L"\\lib\\UPPER.DART") == root);
    assert(resolve(root + L"\\lib\\helper.txt").empty());
    assert(resolve(root + L"\\lib\\page.dart", false).empty());
    assert(resolve(L"D:\\Other\\main.dart").empty());
    packages[root + L"\\nested"] = false;
    assert(resolve(root + L"\\nested\\lib\\main.dart").empty());
    packages[root + L"\\nested"] = true;
    assert(resolve(root + L"\\nested\\lib\\main.dart") == root + L"\\nested");
    packages[L"C:\\"] = true;
    assert(resolve(L"C:\\main.dart") == L"C:\\");
    assert(JobsFlutter::RunTargetParent(L"C:\\") == L"C:\\");
    std::cout << "PASS: 9 Dart menu package-boundary assertions\n";
}

// AndroidRepairDesktopProbe.cpp | WindowsOS@Extension
// Created by Jobs on 2026年10月23日，星期五.
#include "../JobsAndroidSimulatorRepairer/Scripts/DesktopScope.h"
#include <cassert>
#include <iostream>
int main() {
    using JobsAndroid::IsDesktopContext;
    assert(IsDesktopContext(false, L"C:\\Users\\Jobs\\Desktop", L"C:\\Users\\Jobs\\Desktop"));
    assert(IsDesktopContext(false, L"c:/USERS/jobs/Desktop/", L"C:\\Users\\Jobs\\Desktop"));
    assert(IsDesktopContext(false, L"D:\\OneDrive\\桌面", L"D:\\OneDrive\\桌面"));
    assert(!IsDesktopContext(true, L"C:\\Users\\Jobs\\Desktop", L"C:\\Users\\Jobs\\Desktop"));
    assert(!IsDesktopContext(false, L"C:\\Users\\Jobs\\Desktop\\Demo", L"C:\\Users\\Jobs\\Desktop"));
    assert(!IsDesktopContext(false, L"C:\\Users\\Jobs\\Documents", L"C:\\Users\\Jobs\\Desktop"));
    assert(!IsDesktopContext(false, L"C:\\Users\\Jobs\\Documents\\Desktop", L"C:\\Users\\Jobs\\Desktop"));
    assert(!IsDesktopContext(false, L"", L"C:\\Users\\Jobs\\Desktop"));
    assert(!IsDesktopContext(false, L"C:\\Users\\Jobs\\Desktop", L""));
    std::cout << "PASS: AndroidRepairDesktopProbe (9 assertions)\n";
}

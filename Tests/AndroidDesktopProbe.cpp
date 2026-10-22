// AndroidDesktopProbe.cpp | WindowsOS@Extension
// Created by Jobs on 2026年10月22日，星期四.
#include "../JobsAndroidSimulatorCreator/Scripts/DesktopScope.h"
#include <cassert>
#include <iostream>
int main() {
    using JobsAndroid::IsDesktopContext;
    assert(IsDesktopContext(false, L"C:\\Users\\Jobs\\Desktop", L"C:\\Users\\Jobs\\Desktop"));
    assert(IsDesktopContext(false, L"c:/users/JOBS/Desktop/", L"C:\\Users\\Jobs\\Desktop"));
    assert(!IsDesktopContext(true, L"C:\\Users\\Jobs\\Desktop", L"C:\\Users\\Jobs\\Desktop"));
    assert(!IsDesktopContext(false, L"C:\\Users\\Jobs\\Desktop\\Demo", L"C:\\Users\\Jobs\\Desktop"));
    assert(!IsDesktopContext(false, L"C:\\Users\\Jobs\\Documents", L"C:\\Users\\Jobs\\Desktop"));
    assert(!IsDesktopContext(false, L"C:\\Users\\Jobs\\Documents\\Desktop", L"C:\\Users\\Jobs\\Desktop"));
    assert(!IsDesktopContext(false, L"", L"C:\\Users\\Jobs\\Desktop"));
    assert(!IsDesktopContext(false, L"C:\\Users\\Jobs\\Desktop", L""));
    assert(IsDesktopContext(false, L"D:\\OneDrive\\桌面", L"D:\\OneDrive\\桌面"));
    std::cout << "PASS: AndroidDesktopProbe (9 assertions)\n";
}

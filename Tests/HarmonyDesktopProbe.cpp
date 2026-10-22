// HarmonyDesktopProbe.cpp | WindowsOS@Extension
// Created by Jobs on 2026年10月23日，星期五.
#include "../JobsHarmonySimulatorCreator/Scripts/DesktopScope.h"
#include <cassert>
#include <iostream>

int main() {
    using JobsHarmony::IsDesktopContext;
    assert(IsDesktopContext(false, L"C:\\Users\\Jobs\\Desktop", L"C:\\Users\\Jobs\\Desktop"));
    assert(IsDesktopContext(false, L"c:/users/JOBS/Desktop/", L"C:\\Users\\Jobs\\Desktop"));
    assert(!IsDesktopContext(true, L"C:\\Users\\Jobs\\Desktop", L"C:\\Users\\Jobs\\Desktop"));
    assert(!IsDesktopContext(false, L"C:\\Users\\Jobs\\Desktop\\Demo", L"C:\\Users\\Jobs\\Desktop"));
    assert(!IsDesktopContext(false, L"C:\\Users\\Jobs\\Documents", L"C:\\Users\\Jobs\\Desktop"));
    assert(!IsDesktopContext(false, L"C:\\Users\\Jobs\\Documents\\Desktop", L"C:\\Users\\Jobs\\Desktop"));
    assert(!IsDesktopContext(false, L"C:\\Users\\Jobs\\Desktop-copy", L"C:\\Users\\Jobs\\Desktop"));
    assert(!IsDesktopContext(false, L"", L"C:\\Users\\Jobs\\Desktop"));
    assert(!IsDesktopContext(false, L"C:\\Users\\Jobs\\Desktop", L""));
    assert(IsDesktopContext(false, L"D:\\OneDrive\\桌面", L"D:\\OneDrive\\桌面"));
    assert(!IsDesktopContext(true, L"D:\\OneDrive\\桌面", L"D:\\OneDrive\\桌面"));
    assert(IsDesktopContext(false, L"D:/OneDrive/Jobs 中文 & 100%/", L"D:\\OneDrive\\Jobs 中文 & 100%"));
    assert(!IsDesktopContext(false, L"C:\\Users\\Jobs\\Desktop", L"C:\\Users\\Jobs\\Desktop", false));
    std::cout << "PASS: HarmonyDesktopProbe (13 assertions)\n";
}

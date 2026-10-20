// FlutterRunnerProjectProbe.cpp | WindowsOS@Extension 隔离验证
// Created by Jobs on 2026年10月20日，星期二.
#include "../JobsFlutterRunner/Scripts/FlutterProject.h"
#include <fstream>
#include <iostream>
#include <iterator>
int main(int count, char** arguments) {
    if (count != 2) return 2;
    std::ifstream input(arguments[1], std::ios::binary);
    if (!input) return 3;
    std::string text((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
    std::cout << (JobsFlutter::IsFlutterPubspec(text) ? "true" : "false") << std::endl;
    return 0;
}

// GitRollbackFzfProbe.cpp | native UTF8 stdin/stdout fixture, no Git operations
// Created by Jobs on 2026年10月26日，星期一.
#include <iostream>
#include <string>
int main(int argc, char** argv) {
    bool back = false;
    for (int i = 1; i < argc; ++i) {
        const std::string option(argv[i]);
        if (option == "--version") { std::cout << "0.99 fixture\n"; return 0; }
        if (option == "--help") { std::cout << "--expect --reverse --no-sort\n"; return 0; }
        if (option == "--expect=left") back = true;
    }
    std::string first;
    if (!std::getline(std::cin, first)) return 1;
    if (back) std::cout << '\n';
    std::cout << first << '\n';
    return 0;
}

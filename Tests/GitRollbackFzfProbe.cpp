// GitRollbackFzfProbe.cpp | native UTF8 stdin/stdout fixture, no Git operations
// Created by Jobs on 2026年10月26日，星期一.
#include <iostream>
#include <string>
#include <cstdlib>
#include <initializer_list>
int main(int argc, char** argv) {
    bool back = false;
    for (int i = 1; i < argc; ++i) {
        const std::string option(argv[i]);
        if (option == "--version") { std::cout << "0.99 fixture\n"; return 0; }
        if (option == "--help") { std::cout << "--expect --reverse --no-sort\n"; return 0; }
        if (option == "--expect=left") back = true;
    }
    const char* modeValue = std::getenv("JOBS_FZF_PROBE_MODE");
    const std::string mode = modeValue ? modeValue : "select";
    if (mode == "early-cancel") return 130;
    if (mode == "early-back") { std::cout << "left\n"; return 1; }
    if (mode == "early-back-zero") { std::cout << "left\n"; return 0; }
    for (const char* name : {"FZF_DEFAULT_OPTS", "FZF_DEFAULT_OPTS_FILE"}) {
        const char* value = std::getenv(name);
        if (value && *value) return 24;
    }
    std::string first;
    if (!std::getline(std::cin, first)) return 1;
    if (first.compare(0, 3, "\xEF\xBB\xBF") == 0) {
        std::cerr << "Unexpected UTF-8 BOM at native stdin.\n";
        return 23;
    }
    if (first != u8"选择提交 soft 回退") {
        std::cerr << "Unexpected UTF-8 candidate bytes at native stdin.\n";
        return 25;
    }
    if (mode == "early-select") {
        if (back) std::cout << '\n';
        std::cout << first << '\n';
        return 0;
    }
    std::string remaining;
    while (std::getline(std::cin, remaining)) { }
    if (mode == "cancel") return 130;
    if (mode == "failure") return 2;
    if (mode == "empty") return 0;
    if (mode == "back") { std::cout << "left\n"; return 1; }
    if (back) std::cout << '\n';
    if (mode == "outside") { std::cout << "outside candidate\n"; return 0; }
    if (mode == "invalid-utf8") { std::cout << "\xC3\x28\n"; return 0; }
    std::cout << first << '\n';
    return 0;
}

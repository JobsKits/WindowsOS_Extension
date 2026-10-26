#pragma once
#include <array>
#include <string>
namespace JobsFlutterTools {
struct Entry { const wchar_t* action; const wchar_t* label; };
static const Entry Entries[] = {
    {L"run", L"从终端运行 Flutter 项目"},
    {L"pub-get", L"拉取Flutter第三方依赖"},
    {L"extract", L"提取Flutter第三方依赖"},
    {L"sdk-version", L"查看当前Flutter项目的SDK版本"},
    {L"sdk-manage", L"安装/切换Flutter SDK版本"},
    {L"ohos-sdk-manage", L"安装/切换 Flutter@OpenHarmony SDK"},
    {L"package", L"Flutter打包"},
    {L"codegen", L"Flutter自动化生产代码"},
    {L"native-doctor", L"原生Flutter项目体检"},
    {L"harmony-doctor", L"OpenHarmony Flutter 环境体检"},
    {L"maintenance", L"Flutter清理维护工具"},
    {L"repair-android", L"修复 Android SDK / platforms 缺失"},
    {L"repair-imports", L"修复 Flutter 项目中文路径"},
    {L"repair-namespace", L"修复 Flutter 插件 namespace"},
};
static const unsigned Count = sizeof(Entries) / sizeof(Entries[0]);
using Selection = std::array<bool, Count>;
// 安装器写入固定 ASCII 动作表；损坏配置不回退为全部启用。
inline bool ParseSelection(const std::string& text, Selection& selected) {
    selected.fill(false);
    if (text.empty() || text.size() > 4096) return false;
    size_t start = 0;
    while (start < text.size()) {
        const size_t end = text.find('\n', start);
        std::string token = text.substr(start, end == std::string::npos ? end : end - start);
        if (!token.empty() && token.back() == '\r') token.pop_back();
        bool found = false;
        for (unsigned index = 0; index < Count; ++index) {
            const std::wstring wide(Entries[index].action);
            if (token == std::string(wide.begin(), wide.end())) {
                if (selected[index]) return false;
                selected[index] = true;
                found = true;
                break;
            }
        }
        if (!found) return false;
        if (end == std::string::npos) break;
        start = end + 1;
    }
    return true;
}
inline bool ParseMenuState(const std::string& text, std::string& release, Selection& selected) {
    selected.fill(false);
    release.clear();
    const std::string version = "JobsFlutterTools-v1\n";
    if (text.size() > 65536 || text.compare(0, version.size(), version) != 0) return false;
    const auto end = text.find('\n', version.size());
    if (end == std::string::npos || end == version.size()) return false;
    release = text.substr(version.size(), end - version.size());
    for (unsigned char c : release) { if (c < 32) return false; }
    return ParseSelection(text.substr(end + 1), selected);
}
}

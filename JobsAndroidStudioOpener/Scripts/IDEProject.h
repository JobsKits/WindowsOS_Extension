// IDEProject.h | Jobs IDE directory eligibility
// Created by Jobs on 2026年10月26日，星期一.
#pragma once
#include <functional>
#include <codecvt>
#include <locale>
#include <regex>
#include <string>
#include <vector>
#include "FlutterProject.h"
namespace JobsIDE {
struct Files {
    std::function<int(const std::wstring&)> kind;
    std::function<bool(const std::wstring&, std::vector<std::wstring>&)> entries;
    std::function<bool(const std::wstring&, std::string&)> read;
};
enum class Kind { AndroidStudio, VSCode };
inline std::wstring Normalize(std::wstring path) {
    for (auto& character : path) { if (character == L'/') character = L'\\'; }
    std::wstring prefix;
    size_t offset = 0, floor = 0;
    if (path.compare(0, 2, L"\\\\") == 0) { prefix = L"\\\\"; offset = 2; floor = 2; }
    else if (path.size() >= 2 && path[1] == L':') { prefix = path.substr(0, 2) + L"\\"; offset = 2; }
    else if (!path.empty() && path[0] == L'\\') { prefix = L"\\"; offset = 1; }
    std::vector<std::wstring> components;
    while (offset < path.size()) {
        const auto end = path.find(L'\\', offset);
        const auto part = path.substr(offset, end == std::wstring::npos ? end : end - offset);
        if (part == L"..") { if (components.size() > floor) components.pop_back(); }
        else if (!part.empty() && part != L".") components.push_back(part);
        if (end == std::wstring::npos) break;
        offset = end + 1;
    }
    std::wstring result = prefix;
    for (const auto& part : components) { if (!result.empty() && result.back() != L'\\') result += L'\\'; result += part; }
    return result;
}
inline std::wstring Join(const std::wstring& path, const std::wstring& name) { return Normalize(path + L"\\" + name); }
inline bool EndsWith(const std::wstring& value, const std::wstring& suffix) {
    if (value.size() < suffix.size()) return false;
    auto tail = value.substr(value.size() - suffix.size());
    for (auto& character : tail) { if (character >= L'A' && character <= L'Z') character += L'a' - L'A'; }
    return tail == suffix;
}
inline bool Noise(const std::wstring& name) {
    return (EndsWith(name, L".ds_store") && name.size() == 9) ||
        (EndsWith(name, L"thumbs.db") && name.size() == 9) ||
        (EndsWith(name, L"desktop.ini") && name.size() == 11);
}
inline bool Has(const std::string& text, const std::string& token) { return text.find(token) != std::string::npos; }
inline bool Read(const Files& files, const std::wstring& path, std::string& text) {
    return files.kind(path) == 0 && files.read(path, text);
}
inline std::string GradleCode(const std::string& text) {
    std::string output;
    char quote = 0;
    for (size_t index = 0; index < text.size(); ++index) {
        const char character = text[index];
        if (quote) {
            output += character;
            if (character == '\\' && index + 1 < text.size()) output += text[++index];
            else if (character == quote) quote = 0;
        } else if (character == '/' && index + 1 < text.size() && text[index + 1] == '/') {
            while (index < text.size() && text[index] != '\n') ++index;
            output += '\n';
        } else if (character == '/' && index + 1 < text.size() && text[index + 1] == '*') {
            const auto end = text.find("*/", index + 2);
            if (end == std::string::npos) break;
            index = end + 1;
            output += ' ';
        } else {
            output += character;
            if (character == '\'' || character == '"') quote = character;
        }
    }
    return output;
}
inline bool AndroidPlugin(const std::string& text) {
    const auto source = GradleCode(text);
    static const std::regex plugin(R"rx((id\s*\(?\s*|apply\s+plugin\s*:\s*|apply\s*\(\s*plugin\s*=\s*)["']com\.android\.(application|library|dynamic-feature|test)["']|alias\s*\(\s*libs\.plugins\.android[.A-Za-z0-9_]*\s*\)|classpath\s*\(?\s*["']com\.android\.tools\.build:gradle)rx");
    return std::regex_search(source, plugin);
}
inline bool Flutter(const Files& files, const std::wstring& path) {
    std::string text;
    return Read(files, Join(path, L"pubspec.yaml"), text) && JobsFlutter::IsFlutterPubspec(text);
}
inline bool Android(const Files& files, const std::wstring& path) {
    if (Flutter(files, path)) return true;
    const bool settings = files.kind(Join(path, L"settings.gradle")) == 0 || files.kind(Join(path, L"settings.gradle.kts")) == 0;
    if (!settings) return false;
    for (const auto name : {L"build.gradle", L"build.gradle.kts", L"settings.gradle", L"settings.gradle.kts"}) {
        std::string text;
        if (Read(files, Join(path, name), text) && AndroidPlugin(text)) return true;
    }
    for (const auto name : {L"app\\build.gradle", L"app\\build.gradle.kts"}) {
        std::string text;
        if (Read(files, Join(path, name), text) && AndroidPlugin(text)) return true;
    }
    const bool rootBuild = files.kind(Join(path, L"build.gradle")) == 0 || files.kind(Join(path, L"build.gradle.kts")) == 0;
    if (rootBuild && (files.kind(Join(path, L"AndroidManifest.xml")) == 0 || files.kind(Join(path, L"src\\main\\AndroidManifest.xml")) == 0)) return true;
    const bool appBuild = files.kind(Join(path, L"app\\build.gradle")) == 0 || files.kind(Join(path, L"app\\build.gradle.kts")) == 0;
    return appBuild && files.kind(Join(path, L"app\\src\\main\\AndroidManifest.xml")) == 0;
}
inline bool IOSProject(const Files& files, const std::wstring& project, bool& reliable) {
    const int projectKind = files.kind(project);
    const auto metadata = Join(project, L"project.pbxproj");
    const int metadataKind = files.kind(metadata);
    if (projectKind == 2 || metadataKind > 0) { reliable = false; return false; }
    if (projectKind != 1 || metadataKind != 0) return false;
    std::string text;
    if (!files.read(metadata, text)) { reliable = false; return false; }
    return std::regex_search(text, std::regex(R"((SDKROOT\s*=\s*"?iphone(os|simulator)|SUPPORTED_PLATFORMS\s*=\s*"?[^;]*iphone(os|simulator)))"));
}
inline bool IOSAt(const Files& files, const std::wstring& path, bool& reliable) {
    std::vector<std::wstring> entries;
    if (files.kind(path) != 1 || !files.entries(path, entries)) { reliable = false; return false; }
    for (const auto& entry : entries) {
        const auto project = Join(path, entry);
        if (EndsWith(entry, L".xcodeproj") && IOSProject(files, project, reliable)) return true;
        std::string text;
        if (!EndsWith(entry, L".xcworkspace")) continue;
        const auto contents = Join(project, L"contents.xcworkspacedata");
        if (files.kind(project) == 2 || files.kind(contents) > 0) { reliable = false; continue; }
        if (files.kind(project) != 1 || files.kind(contents) != 0) continue;
        if (!files.read(contents, text)) { reliable = false; continue; }
        const std::regex reference(R"ref(location\s*=\s*["'](group|container|absolute):([^"']+\.xcodeproj)["'])ref", std::regex::icase);
        for (std::sregex_iterator match(text.begin(), text.end(), reference), end; match != end; ++match) {
            std::string relative = (*match)[2].str();
            for (const auto& entity : std::vector<std::pair<std::string, std::string>> {{"&amp;", "&"}, {"&quot;", "\""}, {"&apos;", "'"}, {"&lt;", "<"}, {"&gt;", ">"}}) {
                size_t position = 0;
                while ((position = relative.find(entity.first, position)) != std::string::npos) { relative.replace(position, entity.first.size(), entity.second); position += entity.second.size(); }
            }
            if (relative.empty()) { reliable = false; continue; }
            std::wstring destination;
            try { destination = std::wstring_convert<std::codecvt_utf8_utf16<wchar_t>>().from_bytes(relative); } catch (...) { reliable = false; continue; }
            for (auto& character : destination) { if (character == '/') character = L'\\'; }
            std::string referenceKind = (*match)[1].str();
            for (auto& character : referenceKind) { if (character >= 'A' && character <= 'Z') character += 'a' - 'A'; }
            const auto resolved = referenceKind == "absolute" ? Normalize(destination) : Join(path, destination);
            if (files.kind(resolved) != 1) { reliable = false; continue; }
            if (IOSProject(files, resolved, reliable)) return true;
        }
    }
    return false;
}
inline bool Eligible(const Files& files, const std::wstring& path, Kind kind) {
    std::vector<std::wstring> entries;
    if (files.kind(path) != 1 || !files.entries(path, entries) || entries.empty()) return false;
    bool hasContent = false;
    for (const auto& entry : entries) { if (!Noise(entry)) { hasContent = true; break; } }
    if (!hasContent) return false;
    for (const auto suffix : {L".app", L".xcodeproj", L".xcworkspace", L".bundle", L".framework"}) {
        if (EndsWith(path, suffix)) return false;
    }
    if (kind == Kind::AndroidStudio) return Android(files, path);
    if (Flutter(files, path)) return true;
    bool reliable = true;
    return !IOSAt(files, path, reliable) && reliable;
}
}

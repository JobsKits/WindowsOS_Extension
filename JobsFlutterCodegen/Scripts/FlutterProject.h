// FlutterProject.h | JobsFlutterRunner
// Created by Jobs on 2026年10月20日，星期二.
// 菜单桥接与隔离测试共用的有限 YAML 读取器；不执行项目脚本或查找父子目录。
#pragma once
#include <algorithm>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace JobsFlutter {
inline std::string Trim(const std::string& text) {
    const size_t first = text.find_first_not_of(" \r\n");
    if (first == std::string::npos) return "";
    return text.substr(first, text.find_last_not_of(" \r\n") - first + 1);
}
inline std::string Atom(const std::string& value) {
    std::string text = Trim(value);
    if (text.size() >= 2 && ((text.front() == '\'' && text.back() == '\'') ||
        (text.front() == '"' && text.back() == '"'))) return text.substr(1, text.size() - 2);
    return text;
}
inline std::string WithoutComment(const std::string& text) {
    char quote = 0;
    for (size_t i = 0; i < text.size(); ++i) {
        const char c = text[i];
        if (quote == '"' && c == '\\') { ++i; continue; }
        if (quote == '\'' && c == '\'' && i + 1 < text.size() && text[i + 1] == '\'') { ++i; continue; }
        if (quote) { if (c == quote) quote = 0; continue; }
        if (c == '\'' || c == '"') { quote = c; continue; }
        if (c == '#' && (i == 0 || text[i - 1] == ' ' || text[i - 1] == '\t')) return text.substr(0, i);
    }
    return text;
}
inline std::map<std::string, std::string> FlowMap(const std::string& text) {
    const std::string value = Trim(text);
    if (value.size() < 2 || value.front() != '{' || value.back() != '}') throw std::runtime_error("flow map");
    std::map<std::string, std::string> result;
    const std::string body = value.substr(1, value.size() - 2);
    int depth = 0;
    char quote = 0;
    size_t start = 0;
    for (size_t i = 0; i <= body.size(); ++i) {
        const char c = i < body.size() ? body[i] : ',';
        if (quote == '"' && c == '\\') { ++i; continue; }
        if (quote) { if (c == quote) quote = 0; continue; }
        if (c == '\'' || c == '"') { quote = c; continue; }
        if (c == '{' || c == '[') ++depth;
        if (c == '}' || c == ']') --depth;
        if (depth < 0) throw std::runtime_error("flow depth");
        if (c != ',' || depth != 0) continue;
        const std::string part = Trim(body.substr(start, i - start));
        start = i + 1;
        if (part.empty()) {
            if (i == body.size() && (Trim(body).empty() || !result.empty())) continue;
            throw std::runtime_error("empty flow entry");
        }
        const size_t colon = part.find(':');
        if (colon == std::string::npos) throw std::runtime_error("flow entry");
        if (part.front() != '\'' && part.front() != '"' && colon + 1 < part.size() && part[colon + 1] != ' ') throw std::runtime_error("flow separator");
        const std::string key = Atom(part.substr(0, colon));
        if (key.empty() || result.count(key)) throw std::runtime_error("duplicate key");
        result[key] = Trim(part.substr(colon + 1));
    }
    if (quote || depth) throw std::runtime_error("unclosed map");
    return result;
}
struct Entry { size_t indent; std::string key; std::string value; };
inline bool IsFlutterPubspec(const std::string& source) {
    try {
        if (source.find('\0') != std::string::npos) return false;
        std::string input = source;
        if (input.compare(0, 3, "\xEF\xBB\xBF") == 0) input.erase(0, 3);
        std::vector<std::string> lines;
        std::istringstream stream(input);
        std::string line;
        size_t root = 0, roots = 0;
        std::string rootValue;
        while (std::getline(stream, line)) {
            line = WithoutComment(line);
            if (Trim(line) == "---" || Trim(line) == "...") return false;
            if (line.substr(0, line.find_first_not_of(" \t")).find('\t') != std::string::npos) return false;
            lines.push_back(line);
            const size_t colon = line.find(':');
            if (!line.empty() && line[0] != ' ' && colon != std::string::npos && Atom(line.substr(0, colon)) == "dependencies") {
                root = lines.size() - 1;
                rootValue = Trim(line.substr(colon + 1));
                ++roots;
            }
        }
        if (roots != 1) return false;
        if (!rootValue.empty()) {
            const auto dependencies = FlowMap(rootValue);
            if (!dependencies.count("flutter")) return false;
            const auto flutter = FlowMap(dependencies.at("flutter"));
            return flutter.count("sdk") && Atom(flutter.at("sdk")) == "flutter";
        }
        std::vector<Entry> entries;
        size_t minimum = static_cast<size_t>(-1);
        for (size_t i = root + 1; i < lines.size(); ++i) {
            if (Trim(lines[i]).empty()) continue;
            if (lines[i][0] != ' ') break;
            const size_t colon = lines[i].find(':');
            const size_t indent = lines[i].find_first_not_of(' ');
            if (colon == std::string::npos || indent == std::string::npos) return false;
            entries.push_back({indent, Atom(lines[i].substr(indent, colon - indent)), Trim(lines[i].substr(colon + 1))});
            minimum = (std::min)(minimum, indent);
        }
        size_t selected = 0, declarations = 0;
        for (size_t i = 0; i < entries.size(); ++i) {
            if (entries[i].indent == minimum && entries[i].key == "flutter") { selected = i; ++declarations; }
        }
        if (declarations != 1) return false;
        if (!entries[selected].value.empty()) {
            const auto flutter = FlowMap(entries[selected].value);
            return flutter.count("sdk") && Atom(flutter.at("sdk")) == "flutter";
        }
        std::string sdk;
        size_t childIndent = static_cast<size_t>(-1), sdkCount = 0;
        for (size_t i = selected + 1; i < entries.size() && entries[i].indent > minimum; ++i) {
            if (entries[i].indent < childIndent) { childIndent = entries[i].indent; sdkCount = 0; sdk.clear(); }
            if (entries[i].indent == childIndent && entries[i].key == "sdk") { ++sdkCount; sdk = Atom(entries[i].value); }
        }
        return sdkCount == 1 && sdk == "flutter";
    } catch (...) { return false; }
}
}

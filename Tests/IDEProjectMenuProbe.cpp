// IDEProjectMenuProbe.cpp | Jobs IDE menu eligibility regression
// Created by Jobs on 2026年10月26日，星期一.
#include <cassert>
#include <iostream>
#include <map>
#include <set>
#include "../JobsAndroidStudioOpener/Scripts/IDEProject.h"
struct Fixture {
    const std::wstring root = L"C:\\fixture";
    std::map<std::wstring, std::pair<int, std::string>> items;
    std::set<std::wstring> unreadable;
    Fixture() { items[root] = {1, ""}; }
    void Add(std::wstring relative, const std::string& text, bool directory = false) {
        for (auto& character : relative) { if (character == '/') character = L'\\'; }
        const std::wstring path = JobsIDE::Join(root, relative);
        size_t index = 2;
        while ((index = path.find(L'\\', index + 1)) != std::wstring::npos) items[path.substr(0, index)] = {1, ""};
        items[path] = {directory ? 1 : 0, text};
    }
    JobsIDE::Files Files() {
        return {
            [this](const std::wstring& path) { const auto found = items.find(path); return found == items.end() ? -1 : found->second.first; },
            [this](const std::wstring& path, std::vector<std::wstring>& output) {
                if (!items.count(path) || items[path].first != 1) return false;
                std::set<std::wstring> names;
                const std::wstring prefix = path + L"\\";
                for (const auto& item : items) {
                    if (item.first.compare(0, prefix.size(), prefix) != 0) continue;
                    const auto relative = item.first.substr(prefix.size());
                    names.insert(relative.substr(0, relative.find(L'\\')));
                }
                output.assign(names.begin(), names.end());
                return true;
            },
            [this](const std::wstring& path, std::string& output) {
                if (!items.count(path) || items[path].first != 0 || unreadable.count(path)) return false;
                output = items[path].second;
                return true;
            }
        };
    }
};
int main() {
    unsigned count = 0;
    auto check = [&count](Fixture& fixture, bool android, bool vscode) {
        const auto files = fixture.Files();
        assert(JobsIDE::Eligible(files, fixture.root, JobsIDE::Kind::AndroidStudio) == android); ++count;
        assert(JobsIDE::Eligible(files, fixture.root, JobsIDE::Kind::VSCode) == vscode); ++count;
    };
    Fixture empty; check(empty, false, false);
    Fixture noise; noise.Add(L".DS_Store", "metadata"); noise.Add(L"Thumbs.db", "metadata"); noise.Add(L"desktop.ini", "metadata"); check(noise, false, false);
    Fixture plain; plain.Add(L"README.md", "notes"); check(plain, false, true);
    Fixture hidden; hidden.Add(L".git", "", true); check(hidden, false, true);
    Fixture flutter; flutter.Add(L"pubspec.yaml", "name: sample\ndependencies:\n  flutter:\n    sdk: flutter\n"); check(flutter, true, true);
    flutter.Add(L"ios/Runner.xcodeproj/project.pbxproj", "SDKROOT = iphoneos;"); check(flutter, true, true);
    Fixture harmony; harmony.Add(L"pubspec.yaml", "dependencies: {flutter: {sdk: flutter}}\n"); harmony.Add(L"ohos", "", true); check(harmony, true, true);
    for (const std::string source : {"description: 'dependencies flutter sdk flutter'\n", "dev_dependencies:\n  flutter_test:\n    sdk: flutter\n", "dependencies:\n  flutter:\n    sdk: dart\n", "dependencies: {flutter: {sdk: flutter}}\ndependencies: {}\n"}) {
        Fixture invalid; invalid.Add(L"pubspec.yaml", source); check(invalid, false, true);
    }
    Fixture android; android.Add(L"settings.gradle", "rootProject.name='fixture'"); android.Add(L"build.gradle", "plugins { id 'com.android.application' }"); check(android, true, true);
    Fixture kotlin; kotlin.Add(L"settings.gradle.kts", "include(\":app\")"); kotlin.Add(L"app/build.gradle.kts", "plugins { id(\"com.android.library\") }"); check(kotlin, true, true);
    Fixture manifests; manifests.Add(L"settings.gradle", "include ':app'"); manifests.Add(L"app/build.gradle", "android {}"); manifests.Add(L"app/src/main/AndroidManifest.xml", "<manifest />"); check(manifests, true, true);
    Fixture java; java.Add(L"settings.gradle", "rootProject.name='java'"); java.Add(L"build.gradle", "plugins { id 'java' }"); check(java, false, true);
    Fixture comment; comment.Add(L"settings.gradle", "rootProject.name='java'"); comment.Add(L"build.gradle", "// id 'com.android.application'\n/* apply plugin: 'com.android.library' */\ndescription = 'com.android.application';"); check(comment, false, true);
    Fixture alias; alias.Add(L"settings.gradle", "include ':app'"); alias.Add(L"app/build.gradle.kts", "plugins { alias(libs.plugins.android.application) }"); check(alias, true, true);
    Fixture noSettings; noSettings.Add(L"build.gradle", "plugins { id 'com.android.application' }"); check(noSettings, false, true);
    Fixture ios; ios.Add(L"Demo.xcodeproj/project.pbxproj", "SDKROOT = iphoneos;"); check(ios, false, false);
    Fixture simulator; simulator.Add(L"Demo.xcodeproj/project.pbxproj", "SUPPORTED_PLATFORMS = \"iphonesimulator\";"); check(simulator, false, false);
    Fixture mac; mac.Add(L"Demo.xcodeproj/project.pbxproj", "SDKROOT = macosx;"); check(mac, false, true);
    Fixture package; package.Add(L"Package.swift", ".iOS(.v17)"); check(package, false, true);
    Fixture nested; nested.Add(L"ios/Demo.xcodeproj/project.pbxproj", "SDKROOT = iphoneos;"); check(nested, false, true);
    Fixture workspace; workspace.Add(L"Demo.xcworkspace/contents.xcworkspacedata", "<Workspace><FileRef location=\"group:Child/Demo.xcodeproj\" /></Workspace>"); workspace.Add(L"Child/Demo.xcodeproj/project.pbxproj", "SDKROOT = iphoneos;"); check(workspace, false, false);
    Fixture unicode; unicode.Add(L"Demo.xcworkspace/contents.xcworkspacedata", u8"<FileRef location=\"group:中文 &amp; file/Demo.xcodeproj\" />"); unicode.Add(L"中文 & file/Demo.xcodeproj/project.pbxproj", "SDKROOT = iphoneos;"); check(unicode, false, false);
    Fixture sibling; sibling.Add(L"Demo.xcworkspace/contents.xcworkspacedata", "<FileRef location=\"group:../Sibling/Demo.xcodeproj\" />"); sibling.Add(L"../Sibling/Demo.xcodeproj/project.pbxproj", "SDKROOT = iphoneos;"); check(sibling, false, false);
    Fixture unknown; unknown.Add(L"Demo.xcodeproj/project.pbxproj", "SDKROOT = iphoneos;"); unknown.unreadable.insert(JobsIDE::Join(unknown.root, L"Demo.xcodeproj/project.pbxproj")); check(unknown, false, false);
    Fixture unknownWorkspace; unknownWorkspace.Add(L"Demo.xcworkspace/contents.xcworkspacedata", "workspace"); unknownWorkspace.unreadable.insert(JobsIDE::Join(unknownWorkspace.root, L"Demo.xcworkspace/contents.xcworkspacedata")); check(unknownWorkspace, false, false);
    Fixture linked; linked.Add(L"README.md", "notes"); linked.items[linked.root].first = 2; check(linked, false, false);
    assert(!JobsIDE::Eligible(plain.Files(), plain.root + L"\\README.md", JobsIDE::Kind::VSCode)); ++count;
    Fixture bundle; bundle.Add(L"Tool.app/Contents", "", true);
    assert(!JobsIDE::Eligible(bundle.Files(), bundle.root + L"\\Tool.app", JobsIDE::Kind::VSCode)); ++count;
    std::cout << "PASS: IDEProjectMenuProbe (" << count << " assertions)\n";
}

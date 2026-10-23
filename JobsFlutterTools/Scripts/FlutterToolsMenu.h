#pragma once
namespace JobsFlutterTools {
struct Entry { const wchar_t* action; const wchar_t* label; };
static const Entry Entries[] = {
    {L"run", L"运行Flutter项目"},
    {L"pub-get", L"拉取Flutter第三方依赖"},
    {L"extract", L"提取Flutter第三方依赖"},
    {L"sdk-version", L"查看当前Flutter项目的SDK版本"},
    {L"sdk-manage", L"安装/切换Flutter SDK版本"},
    {L"ohos-sdk-manage", L"安装/切换 Flutter@OpenHarmony SDK"},
    {L"package", L"Flutter打包"},
    {L"codegen", L"Flutter自动化生产代码"},
    {L"native-doctor", L"原生Flutter项目体检"},
    {L"harmony-doctor", L"鸿蒙Flutter环境体检"},
    {L"maintenance", L"Flutter清理维护工具"},
    {L"repair-android", L"修复 Android SDK / platforms 缺失"},
    {L"repair-imports", L"修复 Flutter 项目中文路径"},
    {L"repair-namespace", L"修复 Flutter 插件 namespace"},
};
static const unsigned Count = sizeof(Entries) / sizeof(Entries[0]);
}

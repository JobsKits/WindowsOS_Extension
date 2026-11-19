// VisibilityRuntime.h | JobsFileVisibility
// Created by Jobs on 2026年11月18日，星期三.
#pragma once
#include <regex>
#include "FileVisibilityText.h"

namespace JobsFileVisibility {
// Cached COM instances must stop acting after uninstall or another release takes ownership.
inline bool IsActiveRegistration(HMODULE module) {
    std::vector<wchar_t> current(32768), registered(32768);
    const DWORD length = GetModuleFileNameW(module, current.data(), static_cast<DWORD>(current.size()));
    if (!length || length >= current.size()) return false;
    DWORD size = static_cast<DWORD>(registered.size() * sizeof(wchar_t));
    const LSTATUS result = RegGetValueW(HKEY_CURRENT_USER,
        L"Software\\Classes\\CLSID\\{F667A0A8-C7A6-4C79-A420-12DA30EBF981}\\InprocServer32",
        nullptr, RRF_RT_REG_SZ, nullptr, registered.data(), &size);
    return result == ERROR_SUCCESS && _wcsicmp(current.data(), registered.data()) == 0;
}
// Read only the small current-user preference file, never arbitrary registry or environment data.
inline std::wstring PreferredLanguage() {
    std::wstring language;
    PWSTR local = nullptr;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, KF_FLAG_DONT_VERIFY, nullptr, &local))) {
        const std::wstring path = std::wstring(local) + L"\\Jobs\\WindowsExtension\\panel-preferences.json";
        CoTaskMemFree(local);
        Handle file(path, false, GENERIC_READ);
        if (file != INVALID_HANDLE_VALUE) {
            LARGE_INTEGER size = {};
            if (GetFileSizeEx(file, &size) && size.QuadPart > 0 && size.QuadPart < 16384) {
                std::vector<char> data(static_cast<size_t>(size.QuadPart));
                DWORD read = 0;
                if (ReadFile(file, data.data(), static_cast<DWORD>(data.size()), &read, nullptr) && read == data.size()) {
                    const int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, data.data(), read, nullptr, 0);
                    if (count > 0) {
                        std::wstring json(count, L'\0');
                        MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, data.data(), read, &json[0], count);
                        std::wsmatch match;
                        const std::wregex field(L"\"Language\"\\s*:\\s*\"([A-Za-z-]+)\"");
                        if (std::regex_search(json, match, field)) language = match[1];
                    }
                }
            }
        }
    }
    if (language.empty() || language == L"system") {
        wchar_t locale[LOCALE_NAME_MAX_LENGTH] = {};
        if (LCIDToLocaleName(MAKELCID(GetUserDefaultUILanguage(), SORT_DEFAULT), locale, LOCALE_NAME_MAX_LENGTH, 0)) language = locale;
    }
    return language;
}
}

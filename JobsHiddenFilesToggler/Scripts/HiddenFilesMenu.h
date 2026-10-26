// HiddenFilesMenu.h | JobsHiddenFilesToggler
// Created by Jobs on 2026年10月26日，星期一.
#pragma once
namespace JobsHiddenFiles {
enum class State { Unknown, Hidden, Visible };
inline State FromPreference(bool readable, bool exists, unsigned long value) {
    if (!readable) return State::Unknown;
    if (!exists || value == 2) return State::Hidden;
    return value == 1 ? State::Visible : State::Unknown;
}
inline const wchar_t* ActionTitle(State state) {
    if (state == State::Hidden) return L"👁️ 显示文件";
    if (state == State::Visible) return L"🙈 隐藏文件";
    return L"⚠️ 隐藏文件状态不可用";
}
#ifdef _WIN32
inline State ReadState() {
    DWORD value = 0;
    DWORD size = sizeof(value);
    const LSTATUS result = RegGetValueW(HKEY_CURRENT_USER,
        L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced", L"Hidden",
        RRF_RT_REG_DWORD, nullptr, &value, &size);
    return FromPreference(result == ERROR_SUCCESS || result == ERROR_FILE_NOT_FOUND,
        result != ERROR_FILE_NOT_FOUND, value);
}
#endif
}

// DeleteDialog.h | JobsPermanentDeleter
// Created by Jobs on 2026年11月18日，星期三.
#pragma once
#include <regex>
#include "DeleteText.h"
namespace JobsPermanentDeleter {
// A cached Explorer instance must stop acting after uninstall or release replacement.
inline bool IsActiveRegistration(HMODULE module) {
    std::vector<wchar_t> current(32768), registered(32768);
    DWORD length = GetModuleFileNameW(module, current.data(), static_cast<DWORD>(current.size()));
    if (!length || length >= current.size()) return false;
    DWORD bytes = static_cast<DWORD>(registered.size() * sizeof(wchar_t));
    LSTATUS result = RegGetValueW(HKEY_CURRENT_USER,
        L"Software\\Classes\\CLSID\\{79022A9C-59CF-485A-90D8-67C67EE7CE33}\\InprocServer32",
        nullptr, RRF_RT_REG_SZ, nullptr, registered.data(), &bytes);
    return result == ERROR_SUCCESS && _wcsicmp(current.data(), registered.data()) == 0;
}
// Read only the panel's bounded preference file; dialog changes remain session-local.
inline std::wstring Preference(const wchar_t* key) {
    std::wstring result;
    PWSTR local = nullptr;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, KF_FLAG_DONT_VERIFY, nullptr, &local))) {
        std::wstring path = std::wstring(local) + L"\\Jobs\\WindowsExtension\\panel-preferences.json";
        CoTaskMemFree(local);
        Handle file;
        file.value = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
            nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
        LARGE_INTEGER size = {};
        if (file.value != INVALID_HANDLE_VALUE && GetFileSizeEx(file.value, &size) && size.QuadPart > 0 && size.QuadPart < 16384) {
            std::vector<char> data(static_cast<size_t>(size.QuadPart));
            DWORD read = 0;
            if (ReadFile(file.value, data.data(), static_cast<DWORD>(data.size()), &read, nullptr) && read == data.size()) {
                int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, data.data(), read, nullptr, 0);
                if (count > 0) {
                    std::wstring json(count, L'\0');
                    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, data.data(), read, &json[0], count);
                    std::wsmatch match;
                    std::wregex expression(std::wstring(L"\"") + key + L"\"\\s*:\\s*\"([A-Za-z-]+)\"");
                    if (std::regex_search(json, match, expression)) result = match[1];
                }
            }
        }
    }
    return result;
}
// Follow the actual Windows display language when no explicit language was chosen.
inline std::wstring PreferredLanguage() {
    std::wstring result = Preference(L"Language");
    if (result.empty() || result == L"system") {
        wchar_t locale[LOCALE_NAME_MAX_LENGTH] = {};
        if (LCIDToLocaleName(MAKELCID(GetUserDefaultUILanguage(), SORT_DEFAULT), locale, LOCALE_NAME_MAX_LENGTH, 0)) result = locale;
    }
    return TextFor(result).code;
}
enum { ConfirmButton = 1001, LanguageChoice = 1002, ThemeChoice = 1003, WarningLabel = 1004,
    CountLabel = 1005, LanguageLabel = 1006, ThemeLabel = 1007, PathsView = 1008 };
struct DialogState {
    std::wstring language = PreferredLanguage();
    int theme = 0;
    bool confirmation = true, dark = false;
    size_t count = 0;
    size_t deleted = 0;
    DWORD error = ERROR_SUCCESS;
    std::wstring details;
    HBRUSH background = nullptr;
    HFONT font = nullptr;
};
// Use app-mode settings only for the System appearance choice.
inline bool DarkSystem() {
    DWORD light = 1, bytes = sizeof(light);
    RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
        L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &light, &bytes);
    return light == 0;
}
// Apply strings and both surfaces together without changing the delete plan or default action.
inline void PresentDialog(HWND window, DialogState& state) {
    const auto& text = TextFor(state.language);
    state.dark = state.theme == 2 || (state.theme == 0 && DarkSystem());
    if (state.background) DeleteObject(state.background);
    state.background = CreateSolidBrush(state.dark ? RGB(28,28,30) : RGB(255,255,255));
    SetWindowTextW(window, text.title);
    SetDlgItemTextW(window, ConfirmButton, text.confirm);
    SetDlgItemTextW(window, IDCANCEL, state.confirmation ? text.cancel : text.close);
    SetDlgItemTextW(window, WarningLabel, state.confirmation ? text.warning : text.title);
    SetDlgItemTextW(window, LanguageLabel, text.language);
    SetDlgItemTextW(window, ThemeLabel, text.theme);
    std::wstring count = state.confirmation ? std::wstring(text.count) + std::to_wstring(state.count) : L"";
    SetDlgItemTextW(window, CountLabel, count.c_str());
    if (!state.confirmation) {
        std::wstring message = std::wstring(text.failure) + std::to_wstring(state.error) + L"\r\n\r\n";
        if (state.deleted) message += std::wstring(text.partial) + std::to_wstring(state.deleted) + L"\r\n\r\n";
        message += state.details;
        SetDlgItemTextW(window,PathsView,message.c_str());
    }
    HWND choice = GetDlgItem(window, ThemeChoice);
    SendMessageW(choice, CB_RESETCONTENT, 0, 0);
    for (const auto* label : {text.system, text.light, text.dark}) SendMessageW(choice, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(label));
    SendMessageW(choice, CB_SETCURSEL, state.theme, 0);
    InvalidateRect(window, nullptr, TRUE);
}
// Create controls in DPI-scaled pixels; the dialog owns its font and background brush.
inline HWND AddControl(HWND parent, DialogState& state, const wchar_t* type, DWORD style, int id,
                       int x, int y, int width, int height) {
    HDC dc = GetDC(parent);
    int dpi = GetDeviceCaps(dc, LOGPIXELSX);
    ReleaseDC(parent, dc);
    HWND control = CreateWindowExW(type == std::wstring(L"EDIT") ? WS_EX_CLIENTEDGE : 0, type, L"",
        WS_CHILD | WS_VISIBLE | style, MulDiv(x,dpi,96), MulDiv(y,dpi,96), MulDiv(width,dpi,96), MulDiv(height,dpi,96),
        parent, reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), GetModuleHandleW(nullptr), nullptr);
    SendMessageW(control, WM_SETFONT, reinterpret_cast<WPARAM>(state.font), TRUE);
    return control;
}
// A single explicit button event authorizes deletion; Return defaults to Cancel.
inline INT_PTR CALLBACK DeleteDialogProcedure(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    auto* state = reinterpret_cast<DialogState*>(GetWindowLongPtrW(window, DWLP_USER));
    if (message == WM_INITDIALOG) {
        state = reinterpret_cast<DialogState*>(lparam);
        SetWindowLongPtrW(window, DWLP_USER, reinterpret_cast<LONG_PTR>(state));
        HDC dc = GetDC(window);
        int dpi = GetDeviceCaps(dc, LOGPIXELSX);
        ReleaseDC(window, dc);
        state->font = CreateFontW(-MulDiv(12,dpi,72),0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,
            OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,CLEARTYPE_QUALITY,DEFAULT_PITCH,L"Segoe UI");
        RECT area = {0,0,MulDiv(760,dpi,96),MulDiv(580,dpi,96)};
        AdjustWindowRectEx(&area, GetWindowLongW(window,GWL_STYLE), FALSE, GetWindowLongW(window,GWL_EXSTYLE));
        RECT work = {}; SystemParametersInfoW(SPI_GETWORKAREA,0,&work,0);
        int width = area.right-area.left, height = area.bottom-area.top;
        SetWindowPos(window,nullptr,work.left+(work.right-work.left-width)/2,work.top+(work.bottom-work.top-height)/2,width,height,SWP_NOZORDER);
        AddControl(window,*state,L"STATIC",SS_LEFT,LanguageLabel,24,22,110,28);
        HWND language = AddControl(window,*state,L"COMBOBOX",WS_TABSTOP|CBS_DROPDOWNLIST|WS_VSCROLL,LanguageChoice,138,18,220,300);
        const wchar_t* codes[] = {L"zh-Hans",L"zh-Hant",L"bo",L"en",L"ja",L"fr",L"es",L"de",L"ru",L"ko"};
        for (int i=0;i<10;++i) {
            const auto& text = TextFor(codes[i]);
            SendMessageW(language,CB_ADDSTRING,0,reinterpret_cast<LPARAM>(text.name));
            if (state->language == codes[i]) SendMessageW(language,CB_SETCURSEL,i,0);
        }
        AddControl(window,*state,L"STATIC",SS_LEFT,ThemeLabel,386,22,110,28);
        AddControl(window,*state,L"COMBOBOX",WS_TABSTOP|CBS_DROPDOWNLIST|WS_VSCROLL,ThemeChoice,504,18,230,160);
        AddControl(window,*state,L"STATIC",SS_LEFT,WarningLabel,24,66,710,116);
        AddControl(window,*state,L"STATIC",SS_LEFT,CountLabel,24,188,710,32);
        HWND paths = AddControl(window,*state,L"EDIT",WS_TABSTOP|WS_VSCROLL|WS_HSCROLL|ES_MULTILINE|ES_READONLY|ES_AUTOVSCROLL|ES_AUTOHSCROLL,PathsView,24,228,710,254);
        SendMessageW(paths,EM_SETLIMITTEXT,4000000,0);
        SetWindowTextW(paths,state->details.c_str());
        HWND confirm = AddControl(window,*state,L"BUTTON",WS_TABSTOP|BS_OWNERDRAW,ConfirmButton,24,514,340,42);
        if (!state->confirmation) ShowWindow(confirm,SW_HIDE);
        AddControl(window,*state,L"BUTTON",WS_TABSTOP|BS_OWNERDRAW,IDCANCEL,394,514,340,42);
        PresentDialog(window,*state);
        SendMessageW(window,DM_SETDEFID,IDCANCEL,0);
        SetFocus(GetDlgItem(window,IDCANCEL));
        return FALSE;
    }
    if (!state) return FALSE;
    if (message == WM_COMMAND) {
        int id = LOWORD(wparam);
        if (id == IDCANCEL || id == IDOK) { EndDialog(window,IDCANCEL); return TRUE; }
        if (id == ConfirmButton && HIWORD(wparam) == BN_CLICKED && state->confirmation) { EndDialog(window,ConfirmButton); return TRUE; }
        if (id == LanguageChoice && HIWORD(wparam) == CBN_SELCHANGE) {
            const wchar_t* codes[] = {L"zh-Hans",L"zh-Hant",L"bo",L"en",L"ja",L"fr",L"es",L"de",L"ru",L"ko"};
            LRESULT selected = SendDlgItemMessageW(window,LanguageChoice,CB_GETCURSEL,0,0);
            if (selected >= 0 && selected < 10) state->language = codes[selected];
            PresentDialog(window,*state); return TRUE;
        }
        if (id == ThemeChoice && HIWORD(wparam) == CBN_SELCHANGE) {
            LRESULT selected = SendDlgItemMessageW(window,ThemeChoice,CB_GETCURSEL,0,0);
            if (selected >= 0 && selected <= 2) state->theme = static_cast<int>(selected);
            PresentDialog(window,*state); return TRUE;
        }
    }
    if (message == WM_SETTINGCHANGE) { PresentDialog(window,*state); return TRUE; }
    if (message == WM_CLOSE) { EndDialog(window,IDCANCEL); return TRUE; }
    if (message == WM_DRAWITEM) {
        auto* item = reinterpret_cast<DRAWITEMSTRUCT*>(lparam);
        COLORREF color = item->CtlID == ConfirmButton ? RGB(180,35,24) : RGB(0,87,184);
        HBRUSH brush = CreateSolidBrush(color);
        FillRect(item->hDC,&item->rcItem,brush); DeleteObject(brush);
        HGDIOBJ previousFont = SelectObject(item->hDC,state->font);
        SetTextColor(item->hDC,RGB(255,255,255)); SetBkMode(item->hDC,TRANSPARENT);
        wchar_t label[128] = {}; GetWindowTextW(item->hwndItem,label,128);
        DrawTextW(item->hDC,label,-1,&item->rcItem,DT_CENTER|DT_VCENTER|DT_SINGLELINE);
        SelectObject(item->hDC,previousFont);
        if (item->itemState & ODS_FOCUS) { RECT focus=item->rcItem; InflateRect(&focus,-4,-4); DrawFocusRect(item->hDC,&focus); }
        return TRUE;
    }
    if (message == WM_CTLCOLORDLG || message == WM_CTLCOLORSTATIC || message == WM_CTLCOLOREDIT || message == WM_CTLCOLORLISTBOX) {
        HDC dc = reinterpret_cast<HDC>(wparam);
        SetTextColor(dc,state->dark ? RGB(245,245,247) : RGB(25,25,28));
        SetBkColor(dc,state->dark ? RGB(28,28,30) : RGB(255,255,255));
        return reinterpret_cast<INT_PTR>(state->background);
    }
    return FALSE;
}
// Return true only when the red left button receives the explicit confirmation action.
inline bool ShowDeleteDialog(HMODULE module, HWND owner, DialogState& state) {
    std::wstring theme = Preference(L"Theme");
    state.theme = theme == L"dark" ? 2 : theme == L"light" ? 1 : 0;
    struct Template { DLGTEMPLATE dialog; WORD menu,windowClass,title; } layout = {};
    layout.dialog.style = WS_POPUP|WS_CAPTION|WS_SYSMENU|DS_MODALFRAME;
    layout.dialog.dwExtendedStyle = WS_EX_DLGMODALFRAME;
    layout.dialog.cx=480; layout.dialog.cy=360;
    INT_PTR result = DialogBoxIndirectParamW(module,&layout.dialog,owner,DeleteDialogProcedure,reinterpret_cast<LPARAM>(&state));
    if (state.background) { DeleteObject(state.background); state.background = nullptr; }
    if (state.font) { DeleteObject(state.font); state.font = nullptr; }
    return result == ConfirmButton;
}
}

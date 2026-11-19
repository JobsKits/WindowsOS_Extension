// FileVisibilityText.h | JobsFileVisibility
// Created by Jobs on 2026年11月18日，星期三.
#pragma once
#include <string>
namespace JobsFileVisibility {
struct Text {
    const wchar_t* code;
    const wchar_t* hide;
    const wchar_t* show;
    const wchar_t* title;
    const wchar_t* summary;
    const wchar_t* retry;
    const wchar_t* error;
};
// The same ten language choices as the management panel; unknown system locales use English.
inline const Text& TextFor(const std::wstring& code) {
    static const Text rows[] = {
        {L"zh-Hans", L"🙈 隐藏所选项目", L"👁️ 显示所选项目", L"Jobs · 所选项目隐藏属性", L"未完成 {0} / {1} 项；成功项保留当前状态。", L"请核对权限或目标是否已被替换，再重新打开菜单。", L"Win32 错误码："},
        {L"zh-Hant", L"🙈 隱藏所選項目", L"👁️ 顯示所選項目", L"Jobs · 所選項目隱藏屬性", L"未完成 {0} / {1} 項；成功項保留目前狀態。", L"請核對權限或目標是否已被替換，再重新開啟選單。", L"Win32 錯誤碼："},
        {L"bo", L"🙈 བདམས་པའི་རྣམ་གྲངས་སྦེད།", L"👁️ བདམས་པའི་རྣམ་གྲངས་སྟོན།", L"Jobs · སྦས་པའི་ཁྱད་ཆོས།", L"{1} ལས་ {0} མ་གྲུབ། གྲུབ་པའི་གནས་སྟངས་སོར་འཇོག", L"ཆོག་མཆན་དང་དམིགས་ཡུལ་བརྗེས་ཡོད་མེད་ཞིབ་བཤེར་བྱས་ནས་འདེམས་ཐོ་བསྐྱར་དུ་ཕྱེ།", L"Win32 ནོར་འཁྲུལ་ཨང་། "},
        {L"en", L"🙈 Hide selected items", L"👁️ Show selected items", L"Jobs · Selected item visibility", L"{0} / {1} items failed; successful items keep their current state.", L"Check permissions or whether the target was replaced, then reopen the menu.", L"Win32 error: "},
        {L"ja", L"🙈 選択した項目を非表示", L"👁️ 選択した項目を表示", L"Jobs · 選択項目の隠し属性", L"{1} 項目中 {0} 項目に失敗しました。成功した項目の状態は保持されます。", L"アクセス権や対象の置き換えを確認し、メニューを開き直してください。", L"Win32 エラー："},
        {L"fr", L"🙈 Masquer la sélection", L"👁️ Afficher la sélection", L"Jobs · Visibilité de la sélection", L"{0} / {1} éléments ont échoué ; les autres conservent leur état actuel.", L"Vérifiez les autorisations ou le remplacement des cibles, puis rouvrez le menu.", L"Erreur Win32 : "},
        {L"es", L"🙈 Ocultar selección", L"👁️ Mostrar selección", L"Jobs · Visibilidad de selección", L"Fallaron {0} / {1} elementos; los correctos conservan su estado actual.", L"Compruebe los permisos o si cambió el destino y vuelva a abrir el menú.", L"Error Win32: "},
        {L"de", L"🙈 Auswahl ausblenden", L"👁️ Auswahl einblenden", L"Jobs · Sichtbarkeit der Auswahl", L"{0} / {1} Elemente fehlgeschlagen; erfolgreiche Elemente behalten ihren aktuellen Zustand.", L"Prüfen Sie Berechtigungen und ersetzte Ziele und öffnen Sie das Menü erneut.", L"Win32-Fehler: "},
        {L"ru", L"🙈 Скрыть выбранное", L"👁️ Показать выбранное", L"Jobs · Видимость выбранного", L"Ошибка для {0} из {1} элементов; успешные изменения сохранены.", L"Проверьте разрешения и замену объектов, затем откройте меню снова.", L"Ошибка Win32: "},
        {L"ko", L"🙈 선택 항목 숨기기", L"👁️ 선택 항목 표시", L"Jobs · 선택 항목 숨김 속성", L"{1}개 중 {0}개 실패. 성공한 항목의 현재 상태는 유지됩니다.", L"권한이나 대상 교체 여부를 확인한 다음 메뉴를 다시 여세요.", L"Win32 오류: "}
    };
    for (const auto& row : rows) if (code == row.code) return row;
    if (code.find(L"zh") == 0) {
        if (code.find(L"Hant") != std::wstring::npos || code.find(L"TW") != std::wstring::npos || code.find(L"HK") != std::wstring::npos || code.find(L"MO") != std::wstring::npos) return rows[1];
        return rows[0];
    }
    for (const auto& row : rows) if (code.find(std::wstring(row.code) + L"-") == 0) return row;
    return rows[3];
}
// Counts replace fixed placeholders; selected paths remain literal diagnostic data.
inline std::wstring Summary(const Text& text, size_t failed, size_t total) {
    std::wstring result(text.summary);
    result.replace(result.find(L"{0}"), 3, std::to_wstring(failed));
    result.replace(result.find(L"{1}"), 3, std::to_wstring(total));
    return result;
}
}

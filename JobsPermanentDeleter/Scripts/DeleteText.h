// DeleteText.h | JobsPermanentDeleter
// Created by Jobs on 2026年11月18日，星期三.
#pragma once
#include <string>
namespace JobsPermanentDeleter {
struct Text {
    const wchar_t *code, *name, *menu, *title, *warning, *confirm, *cancel, *close,
        *language, *theme, *system, *light, *dark, *count, *failure, *partial;
};
// Every visible action and warning has the same ten language choices as the management panel.
inline const Text& TextFor(const std::wstring& language) {
    static const Text rows[] = {
        {L"zh-Hans",L"简体中文",L"永久删除（不进回收站）",L"Jobs · 永久删除",L"这些项目及文件夹内的内容将直接删除，不进入回收站，无法通过回收站恢复。确认继续？",L"确认",L"取消",L"关闭",L"语言",L"主题",L"跟随系统",L"白天",L"黑夜",L"待删除项目（含子项）：",L"无法安全删除。请核对权限、只读属性、链接、目标是否被替换或项目数量限制，再重新打开菜单。错误码：",L"已删除的项目无法撤销；未删除项目保留。已删除项目："},
        {L"zh-Hant",L"繁體中文",L"永久刪除（不進資源回收筒）",L"Jobs · 永久刪除",L"這些項目及資料夾內的內容將直接刪除，不進入資源回收筒，無法透過資源回收筒復原。確認繼續？",L"確認",L"取消",L"關閉",L"語言",L"主題",L"跟隨系統",L"白天",L"黑夜",L"待刪除項目（含子項）：",L"無法安全刪除。請核對權限、唯讀屬性、連結、目標是否被替換或項目數量限制，再重新開啟選單。錯誤碼：",L"已刪除的項目無法復原；未刪除項目保留。已刪除項目："},
        {L"bo",L"བོད་ཡིག",L"རྒྱུན་གཏན་དུ་སུབ་པ།",L"Jobs · རྒྱུན་གཏན་དུ་སུབ་པ།",L"བདམས་པའི་ཡིག་ཆ་དང་ཡིག་སྣོད་ནང་གི་དོན་ཆ་ཐད་ཀར་སུབ་རྒྱུ་ཡིན། གད་སྙིགས་སྒམ་དུ་མི་འཇོག་པས་དེ་ནས་སླར་གསོ་མི་ཐུབ། མུ་མཐུད་དམ།",L"གཏན་འཁེལ།",L"དོར་བ།",L"ཁ་རྒྱག",L"སྐད་ཡིག",L"བརྗོད་གཞི།",L"མ་ལག་རྗེས་འབྲང་།",L"ཉིན་མོ།",L"མཚན་མོ།",L"སུབ་རྒྱུའི་གྲངས།",L"བདེ་འཇགས་ངང་སུབ་མ་ཐུབ། ཆོག་མཆན་དང་འབྲེལ་མཐུད་དམ་དམིགས་ཡུལ་བརྗེས་ཡོད་མེད་ཞིབ་བཤེར་བྱས་ནས་སླར་འདེམས་ཐོ་ཁ་ཕྱེ། ནོར་ཨང་།",L"སུབ་ཟིན་པ་སླར་གསོ་མི་ཐུབ། མ་སུབ་པ་སོར་འཇོག སུབ་ཟིན་གྲངས།"},
        {L"en",L"English",L"Permanently delete (skip Recycle Bin)",L"Jobs · Permanent delete",L"These items and all folder contents will be deleted directly, without the Recycle Bin. They cannot be restored from the Recycle Bin. Continue?",L"Confirm",L"Cancel",L"Close",L"Language",L"Theme",L"System",L"Light",L"Dark",L"Items to delete (including children): ",L"Cannot delete safely. Check permissions, read-only attributes, links, replaced targets or item limits, then reopen the menu. Error: ",L"Deleted items cannot be undone; remaining items are kept. Deleted items: "},
        {L"ja",L"日本語",L"完全に削除（ごみ箱を使わない）",L"Jobs · 完全に削除",L"選択項目とフォルダー内の内容を、ごみ箱を経由せず直接削除します。ごみ箱から復元できません。続行しますか？",L"確認",L"キャンセル",L"閉じる",L"言語",L"テーマ",L"システム",L"ライト",L"ダーク",L"削除する項目数（子項目を含む）：",L"安全に削除できません。権限、読み取り専用属性、リンク、対象の置換や項目数制限を確認し、メニューを開き直してください。エラー：",L"削除済み項目は元に戻せません。未削除項目は保持されます。削除済み："},
        {L"fr",L"Français",L"Supprimer définitivement (sans Corbeille)",L"Jobs · Suppression définitive",L"Ces éléments et le contenu des dossiers seront supprimés directement, sans passer par la Corbeille. Ils ne pourront pas être restaurés depuis la Corbeille. Continuer ?",L"Confirmer",L"Annuler",L"Fermer",L"Langue",L"Thème",L"Système",L"Clair",L"Sombre",L"Éléments à supprimer (contenu compris) : ",L"Suppression sûre impossible. Vérifiez les droits, la lecture seule, les liens, les cibles remplacées et la limite d’éléments, puis rouvrez le menu. Erreur : ",L"Les éléments supprimés ne peuvent pas être récupérés ; les autres sont conservés. Éléments supprimés : "},
        {L"es",L"Español",L"Eliminar permanentemente (sin Papelera)",L"Jobs · Eliminación permanente",L"Estos elementos y el contenido de las carpetas se eliminarán directamente, sin pasar por la Papelera. No se podrán restaurar desde ella. ¿Continuar?",L"Confirmar",L"Cancelar",L"Cerrar",L"Idioma",L"Tema",L"Sistema",L"Claro",L"Oscuro",L"Elementos a eliminar (incluido el contenido): ",L"No se puede eliminar con seguridad. Revise permisos, solo lectura, enlaces, destinos sustituidos y límites; vuelva a abrir el menú. Error: ",L"No se pueden deshacer las eliminaciones; los demás elementos se conservan. Elementos eliminados: "},
        {L"de",L"Deutsch",L"Endgültig löschen (ohne Papierkorb)",L"Jobs · Endgültig löschen",L"Diese Elemente und alle Ordnerinhalte werden direkt und ohne Papierkorb gelöscht. Eine Wiederherstellung aus dem Papierkorb ist nicht möglich. Fortfahren?",L"Bestätigen",L"Abbrechen",L"Schließen",L"Sprache",L"Design",L"System",L"Hell",L"Dunkel",L"Zu löschende Elemente (mit Inhalt): ",L"Sicheres Löschen nicht möglich. Prüfen Sie Rechte, Schreibschutz, Verknüpfungen, ausgetauschte Ziele und das Elementlimit. Öffnen Sie das Menü erneut. Fehler: ",L"Gelöschte Elemente können nicht zurückgeholt werden; übrige bleiben erhalten. Gelöschte Elemente: "},
        {L"ru",L"Русский",L"Удалить навсегда (минуя корзину)",L"Jobs · Удаление навсегда",L"Эти объекты и содержимое папок будут удалены напрямую, минуя корзину. Восстановить их из корзины будет невозможно. Продолжить?",L"Подтвердить",L"Отмена",L"Закрыть",L"Язык",L"Тема",L"Системная",L"Светлая",L"Тёмная",L"Объекты для удаления (включая содержимое): ",L"Безопасное удаление невозможно. Проверьте права, атрибут «только чтение», ссылки, замену целей и лимит объектов; откройте меню снова. Ошибка: ",L"Удаление нельзя отменить; остальные объекты сохранены. Удалено объектов: "},
        {L"ko",L"한국어",L"영구 삭제 (휴지통 건너뛰기)",L"Jobs · 영구 삭제",L"선택한 항목과 폴더 내용이 휴지통을 거치지 않고 직접 삭제됩니다. 휴지통에서 복원할 수 없습니다. 계속하시겠습니까?",L"확인",L"취소",L"닫기",L"언어",L"테마",L"시스템",L"라이트",L"다크",L"삭제할 항목 수 (하위 항목 포함): ",L"안전하게 삭제할 수 없습니다. 권한, 읽기 전용 속성, 링크, 대상 교체 또는 항목 수 제한을 확인한 후 메뉴를 다시 여세요. 오류: ",L"삭제는 취소할 수 없으며 나머지 항목은 보존됩니다. 삭제한 항목: "}
    };
    std::wstring code = language;
    if (code == L"zh-TW" || code == L"zh-HK" || code == L"zh-MO") code = L"zh-Hant";
    if (code == L"zh-CN" || code == L"zh-SG") code = L"zh-Hans";
    for (const auto& row : rows) if (code == row.code) return row;
    size_t separator = code.find(L'-');
    if (separator != std::wstring::npos) return TextFor(code.substr(0, separator));
    return rows[3];
}
}

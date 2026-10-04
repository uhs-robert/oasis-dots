// home/quickshell/.config/quickshell/components/popup/PopupKeys.qml
import QtQuick
import "../../services"

QtObject {
    id: root

    required property var popup
    property double last_g_ms: 0

    // Runs after the popup's own handlers: keys reach it only when nothing deeper accepted them.
    function handle(event, focus_item) {
        if (focus_item && "cursorPosition" in focus_item) return;
        const back = event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier);
        const before = root.popup.cursor_key();
        if (root.popup.key_help !== "" && root.popup.is_help_key(event)) {
            root.popup.help_open = true;
        } else if (root.popup.search_enabled && (event.key === Qt.Key_Slash || event.text === "/")) {
            if (root.popup.search_starts_open) root.popup.enter_search(); else root.popup.open_search();
        } else if (root.popup.search_starts_open && event.key === Qt.Key_I) {
            root.popup.enter_search();
        } else if (root.popup.search_enabled && root.popup.search_query !== "" && event.key === Qt.Key_N) {
            root.popup.step_search(back ? -1 : 1);
            root.popup.play_if_moved(before);
        } else if (event.key === Qt.Key_Backspace && Popups.back_name !== "") {
            ThemeAudio.play("cancel");
            Popups.back();
        } else if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_H || event.key === Qt.Key_L)) {
            Popups.walk(event.key === Qt.Key_L ? 1 : -1);
        } else if (event.key === Qt.Key_Q) {
            ThemeAudio.play("cancel");
            Popups.close();
        } else if (event.key === Qt.Key_BracketLeft || event.key === Qt.Key_BracketRight) {
            const step = event.key === Qt.Key_BracketLeft ? -1 : 1;
            if (root.popup.sub_views.length > 0) root.popup.step_sub(step); else root.popup.step_tab(step);
            root.popup.play_if_moved(before);
        } else if (event.key >= Qt.Key_1 && event.key < Qt.Key_1 + Math.min(9, root.popup.tabs.length)) {
            root.popup.set_tab(event.key - Qt.Key_1);
            root.popup.play_if_moved(before);
        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            if (root.popup.tabs.length > 0) root.popup.step_tab(back ? -1 : 1); else root.popup.step_sub(back ? -1 : 1);
            root.popup.play_if_moved(before);
        } else if (root.popup.line_ends_enabled && (event.key === Qt.Key_0 || event.text === "$")) {
            if (event.key === Qt.Key_0) root.popup.line_start(); else root.popup.line_end();
            root.popup.play_if_moved(before);
        } else if (root.popup.jumps_enabled && event.key === Qt.Key_G) {
            if (event.modifiers & Qt.ShiftModifier) {
                root.popup.jump_last();
                root.popup.play_if_moved(before);
            } else {
                const now_ms = Date.now();
                if (now_ms - root.last_g_ms < 500) {
                    root.last_g_ms = 0;
                    root.popup.jump_first();
                    root.popup.play_if_moved(before);
                } else {
                    root.last_g_ms = now_ms;
                }
            }
        } else {
            return;
        }
        event.accepted = true;
    }
}

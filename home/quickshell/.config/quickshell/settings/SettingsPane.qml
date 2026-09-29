// home/quickshell/.config/quickshell/settings/SettingsPane.qml
import QtQuick
import "../theme"

// Base of a settings section; the popup loads one and hands itself in as `popup`.
FocusScope {
    id: root

    property var popup: null
    readonly property var st: root.popup ? root.popup.st : Style
    property string footer_hint: ""
    property bool picking: false
    readonly property string shown_hint: root.picking ? "type to filter · Up/Down or Ctrl+n/p move · Enter pick · Esc cancel" : root.footer_hint
    property var search_rows: []
    property int search_cursor: -1
    // True while the popup is open with focus in the pane; typing a search keeps it so.
    readonly property bool live: !!root.popup && root.popup.is_open === true && root.popup.in_pane === true

    focus: true

    function search_select(index) {
    }

    // -1 for gg, 1 for G.
    function jump(delta) {
    }

    function wrap_index(i, delta, count) {
        return count <= 0 ? 0 : ((i + delta) % count + count) % count;
    }

    function cap(text) {
        return text.charAt(0).toUpperCase() + text.slice(1);
    }

    function focus_pane() {
        if (root.popup) root.popup.enter_pane();
    }
}

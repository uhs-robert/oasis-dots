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
    property var pick_list: null
    property var pick_done: null
    readonly property string shown_hint: root.picking ? (root.pick_list && !root.pick_list.insert ? "Enter pick · j/k move · gg/G first/last · i insert · Esc close" : "Enter pick · Up/Down or Ctrl+n/p move · Esc normal") : root.footer_hint
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

    // Opens `list` (a PickerList) over `labels`, with an image url per label when `thumbs` is given; on_pick gets the chosen index.
    function show_picker(list, title, labels, current, on_pick, thumbs) {
        list.title = title;
        list.items = labels.map((l, i) => ({ label: l, thumb: thumbs ? thumbs[i] : "" }));
        list.current = current;
        root.pick_list = list;
        root.pick_done = on_pick;
        root.picking = true;
        list.open();
    }

    function hide_picker() {
        if (!root.picking) return;
        root.picking = false;
        root.pick_list = null;
        root.pick_done = null;
        root.forceActiveFocus();
    }

    function finish_picker(index) {
        const done = root.pick_done;
        root.hide_picker();
        if (done) done(index);
    }

    onLiveChanged: if (!root.live) root.hide_picker()

    function focus_pane() {
        if (root.popup) root.popup.enter_pane();
    }
}

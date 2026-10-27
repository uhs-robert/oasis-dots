import QtQuick
import QtQuick.Layouts
import qs.ui.menu
import qs.theme
import qs.features.launcher
import "../../core/Fuzzy.js" as Fuzzy

// A fuzzy-filtered list of a row's options; items are { label, thumb? }, picked(index) reports the position in items.
// An item's thumb is an image url shown beside its label; a list with thumbs shows fewer, taller rows.
// A host that sets available_height gets as many rows as fit it; the list never reports that height back through its own implicit size, so it cannot grow its container.
ColumnLayout {
    id: root

    property var st: Style
    property string title: ""
    property var items: []
    property int current: -1
    property string query: ""
    property int cursor: 0
    property bool insert: true
    property real last_g_ms: 0
    readonly property bool has_thumbs: root.items.length > 0 && !!root.items[0].thumb
    property real available_height: 0
    // Opt-in split view: the rows go into `list_host` (the popup's help column), `list_height` tall, and the list's own
    // place shows a large preview of the highlighted item's thumb above the filter box. Keys stay on the filter box.
    property Item list_host: null
    property real list_height: 0
    readonly property bool split: root.list_host !== null
    readonly property real row_height: Style.px(root.has_thumbs ? 40 : 28)
    // Everything but the rows: title, filter box, the position counter and the gaps between them.
    readonly property real chrome_height: title_text.implicitHeight + Style.px(28) + counter_text.implicitHeight + 4 * root.spacing
    readonly property int default_window: root.has_thumbs ? 6 : 8
    // What a host that does not fill the list should reserve for it.
    readonly property real default_height: root.chrome_height + Math.min(root.default_window, Math.max(1, root.results.length)) * (root.row_height + root.spacing)
    readonly property int window_size: root.split ? Math.max(3, Math.floor((root.list_height - counter_text.implicitHeight - root.spacing) / (root.row_height + root.spacing))) : root.available_height > 0 ? Math.max(3, Math.floor((root.available_height - root.chrome_height) / (root.row_height + root.spacing))) : root.default_window

    readonly property var results: {
        const terms = Fuzzy.terms_of(root.query);
        const out = [];
        for (let i = 0; i < root.items.length; i++) {
            const m = terms.length === 0 ? { score: 0, positions: [] } : Fuzzy.score_item(terms, { label: root.items[i].label });
            if (m) out.push({ index: i, label: root.items[i].label, thumb: root.items[i].thumb || "", score: m.score, positions: m.positions });
        }
        if (terms.length > 0) out.sort((a, b) => b.score - a.score || a.index - b.index);
        return out;
    }
    readonly property int highlighted: root.results[root.cursor] ? root.results[root.cursor].index : -1
    readonly property int first_shown: Math.max(0, Math.min(root.cursor - Math.floor(root.window_size / 2), root.results.length - root.window_size))

    signal picked(int index)
    signal closed

    Layout.fillWidth: true
    spacing: 4

    // Hiding leaves the input focused, and the pane's forceActiveFocus is a no-op while it is.
    onVisibleChanged: if (!root.visible) {
        input.focus = false;
        normal_keys.focus = false;
    }

    function open() {
        const recalled = TypingSettings.recall("settings:" + root.title);
        input.text = recalled;
        root.query = recalled;
        const at = root.results.findIndex(r => r.index === root.current);
        root.cursor = Math.max(0, at);
        root.set_insert(TypingSettings.starts_insert);
    }

    function set_insert(on) {
        root.insert = on;
        if (on) {
            normal_keys.focus = false;
            input.forceActiveFocus();
        } else {
            input.focus = false;
            normal_keys.forceActiveFocus();
        }
    }

    function move(delta) {
        const n = root.results.length;
        if (n > 0) root.cursor = ((root.cursor + delta) % n + n) % n;
    }

    // Ctrl+D/U: half the shown rows, stopping at either end.
    function half_window(delta) {
        const n = root.results.length;
        if (n > 0) root.cursor = Math.max(0, Math.min(n - 1, root.cursor + delta * Math.max(1, Math.floor(root.window_size / 2))));
    }

    function accept() {
        const r = root.results[root.cursor];
        if (r) root.picked(r.index);
    }

    Item {
        id: normal_keys
        Layout.preferredWidth: 0
        Layout.preferredHeight: 0

        Keys.onPressed: event => {
            const ctrl = !!(event.modifiers & Qt.ControlModifier);
            const k = event.key;
            if (ctrl && (k === Qt.Key_D || k === Qt.Key_U)) {
                root.half_window(k === Qt.Key_D ? 1 : -1);
                event.accepted = true;
                return;
            }
            if (ctrl || (event.modifiers & Qt.AltModifier)) return;
            if (k === Qt.Key_Escape || k === Qt.Key_Q) root.closed();
            else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.accept();
            else if (k === Qt.Key_Down || k === Qt.Key_J || k === Qt.Key_Tab) root.move(1);
            else if (k === Qt.Key_Up || k === Qt.Key_K || k === Qt.Key_Backtab) root.move(-1);
            else if (k === Qt.Key_I || event.text === "/") root.set_insert(true);
            else if (k === Qt.Key_A) {
                root.set_insert(true);
                input.cursorPosition = input.text.length;
            } else if (k === Qt.Key_G) {
                if (event.modifiers & Qt.ShiftModifier) {
                    root.cursor = Math.max(0, root.results.length - 1);
                } else {
                    const now_ms = Date.now();
                    if (now_ms - root.last_g_ms < 500) {
                        root.last_g_ms = 0;
                        root.cursor = 0;
                    } else {
                        root.last_g_ms = now_ms;
                    }
                }
            } else return;
            event.accepted = true;
        }
    }

    Text {
        id: title_text
        Layout.fillWidth: true
        text: root.title
        color: root.st.text_accent
        font.family: root.st.font_family
        font.pixelSize: root.st.font_size
    }

    Image {
        visible: root.split
        Layout.fillWidth: true
        Layout.fillHeight: true
        source: root.split && root.results[root.cursor] ? root.results[root.cursor].thumb : ""
        sourceSize: Qt.size(Math.max(1, Math.round(width)), Math.max(1, Math.round(height)))
        fillMode: Image.PreserveAspectFit
        verticalAlignment: Image.AlignTop
        asynchronous: true
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.px(28)
        radius: 6
        color: "transparent"
        border.width: 1
        border.color: root.insert ? root.st.text_accent : Qt.alpha(root.st.text_muted, 0.4)

        TextInput {
            id: input
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.leftMargin: 8
            anchors.right: mode_text.left
            anchors.rightMargin: 8
            verticalAlignment: TextInput.AlignVCenter
            maximumLength: 64
            clip: true
            color: root.st.text_fg
            selectionColor: root.st.selection_bg
            selectedTextColor: root.st.selection_inverse ? root.st.selection_fg : root.st.text_fg
            font.family: root.st.font_family
            font.pixelSize: root.st.font_size
            onTextChanged: {
                root.query = text;
                root.cursor = 0;
                TypingSettings.remember("settings:" + root.title, text);
            }

            Keys.onPressed: event => {
                const ctrl = !!(event.modifiers & Qt.ControlModifier);
                if (event.key === Qt.Key_Escape) root.set_insert(false);
                // Ctrl+U keeps clearing the query while typing, as in the shell; NORMAL has the half-window up.
                else if (ctrl && event.key === Qt.Key_U) input.text = "";
                else if (ctrl && event.key === Qt.Key_D) root.half_window(1);
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.accept();
                else if (event.key === Qt.Key_Down || (ctrl && (event.key === Qt.Key_N || event.key === Qt.Key_J))) root.move(1);
                else if (event.key === Qt.Key_Up || (ctrl && (event.key === Qt.Key_P || event.key === Qt.Key_K))) root.move(-1);
                else if (event.key === Qt.Key_Tab) root.move(1);
                else if (event.key === Qt.Key_Backtab) root.move(-1);
                else return;
                event.accepted = true;
            }
        }

        Text {
            id: mode_text
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: root.insert ? "INSERT" : "NORMAL"
            color: root.insert ? root.st.text_accent : root.st.text_primary
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-4)
            font.bold: true
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: root.set_insert(true)
        }

        Text {
            visible: input.text === ""
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: "type to filter"
            color: root.st.text_dim
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-2)
        }
    }

    ColumnLayout {
        id: list_col
        parent: root.split ? root.list_host : root
        // Out in the host it no longer inherits the list's visibility.
        visible: root.visible
        width: root.split && root.list_host ? root.list_host.width : root.width
        Layout.fillWidth: true
        spacing: root.spacing

        Repeater {
            model: root.results.slice(root.first_shown, root.first_shown + root.window_size)

            MenuRow {
                id: entry
                required property int index
                required property var modelData
                readonly property int at: root.first_shown + entry.index

                Layout.fillWidth: true
                Layout.preferredHeight: root.row_height
                base_radius: 6
                selected: entry.at === root.cursor

                RowLayout {
                    anchors.left: parent.left
                    anchors.leftMargin: 8 + entry.inset
                    anchors.right: parent.right
                    anchors.rightMargin: 8 + entry.key_space
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Text {
                        Layout.preferredWidth: Style.px(12)
                        text: entry.modelData.index === root.current ? "✓" : ""
                        color: entry.fg(root.st.toggle_on)
                        font.family: root.st.font_family
                        font.pixelSize: root.st.font_size
                    }

                    Image {
                        visible: root.has_thumbs
                        Layout.preferredWidth: Style.px(56)
                        Layout.preferredHeight: Style.px(32)
                        source: entry.modelData.thumb
                        // Decoding at display size keeps a few hundred full-size wallpapers from stalling the shell.
                        sourceSize: Qt.size(Math.round(Style.px(56) * 2), Math.round(Style.px(32) * 2))
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                    }

                    Text {
                        Layout.fillWidth: true
                        text: Fuzzy.highlight(entry.modelData.label, entry.modelData.positions, String(entry.fg(root.st.text_accent)))
                        textFormat: Text.StyledText
                        elide: Text.ElideRight
                        color: entry.fg(root.st.text_fg)
                        font.family: root.st.font_family
                        font.pixelSize: root.st.font_size
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.cursor = entry.at;
                        root.accept();
                    }
                }
            }
        }

        Text {
            visible: root.results.length === 0
            Layout.fillWidth: true
            text: "No match"
            color: root.st.text_dim
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-2)
        }

        Text {
            id: counter_text
            visible: root.results.length > root.window_size
            Layout.fillWidth: true
            text: (root.cursor + 1) + " / " + root.results.length
            horizontalAlignment: Text.AlignRight
            color: root.st.text_dim
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-3)
        }
    }
}

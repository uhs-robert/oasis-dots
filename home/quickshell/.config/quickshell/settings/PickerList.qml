// home/quickshell/.config/quickshell/settings/PickerList.qml
import QtQuick
import QtQuick.Layouts
import "../components"
import "../theme"
import "../services"
import "../picker/Fuzzy.js" as Fuzzy

// A fuzzy-filtered list of a row's options; items are { label }, picked(index) reports the position in items.
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
    readonly property int window_size: 8

    readonly property var results: {
        const terms = Fuzzy.terms_of(root.query);
        const out = [];
        for (let i = 0; i < root.items.length; i++) {
            const m = terms.length === 0 ? { score: 0, positions: [] } : Fuzzy.score_item(terms, { label: root.items[i].label });
            if (m) out.push({ index: i, label: root.items[i].label, score: m.score, positions: m.positions });
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
        const recalled = InputSettings.recall("settings:" + root.title);
        input.text = recalled;
        root.query = recalled;
        const at = root.results.findIndex(r => r.index === root.current);
        root.cursor = Math.max(0, at);
        root.set_insert(InputSettings.starts_insert);
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
        Layout.fillWidth: true
        text: root.title
        color: root.st.text_accent
        font.family: root.st.font_family
        font.pixelSize: root.st.font_size
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
            selectionColor: root.st.text_accent
            font.family: root.st.font_family
            font.pixelSize: root.st.font_size
            onTextChanged: {
                root.query = text;
                root.cursor = 0;
                InputSettings.remember("settings:" + root.title, text);
            }

            Keys.onPressed: event => {
                const ctrl = !!(event.modifiers & Qt.ControlModifier);
                if (event.key === Qt.Key_Escape) root.set_insert(false);
                else if (ctrl && event.key === Qt.Key_U) input.text = "";
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

    Repeater {
        model: root.results.slice(root.first_shown, root.first_shown + root.window_size)

        MenuRow {
            id: entry
            required property int index
            required property var modelData
            readonly property int at: root.first_shown + entry.index

            Layout.fillWidth: true
            Layout.preferredHeight: Style.px(28)
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
        visible: root.results.length > root.window_size
        Layout.fillWidth: true
        text: (root.cursor + 1) + " / " + root.results.length
        horizontalAlignment: Text.AlignRight
        color: root.st.text_dim
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-3)
    }
}

// home/quickshell/.config/quickshell/popups/StylePopup.qml
import QtQuick
import QtQuick.Layouts
import "../components"
import "../theme"
import "../services"
import "../components/transitions"

Popup {
    id: root

    popup_name: "style"
    preferred_width: 180
    footer_hint: "/ find · j/k preview · gg/G first/last · 1-9 pick · Enter apply · c cava line · l lock screen · q cancel"
    body_height: content.implicitHeight + 24
    jumps_enabled: true

    property int selected: 0

    readonly property bool is_open: Popups.open_name === "style"
    onIs_openChanged: {
        if (is_open) root.selected = Math.max(0, Style.names.indexOf(Style.saved_name));
        else Transitions.show(Style.saved_name, true);
    }
    // Typing to find only highlights a row; NORMAL-mode navigation (j/k, gg/G, 1-9) still previews live.
    onSelectedChanged: if (is_open && !root.search_typing) Transitions.show(Style.names[root.selected], false)
    search_enabled: true
    search_starts_open: true
    search_opens_typing: false
    search_rows: Style.names.map(n => root.label(n))
    search_cursor: root.selected
    onSearch_select: index => root.selected = index
    // Enter while typing drops to NORMAL on the match and previews it; a second Enter applies.
    onSearch_accept: {
        root.accept_search();
        Transitions.show(Style.names[root.selected], true);
    }
    onJump_first: root.selected = 0
    onJump_last: root.selected = Style.names.length - 1

    function apply() {
        Transitions.commit(Style.names[root.selected]);
        Popups.close();
    }

    function open_lock() {
        Popups.open("lockscreen", Popups.open_anchor, Popups.open_color, Popups.open_screen_name, "style");
    }

    function label(style_name) {
        return Style.label(style_name);
    }

    Item {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        implicitHeight: styles_col.implicitHeight
        focus: true

        Keys.onPressed: event => {
            if (event.key === Qt.Key_C) {
                Style.set_cava_line(!Style.cava_line);
                event.accepted = true;
            } else if (event.key === Qt.Key_L) {
                root.open_lock();
                event.accepted = true;
            } else if (event.key === Qt.Key_J) {
                root.selected = root.wrap_index(root.selected, 1, 0, Style.names.length);
                event.accepted = true;
            } else if (event.key === Qt.Key_K) {
                root.selected = root.wrap_index(root.selected, -1, 0, Style.names.length);
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.apply();
                event.accepted = true;
            } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9 && event.key - Qt.Key_1 < Style.names.length) {
                root.selected = event.key - Qt.Key_1;
                event.accepted = true;
            }
        }

        ColumnLayout {
            id: styles_col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 4

            Repeater {
                model: Style.names

                MenuRow {
                    id: row
                    required property int index
                    required property string modelData

                    Layout.fillWidth: true
                    height: Style.px(28)
                    base_radius: 6
                    selected: index === root.selected
                    key: row.index < 9 ? String(row.index + 1) : ""

                    RowLayout {
                        anchors.left: parent.left
                        anchors.leftMargin: 8 + row.inset
                        anchors.right: parent.right
                        anchors.rightMargin: 8 + row.key_space
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        RowLabel {
                            Layout.fillWidth: true
                            label: root.label(row.modelData)
                            color: row.fg(root.st.text_fg)
                            font.family: root.st.font_family
                            font.pixelSize: root.st.font_size
                        }

                        Text {
                            text: row.modelData === Style.saved_name ? "active" : ""
                            color: row.fg(Theme.ok)
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-3)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.selected = row.index;
                            root.apply();
                        }
                    }
                }
            }

            ToggleRow {
                Layout.topMargin: 6
                label: "Cava line"
                toggle_key: "c"
                checked: Style.cava_line
                onToggled: Style.set_cava_line(!Style.cava_line)
            }

            ToggleRow {
                label: "Lock screen"
                toggle_key: "l"
                checked: true
                state_label: Style.lock_style === "follow" ? "Follow" : Style.lock_style === "simple" ? "Simple" : Style.label(Style.lock_style)
                onToggled: root.open_lock()
            }
        }
    }
}

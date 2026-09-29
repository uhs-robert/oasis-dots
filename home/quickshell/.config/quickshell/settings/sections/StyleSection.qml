// home/quickshell/.config/quickshell/settings/sections/StyleSection.qml
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../../services"
import "../../components/transitions"
import ".."

SettingsPane {
    id: root

    property int selected: 0

    footer_hint: "/ find · j/k preview · gg/G first/last · 1-9 pick · Enter apply · c cava line · Esc sections · q close"
    search_rows: Style.names.map(n => Style.label(n))
    search_cursor: root.selected
    implicitHeight: col.implicitHeight

    // Leaving the pane or closing the popup drops any unapplied preview.
    onLiveChanged: {
        if (root.live) root.selected = Math.max(0, Style.names.indexOf(Style.saved_name));
        else Transitions.show(Style.saved_name, true);
    }
    // Typing to find only highlights a row; the preview follows once typing ends.
    onSelectedChanged: if (root.live && !root.popup.search_typing) Transitions.show(Style.names[root.selected], false)
    Component.onCompleted: if (root.live) root.selected = Math.max(0, Style.names.indexOf(Style.saved_name))

    function search_select(index) {
        root.selected = index;
    }

    function jump(delta) {
        root.selected = delta < 0 ? 0 : Style.names.length - 1;
    }

    function apply() {
        Transitions.commit(Style.names[root.selected]);
    }

    Connections {
        target: root.popup
        function onSearch_typingChanged() {
            if (root.live && !root.popup.search_typing) Transitions.show(Style.names[root.selected], false);
        }
    }

    Keys.onPressed: event => {
        if (event.modifiers & Qt.ControlModifier) return;
        if (event.key === Qt.Key_C) Style.set_cava_line(!Style.cava_line);
        else if (event.key === Qt.Key_J) root.selected = root.wrap_index(root.selected, 1, Style.names.length);
        else if (event.key === Qt.Key_K) root.selected = root.wrap_index(root.selected, -1, Style.names.length);
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.apply();
        else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9 && event.key - Qt.Key_1 < Style.names.length) root.selected = event.key - Qt.Key_1;
        else return;
        event.accepted = true;
    }

    ColumnLayout {
        id: col
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
                Layout.preferredHeight: Style.px(28)
                base_radius: 6
                selected: root.live && row.index === root.selected
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
                        label: Style.label(row.modelData)
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
                        root.focus_pane();
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
    }
}

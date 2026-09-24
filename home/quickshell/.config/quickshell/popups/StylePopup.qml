// home/quickshell/.config/quickshell/popups/StylePopup.qml
import QtQuick
import QtQuick.Layouts
import "../components"
import "../theme"
import "../services"

Popup {
    id: root

    popup_name: "style"
    preferred_width: 180
    footer_hint: "j/k preview · 1-9 pick · Enter apply · q cancel"
    body_height: content.implicitHeight + 24

    property int selected: 0

    readonly property bool is_open: Popups.open_name === "style"
    onIs_openChanged: {
        if (is_open) root.selected = Math.max(0, Style.names.indexOf(Style.saved_name));
        else Style.preview(Style.saved_name);
    }
    onSelectedChanged: if (is_open) Style.preview(Style.names[root.selected])

    function apply() {
        Style.set(Style.names[root.selected]);
        Popups.close();
    }

    function label(style_name) {
        return style_name.charAt(0).toUpperCase() + style_name.slice(1);
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
            if (event.key === Qt.Key_J) {
                root.selected = (root.selected + 1) % Style.names.length;
                event.accepted = true;
            } else if (event.key === Qt.Key_K) {
                root.selected = (root.selected - 1 + Style.names.length) % Style.names.length;
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

                        Text {
                            Layout.fillWidth: true
                            text: root.label(row.modelData)
                            color: row.fg(Theme.fg_core)
                            font.family: Style.font_family
                            font.pixelSize: Style.font_size
                        }

                        Text {
                            text: row.modelData === Style.saved_name ? "active" : ""
                            color: row.fg(Theme.ok)
                            font.family: Style.font_family
                            font.pixelSize: Style.font_size - 3
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
        }
    }
}

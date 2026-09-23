// home/quickshell/.config/quickshell/popups/notifications/HeaderButton.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"

// A pill button for the notifications header: icon + label + a keycap-style key hint.
Rectangle {
    id: root

    property string icon: ""
    property string label: ""
    property string key_hint: ""
    property bool active: false

    signal activated()

    implicitWidth: row.implicitWidth + 28
    implicitHeight: row.implicitHeight + 16
    radius: 8
    color: root.active ? Theme.theme_primary : mouse_area.pressed ? Qt.darker(Theme.bg_surface, 1.3) : mouse_area.containsMouse ? Theme.ui_visual_bg : Theme.bg_surface
    border.width: 1
    border.color: Theme.ui_border

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6

        Text {
            text: root.icon
            color: root.active ? Theme.bg_core : Theme.fg_core
            font.family: Theme.font_family
            font.pixelSize: Theme.popup_font_size
        }

        Text {
            text: root.label
            color: root.active ? Theme.bg_core : Theme.fg_core
            font.bold: root.active
            font.family: Theme.font_family
            font.pixelSize: Theme.popup_font_size - 2
        }

        Rectangle {
            implicitWidth: key_label.implicitWidth + 8
            implicitHeight: 16
            radius: 3
            color: root.active ? Theme.bg_core : Theme.bg_mantle
            border.width: 1
            border.color: Theme.ui_border

            Text {
                id: key_label
                anchors.centerIn: parent
                text: root.key_hint
                color: root.active ? Theme.theme_primary : Theme.fg_dim
                font.bold: true
                font.family: Theme.font_family
                font.pixelSize: Theme.popup_font_size - 5
            }
        }
    }

    MouseArea {
        id: mouse_area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.activated()
    }
}

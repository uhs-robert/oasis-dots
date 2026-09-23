// home/quickshell/.config/quickshell/popups/media/RoundButton.qml
import QtQuick
import "../../theme"

// A small round icon button for the media transport row.
Rectangle {
    id: root

    property string icon: ""
    property string badge: ""
    property int diameter: 32
    property bool primary: false
    property bool active: false
    property bool button_enabled: true

    signal activated()

    width: root.diameter
    height: root.diameter
    radius: root.diameter / 2
    opacity: root.button_enabled ? 1 : 0.35
    color: root.primary
        ? (mouse_area.pressed ? Qt.darker(Theme.theme_primary, 1.3) : mouse_area.containsMouse ? Qt.lighter(Theme.theme_primary, 1.15) : Theme.theme_primary)
        : (mouse_area.containsMouse ? Theme.bg_surface : "transparent")

    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
    scale: mouse_area.pressed ? 0.94 : 1.0

    Text {
        anchors.centerIn: parent
        text: root.icon
        color: root.primary ? Theme.bg_core : (root.active ? Theme.theme_primary : Theme.fg_core)
        font.family: Theme.font_family
        font.pixelSize: root.primary ? root.diameter * 0.42 : root.diameter * 0.5
    }

    Rectangle {
        visible: root.badge !== ""
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: -1
        anchors.bottomMargin: -1
        width: 12
        height: 12
        radius: 6
        color: Theme.theme_primary
        border.width: 1
        border.color: Theme.bg_mantle

        Text {
            anchors.centerIn: parent
            text: root.badge
            color: Theme.bg_core
            font.family: Theme.font_family
            font.pixelSize: 8
            font.bold: true
        }
    }

    MouseArea {
        id: mouse_area
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.button_enabled
        onClicked: root.activated()
    }
}

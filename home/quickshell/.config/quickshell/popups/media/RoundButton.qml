// home/quickshell/.config/quickshell/popups/media/RoundButton.qml
import QtQuick
import "../../theme"
import "../../services"

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
        ? (mouse_area.pressed ? Qt.darker(Style.pal.primary, 1.3) : mouse_area.containsMouse ? Qt.lighter(Style.pal.primary, 1.15) : Style.pal.primary)
        : (mouse_area.containsMouse ? Style.pal.bg_surface : "transparent")

    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
    scale: mouse_area.pressed ? 0.94 : 1.0

    Text {
        anchors.centerIn: parent
        text: root.icon
        color: root.primary ? Style.pal.bg_core : (root.active ? Style.pal.primary : Style.pal.fg)
        font.family: Style.font_family
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
        radius: Style.radius(6)
        color: Style.pal.primary
        border.width: 1
        border.color: Style.pal.bg_mantle

        Text {
            anchors.centerIn: parent
            text: root.badge
            color: Style.pal.bg_core
            font.family: Style.font_family
            font.pixelSize: 8
            font.bold: true
        }
    }

    MouseArea {
        id: mouse_area
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.button_enabled
        onClicked: {
            ThemeAudio.play("confirm");
            root.activated();
        }
    }
}

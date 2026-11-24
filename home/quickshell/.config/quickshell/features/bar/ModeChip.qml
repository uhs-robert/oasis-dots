import QtQuick
import qs.theme

// A filled chip at the end of the left island: the Hyprland submap or a voice mode.
Rectangle {
    id: root

    property string label: ""
    property color tint: Theme.theme_secondary

    implicitWidth: chip_text.implicitWidth + 16
    implicitHeight: chip_text.implicitHeight + 6
    radius: Style.radius(4)
    color: root.tint

    Text {
        id: chip_text
        anchors.centerIn: parent
        text: root.label.toUpperCase()
        color: Theme.bg_core
        font.family: Style.font_family
        font.pixelSize: Style.bar_font_size - 1
        font.bold: true
        font.letterSpacing: 1
    }
}

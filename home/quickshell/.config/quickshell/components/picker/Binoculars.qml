// home/quickshell/.config/quickshell/components/picker/Binoculars.qml
import QtQuick
import "../../theme"

// Small binocular glyph for the PS1 scope skin's CAMERA slot.
Item {
    id: root

    property color color: Theme.red

    implicitWidth: 26
    implicitHeight: 14

    Rectangle {
        x: 1
        y: 2
        width: 10
        height: 10
        radius: 5
        color: "transparent"
        border.width: 2
        border.color: root.color
    }

    Rectangle {
        x: 15
        y: 2
        width: 10
        height: 10
        radius: 5
        color: "transparent"
        border.width: 2
        border.color: root.color
    }

    Rectangle {
        x: 10
        y: 5
        width: 6
        height: 3
        color: root.color
    }
}

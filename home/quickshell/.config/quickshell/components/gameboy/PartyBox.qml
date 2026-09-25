// home/quickshell/.config/quickshell/components/gameboy/PartyBox.qml
import QtQuick
import "../../theme"

// A Pokemon party row: shade 0 box in a hard-cornered 1px double border, lit in shade 3 when selected.
Rectangle {
    id: root

    property bool selected: false

    color: Style.shade_0
    border.width: 1
    border.color: root.selected ? Style.shade_3 : Style.shade_1
    antialiasing: false

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        color: "transparent"
        border.width: 1
        border.color: root.selected ? Style.shade_3 : Style.shade_2
        antialiasing: false
    }
}

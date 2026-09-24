// home/quickshell/.config/quickshell/components/LockBrackets.qml
import QtQuick
import "../theme"

// Target-lock brackets at the four corners of a selected item, in the style's selection_brackets color.
CornerBrackets {
    id: root

    property bool shown: true

    anchors.fill: parent
    color: root.shown ? Style.for_item(root).selection_brackets : "transparent"
    inset: 0
    arm: 8
    thickness: 1.5
    all_corners: true
}

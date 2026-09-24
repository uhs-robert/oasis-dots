// home/quickshell/.config/quickshell/components/Slant.qml
import QtQuick
import "../theme"

// Fills its parent as a parallelogram leaning right by `slant` px per px of height.
Rectangle {
    id: root

    property real slant: Style.for_item(root).slant
    readonly property real shift: root.slant * root.height

    width: parent ? parent.width - root.shift : 0
    height: parent ? parent.height : 0
    antialiasing: true
    transform: Matrix4x4 {
        matrix: Qt.matrix4x4(1, -root.slant, 0, root.shift, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
    }
}

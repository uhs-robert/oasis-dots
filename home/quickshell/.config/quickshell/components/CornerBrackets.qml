// home/quickshell/.config/quickshell/components/CornerBrackets.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

// The style's corner brackets at the top left and top right, inset from the frame edge.
Item {
    id: root

    property color color: Style.for_item(root).frame_brackets
    property int inset: 4
    property int arm: 10

    visible: root.color.a > 0

    Repeater {
        model: root.visible ? [[0, 0], [0, 1], [1, 0], [1, 1]] : []

        Rectangle {
            id: arm_line
            required property var modelData
            readonly property bool on_right: arm_line.modelData[0] === 1
            readonly property bool upright: arm_line.modelData[1] === 1

            x: arm_line.on_right ? root.width - root.inset - arm_line.width : root.inset
            y: root.inset
            width: arm_line.upright ? 1 : root.arm
            height: arm_line.upright ? root.arm : 1
            color: root.color
        }
    }
}

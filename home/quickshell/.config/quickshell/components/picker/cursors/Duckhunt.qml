// home/quickshell/.config/quickshell/components/picker/cursors/Duckhunt.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../../theme"
import "../../../services"

// NES Zapper reticle: a white ring with four white arms, each outlined in black.
Item {
    id: root

    required property string screen_name
    required property point origin
    required property bool target_mode

    readonly property point at: Screenshot.cursor_point
    readonly property int cx: Math.round(root.at.x)
    readonly property int cy: Math.round(root.at.y)
    // Arms run from 6px to 15px off-center on each axis, 3px thick.
    readonly property var arms: [
        [-15, -1, 9, 3],
        [6, -1, 9, 3],
        [-1, -15, 3, 9],
        [-1, 6, 3, 9]
    ]

    visible: Style.picker_skin === "duckhunt" && Screenshot.phase === "select" && Screenshot.cursor_screen === root.screen_name && !root.target_mode

    Repeater {
        model: root.arms

        Rectangle {
            required property var modelData
            x: root.cx + modelData[0] - 1
            y: root.cy + modelData[1] - 1
            width: modelData[2] + 2
            height: modelData[3] + 2
            color: Theme.bg_shadow
        }
    }

    Repeater {
        model: root.arms

        Rectangle {
            required property var modelData
            x: root.cx + modelData[0]
            y: root.cy + modelData[1]
            width: modelData[2]
            height: modelData[3]
            color: Theme.fg_strong
        }
    }

    Rectangle {
        x: root.cx - 11.5
        y: root.cy - 11.5
        width: 23
        height: 23
        radius: width / 2
        color: "transparent"
        border.width: 1
        border.color: Theme.bg_shadow
    }

    Rectangle {
        x: root.cx - 10.5
        y: root.cy - 10.5
        width: 21
        height: 21
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: Theme.fg_strong
    }
}

// home/quickshell/.config/quickshell/components/picker/cursors/Tvosd.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../../theme"
import "../../../services"

// CRT TV on-screen-display reticle: a chunky green phosphor crosshair with a soft
// glow and a dark outline, matching the picture-menu look of the OSD loupe.
Item {
    id: root

    required property string screen_name
    required property point origin
    required property bool target_mode

    property point at: Screenshot.cursor_point
    property bool shown: Screenshot.phase === "select" && Screenshot.cursor_screen === root.screen_name
    readonly property int cx: Math.round(root.at.x)
    readonly property int cy: Math.round(root.at.y)
    // Arms run from 7px to 17px off-center on each axis, 3px thick.
    readonly property var arms: [
        [-17, -1, 10, 3],
        [7, -1, 10, 3],
        [-1, -17, 3, 10],
        [-1, 7, 3, 10]
    ]

    visible: Style.picker_skin === "tvosd" && root.shown && !root.target_mode

    Repeater {
        model: root.arms

        Rectangle {
            required property var modelData
            x: root.cx + modelData[0] - 3
            y: root.cy + modelData[1] - 3
            width: modelData[2] + 6
            height: modelData[3] + 6
            color: Qt.alpha(Theme.green, 0.35)
        }
    }

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
            color: Theme.green
        }
    }
}

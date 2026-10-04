// home/quickshell/.config/quickshell/components/picker/cursors/Tiecomp.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../../theme"
import "../../../services"

// TIE targeting-computer reticle: a thin cockpit ring with a center dot and four
// outboard ticks at N/E/S/W, crisp green over a faint dark outline for contrast.
Item {
    id: root

    required property string screen_name
    required property point origin
    required property bool target_mode

    readonly property point at: Screenshot.cursor_point
    readonly property int cx: Math.round(root.at.x)
    readonly property int cy: Math.round(root.at.y)
    readonly property int ring_r: 14
    readonly property int tick_gap: 3
    readonly property int tick_len: 6
    readonly property var ticks: [
        [-1, -(root.ring_r + root.tick_gap + root.tick_len), 2, root.tick_len],
        [-1, root.ring_r + root.tick_gap, 2, root.tick_len],
        [-(root.ring_r + root.tick_gap + root.tick_len), -1, root.tick_len, 2],
        [root.ring_r + root.tick_gap, -1, root.tick_len, 2]
    ]

    visible: Style.picker_skin === "tiecomp" && Screenshot.phase === "select" && Screenshot.cursor_screen === root.screen_name && !root.target_mode

    Rectangle {
        x: root.cx - root.ring_r - 1
        y: root.cy - root.ring_r - 1
        width: (root.ring_r + 1) * 2
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 3
        border.color: Qt.alpha(Theme.bg_shadow, 0.8)
    }

    Rectangle {
        x: root.cx - root.ring_r
        y: root.cy - root.ring_r
        width: root.ring_r * 2
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 1.5
        border.color: Theme.green
    }

    Repeater {
        model: root.ticks

        Rectangle {
            required property var modelData
            x: root.cx + modelData[0] - 1
            y: root.cy + modelData[1] - 1
            width: modelData[2] + 2
            height: modelData[3] + 2
            color: Qt.alpha(Theme.bg_shadow, 0.8)
        }
    }

    Repeater {
        model: root.ticks

        Rectangle {
            required property var modelData
            x: root.cx + modelData[0]
            y: root.cy + modelData[1]
            width: modelData[2]
            height: modelData[3]
            color: Theme.green
        }
    }

    Rectangle {
        x: root.cx - 2
        y: root.cy - 2
        width: 5
        height: 5
        color: Qt.alpha(Theme.bg_shadow, 0.8)
    }

    Rectangle {
        x: root.cx - 1
        y: root.cy - 1
        width: 3
        height: 3
        color: Theme.green
    }
}

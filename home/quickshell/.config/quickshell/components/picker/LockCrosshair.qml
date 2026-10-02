// home/quickshell/.config/quickshell/components/picker/LockCrosshair.qml
import QtQuick
import "../../theme"

// The lock-on reticle's four-tick crosshair with a centre dot, centred on (cx, cy).
Item {
    id: root

    property int cx: 0
    property int cy: 0
    property color color: Theme.theme_primary_light
    readonly property int tick_len: 6
    readonly property int tick_gap: 7
    readonly property var ticks: [[0, -root.tick_gap - root.tick_len, 1, root.tick_len], [0, root.tick_gap, 1, root.tick_len], [-root.tick_gap - root.tick_len, 0, root.tick_len, 1], [root.tick_gap, 0, root.tick_len, 1]]

    Repeater {
        model: root.ticks

        Rectangle {
            required property var modelData
            x: root.cx + modelData[0] - 1
            y: root.cy + modelData[1] - 1
            width: modelData[2] + 2
            height: modelData[3] + 2
            color: Qt.alpha(Theme.bg_shadow, 0.7)
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
            color: root.color
        }
    }

    Rectangle {
        x: root.cx - 3
        y: root.cy - 3
        width: 5
        height: 5
        color: Qt.alpha(Theme.bg_shadow, 0.7)
    }

    Rectangle {
        x: root.cx - 1
        y: root.cy - 1
        width: 3
        height: 3
        color: root.color
    }
}

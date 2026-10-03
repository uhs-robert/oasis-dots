// home/quickshell/.config/quickshell/components/picker/LockCrosshair.qml
import QtQuick
import "../../theme/Watch.js" as W

// The GoldenEye 007 aiming crosshair centred on (cx, cy): a red circle under a cross that runs through the centre and past the circle; a positive `gap` opens the very centre.
Item {
    id: root

    property int cx: 0
    property int cy: 0
    property real size: 30
    property real stroke: Math.min(2.5, Math.max(1.25, root.size / 26))
    property real gap: 0
    property color color: Qt.alpha(W.reticle, 0.85)
    readonly property real r: root.size / 2
    readonly property real reach: root.r + root.size * 0.4
    // [x, y, w, h] relative to the centre: one line each way, or two halves around a gap.
    readonly property var lines: root.gap > 0
        ? [[-root.reach, -root.stroke / 2, root.reach - root.gap, root.stroke], [root.gap, -root.stroke / 2, root.reach - root.gap, root.stroke], [-root.stroke / 2, -root.reach, root.stroke, root.reach - root.gap], [-root.stroke / 2, root.gap, root.stroke, root.reach - root.gap]]
        : [[-root.reach, -root.stroke / 2, root.reach * 2, root.stroke], [-root.stroke / 2, -root.reach, root.stroke, root.reach * 2]]

    Rectangle {
        x: root.cx - root.r - root.stroke
        y: root.cy - root.r - root.stroke
        width: root.size + root.stroke * 2
        height: width
        radius: width / 2
        color: "transparent"
        border.width: root.stroke + 2
        border.color: "#40000000"
        antialiasing: true
    }

    Repeater {
        model: root.lines

        Rectangle {
            required property var modelData
            x: root.cx + modelData[0] - 1
            y: root.cy + modelData[1] - 1
            width: modelData[2] + 2
            height: modelData[3] + 2
            color: "#40000000"
        }
    }

    Rectangle {
        x: root.cx - root.r - root.stroke / 2
        y: root.cy - root.r - root.stroke / 2
        width: root.size + root.stroke
        height: width
        radius: width / 2
        color: "transparent"
        border.width: root.stroke
        border.color: root.color
        antialiasing: true
    }

    Repeater {
        model: root.lines

        Rectangle {
            required property var modelData
            x: root.cx + modelData[0]
            y: root.cy + modelData[1]
            width: modelData[2]
            height: modelData[3]
            color: root.color
        }
    }
}

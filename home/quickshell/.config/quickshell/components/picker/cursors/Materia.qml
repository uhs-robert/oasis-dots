// home/quickshell/.config/quickshell/components/picker/cursors/Materia.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../../theme"
import "../../../services"
import "../.."

// FF7 battle targeting: the materia glove points at the pixel, fingertip just left of it.
Item {
    id: root

    required property string screen_name
    required property point origin
    required property bool target_mode

    property point at: Screenshot.cursor_point
    property bool shown: Screenshot.phase === "select" && Screenshot.cursor_screen === root.screen_name
    readonly property int cx: Math.round(root.at.x)
    readonly property int cy: Math.round(root.at.y)
    readonly property real glove_w: 36
    readonly property real glove_h: Math.round(root.glove_w * 14 / 22)

    visible: Style.picker_skin === "materia" && root.shown && !root.target_mode

    Timer {
        id: bob_timer
        running: root.visible
        interval: 250
        repeat: true
        property bool left: false
        onTriggered: bob_timer.left = !bob_timer.left
    }

    HandCursor {
        x: root.cx - root.glove_w - 4 + (bob_timer.left ? -3 : 0)
        y: root.cy - root.glove_h / 2
        width: root.glove_w
        height: root.glove_h
    }
}

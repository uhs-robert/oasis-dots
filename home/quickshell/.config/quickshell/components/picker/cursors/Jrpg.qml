// home/quickshell/.config/quickshell/components/picker/cursors/Jrpg.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../../theme"
import "../../../services"
import "../.."

// JRPG battle targeting: a bobbing white glove points at the target pixel, which blinks.
Item {
    id: root

    required property string screen_name
    required property point origin
    required property bool target_mode

    property point at: Screenshot.cursor_point
    property bool shown: Screenshot.phase === "select" && Screenshot.cursor_screen === root.screen_name
    readonly property int cx: Math.round(root.at.x)
    readonly property int cy: Math.round(root.at.y)
    readonly property real glove_w: 54
    readonly property real glove_h: Math.round(root.glove_w * 14 / 22)

    visible: Style.picker_skin === "jrpg" && root.shown && !root.target_mode

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

    Timer {
        id: blink_timer
        running: root.visible
        interval: 400
        repeat: true
        property bool alt: false
        onTriggered: blink_timer.alt = !blink_timer.alt
    }

    Rectangle {
        x: root.cx - 2
        y: root.cy - 2
        width: 4
        height: 4
        color: "transparent"
        border.width: 1
        border.color: blink_timer.alt ? Theme.theme_secondary : Theme.fg_strong
    }
}

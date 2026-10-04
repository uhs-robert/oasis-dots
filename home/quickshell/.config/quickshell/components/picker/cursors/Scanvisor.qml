// home/quickshell/.config/quickshell/components/picker/cursors/Scanvisor.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../../theme"
import "../../../services"
import "../.."

// Metroid Prime scan visor reticle: cyan corner brackets that close in once the
// cursor rests, then a 6-step scan sweep that turns the point and readout green.
Item {
    id: root

    required property string screen_name
    required property point origin
    required property bool target_mode

    property point at: Screenshot.cursor_point
    property bool shown: Screenshot.phase === "select" && Screenshot.cursor_screen === root.screen_name
    readonly property int cx: Math.round(root.at.x)
    readonly property int cy: Math.round(root.at.y)
    readonly property int move_half: 22
    readonly property int rest_half: 12
    readonly property int scan_steps: 6
    // -1 while moving; 0..scan_steps once resting and scanning.
    property int scan_step: -1
    readonly property bool scanning: root.scan_step >= 0
    readonly property bool complete: root.scan_step >= root.scan_steps
    readonly property int half: root.scanning ? root.rest_half : root.move_half
    readonly property color scan_color: root.complete ? Theme.bright_green : Theme.bright_yellow

    visible: Style.picker_skin === "scanvisor" && root.shown && !root.target_mode

    function reset_scan() {
        root.scan_step = -1;
        scan_timer.stop();
        if (root.visible) hold_timer.restart();
        else hold_timer.stop();
    }

    onAtChanged: root.reset_scan()
    onVisibleChanged: root.reset_scan()
    Component.onCompleted: root.reset_scan()

    Timer {
        id: hold_timer
        interval: 220
        onTriggered: {
            root.scan_step = 0;
            scan_timer.restart();
        }
    }

    Timer {
        id: scan_timer
        interval: 70
        repeat: true
        onTriggered: {
            if (root.scan_step < root.scan_steps) root.scan_step += 1;
            else scan_timer.stop();
        }
    }

    CornerBrackets {
        x: root.cx - root.half
        y: root.cy - root.half
        width: root.half * 2
        height: root.half * 2
        color: Theme.bright_cyan
        inset: 0
        arm: 10
        thickness: 2
        all_corners: true
    }

    Rectangle {
        visible: root.scanning
        x: root.cx - 4
        y: root.cy - 4
        width: 8
        height: 8
        rotation: 45
        color: "transparent"
        border.width: 2
        border.color: root.scan_color
    }

    Rectangle {
        visible: !root.scanning
        x: root.cx - 1
        y: root.cy - 1
        width: 3
        height: 3
        color: Theme.bright_cyan
    }

    Column {
        id: scan_readout
        visible: root.scanning
        x: root.cx - scan_readout.width / 2
        y: root.cy + root.rest_half + 10
        width: 120
        spacing: 3

        Text {
            width: scan_readout.width
            horizontalAlignment: Text.AlignHCenter
            text: root.complete ? "SCAN COMPLETE" : "SCANNING " + Math.round(root.scan_step / root.scan_steps * 100) + "%"
            color: root.scan_color
            font.family: Style.font_family
            font.pixelSize: 10
            font.letterSpacing: 1.5
        }

        Rectangle {
            width: scan_readout.width
            height: 4
            color: Qt.alpha(Theme.bg_shadow, 0.7)
            border.width: 1
            border.color: Qt.alpha(Theme.bright_cyan, 0.4)

            Rectangle {
                x: 1
                y: 1
                width: Math.max(0, (parent.width - 2) * (root.scan_step / root.scan_steps))
                height: parent.height - 2
                color: root.scan_color
            }
        }
    }
}

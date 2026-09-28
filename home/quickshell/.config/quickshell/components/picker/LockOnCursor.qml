// home/quickshell/.config/quickshell/components/picker/LockOnCursor.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import "../../services"
import ".."

// Perfect Dark reticle for the Goldeneye picker skin: a four-tick crosshair with a center dot,
// plus red corner brackets that step inward once the cursor has held still for ~220ms.
Item {
    id: root

    required property string screen_name
    required property bool target_mode

    readonly property point at: Screenshot.cursor_point
    readonly property int cx: Math.round(root.at.x)
    readonly property int cy: Math.round(root.at.y)
    readonly property int tick_len: 6
    readonly property int tick_gap: 7
    readonly property var lock_sizes: [46, 30, 18]
    property int lock_step: -1

    visible: Style.picker_skin === "goldeneye" && Screenshot.phase === "select" && Screenshot.cursor_screen === root.screen_name && !root.target_mode

    function reset_lock() {
        root.lock_step = -1;
        step_timer.stop();
        if (root.visible) hold_timer.restart();
        else hold_timer.stop();
    }

    onAtChanged: root.reset_lock()
    onVisibleChanged: root.reset_lock()
    Component.onCompleted: root.reset_lock()

    Timer {
        id: hold_timer
        interval: 220
        onTriggered: {
            root.lock_step = 0;
            step_timer.restart();
        }
    }

    Timer {
        id: step_timer
        interval: 70
        repeat: true
        onTriggered: {
            if (root.lock_step < root.lock_sizes.length - 1) root.lock_step += 1;
            else step_timer.stop();
        }
    }

    Repeater {
        model: [[0, -root.tick_gap - root.tick_len, 1, root.tick_len], [0, root.tick_gap, 1, root.tick_len], [-root.tick_gap - root.tick_len, 0, root.tick_len, 1], [root.tick_gap, 0, root.tick_len, 1]]

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
        model: [[0, -root.tick_gap - root.tick_len, 1, root.tick_len], [0, root.tick_gap, 1, root.tick_len], [-root.tick_gap - root.tick_len, 0, root.tick_len, 1], [root.tick_gap, 0, root.tick_len, 1]]

        Rectangle {
            required property var modelData
            x: root.cx + modelData[0]
            y: root.cy + modelData[1]
            width: modelData[2]
            height: modelData[3]
            color: Theme.theme_primary_light
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
        color: Theme.theme_primary_light
    }

    Item {
        id: lock_box
        readonly property int size: root.lock_step >= 0 ? root.lock_sizes[root.lock_step] : 0
        visible: root.lock_step >= 0
        x: root.cx - lock_box.size / 2
        y: root.cy - lock_box.size / 2
        width: lock_box.size
        height: lock_box.size

        CornerBrackets {
            anchors.fill: parent
            color: Theme.theme_label
            inset: 0
            arm: Math.max(4, Math.round(lock_box.size / 4))
            thickness: 2
            all_corners: true
        }
    }
}

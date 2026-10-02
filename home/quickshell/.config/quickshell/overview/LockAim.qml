// home/quickshell/.config/quickshell/overview/LockAim.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../components"
import "../components/picker"
import "../theme"
import "../services"

// The GoldenEye lock-on over the overview's selected window: a crosshair on its centre and red corner brackets that step closed when the selection moves.
Item {
    id: root

    // Target in this item's coordinates: { x, y, w, h }, or null to hide.
    property var aim: null
    // Step the brackets closed on a new target; otherwise they sit locked.
    property bool animate: false

    readonly property real tx: root.aim ? root.aim.x : 0
    readonly property real ty: root.aim ? root.aim.y : 0
    readonly property real tw: root.aim ? root.aim.w : 0
    readonly property real th: root.aim ? root.aim.h : 0
    readonly property string aim_key: Math.round(root.tx) + "," + Math.round(root.ty) + "," + Math.round(root.tw) + "," + Math.round(root.th)
    readonly property var lock_steps: [60, 30, 0]
    property int lock_step: root.lock_steps.length - 1
    readonly property real grow: root.lock_steps[root.lock_step]

    visible: Style.picker_skin === "goldeneye" && !!root.aim

    function relock() {
        step_timer.stop();
        if (!root.visible || !root.animate) {
            root.lock_step = root.lock_steps.length - 1;
            return;
        }
        root.lock_step = 0;
        step_timer.restart();
    }

    onAim_keyChanged: root.relock()

    Timer {
        id: step_timer
        interval: 70
        repeat: true
        onTriggered: {
            if (root.lock_step < root.lock_steps.length - 1) root.lock_step += 1;
            else step_timer.stop();
        }
    }

    CornerBrackets {
        x: root.tx - root.grow
        y: root.ty - root.grow
        width: root.tw + root.grow * 2
        height: root.th + root.grow * 2
        color: Theme.theme_label
        inset: 0
        arm: Math.max(6, Math.min(22, Math.round(Math.min(root.tw, root.th) / 4)))
        thickness: 3
        all_corners: true
    }

    LockCrosshair {
        cx: Math.round(root.tx + root.tw / 2)
        cy: Math.round(root.ty + root.th / 2)
        color: Theme.theme_primary_light
    }
}

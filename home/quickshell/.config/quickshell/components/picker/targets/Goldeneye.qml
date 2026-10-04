// home/quickshell/.config/quickshell/components/picker/targets/Goldeneye.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../../theme"
import "../../../services"
import "../.."
import "../../goldeneye" as Goldeneye
import "../../../theme/Watch.js" as W

// GoldenEye dressing for the window/screen/region target: red lock-on brackets that
// step closed when the target changes, a TARGET/AREA panel, and an OASIS WATCH readout.
Item {
    id: root

    required property string screen_name
    required property point origin
    required property rect sel
    required property bool mine
    required property bool target_mode

    readonly property bool full: Screenshot.mode === "screen"
    readonly property bool region: Screenshot.mode === "region"
    readonly property real tx: root.sel.x
    readonly property real ty: root.sel.y
    readonly property real tw: root.sel.width
    readonly property real th: root.sel.height
    readonly property string cls: root.region ? "AREA" : root.full ? root.screen_name : (Screenshot.targets[Screenshot.target_index] ? Screenshot.targets[Screenshot.target_index].label : "")
    readonly property bool dragging: root.region && Screenshot.phase === "select"
    readonly property string lock_key: root.dragging ? "" : root.target_mode ? String(Screenshot.target_index) : Math.round(root.tx) + "," + Math.round(root.ty) + "," + Math.round(root.tw) + "," + Math.round(root.th)
    readonly property var lock_steps: [60, 30, 0]
    property int lock_step: root.lock_steps.length - 1
    readonly property real grow: root.lock_steps[root.lock_step]
    readonly property real base: root.full ? 10 : -6

    function relock() {
        step_timer.stop();
        if (root.dragging) {
            root.lock_step = root.lock_steps.length - 1;
            return;
        }
        root.lock_step = 0;
        step_timer.restart();
    }

    onLock_keyChanged: root.relock()
    Component.onCompleted: root.relock()

    Timer {
        id: step_timer
        interval: 70
        repeat: true
        onTriggered: {
            if (root.lock_step < root.lock_steps.length - 1) root.lock_step += 1;
            else step_timer.stop();
        }
    }

    Repeater {
        model: root.target_mode ? Screenshot.targets : []

        Item {
            id: other
            required property var modelData
            required property int index
            visible: other.modelData.screen === root.screen_name && other.index !== Screenshot.target_index && Screenshot.phase === "select"
            x: other.modelData.rect.x + 6
            y: other.modelData.rect.y + 6
            width: other.modelData.rect.width - 12
            height: other.modelData.rect.height - 12

            CornerBrackets {
                anchors.fill: parent
                color: Qt.alpha(W.reticle, 0.6)
                inset: 0
                arm: 10
                thickness: 1
                all_corners: true
            }

            Text {
                x: 14
                y: -2
                text: other.modelData.label
                color: Qt.alpha(W.reticle, 0.6)
                font.family: Style.font_family
                font.pixelSize: Style.fs(-7)
            }
        }
    }

    Rectangle {
        visible: root.mine
        x: root.tx + (root.full ? 4 : 0)
        y: root.ty + (root.full ? 4 : 0)
        width: root.tw - (root.full ? 8 : 0)
        height: root.th - (root.full ? 8 : 0)
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(W.reticle, 0.45)
    }

    CornerBrackets {
        visible: root.mine
        x: root.tx + root.base - root.grow
        y: root.ty + root.base - root.grow
        width: root.tw - root.base * 2 + root.grow * 2
        height: root.th - root.base * 2 + root.grow * 2
        color: W.reticle
        inset: 0
        arm: 22
        thickness: 3
        all_corners: true
    }

    Rectangle {
        id: panel
        visible: root.mine
        x: root.tx + (root.full ? 24 : 18)
        y: root.full ? root.ty + 24 : root.ty + 16
        width: panel_col.implicitWidth + 20
        height: panel_col.implicitHeight + 14
        color: Qt.alpha(Theme.bg_crust, 0.9)

        Rectangle {
            width: parent.width
            height: 2
            color: W.reticle
        }

        Column {
            id: panel_col
            x: 10
            y: 8
            spacing: 2

            Text {
                text: root.region ? "AREA" : "TARGET"
                color: W.reticle
                font.family: Style.font_family
                font.pixelSize: Style.fs(-7)
                font.letterSpacing: 1
            }

            Row {
                spacing: 12

                Text {
                    text: root.cls
                    color: Theme.fg_strong
                    font.family: Style.title_font_family
                    font.pixelSize: Style.fs(-4)
                    font.letterSpacing: 1
                }
            }
        }
    }

    Goldeneye.WatchReadout {
        id: watch
        visible: root.mine
        readonly property real w: Math.max(watch_lcd.implicitWidth + 24, watch.caption_width)
        x: root.tx + root.tw - watch.w - (root.full ? 24 : 18)
        y: root.ty + root.th - (root.full ? 74 : 66)
        width: watch.w
        height: 44
        status: root.grow === 0 ? "LOCKED" : "TRACKING"

        Goldeneye.SizeText {
            id: watch_lcd
            anchors.centerIn: parent
            width_px: Math.round(root.tw)
            height_px: Math.round(root.th)
        }
    }
}

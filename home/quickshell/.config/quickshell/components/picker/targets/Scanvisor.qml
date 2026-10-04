// home/quickshell/.config/quickshell/components/picker/targets/Scanvisor.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../../theme"
import "../../../services"
import "../.."
import ".."

// Metroid Prime scan visor dressing for the window/screen/region target: cyan brackets that
// close in on a new target, a diamond scan point, and a logbook visor card.
Item {
    id: root

    required property string screen_name
    required property point origin
    required property rect sel
    required property bool mine
    required property bool target_mode

    readonly property bool full: Screenshot.mode === "screen"
    readonly property bool region: Screenshot.mode === "region"
    readonly property string cls: root.region ? "AREA" : root.full ? root.screen_name : (Screenshot.targets[Screenshot.target_index] ? Screenshot.targets[Screenshot.target_index].label : "")
    readonly property string logbook_kind: root.region ? "AREA" : root.full ? "OUTPUT" : "WINDOW"
    readonly property real tx: root.sel.x
    readonly property real ty: root.sel.y
    readonly property real tw: root.sel.width
    readonly property real th: root.sel.height
    readonly property int inset: root.full ? 8 : 0
    readonly property bool dragging: root.region && Screenshot.phase === "select"
    readonly property string lock_key: root.dragging ? "" : root.target_mode ? String(Screenshot.target_index) : Math.round(root.tx) + "," + Math.round(root.ty) + "," + Math.round(root.tw) + "," + Math.round(root.th)
    readonly property var lock_steps: [40, 24, 12, 6, 2, 0]
    property int lock_step: root.lock_steps.length - 1
    readonly property real grow: root.lock_steps[root.lock_step]
    readonly property bool complete: root.lock_step === root.lock_steps.length - 1
    readonly property color scan_color: root.complete ? Theme.bright_green : Theme.bright_yellow

    function pad4(v) {
        const n = Math.round(v);
        return (n < 0 ? "-" : "") + String(Math.abs(n)).padStart(4, "0");
    }

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
            x: other.modelData.rect.x
            y: other.modelData.rect.y
            width: other.modelData.rect.width
            height: other.modelData.rect.height

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: 1
                border.color: Qt.alpha(Theme.bright_cyan, 0.25)
            }

            Rectangle {
                x: 8 - 4
                y: 8 - 4
                width: 8
                height: 8
                rotation: 45
                color: "transparent"
                border.width: 2
                border.color: Theme.bright_yellow
            }

            LabelPlate {
                target: other_label
            }

            Text {
                id: other_label
                x: 8
                y: 22
                text: other.modelData.label
                color: Qt.alpha(Theme.bright_cyan, 0.6)
                font.family: Style.font_family
                font.pixelSize: Style.fs(-7)
            }
        }
    }

    Rectangle {
        visible: root.mine
        x: root.tx + root.inset
        y: root.ty + root.inset
        width: root.tw - root.inset * 2
        height: root.th - root.inset * 2
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(Theme.bright_cyan, 0.45)
    }

    CornerBrackets {
        visible: root.mine
        x: root.tx + root.inset - root.grow
        y: root.ty + root.inset - root.grow
        width: root.tw - root.inset * 2 + root.grow * 2
        height: root.th - root.inset * 2 + root.grow * 2
        color: Theme.bright_cyan
        inset: 0
        arm: 18
        thickness: 2
        all_corners: true
    }

    Rectangle {
        visible: root.mine
        x: root.tx + root.inset - 4
        y: root.ty + root.inset - 4
        width: 8
        height: 8
        rotation: 45
        color: "transparent"
        border.width: 2
        border.color: root.scan_color
    }

    Item {
        id: logbook
        visible: root.mine
        readonly property real card_w: 230
        readonly property real raw_x: root.tx + root.tw - logbook.card_w
        readonly property real raw_y: root.ty + root.th
        x: Math.max(4, Math.min(parent.width - logbook.card_w - 4, logbook.raw_x))
        y: Math.min(parent.height - logbook_col.implicitHeight - 20, logbook.raw_y)
        width: logbook.card_w
        height: logbook_col.implicitHeight + 16

        ScanGlass {
            anchors.fill: parent
            corner: 10
        }

        Column {
            id: logbook_col
            x: 10
            y: 8
            width: logbook.card_w - 20
            spacing: 4

            Text {
                text: root.complete ? "LOGBOOK // " + root.logbook_kind : "SCANNING " + Math.round(root.lock_step / (root.lock_steps.length - 1) * 100) + "%"
                color: root.scan_color
                font.family: Style.font_family
                font.pixelSize: 10
                font.letterSpacing: 1.5
            }

            Text {
                width: logbook_col.width
                elide: Text.ElideRight
                text: root.cls
                color: Theme.fg_strong
                font.family: Style.title_font_family
                font.pixelSize: Style.fs(-3)
            }

            Row {
                spacing: 6

                Text {
                    text: "SIZE"
                    color: Theme.fg_dim
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-7)
                }

                Text {
                    text: Math.round(root.tw) + " x " + Math.round(root.th)
                    color: Theme.bright_cyan
                    font.family: Style.number_font
                    font.pixelSize: Style.fs(-6)
                }
            }

            Row {
                spacing: 6

                Text {
                    text: "POS"
                    color: Theme.fg_dim
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-7)
                }

                Text {
                    text: root.pad4(root.origin.x + root.tx) + " " + root.pad4(root.origin.y + root.ty)
                    color: Theme.bright_cyan
                    font.family: Style.number_font
                    font.pixelSize: Style.fs(-6)
                }
            }
        }
    }
}

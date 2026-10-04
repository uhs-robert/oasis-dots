// home/quickshell/.config/quickshell/components/picker/targets/Tiecomp.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../../theme"
import "../../../services"
import "../.."

// TIE targeting-computer dressing for the window/screen/region target: faint green ticks on
// every other window, red lock-on brackets that step closed on the target, and a glass card.
Item {
    id: root

    required property string screen_name
    required property point origin
    required property rect sel
    required property bool mine
    required property bool target_mode

    readonly property bool full: Screenshot.mode === "screen"
    readonly property bool region: Screenshot.mode === "region"
    readonly property bool window: root.target_mode && !root.full
    readonly property real tx: root.sel.x
    readonly property real ty: root.sel.y
    readonly property real tw: root.sel.width
    readonly property real th: root.sel.height
    readonly property int inset: root.full ? 8 : 0
    readonly property real fx: root.tx + root.inset
    readonly property real fy: root.ty + root.inset
    readonly property real fw: root.tw - root.inset * 2
    readonly property real fh: root.th - root.inset * 2
    // This screen's windows, in target order, for the "n/N" readout.
    readonly property var screen_targets: {
        if (!root.window) return [];
        const out = [];
        for (let i = 0; i < Screenshot.targets.length; i++) {
            if (Screenshot.targets[i].screen === root.screen_name) out.push(i);
        }
        return out;
    }
    readonly property int screen_n: root.screen_targets.indexOf(Screenshot.target_index) + 1
    readonly property string cls: root.region ? "AREA" : root.full ? root.screen_name : (Screenshot.targets[Screenshot.target_index] ? Screenshot.targets[Screenshot.target_index].label : "")
    readonly property bool dragging: root.region && Screenshot.phase === "select"
    readonly property string lock_key: root.dragging ? "" : root.target_mode ? String(Screenshot.target_index) : Math.round(root.tx) + "," + Math.round(root.ty) + "," + Math.round(root.tw) + "," + Math.round(root.th)
    readonly property var lock_steps: [60, 30, 0]
    property int lock_step: root.lock_steps.length - 1
    readonly property real grow: root.lock_steps[root.lock_step]
    readonly property real card_w: 264

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
        model: root.window ? Screenshot.targets : []

        Item {
            id: other
            required property var modelData
            required property int index
            visible: other.modelData.screen === root.screen_name && other.index !== Screenshot.target_index && Screenshot.phase === "select"
            x: other.modelData.rect.x + 5
            y: other.modelData.rect.y + 5
            width: other.modelData.rect.width - 10
            height: other.modelData.rect.height - 10

            CornerBrackets {
                anchors.fill: parent
                color: Qt.alpha(Theme.green, 0.5)
                inset: 0
                arm: 10
                thickness: 1
                all_corners: true
            }
        }
    }

    Rectangle {
        visible: root.mine && root.full
        x: root.fx
        y: root.fy
        width: root.fw
        height: root.fh
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(Theme.green, 0.5)
    }

    CornerBrackets {
        visible: root.mine
        x: root.fx + root.inset - root.grow
        y: root.fy + root.inset - root.grow
        width: root.fw - root.inset * 2 + root.grow * 2
        height: root.fh - root.inset * 2 + root.grow * 2
        color: Theme.red
        inset: 0
        arm: 22
        thickness: 3
        all_corners: true
    }

    Item {
        id: card
        readonly property real target_x: root.tx + root.tw
        readonly property real target_y: root.ty + root.th
        visible: root.mine
        x: Math.max(0, Math.min(root.width - card.width, card.target_x - card.width - 16))
        y: Math.max(0, Math.min(root.height - card.height, card.target_y - card.height - 16))
        width: root.card_w
        height: card_col.implicitHeight + 36

        OctagonFrame {
            anchors.fill: parent
        }

        Column {
            id: card_col
            x: 24
            y: 18
            spacing: 2
            width: card.width - 48

            Text {
                text: root.full ? "SECTOR " + root.cls : root.region ? "TGT AREA" : "TGT " + root.screen_n + "/" + root.screen_targets.length
                color: Theme.green
                font.family: Style.font_family
                font.pixelSize: Style.fs(-7)
                font.letterSpacing: 1
            }

            Text {
                visible: root.window
                width: parent.width
                elide: Text.ElideRight
                text: root.cls
                color: Theme.fg_strong
                font.family: Style.title_font_family
                font.bold: true
                font.pixelSize: Style.fs(-4)
            }

            Text {
                text: "SIZE " + Math.round(root.tw) + " x " + Math.round(root.th)
                color: Theme.green
                font.family: Style.font_family
                font.pixelSize: Style.fs(-7)
            }

            Text {
                visible: root.window
                text: "POS " + Math.round(root.origin.x + root.tx) + "," + Math.round(root.origin.y + root.ty)
                color: Theme.green
                font.family: Style.font_family
                font.pixelSize: Style.fs(-7)
            }

            Text {
                visible: root.window
                text: "T CYCLE  ENTER FIRE"
                color: Qt.alpha(Theme.green, 0.6)
                font.family: Style.font_family
                font.pixelSize: Style.fs(-8)
                font.letterSpacing: 1
            }
        }
    }
}

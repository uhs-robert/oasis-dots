// home/quickshell/.config/quickshell/components/picker/targets/Tvosd.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../../theme"
import "../../../services"
import "../.."
import ".."

// CRT TV on-screen-display dressing for the window/screen/region target: a glowing
// green channel frame, a channel-list panel, and big corner readouts.
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
    // Window mode lists only this screen's targets; screen mode lists every output.
    readonly property var list_items: {
        if (!root.window && !root.full) return [];
        const out = [];
        for (let i = 0; i < Screenshot.targets.length; i++) {
            const t = Screenshot.targets[i];
            if (root.window && t.screen !== root.screen_name) continue;
            out.push({
                i: i,
                label: t.label
            });
        }
        return out;
    }
    readonly property int max_rows: Math.max(1, Math.min(8, Math.floor((root.height - 120) / 28)))
    readonly property int cur_row: Math.max(0, root.list_items.findIndex(t => t.i === Screenshot.target_index))
    readonly property int first_row: Math.max(0, Math.min(root.list_items.length - root.max_rows, root.cur_row - Math.floor(root.max_rows / 2)))
    readonly property var shown_items: root.list_items.slice(root.first_row, root.first_row + root.max_rows)
    readonly property string corner_text: root.region ? "ZOOM " + Math.round(root.tw) + "x" + Math.round(root.th) : root.full ? "INPUT" : "CH " + root.ch_key(Screenshot.target_index)
    readonly property int corner_size: root.region ? 40 : 64

    // Zero-pads a numeric hint key to two digits; non-numeric keys (or a missing one) pass through.
    function ch_key(index) {
        const raw = Style.picker_hint_keys.charAt(index);
        if (raw === "") return String(index + 1).padStart(2, "0");
        return /[0-9]/.test(raw) ? raw.padStart(2, "0") : raw;
    }

    Rectangle {
        id: frame_glow
        visible: root.mine
        x: root.fx - 4
        y: root.fy - 4
        width: root.fw + 8
        height: root.fh + 8
        color: "transparent"
        border.width: 6
        border.color: Qt.alpha(Theme.green, 0.25)
    }

    Rectangle {
        id: frame
        visible: root.mine
        x: root.fx
        y: root.fy
        width: root.fw
        height: root.fh
        color: "transparent"
        border.width: 2
        border.color: Theme.green
    }

    Rectangle {
        id: channel_list
        visible: (root.window || root.full) && root.list_items.length > 0
        x: 26
        y: 34
        width: list_col.implicitWidth + 28
        height: list_col.implicitHeight + 16
        color: Qt.alpha(Theme.bg_shadow, 0.72)

        Column {
            id: list_col
            x: 14
            y: 8
            spacing: 2

            Repeater {
                model: channel_list.visible ? root.shown_items : []

                Item {
                    id: chan_row
                    required property var modelData
                    readonly property bool active: chan_row.modelData.i === Screenshot.target_index
                    width: chan_text.width + (chan_row.active ? 8 : 0)
                    height: chan_text.implicitHeight

                    Rectangle {
                        visible: chan_row.active
                        anchors.fill: parent
                        color: Theme.green
                    }

                    Text {
                        id: chan_text
                        x: chan_row.active ? 4 : 0
                        width: Math.min(implicitWidth, 420)
                        elide: Text.ElideRight
                        text: (root.full ? "INPUT " + (chan_row.modelData.i + 1) : "CH " + root.ch_key(chan_row.modelData.i)) + " " + chan_row.modelData.label
                        color: chan_row.active ? Theme.bg_crust : Theme.green
                        style: chan_row.active ? Text.Normal : Text.Outline
                        styleColor: Qt.alpha(Theme.green, 0.6)
                        font.family: Style.font_family
                        font.pixelSize: 24
                    }
                }
            }
        }
    }

    LabelPlate {
        target: corner_label
        pad_x: 6
        pad_y: 4
    }

    Text {
        id: corner_label
        visible: root.mine
        x: root.width - corner_label.implicitWidth - 26
        y: 34
        text: root.corner_text
        color: Theme.green
        style: Text.Outline
        styleColor: Qt.alpha(Theme.green, 0.6)
        font.family: Style.font_family
        font.pixelSize: root.corner_size
    }

    LabelPlate {
        target: size_label
        pad_x: 6
        pad_y: 3
    }

    Text {
        id: size_label
        visible: root.mine && !root.region
        x: root.width - size_label.implicitWidth - 26
        y: root.height - size_label.implicitHeight - 18
        text: Math.round(root.tw) + "x" + Math.round(root.th)
        color: Theme.green
        style: Text.Outline
        styleColor: Qt.alpha(Theme.green, 0.6)
        font.family: Style.font_family
        font.pixelSize: 26
    }
}

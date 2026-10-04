// home/quickshell/.config/quickshell/components/picker/targets/Jrpg.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../../theme"
import "../../../services"
import "../.."
import "../../snes" as SnesParts

// SNES JRPG dressing for the window/screen/region target: a SNES-window frame on the pick, dotted
// outlines on the rest, a bobbing glove pointing at the pick, and a battle-menu style target list.
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
    readonly property int frame_inset: root.full ? 8 : 0
    readonly property real glove_w: 36
    readonly property real glove_h: Math.round(root.glove_w * 14 / 22)

    // The battle menu's row list: windows on this screen, this screen's outputs, or a single AREA row.
    readonly property var menu_targets: root.region ? [{ label: "AREA", rect: root.sel }] : root.full ? Screenshot.targets : Screenshot.targets.filter(t => t.screen === root.screen_name)
    readonly property int cur_row: root.region ? 0 : root.full ? Screenshot.target_index : root.menu_targets.indexOf(Screenshot.targets[Screenshot.target_index])
    readonly property string menu_title: root.full ? "OUTPUTS" : root.region ? "TARGET" : "ENEMIES"
    readonly property real menu_w: Math.max(190, Math.min(420, 20 + 22 + 16 + root.shown_rows.reduce((w, t) => Math.max(w, name_metrics.advanceWidth(t.label) + size_metrics.advanceWidth(root.size_label(t.rect))), 0)))
    readonly property real row_h: 22
    readonly property int max_rows: Math.max(1, Math.min(8, Math.floor((root.height - 84) / root.row_h)))
    readonly property int first_row: Math.max(0, Math.min(root.menu_targets.length - root.max_rows, root.cur_row - Math.floor(root.max_rows / 2)))
    readonly property var shown_rows: root.menu_targets.slice(root.first_row, root.first_row + root.max_rows)
    readonly property real menu_h: 30 + root.shown_rows.length * root.row_h + 10
    readonly property bool menu_right: root.tx + root.tw / 2 < root.width / 2

    function size_label(r) {
        return Math.round(r.width) + " x " + Math.round(r.height);
    }

    FontMetrics {
        id: name_metrics
        font.family: Style.font_family
        font.pixelSize: Style.fs(-6)
    }

    FontMetrics {
        id: size_metrics
        font.family: Style.font_family
        font.pixelSize: Style.fs(-7)
    }

    Repeater {
        model: root.target_mode ? Screenshot.targets : []

        Item {
            id: other
            required property var modelData
            required property int index
            visible: other.modelData.screen === root.screen_name && other.index !== Screenshot.target_index && Screenshot.phase === "select"
            x: other.modelData.rect.x + 3
            y: other.modelData.rect.y + 3
            width: other.modelData.rect.width - 6
            height: other.modelData.rect.height - 6

            DashedOutline {
                anchors.fill: parent
                color: Qt.alpha(Theme.theme_primary, 0.55)
            }
        }
    }

    Item {
        id: target_frame
        visible: root.mine
        x: root.tx + root.frame_inset
        y: root.ty + root.frame_inset
        width: root.tw - root.frame_inset * 2
        height: root.th - root.frame_inset * 2

        Rectangle {
            x: 4
            y: 4
            width: parent.width
            height: parent.height
            radius: 6
            color: Qt.alpha(Theme.bg_shadow, 0.7)
        }

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: "transparent"
            border.width: 3
            border.color: Theme.theme_primary
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 3
            radius: 3
            color: "transparent"
            border.width: 2
            border.color: Theme.fg_muted
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: -2
            radius: 8
            color: "transparent"
            border.width: 2
            border.color: Theme.bg_shadow
        }
    }

    Timer {
        id: bob_timer
        running: hand.visible
        interval: 250
        repeat: true
        property bool left: false
        onTriggered: bob_timer.left = !bob_timer.left
    }

    HandCursor {
        id: hand
        visible: root.mine
        readonly property bool inside: root.full || root.tx < 40
        x: (hand.inside ? root.tx + 12 : root.tx - root.glove_w - 4) + (bob_timer.left ? -3 : 0)
        y: root.ty + root.th / 2 - root.glove_h / 2
        width: root.glove_w
        height: root.glove_h
    }

    SnesParts.SnesWindow {
        id: battle_menu
        visible: root.mine
        x: root.menu_right ? root.width - root.menu_w - 22 : 22
        y: root.height - root.menu_h - 22
        width: root.menu_w
        height: root.menu_h

        Column {
            x: 10
            y: 8
            width: battle_menu.width - 20
            spacing: 4

            Text {
                text: root.menu_title
                color: Theme.theme_secondary
                font.family: Style.font_family
                font.pixelSize: Style.fs(-6)
                style: Text.Raised
                styleColor: Style.text_shadow
            }

            Repeater {
                model: root.shown_rows

                Item {
                    id: row
                    required property var modelData
                    required property int index
                    width: battle_menu.width - 20
                    height: root.row_h

                    HandCursor {
                        visible: row.index + root.first_row === root.cur_row
                        x: 0
                        y: (row.height - height) / 2
                        width: 18
                        height: Math.round(18 * 14 / 22)
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 22
                        anchors.right: row_size.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: row.modelData.label
                        color: row.index + root.first_row === root.cur_row ? Theme.fg_strong : Theme.theme_primary_light
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-6)
                        style: Text.Raised
                        styleColor: Style.text_shadow
                    }

                    Text {
                        id: row_size
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.size_label(row.modelData.rect)
                        color: Theme.theme_secondary
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-7)
                        style: Text.Raised
                        styleColor: Style.text_shadow
                    }
                }
            }
        }
    }
}

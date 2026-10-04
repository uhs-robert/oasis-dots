// home/quickshell/.config/quickshell/components/picker/MateriaTargets.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import "../../services"
import ".."
import "../ff7" as Ff7

// FF7 dressing for the window/screen/region target: a materia-window border on the pick, a centered
// help-bar naming it, and a weapon bar of linked materia slots for the windows or outputs on this screen.
Item {
    id: root

    required property string screen_name
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
    readonly property real slot_size: 26
    readonly property real slot_spacing: 10
    readonly property int max_slots: 8

    readonly property var slot_palette: [Theme.green, Theme.bright_yellow, Theme.magenta, Theme.blue, Theme.red, Theme.cyan, Theme.bright_magenta, Theme.bright_blue]

    // Windows on this screen, or every output in screen mode.
    readonly property var slot_targets: root.full ? Screenshot.targets : Screenshot.targets.filter(t => t.screen === root.screen_name)
    readonly property int cur_slot: root.slot_targets.indexOf(Screenshot.targets[Screenshot.target_index])
    readonly property int first_slot: Math.max(0, Math.min(root.slot_targets.length - root.max_slots, root.cur_slot - Math.floor(root.max_slots / 2)))
    readonly property var shown_slots: root.slot_targets.slice(root.first_slot, root.first_slot + root.max_slots)
    readonly property int shown_cur: root.cur_slot - root.first_slot

    readonly property string help_label: root.region ? root.size_label(root.sel) : (Screenshot.targets[Screenshot.target_index] ? Screenshot.targets[Screenshot.target_index].label : "")

    visible: root.mine || root.target_mode

    function size_label(r) {
        return Math.round(r.width) + " x " + Math.round(r.height);
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
                color: Qt.alpha(Style.frame_border_color, 0.4)
            }
        }
    }

    // The FF7 window border, with no fill so the target's own window shows through.
    Item {
        id: target_frame
        visible: root.mine
        x: root.tx + root.frame_inset
        y: root.ty + root.frame_inset
        width: root.tw - root.frame_inset * 2
        height: root.th - root.frame_inset * 2

        Rectangle {
            anchors.fill: parent
            anchors.margins: -2
            radius: 10
            color: "transparent"
            border.width: 1
            border.color: Theme.bg_shadow
        }

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: "transparent"
            border.width: 2
            border.color: Style.frame_border_color
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 3
            radius: 5
            color: "transparent"
            border.width: 1
            border.color: Theme.bg_shadow
        }
    }

    Ff7.Ff7Window {
        id: help_bar
        visible: root.mine
        x: Math.max(8, Math.min(root.width - width - 8, (root.width - help_bar.width) / 2))
        y: 32
        width: help_text.implicitWidth + 28
        height: help_text.implicitHeight + 16

        Text {
            id: help_text
            anchors.centerIn: parent
            text: root.help_label
            color: Theme.fg_strong
            font.family: Style.font_family
            font.pixelSize: Style.fs(-4)
        }
    }

    Ff7.Ff7Window {
        id: slots_win
        visible: root.mine && !root.region
        x: 22
        y: Math.max(8, root.height - slots_win.height - 22)
        width: slots_col.implicitWidth + 24
        height: slots_col.implicitHeight + 20

        Column {
            id: slots_col
            x: 12
            y: 10
            spacing: 8

            Text {
                text: root.full ? "Outputs" : "Slots"
                color: Theme.theme_primary_light
                font.family: Style.font_family
                font.pixelSize: Style.fs(-6)
                font.capitalization: Font.AllUppercase
            }

            Item {
                id: slots_row
                readonly property int count: root.shown_slots.length
                width: slots_row.count > 0 ? slots_row.count * root.slot_size + (slots_row.count - 1) * root.slot_spacing : root.slot_size
                height: Math.max(root.glove_h, root.slot_size)

                Ff7.MateriaLinks {
                    anchors.centerIn: parent
                    width: slots_row.width
                    height: root.slot_size
                    count: slots_row.count
                    slot: root.slot_size
                    spacing: root.slot_spacing
                    lit: true
                }

                Row {
                    anchors.centerIn: parent
                    spacing: root.slot_spacing

                    Repeater {
                        model: root.shown_slots

                        Item {
                            id: slot_item
                            required property var modelData
                            required property int index
                            width: root.slot_size
                            height: root.slot_size

                            Ff7.MateriaSlot {
                                anchors.fill: parent
                                color: root.slot_palette[(slot_item.index + root.first_slot) % root.slot_palette.length]
                                lit: slot_item.index === root.shown_cur
                                raised: slot_item.index === root.shown_cur
                            }

                            HandCursor {
                                visible: slot_item.index === root.shown_cur
                                x: -root.glove_w + 6
                                y: (parent.height - height) / 2
                                width: root.glove_w
                                height: root.glove_h
                            }
                        }
                    }
                }
            }

            Text {
                text: "Size " + (Screenshot.targets[Screenshot.target_index] ? root.size_label(Screenshot.targets[Screenshot.target_index].rect) : "")
                color: Theme.fg_strong
                font.family: Style.font_family
                font.pixelSize: Style.fs(-6)
            }
        }
    }
}

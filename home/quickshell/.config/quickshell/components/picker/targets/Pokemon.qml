// home/quickshell/.config/quickshell/components/picker/targets/Pokemon.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../../theme"
import "../../../services"
import "../.."

// Game Boy party dressing for the window/screen/region target: a double-bordered pick frame and
// a party-menu box listing windows or outputs with HP-style size bars.
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
    readonly property real box_w: 380
    readonly property real row_h: 34
    readonly property int max_rows: 5

    // Windows on this screen, or every output in screen mode.
    readonly property var list_items: {
        const out = [];
        for (let i = 0; i < Screenshot.targets.length; i++) {
            const t = Screenshot.targets[i];
            if (!root.full && t.screen !== root.screen_name) continue;
            out.push({
                i: i,
                label: t.label,
                rect: t.rect
            });
        }
        return out;
    }
    readonly property int cur_row: Math.max(0, root.list_items.findIndex(t => t.i === Screenshot.target_index))
    readonly property int first_row: Math.max(0, Math.min(root.list_items.length - root.max_rows, root.cur_row - Math.floor(root.max_rows / 2)))
    readonly property var shown_items: root.list_items.slice(root.first_row, root.first_row + root.max_rows)
    readonly property real menu_h: party_menu_col.implicitHeight + 16

    function area_ratio(r) {
        return (r.width * r.height) / (root.width * root.height);
    }

    function hp_color(ratio) {
        return ratio > 0.5 ? Theme.green : ratio > 0.2 ? Theme.theme_secondary : Theme.red;
    }

    function size_label(r) {
        return Math.round(r.width) + "x" + Math.round(r.height);
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
                color: Qt.alpha(Style.picker_shades[2], 0.55)
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
            anchors.fill: parent
            color: "transparent"
            border.width: 2
            border.color: Style.picker_shades[1]
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 4
            color: "transparent"
            border.width: 2
            border.color: Style.picker_shades[2]
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            color: "transparent"
            border.width: 2
            border.color: Style.picker_shades[3]
        }
    }

    Rectangle {
        id: area_box
        visible: root.mine && root.region
        x: 24
        y: root.height - area_box.height - 24
        width: area_text.implicitWidth + 20
        height: area_text.implicitHeight + 16
        color: Style.picker_shades[0]
        border.width: 1
        border.color: Style.picker_shades[1]
        antialiasing: false

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            color: "transparent"
            border.width: 1
            border.color: Style.picker_shades[2]
            antialiasing: false
        }

        Text {
            id: area_text
            anchors.centerIn: parent
            text: "AREA " + root.size_label(root.sel)
            color: Style.text_fg
            font.family: Style.mono_font
            font.pixelSize: 12
        }
    }

    Rectangle {
        id: party_box
        visible: root.mine && !root.region
        x: 24
        y: root.height - party_box.height - 24
        width: root.box_w
        height: root.menu_h
        color: Style.picker_shades[0]
        border.width: 1
        border.color: Style.picker_shades[1]
        antialiasing: false

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            color: "transparent"
            border.width: 1
            border.color: Style.picker_shades[2]
            antialiasing: false
        }

        Column {
            id: party_menu_col
            x: 12
            y: 8
            width: party_box.width - 24
            spacing: 0

            Repeater {
                model: party_box.visible ? root.shown_items : []

                Item {
                    id: row
                    required property var modelData
                    readonly property bool active: row.modelData.i === Screenshot.target_index
                    readonly property real ratio: root.area_ratio(row.modelData.rect)
                    width: parent.width
                    height: root.row_h

                    Item {
                        y: 0
                        width: parent.width
                        height: 16

                        PixelSprite {
                            visible: row.active
                            pixel: 2
                            rows: ["3...", "33..", "333.", "3333", "333.", "33..", "3..."]
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 18
                            anchors.right: row_lv.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: row.modelData.label
                            color: Style.text_fg
                            font.family: Style.font_family
                            font.pixelSize: 14
                        }

                        Text {
                            id: row_lv
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: ":L" + (row.modelData.i + 1)
                            color: Style.text_muted
                            font.family: Style.font_family
                            font.pixelSize: 14
                        }
                    }

                    Item {
                        y: 18
                        x: 18
                        width: parent.width - 18
                        height: 14

                        Text {
                            id: hp_label
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "HP:"
                            color: Style.text_fg
                            font.family: Style.font_family
                            font.pixelSize: 12
                        }

                        Rectangle {
                            id: hp_bar
                            anchors.left: hp_label.right
                            anchors.leftMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            width: 140
                            height: 8
                            radius: 4
                            color: "transparent"
                            border.width: 1
                            border.color: Style.picker_shades[2]

                            Rectangle {
                                x: 1
                                y: 1
                                width: Math.max(0, Math.round((hp_bar.width - 2) * Math.min(1, row.ratio)))
                                height: hp_bar.height - 2
                                radius: 3
                                color: root.hp_color(row.ratio)
                            }
                        }

                        Text {
                            anchors.left: hp_bar.right
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.size_label(row.modelData.rect)
                            color: Style.text_muted
                            font.family: Style.font_family
                            font.pixelSize: 12
                        }
                    }
                }
            }

            Item {
                width: parent.width
                height: 8

                Column {
                    y: 3
                    width: parent.width
                    spacing: 2

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Style.picker_shades[1]
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Style.picker_shades[1]
                    }
                }
            }

            Text {
                text: root.full ? "Choose a screen." : "Choose a window."
                color: Style.text_fg
                font.family: Style.font_family
                font.pixelSize: 14
            }
        }
    }
}

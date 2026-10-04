// home/quickshell/.config/quickshell/components/picker/loupe/Tiecomp.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../../theme"
import "../../../services"
import "../.."
import ".."

Item {
    id: root

    required property var loupe
    readonly property real gap: 32
    readonly property real flip_gap: root.loupe.gap
    readonly property bool own_readout: false
    implicitWidth: root.tc_width
    implicitHeight: root.tc_pad_y * 2 + root.tc_header_h + root.tc_lens_gap * 2 + root.loupe.view + tc_rows_col.implicitHeight

    readonly property real tc_pad_x: 22
    readonly property real tc_pad_y: 18
    readonly property real tc_header_h: 22
    readonly property real tc_lens_gap: 8
    readonly property real tc_row_h: 18
    readonly property var tc_rows: {
        const rows = root.loupe.pixel_mode ? [
            { label: "SHLD", value: String(root.loupe.rgb[0]), ratio: root.loupe.rgb[0] / 255, bar: true, color: Theme.red },
            { label: "HULL", value: String(root.loupe.rgb[1]), ratio: root.loupe.rgb[1] / 255, bar: true, color: Theme.green },
            { label: "SYS", value: String(root.loupe.rgb[2]), ratio: root.loupe.rgb[2] / 255, bar: true, color: Theme.blue }
        ] : [
            { label: "POS", value: Math.round(root.loupe.screen_x + root.loupe.at.x) + "," + Math.round(root.loupe.screen_y + root.loupe.at.y), bar: false, color: Theme.green },
            { label: "SIZE", value: Math.round(root.loupe.sel.width) + "x" + Math.round(root.loupe.sel.height), bar: false, color: Theme.green }
        ];
        rows.push({ label: "RNG", value: root.loupe.zoom + ".0", bar: false, color: Theme.green });
        return rows;
    }
    readonly property real tc_width: Math.max(252, root.loupe.view + root.tc_pad_x * 2)

    OctagonFrame {
        anchors.fill: parent
    }

    LoupeLens {
        id: lens
        loupe: root.loupe
        x: root.tc_pad_x
        y: root.tc_pad_y + root.tc_header_h + root.tc_lens_gap
        center_color: Theme.red

        Repeater {
            model: Math.ceil(root.loupe.view / 3)

            Rectangle {
                required property int index
                y: index * 3
                width: root.loupe.view
                height: 1
                color: Qt.alpha(Theme.green, 0.05)
            }
        }

        CornerBrackets {
            anchors.fill: parent
            color: Theme.green
            inset: 4
            arm: 14
            thickness: 1.5
            all_corners: true
        }
    }

    Text {
        id: tc_header
        x: root.tc_pad_x
        y: root.tc_pad_y
        text: root.loupe.pixel_mode ? "TGT " + (Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : "#------") : root.loupe.has_sel ? "TGT " + Math.round(root.loupe.sel.width) + "x" + Math.round(root.loupe.sel.height) : "TGT AREA"
        color: Theme.green
        font.family: Style.title_font_family
        font.bold: true
        font.pixelSize: 15
        font.letterSpacing: 1
    }

    Column {
        id: tc_rows_col
        x: root.tc_pad_x
        y: root.tc_pad_y + root.tc_header_h + root.loupe.view + root.tc_lens_gap * 2
        width: root.tc_width - root.tc_pad_x * 2
        spacing: 0

        Repeater {
            model: root.tc_rows

            Item {
                id: tc_row
                required property var modelData
                width: tc_rows_col.width
                height: root.tc_row_h

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    text: tc_row.modelData.label
                    color: tc_row.modelData.color
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-6)
                }

                Text {
                    id: tc_value
                    anchors.right: parent.right
                    width: tc_row.modelData.bar ? 30 : 90
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: tc_row.modelData.value
                    color: tc_row.modelData.color
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-6)
                }

                Text {
                    visible: tc_row.modelData.bar
                    readonly property int filled: Math.round(Math.max(0, Math.min(1, tc_row.modelData.ratio)) * 10)
                    anchors.left: parent.left
                    anchors.leftMargin: 44
                    anchors.right: tc_value.left
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    clip: true
                    text: "▮".repeat(filled) + "▯".repeat(10 - filled)
                    color: tc_row.modelData.color
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-6)
                }
            }
        }
    }
}

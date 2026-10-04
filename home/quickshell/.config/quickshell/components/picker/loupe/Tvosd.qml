// home/quickshell/.config/quickshell/components/picker/loupe/Tvosd.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../../theme"
import "../../../services"
import ".."

Item {
    id: root

    required property var loupe
    readonly property real gap: 32
    readonly property real flip_gap: root.loupe.gap
    readonly property bool own_readout: false
    implicitWidth: root.tv_width
    implicitHeight: root.tv_pad_y * 2 + root.tv_header_h + root.tv_lens_gap * 2 + root.loupe.view + tv_rows_col.implicitHeight

    readonly property real tv_pad_x: 14
    readonly property real tv_pad_y: 10
    readonly property real tv_header_h: 34
    readonly property real tv_lens_gap: 8
    readonly property var tv_rows: {
        const rows = root.loupe.pixel_mode ? [
            { label: "RED", value: root.loupe.rgb[0], ratio: root.loupe.rgb[0] / 255, color: Theme.red },
            { label: "GREEN", value: root.loupe.rgb[1], ratio: root.loupe.rgb[1] / 255, color: Theme.bright_green },
            { label: "BLUE", value: root.loupe.rgb[2], ratio: root.loupe.rgb[2] / 255, color: Theme.blue }
        ] : [
            { label: "H POS", value: Math.round(root.loupe.at.x), ratio: root.loupe.at.x / root.loupe.area_width, color: Theme.green },
            { label: "V POS", value: Math.round(root.loupe.at.y), ratio: root.loupe.at.y / root.loupe.area_height, color: Theme.green }
        ];
        rows.push({ label: "VOL", value: root.loupe.zoom + "x", ratio: 0, vol: true, color: Theme.green });
        return rows;
    }
    readonly property real tv_width: Math.max(290, root.loupe.view + root.tv_pad_x * 2)

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Theme.bg_shadow, 0.72)
    }

    LoupeLens {
        id: lens
        loupe: root.loupe
        x: root.tv_pad_x
        y: root.tv_pad_y + root.tv_header_h + root.tv_lens_gap
        center_color: Theme.bright_green
    }

    Rectangle {
        x: lens.x - 5
        y: lens.y - 5
        width: lens.width + 10
        height: lens.height + 10
        color: "transparent"
        border.width: 6
        border.color: Qt.alpha(Theme.green, 0.25)
    }

    Rectangle {
        x: lens.x - 2
        y: lens.y - 2
        width: lens.width + 4
        height: lens.height + 4
        color: "transparent"
        border.width: 2
        border.color: Theme.green
    }

    Text {
        id: tv_header
        x: root.tv_pad_x
        y: root.tv_pad_y
        text: root.loupe.pixel_mode ? "COLOUR " + (Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : "#------") : root.loupe.has_sel ? "ZOOM " + Math.round(root.loupe.sel.width) + "x" + Math.round(root.loupe.sel.height) : "ZOOM"
        color: Theme.green
        style: Text.Outline
        styleColor: Qt.alpha(Theme.green, 0.6)
        font.family: Style.font_family
        font.pixelSize: 30
    }

    Column {
        id: tv_rows_col
        x: root.tv_pad_x
        y: root.tv_pad_y + root.tv_header_h + root.loupe.view + root.tv_lens_gap * 2
        width: root.tv_width - root.tv_pad_x * 2
        spacing: 0

        Repeater {
            model: root.tv_rows

            Item {
                id: tv_row
                required property var modelData
                width: tv_rows_col.width
                height: 20

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 64
                    text: tv_row.modelData.label
                    color: tv_row.modelData.color
                    style: Text.Outline
                    styleColor: Qt.alpha(tv_row.modelData.color, 0.6)
                    font.family: Style.font_family
                    font.pixelSize: 18
                }

                Text {
                    id: tv_value
                    anchors.right: parent.right
                    width: 44
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: String(tv_row.modelData.value)
                    color: tv_row.modelData.color
                    style: Text.Outline
                    styleColor: Qt.alpha(tv_row.modelData.color, 0.6)
                    font.family: Style.font_family
                    font.pixelSize: 18
                }

                Text {
                    readonly property int filled: tv_row.modelData.vol ? Math.min(10, Screenshot.zoom_index * 2 + 2) : Math.round(Math.max(0, Math.min(1, tv_row.modelData.ratio)) * 10)
                    anchors.left: parent.left
                    anchors.leftMargin: 68
                    anchors.right: tv_value.left
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    clip: true
                    text: "▮".repeat(filled) + "▯".repeat(10 - filled)
                    color: tv_row.modelData.color
                    style: Text.Outline
                    styleColor: Qt.alpha(tv_row.modelData.color, 0.6)
                    font.family: Style.font_family
                    font.pixelSize: 18
                }
            }
        }
    }
}

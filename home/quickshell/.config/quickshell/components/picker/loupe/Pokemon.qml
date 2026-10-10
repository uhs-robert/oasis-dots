// home/quickshell/.config/quickshell/components/picker/loupe/Pokemon.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../../theme"
import "../../../services"
import ".."

Item {
    id: root

    required property var loupe
    readonly property real gap: 34
    readonly property real flip_gap: root.loupe.gap
    readonly property bool own_readout: false
    implicitWidth: root.pk_width
    implicitHeight: root.pk_pad * 2 + root.pk_header_h + root.pk_lens_gap * 2 + root.loupe.view + root.pk_stats_h + root.pk_divider_gap * 2 + root.pk_divider_h + root.pk_msg_h

    readonly property real pk_pad: 10
    readonly property real pk_lens_gap: 8
    readonly property real pk_line_h: 18
    readonly property real pk_divider_gap: 6
    readonly property real pk_divider_h: 4
    readonly property real pk_header_h: root.pk_line_h * 3
    readonly property real pk_msg_h: root.pk_line_h * 2
    readonly property real pk_luma: (root.loupe.rgb[0] * 0.3 + root.loupe.rgb[1] * 0.59 + root.loupe.rgb[2] * 0.11) / 255
    function pk_hp_color(ratio) {
        return ratio > 0.5 ? Theme.green : ratio > 0.2 ? Theme.theme_secondary : Theme.red;
    }
    function pk_pad3(v) {
        return String(Math.max(0, Math.min(999, Math.round(v)))).padStart(3, "0");
    }
    function pk_pad4(v) {
        return String(Math.max(0, Math.round(v))).padStart(4, "0");
    }
    readonly property var pk_rows: {
        if (root.loupe.pixel_mode) return ["RED   " + root.pk_pad3(root.loupe.rgb[0]), "GREEN " + root.pk_pad3(root.loupe.rgb[1]), "BLUE  " + root.pk_pad3(root.loupe.rgb[2])];
        return ["X " + root.pk_pad4(root.loupe.at.x) + " Y " + root.pk_pad4(root.loupe.at.y)];
    }
    readonly property real pk_stats_h: root.pk_rows.length * root.pk_line_h
    readonly property var pk_message: {
        if (root.loupe.pixel_mode) return ["Wild " + (Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : "#------"), "appeared!"];
        if (root.loupe.has_sel) return ["Got a " + Math.round(root.loupe.sel.width) + "x" + Math.round(root.loupe.sel.height), "shot!"];
        return ["Drag to catch", "an area!"];
    }
    readonly property real pk_width: Math.max(250, root.loupe.view + root.pk_pad * 2)

    Rectangle {
        anchors.fill: parent
        color: Style.pixel_shades[0]
        border.width: 2
        border.color: Style.pixel_shades[1]
        antialiasing: false
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 3
        color: "transparent"
        border.width: 2
        border.color: Style.pixel_shades[2]
        antialiasing: false
    }

    LoupeLens {
        id: lens
        loupe: root.loupe
        x: (root.pk_width - root.loupe.view) / 2
        y: root.pk_pad + root.pk_header_h + root.pk_lens_gap
        center_color: Style.pixel_shades[1]
    }

    Rectangle {
        x: lens.x - 3
        y: lens.y - 3
        width: lens.width + 6
        height: lens.height + 6
        color: "transparent"
        border.width: 3
        border.color: Style.pixel_shades[1]
        antialiasing: false
    }

    Column {
        id: pk_header_col
        x: root.pk_pad
        y: root.pk_pad
        width: root.pk_width - root.pk_pad * 2
        spacing: 0

        Text {
            width: parent.width
            height: root.pk_line_h
            text: root.loupe.pixel_mode ? (Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : "#------") : "AREA"
            color: Style.text_fg
            font.family: Style.mono_font
            font.pixelSize: 12
        }

        Item {
            width: parent.width
            height: root.pk_line_h

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: ":L" + root.loupe.zoom
                color: Style.text_fg
                font.family: Style.mono_font
                font.pixelSize: 12
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: !root.loupe.pixel_mode && root.loupe.has_sel
                text: Math.round(root.loupe.sel.width) + "x" + Math.round(root.loupe.sel.height)
                color: Style.text_fg
                font.family: Style.mono_font
                font.pixelSize: 12
            }
        }

        Item {
            id: pk_hp_row
            width: parent.width
            height: root.pk_line_h

            Text {
                id: pk_hp_label
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "HP:"
                color: Style.text_fg
                font.family: Style.mono_font
                font.pixelSize: 12
            }

            Rectangle {
                id: pk_hp_bar
                anchors.left: pk_hp_label.right
                anchors.leftMargin: 6
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 8
                radius: 4
                color: "transparent"
                border.width: 1
                border.color: Style.pixel_shades[1]

                Rectangle {
                    x: 1
                    y: 1
                    width: Math.max(0, Math.round((pk_hp_bar.width - 2) * Math.min(1, root.pk_luma)))
                    height: pk_hp_bar.height - 2
                    radius: 3
                    color: root.pk_hp_color(root.pk_luma)
                }
            }
        }
    }

    Column {
        id: pk_stats_col
        x: root.pk_pad
        y: root.pk_pad + root.pk_header_h + root.pk_lens_gap + root.loupe.view + root.pk_lens_gap
        width: root.pk_width - root.pk_pad * 2
        spacing: 0

        Repeater {
            model: root.pk_rows

            Text {
                required property string modelData
                width: pk_stats_col.width
                height: root.pk_line_h
                text: modelData
                color: Style.text_fg
                font.family: Style.mono_font
                font.pixelSize: 12
            }
        }
    }

    Column {
        id: pk_divider
        x: root.pk_pad
        y: pk_stats_col.y + root.pk_stats_h + root.pk_divider_gap
        width: root.pk_width - root.pk_pad * 2
        spacing: 2

        Rectangle {
            width: parent.width
            height: 1
            color: Style.pixel_shades[1]
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Style.pixel_shades[1]
        }
    }

    Column {
        id: pk_message_col
        x: root.pk_pad
        y: pk_divider.y + root.pk_divider_h + root.pk_divider_gap
        width: root.pk_width - root.pk_pad * 2
        spacing: 0

        Repeater {
            model: root.pk_message

            Text {
                required property string modelData
                width: pk_message_col.width
                height: root.pk_line_h
                text: modelData
                color: Style.text_fg
                font.family: Style.mono_font
                font.pixelSize: 12
            }
        }
    }
}

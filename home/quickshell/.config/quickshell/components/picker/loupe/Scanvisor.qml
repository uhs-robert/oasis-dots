// home/quickshell/.config/quickshell/components/picker/loupe/Scanvisor.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../../theme"
import "../../../services"
import ".."

Item {
    id: root

    required property var loupe
    readonly property real gap: 40
    readonly property real flip_gap: root.loupe.gap
    readonly property bool own_readout: false
    implicitWidth: root.sv_pad * 2 + root.loupe.view
    implicitHeight: root.sv_pad + root.sv_header_h + root.sv_header_gap + root.loupe.view + root.sv_card_gap + sv_card_col.implicitHeight + root.sv_pad

    readonly property real sv_pad: 10
    readonly property real sv_header_h: 18
    readonly property real sv_header_gap: 8
    readonly property real sv_card_gap: 17
    readonly property var sv_rgb: root.loupe.scan_complete ? root.loupe.rgb : [0, 0, 0]

    ScanGlass {
        anchors.fill: parent
        corner: 12
        sheen: true
    }

    LoupeLens {
        id: lens
        loupe: root.loupe
        x: root.sv_pad
        y: root.sv_pad + root.sv_header_h + root.sv_header_gap
        grid_color: Qt.alpha(Theme.cyan, 0.14)
        center_color: root.loupe.scan_complete ? Theme.bright_green : Theme.bright_yellow
    }

    Item {
        id: sv_header
        x: root.sv_pad
        y: root.sv_pad
        width: root.loupe.view
        height: root.sv_header_h

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "SCAN VISOR"
            color: Theme.bright_cyan
            font.family: Style.font_family
            font.pixelSize: Style.fs(-6)
            font.letterSpacing: 1.5
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            Repeater {
                model: Screenshot.zoom_levels

                Rectangle {
                    id: sv_tank
                    required property int modelData
                    width: 9
                    height: 9
                    color: sv_tank.modelData <= root.loupe.zoom ? Theme.bright_cyan : "transparent"
                    border.width: 1
                    border.color: Theme.bright_cyan
                }
            }
        }
    }

    Item {
        id: sv_card
        readonly property real lens_bottom: root.sv_pad + root.sv_header_h + root.sv_header_gap + root.loupe.view
        x: root.sv_pad
        y: sv_card.lens_bottom + root.sv_card_gap
        width: root.loupe.view

        Rectangle {
            x: 0
            y: -(root.sv_card_gap - 6)
            width: parent.width
            height: 1
            color: Qt.alpha(Theme.bright_cyan, 0.25)
        }

        Column {
            id: sv_card_col
            width: sv_card.width
            spacing: 4

            Text {
                text: root.loupe.pixel_mode ? (root.loupe.scan_complete ? "LOGBOOK // PIGMENT" : "SCANNING " + Math.round(root.loupe.scan_step / root.loupe.scan_steps * 100) + "%") : "LOGBOOK // AREA"
                color: root.loupe.pixel_mode ? (root.loupe.scan_complete ? Theme.bright_green : Theme.bright_yellow) : Theme.bright_green
                font.family: Style.font_family
                font.pixelSize: 10
                font.letterSpacing: 1.5
            }

            Row {
                visible: root.loupe.pixel_mode
                spacing: 6

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 12
                    height: 12
                    border.width: 1
                    border.color: Theme.fg_muted
                    color: root.loupe.scan_complete && Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : "transparent"
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.loupe.scan_complete && Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : "#------"
                    color: Theme.fg_strong
                    font.family: Style.number_font
                    font.pixelSize: Style.fs(-3)
                }
            }

            Text {
                visible: !root.loupe.pixel_mode
                text: root.loupe.has_sel ? Math.round(root.loupe.sel.width) + " x " + Math.round(root.loupe.sel.height) : root.loupe.pad4(root.loupe.screen_x + root.loupe.at.x) + " " + root.loupe.pad4(root.loupe.screen_y + root.loupe.at.y)
                color: Theme.fg_strong
                font.family: Style.number_font
                font.pixelSize: Style.fs(-3)
            }

            Repeater {
                model: root.loupe.pixel_mode ? [{ label: "R", value: root.sv_rgb[0], color: Theme.red }, { label: "G", value: root.sv_rgb[1], color: Theme.bright_green }, { label: "B", value: root.sv_rgb[2], color: Theme.blue }] : []

                Item {
                    id: sv_row
                    required property var modelData
                    width: sv_card_col.width
                    height: 12

                    Text {
                        id: sv_row_label
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 10
                        text: sv_row.modelData.label
                        color: Theme.fg_dim
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-7)
                    }

                    Text {
                        id: sv_row_value
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24
                        horizontalAlignment: Text.AlignRight
                        text: root.loupe.scan_complete ? String(sv_row.modelData.value) : "---"
                        color: Theme.fg_strong
                        font.family: Style.mono_font
                        font.pixelSize: Style.fs(-7)
                    }

                    Rectangle {
                        anchors.left: sv_row_label.right
                        anchors.leftMargin: 4
                        anchors.right: sv_row_value.left
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        height: 4
                        color: Qt.alpha(Theme.bg_shadow, 0.7)
                        border.width: 1
                        border.color: Qt.alpha(sv_row.modelData.color, 0.4)

                        Rectangle {
                            x: 1
                            y: 1
                            width: Math.max(0, (parent.width - 2) * (root.loupe.scan_complete ? sv_row.modelData.value / 255 : 0))
                            height: parent.height - 2
                            color: sv_row.modelData.color
                        }
                    }
                }
            }

            Text {
                text: root.loupe.pixel_mode ? "POS " + root.loupe.pad4(root.loupe.screen_x + root.loupe.at.x) + " " + root.loupe.pad4(root.loupe.screen_y + root.loupe.at.y) : root.loupe.has_sel ? "FRAMING" : "STANDBY"
                color: Theme.fg_dim
                font.family: Style.font_family
                font.pixelSize: Style.fs(-7)
            }
        }
    }
}

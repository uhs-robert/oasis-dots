// home/quickshell/.config/quickshell/components/picker/loupe/Nvimfloat.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import "../../../theme"
import "../../../services"
import ".."

Item {
    id: root

    required property var loupe
    readonly property real gap: 30
    readonly property real flip_gap: root.loupe.gap
    readonly property bool own_readout: false
    implicitWidth: root.loupe.view + root.loupe.pad * 2
    implicitHeight: root.loupe.pad + root.header_h + root.loupe.view + root.nv_foot_gap + root.nv_row_h + root.nv_cmd_h + root.loupe.pad

    readonly property real nv_row_h: 20
    readonly property real nv_cmd_h: 18
    readonly property real nv_foot_gap: 4
    readonly property real header_h: 18

    LoupeLens {
        id: lens
        loupe: root.loupe
        x: root.loupe.pad
        y: root.loupe.pad + root.header_h
        center_color: Theme.fg_core
    }

    Rectangle {
        z: -1
        anchors.fill: parent
        radius: 6
        color: Theme.bg_crust
        border.width: 1
        border.color: Theme.theme_primary
    }

    Rectangle {
        x: 12
        y: -1
        width: nv_title_text.implicitWidth + 12
        height: 16
        radius: 3
        color: Theme.theme_secondary

        Text {
            id: nv_title_text
            anchors.centerIn: parent
            text: root.loupe.pixel_mode ? (Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : "#------") : "Region"
            color: Theme.bg_crust
            font.family: Style.mono_font
            font.bold: true
            font.pixelSize: Style.fs(-6)
        }
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: 12
        y: 2
        text: root.loupe.zoom + "x"
        color: Theme.theme_primary_light
        font.family: Style.mono_font
        font.pixelSize: Style.fs(-6)
    }

    Item {
        id: nv_lualine
        x: root.loupe.pad
        y: root.loupe.pad + root.header_h + root.loupe.view + root.nv_foot_gap
        width: root.loupe.view
        height: root.nv_row_h

        readonly property string mode: root.loupe.pixel_mode ? "NORMAL" : root.loupe.has_sel ? "V-BLOCK" : "VISUAL"
        readonly property color mode_color: root.loupe.pixel_mode ? Theme.theme_primary : Theme.magenta

        Rectangle {
            id: nv_mode_chip
            height: parent.height
            width: nv_mode_text.implicitWidth + 16
            color: nv_lualine.mode_color

            Text {
                id: nv_mode_text
                anchors.centerIn: parent
                text: nv_lualine.mode
                color: Theme.bg_crust
                font.family: Style.font_family
                font.bold: true
                font.pixelSize: Style.fs(-7)
            }
        }

        Shape {
            id: nv_mode_arrow
            x: nv_mode_chip.width
            width: 10
            height: nv_lualine.height
            ShapePath {
                fillColor: nv_lualine.mode_color
                strokeWidth: -1
                startX: 0
                startY: 0
                PathLine {
                    x: 10
                    y: nv_lualine.height / 2
                }
                PathLine {
                    x: 0
                    y: nv_lualine.height
                }
                PathLine {
                    x: 0
                    y: 0
                }
            }
        }

        Rectangle {
            visible: root.loupe.pixel_mode
            x: nv_mode_arrow.x + nv_mode_arrow.width
            height: parent.height
            width: 26
            color: Theme.bg_surface

            Rectangle {
                anchors.centerIn: parent
                width: 12
                height: 12
                color: Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : "transparent"
            }
        }

        Text {
            visible: !root.loupe.pixel_mode
            x: nv_mode_arrow.x + nv_mode_arrow.width + 6
            anchors.verticalCenter: parent.verticalCenter
            text: "▦"
            color: Theme.theme_primary_light
            font.pixelSize: Style.fs(-6)
        }

        Text {
            id: nv_z_text
            anchors.right: parent.right
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: Math.round(root.loupe.at.y) + ":" + Math.round(root.loupe.at.x)
            color: Theme.bg_crust
            font.family: Style.mono_font
            font.bold: true
            font.pixelSize: Style.fs(-7)

            Rectangle {
                z: -1
                anchors.fill: parent
                anchors.leftMargin: -8
                color: Theme.theme_primary_strong
            }
        }
    }

    Row {
        id: nv_cmdline
        x: root.loupe.pad
        y: nv_lualine.y + nv_lualine.height + 2
        width: root.loupe.view
        height: root.nv_cmd_h
        spacing: 4

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.loupe.pixel_mode ? ":hi" : root.loupe.has_sel ? ":'<,'>" : ":"
            color: Theme.magenta
            font.family: Style.mono_font
            font.pixelSize: Style.fs(-6)
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.loupe.pixel_mode ? "Pick" : "Screenshot"
            color: Theme.fg_core
            font.family: Style.mono_font
            font.pixelSize: Style.fs(-6)
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.loupe.pixel_mode ? "guifg=" + (Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : "#------") : root.loupe.has_sel ? Math.round(root.loupe.sel.width) + "x" + Math.round(root.loupe.sel.height) : ""
            color: Theme.theme_secondary
            font.family: Style.mono_font
            font.pixelSize: Style.fs(-6)
        }
    }
}

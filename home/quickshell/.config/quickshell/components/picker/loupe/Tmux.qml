// home/quickshell/.config/quickshell/components/picker/loupe/Tmux.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../../theme"
import "../../../services"
import ".."

Item {
    id: root

    required property var loupe
    readonly property real gap: 30
    readonly property real flip_gap: root.loupe.gap
    readonly property bool own_readout: false
    implicitWidth: root.tmux_w
    implicitHeight: root.tmux_pad * 2 + root.tmux_line_h * 3 + root.tmux_gap * 2 + root.loupe.view

    readonly property real tmux_pad: 10
    readonly property real tmux_line_h: 18
    readonly property real tmux_gap: 6
    readonly property real tmux_w: Math.max(220, root.loupe.view + root.tmux_pad * 2)

    Rectangle {
        anchors.fill: parent
        color: Theme.bg_crust
        border.width: 1
        border.color: Theme.green
    }

    Rectangle {
        x: tmux_title.x - 3
        y: tmux_title.y
        width: tmux_title.implicitWidth + 6
        height: tmux_title.implicitHeight
        color: Theme.bg_crust
    }

    Text {
        id: tmux_title
        x: 10
        y: -tmux_title.implicitHeight / 2
        text: "[0] pick"
        color: Theme.green
        font.family: Style.font_family
        font.pixelSize: Style.fs(-6)
    }

    LoupeLens {
        id: lens
        loupe: root.loupe
        x: root.tmux_pad
        y: root.tmux_pad + root.tmux_line_h + root.tmux_gap
        center_color: Theme.ui_match_bg
    }

    Row {
        id: tmux_cmd_line
        x: root.tmux_pad
        y: root.tmux_pad
        height: root.tmux_line_h
        spacing: 4

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "$"
            color: Theme.green
            font.family: Style.mono_font
            font.pixelSize: 12
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "pick --at " + Math.round(root.loupe.screen_x + root.loupe.at.x) + "," + Math.round(root.loupe.screen_y + root.loupe.at.y) + " --zoom " + root.loupe.zoom
            color: Theme.fg_strong
            font.family: Style.mono_font
            font.pixelSize: 12
        }
    }

    Row {
        id: tmux_output_line
        visible: root.loupe.pixel_mode
        x: root.tmux_pad
        y: root.tmux_pad + root.tmux_line_h + root.tmux_gap + root.loupe.view + root.tmux_gap
        height: root.tmux_line_h
        spacing: 8

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : "#------"
            color: Theme.fg_strong
            font.family: Style.mono_font
            font.pixelSize: 12
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "rgb(" + root.loupe.rgb[0] + " " + root.loupe.rgb[1] + " " + root.loupe.rgb[2] + ")"
            color: Theme.fg_dim
            font.family: Style.mono_font
            font.pixelSize: 12
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "██"
            color: Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : Theme.fg_dim
            font.family: Style.mono_font
            font.pixelSize: 12
        }
    }

    Text {
        id: tmux_region_line
        visible: !root.loupe.pixel_mode
        x: root.tmux_pad
        y: root.tmux_pad + root.tmux_line_h + root.tmux_gap + root.loupe.view + root.tmux_gap
        height: root.tmux_line_h
        text: root.loupe.has_sel ? Math.round(root.loupe.sel.width) + "x" + Math.round(root.loupe.sel.height) + "  +" + Math.round(root.loupe.sel.x) + "," + Math.round(root.loupe.sel.y) : "drag to select"
        color: root.loupe.has_sel ? Theme.fg_strong : Theme.fg_dim
        font.family: Style.mono_font
        font.pixelSize: 12
    }

    Row {
        id: tmux_prompt_line
        x: root.tmux_pad
        y: root.tmux_pad + root.tmux_line_h * 2 + root.tmux_gap * 2 + root.loupe.view
        height: root.tmux_line_h
        spacing: 4

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "$ "
            color: Theme.green
            font.family: Style.mono_font
            font.pixelSize: 12
        }

        Rectangle {
            id: tmux_prompt_block
            anchors.verticalCenter: parent.verticalCenter
            width: 7
            height: 13
            color: Theme.fg_core

            Timer {
                running: tmux_prompt_line.visible
                interval: 500
                repeat: true
                onTriggered: tmux_prompt_block.opacity = tmux_prompt_block.opacity > 0 ? 0 : 1
            }
        }
    }
}

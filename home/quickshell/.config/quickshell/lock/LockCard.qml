// home/quickshell/.config/quickshell/lock/LockCard.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../theme"
import "../components"
import "../components/neovim" as Neovim

// A floating frame in the active style, titled like the OSD, around a column of content.
Item {
    id: root

    property string title: "LOCKED"
    property real body_width: Style.px(360)
    default property alias content: body.data

    readonly property int pad_x: Style.px(22)
    readonly property int pad_y: Style.px(16)
    readonly property bool banded: Style.show_title && (Style.title_band.a > 0 || Style.title_strip.a > 0)
    readonly property real float_top: Style.border_title && Style.show_title ? Math.round(title_tab.height / 2) : 0

    implicitWidth: frame.width
    implicitHeight: frame.height + root.float_top

    Rectangle {
        visible: Style.frame_drop > 0
        x: frame.x
        y: frame.y + Style.frame_drop
        width: frame.width
        height: frame.height
        radius: frame.radius
        color: Style.frame_shadow.a > 0 ? Style.frame_shadow : Theme.bg_shadow
    }

    Loader {
        active: Style.border_title
        x: 0
        y: 0
        width: frame.width
        height: frame.height + root.float_top
        sourceComponent: Neovim.FloatFrame {
            title: Style.show_title ? Style.title_text(root.title) : ""
            chip_height: root.float_top * 2
            radius: Style.frame_radius
        }
    }

    Rectangle {
        id: frame

        readonly property real top_rule: Style.frame_top_rule ? Style.accent_height : 0
        readonly property real band_height: Math.max(26, title_tab.height + 4)
        readonly property real header_height: !title_tab.visible ? 0 : root.banded ? frame.band_height + 4 + Style.inset_pad : Style.border_title ? root.float_top : title_tab.height + frame.top_rule + Style.inset_pad

        y: root.float_top
        width: Math.max(root.body_width + root.pad_x * 2, title_tab.visible ? title_tab.width + Style.inset_pad * 2 : 0)
        height: frame.header_height + body.implicitHeight + root.pad_y * 2 + Style.inset_pad + Style.slant_room
        radius: Style.frame_radius
        color: Style.frame_chamfer > 0 || Style.frame_visor || Style.custom_frame || Style.border_title ? "transparent" : Style.frame_follows_island ? Theme.bg_core : Style.frame_color
        border.width: Style.frame_visor || Style.frame_chamfer > 0 || Style.custom_frame || Style.border_title ? 0 : Style.frame_border_width
        border.color: Style.frame_border_color

        VisorGlass {
            anchors.fill: parent
        }

        FrameShade {
            anchors.fill: parent
            anchors.margins: Style.frame_border_width
            top_radius: Math.max(0, frame.radius - Style.frame_border_width)
            bottom_radius: top_radius
            chamfer: Style.frame_chamfer
        }

        CustomFrame {
            anchors.fill: parent
        }

        FrameInset {
            top_radius: frame.radius
            bottom_radius: frame.radius
        }

        Sheen {
            color_top: Style.frame_float > 0 ? Style.sheen : "transparent"
            corner: frame.radius
            edge: Style.frame_border_width
        }

        Rectangle {
            visible: Style.frame_top_rule
            x: Style.frame_border_width
            y: Style.frame_border_width
            width: frame.width - Style.frame_border_width * 2
            height: Style.accent_height
            color: Style.accent_color
        }

        // Static scanlines; nothing animates them.
        Repeater {
            model: Style.scanlines && Style.frame_octagon <= 0 ? Math.ceil(frame.height / Style.scanline_period) : 0

            Rectangle {
                required property int index
                y: index * Style.scanline_period
                width: frame.width
                height: 1
                color: Style.scanline_color
            }
        }

        Dither {
            anchors.fill: parent
            anchors.margins: Style.frame_border_width
            color: Style.dither
            radius: frame.radius
            top_radius: frame.radius
        }

        Loader {
            active: root.banded
            x: Style.inset_pad + Style.frame_border_width
            y: x
            width: frame.width - x * 2
            height: frame.band_height
            sourceComponent: Style.title_strip.a > 0 ? lock_strip : lock_header

            Component {
                id: lock_header
                TabHeader {
                    readonly property var ids: Style.title_ids.lock || []
                    title: root.title
                    panel_id: ids[0] || ""
                    readout: ids[1] || ""
                }
            }

            Component {
                id: lock_strip
                TitleStrip {
                    title: root.title
                    closable: false
                }
            }
        }

        Rectangle {
            id: title_tab
            visible: Style.show_title
            opacity: root.banded || Style.border_title ? 0 : 1
            x: (Style.rounded ? frame.radius : 0) + Style.inset_pad
            y: frame.top_rule + Style.inset_pad
            width: title_text.implicitWidth + 20
            height: title_text.implicitHeight + 4
            color: Style.title_bg

            Text {
                id: title_text
                anchors.centerIn: parent
                text: Style.title_prefix + Style.title_text(root.title) + Style.title_suffix
                color: Style.title_fg
                font.family: Style.title_font_family
                font.pixelSize: Style.title_size > 0 ? Style.title_size : Style.fs(-2)
                font.weight: Style.title_weight > 0 ? Style.title_weight : Style.title_font_family === Style.font_family ? Font.Bold : Font.Normal
                font.letterSpacing: Style.title_spacing
            }
        }

        ColumnLayout {
            id: body
            x: root.pad_x
            y: frame.header_height + root.pad_y
            width: frame.width - root.pad_x * 2
            spacing: Style.px(12)
        }
    }
}

// home/quickshell/.config/quickshell/overview/OverviewFrame.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import "../components"
import "../theme"
import "../components/neovim" as Neovim

// The active style's panel around the overview: its frame, title, a status readout and the key footer.
Rectangle {
    id: root

    property string title: ""
    property string status: ""
    property color status_color: Style.text_muted
    property string footer: ""
    default property alias content: body_area.data
    readonly property alias body: body_area

    readonly property int pad_x: Style.px(18)
    readonly property int pad_y: Style.px(12)
    readonly property real top_edge: Math.max(Style.accent_height, Style.frame_border_width)
    readonly property bool banded: Style.show_title && (Style.title_band.a > 0 || Style.title_strip.a > 0)
    readonly property bool float_title: Style.border_title && Style.show_title
    readonly property real band_height: Math.max(26, title_tab.height + 4)
    readonly property real header_height: root.banded ? root.band_height + 4 + Style.inset_pad : root.float_title ? Math.round(title_tab.height / 2) : title_tab.height + Math.max(0, Style.inset_pad - Style.frame_border_width)
    readonly property real footer_height: Style.show_footer && root.footer !== "" ? footer_line.implicitHeight + Style.px(10) : 0
    readonly property int text_style: Style.glow ? Text.Outline : Style.text_shadow.a > 0 ? Text.Raised : Text.Normal
    readonly property color text_glow: Style.glow ? Qt.alpha(Theme.theme_primary, 0.3) : Style.text_shadow

    radius: Style.frame_radius
    color: Style.frame_chamfer > 0 || Style.frame_visor || Style.custom_frame ? "transparent" : Style.frame_follows_island ? Theme.bg_mantle : Style.frame_color
    border.width: Style.frame_visor || Style.frame_chamfer > 0 || Style.custom_frame ? 0 : Style.frame_border_width
    border.color: Style.frame_border_color

    // Swallows clicks on the frame so only the scrim around it closes the overview.
    MouseArea {
        anchors.fill: parent
    }

    VisorGlass {
        anchors.fill: parent
    }

    Shape {
        id: frame_glow
        visible: Style.frame_glow.a > 0
        anchors.fill: parent
        anchors.margins: Style.frame_border_width

        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: frame_glow.width / 2
                centerY: 0
                focalX: frame_glow.width / 2
                focalY: 0
                centerRadius: Math.max(frame_glow.width * 0.6, Math.min(frame_glow.height, 420))
                focalRadius: 0
                GradientStop { position: 0; color: Style.frame_glow }
                GradientStop { position: 0.72; color: Style.frame_color }
            }
            PathRectangle { width: frame_glow.width; height: frame_glow.height }
        }
    }

    FrameShade {
        anchors.fill: parent
        anchors.margins: Style.frame_border_width
        top_radius: Math.max(0, root.radius - Style.frame_border_width)
        bottom_radius: top_radius
        chamfer: Style.frame_chamfer
    }

    CustomFrame {
        anchors.fill: parent
    }

    FrameInset {
        top_radius: root.radius
        bottom_radius: root.radius
        top_offset: root.top_edge - Style.frame_border_width
    }

    Sheen {
        color_top: Style.frame_float > 0 ? Style.sheen : "transparent"
        corner: root.radius
        edge: Style.frame_border_width
    }

    Rectangle {
        x: root.radius
        width: root.width - root.radius * 2
        height: Style.accent_height
        color: Style.accent_color
    }

    // Static scanlines under the content; nothing animates them.
    Item {
        visible: Style.scanlines && Style.frame_octagon <= 0
        anchors.fill: parent
        anchors.margins: root.radius > 0 ? Style.frame_border_width : 0
        clip: true

        Repeater {
            model: Style.scanlines && Style.frame_octagon <= 0 ? Math.max(0, Math.ceil(parent.height / Style.scanline_period)) : 0

            Rectangle {
                required property int index
                y: index * Style.scanline_period
                width: parent.width
                height: 1
                color: Style.scanline_color
            }
        }
    }

    Dither {
        anchors.fill: parent
        anchors.margins: Style.frame_border_width
        color: Style.dither
        radius: root.radius
        top_radius: root.radius
    }

    Loader {
        id: band_loader
        active: root.banded
        x: Style.inset_pad + Style.frame_border_width
        y: x
        width: root.width - x * 2
        height: root.band_height
        sourceComponent: Style.title_strip.a > 0 ? title_strip : tab_header

        Component {
            id: tab_header
            TabHeader {
                readonly property var ids: Style.title_ids.overview || []
                title: root.title
                panel_id: ids[0] || ""
                readout: ids[1] || ""
                readout_value: root.status
            }
        }

        Component {
            id: title_strip
            TitleStrip {
                title: root.title
                readout_value: root.status
                closable: false
            }
        }
    }

    Rectangle {
        id: title_tab
        opacity: root.banded || root.float_title ? 0 : 1
        x: (Style.fade_fills || Style.rounded && !Style.title_case ? root.radius : 0) + Style.inset_pad
        y: root.top_edge + Math.max(0, Style.inset_pad - Style.frame_border_width)
        width: Style.fade_fills ? root.width / 3 : title_text.implicitWidth + 20
        height: title_text.implicitHeight + 4
        color: !Style.show_title || Style.fade_fills ? "transparent" : Style.title_bg

        FadeFill {
            visible: Style.show_title && Style.fade_fills
            fill: Style.title_bg
        }

        Text {
            id: title_text
            x: 10
            y: (parent.height - height) / 2
            text: Style.title_prefix + Style.title_text(root.title) + (Style.caret_phase ? Style.title_suffix : " ".repeat(Style.title_suffix.length))
            color: Style.show_title ? Style.title_fg : Style.accent_color
            font.family: Style.title_font_family
            font.pixelSize: Style.title_size > 0 ? Style.title_size : Style.fs(-2)
            font.weight: Style.title_weight > 0 ? Style.title_weight : Style.title_font_family === Style.font_family ? Font.Bold : Font.Normal
            font.letterSpacing: Style.show_title ? Style.title_spacing : 0
            style: root.text_style
            styleColor: root.text_glow
        }
    }

    Loader {
        active: root.float_title
        x: 12
        y: -Math.round(title_tab.height / 2)
        sourceComponent: Neovim.BorderTitle {
            title: Style.title_text(root.title)
        }
    }

    Text {
        visible: !root.banded && root.status !== ""
        anchors.right: parent.right
        anchors.rightMargin: root.pad_x + Style.inset_pad
        y: root.float_title ? root.top_edge + 4 : title_tab.y + (title_tab.height - height) / 2
        text: root.status
        color: root.status_color
        font.family: Style.mono_font
        font.pixelSize: Style.fs(-3)
        style: root.text_style
        styleColor: root.text_glow
    }

    Item {
        id: body_area
        clip: true
        x: root.pad_x + Style.inset_pad
        y: root.top_edge + root.header_height + root.pad_y
        width: root.width - x * 2
        height: root.height - y - root.footer_height - root.pad_y - Style.inset_pad - Style.slant_room
    }

    MenuFooter {
        id: footer_line
        visible: root.footer_height > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.pad_x + Style.inset_pad
        anchors.rightMargin: root.pad_x + Style.inset_pad
        anchors.bottomMargin: Style.px(8) + Style.inset_pad + Style.slant_room
        centered: true
        text: root.footer
    }
}

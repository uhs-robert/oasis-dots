import QtQuick
import qs.ui.effects
import qs.ui.frames
import qs.theme

// One tab hanging from the center island's line (or standing on it over a bottom bar): a Hyprland submap or a voice mode.
Item {
    id: root

    property string name: ""
    property color tint: Theme.theme_secondary
    // 0 slid into the line out of sight, 1 fully out.
    property real progress: 0
    property bool rises: false

    visible: root.progress > 0
    width: tab.width
    height: tab.height
    clip: true

    Rectangle {
        id: tab
        // Styles with a clear title show the tint on the text instead of the fill.
        readonly property bool filled: !Style.show_title || Style.title_bg.a > 0

        y: (root.rises ? height : -height) * (1 - root.progress)
        width: label.implicitWidth + 20 + Style.inset_pad * 2
        height: label.implicitHeight + (Style.show_title ? 4 : 2) + Style.inset_pad * 2
        topLeftRadius: root.rises ? Style.radius(6) : 0
        topRightRadius: root.rises ? Style.radius(6) : 0
        bottomLeftRadius: root.rises ? 0 : Style.radius(6)
        bottomRightRadius: root.rises ? 0 : Style.radius(6)
        color: tab.filled ? root.tint : Style.frame_color
        border.width: Style.show_title ? Style.frame_border_width : 0
        border.color: Style.frame_border_color

        Text {
            id: label
            anchors.centerIn: parent
            text: Style.show_title ? Style.title_prefix + root.name.toUpperCase() + Style.title_suffix : root.name
            color: tab.filled ? Theme.bg_core : root.tint
            font.family: Style.font_family
            font.pixelSize: Style.show_title ? Style.font_size - 2 : Style.bar_font_size
            font.bold: true
            font.letterSpacing: Style.show_title ? Style.title_spacing : 0
            style: Style.glow ? Text.Outline : Text.Normal
            styleColor: Qt.alpha(root.tint, 0.35)
        }

        // Static scanlines; nothing animates them.
        Scanlines {
            visible: Style.scanlines
            anchors.fill: parent
            color: Qt.alpha(root.tint, 0.08)
            period: Style.scanline_period
        }

        // Under a capsule the tab's border on the line side gives way so its fill meets the line.
        Rectangle {
            visible: Style.bar_capsule > 0 && tab.border.width > 0
            x: tab.border.width
            width: tab.width - tab.border.width * 2
            y: root.rises ? tab.height - tab.border.width : 0
            height: tab.border.width
            color: tab.color
        }

        FrameInset {
            edge: tab.border.width
            top_radius: tab.topLeftRadius
            bottom_radius: tab.bottomLeftRadius
        }
    }
}

// home/quickshell/.config/quickshell/bar/ModeTab.qml
import QtQuick
import "../components"
import "../theme"

// One tab hanging from the center island's line: a Hyprland submap or a voice mode.
Item {
    id: root

    property string name: ""
    property color tint: Theme.theme_secondary
    // 0 slid up out of sight, 1 fully down.
    property real progress: 0

    visible: root.progress > 0
    width: tab.width
    height: tab.height
    clip: true

    Rectangle {
        id: tab
        // Styles with a clear title show the tint on the text instead of the fill.
        readonly property bool filled: !Style.show_title || Style.title_bg.a > 0

        y: -height * (1 - root.progress)
        width: label.implicitWidth + 20 + Style.inset_pad * 2
        height: label.implicitHeight + (Style.show_title ? 4 : 2) + Style.inset_pad * 2
        bottomLeftRadius: Style.radius(6)
        bottomRightRadius: Style.radius(6)
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

        // Under a capsule the tab's top border gives way so its fill meets the line.
        Rectangle {
            visible: Style.bar_capsule > 0 && tab.border.width > 0
            x: tab.border.width
            width: tab.width - tab.border.width * 2
            height: tab.border.width
            color: tab.color
        }

        FrameInset {
            edge: tab.border.width
            bottom_radius: tab.bottomLeftRadius
        }
    }
}

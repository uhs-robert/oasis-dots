// home/quickshell/.config/quickshell/components/BadgedGlyph.qml
import QtQuick
import "../theme"

// A glyph with its count as a small superscript badge at the top right.
Item {
    id: root

    property string glyph: ""
    property string count: ""
    property color tint: Theme.yellow
    // Pango rise in 1/1024pt, for a bobbing glyph (keeptabs' running/done icons).
    property real glyph_rise: 0
    property real glyph_opacity: 1

    readonly property alias glyph_item: glyph_text
    readonly property alias count_item: count_text

    readonly property real badge_size: Style.bar_badge_size
    readonly property real badge_rise: 3
    readonly property real badge_overlap: 1

    implicitWidth: glyph_text.implicitWidth + (count_text.visible ? count_text.implicitWidth - root.badge_overlap : 0)
    implicitHeight: glyph_text.implicitHeight + root.badge_rise

    Text {
        id: glyph_text
        y: root.badge_rise - root.glyph_rise / 1024
        text: root.glyph
        color: root.tint
        font.family: Style.bar_font_family
        style: Style.bar_text_style
        styleColor: Style.bar_glow_color
        font.pixelSize: Style.bar_glyph_size
        opacity: root.glyph_opacity
    }

    Text {
        id: count_text
        visible: root.count !== ""
        x: glyph_text.implicitWidth - root.badge_overlap
        y: 0
        text: root.count
        color: root.tint
        font.family: Style.bar_font_family
        style: Style.bar_text_style
        styleColor: Style.bar_glow_color
        font.pixelSize: root.badge_size
        font.bold: true
    }
}

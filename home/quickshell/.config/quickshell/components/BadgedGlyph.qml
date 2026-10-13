// home/quickshell/.config/quickshell/components/BadgedGlyph.qml
import QtQuick
import "../theme"
import "bar_icons"

// A glyph with its count as a small superscript badge at the top right.
Item {
    id: root

    property string glyph: ""
    property string count: ""
    property color tint: Theme.yellow
    // Pango rise in 1/1024pt, for a bobbing glyph (keeptabs' running/done icons).
    property real glyph_rise: 0
    property real glyph_opacity: 1
    property string icon_name: ""
    property string icon_variant: ""

    readonly property alias glyph_item: glyph_icon
    readonly property alias count_item: count_text

    readonly property real badge_size: Style.bar_badge_size
    readonly property real badge_rise: 3
    // A font glyph's side bearing leaves room for the badge to tuck 1px in; a pixel sprite fills its box to the edge, so the badge steps a sprite pixel clear of it.
    readonly property real badge_overlap: glyph_icon.rows ? -glyph_icon.pixel : 1

    implicitWidth: glyph_icon.implicitWidth + (count_text.visible ? count_text.implicitWidth - root.badge_overlap : 0)
    // Height is the glyph alone so layouts center the glyph; the badge overhangs the top.
    implicitHeight: glyph_icon.implicitHeight

    BarIcon {
        id: glyph_icon
        y: -root.glyph_rise / 1024
        name: root.icon_name
        variant: root.icon_variant
        glyph: root.glyph
        tint: root.tint
        opacity: root.glyph_opacity
    }

    Text {
        id: count_text
        visible: root.count !== ""
        x: glyph_icon.width - root.badge_overlap
        y: -root.badge_rise
        text: root.count
        color: root.tint
        font.family: Style.bar_font_family
        style: Style.bar_text_style
        styleColor: Style.bar_glow_color
        font.pixelSize: root.badge_size
        font.bold: true
    }
}

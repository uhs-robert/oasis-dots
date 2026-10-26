import QtQuick
import qs.theme

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
    // On a side bar the glyph, not glyph plus badge, sits on the column's axis, and the badge stays inside `cross`: tucked at the top right when it fits there, else a line under the glyph.
    property bool vertical: false
    property real cross: 0

    readonly property alias glyph_item: glyph_icon
    readonly property alias count_item: count_text

    readonly property real badge_size: Style.bar_badge_size
    // Drawn icons (sprites, vectors) fill the glyph's full height, so a badge raised as far as a font glyph's would sit on a framed island's top border (NES).
    readonly property real badge_rise: glyph_icon.drawn ? 2 : 3
    // A font glyph's side bearing leaves room for the badge to tuck 1px in; a drawn icon fills its box to the edge, so the badge steps clear of it by the icon's clearance.
    readonly property real badge_overlap: glyph_icon.drawn ? -glyph_icon.clearance : 1

    readonly property bool badge_below: root.vertical && count_text.visible && glyph_icon.implicitWidth - root.badge_overlap + count_text.implicitWidth > (glyph_icon.implicitWidth + root.cross) / 2
    // Vertical: the item is the glyph alone, so the layout centres the glyph and a superscript badge overhangs to its right.
    implicitWidth: glyph_icon.implicitWidth + (count_text.visible && !root.vertical ? count_text.implicitWidth - root.badge_overlap : 0)
    // Height is the glyph alone so layouts center the glyph; the badge overhangs the top, unless it sits under the glyph.
    implicitHeight: glyph_icon.implicitHeight + (root.badge_below ? count_text.implicitHeight + 1 : 0)

    BarIcon {
        id: glyph_icon
        y: -root.glyph_rise / 1024
        name: root.icon_name
        variant: root.icon_variant
        glyph: root.glyph
        ink_centre: root.vertical
        tint: root.tint
        opacity: root.glyph_opacity
    }

    Text {
        id: count_text
        visible: root.count !== ""
        x: root.badge_below ? (glyph_icon.width - count_text.implicitWidth) / 2 : glyph_icon.width - root.badge_overlap
        y: root.badge_below ? glyph_icon.height + 1 : -root.badge_rise
        text: root.count
        color: root.tint
        font.family: Style.bar_font_family
        style: Style.bar_text_style
        styleColor: Style.bar_glow_color
        font.pixelSize: root.badge_size
        font.bold: true
    }
}

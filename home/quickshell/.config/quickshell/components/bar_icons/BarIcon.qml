// home/quickshell/.config/quickshell/components/bar_icons/BarIcon.qml
import QtQuick
import "../../theme"
import ".."
import "IconSets.js" as IconSets

// A bar module's icon: the pixel sprite Style.bar_icon_set draws for `name` and `variant`, else the module's Nerd Font `glyph`.
Item {
    id: root

    property string name: ""
    property string variant: ""
    property string glyph: ""
    property color tint: Theme.theme_primary
    // The sprite's second colour: the style's lightest shade when it defines shades, else a lighter step of the tint.
    property color highlight: Style.shade_0.a > 0 ? Style.pixel_shades[3] : Qt.lighter(root.tint, 1.6)
    property string font_family: Style.bar_font_family
    property int glyph_size: Style.bar_glyph_size

    readonly property var rows: IconSets.sprite(Style.bar_icon_set, root.name, root.variant)
    // A ~9-row sprite spans the glyph's height at a whole pixel size, so it stays crisp.
    readonly property int pixel: Math.max(1, Math.round(root.glyph_size / 9))

    implicitWidth: root.rows && sprite_loader.item ? sprite_loader.item.implicitWidth : glyph_text.implicitWidth
    implicitHeight: root.rows && sprite_loader.item ? sprite_loader.item.implicitHeight : glyph_text.implicitHeight
    width: implicitWidth
    height: implicitHeight

    Text {
        id: glyph_text
        visible: !root.rows
        text: root.glyph
        color: root.tint
        font.family: root.font_family
        style: Style.bar_text_style
        styleColor: Style.bar_glow_color
        font.pixelSize: root.glyph_size
    }

    Loader {
        id: sprite_loader
        active: !!root.rows
        sourceComponent: PixelSprite {
            rows: root.rows
            pixel: root.pixel
            colors: [root.tint, root.highlight]
        }
    }
}

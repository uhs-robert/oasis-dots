// home/quickshell/.config/quickshell/components/bar_icons/BarIcon.qml
import QtQuick
import "../../theme"
import ".."
import "../../theme/icon_sets/IconSets.js" as IconSets

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
    // For an icon whose variant flips often (volume, wifi, battery): the slot is as large as the icon's biggest sprite, so neighbours stay put.
    property bool fixed_slot: false

    readonly property var rows: IconSets.sprite(Style.bar_icon_set, root.name, root.variant)
    // A ~9-row sprite spans the glyph's height at a whole pixel size, so it stays crisp.
    readonly property int pixel: Math.max(1, Math.round(root.glyph_size / 9))

    readonly property var extent: root.fixed_slot ? IconSets.extent(Style.bar_icon_set, root.name) : null

    implicitWidth: !root.rows ? glyph_text.implicitWidth : root.extent ? root.extent.columns * root.pixel : sprite_loader.item ? sprite_loader.item.implicitWidth : 0
    implicitHeight: !root.rows ? glyph_text.implicitHeight : root.extent ? root.extent.rows * root.pixel : sprite_loader.item ? sprite_loader.item.implicitHeight : 0
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
        anchors.centerIn: parent
        active: !!root.rows
        sourceComponent: PixelSprite {
            rows: root.rows
            pixel: root.pixel
            colors: [root.tint, root.highlight]
        }
    }
}

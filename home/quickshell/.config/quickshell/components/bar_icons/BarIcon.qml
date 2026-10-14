// home/quickshell/.config/quickshell/components/bar_icons/BarIcon.qml
import QtQuick
import QtQuick.Shapes
import "../../theme"
import ".."
import "../../theme/icon_sets/IconSets.js" as IconSets

// A bar module's icon: the pixel sprite, vector or text (emoji) Style.bar_icon_set draws for `name` and `variant`, else the module's Nerd Font `glyph`.
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
    readonly property var vector: IconSets.vector(Style.bar_icon_set, root.name, root.variant)
    readonly property var text_entry: IconSets.text(Style.bar_icon_set, root.name, root.variant)
    // Whether the set draws this icon (sprite, vector or text) rather than the Nerd Font glyph, which keeps a side bearing a drawn icon lacks.
    readonly property bool drawn: !!root.rows || !!root.vector || !!root.text_entry
    // A ~9-row sprite spans the glyph's height at a whole pixel size, so it stays crisp.
    readonly property int pixel: Math.max(1, Math.round(root.glyph_size / 9))
    // Pixels per viewBox unit, from constants only: a Shape overwrites its own implicit size with its path bounds, so reading it back loops.
    readonly property real unit: root.glyph_size * root.vector_fill / 24
    // The vector's 24-unit height covers this share of glyph_size. Above 1 because a vector's thin strokes carry less ink than a font glyph of the same height.
    readonly property real vector_fill: 1.1
    // How far a count badge stays clear of a drawn icon's edge: one sprite pixel, or the same distance for a vector or emoji.
    readonly property real clearance: root.vector || root.text_entry ? root.glyph_size / 9 : root.pixel
    // A colour emoji's pixelSize is its em box, and the picture fills only part of it; this share of glyph_size makes the picture as tall as a Nerd Font glyph.
    readonly property real text_fill: 0.75
    readonly property int text_size: Math.round(root.glyph_size * root.text_fill)
    readonly property string text_font: root.text_entry && root.text_entry.font ? root.text_entry.font : "Noto Color Emoji"

    readonly property var extent: root.fixed_slot ? IconSets.extent(Style.bar_icon_set, root.name) : null
    readonly property var vector_extent: root.fixed_slot ? IconSets.vector_extent(Style.bar_icon_set, root.name) : null

    // The slot of a text icon is its widest variant's advance by the Nerd Font line height, so swapping to text moves no neighbour vertically.
    implicitWidth: root.text_entry ? (root.fixed_slot ? slot_text.implicitWidth : emoji_text.implicitWidth) : root.vector ? (root.vector_extent ? root.vector_extent.w : root.vector.w) * root.unit : !root.rows ? glyph_text.implicitWidth : root.extent ? root.extent.columns * root.pixel : sprite_loader.item ? sprite_loader.item.implicitWidth : 0
    implicitHeight: root.text_entry ? glyph_text.implicitHeight : root.vector ? (root.vector_extent ? root.vector_extent.h : root.vector.h) * root.unit : !root.rows ? glyph_text.implicitHeight : root.extent ? root.extent.rows * root.pixel : sprite_loader.item ? sprite_loader.item.implicitHeight : 0
    width: implicitWidth
    height: implicitHeight

    Text {
        id: glyph_text
        visible: !root.drawn
        text: root.glyph
        color: root.tint
        font.family: root.font_family
        style: Style.bar_text_style
        styleColor: Style.bar_glow_color
        font.pixelSize: root.glyph_size
    }

    Text {
        id: emoji_text
        visible: !!root.text_entry
        anchors.centerIn: parent
        text: root.text_entry ? root.text_entry.text : ""
        font.family: root.text_font
        font.pixelSize: root.text_size
    }

    // Measures the widest variant so a fixed slot keeps its width across variants.
    Text {
        id: slot_text
        visible: false
        text: root.fixed_slot ? IconSets.widest_text(Style.bar_icon_set, root.name) : ""
        font.family: root.text_font
        font.pixelSize: root.text_size
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

    Shape {
        visible: !!root.vector
        anchors.centerIn: parent
        width: root.vector ? root.vector.w * root.unit : 0
        height: root.vector ? root.vector.h * root.unit : 0
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: root.tint
            strokeColor: "transparent"
            fillRule: root.vector && root.vector.fill_rule === "evenodd" ? ShapePath.OddEvenFill : ShapePath.WindingFill
            scale: Qt.size(root.unit, root.unit)
            PathSvg { path: root.vector && root.vector.body ? root.vector.body : "" }
        }

        ShapePath {
            fillColor: root.highlight
            strokeColor: "transparent"
            fillRule: root.vector && root.vector.fill_rule === "evenodd" ? ShapePath.OddEvenFill : ShapePath.WindingFill
            scale: Qt.size(root.unit, root.unit)
            PathSvg { path: root.vector && root.vector.accent ? root.vector.accent : "" }
        }
    }
}

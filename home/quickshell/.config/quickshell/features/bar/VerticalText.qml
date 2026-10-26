import QtQuick
import QtQuick.Layouts
import qs.theme
import "VerticalLayout.js" as VerticalLayout

// The bar's text. On a side bar it is centred, shrunk to fit `cross` (not below min_size) and, where that would still go
// under min_size, shown as short_text (the number without its unit sign).
// The size and the unit are decided from full_template and short_template, the module's widest values ("100%", "-88°F"),
// not from the live text, so they stay put as the digits change and the modules below do not shift.
Text {
    id: root

    property bool vertical: false
    property real cross: 0
    property string full_text: ""
    property string short_text: ""
    property string full_template: ""
    // Empty when there is no short form: the text then only shrinks.
    property string short_template: ""
    property int base_size: Style.bar_font_size
    property int min_size: VerticalLayout.min_text_px

    // Sized by hand rather than fontSizeMode: Fit would need a height to fit and never reports which text it settled on.
    readonly property var fit: VerticalLayout.fit_text(root.metric(full_probe, root.full_template), root.short_template !== "" ? root.metric(short_probe, root.short_template) : null, root.cross, root.base_size, root.min_size)
    readonly property bool shows_short: root.vertical && root.fit.short
    readonly property string shown_text: root.shows_short ? root.short_text : root.full_text

    // The probes measure at base_size without letter spacing, which is added back as a fixed width per character.
    function metric(probe, template) {
        return { glyph_per_px: probe.advanceWidth / root.base_size, fixed: template.length * root.font.letterSpacing };
    }

    text: root.shown_text
    font.family: Style.bar_font_family
    style: Style.bar_text_style
    styleColor: Style.bar_glow_color
    font.pixelSize: root.vertical ? root.fit.size : root.base_size
    font.capitalization: Style.bar_capitalization
    font.letterSpacing: Style.bar_letter_spacing
    // Left on a top bar: centring there re-rasterised the glyphs by a sub-pixel and broke the pixel-identical top bar.
    horizontalAlignment: root.vertical ? Text.AlignHCenter : Text.AlignLeft
    // What still does not fit at min_size ends in an ellipsis instead of spilling past the island; a clip would cut a digit in half and read as a different number.
    // The cap is cross plus the air (text at min_size may use it, as nes's 9 px "50°" does) and the blank spacing after the last glyph.
    elide: root.vertical ? Text.ElideRight : Text.ElideNone
    Layout.maximumWidth: root.vertical ? root.cross + VerticalLayout.air_px + root.font.letterSpacing : Number.POSITIVE_INFINITY

    TextMetrics {
        id: full_probe
        text: root.full_template
        font.family: root.font.family
        font.pixelSize: root.base_size
        font.capitalization: root.font.capitalization
    }

    TextMetrics {
        id: short_probe
        text: root.short_template
        font.family: root.font.family
        font.pixelSize: root.base_size
        font.capitalization: root.font.capitalization
    }
}

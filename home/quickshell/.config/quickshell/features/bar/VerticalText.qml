import QtQuick
import qs.theme
import "VerticalLayout.js" as VerticalLayout

// The bar's text. On a side bar it is centred, shrunk to fit `cross` (not below min_size) and, where that would still go
// under min_size, shown as short_text (the number without its unit sign).
Text {
    id: root

    property bool vertical: false
    property real cross: 0
    property string full_text: ""
    property string short_text: ""
    property int base_size: Style.bar_font_size
    property int min_size: VerticalLayout.min_text_px

    // Sized by hand rather than fontSizeMode: Fit would need a height to fit and never reports which text it settled on.
    readonly property bool shows_short: root.vertical && root.short_text !== "" && VerticalLayout.too_wide(root.full_text.length, root.advance_per_px, root.cross, root.min_size)
    readonly property string shown_text: root.shows_short ? root.short_text : root.full_text
    readonly property real advance_per_px: probe.advanceWidth / Math.max(1, root.full_text.length) / root.base_size

    text: root.shown_text
    font.family: Style.bar_font_family
    style: Style.bar_text_style
    styleColor: Style.bar_glow_color
    font.pixelSize: root.vertical ? VerticalLayout.fit_size(root.shown_text.length, root.advance_per_px, root.cross, root.base_size, root.min_size) : root.base_size
    font.capitalization: Style.bar_capitalization
    font.letterSpacing: Style.bar_letter_spacing
    // Left on a top bar: centring there re-rasterised the glyphs by a sub-pixel and broke the pixel-identical top bar.
    horizontalAlignment: root.vertical ? Text.AlignHCenter : Text.AlignLeft

    TextMetrics {
        id: probe
        text: root.full_text
        font.family: root.font.family
        font.pixelSize: root.base_size
        font.capitalization: root.font.capitalization
        font.letterSpacing: root.font.letterSpacing
    }
}

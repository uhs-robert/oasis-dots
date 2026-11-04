import QtQuick
import qs.theme
import "AnsiText.js" as AnsiText

// A terminal pane's captured text with its colours, its bottom lines shrunk to fit the pane's full width, for the
// agents and tmux previews.
Item {
    id: root

    // The capture with its escape codes.
    property string pane_text: ""
    // The pane's width in columns; 0 until a capture gives it.
    property int pane_columns: 0

    readonly property real inner_width: root.width - 20
    // The mono font's advance per pixel of size: advances scale with the size, so one measure fits any width. Box
    // drawing is measured too, since a mono font without it falls back to a wider one and a TUI's full-width frame overflows.
    readonly property real advance_ratio: Math.max(reference_metrics.advanceWidth("M"), reference_metrics.advanceWidth("─")) / reference_metrics.font.pixelSize
    // Never smaller than this: a pane too wide to fit at it (an ultrawide's) wraps instead of shrinking out of reading size.
    readonly property int min_font_px: Style.fs(-3)
    // Small enough that the pane's full width fits, with 2% slack for hinting; 0 until a capture gives the width.
    readonly property int fit_px: root.pane_columns > 0 && root.advance_ratio > 0 ? Math.floor(root.inner_width / (root.pane_columns * root.advance_ratio) * 0.98) : 0
    // Capped so a narrow pane in a big preview stays text-sized.
    readonly property int font_px: Math.max(root.min_font_px, Math.min(Style.fs(1), root.fit_px))
    // Columns that fit at the floor, with the same slack; 0 (no wrapping) when the whole width fits, which rounding
    // the same sum back the other way could get one column short of.
    readonly property int wrap_columns: root.fit_px >= root.min_font_px || root.advance_ratio <= 0 ? 0 : Math.max(1, Math.floor(root.inner_width / (root.font_px * root.advance_ratio) * 0.98))
    // A fixed pitch on the text below, so the line count that fits is exact and no half line shows at the top.
    readonly property int line_pitch: Math.ceil(metrics.lineSpacing)
    readonly property int max_lines: Math.max(1, Math.floor((root.height - 20) / root.line_pitch))
    // Kitty's colours, from the raw palette: a style remaps Style.pal, kitty does not follow it.
    readonly property var ansi_palette: [Theme.black, Theme.red, Theme.green, Theme.yellow, Theme.blue, Theme.magenta, Theme.cyan, Theme.white, Theme.bright_black, Theme.bright_red, Theme.bright_green, Theme.bright_yellow, Theme.bright_blue, Theme.bright_magenta, Theme.bright_cyan, Theme.bright_white].map(AnsiText.hex_of)
    readonly property string styled: root.pane_text === "" ? "" : AnsiText.to_styled(AnsiText.bottom_lines(AnsiText.wrap_lines(root.pane_text, root.wrap_columns), root.max_lines), AnsiText.hex_of(Theme.fg_core), root.ansi_palette, AnsiText.hex_of(Theme.bg_core))

    clip: true

    FontMetrics {
        id: reference_metrics
        font.family: Style.mono_font
        font.pixelSize: 100
    }

    FontMetrics {
        id: metrics
        font.family: Style.mono_font
        font.pixelSize: root.font_px
    }

    Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 10
        text: root.styled
        textFormat: Text.StyledText
        wrapMode: Text.NoWrap
        lineHeightMode: Text.FixedHeight
        lineHeight: root.line_pitch
        color: Theme.fg_core
        font.family: Style.mono_font
        font.pixelSize: root.font_px
    }
}

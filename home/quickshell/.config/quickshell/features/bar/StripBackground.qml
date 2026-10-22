import QtQuick
import qs.theme

// The full-bar strip (Island shape "Full bar"): one band across the bar carrying the style's island look, with the
// islands drawing nothing over it. Under the modules, so cava and module fills sit on top of it.
BandFill {
    id: root

    // A screen frame's layout (FrameGeometry.frame_layout) when the strip is its bar edge: the rim and inset line then
    // stop where the hole's corners begin and carry on round them, the strip drawing the part above its open edge.
    property var frame: null

    color: Style.strip_color
    shade_color: Style.frame_shade
    fill_opacity: Style.bar_island_opacity
    border_width: Style.screen_frame_rim
    border_color: Style.bar_border_color
    // As the islands boost it, so the strip's dither reads as theirs did.
    dither_color: Qt.alpha(Style.dither, Math.min(1, Style.dither.a * 2.2))
    scanline_color: Style.bar_scanline_color
    scanline_period: Style.scanline_period
    inset_gap: Style.bar_inset_gap
    inset_width: Style.bar_inset_width
    inset_color: Style.bar_inset_color
    inset_start: root.frame ? root.frame.straight[0] : 0
    inset_end: root.frame ? root.frame.length - root.frame.straight[1] : 0
    ornament: root.frame ? frame_corners : null

    Component {
        id: frame_corners
        FrameStrokes {
            layout: root.frame
            rim_width: Style.screen_frame_rim
            rim_color: Style.bar_border_color
            inset_gap: Style.bar_inset_gap
            inset_width: Style.bar_inset_width
            inset_color: Style.bar_inset_color
        }
    }
}

import QtQuick
import Quickshell.Hyprland
import qs.theme
import "../../ui/frames/FrameGeometry.js" as FrameGeometry

// The full-bar strip (Island shape "Full bar"): one band across the bar carrying the style's island look, with the
// islands drawing nothing over it. Under the modules, so cava and module fills sit on top of it.
BandFill {
    id: root

    // A screen frame's layout (FrameGeometry.frame_layout) when the strip is its bar edge: the rim and inset line then
    // stop where the hole's corners begin and carry on round them, the strip drawing the part above its open edge, the
    // whole line lit on the focused monitor and dim elsewhere, as ScreenFrame's part is.
    property var frame: null
    property string screen_name: ""
    readonly property bool focused: !!Hyprland.focusedMonitor && Hyprland.focusedMonitor.name === root.screen_name
    readonly property bool submap_tint: SubmapState.active && root.focused
    property color frame_rim_color: root.submap_tint ? SubmapState.bar_color : Style.screen_frame_rim_color(root.focused)
    property color frame_inset_color: root.submap_tint ? SubmapState.bar_color : Style.screen_frame_inset_color(root.focused)
    Behavior on frame_rim_color {
        ColorAnimation { duration: 200 }
    }
    Behavior on frame_inset_color {
        ColorAnimation { duration: 200 }
    }

    // A drawer's window over the strip, while it is translucent and reaches the strip: the strip leaves its lines out there (the drawer draws its own).
    line_gaps: FrameGeometry.strip_gaps(ScreenFrames.drawer_rects(root.screen_name), root.edge, root.thickness, root.frame ? root.frame.depth : 0)

    color: Style.strip_color
    shade_color: Style.frame_shade
    fill_opacity: Style.bar_island_opacity
    border_width: Style.bar_border_width
    border_color: root.frame ? root.frame_rim_color : Style.bar_border_color
    // As the islands boost it, so the strip's dither reads as theirs did.
    dither_color: Qt.alpha(Style.dither, Math.min(1, Style.dither.a * 2.2))
    scanline_color: Style.bar_scanline_color
    scanline_period: Style.scanline_period
    inset_gap: Style.bar_inset_gap
    inset_width: Style.bar_inset_width
    inset_color: root.frame ? root.frame_inset_color : Style.bar_inset_color
    inset_start: root.frame ? root.frame.straight[0] : 0
    inset_end: root.frame ? root.frame.length - root.frame.straight[1] : 0
    ornament: root.frame ? frame_corners : null

    Component {
        id: frame_corners
        FrameStrokes {
            layout: root.frame
            rim_width: Style.bar_border_width
            rim_color: root.frame_rim_color
            inset_gap: Style.bar_inset_gap
            inset_width: Style.bar_inset_width
            inset_color: root.frame_inset_color
        }
    }
}

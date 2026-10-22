import QtQuick
import Quickshell.Hyprland
import qs.theme

// The full-bar strip (Island shape "Full bar"): one band across the bar carrying the style's island look, with the
// islands drawing nothing over it. Under the modules, so cava and module fills sit on top of it.
BandFill {
    id: root

    // A screen frame's layout (FrameGeometry.frame_layout) when the strip is its bar edge: the rim and inset line then
    // stop where the hole's corners begin and carry on round them, dimmed, the strip drawing the part above its open
    // edge. Only the straight rim between the corners lights up, and only on the focused monitor.
    property var frame: null
    property string screen_name: ""
    readonly property bool focused: !!Hyprland.focusedMonitor && Hyprland.focusedMonitor.name === root.screen_name
    property color straight_rim_color: root.focused ? Style.bar_border_color : Style.screen_frame_rim_color
    Behavior on straight_rim_color {
        ColorAnimation { duration: 200 }
    }

    color: Style.strip_color
    shade_color: Style.frame_shade
    fill_opacity: Style.bar_island_opacity
    border_width: Style.bar_border_width
    // Under a frame the ornament draws the straight rim, so it can fade into the dim corners.
    border_color: root.frame ? "transparent" : Style.bar_border_color
    // As the islands boost it, so the strip's dither reads as theirs did.
    dither_color: Qt.alpha(Style.dither, Math.min(1, Style.dither.a * 2.2))
    scanline_color: Style.bar_scanline_color
    scanline_period: Style.scanline_period
    inset_gap: Style.bar_inset_gap
    inset_width: Style.bar_inset_width
    inset_color: root.frame ? Style.screen_frame_inset_color : Style.bar_inset_color
    inset_start: root.frame ? root.frame.straight[0] : 0
    inset_end: root.frame ? root.frame.length - root.frame.straight[1] : 0
    ornament: root.frame ? frame_rims : null

    Component {
        id: frame_rims

        Item {
            FrameStrokes {
                layout: root.frame
                rim_width: Style.bar_border_width
                rim_color: Style.screen_frame_rim_color
                inset_gap: Style.bar_inset_gap
                inset_width: Style.bar_inset_width
                inset_color: Style.screen_frame_inset_color
            }

            // Fades from the dim corners to straight_rim_color over one corner radius at each end.
            Rectangle {
                id: straight_rim
                readonly property real fade: width > 0 && root.frame ? Math.min(0.5, root.frame.radius / width) : 0
                x: root.inset_start
                y: root.thickness - Style.bar_border_width
                width: Math.max(0, root.length - root.inset_start - root.inset_end)
                height: Style.bar_border_width
                visible: Style.bar_border_width > 0 && Style.bar_border_color.a > 0
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Style.screen_frame_rim_color }
                    GradientStop { position: straight_rim.fade; color: root.straight_rim_color }
                    GradientStop { position: 1 - straight_rim.fade; color: root.straight_rim_color }
                    GradientStop { position: 1; color: Style.screen_frame_rim_color }
                }
            }
        }
    }
}

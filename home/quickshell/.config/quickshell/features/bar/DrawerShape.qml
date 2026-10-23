import QtQuick
import QtQuick.Shapes
import Quickshell.Hyprland
import qs.theme
import qs.ui.effects
import "DrawerGeometry.js" as Drawer

// A drawer's shape (DrawerGeometry.js) in the screen frame's material: the fill and the frame's rim and inset line
// round it, open on the attached side. It draws nothing outside its surface and nothing inside the body but the fill
// and the frame's dither and scanlines on it.
Item {
    id: root

    required property var layout
    property string screen_name: ""
    // The line is lit on the focused monitor only, switching with the frame's (ScreenFrame).
    readonly property bool focused: !!Hyprland.focusedMonitor && Hyprland.focusedMonitor.name === root.screen_name
    // With translucent islands the fill takes their opacity and covers only the hole, so it never stacks on the frame's
    // own fill; the frame and the strip leave their lines out under the window (ScreenFrames.drawer_windows). Otherwise it
    // is opaque and the cover strip hides the lines.
    property bool translucent: false
    // The screen frame's layout (FrameGeometry.frame_layout). A drawer hung from the bar's own edge continues the strip's
    // shade; on any other edge the frame is flat strip_color, so it stays flat.
    property var frame: null
    readonly property real strip_thickness: root.frame && root.frame.has_bar && Style.strip_shape && Style.frame_shade.a > 0 && root.frame.edge === root.layout.edge ? root.frame.near : 0
    property color fill_color: root.translucent ? Style.island_fill(Style.strip_color) : Style.strip_color
    // Where the drawer's rows lie in the screen frame's canonical frame (Drawer.texture_origin); the dither and
    // scanlines tile from there so they run on from the bands across the join.
    property var texture_origin: ({ x: 0, y: 0, flipped: false })
    // How far from the attached edge the rim and inset line run, for a body that draws its own edge; negative for all.
    property real lines_depth: -1
    property int rim_width: Style.bar_border_width
    property color rim_color: Style.screen_frame_rim_color(root.focused)
    property real inset_gap: Style.bar_inset_gap
    property real inset_width: Style.bar_inset_width
    property color inset_color: Style.screen_frame_inset_color(root.focused)
    Behavior on rim_color {
        ColorAnimation { duration: 200 }
    }
    Behavior on inset_color {
        ColorAnimation { duration: 200 }
    }

    readonly property var fill_points: (root.translucent ? Drawer.hole_fill_loop(root.layout) : Drawer.fill_loop(root.layout))
    readonly property real scanline_period: Style.scanline_period
    readonly property var texture_phase: Drawer.texture_phase(root.texture_origin, root.scanline_period)

    // For the caller's content and input region, in the surface's coordinates.
    readonly property rect body_rect: {
        const r = Drawer.body_rect(root.layout);
        return Qt.rect(r.x, r.y, r.width, r.height);
    }

    implicitWidth: root.layout.surface.width
    implicitHeight: root.layout.surface.height

    Item {
        width: root.layout.length
        height: root.layout.depth
        transform: Matrix4x4 {
            matrix: {
                const m = Drawer.drawer_affine(root.layout);
                return Qt.matrix4x4(m[0], m[2], 0, m[4], m[1], m[3], 0, m[5], 0, 0, 1, 0, 0, 0, 0, 1);
            }
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: -1
                fillColor: root.fill_color
                fillGradient: root.strip_thickness > 0 ? shade : null
                PathPolyline {
                    path: root.fill_points.map(p => Qt.point(p[0], p[1]))
                }
            }

            // The window's top lies `cover` px inside the strip, so the shade starts that far down it and reaches fill_color
            // at the seam, where the strip's own shade ends.
            BandShade {
                id: shade
                shade_color: root.translucent ? Style.island_fill(Style.frame_shade) : Style.frame_shade
                color: root.fill_color
                thickness: root.strip_thickness
                offset: root.strip_thickness - root.layout.cover
            }
        }

        // The bands' texture (ScreenFrame), cut to the fill row by row since the fill is not a rectangle. Under the
        // lines. It tiles from its own origin, so it starts up to one 4 px tile before the drawer to take the phase.
        Loader {
            id: dither_layer
            readonly property real shift_x: root.texture_phase.dither_x
            readonly property real shift_y: root.texture_phase.dither_y
            x: -shift_x
            y: -shift_y
            width: root.layout.length + shift_x
            height: root.layout.depth + shift_y
            active: Style.dither.a > 0
            sourceComponent: Dither {
                row_span: (y0, y1) => {
                    const s = Drawer.fill_row_span(root.fill_points, y0 - dither_layer.shift_y, y1 - dither_layer.shift_y);
                    return { x: s.x + dither_layer.shift_x, w: s.w };
                }
                color: Style.island_fill(Qt.alpha(Style.dither, Math.min(1, Style.dither.a * 2.2)))
            }
        }

        Repeater {
            model: Style.bar_scanline_color.a > 0 ? Math.max(0, Math.ceil((root.layout.depth - root.texture_phase.first_scanline) / root.scanline_period)) : 0

            Rectangle {
                required property int index
                readonly property real line_y: root.texture_phase.first_scanline + index * root.scanline_period
                readonly property var row_span: Drawer.fill_row_span(root.fill_points, line_y, line_y + 1)
                x: row_span.x
                y: line_y
                width: row_span.w
                height: 1
                color: Style.island_fill(Style.bar_scanline_color)
            }
        }

        Item {
            width: root.layout.length
            height: root.lines_depth < 0 ? root.layout.depth : root.lines_depth
            clip: true

            Loader {
                active: root.inset_width > 0 && root.inset_color.a > 0
                sourceComponent: Shape {
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeWidth: root.inset_width
                        strokeColor: root.inset_color
                        fillColor: "transparent"
                        capStyle: ShapePath.FlatCap
                        joinStyle: ShapePath.MiterJoin
                        miterLimit: 4
                        PathPolyline {
                            path: Drawer.stroke_path(root.layout, root.inset_gap + root.inset_width / 2).map(p => Qt.point(p[0], p[1]))
                        }
                    }
                }
            }

            Loader {
                active: root.rim_width > 0 && root.rim_color.a > 0
                sourceComponent: Shape {
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeWidth: root.rim_width
                        strokeColor: root.rim_color
                        fillColor: "transparent"
                        capStyle: ShapePath.FlatCap
                        joinStyle: ShapePath.MiterJoin
                        miterLimit: 4
                        PathPolyline {
                            path: Drawer.stroke_path(root.layout, root.rim_width / 2).map(p => Qt.point(p[0], p[1]))
                        }
                    }
                }
            }
        }
    }
}

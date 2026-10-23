import QtQuick
import QtQuick.Shapes
import qs.ui.effects
import "BandGeometry.js" as Band

// One band along a screen edge (BandGeometry.js): fill, vertical shade, dither, scanlines, inset line and rim, drawn
// in the band frame and placed on `edge`. It knows nothing of the bar or its islands; callers pass the tokens.
Item {
    id: root

    property string edge: "top"
    property real length: 0
    property real thickness: 0
    property color color: "transparent"
    // The shade runs from the screen edge (shade_color) to the open edge (color), whatever the style's shade_vertical.
    property color shade_color: "transparent"
    // Fills, shade, dither and scanlines fade to this; the inset line and rim stay solid.
    property real fill_opacity: 1
    property int border_width: 0
    property color border_color: "transparent"
    property color dither_color: "transparent"
    property color scanline_color: "transparent"
    property int scanline_period: 3
    // A line along the open edge, inset_gap in from it, between the same insets as the rim.
    property real inset_gap: 0
    property real inset_width: 0
    property color inset_color: "transparent"
    // Where the rim and inset line stop short of the band's ends, for corners drawn by someone else.
    property real inset_start: 0
    property real inset_end: 0
    // The band's offset in a pattern shared with neighbouring bands, so their dither and scanlines line up.
    property real phase_x: 0
    property real phase_y: 0
    // Drawn above the rim, in the band frame, clipped to the band.
    property Component ornament: null
    // { x, y, w, h } in the band frame where the inset line, rim and ornament are left out, for a drawer's mouth.
    property var line_gaps: []

    readonly property bool vertical: root.edge === "left" || root.edge === "right"
    readonly property var affine: Band.band_affine(root.edge, root.thickness)
    readonly property real first_scanline: Band.phase_wrap(-root.phase_y, root.scanline_period)
    readonly property real inset_line_y: root.thickness - root.inset_gap - root.inset_width / 2

    function faded(c) {
        return Qt.alpha(c, c.a * root.fill_opacity);
    }

    function span(y0, y1) {
        const a = Band.band_span(root.length, root.thickness, root.border_width, y0), b = Band.band_span(root.length, root.thickness, root.border_width, y1);
        const x = Math.max(a[0], b[0]);
        return { x: x, w: Math.min(a[1], b[1]) - x };
    }

    width: root.vertical ? root.thickness : root.length
    height: root.vertical ? root.length : root.thickness

    Item {
        id: band
        width: root.length
        height: root.thickness
        transform: Matrix4x4 {
            matrix: {
                const m = root.affine;
                return Qt.matrix4x4(m[0], m[2], 0, m[4], m[1], m[3], 0, m[5], 0, 0, 1, 0, 0, 0, 0, 1);
            }
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: -1
                fillColor: root.faded(root.color)
                fillGradient: root.shade_color.a > 0 ? shade : null
                PathPolyline {
                    path: Band.band_fill(root.length, root.thickness).map(p => Qt.point(p[0], p[1]))
                }
            }

            LinearGradient {
                id: shade
                x1: 0
                y1: 0
                x2: 0
                y2: root.thickness
                GradientStop { position: 0; color: root.faded(root.shade_color) }
                GradientStop { position: 1; color: root.faded(root.color) }
            }
        }

        // Dither tiles from its own origin, so it starts up to one 4px tile before the band to take the phase.
        Loader {
            id: dither_layer
            readonly property real shift_x: Band.phase_wrap(root.phase_x, 4)
            readonly property real shift_y: Band.phase_wrap(root.phase_y, 4)
            x: -shift_x
            y: -shift_y
            width: root.length + shift_x
            height: root.thickness + shift_y
            active: root.dither_color.a > 0
            sourceComponent: Dither {
                row_span: (y0, y1) => {
                    const s = root.span(Math.max(0, y0 - dither_layer.shift_y), y1 - dither_layer.shift_y);
                    return { x: s.x + dither_layer.shift_x, w: s.w };
                }
                color: root.faded(root.dither_color)
            }
        }

        Repeater {
            model: root.scanline_color.a > 0 ? Math.max(0, Math.ceil((root.thickness - root.first_scanline) / root.scanline_period)) : 0

            Rectangle {
                required property int index
                readonly property var row_span: root.span(y, y + 1)
                x: row_span.x
                y: root.first_scanline + index * root.scanline_period
                width: Math.max(0, row_span.w)
                height: 1
                color: root.faded(root.scanline_color)
            }
        }

        Component {
            id: inset_line
            Loader {
                active: root.inset_width > 0 && root.inset_color.a > 0
                sourceComponent: Shape {
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeWidth: root.inset_width
                        strokeColor: root.inset_color
                        fillColor: "transparent"
                        capStyle: ShapePath.FlatCap
                        startX: root.inset_start
                        startY: root.inset_line_y
                        PathLine { x: root.length - root.inset_end; y: root.inset_line_y }
                    }
                }
            }
        }

        Component {
            id: rim_line
            Loader {
                active: root.border_width > 0 && root.border_color.a > 0
                sourceComponent: Shape {
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeWidth: root.border_width
                        strokeColor: root.border_color
                        fillColor: "transparent"
                        capStyle: ShapePath.FlatCap
                        PathPolyline {
                            path: Band.band_rim_stroke(root.length, root.thickness, root.inset_start, root.inset_end, root.border_width).map(p => Qt.point(p[0], p[1]))
                        }
                    }
                }
            }
        }

        Component {
            id: ornament_layer
            Loader {
                clip: true
                active: root.ornament !== null
                sourceComponent: root.ornament
            }
        }

        GapClip { w: root.length; h: root.thickness; gaps: root.line_gaps; source: inset_line }
        GapClip { w: root.length; h: root.thickness; gaps: root.line_gaps; source: rim_line }
        GapClip { w: root.length; h: root.thickness; gaps: root.line_gaps; source: ornament_layer }
    }
}

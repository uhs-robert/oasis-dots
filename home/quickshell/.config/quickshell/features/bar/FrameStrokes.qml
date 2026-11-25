import QtQuick
import QtQuick.Shapes
import "../../ui/frames/FrameGeometry.js" as Frame

// The rim and inset line round a screen frame's hole (FrameGeometry.frame_strokes), in the layout's canonical frame. The
// frame window and each bar's strip draw them, each clipped to its own part, so they read as one line.
Item {
    id: root

    // Null for a moment while a frame goes off, before the strip drops this ornament.
    required property var layout
    property int rim_width: 0
    property color rim_color: "transparent"
    // As BandFill's inset line: inset_gap out from the hole's edge.
    property real inset_gap: 0
    property real inset_width: 0
    property color inset_color: "transparent"

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
                PathMultiline {
                    paths: (root.layout ? Frame.frame_strokes(root.layout, root.inset_gap + root.inset_width / 2) : []).map(line => line.map(p => Qt.point(p[0], p[1])))
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
                PathMultiline {
                    paths: (root.layout ? Frame.frame_strokes(root.layout, root.rim_width / 2) : []).map(line => line.map(p => Qt.point(p[0], p[1])))
                }
            }
        }
    }
}

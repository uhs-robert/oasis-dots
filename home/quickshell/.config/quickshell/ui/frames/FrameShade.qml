import QtQuick
import QtQuick.Shapes
import qs.theme
import "PanelCuts.js" as Cuts

// The style's frame shade into frame_color, diagonal or vertical; it also paints chamfered frames.
Item {
    id: root

    property real bottom_radius: 0
    property real top_radius: 0
    property real top_left_radius: root.top_radius
    property real top_right_radius: root.top_radius
    property real bottom_left_radius: root.bottom_radius
    property real bottom_right_radius: root.bottom_radius
    property real chamfer: 0
    // The corners that touch the bar are not cut.
    property var square: Cuts.none
    property var st: Style.for_item(root)
    readonly property color start_color: root.st.frame_shade.a > 0 ? root.st.frame_shade : root.st.frame_color
    // Chamfered frames trace their border here, just outside the fill where a Rectangle border would sit.
    readonly property real stroke: root.chamfer > 0 ? root.st.frame_border_width : 0

    visible: (root.st.frame_shade.a > 0 || root.chamfer > 0) && !root.st.custom_frame

    Shape {
        visible: root.chamfer <= 0
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0
                y1: 0
                x2: root.st.shade_vertical ? 0 : root.width
                y2: root.height
                GradientStop { position: 0; color: root.start_color }
                GradientStop { position: 1; color: root.st.frame_color }
            }
            PathRectangle {
                width: root.width
                height: root.height
                topLeftRadius: root.top_left_radius
                topRightRadius: root.top_right_radius
                bottomLeftRadius: root.bottom_left_radius
                bottomRightRadius: root.bottom_right_radius
            }
        }
    }

    Shape {
        visible: root.chamfer > 0
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0
                y1: 0
                x2: root.st.shade_vertical ? 0 : root.width
                y2: root.height
                GradientStop { position: 0; color: root.start_color }
                GradientStop { position: 1; color: root.st.frame_color }
            }
            PathPolyline {
                path: Cuts.chamfer(root.width, root.height, Math.min(root.chamfer, root.height / 2, root.width / 2), 0, root.square).map(p => Qt.point(p[0], p[1]))
            }
        }

        ShapePath {
            strokeWidth: root.stroke > 0 ? root.stroke : -1
            strokeColor: root.st.frame_border_color
            fillColor: "transparent"
            joinStyle: ShapePath.MiterJoin
            PathPolyline {
                path: {
                    const o = root.stroke / 2;
                    return Cuts.chamfer(root.width + o, root.height + o, Math.min(root.chamfer, root.height / 2, root.width / 2), o, root.square).map(p => Qt.point(p[0], p[1]));
                }
            }
        }
    }
}

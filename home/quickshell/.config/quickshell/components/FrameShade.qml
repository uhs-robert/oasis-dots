// home/quickshell/.config/quickshell/components/FrameShade.qml
import QtQuick
import QtQuick.Shapes
import "../theme"

// The style's frame shade into frame_color, diagonal or vertical; it also paints chamfered frames.
Item {
    id: root

    property real bottom_radius: 0
    property real top_radius: 0
    property real chamfer: 0
    property var st: Style.for_item(root)
    readonly property color start_color: root.st.frame_shade.a > 0 ? root.st.frame_shade : root.st.frame_color
    // Chamfered frames trace their border here, just outside the fill where a Rectangle border would sit.
    readonly property real stroke: root.chamfer > 0 ? root.st.frame_border_width : 0

    visible: root.st.frame_shade.a > 0 || root.chamfer > 0

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
                topLeftRadius: root.top_radius
                topRightRadius: root.top_radius
                bottomLeftRadius: root.bottom_radius
                bottomRightRadius: root.bottom_radius
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
                path: {
                    const w = root.width, h = root.height, c = Math.min(root.chamfer, h / 2, w / 2);
                    return [Qt.point(0, 0), Qt.point(w, 0), Qt.point(w, h - c), Qt.point(w - c, h), Qt.point(c, h), Qt.point(0, h - c), Qt.point(0, 0)];
                }
            }
        }

        ShapePath {
            strokeWidth: root.stroke > 0 ? root.stroke : -1
            strokeColor: root.st.frame_border_color
            fillColor: "transparent"
            joinStyle: ShapePath.MiterJoin
            PathPolyline {
                path: {
                    const o = root.stroke / 2, w = root.width + o, h = root.height + o, c = Math.min(root.chamfer, root.height / 2, root.width / 2);
                    return [Qt.point(-o, -o), Qt.point(w, -o), Qt.point(w, h - c), Qt.point(w - c, h), Qt.point(c - o, h), Qt.point(-o, h - c), Qt.point(-o, -o)];
                }
            }
        }
    }
}

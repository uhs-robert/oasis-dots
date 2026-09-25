// home/quickshell/.config/quickshell/components/oasis/SlantFrame.qml
import QtQuick
import QtQuick.Shapes
import "../../theme"

// An oasis panel: a flat top, bottom corners cut at the bar islands' slant, filled sky to night, a sand horizon along the foot.
Item {
    id: root

    property var st: Style.for_item(root)
    property color edge_color: root.st.frame_border_color
    property color fill_top: root.st.frame_shade.a > 0 ? root.st.frame_shade : root.st.frame_color
    property color fill_bottom: root.st.frame_color

    readonly property real bw: root.st.frame_border_width
    readonly property color sand: Theme.theme_secondary

    // The bottom edge from its left end to its right end, for the box inset by i.
    function bottom_edge(i) {
        const x0 = i, x1 = root.width - i, y1 = root.height - i, cap = Math.max(1, root.height * 0.45);
        const cut = depth => Math.max(0, Math.min(depth, cap) - i * 0.6);
        const l = cut(10), r = cut(36);
        return [Qt.point(x0, y1 - l), Qt.point(x0 + l / 2, y1), Qt.point(x1 - r / 2, y1), Qt.point(x1, y1 - r)];
    }

    function outline(i) {
        const pts = [Qt.point(i, i), Qt.point(root.width - i, i)].concat(root.bottom_edge(i).reverse());
        pts.push(pts[0]);
        return pts;
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0
                y1: 0
                x2: 0
                y2: root.height
                GradientStop { position: 0; color: root.fill_top }
                GradientStop { position: 1; color: root.fill_bottom }
            }
            PathPolyline { path: root.outline(0) }
        }

        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0
                y1: root.height - 36
                x2: 0
                y2: root.height
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: Qt.alpha(root.sand, 0.08) }
            }
            PathPolyline { path: root.outline(root.bw) }
        }

        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0
                y1: 0
                x2: root.width
                y2: 0
                GradientStop { position: 0; color: Qt.alpha(root.sand, 0.1) }
                GradientStop { position: 0.3; color: Qt.alpha(root.sand, 0.55) }
                GradientStop { position: 0.7; color: Qt.alpha(root.sand, 0.55) }
                GradientStop { position: 1; color: Qt.alpha(root.sand, 0.1) }
            }
            PathPolyline { path: root.bottom_edge(root.bw).concat(root.bottom_edge(root.bw + 1).reverse()) }
        }

        ShapePath {
            strokeWidth: root.bw > 0 ? root.bw : -1
            strokeColor: root.edge_color
            fillColor: "transparent"
            joinStyle: ShapePath.MiterJoin
            PathPolyline { path: root.outline(root.bw / 2) }
        }
    }
}

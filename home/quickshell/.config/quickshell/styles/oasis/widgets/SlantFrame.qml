import QtQuick
import QtQuick.Shapes
import qs.theme
import "../../../ui/frames/PanelCuts.js" as Cuts

// An oasis panel: a flat top, bottom corners cut at the bar islands' slant, filled sky to night, a sand horizon along the foot.
Item {
    id: root

    property var st: Style.for_item(root)
    property color edge_color: root.st.frame_border_color
    property color fill_top: root.st.frame_shade.a > 0 ? root.st.frame_shade : root.st.frame_color
    property color fill_bottom: root.st.frame_color
    // False for a straight foot, where a host's own corners (the screen frame's) are the panel's.
    property bool cut_corners: true
    // The corners that touch the bar stay square.
    property var square: Cuts.none

    readonly property real bw: root.st.frame_border_width
    readonly property color sand: Theme.theme_secondary

    // The bottom edge from its left end to its right end, for the box inset by i.
    function bottom_edge(i) {
        const square = root.cut_corners ? root.square : { bottom_left: true, bottom_right: true };
        return Cuts.slant_foot(root.width, root.height, i, square).map(p => Qt.point(p[0], p[1]));
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

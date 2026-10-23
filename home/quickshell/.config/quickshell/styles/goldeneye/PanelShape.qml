import QtQuick
import QtQuick.Shapes
import "Watch.js" as Watch

// The watch's translucent green octagon with the pale notches on its sides, at any size.
Item {
    id: root

    property real cut: 10
    property real notch_w: 8
    property real notch_h: 22
    property bool notches: true
    property color edge: "transparent"
    // Half a pixel inside, so the 1px edge stroke fills one pixel column instead of dithering across two.
    readonly property real inset: root.edge.a > 0 ? 0.5 : 0
    readonly property var outline: {
        const x0 = root.inset, y0 = root.inset, x1 = root.width - root.inset, y1 = root.height - root.inset;
        const c = Math.min(root.cut, (x1 - x0) / 2, (y1 - y0) / 2);
        return [Qt.point(x0 + c, y0), Qt.point(x1 - c, y0), Qt.point(x1, y0 + c), Qt.point(x1, y1 - c), Qt.point(x1 - c, y1), Qt.point(x0 + c, y1), Qt.point(x0, y1 - c), Qt.point(x0, y0 + c), Qt.point(x0 + c, y0)];
    }
    property color top_color: Qt.rgba(Watch.panel_top[0], Watch.panel_top[1], Watch.panel_top[2], Watch.panel_top[3])
    property color bottom_color: Qt.rgba(Watch.panel_bottom[0], Watch.panel_bottom[1], Watch.panel_bottom[2], Watch.panel_bottom[3])

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
                GradientStop { position: 0; color: root.top_color }
                GradientStop { position: 1; color: root.bottom_color }
            }
            PathPolyline { path: root.outline }
        }

        ShapePath {
            strokeWidth: root.edge.a > 0 ? 1 : -1
            strokeColor: root.edge
            fillColor: "transparent"
            joinStyle: ShapePath.MiterJoin
            PathPolyline { path: root.outline }
        }
    }

    Rectangle {
        visible: root.notches
        x: 0
        y: (root.height - root.notch_h) / 2
        width: root.notch_w
        height: root.notch_h
        color: Qt.rgba(0.7, 0.78, 0.7, 0.26)
    }

    Rectangle {
        visible: root.notches
        x: root.width - root.notch_w
        y: (root.height - root.notch_h) / 2
        width: root.notch_w
        height: root.notch_h
        color: Qt.rgba(0.7, 0.78, 0.7, 0.26)
    }
}

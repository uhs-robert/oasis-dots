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
    // A 1px stroke centred on the item's own edge straddles two pixel columns and the curve renderer dithers it row by row
    // (a dotted right edge); with an edge drawn the outline runs half a pixel inside so the stroke fills one column.
    readonly property real inset: root.edge.a > 0 ? 0.5 : 0
    readonly property var outline: {
        const o = root.inset, w = root.width - o, h = root.height - o, c = Math.min(root.cut, w / 2, h / 2);
        return [Qt.point(c, o), Qt.point(w - c, o), Qt.point(w, c), Qt.point(w, h - c), Qt.point(w - c, h), Qt.point(c, h), Qt.point(o, h - c), Qt.point(o, c), Qt.point(c, o)];
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

// home/quickshell/.config/quickshell/components/CutBox.qml
import QtQuick
import QtQuick.Shapes

// A box with 45-degree cuts at chosen corners, filled and outlined.
Shape {
    id: root

    property real cut_tl: 0
    property real cut_tr: 0
    property real cut_br: 0
    property real cut_bl: 0
    property color fill: "transparent"
    // A horizontal fade from fill into fill_end when set.
    property color fill_end: root.fill
    property color stroke: "transparent"

    preferredRendererType: Shape.CurveRenderer

    function outline(i) {
        const w = root.width - i, h = root.height - i, k = i * 0.41;
        const tl = Math.max(0, root.cut_tl - k), tr = Math.max(0, root.cut_tr - k), br = Math.max(0, root.cut_br - k), bl = Math.max(0, root.cut_bl - k);
        return [Qt.point(i + tl, i), Qt.point(w - tr, i), Qt.point(w, i + tr), Qt.point(w, h - br), Qt.point(w - br, h), Qt.point(i + bl, h), Qt.point(i, h - bl), Qt.point(i, i + tl), Qt.point(i + tl, i)];
    }

    ShapePath {
        strokeWidth: -1
        fillGradient: LinearGradient {
            x1: 0
            y1: 0
            x2: root.width
            y2: 0
            GradientStop { position: 0; color: root.fill }
            GradientStop { position: 1; color: root.fill_end }
        }
        PathPolyline { path: root.outline(0) }
    }

    ShapePath {
        strokeWidth: root.stroke.a > 0 ? 1 : -1
        strokeColor: root.stroke
        fillColor: "transparent"
        joinStyle: ShapePath.MiterJoin
        PathPolyline { path: root.outline(0.5) }
    }
}

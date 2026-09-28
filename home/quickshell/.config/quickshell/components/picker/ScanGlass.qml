// home/quickshell/.config/quickshell/components/picker/ScanGlass.qml
import QtQuick
import QtQuick.Shapes
import "../../theme"

// Chamfered visor-glass panel for the scan visor picker skin: a cut-corner pane with a
// cyan-tinted gradient fill, thin bright border and an optional top sheen.
Shape {
    id: root

    property real corner: 12
    property color border_color: Qt.alpha(Theme.bright_cyan, 0.65)
    property bool sheen: false

    readonly property real k: Math.min(root.corner, root.width / 3, root.height / 3)

    preferredRendererType: Shape.CurveRenderer

    function outline(i) {
        const w = root.width, h = root.height, k = Math.max(0, root.k - i * 0.6);
        return [
            Qt.point(i + k, i), Qt.point(w - i - k, i), Qt.point(w - i, i + k), Qt.point(w - i, h - i - k),
            Qt.point(w - i - k, h - i), Qt.point(i + k, h - i), Qt.point(i, h - i - k), Qt.point(i, i + k),
            Qt.point(i + k, i)
        ];
    }

    ShapePath {
        strokeWidth: -1
        fillGradient: LinearGradient {
            x1: 0
            y1: 0
            x2: 0
            y2: root.height
            GradientStop { position: 0; color: Qt.tint(Theme.bg_crust, Qt.alpha(Theme.cyan, 0.22)) }
            GradientStop { position: 0.3; color: Qt.alpha(Theme.bg_crust, 0.86) }
            GradientStop { position: 0.9; color: Qt.alpha(Theme.bg_crust, 0.9) }
        }
        PathPolyline { path: root.outline(0) }
    }

    ShapePath {
        strokeWidth: -1
        fillGradient: RadialGradient {
            centerX: root.width / 2
            centerY: 0
            focalX: root.width / 2
            focalY: 0
            centerRadius: root.width * 0.5
            focalRadius: 0
            GradientStop { position: 0; color: Qt.alpha(Theme.fg_strong, root.sheen ? 0.1 : 0) }
            GradientStop { position: 1; color: Qt.alpha(Theme.fg_strong, 0) }
        }
        PathPolyline { path: root.outline(0) }
    }

    ShapePath {
        strokeWidth: 1
        strokeColor: root.border_color
        fillColor: "transparent"
        joinStyle: ShapePath.MiterJoin
        PathPolyline { path: root.outline(0.5) }
    }
}

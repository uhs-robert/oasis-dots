// home/quickshell/.config/quickshell/components/oasis/MoonRule.qml
import QtQuick
import QtQuick.Shapes
import "../../theme"

// A footer rule that fades out toward a small sand crescent at its right end.
Item {
    id: root

    property color color: "transparent"
    readonly property real moon: 8

    height: root.moon

    Rectangle {
        y: Math.round(root.height / 2)
        width: Math.max(0, root.width - root.moon - 6)
        height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.alpha(root.color, 0) }
            GradientStop { position: 0.25; color: root.color }
            GradientStop { position: 1; color: root.color }
        }
    }

    Shape {
        x: root.width - root.moon
        width: root.moon
        height: root.moon
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillColor: Qt.alpha(Theme.theme_secondary, 0.85)
            scale: Qt.size(root.moon / 8, root.moon / 8)
            PathSvg { path: "M6 0.54 A4 4 0 1 0 6 7.46 A3.54 3.54 0 0 1 6 0.54 Z" }
        }
    }
}

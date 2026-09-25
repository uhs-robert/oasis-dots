// home/quickshell/.config/quickshell/components/WindowGradient.qml
import QtQuick
import QtQuick.Shapes
import "../theme"

// The style's window_gradient (up to three stops) laid corner to corner like a CSS 135deg gradient.
Shape {
    id: root

    property var st: Style.for_item(root)
    property var stops: root.st.window_gradient
    property real top_radius: 0
    property real bottom_radius: 0
    readonly property real reach: (root.width + root.height) / 4

    function stop(i) {
        const n = root.stops.length;
        return n > 0 ? root.stops[Math.min(i, n - 1)] : [i / 2, "transparent"];
    }

    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeWidth: -1
        fillGradient: LinearGradient {
            x1: root.width / 2 - root.reach
            y1: root.height / 2 - root.reach
            x2: root.width / 2 + root.reach
            y2: root.height / 2 + root.reach
            GradientStop { position: root.stop(0)[0]; color: root.stop(0)[1] }
            GradientStop { position: root.stop(1)[0]; color: root.stop(1)[1] }
            GradientStop { position: root.stop(2)[0]; color: root.stop(2)[1] }
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

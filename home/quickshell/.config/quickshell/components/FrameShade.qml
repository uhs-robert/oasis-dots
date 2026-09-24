// home/quickshell/.config/quickshell/components/FrameShade.qml
import QtQuick
import QtQuick.Shapes
import "../theme"

// The style's diagonal frame shade, from frame_shade at the top left into frame_color.
Shape {
    id: root

    property real bottom_radius: 0
    property real top_radius: 0

    visible: Style.frame_shade.a > 0
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeWidth: -1
        fillGradient: LinearGradient {
            x1: 0
            y1: 0
            x2: root.width
            y2: root.height
            GradientStop { position: 0; color: Style.frame_shade }
            GradientStop { position: 1; color: Style.frame_color }
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

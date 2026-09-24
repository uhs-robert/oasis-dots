// home/quickshell/.config/quickshell/components/Reticle.qml
import QtQuick
import QtQuick.Shapes

// A targeting reticle: ring, four crosshair ticks and a filled center diamond.
Shape {
    id: root

    property color color: "transparent"
    property color center_color: "transparent"
    readonly property real u: root.width / 24

    implicitWidth: 18
    implicitHeight: 18
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeWidth: 1.2 * root.u
        strokeColor: root.color
        fillColor: "transparent"
        capStyle: ShapePath.FlatCap

        PathAngleArc { centerX: 12 * root.u; centerY: 12 * root.u; radiusX: 7.5 * root.u; radiusY: 7.5 * root.u; startAngle: 0; sweepAngle: 360 }
        PathMove { x: 12 * root.u; y: 1.5 * root.u }
        PathLine { x: 12 * root.u; y: 7.5 * root.u }
        PathMove { x: 12 * root.u; y: 16.5 * root.u }
        PathLine { x: 12 * root.u; y: 22.5 * root.u }
        PathMove { x: 1.5 * root.u; y: 12 * root.u }
        PathLine { x: 7.5 * root.u; y: 12 * root.u }
        PathMove { x: 16.5 * root.u; y: 12 * root.u }
        PathLine { x: 22.5 * root.u; y: 12 * root.u }
    }

    ShapePath {
        strokeWidth: -1
        fillColor: root.center_color
        startX: 12 * root.u
        startY: 10 * root.u
        PathLine { x: 14 * root.u; y: 12 * root.u }
        PathLine { x: 12 * root.u; y: 14 * root.u }
        PathLine { x: 10 * root.u; y: 12 * root.u }
        PathLine { x: 12 * root.u; y: 10 * root.u }
    }
}

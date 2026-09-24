// home/quickshell/.config/quickshell/components/CornerTick.qml
import QtQuick
import QtQuick.Shapes

// A diagonal tick across the parent's top-right corner, as if the corner were cut.
Shape {
    id: root

    property color color: "transparent"
    property real size: 8

    visible: root.color.a > 0
    anchors.top: parent ? parent.top : undefined
    anchors.right: parent ? parent.right : undefined
    width: root.size
    height: root.size
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeWidth: 1.2
        strokeColor: root.color
        fillColor: "transparent"
        startX: 0
        startY: 0
        PathLine { x: root.size; y: root.size }
    }
}

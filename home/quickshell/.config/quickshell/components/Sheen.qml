// home/quickshell/.config/quickshell/components/Sheen.qml
import QtQuick

// A 1px highlight along the top edge of a rounded surface, fading out into its corners.
Rectangle {
    id: root

    property color color_top: "transparent"
    property real corner: 0
    property real edge: 0

    visible: root.color_top.a > 0
    x: Math.max(root.edge, root.corner * 0.6)
    y: root.edge
    width: Math.max(0, (parent ? parent.width : 0) - root.x * 2)
    height: 1
    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: Qt.alpha(root.color_top, 0) }
        GradientStop { position: 0.12; color: root.color_top }
        GradientStop { position: 0.88; color: root.color_top }
        GradientStop { position: 1; color: Qt.alpha(root.color_top, 0) }
    }
}

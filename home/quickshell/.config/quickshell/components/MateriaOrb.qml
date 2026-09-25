// home/quickshell/.config/quickshell/components/MateriaOrb.qml
import QtQuick
import QtQuick.Shapes
import "../theme"

// A materia orb: a glossy sphere lit from the top left; wider than tall it draws a capsule.
Shape {
    id: root

    property color color: Theme.theme_secondary
    property real radius: Math.min(root.width, root.height) / 2
    property bool glow: true

    implicitWidth: 16
    implicitHeight: 16
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeWidth: root.glow ? 2 : -1
        strokeColor: Qt.alpha(root.color, 0.3)
        fillColor: "transparent"
        PathRectangle {
            x: -1
            y: -1
            width: root.width + 2
            height: root.height + 2
            radius: root.radius + 1
        }
    }

    ShapePath {
        strokeWidth: 1
        strokeColor: Qt.alpha(Theme.bg_crust, 0.7)
        fillGradient: RadialGradient {
            centerX: root.width * 0.34
            centerY: root.height * 0.3
            centerRadius: Math.max(root.width, root.height) * 0.96
            focalX: root.width * 0.34
            focalY: root.height * 0.3
            focalRadius: 0
            GradientStop { position: 0; color: Theme.fg_strong }
            GradientStop { position: 0.09; color: Theme.fg_strong }
            GradientStop { position: 0.38; color: root.color }
            GradientStop { position: 1; color: Qt.tint(Theme.bg_crust, Qt.alpha(root.color, 0.35)) }
        }
        PathRectangle {
            width: root.width
            height: root.height
            radius: root.radius
        }
    }
}

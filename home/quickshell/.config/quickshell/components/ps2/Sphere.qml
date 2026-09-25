// home/quickshell/.config/quickshell/components/ps2/Sphere.qml
import QtQuick
import QtQuick.Shapes
import "../../theme"

// One Audio CD player sphere: a glassy ball, glowing blue when lit.
Item {
    id: root

    property bool lit: false
    property color color: Theme.theme_primary_light
    readonly property real r: root.width / 2

    implicitWidth: 10
    implicitHeight: root.width

    Rectangle {
        visible: root.lit
        anchors.centerIn: parent
        width: root.width * 1.9
        height: width
        radius: width / 2
        color: Qt.alpha(root.color, 0.16)
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: 1
            strokeColor: Qt.alpha(root.color, root.lit ? 0.6 : 0.22)
            fillGradient: RadialGradient {
                centerX: root.r
                centerY: root.r
                centerRadius: root.r
                focalX: root.r * 0.7
                focalY: root.r * 0.6
                focalRadius: 0
                GradientStop { position: 0; color: root.lit ? Theme.fg_strong : Qt.alpha(root.color, 0.3) }
                GradientStop { position: 0.35; color: root.lit ? root.color : Qt.alpha(root.color, 0.12) }
                GradientStop { position: 1; color: root.lit ? Qt.alpha(Theme.theme_primary_strong, 0.9) : Qt.alpha(Theme.theme_primary_strong, 0.08) }
            }
            PathAngleArc { centerX: root.r; centerY: root.r; radiusX: root.r - 0.5; radiusY: root.r - 0.5; startAngle: 0; sweepAngle: 360 }
        }
    }
}

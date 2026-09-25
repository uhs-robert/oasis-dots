// home/quickshell/.config/quickshell/components/ps2/GlowRing.qml
import QtQuick
import QtQuick.Shapes
import "../../theme"

// The PS2 OSD: a soft blue glow behind a thin ring lit clockwise from the top by `value`, a thin readout inside.
Item {
    id: root

    property real value: 0
    property string label: ""
    property string caption: ""
    property bool dimmed: false
    readonly property real c: root.width / 2
    readonly property real r: root.width / 2 - 8

    implicitWidth: 84
    implicitHeight: root.width
    opacity: root.dimmed ? 0.5 : 1

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: root.c
                centerY: root.c
                focalX: root.c
                focalY: root.c
                centerRadius: root.c
                focalRadius: 0
                GradientStop { position: 0; color: Qt.alpha(Theme.theme_primary, 0.3) }
                GradientStop { position: 0.72; color: Qt.alpha(Theme.theme_primary, 0.12) }
                GradientStop { position: 1; color: "transparent" }
            }
            PathAngleArc { centerX: root.c; centerY: root.c; radiusX: root.c; radiusY: root.c; startAngle: 0; sweepAngle: 360 }
        }

        ShapePath {
            strokeWidth: 2
            strokeColor: Qt.alpha(Theme.theme_primary, 0.2)
            fillColor: "transparent"
            PathAngleArc { centerX: root.c; centerY: root.c; radiusX: root.r; radiusY: root.r; startAngle: 0; sweepAngle: 360 }
        }

        ShapePath {
            strokeWidth: 7
            strokeColor: Qt.alpha(Theme.theme_primary_light, 0.18)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: root.c; centerY: root.c; radiusX: root.r; radiusY: root.r; startAngle: -90; sweepAngle: 360 * Math.max(0.001, Math.min(1, root.value)) }
        }

        ShapePath {
            strokeWidth: 2
            strokeColor: Theme.theme_primary_light
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: root.c; centerY: root.c; radiusX: root.r; radiusY: root.r; startAngle: -90; sweepAngle: 360 * Math.max(0.001, Math.min(1, root.value)) }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: -2

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            color: Theme.fg_strong
            font.family: "Exo 2"
            font.pixelSize: Math.round(root.width * 0.28)
            font.weight: Font.ExtraLight
        }

        Text {
            visible: root.caption !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.caption
            color: Theme.theme_primary_light
            font.family: "Exo 2"
            font.pixelSize: Math.max(8, Math.round(root.width * 0.1))
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.2
        }
    }
}

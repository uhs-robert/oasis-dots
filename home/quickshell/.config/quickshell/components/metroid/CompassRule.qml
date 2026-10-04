// home/quickshell/.config/quickshell/components/metroid/CompassRule.qml
import QtQuick
import QtQuick.Shapes

// A visor heading tape: ticks rising off a faint baseline, every fifth taller, fading out from a centre caret.
Item {
    id: root

    property color color: "white"
    readonly property color strong: Qt.rgba(root.color.r, root.color.g, root.color.b, Math.min(1, root.color.a * 2.4))
    readonly property int step: 6
    readonly property int half_count: Math.max(0, Math.floor(root.width / 2 / root.step))
    readonly property real mid: Math.round(root.width / 2)

    implicitHeight: 7

    Rectangle {
        y: root.height - 1
        width: root.width
        height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 0.5; color: root.color }
            GradientStop { position: 1; color: "transparent" }
        }
    }

    Repeater {
        model: root.half_count * 2 + 1

        Rectangle {
            required property int index
            readonly property int offset: index - root.half_count
            readonly property bool major: offset % 5 === 0

            x: root.mid + offset * root.step
            y: root.height - 1 - height
            width: 1
            height: major ? 4 : 2
            color: major ? root.strong : root.color
            opacity: root.half_count > 0 ? Math.max(0.12, 1 - Math.abs(offset) / root.half_count) : 1
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillColor: root.strong
            PathSvg { path: "M " + (root.mid - 3) + " 0 L " + (root.mid + 4) + " 0 L " + (root.mid + 0.5) + " 3.5 Z" }
        }
    }
}

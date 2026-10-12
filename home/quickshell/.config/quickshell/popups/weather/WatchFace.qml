// home/quickshell/.config/quickshell/popups/weather/WatchFace.qml
import QtQuick
import QtQuick.Shapes
import "../../theme"
import "../../theme/Watch.js" as W

// The pause watch as a 24-hour dial: midnight at the top like a wall clock, noon at the bottom, numerals every three hours around a bezel
// band that views fill, a pale hand inside the band, and the face for readouts. `bezel` children sit at the dial centre
// and point up, so a view rotates each one to angle_of(hour).
Item {
    id: root

    // Hour of day the hand points at; below zero hides it.
    property real hand_hour: -1
    property color hand_color: Style.wk.lit
    property real hand_alpha: 1
    // Radial depth of the bezel band, measured in from the rim.
    readonly property real band: 30
    readonly property real label_pad: 16
    readonly property real bezel_r: Math.min(root.width, root.height) / 2 - root.label_pad
    readonly property real face_r: root.bezel_r - root.band - 6
    readonly property real cx: root.width / 2
    readonly property real cy: root.height / 2
    default property alias face: face_content.data
    property alias bezel: bezel_layer.data

    function angle_of(hour) {
        return (hour / 24 * 360) % 360;
    }

    Rectangle {
        x: root.cx - root.bezel_r
        y: root.cy - root.bezel_r
        width: root.bezel_r * 2
        height: width
        radius: width / 2
        border.width: 2
        border.color: Style.wk.rim
        gradient: Gradient {
            GradientStop { position: 0; color: Style.wk.panel_top }
            GradientStop { position: 1; color: Style.wk.panel_bottom }
        }
    }

    Rectangle {
        x: root.cx - root.face_r - 3
        y: root.cy - root.face_r - 3
        width: (root.face_r + 3) * 2
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 1
        border.color: Style.wk.edge
    }

    Repeater {
        model: 8

        Text {
            required property int index
            readonly property real hour: index * 3
            readonly property real theta: root.angle_of(hour) * Math.PI / 180
            x: root.cx + (root.bezel_r + 10) * Math.sin(theta) - width / 2
            y: root.cy - (root.bezel_r + 10) * Math.cos(theta) - height / 2
            width: 20
            horizontalAlignment: Text.AlignHCenter
            text: (hour < 10 ? "0" : "") + hour
            color: Style.wk.dim
            font.family: W.mono_font
            font.pixelSize: Style.fs(-6)
        }
    }

    Item {
        id: bezel_layer
        x: root.cx
        y: root.cy
    }

    Item {
        visible: root.hand_hour >= 0
        x: root.cx
        y: root.cy
        rotation: root.angle_of(root.hand_hour)
        opacity: root.hand_alpha

        Shape {
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: 2
                strokeColor: Qt.alpha(root.hand_color, 0.85)
                fillColor: Qt.alpha(root.hand_color, 0.22)
                joinStyle: ShapePath.MiterJoin
                startX: 0
                startY: -root.face_r
                PathLine { x: 8; y: -root.face_r + 14 }
                PathLine { x: 8; y: -root.face_r + 28 }
                PathLine { x: -8; y: -root.face_r + 28 }
                PathLine { x: -8; y: -root.face_r + 14 }
                PathLine { x: 0; y: -root.face_r }
            }
        }
    }

    Item {
        id: face_content
        x: root.cx - width / 2
        y: root.cy - height / 2
        width: (root.face_r - 36) * 2
        height: width
    }
}

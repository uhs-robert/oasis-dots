// home/quickshell/.config/quickshell/popups/weather/WatchFace.qml
import QtQuick
import QtQuick.Shapes
import "../../theme"
import "../../services"
import "../../theme/Watch.js" as W

// The pause watch as a dial of `hours_per_turn` hours (12 like a wall clock, or 24) with `top_hour` at the top, numerals at the four
// quarters and a tick for each other hour, around a bezel
// band that views fill, a pale hand inside the band, and the face for readouts. `bezel` children sit at the dial centre
// and point up, so a view rotates each one to angle_of(hour).
Item {
    id: root

    // Hour of day the hand points at; below zero hides it.
    property real hand_hour: -1
    property color hand_color: Style.wk.lit
    property real hand_alpha: 1
    property int hours_per_turn: 12
    property real top_hour: 0
    // Radial depth of the bezel band, measured in from the rim.
    property real band: 30
    readonly property real label_pad: 16
    readonly property real bezel_r: Math.min(root.width, root.height) / 2 - root.label_pad
    readonly property real face_r: root.bezel_r - root.band - 6
    readonly property real cx: root.width / 2
    readonly property real cy: root.height / 2
    default property alias face: face_content.data
    property alias bezel: bezel_layer.data

    function angle_of(hour) {
        const n = root.hours_per_turn;
        return (((hour - root.top_hour) % n + n) % n) / n * 360;
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

    function numeral_text(hour) {
        if (root.hours_per_turn === 12) return hour % 12 === 0 ? "12" : String(hour % 12);
        return TimeFormat.hour(new Date(2000, 0, 1, hour));
    }

    Repeater {
        model: 4

        Text {
            required property int index
            readonly property real hour: (root.top_hour + index * root.hours_per_turn / 4) % 24
            readonly property real theta: root.angle_of(hour) * Math.PI / 180
            // Side numerals reach out by half their width so "6pm" clears the rim like the top and bottom ones.
            readonly property real reach: root.bezel_r + 8 + Math.abs(Math.sin(theta)) * implicitWidth / 2
            x: root.cx + reach * Math.sin(theta) - width / 2
            y: root.cy - reach * Math.cos(theta) - height / 2
            width: implicitWidth
            horizontalAlignment: Text.AlignHCenter
            text: root.numeral_text(hour)
            color: Style.wk.dim
            font.family: W.mono_font
            font.pixelSize: Style.fs(-6)
        }
    }

    Repeater {
        model: root.hours_per_turn

        Rectangle {
            required property int index
            visible: index % (root.hours_per_turn / 4) !== 0
            x: root.cx - 1
            y: root.cy - root.bezel_r - 7
            width: 2
            height: 5
            color: Style.wk.dim
            transform: Rotation { origin.x: 1; origin.y: root.bezel_r + 7; angle: index / root.hours_per_turn * 360 }
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

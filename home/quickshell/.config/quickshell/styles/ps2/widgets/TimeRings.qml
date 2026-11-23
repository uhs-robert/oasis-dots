import QtQuick
import QtQuick.Shapes
import qs.theme

// The PS2 clock's wire rings: the outer ring has a segment per minute, the inner one a segment per hour, each lit up
// to and including the current one. `fire()` flashes the newest minute segment once; the caller calls it on the
// minute tick and nothing loops.
Item {
    id: root

    // 0-59, and 0-11 for the 12-hour dial.
    property int minute: 0
    property int hour: 0
    property real flash: 0
    readonly property real c: root.width / 2
    readonly property real r_minute: root.c - 4
    readonly property real r_hour: root.r_minute * 0.72
    readonly property real gap: 0.06

    implicitWidth: 96
    implicitHeight: root.width

    function fire() {
        flash_anim.restart();
    }

    NumberAnimation {
        id: flash_anim
        target: root
        property: "flash"
        from: 1
        to: 0
        duration: 1100
        easing.type: Easing.OutCubic
    }

    // One ring of `n` segments: a faint track, the lit arc, and an optional flashing newest segment.
    component Ring: Shape {
        id: ring

        required property int n
        required property real radius
        required property real lw
        required property int lit
        property real head_flash: 0
        readonly property real step: 360 / ring.n
        readonly property real circumference: 2 * Math.PI * ring.radius
        // Dash lengths are in stroke widths; the gap is a fixed share of each segment.
        readonly property var dashes: [(ring.circumference / ring.n * (1 - root.gap * 2)) / ring.lw, (ring.circumference / ring.n * root.gap * 2) / ring.lw]

        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: ring.lw
            strokeColor: Qt.alpha(Theme.theme_primary, 0.16)
            fillColor: "transparent"
            dashPattern: ring.dashes
            PathAngleArc { centerX: root.c; centerY: root.c; radiusX: ring.radius; radiusY: ring.radius; startAngle: -90; sweepAngle: 360 }
        }

        ShapePath {
            strokeWidth: ring.lw
            strokeColor: Qt.alpha(Theme.theme_primary_light, 0.62)
            fillColor: "transparent"
            dashPattern: ring.dashes
            PathAngleArc { centerX: root.c; centerY: root.c; radiusX: ring.radius; radiusY: ring.radius; startAngle: -90; sweepAngle: ring.step * (ring.lit + 1) }
        }

        ShapePath {
            strokeWidth: ring.lw + 1
            strokeColor: Qt.alpha(Theme.fg_strong, ring.head_flash)
            fillColor: "transparent"
            PathAngleArc {
                centerX: root.c
                centerY: root.c
                radiusX: ring.radius
                radiusY: ring.radius
                startAngle: -90 + ring.step * (ring.lit + root.gap)
                sweepAngle: ring.step * (1 - root.gap * 2)
            }
        }
    }

    Ring { n: 60; radius: root.r_minute; lw: 4; lit: root.minute; head_flash: root.flash }
    Ring { n: 12; radius: root.r_hour; lw: 3; lit: root.hour }
}

// home/quickshell/.config/quickshell/lock/skins/goldeneye/SegmentArc.qml
import QtQuick

// Bezel segments on the left half of an ellipse (right half when mirrored), the first at the top; `lit` of them at full colour, counted from the top or the bottom.
Item {
    id: root

    property var colors: []
    property int lit: root.colors.length
    property bool mirror: false
    property bool from_bottom: false
    property real thickness: 10
    property real span: 112
    property real gap: 3
    property real unlit_alpha: 0.2
    readonly property real a: root.width - root.thickness / 2
    readonly property real b: root.height / 2 - root.thickness / 2
    readonly property real step: root.span / Math.max(1, root.colors.length) * Math.PI / 180

    Repeater {
        model: root.colors

        Rectangle {
            id: seg
            required property string modelData
            required property int index
            readonly property real t: (-root.span / 2 + (seg.index + 0.5) * root.span / root.colors.length) * Math.PI / 180
            readonly property real px: root.mirror ? root.a * Math.cos(seg.t) : root.width - root.a * Math.cos(seg.t)
            readonly property real py: root.height / 2 + root.b * Math.sin(seg.t)
            readonly property real tilt: -Math.atan2(root.a * Math.sin(seg.t), root.b * Math.cos(seg.t)) * 180 / Math.PI
            x: seg.px - root.thickness / 2
            y: seg.py - seg.height / 2
            width: root.thickness
            height: Math.max(2, Math.hypot(root.a * Math.sin(seg.t), root.b * Math.cos(seg.t)) * root.step - root.gap)
            rotation: root.mirror ? -seg.tilt : seg.tilt
            color: seg.modelData
            opacity: (root.from_bottom ? seg.index >= root.colors.length - root.lit : seg.index < root.lit) ? 1 : root.unlit_alpha
            antialiasing: true
        }
    }
}

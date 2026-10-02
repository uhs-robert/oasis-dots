// home/quickshell/.config/quickshell/components/goldeneye/SegmentStrip.qml
import QtQuick
import "../../lock/skins/goldeneye/Watch.js" as W

// A short run of slanted warm bezel segments, lit up to `value` (0-1), dim after; yellow first, red at the full end.
Row {
    id: root

    property real value: 0
    property int count: 5
    property real seg_width: 5
    property real seg_height: 11
    readonly property int lit: Math.ceil(Math.max(0, Math.min(1, root.value)) * root.count - 1e-6)

    spacing: 2

    Repeater {
        model: root.count

        Rectangle {
            required property int index
            width: root.seg_width
            height: root.seg_height
            color: W.warm[7 - Math.round(index * 7 / Math.max(1, root.count - 1))]
            opacity: index < root.lit ? 1 : 0.2
            antialiasing: true
            transform: Matrix4x4 {
                matrix: Qt.matrix4x4(1, -0.4, 0, 0.4 * root.seg_height, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
            }
        }
    }
}

// home/quickshell/.config/quickshell/components/ps2/SphereTrack.qml
import QtQuick
import "../../theme"

// Audio CD spheres in a line, lit from the left up to `value`.
Item {
    id: root

    property real value: 0
    property real sphere: 8
    readonly property real gap: root.sphere * 0.6
    readonly property int count: Math.max(1, Math.floor((root.width + root.gap) / (root.sphere + root.gap)))
    readonly property int lit_count: Math.round(Math.max(0, Math.min(1, root.value)) * root.count)

    implicitHeight: root.sphere

    Row {
        anchors.verticalCenter: parent.verticalCenter
        x: (root.width - width) / 2
        spacing: root.gap

        Repeater {
            model: root.count

            Sphere {
                required property int index
                width: root.sphere
                lit: index < root.lit_count
            }
        }
    }
}

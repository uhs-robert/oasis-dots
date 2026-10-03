// home/quickshell/.config/quickshell/components/goldeneye/BarRow.qml
import QtQuick
import "../../theme"
import "../../theme/Watch.js" as W

// The lock face's row of green bars as a progress meter: lit up to `value` (0-1), dim after.
Item {
    id: root

    property real value: 0
    readonly property int count: Math.max(6, Math.round(root.width / 26))
    readonly property int lit: Math.ceil(Math.max(0, Math.min(1, root.value)) * root.count - 1e-6)
    readonly property real gap: 5

    implicitHeight: 12

    Repeater {
        model: root.count

        Rectangle {
            required property int index
            x: index * (width + root.gap)
            width: (root.width - root.gap * (root.count - 1)) / root.count
            height: root.height
            color: index < root.lit ? Style.wk.bar_on : Style.wk.bar_off
        }
    }
}

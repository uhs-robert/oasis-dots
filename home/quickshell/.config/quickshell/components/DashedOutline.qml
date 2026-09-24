// home/quickshell/.config/quickshell/components/DashedOutline.qml
import QtQuick

Item {
    id: root

    property color color: "transparent"
    readonly property int dash: 4
    readonly property int gap: 3
    readonly property int across: Math.max(0, Math.ceil(root.width / (root.dash + root.gap)))
    readonly property int down: Math.max(0, Math.ceil(root.height / (root.dash + root.gap)))

    Repeater {
        model: root.across * 2

        Rectangle {
            required property int index
            readonly property int slot: index % root.across
            x: slot * (root.dash + root.gap)
            y: index < root.across ? 0 : root.height - 1
            width: Math.min(root.dash, root.width - x)
            height: 1
            color: root.color
        }
    }

    Repeater {
        model: root.down * 2

        Rectangle {
            required property int index
            readonly property int slot: index % root.down
            x: index < root.down ? 0 : root.width - 1
            y: slot * (root.dash + root.gap)
            width: 1
            height: Math.min(root.dash, root.height - y)
            color: root.color
        }
    }
}

// home/quickshell/.config/quickshell/components/nes/PianoRoll.qml
import QtQuick
import "../../theme"

// A Zelda-ish piano roll as a Meter's art: a fixed tune of notes on a baseline, played up to the value.
Item {
    id: root

    property var meter: null
    property real value: root.meter ? root.meter.value : 0
    readonly property var tune: [0, 2, 4, 2, 5, 4, 2, 1, 3, 5, 3, 1, 0, 1, 3, 4]
    readonly property int count: Math.max(1, Math.floor(root.width / 4))
    readonly property int head: Math.round(Math.max(0, Math.min(1, root.value)) * root.count)
    readonly property real rise: Math.max(0.5, (root.height - 4) / 5)

    Rectangle {
        anchors.bottom: parent.bottom
        width: root.width * Math.max(0, Math.min(1, root.value))
        height: 1
        color: Theme.theme_primary
    }

    Rectangle {
        anchors.bottom: parent.bottom
        x: root.width * Math.max(0, Math.min(1, root.value))
        width: root.width - x
        height: 1
        color: Theme.bg_surface
    }

    Repeater {
        model: root.count

        Rectangle {
            required property int index

            x: index * 4
            y: root.height - 4 - Math.round(root.tune[index % root.tune.length] * root.rise)
            width: 2
            height: 2
            color: index === root.head - 1 ? Theme.fg_strong : index < root.head ? Theme.theme_primary : Theme.bg_surface
        }
    }
}

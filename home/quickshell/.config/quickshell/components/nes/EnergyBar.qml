// home/quickshell/.config/quickshell/components/nes/EnergyBar.qml
import QtQuick
import "../../theme"

// A Mega Man energy bar: thin segments with a bright core in a black case, filling up or rightward.
Item {
    id: root

    property var meter: null
    property real value: root.meter ? root.meter.value : 0
    property bool vertical: false
    // Lit segments take the hot color at or below this value.
    property real low_from: -1
    readonly property int step: 3
    readonly property int count: Math.max(1, Math.floor(((root.vertical ? root.height : root.width) - 4) / root.step))
    readonly property int lit: Math.round(Math.max(0, Math.min(1, root.value)) * root.count)
    readonly property color body: root.value <= root.low_from ? Theme.theme_label : Theme.theme_secondary

    Rectangle {
        anchors.fill: parent
        color: Theme.bg_crust
        border.width: 1
        border.color: Theme.fg_muted
    }

    Repeater {
        model: root.count

        Rectangle {
            required property int index
            readonly property bool on: index < root.lit

            x: root.vertical ? 2 : 2 + index * root.step
            y: root.vertical ? root.height - 2 - (index + 1) * root.step + 1 : 2
            width: root.vertical ? root.width - 4 : root.step - 1
            height: root.vertical ? root.step - 1 : root.height - 4
            color: on ? root.body : "transparent"

            Rectangle {
                visible: parent.on
                x: root.vertical ? Math.round(parent.width / 3) : 0
                y: root.vertical ? 0 : Math.round(parent.height / 3)
                width: root.vertical ? Math.max(1, Math.round(parent.width / 3)) : parent.width
                height: root.vertical ? parent.height : Math.max(1, Math.round(parent.height / 3))
                color: Theme.fg_strong
            }
        }
    }
}

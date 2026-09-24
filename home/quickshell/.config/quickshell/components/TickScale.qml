// home/quickshell/.config/quickshell/components/TickScale.qml
pragma ComponentBehavior: Bound
import QtQuick

// A 1px tick every `step` px along the item, every major_every-th one major; from_end hangs them off the bottom or right edge.
Item {
    id: root

    property bool vertical: false
    property bool from_end: false
    property real step: 10
    property int major_every: 5
    property real major_length: 10
    property real minor_length: 5
    property color major_color: "transparent"
    property color minor_color: root.major_color

    Repeater {
        model: Math.max(0, Math.floor((root.vertical ? root.height : root.width) / root.step) + 1)

        Rectangle {
            required property int index
            readonly property bool major: index % root.major_every === 0
            readonly property real length: major ? root.major_length : root.minor_length

            x: root.vertical ? (root.from_end ? root.width - length : 0) : index * root.step
            y: root.vertical ? index * root.step : (root.from_end ? root.height - length : 0)
            width: root.vertical ? length : 1
            height: root.vertical ? 1 : length
            color: major ? root.major_color : root.minor_color
        }
    }
}

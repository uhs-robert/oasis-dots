// home/quickshell/.config/quickshell/components/TickRuler.qml
pragma ComponentBehavior: Bound
import QtQuick

// A Meter drawn as a tick ruler: a baseline with a tick per segment that lights up with the level.
Item {
    id: root

    required property Item meter
    readonly property var st: root.meter.st
    readonly property real cell: root.width / root.meter.segment_count

    Repeater {
        model: root.meter.segment_count

        Item {
            id: cell
            required property int index
            readonly property bool lit: root.meter.busy
                ? index >= root.meter.busy_head && index < root.meter.busy_head + root.meter.busy_span
                : index < Math.round(root.meter.value * root.meter.segment_count)
            readonly property bool hot: cell.lit && (root.meter.hot || index >= Math.round(root.meter.hot_from * root.meter.segment_count))
            readonly property bool major: index % 5 === 0
            readonly property color ink: cell.hot ? root.st.meter_hot : cell.lit ? root.meter.on_color : "transparent"

            x: index * root.cell
            width: root.cell
            height: root.height

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: cell.lit ? 2 : 1
                color: cell.lit ? cell.ink : root.st.meter_off
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: 1
                height: Math.round(root.height * (cell.hot ? 1 : cell.lit || cell.major ? 0.75 : 0.42))
                color: cell.lit ? cell.ink : cell.major ? root.st.hairline : root.st.hairline_dim
            }
        }
    }
}

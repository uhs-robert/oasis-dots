// home/quickshell/.config/quickshell/components/Meter.qml
import QtQuick
import "../theme"

Item {
    id: root

    property real value: 0
    property bool hot: false
    readonly property int segment_count: 20
    readonly property int gap: 2
    readonly property real segment_width: Math.max(2, (width - gap * (segment_count - 1)) / segment_count)

    implicitWidth: segment_count * 3 + gap * (segment_count - 1)
    implicitHeight: 10

    Row {
        spacing: root.gap

        Repeater {
            model: root.segment_count

            Rectangle {
                required property int index

                width: root.segment_width
                height: root.implicitHeight
                radius: 1
                color: index < Math.round(root.value * root.segment_count)
                    ? (root.hot ? Theme.theme_label : Theme.theme_primary)
                    : Theme.bg_surface
            }
        }
    }
}

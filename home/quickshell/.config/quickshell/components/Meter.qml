// home/quickshell/.config/quickshell/components/Meter.qml
import QtQuick
import "../theme"

Item {
    id: root

    property real value: 0
    property bool hot: false
    // Lit segments from this fraction up take the hot color.
    property real hot_from: 1
    // Set on an inverse-selected row so the lit segments stay visible.
    property bool on_selection: false
    readonly property int segment_count: 20
    readonly property int gap: 2
    readonly property real segment_width: Math.max(2, (width - gap * (segment_count - 1)) / segment_count)

    implicitWidth: segment_count * 3 + gap * (segment_count - 1)
    implicitHeight: Style.px(10)

    Row {
        spacing: root.gap

        Repeater {
            model: root.segment_count

            Rectangle {
                required property int index

                width: root.segment_width
                height: root.implicitHeight
                radius: Style.meter_radius
                color: index < Math.round(root.value * root.segment_count)
                    ? (root.hot || index >= Math.round(root.hot_from * root.segment_count) ? Style.meter_hot : root.on_selection && Style.selection_inverse ? Style.selection_fg : Style.meter_on)
                    : root.on_selection && Style.selection_inverse ? Qt.alpha(Style.selection_fg, 0.25) : Style.meter_off
            }
        }
    }
}

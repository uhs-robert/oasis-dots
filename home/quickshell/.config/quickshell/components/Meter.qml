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
    property int segment_count: 20
    // Indeterminate: a short lit run sweeps across instead of showing value.
    property bool busy: false
    property real busy_pos: 0
    readonly property int busy_span: 4
    readonly property int busy_head: Math.floor(root.busy_pos * (root.segment_count + root.busy_span)) - root.busy_span
    property color on_color: Style.meter_on
    readonly property int gap: 2
    readonly property real segment_width: Math.max(2, (width - gap * (segment_count - 1)) / segment_count)

    implicitWidth: segment_count * 3 + gap * (segment_count - 1)
    implicitHeight: Style.px(10)

    NumberAnimation on busy_pos {
        running: root.busy
        loops: Animation.Infinite
        from: 0
        to: 1
        duration: 1400
    }

    Row {
        spacing: root.gap

        Repeater {
            model: root.segment_count

            Rectangle {
                id: segment
                required property int index
                readonly property bool lit: root.busy
                    ? index >= root.busy_head && index < root.busy_head + root.busy_span
                    : index < Math.round(root.value * root.segment_count)
                readonly property bool is_hot: root.hot || index >= Math.round(root.hot_from * root.segment_count)

                width: root.segment_width
                height: root.implicitHeight
                radius: Style.meter_radius
                color: segment.lit
                    ? (segment.is_hot ? Style.meter_hot : root.on_selection && Style.selection_inverse ? Style.selection_fg : root.on_color)
                    : root.on_selection && Style.selection_inverse ? Qt.alpha(Style.selection_fg, 0.25) : Style.meter_off

                // Lit segments shade down from meter_shade at the top.
                Rectangle {
                    visible: segment.lit && !segment.is_hot && Style.meter_shade.a > 0
                    anchors.fill: parent
                    radius: parent.radius
                    gradient: Gradient {
                        GradientStop { position: 0; color: Style.meter_shade }
                        GradientStop { position: 0.6; color: Qt.alpha(Style.meter_shade, 0) }
                    }
                }
            }
        }
    }
}

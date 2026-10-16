pragma ComponentBehavior: Bound
import QtQuick
import qs.theme

// A gauge as a targeting scale: thin ticks lit up to `value` (0-1), every fifth one long. With `marked`, a
// lock-coloured hairline stands at `value`, for a reading that is a point in a range rather than an amount.
Item {
    id: root

    property real value: 0
    property color color: Style.text_accent
    property bool marked: false
    property color mark_color: Theme.theme_label

    readonly property int pitch: 4
    readonly property int tick_count: Math.max(2, Math.floor((root.width - 1) / root.pitch) + 1)
    readonly property real clamped: Math.max(0, Math.min(1, root.value))
    readonly property real mark_x: Math.round(root.clamped * (root.tick_count - 1)) * root.pitch

    implicitHeight: Style.fs(-4)

    Repeater {
        model: root.tick_count

        Rectangle {
            id: tick
            required property int index
            readonly property bool is_major: tick.index % 5 === 0
            readonly property bool is_lit: tick.index * root.pitch <= root.mark_x && root.clamped > 0

            x: tick.index * root.pitch
            width: 1
            height: tick.is_major ? root.height * 0.8 : root.height * 0.45
            anchors.verticalCenter: parent.verticalCenter
            color: Qt.alpha(root.color, tick.is_lit ? 0.9 : 0.22)
        }
    }

    Rectangle {
        visible: root.marked
        x: root.mark_x - 0.5
        width: 2
        height: root.height + 2
        anchors.verticalCenter: parent.verticalCenter
        color: root.mark_color
    }
}

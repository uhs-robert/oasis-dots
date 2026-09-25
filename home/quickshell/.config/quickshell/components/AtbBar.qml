// home/quickshell/.config/quickshell/components/AtbBar.qml
import QtQuick
import "../theme"

// An ATB gauge: one bar on a dark track, lit from shade_color at the top into fill_color; `ticks` notches it like a Limit gauge.
Item {
    id: root

    readonly property var st: Style.for_item(root)

    property real value: 0
    property color fill_color: root.st.meter_on
    property color shade_color: root.st.meter_shade.a > 0 ? root.st.meter_shade : root.fill_color
    // The part past this fraction takes the hot color.
    property real hot_from: 1
    property color hot_color: root.st.meter_hot
    property bool ticks: false
    // A lit run at `busy_pos` instead of the value, for indeterminate meters.
    property bool busy: false
    property real busy_pos: 0
    // Shades the fill left to right instead of top to bottom.
    property bool horizontal: false

    readonly property real v: Math.max(0, Math.min(1, root.value))
    readonly property real inner_w: Math.max(0, root.width - 2)
    readonly property real inner_h: Math.max(0, root.height - 2)

    implicitWidth: 60
    implicitHeight: root.st.meter_height > 0 ? root.st.meter_height : 7

    Rectangle {
        anchors.fill: parent
        radius: root.st.meter_radius
        color: root.st.meter_off
        border.width: 1
        border.color: root.st.meter_outline.a > 0 ? root.st.meter_outline : Theme.fg_muted
    }

    Item {
        x: 1
        y: 1
        width: root.inner_w
        height: root.inner_h
        clip: true

        Rectangle {
            id: fill
            x: root.busy ? (root.inner_w * 1.25) * root.busy_pos - root.inner_w * 0.25 : 0
            width: root.busy ? root.inner_w * 0.25 : root.inner_w * Math.min(root.v, root.hot_from)
            height: parent.height
            gradient: Gradient {
                orientation: root.horizontal ? Gradient.Horizontal : Gradient.Vertical
                GradientStop { position: 0; color: root.horizontal ? root.fill_color : root.shade_color }
                GradientStop { position: 1; color: root.horizontal ? root.shade_color : root.fill_color }
            }
        }

        Rectangle {
            visible: !root.busy && root.v > root.hot_from
            x: fill.width
            width: root.inner_w * (root.v - root.hot_from)
            height: parent.height
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.tint(root.hot_color, Qt.alpha(Theme.fg_strong, 0.5)) }
                GradientStop { position: 1; color: root.hot_color }
            }
        }

        Repeater {
            model: root.ticks ? Math.floor(root.inner_w / 8) : 0

            Rectangle {
                required property int index
                x: index * 8 + 7
                width: 1
                height: parent.height
                color: Qt.alpha(Theme.bg_crust, 0.35)
            }
        }
    }
}

// home/quickshell/.config/quickshell/popups/weather/BattleGauge.qml
import QtQuick
import "../../theme"

// An NES HP bar: a flat fill in a white outline; `marker` adds a tick standing out of the bar at the fill's end.
Item {
    id: root

    property real value: 0
    property color fill_color: Theme.fg_strong
    property bool marker: false
    readonly property real v: Math.max(0, Math.min(1, root.value))
    readonly property real inner_w: Math.max(0, root.width - 4)

    implicitHeight: 8

    Rectangle {
        anchors.fill: parent
        color: Theme.bg_crust
        border.width: 1
        border.color: Theme.fg_strong
    }

    Rectangle {
        x: 2
        y: 2
        width: Math.round(root.inner_w * root.v)
        height: root.height - 4
        color: root.fill_color
    }

    Rectangle {
        visible: root.marker
        x: 2 + Math.round(root.inner_w * root.v) - 1
        y: -2
        width: 2
        height: root.height + 4
        color: Theme.fg_strong
    }
}

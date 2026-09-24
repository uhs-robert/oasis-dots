// home/quickshell/.config/quickshell/popups/weather/RangeCaps.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"

// Ring end caps on a 1px range line; fills its parent.
Item {
    id: root

    anchors.fill: parent

    Repeater {
        model: root.visible ? [0, 1] : []

        Rectangle {
            required property int modelData
            x: (root.width - width) / 2
            y: modelData === 0 ? -3 : root.height - 3
            width: 6
            height: 6
            radius: 3
            color: Theme.bg_crust
            border.width: 1
            border.color: Style.text_strong
        }
    }
}

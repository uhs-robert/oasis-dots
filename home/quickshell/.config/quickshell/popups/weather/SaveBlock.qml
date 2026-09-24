// home/quickshell/.config/quickshell/popups/weather/SaveBlock.qml
import QtQuick
import "../../theme"
import "../../services"

// A day's memory card save block heading its column; the selected save lifts off its shadow.
Item {
    id: root

    property var day: ({})
    property bool selected: false
    property real block_size: 40
    readonly property int lift: 6

    implicitWidth: root.block_size + 3
    implicitHeight: root.block_size + root.lift + 3

    Rectangle {
        visible: root.selected
        x: (root.width - root.block_size) / 2 + 3
        y: root.lift + 3
        width: root.block_size
        height: root.block_size
        radius: 3
        color: Qt.alpha(Theme.bg_shadow, 0.7)
    }

    SaveIcon {
        x: (root.width - root.block_size) / 2
        y: root.selected ? 0 : root.lift
        size: root.block_size
        code: root.day.code !== undefined ? root.day.code : -1
        lit: root.selected

        Behavior on y {
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutQuad
            }
        }
    }
}

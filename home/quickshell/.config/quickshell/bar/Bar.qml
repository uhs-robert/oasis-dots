// home/quickshell/.config/quickshell/bar/Bar.qml
import QtQuick
import "../theme"
import "../services"

Item {
    id: root

    Island {
        id: left_island
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        bg_color: Theme.bg_core
        cap_right: true

        Text {
            text: "left"
            color: Theme.fg_core
            font.family: Theme.font_family
            font.pixelSize: Theme.font_size
        }
    }

    Island {
        id: center_island
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        bg_color: Theme.bg_mantle
        cap_left: true
        cap_right: true

        Component.onCompleted: Popups.register_default("test", center_island)
        onClicked: Popups.toggle("test", center_island)

        Text {
            text: "center"
            color: Theme.fg_core
            font.family: Theme.font_family
            font.pixelSize: Theme.font_size
        }
    }

    Island {
        id: right_island
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        bg_color: Theme.bg_core
        cap_left: true

        Text {
            text: "right"
            color: Theme.fg_core
            font.family: Theme.font_family
            font.pixelSize: Theme.font_size
        }
    }
}

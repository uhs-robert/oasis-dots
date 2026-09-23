// home/quickshell/.config/quickshell/bar/Bar.qml
import QtQuick
import "../theme"
import "../services"
import "modules"

Item {
    id: root

    property string screen_name: ""
    readonly property bool compact: screen_name.indexOf("eDP") === 0
    readonly property real center_width: center_island.body_item.width

    Island {
        id: left_island
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        bg_color: Theme.bg_core
        cap_right: true

        StartButton {
            compact: root.compact
            island: left_island.body_item
            island_color: left_island.bg_color
        }

        Workspaces {
            screen_name: root.screen_name
            compact: root.compact
        }
    }

    Island {
        id: center_island
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        bg_color: Theme.bg_mantle
        cap_left: true
        cap_right: true

        Component.onCompleted: Popups.register_default("clock", center_island.body_item, center_island.bg_color)
        onClicked: Popups.toggle("clock", center_island.body_item, center_island.bg_color)

        Clock {
            compact: root.compact
        }
    }

    Island {
        id: right_island
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        bg_color: Theme.bg_core
        cap_left: true

        Tray {}

        Volume {
            compact: root.compact
            island: right_island.body_item
            island_color: right_island.bg_color
        }

        Battery {
            compact: root.compact
            island: right_island.body_item
            island_color: right_island.bg_color
        }

        Hardware {
            compact: root.compact
        }

        Bluetooth {
            compact: root.compact
            island: right_island.body_item
            island_color: right_island.bg_color
        }
    }
}

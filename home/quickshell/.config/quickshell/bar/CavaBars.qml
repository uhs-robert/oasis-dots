// home/quickshell/.config/quickshell/bar/CavaBars.qml
import QtQuick
import "../theme"
import "../services"

// Cava drawn inside an island's bottom edge, so it always sits on the island's own color.
Item {
    id: root

    property bool active: MediaState.playing
    readonly property int bar_count: CavaState.bar_count

    height: 6
    opacity: root.active ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        NumberAnimation { duration: 250; easing.type: Easing.InOutCubic }
    }

    Row {
        anchors.fill: parent

        Repeater {
            model: root.bar_count

            Rectangle {
                required property int index
                readonly property real level: CavaState.levels[index] || 0

                anchors.bottom: parent.bottom
                width: root.width / root.bar_count
                height: 1 + level * (root.height - 1)
                color: Theme.theme_primary
                opacity: 0.5 + 0.5 * level
            }
        }
    }
}

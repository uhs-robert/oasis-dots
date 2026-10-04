// home/quickshell/.config/quickshell/popups/media/CavaStrip.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"

// Subtle cava visualizer for the bottom edge of the popup.
Item {
    id: root

    Layout.fillWidth: true
    Layout.preferredHeight: 18
    Layout.topMargin: 4

    readonly property int bar_count: 28
    readonly property bool active: MediaState.playing

    RowLayout {
        anchors.fill: parent
        spacing: 3

        Repeater {
            model: root.bar_count

            Rectangle {
                id: cava_bar
                required property int index
                readonly property int src_index: Math.floor(cava_bar.index * CavaState.bar_count / root.bar_count)
                readonly property real level: CavaState.levels[cava_bar.src_index] || 0

                Layout.fillWidth: true
                Layout.alignment: Qt.AlignBottom
                height: root.active ? Math.max(2, cava_bar.level * 18) : 2
                radius: Style.radius(1)
                color: Style.pal.primary
                opacity: root.active ? 0.25 : 0

                Behavior on height { NumberAnimation { duration: 90 } }
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }
        }
    }
}

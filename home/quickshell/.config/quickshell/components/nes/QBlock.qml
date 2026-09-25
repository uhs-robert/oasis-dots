// home/quickshell/.config/quickshell/components/nes/QBlock.qml
import QtQuick
import "../../theme"

// A Mario ? block: orange with corner rivets and a ?, brown once hit, or an empty outline.
Rectangle {
    id: root

    // "q", "hit" or "empty".
    property string kind: "q"
    property bool mark: true
    readonly property color brown: Qt.tint(Theme.bg_surface, Qt.alpha(Theme.bright_yellow, 0.4))

    color: root.kind === "q" ? Theme.bright_yellow : root.kind === "hit" ? root.brown : "transparent"
    border.width: 1
    border.color: root.kind === "empty" ? Theme.bg_surface : Theme.bg_crust

    Repeater {
        model: root.kind === "empty" ? [] : [[0, 0], [1, 0], [0, 1], [1, 1]]

        Rectangle {
            required property var modelData
            readonly property int dot: root.height >= 16 ? 2 : 1
            x: modelData[0] ? root.width - 2 - dot : 2
            y: modelData[1] ? root.height - 2 - dot : 2
            width: dot
            height: dot
            color: Theme.bg_crust
        }
    }

    Text {
        visible: root.mark && root.kind === "q"
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: 1
        text: "?"
        color: Theme.bg_crust
        font.family: "Press Start 2P"
        font.pixelSize: 8
    }
}

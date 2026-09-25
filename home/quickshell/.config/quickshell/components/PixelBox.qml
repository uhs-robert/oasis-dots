// home/quickshell/.config/quickshell/components/PixelBox.qml
pragma ComponentBehavior: Bound
import QtQuick

// A square box with stacked hard rings, outermost first, like a Pokémon text box border.
Item {
    id: root

    property color fill: "transparent"
    property var rings: []
    property int ring_width: 2
    readonly property int edge: root.rings.length * root.ring_width

    Rectangle {
        anchors.fill: parent
        anchors.margins: root.edge
        color: root.fill
    }

    Repeater {
        model: root.rings

        Rectangle {
            required property color modelData
            required property int index
            anchors.fill: parent
            anchors.margins: index * root.ring_width
            color: "transparent"
            border.width: root.ring_width
            border.color: modelData
        }
    }
}

// home/quickshell/.config/quickshell/components/SegBar.qml
pragma ComponentBehavior: Bound
import QtQuick

// A segmented bar, left to right or bottom to top; segments first_lit to last_lit (inclusive) take on_color.
Item {
    id: root

    property int count: 10
    property int first_lit: 0
    property int last_lit: -1
    property bool vertical: false
    property real gap: 1.5
    property color on_color: "white"
    property color off_color: "transparent"
    readonly property real step: ((root.vertical ? root.height : root.width) + root.gap) / Math.max(1, root.count)

    Repeater {
        model: root.count

        Rectangle {
            required property int index
            readonly property real along: index * root.step

            x: root.vertical ? 0 : along
            y: root.vertical ? root.height - along - height : 0
            width: root.vertical ? root.width : Math.max(1, root.step - root.gap)
            height: root.vertical ? Math.max(1, root.step - root.gap) : root.height
            color: index >= root.first_lit && index <= root.last_lit ? root.on_color : root.off_color
        }
    }
}

// home/quickshell/.config/quickshell/components/FrameTicks.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

// The style's hairline frame marks: a tick scale on the top or left edge, with corner crosses or a corner ring.
Item {
    id: root

    property var st: Style.for_item(root)
    readonly property string mode: root.st.frame_ticks
    readonly property bool on_top: root.mode === "top"

    visible: root.mode !== ""

    TickScale {
        y: root.on_top ? 0 : 14
        width: root.on_top ? root.width : 7
        height: root.on_top ? 10 : Math.max(0, root.height - 28)
        vertical: !root.on_top
        step: root.on_top ? 10 : 8
        major_length: root.on_top ? 10 : 7
        minor_length: root.on_top ? 5 : 4
        major_color: root.st.hairline
        minor_color: root.st.hairline_dim
    }

    Rectangle {
        visible: root.on_top
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: root.st.hairline_dim
    }

    Repeater {
        model: root.on_top ? [0, 1] : []

        Item {
            required property int modelData
            x: modelData === 0 ? 0 : root.width - 9
            y: root.height - 9
            width: 9
            height: 9

            Rectangle {
                y: 4
                width: 9
                height: 1
                color: root.st.text_strong
            }

            Rectangle {
                x: 4
                width: 1
                height: 9
                color: root.st.text_strong
            }
        }
    }

    Rectangle {
        visible: !root.on_top
        x: root.width - 11
        y: 3
        width: 8
        height: 8
        radius: 4
        color: Theme.bg_crust
        border.width: 1
        border.color: root.st.text_strong
    }
}

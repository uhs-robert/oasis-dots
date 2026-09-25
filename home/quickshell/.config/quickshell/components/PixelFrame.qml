// home/quickshell/.config/quickshell/components/PixelFrame.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

// The pixel screen's edge: a dark, pixel_border, dark double border over faint static scan rows.
Item {
    id: root

    property var st: Style.for_item(root)
    property color middle: root.st.pixel_border
    property bool scan_rows: true
    readonly property color dark: root.st.shade_0.a > 0 ? root.st.shade_0 : root.st.frame_border_color
    readonly property int edge: frame_box.edge

    Item {
        visible: root.scan_rows
        anchors.fill: parent
        anchors.margins: root.edge
        clip: true

        Repeater {
            model: root.scan_rows ? Math.max(0, Math.ceil(parent.height / 3)) : 0

            Rectangle {
                required property int index
                y: index * 3
                width: parent.width
                height: 1
                color: Qt.alpha(Theme.bg_crust, 0.12)
            }
        }
    }

    PixelBox {
        id: frame_box
        anchors.fill: parent
        rings: [root.dark, root.middle, root.dark]
    }
}

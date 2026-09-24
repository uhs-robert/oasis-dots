// home/quickshell/.config/quickshell/components/FrameInset.qml
import QtQuick
import "../theme"

// The style's inner ring, frame_inset_gap inside the frame's border; set the frame's outer radii.
Rectangle {
    id: root

    property real top_radius: 0
    property real bottom_radius: 0
    property var st: Style.for_item(root)
    property real edge: root.st.frame_border_width
    property real top_offset: 0
    readonly property real offset: root.edge + root.st.frame_inset_gap

    visible: root.st.frame_inset_width > 0
    anchors.fill: parent
    anchors.margins: root.offset
    anchors.topMargin: root.offset + root.top_offset
    color: "transparent"
    topLeftRadius: Math.max(0, root.top_radius - root.offset)
    topRightRadius: Math.max(0, root.top_radius - root.offset)
    bottomLeftRadius: Math.max(0, root.bottom_radius - root.offset)
    bottomRightRadius: Math.max(0, root.bottom_radius - root.offset)
    border.width: root.st.frame_inset_width
    border.color: root.st.frame_inset_color
}

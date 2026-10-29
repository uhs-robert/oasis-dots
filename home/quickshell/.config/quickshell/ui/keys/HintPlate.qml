import QtQuick
import qs.theme

// The plate a hint bar sits on, sized to its one child (the content) with the style's frame colours. Where it goes is up
// to the caller.
Rectangle {
    id: root
    default property alias contents: holder.data
    // Draws no fill or border, for a plate that sits on a surface which already has its own (a frame drawer's body).
    property bool plain: false
    readonly property Item content: holder.children.length > 0 ? holder.children[0] : null

    implicitWidth: (root.content ? root.content.width : 0) + 28
    implicitHeight: (root.content ? root.content.implicitHeight : 0) + 16
    radius: Style.frame_radius
    color: root.plain ? "transparent" : Style.frame_color
    border.width: root.plain ? 0 : Style.frame_border_width
    border.color: Style.frame_border_color
    Item {
        id: holder
        anchors.fill: parent
    }
}

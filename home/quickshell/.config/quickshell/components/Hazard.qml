// home/quickshell/.config/quickshell/components/Hazard.qml
import QtQuick

// Static diagonal stripes, `line` wide every `tile` px along each axis, over an optional ground.
Rectangle {
    id: root

    property color stripe: "transparent"
    property real tile: 8
    property real line: 3

    readonly property string tile_url: "data:image/svg+xml;utf8," + encodeURIComponent("<svg xmlns='http://www.w3.org/2000/svg' width='" + root.tile + "' height='" + root.tile + "'><path d='M-1 1l2-2M0 " + root.tile + "L" + root.tile + " 0M" + (root.tile - 1) + " " + (root.tile + 1) + "l2-2' stroke='" + Qt.rgba(root.stripe.r, root.stripe.g, root.stripe.b, 1) + "' stroke-opacity='" + root.stripe.a + "' stroke-width='" + root.line + "'/></svg>")

    color: "transparent"
    clip: true

    Image {
        visible: root.stripe.a > 0
        anchors.fill: parent
        fillMode: Image.Tile
        smooth: false
        source: root.stripe.a > 0 ? root.tile_url : ""
    }
}

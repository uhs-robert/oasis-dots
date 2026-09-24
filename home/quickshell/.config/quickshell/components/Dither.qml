// home/quickshell/.config/quickshell/components/Dither.qml
import QtQuick

// A static 2x2 checker; the corner squares stay clear so it never spills past rounded corners.
Item {
    id: root

    property color color: "transparent"
    property real radius: 0
    property real top_radius: 0
    // Edges that slope inward toward the bottom, like the bar's island caps.
    property real slant_left: 0
    property real slant_right: 0

    readonly property string tile: "data:image/svg+xml;utf8," + encodeURIComponent("<svg xmlns='http://www.w3.org/2000/svg' width='4' height='4'><path d='M0 0h2v2H0zM2 2h2v2H2z' fill='" + Qt.rgba(root.color.r, root.color.g, root.color.b, 1) + "' fill-opacity='" + root.color.a + "'/></svg>")
    readonly property var bands: {
        if (root.slant_left > 0 || root.slant_right > 0) {
            const rows = [];
            for (let y = 0; y < root.height; y += 2) {
                const t = y / root.height;
                const x = root.slant_left * t;
                rows.push({ x: x, y: y, w: root.width - x - root.slant_right * t, h: 2 });
            }
            return rows;
        }
        return [
            { x: root.top_radius, y: 0, w: root.width - root.top_radius * 2, h: root.top_radius },
            { x: 0, y: root.top_radius, w: root.width, h: root.height - root.top_radius - root.radius },
            { x: root.radius, y: root.height - root.radius, w: root.width - root.radius * 2, h: root.radius }
        ];
    }

    visible: root.color.a > 0

    Repeater {
        model: root.visible ? root.bands : []

        Item {
            required property var modelData
            x: modelData.x
            y: modelData.y
            width: Math.max(0, modelData.w)
            height: Math.max(0, modelData.h)
            clip: true

            Image {
                x: -parent.x
                y: -parent.y
                width: root.width
                height: root.height
                fillMode: Image.Tile
                smooth: false
                source: root.tile
            }
        }
    }
}

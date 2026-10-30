import QtQuick
import qs.theme

// Monitor select's map: the screens that have a bar, as they sit, the picked one lit. Reads BarEditor, so it takes no
// inputs but a height cap for a caller whose room is short.
Item {
    id: root

    // The map never grows taller than this; the tiles shrink to fit.
    property real max_height: Infinity
    readonly property var bounds: {
        let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
        for (const m of BarEditor.monitors) {
            x0 = Math.min(x0, m.x);
            y0 = Math.min(y0, m.y);
            x1 = Math.max(x1, m.x + m.w);
            y1 = Math.max(y1, m.y + m.h);
        }
        return { x: x0, y: y0, w: Math.max(1, x1 - x0), h: Math.max(1, y1 - y0) };
    }
    readonly property real map_height: Math.min(root.max_height, BarEditor.map_height(root.bounds.w, root.bounds.h))
    readonly property real tile_scale: Math.min(520 / root.bounds.w, root.map_height / root.bounds.h)

    implicitWidth: 520
    implicitHeight: root.map_height

    Repeater {
        model: BarEditor.monitors
        Rectangle {
            id: tile
            required property var modelData
            readonly property bool picked: modelData.name === BarEditor.focus_screen
            x: (modelData.x - root.bounds.x) * root.tile_scale
            y: (modelData.y - root.bounds.y) * root.tile_scale
            width: modelData.w * root.tile_scale - 4
            height: modelData.h * root.tile_scale - 4
            radius: Math.min(Style.frame_radius, 6)
            color: tile.picked ? Qt.alpha(Style.accent_color, 0.3) : "transparent"
            border.width: tile.picked ? 2 : 1
            border.color: tile.picked ? Style.accent_color : Style.frame_border_color
            Rectangle {
                width: parent.width
                height: 8
                color: tile.picked ? Style.accent_color : Style.frame_border_color
            }
            Text {
                anchors.centerIn: parent
                width: parent.width - 8
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: tile.modelData.name + "\n" + BarEditor.tag_of(tile.modelData.name)
                color: Style.text_fg
                font.family: Style.font_family
                font.pixelSize: Style.fs(-1)
            }
        }
    }
}

// home/quickshell/.config/quickshell/components/picker/cursors/Pokemon.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../../theme"
import "../../../services"
import "../.."

// Game Boy party ▶ arrow pointing at the sampled pixel, tip a few px short of it, plus a tiny dot on the pixel.
Item {
    id: root

    required property string screen_name
    required property point origin
    required property bool target_mode

    readonly property point at: Screenshot.cursor_point
    readonly property int cx: Math.round(root.at.x)
    readonly property int cy: Math.round(root.at.y)
    readonly property int gap: 4

    visible: Style.picker_skin === "pokemon" && Screenshot.phase === "select" && Screenshot.cursor_screen === root.screen_name && !root.target_mode

    PixelSprite {
        id: arrow
        pixel: 3
        rows: ["3...", "33..", "333.", "3333", "333.", "33..", "3..."]
        x: root.cx - arrow.width - root.gap
        y: root.cy - arrow.height / 2
    }

    Rectangle {
        x: root.cx - 1
        y: root.cy - 1
        width: 3
        height: 3
        color: Theme.bg_shadow
    }
}

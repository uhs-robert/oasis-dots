import QtQuick
import qs.theme
import qs.services
import qs.ui.effects
import "Slimes.js" as Slimes

// A Dragon Quest slime leading a workspace pill: grey metal slime when empty, blue with apps, a hopping king on the focused one. The workspace's icons sit to its right.
Item {
    id: root

    property bool empty: false
    // Shown on its monitor; the focused workspace is also active.
    property bool active: false
    property bool focused: false
    property int pixel: 2

    readonly property int underline_height: 2
    readonly property int sprite_size: Slimes.SIZE * root.pixel
    readonly property int edge: 2
    property bool hopped: false

    function slime_colors(body: color, shine: color): var {
        return [Style.pal.bg_crust, Style.pal.fg_strong, Style.pal.yellow, Style.pal.bright_yellow, body, shine, Style.pal.fg_dim, Style.pal.red];
    }

    PixelSprite {
        x: root.edge
        y: root.height - root.underline_height - 2 * root.edge - height - (root.hopped ? root.pixel : 0)
        pixel: root.pixel
        colors: root.empty ? root.slime_colors(Style.pal.fg_muted, Style.pal.fg_dim) : root.slime_colors(Style.pal.blue, Style.pal.bright_blue)
        rows: root.focused ? Slimes.KING_SLIME : Slimes.SLIME
    }

    Rectangle {
        visible: root.active
        anchors.bottom: parent.bottom
        // Lifted off the pill's bottom edge, which the NES bar's frame rule paints over.
        anchors.bottomMargin: root.edge
        width: parent.width
        height: root.underline_height
        color: root.focused ? Style.pal.yellow : Style.pal.blue
    }

    // A one-sprite-pixel hop in place of a smooth bob, so the king stays on the pixel grid.
    Timer {
        running: root.focused && root.visible && Power.on_ac
        interval: 500
        repeat: true
        onTriggered: root.hopped = !root.hopped
        onRunningChanged: if (!running) root.hopped = false
    }
}

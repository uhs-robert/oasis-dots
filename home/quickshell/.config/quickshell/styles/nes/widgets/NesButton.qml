import QtQuick
import qs.theme
import qs.ui.effects

// An NES pad button as a pixel sprite: round red A/B, grey rubber START/SELECT pills, or the D-pad with its pressed arms lit.
Row {
    id: root

    property string button: ""
    property real size: 14
    // Four shades, darkest first, redraw the pad in a Game Boy palette instead of NES red and grey.
    property var shades: []
    readonly property bool shaded: root.shades.length === 4
    readonly property int pixel: root.size < 11 ? 1 : 2
    readonly property bool round: root.button === "a" || root.button === "b"
    readonly property bool pill: root.button === "start" || root.button === "select"
    readonly property color red: Qt.tint("#c8102e", Qt.alpha(Theme.red, 0.45))
    readonly property color grey: Qt.tint("#9a9a9a", Qt.alpha(Theme.fg_dim, 0.4))
    // One arm lights per single key (dpad_up and so on); dpad_v and dpad_h light both arms of an axis.
    readonly property string arm_up: root.button === "dpad_up" || root.button === "dpad_v" ? "2" : "1"
    readonly property string arm_down: root.button === "dpad_down" || root.button === "dpad_v" ? "2" : "1"
    readonly property string arm_left: root.button === "dpad_left" || root.button === "dpad_h" ? "2" : "1"
    readonly property string arm_right: root.button === "dpad_right" || root.button === "dpad_h" ? "2" : "1"

    spacing: 3

    PixelSprite {
        anchors.verticalCenter: parent.verticalCenter
        pixel: root.pixel
        rows: root.round ? ["..000..", ".01110.", "0121110", "0111110", "0111110", ".01110.", "..000.."]
            : root.pill ? [".00000000.", "0112222110", "0111111110", ".00000000."]
            : ["..UUU..", "..UUU..", "LL111RR", "LL111RR", "LL111RR", "..DDD..", "..DDD.."].map(r => r.replace(/U/g, root.arm_up).replace(/D/g, root.arm_down).replace(/L/g, root.arm_left).replace(/R/g, root.arm_right))
        colors: root.shaded ? (root.round ? [root.shades[0], root.shades[2], root.shades[3], "transparent"]
                : root.pill ? [root.shades[0], root.shades[1], root.shades[2], "transparent"]
                : ["transparent", root.shades[0], root.shades[3], "transparent"])
            : root.round ? [Qt.darker(root.red, 1.8), root.red, Qt.tint(root.red, Qt.alpha(Theme.fg_strong, 0.45)), "transparent"]
            : root.pill ? [Qt.darker(root.grey, 2.2), root.grey, Qt.tint(root.grey, Qt.alpha(Theme.fg_strong, 0.5)), "transparent"]
            : ["transparent", Theme.fg_muted, Theme.fg_strong, "transparent"]
    }

    Text {
        visible: root.round || root.pill
        anchors.verticalCenter: parent.verticalCenter
        text: root.button.toUpperCase()
        color: root.shaded ? root.shades[3] : root.red
        font.family: "Press Start 2P"
        font.pixelSize: 8
    }
}

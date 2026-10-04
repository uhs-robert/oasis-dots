// home/quickshell/.config/quickshell/lock/skins/ui/ModeIndicator.qml
import QtQuick

// "-- INSERT --" bottom-left while typing a password; a skin may set mode_indicator ("shared", "own", "none"), mode_color and mode_font.
Text {
    id: root

    property var skin: null
    property var ctx: null
    property string font_fallback: ""

    readonly property string choice: root.skin && root.skin.mode_indicator ? root.skin.mode_indicator : "shared"

    visible: !!root.ctx && root.ctx.insert && !root.ctx.granted && !root.ctx.saver && root.choice === "shared"
    enabled: false
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.leftMargin: Math.max(12, parent.width * 0.012)
    anchors.bottomMargin: Math.max(8, parent.height * 0.012)
    text: "-- INSERT --"
    color: root.skin && root.skin.mode_color ? root.skin.mode_color : root.ctx ? root.ctx.tint_bright : "white"
    font.family: root.skin && root.skin.mode_font ? root.skin.mode_font : root.font_fallback
    font.pixelSize: Math.max(13, parent.height * 0.018)
}

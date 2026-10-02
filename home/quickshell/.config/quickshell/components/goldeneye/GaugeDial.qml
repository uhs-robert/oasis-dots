// home/quickshell/.config/quickshell/components/goldeneye/GaugeDial.qml
import QtQuick
import "../../theme"
import "../../lock/skins/goldeneye/Watch.js" as W

// A level as the watch dial: the warm arc fills first (to 50%), then the blue one, bottom up in 16 whole steps; past 100% the blue arc turns red.
Item {
    id: root

    property real value: 0
    property bool muted: false
    property string label: ""
    // Shown in place of the percentage when set, e.g. a device count.
    property string readout: ""
    property real size: 112
    // Low charge: the warm arc turns red.
    property bool low: false
    readonly property bool over: root.value > 1.0001
    readonly property int steps: Math.max(0, Math.min(16, Math.ceil(Math.min(1, root.value) * 16 - 1e-6)))
    readonly property color digit_color: root.muted || root.over ? Style.pal.error : Style.wk.lit

    implicitWidth: root.size
    implicitHeight: root.size

    DialFace {
        width: root.size
        warm_colors: root.low ? [W.red, W.red, W.red, W.red, W.red, W.red, W.red, W.red] : W.warm
        warm_lit: Math.min(8, root.steps)
        cold_lit: Math.max(0, root.steps - 8)
        from_bottom: true
        cold_colors: root.over ? [W.red, W.red, W.red, W.red, W.red, W.red, W.red, W.red] : W.cold_lit
        arc_opacity: root.muted ? 0.35 : 1

        Column {
            anchors.centerIn: parent
            spacing: root.size * 0.02

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.readout !== "" ? root.readout : Math.round(root.value * 100)
                color: root.digit_color
                opacity: root.muted ? 0.7 : 1
                font.family: W.digit_font
                font.pixelSize: root.size * 0.2
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: text !== ""
                text: root.muted ? "MUTE" : root.label
                color: root.muted ? Style.pal.error : Style.wk.soft
                font.family: W.mono_font
                font.pixelSize: root.size * 0.08
                font.letterSpacing: 1
            }
        }
    }
}

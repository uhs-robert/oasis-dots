import QtQuick
import qs.theme
import "../../theme/Watch.js" as W

// goldeneye: a small LCD window like a watch complication, holding the minutes in segment digits before a meeting and MTG in the bar font during one, as DSEG7 has no M.
MarkerBase {
    id: root

    readonly property real digit_size: Style.bar_font_size + 1
    readonly property color lit: root.on_accent ? root.ink : Theme.theme_primary_light

    implicitWidth: Math.ceil(Math.max(upcoming_width.advanceWidth, mtg_width.advanceWidth)) + 12
    implicitHeight: Math.ceil(root.digit_size) + 8

    // Sized from the widest reading, so the minutes ticking down do not resize the window.
    TextMetrics {
        id: upcoming_width
        font.family: W.digit_font
        font.pixelSize: root.digit_size
        text: "00"
    }

    TextMetrics {
        id: mtg_width
        font: root.text_font
        text: "MTG"
    }

    Rectangle {
        anchors.fill: parent
        radius: 2
        color: root.on_accent ? "transparent" : Qt.tint(Theme.bg_crust, Qt.alpha(Theme.theme_primary, 0.1))
        border.width: 1
        border.color: root.on_accent ? root.ink : Qt.alpha(Theme.theme_primary, 0.5)
    }

    Text {
        id: readout
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 1
        text: root.in_meeting ? "MTG" : String(Math.min(99, root.minutes)).padStart(2, "0")
        textFormat: Text.PlainText
        color: root.in_meeting && !root.on_accent ? Style.meter_hot : root.lit
        font.family: root.in_meeting ? root.text_font.family : W.digit_font
        font.pixelSize: root.in_meeting ? root.text_font.pixelSize : root.digit_size
    }
}

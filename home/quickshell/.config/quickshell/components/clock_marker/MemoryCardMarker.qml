import QtQuick
import qs.theme
import qs.ui.effects
import qs.ui.frames

// ps1: a memory-card save slot in the frame's dithered shade, holding 12m before a meeting and a lit MTG during one.
MarkerBase {
    id: root

    readonly property real pad: 6
    readonly property color accent: root.on_accent ? root.ink : Theme.theme_primary_light

    implicitWidth: Math.ceil(Math.max(upcoming_width.advanceWidth, mtg_width.advanceWidth)) + root.pad * 2
    implicitHeight: label.implicitHeight + 4

    // Sized from the widest of both states, so the minutes ticking down do not resize the clock.
    TextMetrics {
        id: upcoming_width
        font: root.text_font
        text: "00m"
    }

    TextMetrics {
        id: mtg_width
        font: root.text_font
        text: "MTG"
    }

    Rectangle {
        id: slot
        anchors.fill: parent
        radius: 3
        color: root.in_meeting ? Qt.alpha(root.accent, 0.5) : Style.frame_color
        border.width: 2
        border.color: root.in_meeting ? root.accent : Style.frame_border_color
    }

    FrameShade {
        anchors.fill: slot
        anchors.margins: 2
        bottom_radius: 1
        top_radius: 1
        visible: !root.in_meeting
    }

    Dither {
        anchors.fill: slot
        anchors.margins: 2
        radius: 1
        color: root.in_meeting ? Qt.alpha(root.accent, 0.25) : Style.dither
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.in_meeting ? "MTG" : root.minutes + "m"
        textFormat: Text.PlainText
        color: root.in_meeting ? Theme.fg_strong : root.accent
        font: root.text_font
        style: Style.bar_text_style
        styleColor: Style.bar_glow_color
    }
}

import QtQuick
import qs.ui.effects
import qs.theme

// nes: a pixel hourglass and 12M before a meeting; the same hourglass beside MTG during one.
MarkerBase {
    id: root

    readonly property int gap: 6
    readonly property color frame_color: root.on_accent ? root.ink : Style.bar_fg
    readonly property color sand_color: root.on_accent ? root.ink : Theme.theme_secondary

    implicitWidth: Math.ceil(hourglass.implicitWidth + root.gap + Math.max(digits_width.advanceWidth, mtg_width.advanceWidth))
    implicitHeight: Math.max(hourglass.implicitHeight, label.implicitHeight)

    // Sized from the widest of both states, so the minutes ticking down and a meeting starting never resize the clock.
    TextMetrics {
        id: digits_width
        font: root.text_font
        text: "00M"
    }

    TextMetrics {
        id: mtg_width
        font: root.text_font
        text: "MTG"
    }

    Row {
        spacing: root.gap
        anchors.verticalCenter: parent.verticalCenter

        PixelSprite {
            id: hourglass
            anchors.verticalCenter: parent.verticalCenter
            pixel: 1
            colors: [root.frame_color, root.sand_color]
            rows: ["000000000", ".0111110.", ".0111110.", "..01110..", "...010...", "....0....", "...010...", "..01110..", ".0111110.", ".0111110.", "000000000"]
        }

        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            width: Math.ceil(Math.max(digits_width.advanceWidth, mtg_width.advanceWidth))
            text: root.in_meeting ? "MTG" : root.minutes + "M"
            textFormat: Text.PlainText
            color: root.frame_color
            font: root.text_font
        }
    }
}

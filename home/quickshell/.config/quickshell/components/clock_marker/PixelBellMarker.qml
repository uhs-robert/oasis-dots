// home/quickshell/.config/quickshell/components/clock_marker/PixelBellMarker.qml
import QtQuick
import ".."
import "../../theme"

// gameboy: a pixel bell and 12M before a meeting; the same bell beside MTG during one.
MarkerBase {
    id: root

    readonly property int gap: 6
    // The Original has no second hue, so the bell takes the shade below the date's; the Color model takes the theme secondary.
    readonly property bool original: Style.device_model === "dmg"
    readonly property color body_color: root.on_accent ? root.ink : root.original ? Style.pixel_shades[2] : Theme.theme_secondary
    readonly property color shine_color: root.on_accent ? root.ink : Style.pixel_shades[3]
    readonly property var bell_rows: ["....0....", "...000...", "..01100..", ".0110000.", ".0110000.", "000000000", ".........", "...000..."]

    implicitWidth: Math.ceil(bell.implicitWidth + root.gap + Math.max(digits_width.advanceWidth, mtg_width.advanceWidth))
    implicitHeight: Math.max(bell.implicitHeight, label.implicitHeight)

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
            id: bell
            anchors.verticalCenter: parent.verticalCenter
            pixel: 2
            colors: [root.body_color, root.shine_color]
            rows: root.bell_rows
        }

        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            width: Math.ceil(Math.max(digits_width.advanceWidth, mtg_width.advanceWidth))
            text: root.in_meeting ? "MTG" : root.minutes + "M"
            textFormat: Text.PlainText
            color: root.body_color
            font: root.text_font
        }
    }
}

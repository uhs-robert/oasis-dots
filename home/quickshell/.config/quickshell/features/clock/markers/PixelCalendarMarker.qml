import QtQuick
import qs.ui.effects
import qs.theme
import "../../../theme/icon_sets/GameboySprites.js" as GameboySprites

// gameboy: a pixel calendar and 12M before a meeting; the same calendar beside MTG during one.
MarkerBase {
    id: root

    readonly property int gap: 6
    // The Original has no second hue, so the calendar takes the shade below the date's; the Color model takes the theme secondary.
    readonly property bool original: Style.device_model === "dmg"
    readonly property color body_color: root.on_accent ? root.ink : root.original ? Style.pixel_shades[2] : Theme.theme_secondary
    readonly property color shine_color: root.on_accent ? root.ink : Style.pixel_shades[3]
    readonly property var calendar_rows: GameboySprites.sprites.meeting.normal

    implicitWidth: Math.ceil(calendar.implicitWidth + root.gap + Math.max(digits_width.advanceWidth, mtg_width.advanceWidth))
    implicitHeight: Math.max(calendar.implicitHeight, label.implicitHeight)

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
            id: calendar
            anchors.verticalCenter: parent.verticalCenter
            pixel: 2
            colors: [root.body_color, root.shine_color]
            rows: root.calendar_rows
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

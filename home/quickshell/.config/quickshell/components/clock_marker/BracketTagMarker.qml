import QtQuick
import qs.theme

// terminal: a bracketed tag, [-12m] before a meeting and [MTG] during one.
MarkerBase {
    id: root

    implicitWidth: Math.ceil(Math.max(upcoming_width.advanceWidth, mtg_width.advanceWidth))
    implicitHeight: label.implicitHeight

    // Sized from the widest of both states, so the minutes ticking down and a meeting starting never resize the clock.
    TextMetrics {
        id: upcoming_width
        font: root.text_font
        text: "[-00m]"
    }

    TextMetrics {
        id: mtg_width
        font: root.text_font
        text: "[MTG]"
    }

    Text {
        id: label
        text: root.in_meeting ? "[MTG]" : "[-" + root.minutes + "m]"
        textFormat: Text.PlainText
        color: root.on_accent ? root.ink : Theme.theme_primary
        font: root.text_font
        style: Style.bar_text_style
        styleColor: Style.bar_glow_color
    }
}

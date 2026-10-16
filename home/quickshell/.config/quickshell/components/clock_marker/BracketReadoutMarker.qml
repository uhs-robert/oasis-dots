import QtQuick
import qs.theme

// tie: a targeting-computer readout inside the clock brackets, · T-12 before a meeting and · MTG during one.
MarkerBase {
    id: root

    implicitWidth: Math.ceil(Math.max(upcoming_width.advanceWidth, mtg_width.advanceWidth))
    implicitHeight: label.implicitHeight

    // The leading space matches the one after the dot, so the dot is as far from the date as from the countdown.
    // Sized from the widest of both states, so the minutes ticking down and a meeting starting never resize the clock.
    TextMetrics {
        id: upcoming_width
        font: root.text_font
        text: " · T-00"
    }

    TextMetrics {
        id: mtg_width
        font: root.text_font
        text: " · MTG"
    }

    Text {
        id: label
        text: root.in_meeting ? " · MTG" : " · T-" + root.minutes
        textFormat: Text.PlainText
        color: root.on_accent ? root.ink : root.in_meeting ? Style.bar_clock_brackets : Style.bar_fg
        font: root.text_font
    }
}

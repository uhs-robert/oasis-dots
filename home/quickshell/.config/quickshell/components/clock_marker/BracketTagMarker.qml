// home/quickshell/.config/quickshell/components/clock_marker/BracketTagMarker.qml
import QtQuick
import "../../theme"

// terminal: a bracketed tag, [-12m] before a meeting and a blinking [live] during one.
MarkerBase {
    id: root

    implicitWidth: Math.ceil(Math.max(upcoming_width.advanceWidth, live_width.advanceWidth))
    implicitHeight: label.implicitHeight

    // Sized from the widest of both states, so the minutes ticking down and a meeting starting never resize the clock.
    TextMetrics {
        id: upcoming_width
        font: root.text_font
        text: "[-00m]"
    }

    TextMetrics {
        id: live_width
        font: root.text_font
        text: "[live]"
    }

    Text {
        id: label
        text: root.in_meeting ? "[live]" : "[-" + root.minutes + "m]"
        textFormat: Text.PlainText
        color: root.on_accent ? root.ink : Theme.theme_primary
        font: root.text_font
        style: Style.bar_text_style
        styleColor: Style.bar_glow_color

        SequentialAnimation on opacity {
            running: root.in_meeting && root.visible
            loops: Animation.Infinite
            NumberAnimation { to: 0.3; duration: 500 }
            NumberAnimation { to: 1; duration: 500 }
            onRunningChanged: if (!running) label.opacity = 1
        }
    }
}

// home/quickshell/.config/quickshell/components/clock_marker/BracketReadoutMarker.qml
import QtQuick
import "../../theme"

// tie: a targeting-computer readout inside the clock brackets, · T-12 before a meeting and a blinking · LOCK during one.
Item {
    id: root

    // Shared marker inputs; see MeetingMarker.
    property int minutes: 0
    property bool in_meeting: false
    property real progress: 0
    property bool on_accent: false
    property color ink: "black"
    property font text_font

    implicitWidth: Math.ceil(root.in_meeting ? lock_width.advanceWidth : upcoming_width.advanceWidth)
    implicitHeight: label.implicitHeight

    // Sized from the widest countdown, so the minutes ticking down do not resize the clock.
    TextMetrics {
        id: upcoming_width
        font: root.text_font
        text: "\u00b7 T-00"
    }

    TextMetrics {
        id: lock_width
        font: root.text_font
        text: "\u00b7 LOCK"
    }

    Text {
        id: label
        text: root.in_meeting ? "\u00b7 LOCK" : "\u00b7 T-" + root.minutes
        textFormat: Text.PlainText
        color: root.on_accent ? root.ink : root.in_meeting ? Style.bar_clock_brackets : Style.bar_fg
        font: root.text_font

        SequentialAnimation on opacity {
            running: root.in_meeting && root.visible
            loops: Animation.Infinite
            NumberAnimation { to: 0.3; duration: 500 }
            NumberAnimation { to: 1; duration: 500 }
            onRunningChanged: if (!running) label.opacity = 1
        }
    }
}

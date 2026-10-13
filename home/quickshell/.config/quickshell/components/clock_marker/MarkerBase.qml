// home/quickshell/.config/quickshell/components/clock_marker/MarkerBase.qml
import QtQuick

// The inputs MeetingMarker hands every style's marker.
Item {
    // Minutes to the upcoming meeting; meaningless while in_meeting.
    property int minutes: 0
    property bool in_meeting: false
    // 0..1 through the lead-in window, 1 during a meeting.
    property real progress: 0
    // The clock sits on a strong fill; markers draw in ink.
    property bool on_accent: false
    property color ink: "black"
    property font text_font
}

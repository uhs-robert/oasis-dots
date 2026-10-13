// home/quickshell/.config/quickshell/components/clock_marker/EncounterSpriteMarker.qml
import QtQuick
import "../../theme"

// Placeholder for nes until its own marker is drawn.
Item {
    id: root

    // Shared marker inputs; see MeetingMarker.
    property int minutes: 0
    property bool in_meeting: false
    property real progress: 0
    property bool on_accent: false
    property color ink: "black"
    property font text_font

    implicitWidth: fallback.implicitWidth
    implicitHeight: fallback.implicitHeight

    DefaultMarker {
        id: fallback
        minutes: root.minutes
        in_meeting: root.in_meeting
        progress: root.progress
        on_accent: root.on_accent
        ink: root.ink
        text_font: root.text_font
    }
}

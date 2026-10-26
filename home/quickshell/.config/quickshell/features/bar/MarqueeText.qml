import QtQuick
import "MediaText.js" as MediaText

// One line of text cut to `max_chars` with an ellipsis. With `scroll` on, a cut line slides through a window as wide
// as the cut text, pausing at each end; the slide runs only while the line is visible, so a hidden well costs nothing.
Item {
    id: root

    property string full_text: ""
    property int max_chars: 24
    property bool scroll: false
    property real speed: 30
    property color color: "white"
    property font font
    property int pause_ms: 1200
    property int style: Text.Normal
    property color style_color: "transparent"

    readonly property string clipped: MediaText.clip(root.full_text, root.max_chars)
    readonly property real window_width: clipped_metrics.advanceWidth
    readonly property real overflow: Math.max(0, full_metrics.advanceWidth - root.window_width)
    readonly property var cycle: MediaText.marquee_cycle(root.overflow, root.speed, root.pause_ms)
    readonly property bool sliding: MediaText.marquee_running(root.scroll, root.visible, root.overflow)

    implicitWidth: root.window_width
    implicitHeight: label.implicitHeight
    clip: true

    TextMetrics {
        id: clipped_metrics
        font: root.font
        text: root.clipped
    }

    TextMetrics {
        id: full_metrics
        font: root.font
        text: root.full_text
    }

    Text {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        text: root.sliding ? root.full_text : root.clipped
        color: root.color
        font: root.font
        style: root.style
        styleColor: root.style_color
        textFormat: Text.PlainText
    }

    // A running animation keeps the travel it started with, so a new cycle (text or width changed) restarts it.
    onCycleChanged: if (slide.running) {
        slide.stop();
        slide.start();
    }

    SequentialAnimation {
        id: slide
        running: root.sliding
        loops: Animation.Infinite
        onRunningChanged: if (!running) label.x = 0

        PauseAnimation { duration: root.cycle.start_pause }
        NumberAnimation { target: label; property: "x"; from: 0; to: -root.overflow; duration: root.cycle.travel }
        PauseAnimation { duration: root.cycle.end_pause }
        // Jump back, never slide back: the text is always read left to right.
        PropertyAction { target: label; property: "x"; value: 0 }
    }
}

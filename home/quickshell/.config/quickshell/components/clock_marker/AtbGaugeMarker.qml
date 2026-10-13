// home/quickshell/.config/quickshell/components/clock_marker/AtbGaugeMarker.qml
import QtQuick
import "../../theme"
import ".."

// ff7: an ATB gauge filling toward the meeting beside the minutes; in a meeting it is full, reads READY and flashes like a turn that is up.
Row {
    id: root

    // Shared marker inputs; see MeetingMarker.
    property int minutes: 0
    property bool in_meeting: false
    property real progress: 0
    property bool on_accent: false
    property color ink: "black"
    property font text_font

    readonly property var st: Style.for_item(root)

    // 0 to 1; how far the flash has washed the gauge and label toward white.
    property real flash: 0

    spacing: 5

    readonly property color tone: root.on_accent ? root.ink : Theme.theme_primary_light

    // Sized from the widest label, so neither the minutes nor READY resize the clock.
    TextMetrics {
        id: upcoming_width
        font: root.text_font
        text: "00m"
    }

    TextMetrics {
        id: ready_width
        font: root.text_font
        text: "READY"
    }

    AtbBar {
        anchors.verticalCenter: parent.verticalCenter
        width: 34
        value: root.in_meeting ? 1 : root.progress
        horizontal: true
        fill_color: root.on_accent ? root.ink : Qt.tint(root.st.meter_on, Qt.alpha("white", root.flash * 0.75))
        shade_color: root.on_accent ? root.ink : Qt.tint(root.st.meter_shade, Qt.alpha("white", root.flash * 0.75))
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.ceil(Math.max(upcoming_width.advanceWidth, ready_width.advanceWidth))
        text: root.in_meeting ? "READY" : root.minutes + "m"
        textFormat: Text.PlainText
        color: root.on_accent ? root.ink : Qt.tint(root.tone, Qt.alpha("white", root.flash * 0.75))
        font: root.text_font
        style: Style.bar_text_style
        styleColor: Style.bar_glow_color
    }

    SequentialAnimation on flash {
        running: root.in_meeting && root.visible
        loops: Animation.Infinite
        NumberAnimation { to: 1; duration: 500; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0; duration: 500; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) root.flash = 0
    }
}

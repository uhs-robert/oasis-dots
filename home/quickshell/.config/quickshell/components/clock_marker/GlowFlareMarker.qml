// home/quickshell/.config/quickshell/components/clock_marker/GlowFlareMarker.qml
import QtQuick
import "../../theme"

// crt: phosphor text with a halo stronger than the bar's own glow, 12M before a meeting and a pulsing REC during one.
Item {
    id: root

    // Shared marker inputs; see MeetingMarker.
    property int minutes: 0
    property bool in_meeting: false
    property real progress: 0
    property bool on_accent: false
    property color ink: "black"
    property font text_font

    // 0..1; the halo rests at 0.45 and swells to 1 while recording.
    property real flare: 0.45

    implicitWidth: Math.ceil(root.in_meeting ? rec_width.advanceWidth : upcoming_width.advanceWidth)
    implicitHeight: label.implicitHeight

    // Sized from the widest countdown, so the minutes ticking down do not resize the clock.
    TextMetrics {
        id: upcoming_width
        font: root.text_font
        text: "00M"
    }

    TextMetrics {
        id: rec_width
        font: root.text_font
        text: "REC"
    }

    Repeater {
        model: [6, 3]

        Rectangle {
            required property int modelData
            anchors.fill: label
            anchors.margins: -modelData
            radius: height / 2
            color: Qt.alpha(root.on_accent ? root.ink : Theme.theme_primary, root.flare * (0.05 + (6 - modelData) * 0.025))
        }
    }

    Text {
        id: label
        text: root.in_meeting ? "REC" : root.minutes + "M"
        textFormat: Text.PlainText
        color: root.on_accent ? root.ink : Theme.theme_primary_light
        font.family: root.text_font.family
        font.pixelSize: root.text_font.pixelSize
        font.letterSpacing: root.text_font.letterSpacing
        font.features: { "tnum": 1 }
        font.capitalization: Font.AllUppercase
        style: Text.Outline
        styleColor: Qt.alpha(root.on_accent ? root.ink : Theme.theme_primary, 0.35 + 0.55 * root.flare)
    }

    SequentialAnimation on flare {
        running: root.in_meeting && root.visible
        loops: Animation.Infinite
        NumberAnimation { to: 1; duration: 500; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0.3; duration: 500; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) root.flare = 0.45
    }
}

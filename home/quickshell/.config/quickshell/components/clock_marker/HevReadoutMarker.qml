// home/quickshell/.config/quickshell/components/clock_marker/HevReadoutMarker.qml
import QtQuick
import "../../theme"

// halflife: an HEV readout, a dim MTG label beside the minutes in a larger numeral, and a pulsing warning dash during a meeting.
MarkerBase {
    id: root

    readonly property real label_size: Math.max(8, Style.bar_font_size - 4)
    readonly property real number_size: Style.bar_font_size + 4
    readonly property color tone: root.on_accent ? root.ink : Style.bar_fg

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    Row {
        id: row
        spacing: 4

        // Sized from the widest of both states, so the minutes ticking down and a meeting starting never resize the clock.
        TextMetrics {
            id: number_width
            font.family: root.text_font.family
            font.features: { "tnum": 1 }
            font.pixelSize: root.number_size
            text: "00"
        }

        TextMetrics {
            id: dash_width
            font.family: root.text_font.family
            font.features: { "tnum": 1 }
            font.pixelSize: root.number_size
            text: "——"
        }

        Text {
            anchors.baseline: readout.baseline
            text: "MTG"
            color: Qt.alpha(root.tone, 0.6)
            font.family: root.text_font.family
            font.features: { "tnum": 1 }
            font.pixelSize: root.label_size
            font.letterSpacing: 1.2
        }

        Text {
            id: readout
            width: Math.ceil(Math.max(number_width.advanceWidth, dash_width.advanceWidth))
            text: root.in_meeting ? "——" : String(root.minutes)
            textFormat: Text.PlainText
            color: root.in_meeting && !root.on_accent ? Theme.warning : root.tone
            font.family: root.text_font.family
            font.features: { "tnum": 1 }
            font.pixelSize: root.number_size

            SequentialAnimation on opacity {
                running: root.in_meeting && root.visible
                loops: Animation.Infinite
                NumberAnimation { to: 0.35; duration: 500; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 500; easing.type: Easing.InOutSine }
                onRunningChanged: if (!running) readout.opacity = 1
            }
        }
    }
}

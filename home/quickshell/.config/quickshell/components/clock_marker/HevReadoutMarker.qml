// home/quickshell/.config/quickshell/components/clock_marker/HevReadoutMarker.qml
import QtQuick
import "../../theme"

// halflife: an HEV readout, a dim MTG label beside the minutes in a larger numeral; during a meeting the readout itself reads MTG in the warning colour.
MarkerBase {
    id: root

    readonly property real label_size: Math.max(8, Style.bar_font_size - 4)
    readonly property real number_size: Style.bar_font_size + 4
    readonly property color tone: root.on_accent ? root.ink : Style.bar_fg

    implicitWidth: Math.ceil(Math.max(row.implicitWidth, mtg_width.advanceWidth))
    implicitHeight: row.implicitHeight

    // Sized from the wider of both states, so the minutes ticking down and a meeting starting never resize the clock.
    TextMetrics {
        id: mtg_width
        font.family: root.text_font.family
        font.features: { "tnum": 1 }
        font.pixelSize: root.number_size
        text: "MTG"
    }

    TextMetrics {
        id: number_width
        font.family: root.text_font.family
        font.features: { "tnum": 1 }
        font.pixelSize: root.number_size
        text: "00"
    }

    Row {
        id: row
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 4

        Text {
            visible: !root.in_meeting
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
            width: root.in_meeting ? Math.ceil(mtg_width.advanceWidth) : Math.ceil(number_width.advanceWidth)
            text: root.in_meeting ? "MTG" : String(root.minutes)
            textFormat: Text.PlainText
            color: root.in_meeting && !root.on_accent ? Theme.warning : root.tone
            font.family: root.text_font.family
            font.features: { "tnum": 1 }
            font.pixelSize: root.number_size
        }
    }
}

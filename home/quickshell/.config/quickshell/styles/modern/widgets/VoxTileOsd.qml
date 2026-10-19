import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.ui.gauges

// The voxtype OSD as a card: a mic tile, the phase, the elapsed time as the readout and the wave where the meter sits.
ColumnLayout {
    id: root

    property bool recording: true
    property string elapsed: "0:00"
    property string glyph: ""
    property bool running: false
    // The mic level source for the wave, supplied by the OSD so this widget stays out of features/voice.
    required property var sample
    required property real gain
    readonly property color state_color: root.recording ? Theme.theme_label : Theme.warning

    spacing: Style.px(14)
    implicitWidth: Style.px(300)

    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        AccentTile {
            glyph: root.glyph
            tint: root.state_color
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 1

            Text {
                text: root.recording ? "Recording" : "Transcribing"
                color: Style.text_strong
                font.family: Style.font_family
                font.pixelSize: Style.fs(-1)
                font.weight: Font.DemiBold
            }

            Text {
                text: "Voxtype"
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
            }
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: root.elapsed
            color: root.recording ? Style.text_strong : root.state_color
            font.family: Style.number_font
            font.pixelSize: Style.fs(20)
            font.weight: Font.Medium
            font.letterSpacing: -1.5
            font.features: { "tnum": 1 }
        }
    }

    Waveform {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.px(36)
        frozen: !root.recording
        running: root.running
        sample: root.sample
        gain: root.gain
    }
}

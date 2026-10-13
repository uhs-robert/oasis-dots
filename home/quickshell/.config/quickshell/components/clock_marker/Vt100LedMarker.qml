// home/quickshell/.config/quickshell/components/clock_marker/Vt100LedMarker.qml
import QtQuick
import "../../theme"

// crt: a VT100 keyboard lamp and "L1 12M" before a meeting; the lamp lit beside "L1 MTG" during one.
MarkerBase {
    id: root

    readonly property color phosphor: root.on_accent ? root.ink : Theme.theme_primary
    readonly property color lit_color: root.on_accent ? root.ink : Theme.theme_primary_light

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    // Sized from the widest of both states, so the minutes ticking down and a meeting starting never resize the clock.
    TextMetrics {
        id: upcoming_width
        font: root.text_font
        text: "L1 00M"
    }

    TextMetrics {
        id: mtg_width
        font: root.text_font
        text: "L1 MTG"
    }

    Row {
        id: row
        spacing: 6

        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: lamp.width
            height: lamp.height

            Rectangle {
                visible: root.in_meeting
                anchors.fill: lamp
                anchors.margins: -3
                radius: 3
                color: Qt.alpha(root.phosphor, 0.35)
            }

            Rectangle {
                id: lamp
                width: Math.round(root.text_font.pixelSize * 0.6)
                height: Math.round(root.text_font.pixelSize * 0.4)
                radius: 1
                color: root.in_meeting ? root.lit_color : Qt.alpha(root.phosphor, 0.3)
                border.width: 1
                border.color: root.in_meeting ? root.lit_color : Qt.alpha(root.phosphor, 0.9)
            }
        }

        Text {
            width: Math.ceil(Math.max(upcoming_width.advanceWidth, mtg_width.advanceWidth))
            anchors.verticalCenter: parent.verticalCenter
            text: root.in_meeting ? "L1 MTG" : "L1 " + root.minutes + "M"
            textFormat: Text.PlainText
            color: root.lit_color
            font.family: root.text_font.family
            font.pixelSize: root.text_font.pixelSize
            font.letterSpacing: root.text_font.letterSpacing
            font.features: { "tnum": 1 }
            font.capitalization: Font.AllUppercase
            style: Text.Outline
            styleColor: Qt.alpha(root.phosphor, 0.35)
        }
    }
}

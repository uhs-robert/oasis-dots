// home/quickshell/.config/quickshell/components/clock_marker/EnergyTanksMarker.qml
import QtQuick
import "../../theme"

// metroid: energy tanks that empty as the meeting nears, beside a two-digit ENERGY readout; in a meeting the tanks are empty and the readout reads MTG in the warning colour.
MarkerBase {
    id: root

    readonly property int tank_count: 4
    readonly property int full_tanks: root.in_meeting ? 0 : Math.ceil((1 - root.progress) * root.tank_count - 0.001)
    readonly property color tank_color: root.on_accent ? root.ink : Theme.theme_secondary
    readonly property color alarm_color: root.on_accent ? root.ink : Theme.warning
    // Low-energy tint, held for the whole meeting.
    readonly property real warn_mix: root.in_meeting ? 1 : 0

    implicitWidth: layout.implicitWidth
    implicitHeight: layout.implicitHeight

    // Sized from the wider of two digits and MTG, so the minutes ticking down and a meeting starting never resize the clock.
    TextMetrics {
        id: digits_width
        font: root.text_font
        text: "00"
    }

    TextMetrics {
        id: mtg_width
        font: root.text_font
        text: "MTG"
    }

    Row {
        id: layout
        anchors.verticalCenter: parent.verticalCenter
        spacing: 5

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Repeater {
                model: root.tank_count

                Rectangle {
                    required property int index
                    readonly property bool full: index < root.full_tanks
                    width: 6
                    height: 8
                    radius: 1
                    color: full ? root.tank_color : "transparent"
                    border.width: 1
                    border.color: full ? root.tank_color : Qt.tint(Qt.alpha(root.tank_color, 0.55), Qt.alpha(root.alarm_color, root.warn_mix))
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.ceil(Math.max(digits_width.advanceWidth, mtg_width.advanceWidth))
            text: root.in_meeting ? "MTG" : String(Math.min(99, root.minutes)).padStart(2, "0")
            textFormat: Text.PlainText
            color: Qt.tint(root.on_accent ? root.ink : Style.bar_fg, Qt.alpha(root.alarm_color, root.warn_mix))
            font: root.text_font
            style: Style.bar_text_style
            styleColor: Style.bar_glow_color
        }
    }
}

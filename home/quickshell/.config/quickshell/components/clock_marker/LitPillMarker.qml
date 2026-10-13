// home/quickshell/.config/quickshell/components/clock_marker/LitPillMarker.qml
import QtQuick
import "../../theme"

// ps2: the lit selection pill of the menus around the minutes, reading MTG during a meeting.
MarkerBase {
    id: root

    implicitWidth: Math.ceil(Math.max(upcoming_width.advanceWidth, mtg_width.advanceWidth)) + 16
    implicitHeight: label.implicitHeight + 4

    // Sized from the widest of both states, so the minutes ticking down and a meeting starting never resize the clock.
    TextMetrics {
        id: upcoming_width
        font: root.text_font
        text: "00m"
    }

    TextMetrics {
        id: mtg_width
        font: root.text_font
        text: "MTG"
    }

    Repeater {
        model: [2, 4, 6]

        Rectangle {
            required property int modelData
            anchors.fill: pill
            anchors.margins: -modelData
            radius: height / 2
            color: Qt.alpha(Style.selection_glow, Style.selection_glow.a * (0.5 - modelData * 0.06))
        }
    }

    Rectangle {
        id: pill
        anchors.fill: parent
        radius: height / 2
        color: Style.selection_bg
        border.width: 1
        border.color: Style.selection_border
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.in_meeting ? "MTG" : root.minutes + "m"
        textFormat: Text.PlainText
        color: Theme.fg_strong
        font: root.text_font
    }
}

import QtQuick
import "../../theme"
import ".."

// ff7: an ATB gauge filling toward the meeting beside the minutes; in a meeting it is full and the label reads MTG.
MarkerBase {
    id: root

    readonly property var st: Style.for_item(root)

    implicitWidth: layout.implicitWidth
    implicitHeight: layout.implicitHeight

    readonly property color tone: root.on_accent ? root.ink : Theme.theme_primary_light

    // Sized from the widest label, so neither the minutes nor MTG resize the clock.
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

    Row {
        id: layout
        anchors.verticalCenter: parent.verticalCenter
        spacing: 5

        AtbBar {
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            value: root.in_meeting ? 1 : root.progress
            horizontal: true
            fill_color: root.on_accent ? root.ink : root.st.meter_on
            shade_color: root.on_accent ? root.ink : root.st.meter_shade
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.ceil(Math.max(upcoming_width.advanceWidth, mtg_width.advanceWidth))
            text: root.in_meeting ? "MTG" : root.minutes + "m"
            textFormat: Text.PlainText
            color: root.on_accent ? root.ink : root.tone
            font: root.text_font
            style: Style.bar_text_style
            styleColor: Style.bar_glow_color
        }
    }
}

import QtQuick
import qs.theme

// A hollow dot and the minutes before a meeting, a solid dot during one.
MarkerBase {
    id: root

    readonly property color tone: root.on_accent ? root.ink : Theme.theme_primary

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    Row {
        id: row
        spacing: 6

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 6
            height: 6
            radius: 3
            color: root.in_meeting ? root.tone : "transparent"
            border.width: 1
            border.color: root.tone
        }

        // Sized from the widest countdown, so the minutes ticking down do not resize the clock.
        TextMetrics {
            id: widest
            font.family: Style.bar_font_family
            font.pixelSize: Style.bar_font_size
            font.letterSpacing: Style.bar_letter_spacing
            font.capitalization: Style.bar_capitalization
            text: "00m"
        }

        Text {
            visible: !root.in_meeting
            anchors.verticalCenter: parent.verticalCenter
            width: Math.ceil(widest.advanceWidth)
            text: root.minutes + "m"
            textFormat: Text.PlainText
            color: root.tone
            font.family: Style.bar_font_family
            font.features: { "tnum": 1 }
            style: Style.bar_text_style
            styleColor: Style.bar_glow_color
            font.pixelSize: Style.bar_font_size
            font.capitalization: Style.bar_capitalization
            font.letterSpacing: Style.bar_letter_spacing
        }
    }
}

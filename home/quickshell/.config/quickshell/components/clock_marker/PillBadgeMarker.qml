import QtQuick
import "../../theme"

// modern: a small primary pill after the date, tinted with 12m before a meeting and solid with a dot and MTG during one.
MarkerBase {
    id: root

    readonly property real pad: 8
    readonly property real dot: 6
    readonly property color accent: root.on_accent ? root.ink : Theme.theme_primary
    // Text and dot on the solid in-meeting fill.
    readonly property color on_fill: root.on_accent ? Theme.theme_primary : root.ink

    implicitWidth: Math.ceil(Math.max(upcoming_width.advanceWidth, mtg_width.advanceWidth + root.dot + 4)) + root.pad * 2
    implicitHeight: label.implicitHeight + 4

    // Sized from the widest of both states, so the minutes ticking down do not resize the clock.
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

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.in_meeting ? root.accent : Qt.alpha(root.accent, 0.16)
        border.width: 1
        border.color: root.in_meeting ? root.accent : Qt.alpha(root.accent, 0.4)
    }

    Row {
        anchors.centerIn: parent
        spacing: 4

        Rectangle {
            visible: root.in_meeting
            anchors.verticalCenter: parent.verticalCenter
            width: root.dot
            height: root.dot
            radius: root.dot / 2
            color: root.on_fill
        }

        Text {
            id: label
            text: root.in_meeting ? "MTG" : root.minutes + "m"
            textFormat: Text.PlainText
            color: root.in_meeting ? root.on_fill : root.accent
            font: root.text_font
        }
    }
}

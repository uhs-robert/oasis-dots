// home/quickshell/.config/quickshell/components/clock_marker/ReserveBoxMarker.qml
import QtQuick
import "../snes"
import "../../theme"

// snes: Super Mario World's item reserve box, a small inset window holding "12M" before a meeting and "MTG" with its border lit during one.
MarkerBase {
    id: root

    readonly property int pad_x: 6
    readonly property int pad_y: 2

    implicitWidth: Math.ceil(Math.max(upcoming_width.advanceWidth, mtg_width.advanceWidth)) + root.pad_x * 2 + 4
    implicitHeight: label.implicitHeight + root.pad_y * 2 + 4

    // Sized from the widest of both states, so the minutes ticking down and a meeting starting never resize the clock.
    TextMetrics {
        id: upcoming_width
        font: root.text_font
        text: "00M"
    }

    TextMetrics {
        id: mtg_width
        font: root.text_font
        text: "MTG"
    }

    SnesWindow {
        visible: !root.on_accent
        anchors.fill: parent
        drop: 0
        radius: 3
        lit: root.in_meeting
    }

    Rectangle {
        visible: root.on_accent
        anchors.fill: parent
        radius: 3
        color: "transparent"
        border.width: 2
        border.color: root.ink
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.in_meeting ? "MTG" : root.minutes + "M"
        textFormat: Text.PlainText
        color: root.on_accent ? root.ink : Theme.theme_secondary
        font: root.text_font
    }
}
